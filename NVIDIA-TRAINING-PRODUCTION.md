# AMD ROCm Dev → NVIDIA GPU Production Training

This guide covers running training workloads on NVIDIA GPUs in production after developing locally
in the ROCm devcontainer on AMD hardware.

The short answer: **your PyTorch code needs no changes**. The longer answer is below.

---

## Table of Contents

1. [Why This Works — Code Portability](#1-why-this-works--code-portability)
2. [Extracting Production Dependencies](#2-extracting-production-dependencies)
3. [Production Dockerfile for NVIDIA](#3-production-dockerfile-for-nvidia)
4. [Kubeflow Training (PyTorchJob)](#4-kubeflow-training-pytorchjob)
5. [Ray Training (KubeRay)](#5-ray-training-kuberay)
6. [Environment Variable Reference](#6-environment-variable-reference)
7. [Verification Steps](#7-verification-steps)

---

## 1. Why This Works — Code Portability

### The HIP → CUDA API mapping

ROCm implements the HIP runtime, which mirrors the CUDA API surface. When PyTorch is built for
ROCm, it maps `torch.cuda.*` calls to the underlying HIP/ROCm equivalents. From your Python
code's perspective, there is no difference:

```python
# This code runs identically on AMD ROCm and NVIDIA CUDA
device = "cuda" if torch.cuda.is_available() else "cpu"
model = MyModel().to(device)

# GPU count
n_gpus = torch.cuda.device_count()

# Memory management
torch.cuda.empty_cache()

# Mixed precision
with torch.autocast("cuda"):
    output = model(input)
```

The `torch.cuda.is_available()` call returns `True` inside both the ROCm devcontainer and an
NVIDIA production container. The string `"cuda"` is the correct device identifier in both
environments.

### Code patterns that work on both

| Pattern | Works on ROCm | Works on CUDA | Notes |
|---|---|---|---|
| `torch.cuda.is_available()` | Yes | Yes | Standard device check |
| `tensor.to("cuda")` | Yes | Yes | Standard device transfer |
| `model.cuda()` | Yes | Yes | Standard model move |
| `torch.autocast("cuda")` | Yes | Yes | Mixed precision |
| `torch.cuda.device_count()` | Yes | Yes | Multi-GPU count |
| `torch.distributed` (DDP) | Yes | Yes | Distributed training |

### Code patterns to avoid

| Pattern | Problem |
|---|---|
| Hardcoded `"hip"` or `"rocm"` strings in device paths | ROCm-only |
| `torch.version.hip` checks without fallback | Breaks on CUDA |
| `HIP_VISIBLE_DEVICES` in Python code | Use `CUDA_VISIBLE_DEVICES` on NVIDIA |
| Importing `amdsmi` or `rocm_smi` directly | AMD-only system libraries |

If you need hardware-specific code paths, use the standard check:

```python
import torch

# Detect backend without breaking on either platform
is_rocm = hasattr(torch.version, 'hip') and torch.version.hip is not None
device = "cuda" if torch.cuda.is_available() else "cpu"
```

---

## 2. Extracting Production Dependencies

### How the ROCm devcontainer filters dependencies

The devcontainer's `setup-environment.sh` and `resolve-dependencies.py` scripts filter your
`requirements.txt` or `pyproject.toml` dependencies to skip packages already provided by the ROCm
container (torch, numpy, etc.). This filtering happens at container startup and is specific to the
ROCm environment.

When building for NVIDIA production, **this filtering does not apply**. You start from an NVIDIA
base image that ships its own optimized packages, and your project dependencies install normally
on top of them.

### Generating `requirements-nvidia.txt`

The cleanest approach for NVIDIA production is to export your project's direct dependencies
without the ROCm exclusions:

```bash
# Inside the ROCm devcontainer, from your project root:

# Option A: If using pyproject.toml with uv
uv export --no-hashes --no-emit-project > requirements-nvidia.txt
# Then remove any lines that are ROCm-specific (torch, torchvision, torchaudio if pinned to ROCm builds)
# NVIDIA base images already provide CUDA-optimized versions of these

# Option B: If using requirements.txt directly
# Copy requirements.txt and remove any torch/torchvision/torchaudio pins
# that reference ROCm URLs or rocm-specific index sources
cp requirements.txt requirements-nvidia.txt
```

For most projects, `requirements-nvidia.txt` is simply your `requirements.txt` without any lines
that pin ROCm-specific wheels (lines containing `+rocm`, `rocm.html`, or `https://download.pytorch.org/whl/rocm*`).

### What the NVIDIA base image already provides

The `nvcr.io/nvidia/pytorch` base image ships pre-installed CUDA-optimized builds of:
- `torch`, `torchvision`, `torchaudio`
- `numpy`, `scipy`, `pandas`
- `transformer-engine`, `flash-attn` (on compatible hardware)
- And 200+ other packages

Do not include these in `requirements-nvidia.txt` — the NVIDIA base image's versions are compiled
against specific CUDA libraries and must not be overwritten. See `PRODUCTION-DEPLOYMENT.md` for
the full three-layer protection mechanism used in NVIDIA production images.

---

## 3. Production Dockerfile for NVIDIA

The NVIDIA production Dockerfile follows the same pattern described in `PRODUCTION-DEPLOYMENT.md`.
Key points specific to training workloads:

```dockerfile
FROM nvcr.io/nvidia/pytorch:26.02-py3

# Workaround for Ubuntu 24.04 having pre-existing ubuntu user at UID 1000
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu

# Non-root user for security
RUN groupadd --gid 1000 trainer \
    && useradd --uid 1000 --gid 1000 --shell /bin/bash --create-home trainer

WORKDIR /app

# Install project dependencies (not torch — already in base image)
COPY requirements-nvidia.txt ./
RUN pip install --no-deps -r requirements-nvidia.txt

# Copy source code
COPY src/ ./src/

# Training-specific environment
ENV PYTHONPATH=/app/src \
    HF_HOME=/app/.cache/huggingface \
    TORCH_HOME=/app/.cache/torch \
    TRANSFORMERS_CACHE=/app/.cache/huggingface/transformers \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,max_split_size_mb:512,garbage_collection_threshold:0.6 \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

USER trainer

# Default entry point — override in Kubernetes pod spec
CMD ["/usr/bin/python3", "-m", "your_project.train"]
```

> **Note**: See `PRODUCTION-DEPLOYMENT.md` for the full three-layer NVIDIA package protection
> system using `setup-environment.sh` with `PRODUCTION=1`. The Dockerfile above uses a simplified
> `pip install --no-deps` approach suitable for projects that only add packages not already in
> the base image. If your project needs finer-grained dependency resolution, use the
> `PRODUCTION=1` approach from `PRODUCTION-DEPLOYMENT.md`.

### Build and verify

```bash
docker build -f Dockerfile.nvidia -t myproject:nvidia-latest .

# Verify GPU access
docker run --rm --gpus all myproject:nvidia-latest \
    python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, GPU: {torch.cuda.get_device_name(0)}')"

# Verify torch version and CUDA version
docker run --rm --gpus all myproject:nvidia-latest \
    python -c "import torch; print(f'torch {torch.__version__}, CUDA {torch.version.cuda}')"
```

---

## 4. Kubeflow Training (PyTorchJob)

Kubeflow's Training Operator provides the `PyTorchJob` CRD, which handles distributed training
coordination (process groups, rendezvous, rank assignment) automatically.

### Prerequisite

Kubeflow Training Operator must be installed:

```bash
kubectl apply -k "github.com/kubeflow/training-operator/manifests/overlays/standalone"

# Verify
kubectl get crd | grep pytorchjobs
# Expected: pytorchjobs.kubeflow.org
```

### Single-node PyTorchJob

For training on one node with one or more GPUs:

```yaml
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: train-my-model
  namespace: ml-training
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1
      restartPolicy: OnFailure
      template:
        spec:
          containers:
          - name: pytorch
            image: registry.example.com/myproject:a72770e
            command:
            - python
            - -m
            - your_project.train
            args:
            - --config=/app/configs/train.yaml
            - --output-dir=/checkpoints/run1
            - --data-dir=/data

            resources:
              requests:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"
              limits:
                memory: "24Gi"
                cpu: "8"
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
            - name: training-data
              mountPath: /data
              readOnly: true
            - name: checkpoints
              mountPath: /checkpoints
            - name: model-weights
              mountPath: /models
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
          - name: dshm
            emptyDir:
              medium: Memory
              sizeLimit: "8Gi"

          tolerations:
          - key: "nvidia.com/gpu"
            operator: "Exists"
            effect: "NoSchedule"

          nodeSelector:
            accelerator: nvidia-gpu
```

### Multi-node DDP PyTorchJob

For training distributed across multiple nodes. The Training Operator automatically sets
`MASTER_ADDR`, `MASTER_PORT`, `RANK`, `WORLD_SIZE`, and `LOCAL_RANK` environment variables:

```yaml
apiVersion: kubeflow.org/v1
kind: PyTorchJob
metadata:
  name: train-my-model-4node
  namespace: ml-training
spec:
  pytorchReplicaSpecs:
    Master:
      replicas: 1           # Always exactly 1 Master
      restartPolicy: OnFailure
      template:
        spec:
          containers:
          - name: pytorch
            image: registry.example.com/myproject:a72770e
            command:
            - python
            - -m
            - torch.distributed.run
            args:
            - --nnodes=4
            - --nproc-per-node=1       # GPUs per node; set to match nvidia.com/gpu request
            - --rdzv-backend=c10d
            - your_project/train.py
            - --config=/app/configs/train.yaml

            resources:
              requests:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"
              limits:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"

            # Training Operator injects: MASTER_ADDR, MASTER_PORT, RANK, WORLD_SIZE, LOCAL_RANK
            env:
            - name: PYTORCH_CUDA_ALLOC_CONF
              value: "expandable_segments:True,max_split_size_mb:512,garbage_collection_threshold:0.6"
            - name: HF_HOME
              value: "/models/.cache/huggingface"

            volumeMounts:
            - name: training-data
              mountPath: /data
              readOnly: true
            - name: checkpoints
              mountPath: /checkpoints
            - name: model-weights
              mountPath: /models
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
          - name: dshm
            emptyDir:
              medium: Memory
              sizeLimit: "8Gi"

          tolerations:
          - key: "nvidia.com/gpu"
            operator: "Exists"
            effect: "NoSchedule"

          nodeSelector:
            accelerator: nvidia-gpu

    Worker:
      replicas: 3           # Total nodes = Master(1) + Worker(N)
      restartPolicy: OnFailure
      template:
        spec:
          # Same container spec as Master (image, command, args, resources, volumes)
          containers:
          - name: pytorch
            image: registry.example.com/myproject:a72770e
            command:
            - python
            - -m
            - torch.distributed.run
            args:
            - --nnodes=4
            - --nproc-per-node=1
            - --rdzv-backend=c10d
            - your_project/train.py
            - --config=/app/configs/train.yaml

            resources:
              requests:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"
              limits:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"

            env:
            - name: PYTORCH_CUDA_ALLOC_CONF
              value: "expandable_segments:True,max_split_size_mb:512,garbage_collection_threshold:0.6"
            - name: HF_HOME
              value: "/models/.cache/huggingface"

            volumeMounts:
            - name: training-data
              mountPath: /data
              readOnly: true
            - name: checkpoints
              mountPath: /checkpoints
            - name: model-weights
              mountPath: /models
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
          - name: dshm
            emptyDir:
              medium: Memory
              sizeLimit: "8Gi"

          tolerations:
          - key: "nvidia.com/gpu"
            operator: "Exists"
            effect: "NoSchedule"

          nodeSelector:
            accelerator: nvidia-gpu
```

### DDP training code pattern

Your training script must initialize the process group. The Training Operator injects all required
environment variables automatically:

```python
import os
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP


def setup_distributed():
    """Initialize distributed training if running in a multi-node environment."""
    if "RANK" not in os.environ:
        # Single-process training (local dev or single-GPU job)
        return False

    dist.init_process_group(backend="nccl")  # nccl for NVIDIA, gloo as fallback
    torch.cuda.set_device(int(os.environ["LOCAL_RANK"]))
    return True


def cleanup_distributed():
    if dist.is_initialized():
        dist.destroy_process_group()


def train():
    is_distributed = setup_distributed()
    rank = int(os.environ.get("RANK", 0))
    local_rank = int(os.environ.get("LOCAL_RANK", 0))
    world_size = int(os.environ.get("WORLD_SIZE", 1))

    device = torch.device(f"cuda:{local_rank}")
    model = MyModel().to(device)

    if is_distributed:
        model = DDP(model, device_ids=[local_rank])

    # Only rank 0 saves checkpoints
    if rank == 0:
        torch.save(model.state_dict(), "/checkpoints/model.pt")

    cleanup_distributed()


if __name__ == "__main__":
    train()
```

### Monitoring a PyTorchJob

```bash
# Check job status
kubectl get pytorchjob -n ml-training

# Describe the job (shows events, replica states)
kubectl describe pytorchjob train-my-model -n ml-training

# Logs from the master pod
kubectl logs -l training.kubeflow.org/job-name=train-my-model,training.kubeflow.org/replica-type=master -n ml-training -f

# Logs from worker 0
kubectl logs -l training.kubeflow.org/job-name=train-my-model,training.kubeflow.org/replica-index=0,training.kubeflow.org/replica-type=worker -n ml-training -f
```

---

## 5. Ray Training (KubeRay)

Ray Train provides a higher-level API for distributed training with automatic fault tolerance,
checkpointing, and hyperparameter search integration.

### Prerequisite

KubeRay operator must be installed:

```bash
helm install kuberay-operator kuberay/kuberay-operator --namespace ray-system --create-namespace

# Verify
kubectl get crd | grep ray
# Expected: rayjobs.ray.io, rayclusters.ray.io, rayservices.ray.io
```

### Ray Train code pattern (TorchTrainer)

```python
import os
import tempfile
import torch
from ray import train
from ray.train import Checkpoint, ScalingConfig
from ray.train.torch import TorchTrainer


def train_func(config):
    """
    This function runs on each worker. Ray Train handles distributed setup
    automatically — no manual dist.init_process_group() needed.
    """
    # Ray Train auto-prepares the model for distributed training
    model = train.torch.prepare_model(MyModel())
    optimizer = torch.optim.AdamW(model.parameters(), lr=config["lr"])

    # Ray Train auto-prepares the dataloader for distributed sampling
    dataloader = train.torch.prepare_data_loader(
        torch.utils.data.DataLoader(MyDataset(), batch_size=config["batch_size"])
    )

    for epoch in range(config["epochs"]):
        model.train()
        total_loss = 0.0
        for batch in dataloader:
            optimizer.zero_grad()
            loss = model(batch)
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

        # Save checkpoint on all workers; Ray aggregates
        with tempfile.TemporaryDirectory() as tmpdir:
            torch.save(model.state_dict(), os.path.join(tmpdir, "model.pt"))
            checkpoint = Checkpoint.from_directory(tmpdir)

        # Report metrics to Ray (aggregated from all workers)
        train.report(
            {"loss": total_loss / len(dataloader), "epoch": epoch},
            checkpoint=checkpoint,
        )


def main():
    trainer = TorchTrainer(
        train_func,
        train_loop_config={"lr": 1e-4, "batch_size": 32, "epochs": 10},
        scaling_config=ScalingConfig(
            num_workers=4,           # Number of training workers (one per GPU node)
            use_gpu=True,
            resources_per_worker={"GPU": 1, "CPU": 8, "memory": 24 * 1024 ** 3},
        ),
        run_config=train.RunConfig(
            storage_path="/checkpoints",
            name="my-training-run",
        ),
    )

    result = trainer.fit()
    print(f"Best checkpoint: {result.best_checkpoints}")


if __name__ == "__main__":
    main()
```

### RayJob YAML for submitting a training run

```yaml
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: train-my-model
  namespace: ml-training
spec:
  # Python entrypoint to run inside the cluster
  entrypoint: python /app/src/your_project/train_ray.py

  # Shut down the cluster when the job finishes
  shutdownAfterJobFinishes: true
  ttlSecondsAfterFinished: 600    # Keep for 10 min after finish for log inspection

  rayClusterSpec:
    rayVersion: "2.40.0"           # Match your Ray version

    headGroupSpec:
      rayStartParams:
        dashboard-host: "0.0.0.0"
      template:
        spec:
          containers:
          - name: ray-head
            image: registry.example.com/myproject:a72770e
            resources:
              requests:
                memory: "8Gi"
                cpu: "4"
              limits:
                memory: "8Gi"
                cpu: "4"
            # Head node: no GPU needed (just coordinates workers)

            volumeMounts:
            - name: checkpoints
              mountPath: /checkpoints
            - name: model-weights
              mountPath: /models

          volumes:
          - name: checkpoints
            persistentVolumeClaim:
              claimName: checkpoint-storage-pvc
          - name: model-weights
            persistentVolumeClaim:
              claimName: model-weights-pvc

    workerGroupSpecs:
    - groupName: gpu-workers
      replicas: 4                 # Number of GPU workers
      minReplicas: 4
      maxReplicas: 4

      rayStartParams: {}

      template:
        spec:
          containers:
          - name: ray-worker
            image: registry.example.com/myproject:a72770e

            resources:
              requests:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"
              limits:
                memory: "24Gi"
                cpu: "8"
                nvidia.com/gpu: "1"

            env:
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
            - name: training-data
              mountPath: /data
              readOnly: true
            - name: checkpoints
              mountPath: /checkpoints
            - name: model-weights
              mountPath: /models
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
          - name: dshm
            emptyDir:
              medium: Memory
              sizeLimit: "8Gi"

          tolerations:
          - key: "nvidia.com/gpu"
            operator: "Exists"
            effect: "NoSchedule"

          nodeSelector:
            accelerator: nvidia-gpu
```

### Monitoring a RayJob

```bash
# Check job status
kubectl get rayjob -n ml-training

# Get the Ray dashboard URL (forward the port)
kubectl port-forward service/train-my-model-raycluster-head-svc 8265:8265 -n ml-training
# Then open http://localhost:8265 in your browser

# Get job logs
kubectl logs -l ray.io/node-type=head -n ml-training -f

# Check worker logs
kubectl logs -l ray.io/group=gpu-workers -n ml-training --prefix
```

### Kubeflow vs Ray: when to use each

| Consideration | Kubeflow PyTorchJob | Ray Train |
|---|---|---|
| API level | Low-level: you manage DDP setup | High-level: Ray handles distributed setup |
| Fault tolerance | Restart policy only | Automatic worker recovery, checkpoint resume |
| Hyperparameter tuning | Manual or separate tool | Built-in Ray Tune integration |
| Data loading | Manual sharding | Automatic via Ray Data |
| Overhead | Minimal (just Kubernetes Job + CRD) | Ray cluster overhead (~1 head node always running) |
| Best for | Simple DDP fine-tuning, known-stable jobs | Long runs, HP search, teams with changing experiments |

---

## 6. Environment Variable Reference

### AMD ROCm devcontainer → NVIDIA production mapping

| Purpose | ROCm devcontainer | NVIDIA production |
|---|---|---|
| GPU visibility | `HIP_VISIBLE_DEVICES=0` | `CUDA_VISIBLE_DEVICES=0` |
| GPU runtime exposure | `/dev/kfd`, `/dev/dri` device mounts | `NVIDIA_VISIBLE_DEVICES=all` |
| Driver capabilities | (implicit via device mounts) | `NVIDIA_DRIVER_CAPABILITIES=compute,utility` |
| ROCm installation path | `ROCM_HOME=/opt/rocm` | Not applicable |
| hipBLASLt control | `ROCBLAS_USE_HIPBLASLT=1` | Not applicable (cuBLAS used) |
| Memory allocator | (ROCm default) | `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True,...` |
| Python path | `PYTHONPATH=/workspaces/{project}/src` | `PYTHONPATH=/app/src` |
| HuggingFace cache | `HF_HOME=/workspaces/{project}/.cache/huggingface` | `HF_HOME=/models/.cache/huggingface` (PVC-backed) |
| Torch cache | `TORCH_HOME=/workspaces/{project}/.cache/torch` | `TORCH_HOME=/models/.cache/torch` (PVC-backed) |

### Variables that stay the same

These variables work identically on both AMD and NVIDIA:

- `HF_TOKEN` — HuggingFace API token
- `HF_HOME` — HuggingFace cache path
- `TORCH_HOME` — Torch hub cache path
- `PYTHONPATH` — Python module search path
- `TRANSFORMERS_CACHE` — Transformers model cache

---

## 7. Verification Steps

### Step 1: Verify your training code runs on ROCm first

```bash
# Inside the ROCm devcontainer
python -c "import torch; print(f'ROCm available: {torch.cuda.is_available()}')"
python -m your_project.train --config configs/train.yaml --dry-run
```

### Step 2: Build and test the NVIDIA image locally (if you have an NVIDIA GPU)

```bash
docker build -f Dockerfile.nvidia -t myproject:nvidia-test .

# Verify CUDA is available
docker run --rm --gpus all myproject:nvidia-test \
    python -c "
import torch
print(f'CUDA available: {torch.cuda.is_available()}')
print(f'GPU count: {torch.cuda.device_count()}')
print(f'GPU name: {torch.cuda.get_device_name(0)}')
print(f'torch version: {torch.__version__}')
print(f'CUDA version: {torch.version.cuda}')
"

# Run a quick training smoke test (1 batch, 1 epoch)
docker run --rm --gpus all \
    -v $(pwd)/data:/data:ro \
    -v $(pwd)/checkpoints:/checkpoints \
    myproject:nvidia-test \
    python -m your_project.train --config configs/train.yaml --max-steps 10
```

### Step 3: Push and submit to Kubeflow or Ray

```bash
GIT_SHA=$(git rev-parse --short HEAD)
docker tag myproject:nvidia-test registry.example.com/myproject:${GIT_SHA}
docker push registry.example.com/myproject:${GIT_SHA}

# Update the image tag in your PyTorchJob or RayJob YAML, then:
kubectl apply -f k8s/pytorchjob.yaml -n ml-training

# Monitor
kubectl get pytorchjob -n ml-training -w
```

### Step 4: Verify GPU allocation in the cluster

```bash
# For PyTorchJob
PODS=$(kubectl get pods -n ml-training -l training.kubeflow.org/job-name=train-my-model -o name)
for POD in $PODS; do
    echo "=== $POD ==="
    kubectl exec -n ml-training $POD -- nvidia-smi --query-gpu=name,memory.total --format=csv
done

# For RayJob
kubectl exec -n ml-training \
    $(kubectl get pod -n ml-training -l ray.io/group=gpu-workers -o name | head -1) \
    -- nvidia-smi
```

### Step 5: Check that distributed training is working

For multi-node jobs, verify all ranks are communicating:

```bash
# Look for these log lines from your training script:
kubectl logs -l training.kubeflow.org/job-name=train-my-model-4node \
    -n ml-training --prefix | grep -E "RANK|WORLD_SIZE|MASTER"

# Expected output from each pod:
# [pod/train-my-model-4node-master-0] RANK=0, WORLD_SIZE=4, MASTER_ADDR=...
# [pod/train-my-model-4node-worker-0] RANK=1, WORLD_SIZE=4, MASTER_ADDR=...
# [pod/train-my-model-4node-worker-1] RANK=2, WORLD_SIZE=4, MASTER_ADDR=...
# [pod/train-my-model-4node-worker-2] RANK=3, WORLD_SIZE=4, MASTER_ADDR=...
```
