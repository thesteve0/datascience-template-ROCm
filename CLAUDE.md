Her# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a ROCm-based data science devcontainer template, ported from the CUDA version at https://github.com/thesteve0/datascience-template-CUDA. It provides development container configurations optimized for machine learning and data science work on AMD GPUs using ROCm.

### Key Objectives

1. **Port from CUDA to ROCm**: Adapt the NVIDIA PyTorch container setup to use AMD ROCm containers
2. **Incorporate Improvements**: Apply lessons learned from using the CUDA template in production
3. **Enhanced Dependency Management**: Better handling of conflicts between container-provided libraries and project requirements
4. **Multi-IDE Support**: Provide devcontainer configurations for both VSCode and JetBrains IDEs

## Architecture Overview

The template follows a fork-friendly devcontainer design with these core components:

### Core Components

- **Base Container**: Official AMD `rocm/pytorch` container (user-verified working on Strix Halo and Steam Deck)
- **Multi-IDE Devcontainers**: Full development environment configurations for both VSCode and JetBrains (created by setup script)
- **GPU Access**: Direct AMD GPU access inside containers
- **Persistent Volumes**: Separate named volumes for models, datasets, and caches to survive container rebuilds
- **Dependency Resolution**: Smart filtering of requirements to avoid conflicts with ROCm-provided packages

### Repository Structure

Template files in the repository root:
```
datascience-template-ROCm/
├── devcontainer.json          # Template for VSCode devcontainer
├── setup-project.sh           # Initial project setup script
├── setup-environment.sh       # Post-creation environment configuration
├── resolve-dependencies.py    # Filters dependencies to avoid package conflicts
├── cleanup-script.sh          # Clean up Docker resources
├── CLAUDE.md                  # This file
├── TODO.md                    # Project roadmap and task tracking
└── README.md
```

### Target Hardware

This template is specifically designed for **consumer AMD GPUs**:
- AMD Ryzen AI Max+ 395 (Strix Halo - gfx1151 architecture)
- Custom Steam Deck configurations
- Similar consumer-grade AMD APUs with integrated graphics

**Official Documentation for Consumer GPUs**:
- [Use ROCm on Radeon and Ryzen](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html)
  - ROCm 7.1 preview release for Radeon GPUs and Ryzen APUs
  - Ryzen AI Max 300 Series support (includes AI Max+ 395)
  - PyTorch support in preview for Ryzen APUs
  - Up to 128GB shared memory on Ryzen APUs

**Note**: While AMD's general ROCm documentation focuses on data center GPUs (MI300X series), the consumer GPU guide above and the `rocm/pytorch` image have been verified to work on Ryzen/Radeon hardware.

### Project Structure (created by setup-project.sh)

When `setup-project.sh` is run, it creates:
```
my-ml-project/
├── .devcontainer/
│   ├── devcontainer.json      # VSCode devcontainer configuration
│   └── ...                    # Additional VSCode-specific files
├── .idea/                     # JetBrains configuration (if selected)
├── configs/                   # Configuration files
├── scripts/                   # Utility scripts
├── src/                       # Source code
├── tests/                     # Test files
├── models/                    # Model storage (volume mount)
├── datasets/                  # Dataset storage (volume mount)
└── .cache/                    # Cache directory (volume mount)
```

## Dependency Management Philosophy

### The Problem

ROCm containers (like NVIDIA containers) come with pre-installed optimized libraries. Installing packages from PyPI that conflict with these can break GPU support or introduce version conflicts.

### The Solution

The `resolve-dependencies.py` script:
- Reads `requirements.txt` or `pyproject.toml`
- Compares against ROCm-provided packages
- Creates filtered versions that skip conflicting packages
- Installs remaining dependencies using `uv` into the system environment

This preserves ROCm optimizations while allowing additional package installation.

## ROCm-Specific Considerations

### Key Differences from CUDA

- **Base Images**: Use AMD ROCm containers (e.g., `rocm/pytorch`) instead of NVIDIA
- **GPU Detection**: Use `rocm-smi` instead of `nvidia-smi`
- **Driver Requirements**: ROCm drivers and ROCm runtime instead of NVIDIA drivers and CUDA toolkit
- **Environment Variables**: ROCm-specific variables (e.g., `HIP_VISIBLE_DEVICES` instead of `CUDA_VISIBLE_DEVICES`)
- **PyTorch Differences**: ROCm PyTorch builds may have different package names and dependencies
- **Container Runtime**: May require additional Docker configuration for ROCm GPU access

### Hardware Requirements

