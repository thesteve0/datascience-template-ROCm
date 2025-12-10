# ROCm PyTorch ML DevContainer Template

A DevContainer template for PyTorch machine learning development on AMD GPUs using ROCm. Optimized for consumer AMD hardware (Ryzen AI, Radeon RX series) with support for both VSCode and JetBrains IDEs.

**Ported from:** [datascience-template-CUDA](https://github.com/thesteve0/datascience-template-CUDA)

## Key Features

- **AMD ROCm GPU Support** - Full GPU acceleration for PyTorch on consumer AMD hardware
- **Intelligent Dependency Management** - Automatically resolves conflicts with ROCm-provided packages
- **Multi-IDE Support** - VSCode and JetBrains configurations
- **Persistent Storage** - Named volumes for models, datasets, and caches survive container rebuilds
- **External Project Integration** - Clone and work with existing repositories seamlessly
- **Docker & Podman** - Works with both container runtimes

## ⚠️ Security Notice: Development Only

**This template is designed for local development environments, NOT production deployments.**

The devcontainer user has **passwordless sudo access** (standard for devcontainers) to simplify package installation and system configuration. This is appropriate for single-user development containers but creates significant security risks in production.

**For production ML deployments:**
- Use separate production-focused container images
- Run as non-root user without sudo privileges
- Implement read-only root filesystems where possible
- Follow the principle of least privilege
- Use proper secrets management (not environment variables)
- Apply container security scanning and hardening

This template prioritizes **developer experience** for rapid ML experimentation and development. Production containers require different security trade-offs.

## Supported Hardware

This template is designed for **consumer AMD GPUs**:

### Tested Hardware
- ✅ AMD Ryzen AI Max+ 395 (Strix Halo - gfx1151)
- ✅ Custom Steam Deck configurations
- ✅ Radeon RX 7000 Series (RDNA 3)
- ✅ Radeon RX 9000 Series (RDNA 4)

### System Requirements
- **OS:** Linux with ROCm 7.1+ drivers
- **RAM:** 32GB+ recommended
- **Storage:** 1TB NVMe SSD recommended (models and datasets are large)
- **Container Runtime:** Docker or Podman with ROCm support

**Note:** This template targets consumer GPUs. For AMD data center GPUs (MI300X series), see [AMD's official ROCm documentation](https://rocm.docs.amd.com/).

## Prerequisites

### 1. Install ROCm Drivers

Follow the official AMD guide for consumer GPUs:
- [ROCm for Radeon and Ryzen GPUs](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html)

For Ryzen AI Max+ 395 (Strix Halo) or similar consumer hardware:
```bash
# Check AMD GPU is visible
lspci | grep -i amd

# Verify ROCm installation
rocm-smi

# Test PyTorch ROCm (after installing container runtime)
docker run -it --device=/dev/kfd --device=/dev/dri \
    rocm/pytorch:latest python -c "import torch; print(f'ROCm available: {torch.cuda.is_available()}')"
```

### 2. Install Container Runtime

**Docker:**
```bash
# Install Docker (Fedora/RHEL)
sudo dnf install docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

**Podman (alternative):**
```bash
# Install Podman (Fedora/RHEL)
sudo dnf install podman

# Configure VSCode to use Podman instead of Docker
# Add to VSCode settings.json:
# "dev.containers.dockerPath": "podman"
```

**Note:** VSCode Dev Containers automatically handles Podman's user namespace mapping with `--userns=keep-id`. No changes to the devcontainer configuration are needed.

### 3. Install IDE

**VSCode:**
- Install [VSCode](https://code.visualstudio.com/)
- Install "Dev Containers" extension

**JetBrains (PyCharm, etc.):**
- Install [JetBrains Gateway](https://www.jetbrains.com/remote-development/gateway/) or PyCharm Professional
- Devcontainer support requires recent versions

## Quick Start

### Option A: Create New Standalone Project

```bash
# 1. Clone this template
git clone https://github.com/YOUR_USERNAME/datascience-template-ROCm.git my-ml-project
cd my-ml-project

# 2. Run setup (select IDE when prompted)
./setup-project.sh

# 3. Open in VSCode
code .

# 4. When prompted, click "Reopen in Container"
#    (First build takes 5-10 minutes)

# 5. Inside container, verify GPU access
rocm-smi
python test-gpu.py  # Comprehensive GPU test with performance benchmarks

# 6. Install your dependencies
echo "transformers>=4.30.0" > requirements.txt
python scripts/resolve-dependencies.py requirements.txt
uv pip install -r requirements-filtered.txt
```

### Option B: Integrate Existing Repository

```bash
# 1. Clone this template
git clone https://github.com/YOUR_USERNAME/datascience-template-ROCm.git my-project-wrapper
cd my-project-wrapper

# 2. Setup with external repo
./setup-project.sh --clone-repo https://github.com/username/existing-ml-project.git

# 3. Open in VSCode and reopen in container
code .

# 4. The external repo is now accessible at ./existing-ml-project/
```

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
├── test-gpu.py                 # GPU acceleration test script
├── setup-project.sh            # Project setup script
└── cleanup-script.sh           # Cleanup utility
```

### Managing Dependencies

The `resolve-dependencies.py` script prevents conflicts with ROCm-provided packages:

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

#### Python Package Management

AMD's ROCm container comes with a **pre-configured virtual environment at `/opt/venv`** that:
- Isolates ROCm-optimized PyTorch and ML packages from system Python
- Is activated by default (no manual activation needed)
- Includes the `uv` package manager (faster than pip)
- Allows `pip install` and `uv pip install` to work directly

The setup script automatically adjusts ownership of `/opt/venv` so you can install packages without sudo.

This design is ideal for single-project devcontainers - you get the benefits of isolation without manual venv management.

**Installing packages:**
```bash
# Using pip (after filtering)
pip install -r requirements-filtered.txt

# Using uv (faster, recommended)
uv pip install -r requirements-filtered.txt
```

Note: No need for `--system` flag with uv since we're already in AMD's pre-configured venv.

### Testing GPU Acceleration

A comprehensive test script is included to verify GPU acceleration:

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
PyTorch version: 2.9.1+rocm7.1.0.git351ff442
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
# Check GPU is visible
rocm-smi

# Quick PyTorch GPU test
python -c "import torch; print(f'GPU: {torch.cuda.is_available()}')"
```

### IDE Selection

You can configure for VSCode, JetBrains, or both:

```bash
# Interactive selection
./setup-project.sh

# Command-line selection
./setup-project.sh --ide vscode
./setup-project.sh --ide jetbrains
./setup-project.sh --ide both
```

### Persistent Volumes

The template uses Docker/Podman named volumes for data that should survive container rebuilds:

- `<project>-models` → `./models/` - Trained models and checkpoints
- `<project>-datasets` → `./datasets/` - Training and evaluation data
- `<project>-cache-hf` → `.cache/huggingface/` - HuggingFace models cache
- `<project>-cache-torch` → `.cache/torch/` - PyTorch models cache

To view volumes:
```bash
docker volume ls | grep my-ml-project
```

### Cleanup

Stop container but keep volumes:
```bash
./cleanup-script.sh
```

Full cleanup (deletes all data):
```bash
docker volume rm my-ml-project-models \
                 my-ml-project-datasets \
                 my-ml-project-cache-hf \
                 my-ml-project-cache-torch
```

## ROCm-Specific Configuration

### Environment Variables

The devcontainer sets these ROCm-specific variables:

```json
{
  "HIP_VISIBLE_DEVICES": "0",              // Which GPU to use
  "HSA_OVERRIDE_GFX_VERSION": "11.0.0",    // gfx compatibility override
  "ROCM_HOME": "/opt/rocm"                 // ROCm installation path
}
```

### GPU Access

The container needs access to ROCm devices:

```json
"runArgs": [
  "--device=/dev/kfd",          // ROCm compute device
  "--device=/dev/dri",          // GPU direct rendering
  "--group-add=video",          // Video group for GPU access
  "--ipc=host",                 // Shared memory
  "--cap-add=SYS_PTRACE",       // Debugging support
  "--security-opt=seccomp=unconfined"
]
```

### Base Container

Using official AMD ROCm PyTorch container:
```
rocm/pytorch:rocm7.1-py3.11-pytorch-2.6.0-ubuntu22.04
```

Verified working on:
- Ryzen AI Max+ 395 (Strix Halo)
- Custom Steam Deck builds

## Troubleshooting

### GPU Not Detected

```bash
# Check GPU is visible to system
rocm-smi

# Check GPU is visible to container
docker run -it --device=/dev/kfd --device=/dev/dri \
    rocm/pytorch:latest rocm-smi

# Verify PyTorch can see GPU
python -c "import torch; print(torch.cuda.is_available())"

# Run comprehensive GPU test
python test-gpu.py
```

### Permission Errors

The devcontainer creates a user matching your host UID/GID. If you get permission errors:

```bash
# Check ownership
ls -la models/ datasets/

# Fix if needed (inside container)
sudo chown -R $(whoami):$(whoami) /workspaces/my-ml-project
```

### Package Installation Failures

If `uv pip install` fails:

```bash
# 1. Verify filtered file was created
cat requirements-filtered.txt

# 2. Install without filtering (not recommended)
uv pip install -r requirements.txt

# 3. Check for conflicts
pip list | grep torch
```

### ROCm Version Mismatch

If you see architecture warnings (gfx1151, etc.):

```bash
# Override GFX version (already set in devcontainer)
export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Or edit .devcontainer/devcontainer.json
# and change HSA_OVERRIDE_GFX_VERSION
```

### Container Won't Start

```bash
# Check Docker daemon
sudo systemctl status docker

# Check logs
docker logs <container-id>

# Rebuild container
# VSCode: Ctrl+Shift+P → "Dev Containers: Rebuild Container"
```

## Differences from CUDA Template

| Feature | CUDA Template | ROCm Template |
|---------|--------------|---------------|
| Base Container | `nvcr.io/nvidia/pytorch` | `rocm/pytorch` |
| GPU Access | `--gpus=all` | `--device=/dev/kfd --device=/dev/dri` |
| GPU Tool | `nvidia-smi` | `rocm-smi` |
| GPU Env Var | `CUDA_VISIBLE_DEVICES` | `HIP_VISIBLE_DEVICES` |
| Package List | `nvidia-provided.txt` | `rocm-provided.txt` |
| IDE Support | VSCode only | VSCode + JetBrains |
| Runtime | Docker only | Docker or Podman |
| Permissions | Group-based sharing (UID 2112 + shared GID) | Direct UID matching (deletes ubuntu user, VSCode auto-adjusts UID) |

## Resources

### Official Documentation
- [ROCm for Radeon/Ryzen GPUs](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/)
- [ROCm PyTorch Documentation](https://rocm.docs.amd.com/en/latest/how-to/pytorch-install/pytorch-install.html)
- [AMD ROCm Containers](https://hub.docker.com/u/rocm)

### Community
- AMD Developer Discord
- [ROCm GitHub Issues](https://github.com/ROCm/ROCm/issues)

### Related Projects
- [Original CUDA Template](https://github.com/thesteve0/datascience-template-CUDA)

## Contributing

Issues and pull requests welcome! This template is designed to be fork-friendly.

## License

See [LICENSE](LICENSE) file.

## Acknowledgments

- Based on [datascience-template-CUDA](https://github.com/thesteve0/datascience-template-CUDA)
- Tested on AMD Ryzen AI Max+ 395 (Strix Halo)
- ROCm PyTorch containers provided by AMD