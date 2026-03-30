# ROCm PyTorch ML DevContainer Template

**ROCm 7.2 | PyTorch 2.9.1 | Python 3.12 | Ubuntu 24.04**

A ready-to-use development container for machine learning on consumer AMD GPUs. Download it, run the setup script, open in your IDE, and start training models -- GPU access, dependency management, and Python environment are all handled for you.

**Ported from:** [datascience-template-CUDA](https://github.com/thesteve0/datascience-template-CUDA)

## Why This Template Exists

Doing ML on consumer AMD GPUs is harder than it should be:

1. **AMD's ROCm documentation focuses on data center GPUs** (MI300X series). If you have a Ryzen AI laptop or a Radeon RX desktop card, the official guides don't cover your hardware well. ROCm 7.2 is the first release with production support for consumer chips, but finding the right docs is difficult.

2. **One wrong `pip install` can silently break your GPU support.** PyPI only distributes CUDA-built PyTorch wheels. If any package you install pulls in `torch` as a dependency, pip happily overwrites your working ROCm PyTorch with a CUDA version that can't see your AMD GPU. You won't know until your training run silently falls back to CPU.

3. **Container setup for ROCm is non-trivial.** You need the right device mounts (`/dev/kfd`, `/dev/dri`), the right group memberships (`video`, `render`), the right environment variables (`HIP_VISIBLE_DEVICES`, not `CUDA_VISIBLE_DEVICES`), and a Python environment that preserves the container's optimized libraries while letting you install your own packages.

This template solves all three problems. It gives you a devcontainer with working GPU access, an automatic dependency protection system that prevents ROCm package overwrites, and tested configurations for both VSCode and JetBrains IDEs.

## Supported Hardware

This template targets **consumer AMD GPUs** -- the ones AMD's main docs tend to overlook:

| Hardware | Architecture | Status |
|----------|-------------|--------|
| AMD Ryzen AI Max+ 395 (Strix Halo) | gfx1151 | Tested |
| AMD Ryzen AI 300 Series (Strix Point) | gfx1150 | Supported |
| Radeon RX 9000 Series (RDNA 4) | gfx12xx | Supported |
| Radeon RX 7000 Series (RDNA 3) | gfx11xx | Supported |
| Custom Steam Deck configurations | varies | Tested |

**System requirements:** Linux with ROCm 7.2+ drivers, Docker or Podman, 32GB+ RAM recommended, 1TB NVMe SSD recommended.

**Precision:** FP16 is the only officially validated precision type for Ryzen AI processors. BF16/FP32/INT8 may work but are untested by AMD. Avoid INT4 quantization (often falls back to slow software emulation).

**Note:** For AMD data center GPUs (MI300X series), use [AMD's official ROCm documentation](https://rocm.docs.amd.com/) instead of this template.

## Prerequisites

### 1. ROCm Drivers

Follow the official guide for consumer GPUs: [ROCm 7.2 for Radeon and Ryzen](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/index.html)

Verify your setup:
```bash
# Check AMD GPU is visible
lspci | grep -i amd

# Verify ROCm installation
amd-smi

# Quick smoke test (pulls container image, takes a minute the first time)
docker run -it --device=/dev/kfd --device=/dev/dri \
    rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1 \
    python -c "import torch; print(f'ROCm available: {torch.cuda.is_available()}')"
```

### 2. Container Runtime

**Docker:**
```bash
sudo dnf install docker              # Fedora/RHEL
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# Log out and back in for group change to take effect
```

**Podman** (alternative -- works out of the box with VSCode Dev Containers, no configuration changes needed):
```bash
sudo dnf install podman
```

### 3. IDE

**VSCode:** Install the [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.

**JetBrains:** Install [JetBrains Gateway](https://www.jetbrains.com/remote-development/gateway/) or PyCharm Professional (recent version required for devcontainer support).

## Quick Start

### New ML Project (Most Common)

```bash
# 1. Download the template (don't git clone -- you want a fresh repo)
#    GitHub -> Code -> Download ZIP -> Extract -> Rename to your project name

# 2. Run setup (select your IDE, confirm git identity)
cd my-ml-project
./setup-project.sh

# 3. Open in your IDE
#    VSCode: code . -> "Reopen in Container" when prompted (5-10 min first build)
#    JetBrains: Open via Gateway or PyCharm's devcontainer support

# 4. Verify GPU access (inside the container)
python hello-gpu.py     # Quick check (30 sec)
python test-gpu.py      # Full benchmark (2-3 min)

# 5. Start working
uv add transformers datasets
```

### Wrapping an Existing Repository

If you have an existing ML project and want to add ROCm GPU support:

```bash
# 1. Download and extract the template, name it as your project wrapper
cd my-project-wrapper

# 2. Setup with your existing repo
./setup-project.sh --clone-repo https://github.com/username/existing-ml-project.git

# 3. Open in IDE -> Reopen in container
# Your repo is available at ./existing-ml-project/ inside the container
```

### IDE Selection

```bash
./setup-project.sh                  # Interactive prompt
./setup-project.sh --ide vscode     # VSCode only
./setup-project.sh --ide jetbrains  # JetBrains only
./setup-project.sh --ide both       # Both IDEs
```

## Managing Dependencies

### The Golden Rule

**Always use `uv add` to install packages.** Never use `pip install` directly.

```bash
uv add transformers              # Add a runtime dependency
uv add --dev pytest              # Add a dev-only dependency
uv remove transformers           # Remove a dependency
uv sync                          # Reinstall everything from lockfile
```

### Why This Matters

When you `uv add transformers`, the `transformers` package depends on `torch`. Normally, uv would pull `torch` from PyPI -- but PyPI only has **CUDA** builds of PyTorch. Installing them would silently overwrite your working ROCm PyTorch, and your GPU would stop working.

The template prevents this automatically. During container setup, it scans every package pre-installed in the ROCm container and writes an exclusion list into `pyproject.toml`:

```toml
[tool.uv]
exclude-dependencies = [
    "numpy",
    "torch",
    "torchvision",
    # ... ~130 more ROCm-provided packages
]
```

When `uv add transformers` sees that `torch` is in the exclusion list, it skips installing it. Your ROCm PyTorch stays untouched, and `transformers` can use it because the `.pth` bridge makes all ROCm packages importable from your project's virtual environment.

### Verifying ROCm PyTorch Is Intact

After installing any package, check:
```bash
python -c "import torch; print(torch.__version__)"
# Should show: 2.9.1+rocm7.2... (the +rocm suffix confirms it's the ROCm build)
```

If you see a version WITHOUT `+rocm`, something overwrote it. See [Troubleshooting](#troubleshooting).

### Alternative: requirements.txt Workflow

For projects using `requirements.txt` instead of `pyproject.toml`:

```bash
# Filter out ROCm-provided packages
python scripts/resolve-dependencies.py requirements.txt

# Install the filtered version
uv pip install -r requirements-filtered.txt
```

## Project Structure

After `setup-project.sh` runs:

```
my-ml-project/
├── .devcontainer/
│   ├── devcontainer.json          # Container configuration
│   ├── Dockerfile                 # Container image definition
│   └── setup-environment.sh       # Runs automatically on container creation
├── src/my-ml-project/             # Your source code goes here
├── tests/                         # Your tests
├── configs/                       # Configuration files
├── scripts/
│   └── resolve-dependencies.py    # For requirements.txt workflow
├── models/                        # Model checkpoints (persists across rebuilds)
├── datasets/                      # Training data (persists across rebuilds)
├── .cache/                        # HuggingFace/PyTorch caches (persists)
├── template_docs/                 # Template reference documentation
├── hello-gpu.py                   # Quick GPU sanity check
├── test-gpu.py                    # Comprehensive GPU benchmark
├── pyproject.toml                 # Dependencies and project config
├── README.md                      # Your project README (customize this)
└── CLAUDE.md                      # Claude Code context (customize this)
```

**Data persistence:** `models/`, `datasets/`, and `.cache/` are regular directories in your project folder. They survive container rebuilds because VSCode bind-mounts your entire workspace. They're in `.gitignore` by default.

### External Data Access

Your host's `~/data` directory is automatically mounted at `/data` inside the container:

```bash
ls /data                                    # Browse host ~/data
python train.py --data-path /data/imagenet  # Reference directly (no copying needed)
```

This is useful for large datasets you don't want to duplicate per project.

## GPU Performance: What to Expect

Consumer AMD GPUs (especially integrated APUs like Ryzen AI) behave differently from discrete NVIDIA GPUs:

**Small models (< 1M parameters):** CPU is often faster. GPU kernel launch overhead (~50-100ms) dominates when there's not much actual computation.

**Medium to large models (5M+ parameters, batch 256+):** GPU wins by 2-4x or more. This is where integrated GPU acceleration pays off.

**Real-world ML models** (transformers, ResNets, diffusion models) are large enough that GPU acceleration is significant. The template includes `test-gpu.py` which demonstrates this with both small and large workloads.

```bash
# Run the full benchmark to see the crossover point
python test-gpu.py
```

## JetBrains IDE Setup

VSCode works out of the box. JetBrains requires one manual step after the container starts:

1. Open **Project Structure**: File -> Project Structure (`Ctrl+Alt+Shift+S`)
2. Click **SDK** dropdown -> **Add SDK** -> **Add Python Interpreter**
3. Configure:
   - Location: Local Machine
   - Environment: Select existing
   - Type: **uv**
   - Path to uv: `/opt/venv/bin/uv`
   - Environment: Select `Python 3.12 (/workspaces/PROJECT_NAME/.venv)`

**Why manual?** JetBrains doesn't support automatic interpreter configuration in devcontainers ([IJPL-174150](https://youtrack.jetbrains.com/issue/IJPL-174150)). The template pre-configures everything else (source roots, test roots, excluded directories, Ruff linter).

## Claude Code Integration

The devcontainer includes Claude Code CLI with Vertex AI authentication.

**Host setup (one-time):**
```bash
# Add to ~/.bashrc or ~/.zshrc
export ANTHROPIC_VERTEX_PROJECT_ID="your-gcp-project-id"
export ANTHROPIC_VERTEX_REGION="us-east5"
export CLAUDE_CODE_USE_VERTEX="true"

# Authenticate with Google Cloud
gcloud auth application-default login
```

Claude Code is then available inside the container. Your gcloud credentials are mounted read-only.

## Security Notice

**This template is for local development, not production.**

The devcontainer user has passwordless sudo access (standard for devcontainers). This is fine for single-user development but inappropriate for production. Production ML deployments should use non-root users, read-only filesystems, proper secrets management, and container hardening.

## Troubleshooting

### GPU Not Detected

```bash
# 1. Check GPU is visible on host
amd-smi

# 2. Check container has GPU access
python -c "import torch; print(torch.cuda.is_available())"

# 3. If False, verify container was started with GPU devices
# The devcontainer.json includes --device=/dev/kfd and --device=/dev/dri
# If using Podman, ensure you're in the video and render groups
```

### ROCm PyTorch Was Overwritten

If `torch.__version__` shows a version without `+rocm`:

```bash
# The simplest fix is to rebuild the container
# VSCode: Ctrl+Shift+P -> "Dev Containers: Rebuild Container"
```

This recreates the entire environment from scratch, restoring the ROCm PyTorch.

### Import Errors ("importing numpy from source directory")

This misleading error actually means Python version mismatch between your `.venv` and the container's Python:

```bash
# Check versions -- they must match
/opt/venv/bin/python --version    # Container Python
.venv/bin/python --version        # Project venv

# Fix: recreate the venv
rm -rf .venv
/opt/venv/bin/uv venv --python /opt/venv/bin/python .venv

# Recreate the .pth bridge
PYVER=$(/opt/venv/bin/python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "/opt/venv/lib/python${PYVER}/site-packages" > .venv/lib/python${PYVER}/site-packages/_rocm_bridge.pth

# Reinstall your packages
uv sync
```

### Container Won't Start

```bash
# Check Docker/Podman is running
sudo systemctl status docker

# Check container logs
docker logs <container-id>

# Rebuild from scratch
# VSCode: Ctrl+Shift+P -> "Dev Containers: Rebuild Container"
```

### Permission Errors

The devcontainer user's UID matches your host user (via VSCode's automatic UID remapping). If you still get permission errors:

```bash
# Inside the container
sudo chown -R $(whoami):$(whoami) /workspaces/my-ml-project
```

## Resources

- [ROCm 7.2 for Radeon/Ryzen GPUs](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/index.html) -- the primary doc for consumer hardware
- [ROCm 7.2 Compatibility Matrix](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/compatibility/compatibilityryz/native_linux/native_linux_compatibility.html)
- [Original CUDA Template](https://github.com/thesteve0/datascience-template-CUDA)
- [ROCm GitHub Issues](https://github.com/ROCm/ROCm/issues)
- AMD Developer Discord

## License

See [LICENSE](LICENSE) file.

## Acknowledgments

- Based on [datascience-template-CUDA](https://github.com/thesteve0/datascience-template-CUDA)
- Tested on AMD Ryzen AI Max+ 395 (Strix Halo) and Steam Deck
- ROCm PyTorch containers provided by AMD
