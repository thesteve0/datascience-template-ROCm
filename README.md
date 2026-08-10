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

### Option B: Add ROCm DevContainer to an Existing Repository

```bash
# 1. Download or clone this template
cd datascience-template-ROCm

# 2. Run the existing-project setup script (repo is cloned as a sibling directory)
./setup-project-existing.sh --repo git@github.com:username/my-ml-project.git --ide jetbrains

# 3. Open the newly prepared directory in your IDE
cd ../my-ml-project
code .    # or open with JetBrains Gateway

# 4. Reopen in Container — setup-environment-existing.sh runs automatically and:
#      - Creates .venv (Python version-matched to the ROCm container)
#      - Bridges ROCm packages (torch, numpy, etc.) into .venv via .pth file
#      - Adds ROCm package exclusions to your existing pyproject.toml
#      - Runs uv sync to install your project's dependencies
```

See [Using with an Existing Repository](#using-with-an-existing-repository) in the Usage Guide for details on what happens automatically and how to handle edge cases.

## Usage Guide

### Project Structure

After running `setup-project.sh`, your project will have:

```
my-ml-project/
├── .devcontainer/
│   ├── devcontainer.json       # VSCode devcontainer config
│   └── setup-environment.sh    # Post-creation setup script
├── scripts/
│   └── resolve-dependencies.py # Dependency conflict resolver
├── src/
│   └── my-ml-project/          # Your source code
├── tests/                      # Test files
├── configs/                    # Configuration files
├── models/                     # Persistent volume mount
├── datasets/                   # Persistent volume mount
├── .cache/                     # Persistent volume mount
├── hello-gpu.py                # Quick GPU sanity check
├── test-gpu.py                 # Comprehensive GPU benchmark
├── setup-project.sh            # Project setup script
└── cleanup-script.sh           # Cleanup utility
```

### Managing Dependencies

#### Understanding the Python Environment

When you open the devcontainer, you're working inside a pre-configured environment:

| Component | Location | Notes |
|-----------|----------|-------|
| **Virtual Environment** | `.venv/` (in project root) | Created by setup script, version-matched to container |
| **Python Interpreter** | `.venv/bin/python` | Python 3.12 with ROCm-optimized PyTorch |
| **Package Manager** | `uv` | Fast, modern Python package manager |
| **ROCm PyTorch** | Accessible via `.pth` bridge | DO NOT reinstall from PyPI — it would replace the ROCm build |

The setup script (either `setup-environment.sh` for new projects or `setup-environment-existing.sh` for existing repos) automatically:
1. Creates `.venv/` using `/opt/venv/bin/python` (version-matched to avoid binary incompatibility)
2. Creates a `.pth` bridge so ROCm packages (torch, numpy, etc.) are importable from `.venv`
3. Generates `rocm-provided.txt` listing all protected packages
4. Configures `pyproject.toml` with `[tool.uv] exclude-dependencies` to prevent PyPI from overwriting ROCm packages

#### Adding New Packages (Recommended: uv)

The modern workflow uses `uv` with `pyproject.toml`:

```bash
# 1. Add packages to pyproject.toml dependencies section
#    Edit pyproject.toml and add to the dependencies list:
#    dependencies = [
#        "transformers",
#        "docling",
#    ]

# 2. Install with uv sync
uv sync
```

The `pyproject.toml` contains a `[tool.uv] exclude-dependencies` section that lists all ROCm-provided packages. When you add a package like `transformers` that depends on `torch`, uv sees `torch` in the exclude list and **skips installing it** - preserving your working ROCm PyTorch.

**Quick add (single package):**
```bash
uv add transformers
```

**Verify PyTorch is still the ROCm version after installing:**
```bash
python -c "import torch; print(torch.__version__)"
# Should show: 2.9.1+rocm7.2... (the +rocm suffix is key)
```

#### Alternative: requirements.txt Workflow

For projects using `requirements.txt`, use the `resolve-dependencies.py` script:

```bash
# 1. Add packages to requirements.txt
cat > requirements.txt << EOF
transformers>=4.30.0
diffusers>=0.21.0
accelerate>=0.24.0
datasets>=2.14.0
EOF

# 2. Filter out ROCm-provided packages
python scripts/resolve-dependencies.py requirements.txt

# 3. Install filtered dependencies
uv pip install -r requirements-filtered.txt
```

The script will:
- Create `requirements-original.txt` (backup)
- Create `requirements-filtered.txt` (safe to install)
- Comment out packages already provided by ROCm
- Show which packages were skipped

#### Why Package Protection Matters

PyPI only hosts CUDA-built PyTorch wheels. If you run `pip install transformers` without protection, pip will see that transformers needs torch and install the CUDA version from PyPI - **breaking your ROCm GPU support**.

The `exclude-dependencies` list in `pyproject.toml` (or the `resolve-dependencies.py` script) prevents this by telling uv/pip to never install these packages as dependencies.

### Using with an Existing Repository

Use `setup-project-existing.sh` when you have an existing git repository (with its own `pyproject.toml`, source code, and history) and want to add ROCm devcontainer infrastructure to it. Your repository becomes the devcontainer workspace root — not a subdirectory.

#### What the scripts do

**`setup-project-existing.sh` (runs on host before opening the container):**
1. Clones your repository as a sibling directory next to the template
2. Copies devcontainer infrastructure into it (`.devcontainer/`, `scripts/`, `test-gpu.py`, `cleanup-script.sh`)
3. Replaces all `{{PLACEHOLDER}}` variables with your project name, git identity, and user info
4. Creates `models/`, `datasets/`, `.cache/` directories and updates `.gitignore`
5. Sets up `.idea/` with Python module configuration if JetBrains is selected

**`setup-environment-existing.sh` (runs inside the container automatically on first start):**
1. Fixes `/opt/venv` ownership
2. Generates `rocm-provided.txt` listing all ROCm-provided packages
3. Creates `.venv` using `/opt/venv/bin/python` (version-matched to avoid binary incompatibility)
4. Creates the `.pth` bridge so ROCm packages (torch, numpy, etc.) are importable from `.venv`
5. Adds `[tool.uv] exclude-dependencies` to your `pyproject.toml` (skipped if already present)
6. Runs `uv sync` to install your dependencies

#### The hatchling edge case

If your `pyproject.toml` uses hatchling as the build backend but doesn't have `[tool.hatch.build.targets.wheel]` configured, `uv sync` would normally fail with:

```
ValueError: Unable to determine which files to ship inside the wheel
The most likely cause of this is that there is no directory that matches the name of your project
```

`setup-environment-existing.sh` detects this automatically and uses `uv sync --no-install-project` instead. Your dependencies are installed, but the project itself is not installed as an editable package.

**To enable editable install**, add to your `pyproject.toml` and then run `uv sync`:
```toml
[tool.hatch.build.targets.wheel]
packages = ["src/your_package_name"]  # adjust to match your actual source directory
```

#### PYTHONPATH

The `devcontainer-existing.json` sets `PYTHONPATH` to the workspace root (`/workspaces/PROJECT_NAME`) rather than `/src`, since existing projects have varied source layouts. If your project follows a `src/` layout, update this in `.devcontainer/devcontainer.json` after setup:

```json
"PYTHONPATH": "/workspaces/your-project-name/src"
```

#### Re-running setup

`setup-environment-existing.sh` is safe to re-run — it skips steps that are already complete (existing `.venv`, existing `exclude-dependencies` configuration). To force a clean setup:

```bash
rm -rf .venv
uv sync  # or uv sync --no-install-project
```

### Troubleshooting

#### ImportError: "importing numpy from source directory"

If you see this error when running code with Ctrl+F5 in VSCode:

```
ImportError: Error importing numpy: you should not try to import numpy from
        its source directory; please exit the numpy source tree, and relaunch
        your python interpreter from there.
```

**Cause**: Your `.venv` was created with a different Python version than the container's `/opt/venv`. This causes binary incompatibility with compiled C extensions (numpy, torch, etc.). The misleading error message actually means the Python versions don't match.

**Diagnostic:**
```bash
# Check Python versions - they MUST match
/opt/venv/bin/python --version    # Container Python (e.g., 3.12.x)
.venv/bin/python --version         # Project venv (should also be 3.12.x)

# Check if .pth bridge points to correct Python version
find .venv -name "_rocm_bridge.pth" -exec cat {} \;
# Should show path matching your Python version (e.g., /opt/venv/lib/python3.12/site-packages)
```

**Fix:**
```bash
# Recreate venv with correct Python version
rm -rf .venv
/opt/venv/bin/python -m venv .venv

# Recreate .pth bridge (the script detects the Python version automatically)
PYTHON_VERSION=$(/opt/venv/bin/python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
echo "/opt/venv/lib/python${PYTHON_VERSION}/site-packages" > .venv/lib/python${PYTHON_VERSION}/site-packages/_rocm_bridge.pth

# Reinstall dependencies
uv sync
```

**Prevention**: The template now automatically detects and prevents Python version mismatches during setup. If you created your project from an older version of the template, consider recreating it or manually applying the fix above.

### Testing GPU Acceleration

Two test scripts are included:

**Quick sanity check (30 seconds):**
```bash
python hello-gpu.py
```

**Comprehensive benchmark (2-3 minutes):**
```bash
python test-gpu.py
```

**What it tests:**
- ✅ GPU availability and device information
- ✅ Basic tensor operations on GPU
- ✅ CPU vs GPU performance comparison (matrix multiplication)
- ✅ Small neural network training (235K params) - shows overhead on integrated GPUs
- ✅ Large neural network training (7.3M params, batch 512) - shows GPU benefits

**Sample output (AMD Radeon 8060S / Strix Halo):**
```
======================================================================
  GPU Availability Check
======================================================================
PyTorch version: 2.9.1+rocm7.2
GPU available: True

✅ GPU Count: 1

GPU 0:
  Name: AMD Radeon 8060S
  Total Memory: 96.00 GB

======================================================================
  CPU vs GPU Performance Comparison
======================================================================
Matrix size: 4096x4096
Iterations: 10

📊 Performance Summary:
   CPU: 0.1784 seconds
   GPU: 0.2831 seconds
   Speedup: 0.63x faster on GPU

⚠️  WARNING: GPU is slower than CPU!
   This may indicate a configuration issue.

======================================================================
  Small Neural Network Training Comparison
======================================================================

📊 Small Model Training Performance:
   CPU: 0.0194 seconds
   GPU: 0.1155 seconds
   Speedup: 0.17x faster on GPU

⚠️  GPU slower for small model (expected on integrated GPUs).
   Small workloads have GPU overhead > actual compute.

======================================================================
  Large Neural Network Training Comparison
======================================================================

📊 Large Model Training Performance:
   Model: 7.3M parameters, batch size 512, 50 iterations
   CPU: 2.4567 seconds
   GPU: 0.8234 seconds
   Speedup: 2.98x faster on GPU

✅ Excellent GPU acceleration! 2.98x speedup for realistic workloads.
```

**Understanding the Results:**

The test suite includes both **small** and **large** workloads to show the full picture:

**Small Model Test (235K params, batch 128):**
- ⚠️ **CPU faster** - GPU overhead dominates for tiny models
- ✅ **GPU works correctly** - This proves GPU operations function
- 💡 **Expected behavior** - Integrated GPUs need larger workloads

**Large Model Test (7.3M params, batch 512):**
- ✅ **GPU faster (2-4x speedup)** - Enough compute to overcome overhead
- ✅ **Realistic workload** - Closer to actual ML model sizes
- 🎯 **Shows GPU benefit** - This is why you have a GPU!

**Why workload size matters:**
1. **GPU overhead is fixed** (~50-100ms for kernel launch, memory setup)
2. **Small model**: Overhead > compute time → CPU wins
3. **Large model**: Compute time >> overhead → GPU wins
4. **Real ML models** (transformers, ResNets) are even larger → GPU wins big

**When GPU acceleration helps on integrated GPUs:**
- Models with 5M+ parameters (most modern ML models)
- Batch sizes 256+ samples
- Large images 512x512+ resolution
- Long training runs (hours/days)
- Inference on large models (LLMs, diffusion)

The test validates your ROCm setup is working correctly and shows GPU benefits appear at realistic model sizes.

**Quick verification:**
```bash
# Check GPU is visible (amd-smi preferred, rocm-smi still works)
amd-smi

# Quick PyTorch GPU test
python hello-gpu.py
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