**Supported Consumer Hardware**:
- Ryzen AI Max 300 Series (includes AI Max+ 395 Strix Halo)
- Radeon RX 7000 Series (RDNA 3) and RX 9000 Series (RDNA 4)
- Custom configurations (e.g., Steam Deck with custom Ryzen chips)

**System Requirements**:
- Linux host with ROCm 7.1+ drivers installed (preview release for consumer GPUs)
- Docker with proper ROCm container support
- Recommended: 32GB+ RAM, 1TB NVMe SSD
- Check [ROCm Radeon/Ryzen compatibility matrix](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html) for your specific hardware

## IDE Support

### VSCode

- Configuration in `.devcontainer/devcontainer.json` (created by setup script)
- Automatically detects and prompts to reopen in container
- Extensions auto-installed (Python, Jupyter, linting, formatting)
- Integrated terminal runs inside container with GPU access

### JetBrains (PyCharm, etc.)

- Configuration in `.idea/` directory (created by setup script)
- Requires JetBrains Gateway or JetBrains IDE with devcontainer support
- Shares same base container and volumes as VSCode setup
- IDE-specific configurations maintained separately

Both IDE configurations use the same:
- Base ROCm container
- Persistent volumes
- Dependency management approach
- Setup scripts

## Development Workflow

### Initial Setup

1. Run `setup-project.sh` to initialize the project structure and create `.devcontainer/` directory
2. Choose your IDE:
   - **VSCode**: Open project, reopen in container when prompted
   - **JetBrains**: Use Gateway or IDE's devcontainer feature
3. Container builds and runs `setup-environment.sh` automatically

### Working with Dependencies

1. Add packages to `requirements.txt` or `pyproject.toml`
2. Run `resolve-dependencies.py` to filter conflicts
3. Install using `uv pip install` with filtered file
4. Verify GPU access still works with `rocm-smi` or PyTorch GPU check

### Verifying GPU Access

```bash
# Check GPU visibility
rocm-smi

# Test PyTorch GPU access
python -c "import torch; print(f'GPU available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}')"
```

### External Repository Integration

The template supports cloning external projects into the workspace while maintaining the devcontainer benefits.

## Known Considerations and Challenges

1. **Base Container Decision**: ✅ Decided to use `rocm/pytorch` (user-verified on target hardware)
2. **Consumer GPU Documentation Gap**: AMD docs focus on MI300X data center GPUs, but `rocm/pytorch` works on consumer hardware - will document real-world results
3. **Package Name Differences**: ROCm package names may differ from CUDA versions
4. **Library Compatibility**: Some ML libraries have better CUDA than ROCm support - will test and document
5. **gfx1151-Specific Issues**: Some features may have limitations (hipBLASLt, AOTriton) - will document workarounds
6. **JetBrains ROCm Support**: May require additional configuration vs VSCode

## Docker Image Research Findings

Comparison of AMD ROCm Docker images:

- **rocm/pytorch**: General-purpose, inference-focused, actively maintained ✅ **SELECTED**
  - Works on Strix Halo and Steam Deck (user-verified)
  - Handles both training and inference
  - ROCm 7.1.0 available

- **rocm/pytorch-training**: Training-focused, ⚠️ being deprecated in favor of primus
  - Not recommended for new projects

- **rocm/primus**: New unified training framework
  - Data center GPUs only (MI300X, MI325X, etc.)
  - Overkill for single-GPU consumer hardware
  - Designed for multi-node distributed training

## Current Status

Repository is in initial setup phase with base image decision made. Next steps are to port scripts and configurations from the CUDA template.

## Important Resources

### Official AMD Documentation
- **[ROCm for Radeon and Ryzen GPUs](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html)** - Primary documentation for consumer GPU support
  - ROCm 7.1 preview release notes
  - PyTorch installation for Ryzen APUs
  - Compatibility matrices for Radeon/Ryzen hardware
  - Framework support (PyTorch, TensorFlow, JAX, ONNX Runtime)

- **[ROCm General Documentation](https://rocm.docs.amd.com/)** - Data center GPU focused (MI300X series)
  - Training and inference guides
  - Container documentation
  - Framework compatibility matrices

### Base Template
- **[CUDA Template Repository](https://github.com/thesteve0/datascience-template-CUDA)** - Original NVIDIA-based template being ported

### Community Resources
- AMD Developer Discord (for consumer GPU support questions)
- [ROCm GitHub Issues](https://github.com/ROCm/ROCm/issues) - For reporting bugs and tracking gfx1151-specific issues