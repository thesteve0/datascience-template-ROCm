# Production Deployment Guide

This guide covers deploying workloads developed in this devcontainer template to Kubernetes production environments. It addresses the unique constraints of NVIDIA GPU containers and the three-layer dependency protection system that must be preserved in production.

---

## Table of Contents

1. [The Core Problem](#1-the-core-problem)
2. [The Right Architecture: Separate Dockerfile.prod](#2-the-right-architecture-separate-dockerfileprod)
3. [Scenario A: PyTorch Training Job](#3-scenario-a-pytorch-training-job-kubernetes-job)
4. [Scenario B: LLM Inference API](#4-scenario-b-llm-inference-api-kubernetes-deployment)
5. [Model Management](#5-model-management)
6. [Dependency Installation at Build Time](#6-dependency-installation-at-build-time)
7. [Graduation Workflow](#7-graduation-workflow-step-by-step)

---

## 1. The Core Problem

### The NVIDIA base image is non-negotiable

The `nvcr.io/nvidia/pytorch:26.02-py3` base image is approximately 20GB. It ships with 200+ Python packages pre-installed into `/usr/local/lib/python3.12/dist-packages` — including CUDA-optimized builds of torch, numpy, flash-attn, and many others. These builds are compiled against specific CUDA versions and cannot be replaced with generic PyPI builds without losing GPU support or performance.

You cannot downsize to a smaller base image. Any image that runs your PyTorch workload needs CUDA drivers, cuDNN, and the NVIDIA-optimized Python packages — that means starting from the NVIDIA base.

### The devcontainer adds dev-only layers

The devcontainer environment includes tools and configuration that do not belong in production:

| Dev-only item | Why excluded from prod |
|---|---|
| `ruff`, `pre-commit` | Linting/formatting tools; no runtime value |
| VSCode and JetBrains extensions | IDE integration; irrelevant to a container |
| `.idea/`, `.vscode/` config | Editor state; not part of the application |
| `iterate-test-jetbrains-env.sh` | Development iteration helper |
| Test scripts, documentation | Not needed at inference or training time |
| `uv.lock` generation for IDE | JetBrains-specific; production uses `uv sync` |

### The three-layer protection system must be preserved

The devcontainer's `setup-environment.sh` implements a three-layer system to prevent uv from overwriting NVIDIA's optimized packages. **All three layers must be replicated in production:**

1. **`.venv` with `--system-site-packages`** — makes NVIDIA's `dist-packages/` visible to the venv Python interpreter
2. **`.pth` bridge** (`_nvidia_bridge.pth`) — adds `/usr/local/lib/python3.12/dist-packages` to the Python path so imports resolve to NVIDIA's builds
3. **Stub `.dist-info` entries** — one per NVIDIA package, copied into the venv's `site-packages/`; uv reads `METADATA` from these stubs and treats NVIDIA packages as already satisfied, skipping reinstallation

Without these layers, `uv sync` will detect an empty venv and reinstall torch, numpy, and 200+ other packages with generic PyPI builds. GPU performance will degrade or PyTorch will run on CPU only.

### Why multi-stage builds don't help

Multi-stage Docker builds are normally used to shrink image size by copying build artifacts from a builder stage into a minimal runtime stage. That pattern breaks here: CUDA libraries, kernel modules, and NVIDIA's Python packages are deeply intertwined with the base OS. You cannot `COPY --from=builder /usr/local/lib/python3.12/dist-packages .` into an Alpine or slim-python image and expect CUDA to work. Both the build stage and the runtime stage need the same NVIDIA base image, so multi-stage builds provide no size benefit.

---

## 2. The Right Architecture: Separate `Dockerfile.prod`

The correct approach is a single-stage `Dockerfile.prod` that:

- Starts from the same NVIDIA base image
- Runs a stripped-down version of `setup-environment.sh` (three-layer NVIDIA setup only, no dev tools)
- Copies only application source files
- Installs only application dependencies via `uv sync --no-dev`
- Runs as a non-root `appuser` (production security requirement)

### Option A vs Option B for environment setup

**Option A (recommended): `PRODUCTION=1` guard in `setup-environment.sh`**

Add an environment variable guard to the existing `setup-environment.sh`. A single script means no risk of the production setup drifting out of sync with the devcontainer setup. Both environments share the same three-layer NVIDIA logic.

```bash
# In setup-environment.sh, wrap dev-only sections:
if [ "${PRODUCTION:-0}" != "1" ]; then
    echo "Installing development tools (ruff, pre-commit)..."
    uv pip install --python ${WORKSPACE_DIR}/.venv/bin/python ruff pre-commit
fi

if [ "${PRODUCTION:-0}" != "1" ]; then
    echo "Generating uv.lock for IDE integration..."
    uv lock --project ${WORKSPACE_DIR}
fi

if [ "${PRODUCTION:-0}" != "1" ]; then
    echo "Configuring git identity..."
    git config --global user.name "{{GIT_NAME}}"
    git config --global user.email "{{GIT_EMAIL}}"
    git config --global init.defaultBranch main
fi
```

**Option B: Separate `production/setup-prod-env.sh`**

Copy only the three-layer NVIDIA setup logic into a separate script. Cleaner separation, but creates two scripts that implement the same core logic — any change to the NVIDIA protection mechanism must be applied in both places.

### `Dockerfile.prod`

```dockerfile
FROM nvcr.io/nvidia/pytorch:26.02-py3

# Workaround for Ubuntu 24.04 having pre-existing ubuntu user at UID 1000.
# Without this, subsequent user creation fails or gets bumped to UID 1001.
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu

# Create a non-root application user.
# Production containers should never run as root.
# UID 1000 is now free after the ubuntu user deletion above.
RUN groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home appuser

# Application working directory
WORKDIR /app

# Copy dependency files first (Docker layer caching: these change less often than src/)
COPY pyproject.toml uv.lock ./

# Copy the NVIDIA-provided package list (generated at devcontainer startup)
# and the setup script that creates the three-layer protection system.
COPY nvidia-provided.txt ./
COPY .devcontainer/setup-environment.sh ./setup-environment.sh

# Run the stripped-down environment setup.
# PRODUCTION=1 skips: ruff, pre-commit, git config, uv.lock generation, ownership fixup.
# This creates:
#   1. /app/.venv with --system-site-packages
#   2. _nvidia_bridge.pth pointing to NVIDIA's dist-packages
#   3. Stub .dist-info entries for all NVIDIA packages
#   4. constraint-dependencies injected into pyproject.toml
RUN PRODUCTION=1 WORKSPACE_DIR=/app bash ./setup-environment.sh

# Install only production application dependencies.
# uv sees NVIDIA stubs as satisfied and installs only new packages into .venv.
# --no-dev skips dev dependency groups (ruff, etc.) if defined in pyproject.toml.
RUN /app/.venv/bin/uv sync --no-dev --project /app

# Copy application source code.
# Done after dependency installation so source changes don't invalidate the dep cache layer.
COPY src/ ./src/

# Environment variables carried over from devcontainer for runtime consistency.
# These match containerEnv in devcontainer.json.
ENV PYTHONPATH=/app/src \
    HF_HOME=/app/.cache/huggingface \
    TORCH_HOME=/app/.cache/torch \
    TRANSFORMERS_CACHE=/app/.cache/huggingface/transformers \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:512,garbage_collection_threshold:0.6 \
    NVIDIA_VISIBLE_DEVICES=all \
    UV_PROJECT_ENVIRONMENT=/app/.venv

# GPU runtime requirements for NVIDIA container runtime
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# Switch to non-root user for runtime
USER appuser

# Default command — override in Kubernetes pod spec or docker run
CMD ["/app/.venv/bin/python", "-m", "your_project.main"]
```

### Verification after build

```bash
# Build the production image
docker build -f Dockerfile.prod -t myproject:prod .

# Verify NVIDIA packages are NOT overwritten — numpy must point to dist-packages
docker run --rm --gpus all myproject:prod \
    python -c "import numpy; print(numpy.__file__)"
# Expected: /usr/local/lib/python3.12/dist-packages/numpy/__init__.py
# WRONG if you see: /app/.venv/lib/python3.12/site-packages/numpy/__init__.py

# Verify GPU access
docker run --rm --gpus all myproject:prod \
    python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, device: {torch.cuda.get_device_name(0)}')"

# Verify the container runs as non-root
docker run --rm myproject:prod id
# Expected: uid=1000(appuser) gid=1000(appuser)
```

---

## 3. Scenario A: PyTorch Training Job (Kubernetes Job)

### When to use

Use a Kubernetes `Job` for:
- Batch model training runs
- Fine-tuning on a fixed dataset
- Evaluation / benchmark runs
- One-shot preprocessing pipelines

Jobs run to completion and terminate. They are not suitable for continuous serving.

### Storage layout

| Mount path | PVC access mode | Contents |
|---|---|---|
| `/data` | ReadOnlyMany | Training dataset (pre-populated) |
| `/checkpoints` | ReadWriteOnce | Model checkpoints written during training |
| `/models` | ReadWriteMany | Base model weights, shared across jobs |

### `training-job.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: finetune-llama-run1
  namespace: ml-training
spec:
  # For single-node training, completions=1 parallelism=1 (defaults).
  # For multi-node DDP, set completions=N parallelism=N (see multi-node section below).
  completions: 1
  parallelism: 1

  # Retry policy: 0 means fail immediately on error (recommended for training jobs
  # where resuming from scratch wastes GPU time — use checkpoint-based resumption instead).
  backoffLimit: 0

  template:
    spec:
      restartPolicy: Never  # Job controller handles retries via backoffLimit

      containers:
      - name: trainer
        image: registry.example.com/myproject:a72770e  # Use git SHA tags, not :latest
        imagePullPolicy: Always

        command: ["/app/.venv/bin/python", "-m", "your_project.train"]
        args:
        - "--config=/app/configs/train.yaml"
        - "--output-dir=/checkpoints/run1"
        - "--data-dir=/data"

        resources:
          requests:
            memory: "20Gi"
            cpu: "8"
            nvidia.com/gpu: "1"      # Request exactly as many GPUs as the job needs
          limits:
            memory: "20Gi"
            cpu: "8"
            nvidia.com/gpu: "1"      # limits must equal requests for GPU resources

        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTORCH_CUDA_ALLOC_CONF
          value: "expandable_segments:True,max_split_size_mb:512,garbage_collection_threshold:0.6"
        - name: HF_HOME
          value: "/models/.cache/huggingface"
        - name: TORCH_HOME
          value: "/models/.cache/torch"
        # HuggingFace token for gated model access (stored as a Secret)
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-credentials
              key: token

        volumeMounts:
        - name: training-data
          mountPath: /data
          readOnly: true
        - name: checkpoints
          mountPath: /checkpoints
        - name: model-weights
          mountPath: /models
        # Shared memory for DataLoader multiprocessing workers.
        # Without this, DataLoader workers using num_workers>0 will crash
        # with "too many open files" or shared memory errors.
        - name: dshm
          mountPath: /dev/shm

      volumes:
      - name: training-data
        persistentVolumeClaim:
          claimName: training-dataset-pvc
      - name: checkpoints
        persistentVolumeClaim:
          claimName: checkpoint-storage-pvc
      - name: model-weights
        persistentVolumeClaim:
          claimName: model-weights-pvc
      # emptyDir with medium: Memory creates a tmpfs — this is the correct way
      # to provide adequate /dev/shm for PyTorch DataLoader workers in Kubernetes.
      # Default /dev/shm in containers is 64MB; DataLoader workers need much more.
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: "8Gi"  # Tune to num_workers * batch_size * tensor_size

      # Node selection: ensure the pod lands on a GPU node
      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"

      nodeSelector:
        accelerator: nvidia-gpu  # Match your cluster's GPU node label

      # Or use nodeAffinity for more expressive rules:
      # affinity:
      #   nodeAffinity:
      #     requiredDuringSchedulingIgnoredDuringExecution:
      #       nodeSelectorTerms:
      #       - matchExpressions:
      #         - key: nvidia.com/gpu.product
      #           operator: In
      #           values: ["NVIDIA-A100-SXM4-80GB", "NVIDIA-H100-80GB-HBM3"]
```

### Multi-node DDP (Distributed Data Parallel)

For training that spans multiple nodes, Kubernetes `IndexedJob` assigns each pod a stable index via `JOB_COMPLETION_INDEX`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: finetune-llama-4node
spec:
  completionMode: Indexed   # Assigns JOB_COMPLETION_INDEX (0..N-1) to each pod
  completions: 4            # Total number of nodes
  parallelism: 4            # Run all nodes simultaneously

  template:
    spec:
      subdomain: ddp-workers   # Must match the headless Service name below

      containers:
      - name: trainer
        image: registry.example.com/myproject:a72770e
        command: ["/app/.venv/bin/python", "-m", "torch.distributed.run"]
        args:
        - "--nnodes=4"
        - "--nproc-per-node=1"                    # GPUs per node
        - "--rdzv-backend=c10d"
        - "--rdzv-endpoint=ddp-workers-0.ddp-workers:29500"  # Pod 0 is the rendezvous master
        - "your_project/train.py"
        env:
        - name: RANK
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
        # ... (same resources, volumes as single-node example)

---
# Headless Service gives each pod a stable DNS name:
# ddp-workers-{index}.ddp-workers.{namespace}.svc.cluster.local
apiVersion: v1
kind: Service
metadata:
  name: ddp-workers
spec:
  clusterIP: None   # Headless — no load balancing, just DNS
  selector:
    job-name: finetune-llama-4node
  ports:
  - port: 29500
    name: rdzv
```

---

## 4. Scenario B: LLM Inference API (Kubernetes Deployment)

### When to use

Use a Kubernetes `Deployment` for:
- Continuous model serving (HTTP API)
- Online inference endpoints
- Long-running GPU workloads that must handle traffic

### Application structure

The key design constraints for GPU inference APIs:

1. **Model loading takes minutes** — health/readiness probes must not assume the model is loaded
2. **Inference blocks** — GPU calls must run in a thread pool to avoid blocking the FastAPI event loop during probe checks
3. **GPU is exclusive** — only one model can typically be loaded; use `Recreate` strategy

#### `api.py`

```python
"""LLM Inference API with correct health/readiness probe design."""
from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from enum import Enum
from concurrent.futures import ThreadPoolExecutor
from typing import Optional

import torch
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel


class ServiceState(Enum):
    STARTING = "starting"
    LOADING_MODEL = "loading_model"
    WARMING_UP = "warming_up"
    READY = "ready"
    FAILED = "failed"


@dataclass
class AppState:
    state: ServiceState = ServiceState.STARTING
    model: Optional[object] = None
    tokenizer: Optional[object] = None
    error: Optional[str] = None
    executor: ThreadPoolExecutor = field(default_factory=lambda: ThreadPoolExecutor(max_workers=1))


app_state = AppState()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load model at startup, clean up at shutdown."""
    loop = asyncio.get_event_loop()

    def load_model():
        """Runs in thread pool — keeps event loop free for probe checks during loading."""
        try:
            app_state.state = ServiceState.LOADING_MODEL
            # Replace with your actual model loading code:
            from transformers import AutoModelForCausalLM, AutoTokenizer
            model_path = "/models/your-model"
            app_state.tokenizer = AutoTokenizer.from_pretrained(model_path)
            app_state.model = AutoModelForCausalLM.from_pretrained(
                model_path,
                torch_dtype=torch.bfloat16,
                device_map="cuda",
            )

            app_state.state = ServiceState.WARMING_UP
            # Warmup pass to pre-allocate CUDA memory and compile kernels
            inputs = app_state.tokenizer("Hello", return_tensors="pt").to("cuda")
            with torch.no_grad():
                app_state.model.generate(**inputs, max_new_tokens=10)

            app_state.state = ServiceState.READY
        except Exception as e:
            app_state.state = ServiceState.FAILED
            app_state.error = str(e)
            raise

    # Start model loading in background thread — does not block the event loop
    loop.run_in_executor(app_state.executor, load_model)

    yield  # Application runs here

    # Shutdown cleanup
    app_state.executor.shutdown(wait=False)
    if app_state.model is not None:
        del app_state.model
        torch.cuda.empty_cache()


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health():
    """
    Liveness probe — returns 200 in all states except FAILED.

    Kubernetes liveness: if this returns non-200, the pod is restarted.
    During model loading (which can take minutes), we MUST return 200 here
    or Kubernetes will restart the pod in an infinite loop before it ever loads.
    Only return 503 if we know we're in a permanent failure state.
    """
    if app_state.state == ServiceState.FAILED:
        raise HTTPException(status_code=503, detail=app_state.error)
    return {"status": "alive", "state": app_state.state.value}


@app.get("/ready")
async def ready():
    """
    Readiness probe — returns 200 only when READY, 503 otherwise.

    Kubernetes readiness: if this returns non-200, the pod is removed from
    the Service's endpoint list (no traffic sent to it). During model loading,
    return 503 so the load balancer keeps the pod out of rotation.
    """
    if app_state.state != ServiceState.READY:
        raise HTTPException(
            status_code=503,
            detail=f"Not ready: {app_state.state.value}"
        )
    return {"status": "ready"}


class GenerateRequest(BaseModel):
    prompt: str
    max_new_tokens: int = 256
    temperature: float = 0.7


class GenerateResponse(BaseModel):
    text: str
    tokens_generated: int


@app.post("/generate", response_model=GenerateResponse)
async def generate(request: GenerateRequest):
    """Run inference in thread pool to avoid blocking the event loop."""
    if app_state.state != ServiceState.READY:
        raise HTTPException(status_code=503, detail=f"Service not ready: {app_state.state.value}")

    loop = asyncio.get_event_loop()

    def _run_inference():
        inputs = app_state.tokenizer(
            request.prompt, return_tensors="pt"
        ).to("cuda")
        with torch.no_grad():
            outputs = app_state.model.generate(
                **inputs,
                max_new_tokens=request.max_new_tokens,
                temperature=request.temperature,
                do_sample=request.temperature > 0,
            )
        generated = outputs[0][inputs["input_ids"].shape[1]:]
        text = app_state.tokenizer.decode(generated, skip_special_tokens=True)
        return text, len(generated)

    text, token_count = await loop.run_in_executor(app_state.executor, _run_inference)
    return GenerateResponse(text=text, tokens_generated=token_count)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
```

### `inference-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: llm-inference-api
  namespace: ml-serving
spec:
  replicas: 1

  # CRITICAL: Use Recreate, not RollingUpdate.
  # RollingUpdate spins up a new pod BEFORE terminating the old one.
  # During rollout, you'd need 2x GPU quota simultaneously.
  # In single-GPU environments (or when GPU quota is tight), this causes
  # the new pod to pend indefinitely waiting for a GPU that the old pod holds.
  # Recreate terminates the old pod first, then starts the new one.
  strategy:
    type: Recreate

  selector:
    matchLabels:
      app: llm-inference-api

  template:
    metadata:
      labels:
        app: llm-inference-api
    spec:
      containers:
      - name: api
        image: registry.example.com/myproject:a72770e
        command: ["/app/.venv/bin/python", "-m", "your_project.api"]

        ports:
        - containerPort: 8080
          name: http

        resources:
          requests:
            memory: "20Gi"
            cpu: "4"
            nvidia.com/gpu: "1"
          limits:
            memory: "20Gi"
            cpu: "4"
            nvidia.com/gpu: "1"

        env:
        - name: CUDA_VISIBLE_DEVICES
          value: "0"
        - name: PYTORCH_CUDA_ALLOC_CONF
          value: "expandable_segments:True,max_split_size_mb:512,garbage_collection_threshold:0.6"
        - name: HF_HOME
          value: "/models/.cache/huggingface"
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-credentials
              key: token

        volumeMounts:
        - name: model-weights
          mountPath: /models
          readOnly: true
        - name: dshm
          mountPath: /dev/shm

        # Startup probe: allows up to 5 minutes (30 failures * 10s period) for
        # model loading before liveness kicks in. Without this, liveness would
        # restart the pod during the multi-minute model load.
        startupProbe:
          httpGet:
            path: /health
            port: 8080
          failureThreshold: 30   # 30 * 10s = 5 minutes max startup time
          periodSeconds: 10

        # Liveness probe: once startup probe passes, check every 30s.
        # /health returns 503 only in FAILED state, so a crashed model
        # triggers a restart without interrupting a healthy loading sequence.
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 0  # Startup probe handles the initial window
          periodSeconds: 30
          failureThreshold: 3

        # Readiness probe: controls load balancer membership.
        # Returns 503 until ServiceState == READY. Pod stays out of rotation
        # during model loading and warmup.
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
          failureThreshold: 1    # Remove from rotation immediately if not ready

      volumes:
      - name: model-weights
        persistentVolumeClaim:
          claimName: model-weights-pvc
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: "4Gi"

      tolerations:
      - key: "nvidia.com/gpu"
        operator: "Exists"
        effect: "NoSchedule"

      nodeSelector:
        accelerator: nvidia-gpu

---
apiVersion: v1
kind: Service
metadata:
  name: llm-inference-api
  namespace: ml-serving
spec:
  selector:
    app: llm-inference-api
  ports:
  - name: http
    port: 80
    targetPort: 8080
  type: ClusterIP  # Use LoadBalancer or Ingress for external access
```

### Health check probe interactions — summary

| Probe | Endpoint | Returns 200 when | Returns 503 when | Effect of 503 |
|---|---|---|---|---|
| `startupProbe` | `/health` | Any state except FAILED | FAILED | Pod restart |
| `livenessProbe` | `/health` | Any state except FAILED | FAILED | Pod restart |
| `readinessProbe` | `/ready` | READY only | Any other state | Removed from Service endpoints |

The `startupProbe` and `livenessProbe` share `/health` intentionally: during the multi-minute model load, liveness must not restart the pod. Only a terminal FAILED state should trigger a restart.

---

## 5. Model Management

### Do not bake models into the image

Do not add model weights to the Docker image. For a 7B parameter model in fp16, the weights alone are ~14GB — added to the 20GB NVIDIA base, the image exceeds 34GB. This defeats Docker layer caching (weights change independently of code), makes pushes/pulls extremely slow, and conflates two independent versioning concerns (code version vs. model version).

### Recommended pattern: PVC-backed model storage

Pre-populate a PersistentVolumeClaim with model weights using a one-time downloader Job. The inference Deployment then mounts the PVC read-only.

#### PVC sizing guidance

| Model size | fp16 weights | Recommended PVC size |
|---|---|---|
| 8B parameters | ~16GB | 50GB (includes KV cache overhead, tokenizer, config) |
| 13B parameters | ~26GB | 80GB |
| 34B parameters | ~68GB | 150GB |
| 70B parameters | ~140GB | 200GB |

Multi-replica Deployments (if GPU quota permits) require `ReadWriteMany` access mode — check that your storage class supports it (NFS, CephFS, or cloud-provider equivalents).

#### `model-downloader-job.yaml`

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: download-llama-weights
  namespace: ml-serving
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: downloader
        # Use a minimal image for the download job — no GPU needed
        image: python:3.12-slim
        command: ["bash", "-c"]
        args:
        - |
          pip install -q huggingface_hub
          python -c "
          from huggingface_hub import snapshot_download
          snapshot_download(
              repo_id='meta-llama/Llama-3.1-8B-Instruct',
              local_dir='/models/Llama-3.1-8B-Instruct',
              token='$(HF_TOKEN)',
          )
          print('Download complete')
          "
        env:
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: huggingface-credentials
              key: token
        resources:
          requests:
            memory: "4Gi"
            cpu: "2"
          limits:
            memory: "8Gi"
            cpu: "4"
        volumeMounts:
        - name: model-weights
          mountPath: /models
      volumes:
      - name: model-weights
        persistentVolumeClaim:
          claimName: model-weights-pvc
```

#### HuggingFace token as a Kubernetes Secret

```bash
kubectl create secret generic huggingface-credentials \
  --from-literal=token=hf_your_token_here \
  --namespace ml-serving
```

### Runtime fallback to HuggingFace Hub

Acceptable for staging environments where model weights are not pre-loaded. Set `HF_HOME` to a writable path and provide `HF_TOKEN`. The first request triggers a download; subsequent requests use the cache. **Not recommended for production**: adds minutes of latency to pod startup and depends on external network access.

---

## 6. Dependency Installation at Build Time

This section explains how the devcontainer's dependency resolution flows correctly into the production image.

### The flow

```
Devcontainer startup
  └── setup-environment.sh
        ├── Generates nvidia-provided.txt (NVIDIA's exact package versions)
        ├── Injects constraint-dependencies into pyproject.toml
        └── Runs `uv lock` (writes uv.lock)

Developer adds packages
  └── uv add transformers accelerate
        ├── uv resolves against constraints (never upgrades NVIDIA packages)
        └── Updates uv.lock

Developer commits
  └── git commit pyproject.toml uv.lock nvidia-provided.txt

Production Docker build (Dockerfile.prod)
  ├── COPY pyproject.toml uv.lock nvidia-provided.txt
  ├── RUN bash setup-environment.sh  (PRODUCTION=1)
  │     ├── Creates .venv with --system-site-packages
  │     ├── Creates .pth bridge
  │     ├── Creates stub .dist-info entries
  │     └── Injects constraints into pyproject.toml
  └── RUN uv sync --no-dev
        ├── Reads uv.lock for pinned versions
        ├── Sees NVIDIA stubs as satisfied — skips reinstalling them
        └── Installs only application packages (transformers, accelerate, etc.) into .venv
```

### Why commit `nvidia-provided.txt`

`nvidia-provided.txt` lists exact NVIDIA package versions. The production `Dockerfile.prod` uses it to inject `constraint-dependencies` into `pyproject.toml` (same as the devcontainer does at runtime). Without it, the production build cannot inject constraints and `uv sync` may attempt to overwrite NVIDIA packages.

The file is generated from the specific NVIDIA container version you're using. If you update `FROM nvcr.io/nvidia/pytorch:26.02-py3` to a newer version, rebuild the devcontainer and re-commit `nvidia-provided.txt`.

---

## 7. Graduation Workflow (Step-by-Step)

```
Step 1: Finalize dependencies inside the devcontainer
─────────────────────────────────────────────────────
  uv add transformers accelerate fastapi uvicorn pydantic
  # Verify the numpy protection is intact:
  python -c "import numpy; print(numpy.__file__)"
  # Must print: /usr/local/lib/python3.12/dist-packages/numpy/__init__.py

Step 2: Commit lock files and application code
───────────────────────────────────────────────
  git add pyproject.toml uv.lock nvidia-provided.txt src/
  git commit -m "feat: add inference API and finalize deps"

Step 3: Write Dockerfile.prod using the template in Section 2
─────────────────────────────────────────────────────────────
  # If using Option A (recommended): add PRODUCTION=1 guards to
  # setup-environment.sh before the dev-only blocks.
  # Dockerfile.prod copies setup-environment.sh and runs it with PRODUCTION=1.

Step 4: Build and verify the production image locally
──────────────────────────────────────────────────────
  docker build -f Dockerfile.prod -t myproject:prod .

  # Test 1: NVIDIA packages not overwritten
  docker run --rm --gpus all myproject:prod \
      python -c "import numpy; print(numpy.__file__)"
  # Expected: /usr/local/lib/python3.12/dist-packages/numpy/__init__.py

  # Test 2: GPU accessible
  docker run --rm --gpus all myproject:prod \
      python -c "import torch; print(torch.cuda.is_available())"
  # Expected: True

  # Test 3: nvidia-smi works
  docker run --rm --gpus all myproject:prod nvidia-smi

  # Test 4: API starts and probes respond correctly
  docker run --rm --gpus all -p 8080:8080 myproject:prod &
  sleep 5
  curl http://localhost:8080/health   # 200 (STARTING or LOADING_MODEL)
  curl http://localhost:8080/ready    # 503 (not ready yet)
  # Wait for model to load, then:
  curl http://localhost:8080/ready    # 200

Step 5: Tag with git SHA and push to container registry
────────────────────────────────────────────────────────
  GIT_SHA=$(git rev-parse --short HEAD)
  docker tag myproject:prod registry.example.com/myproject:${GIT_SHA}
  docker push registry.example.com/myproject:${GIT_SHA}
  # Update image tag in your Kubernetes manifests to this SHA

Step 6: Apply Kubernetes manifests
────────────────────────────────────
  # Create namespace
  kubectl create namespace ml-serving

  # Create HuggingFace token secret
  kubectl create secret generic huggingface-credentials \
      --from-literal=token=${HF_TOKEN} \
      --namespace ml-serving

  # Create PVCs
  kubectl apply -f k8s/pvcs.yaml -n ml-serving

  # Download model weights (one-time job)
  kubectl apply -f k8s/model-downloader-job.yaml -n ml-serving
  kubectl wait --for=condition=complete job/download-llama-weights \
      --timeout=3600s -n ml-serving

  # Deploy the inference API (or training job)
  kubectl apply -f k8s/inference-deployment.yaml -n ml-serving
  kubectl apply -f k8s/service.yaml -n ml-serving

  # Monitor rollout
  kubectl rollout status deployment/llm-inference-api -n ml-serving
  kubectl get pods -n ml-serving -w

Step 7: Verify the running pod
────────────────────────────────
  POD=$(kubectl get pod -n ml-serving -l app=llm-inference-api -o jsonpath='{.items[0].metadata.name}')

  # Confirm GPU allocation
  kubectl describe pod ${POD} -n ml-serving | grep -A5 "Requests:"
  # Expected: nvidia.com/gpu: 1

  # Check GPU from inside the pod
  kubectl exec ${POD} -n ml-serving -- nvidia-smi

  # Check probe endpoints
  kubectl exec ${POD} -n ml-serving -- \
      curl -s http://localhost:8080/health | python -m json.tool
  kubectl exec ${POD} -n ml-serving -- \
      curl -s http://localhost:8080/ready | python -m json.tool

  # Check logs for model loading progress
  kubectl logs ${POD} -n ml-serving -f
```

---

## Reference: Environment Variables

These variables are set in `devcontainer.json` and should be carried into `Dockerfile.prod` as `ENV` directives:

| Variable | Value in devcontainer | Purpose |
|---|---|---|
| `NVIDIA_VISIBLE_DEVICES` | `all` | Expose all GPUs to the container |
| `CUDA_VISIBLE_DEVICES` | `0` | Restrict to first GPU (adjust for multi-GPU) |
| `PYTORCH_CUDA_ALLOC_CONF` | `expandable_segments:True,...` | Reduce CUDA OOM errors from fragmentation |
| `PYTHONPATH` | `/workspaces/{project}/src` | Makes `src/` importable without install |
| `HF_HOME` | `/workspaces/{project}/.cache/huggingface` | HuggingFace cache location |
| `TORCH_HOME` | `/workspaces/{project}/.cache/torch` | Torch hub cache location |
| `TRANSFORMERS_CACHE` | `.../.cache/huggingface/transformers` | Transformers model cache |
| `UV_PROJECT_ENVIRONMENT` | `/workspaces/{project}/.venv` | Tells uv which venv is the project env |
| `NVIDIA_DRIVER_CAPABILITIES` | `compute,utility` | Required by NVIDIA container runtime |

In production, redirect cache paths to the PVC mount (`/models/.cache/...`) so downloaded models persist across pod restarts.
