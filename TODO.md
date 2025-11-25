# Project TODO

This file tracks the roadmap for porting the CUDA data science template to ROCm with improvements.

## Phase 1: Core Template Files Port

### Setup Scripts
- [ ] Port `setup-project.sh` from CUDA template
  - [ ] Adapt for ROCm-specific directory structure
  - [ ] Add JetBrains IDE option during setup
  - [ ] Update placeholder variables for ROCm
- [ ] Port `setup-environment.sh` from CUDA template
  - [ ] Update for ROCm environment variables
  - [ ] Configure HIP/ROCm paths
  - [ ] Set up ROCm-specific cache directories
- [ ] Port `cleanup-script.sh` from CUDA template
  - [ ] Update volume names for ROCm project
  - [ ] Ensure compatibility with both IDE configurations

### Dependency Management
- [ ] Port `resolve-dependencies.py` from CUDA template
  - [ ] Identify ROCm PyTorch pre-installed packages
  - [ ] Create ROCm package conflict list
  - [ ] Test filtering with common ML libraries (transformers, diffusers, etc.)
  - [ ] Handle ROCm-specific package names (torch vs torch-rocm)

## Phase 2: DevContainer Configurations

### ROCm Container Research
- [x] Research available ROCm PyTorch containers
  - [x] Official AMD ROCm containers (rocm/pytorch, rocm/pytorch-training, rocm/primus)
  - [x] Community PyTorch-ROCm images (TheRock, weiziqian builds)
  - [x] Version compatibility matrix reviewed
- [x] Select appropriate base container image → **Decision: rocm/pytorch**
  - User-verified working on Strix Halo and Steam Deck
  - Handles both training and inference
  - Actively maintained, not deprecated
- [ ] Test GPU access in selected container (needs implementation)
- [ ] Document exact ROCm version and PyTorch version used

### VSCode DevContainer
- [ ] Port `devcontainer.json` template
  - [ ] Update base image to ROCm container
  - [ ] Configure ROCm GPU runtime arguments
  - [ ] Update environment variables (CUDA → HIP/ROCm)
  - [ ] Configure persistent volumes (models, datasets, cache)
  - [ ] Add VSCode extensions for Python/ML development
  - [ ] Configure port forwarding (TensorBoard, Jupyter, etc.)
- [ ] Test VSCode devcontainer functionality
  - [ ] Container builds successfully
  - [ ] GPU access works (`rocm-smi` visible)
  - [ ] PyTorch can access GPU
  - [ ] Volumes persist across rebuilds

### JetBrains DevContainer
- [ ] Research JetBrains devcontainer format
  - [ ] Determine if using dev container spec or Docker Compose
  - [ ] Review JetBrains Gateway requirements
- [ ] Create JetBrains configuration
  - [ ] Same base ROCm container as VSCode
  - [ ] Same volume mounts
  - [ ] Python interpreter configuration
  - [ ] Run configurations for common tasks
- [ ] Test JetBrains devcontainer functionality
  - [ ] PyCharm/Gateway can connect
  - [ ] GPU access works
  - [ ] Remote development is smooth

## Phase 3: Improvements Over CUDA Template

### Enhanced Dependency Management
- [ ] Improve conflict detection algorithm
- [ ] Add support for poetry/pdm/pixi in addition to requirements.txt
- [ ] Better error messages when conflicts detected
- [ ] Optional: Create pre-built ROCm package index

### Documentation Improvements
- [ ] Write comprehensive README.md
  - [ ] Hardware requirements
  - [ ] ROCm driver installation guide
  - [ ] Quick start guide
  - [ ] Troubleshooting section
- [ ] Add example workflows
  - [ ] Fine-tuning example
  - [ ] Inference example
  - [ ] Multi-GPU example (future)
- [ ] Document differences from CUDA template
- [ ] Add ROCm-specific gotchas and tips

### User Experience Improvements
- [ ] Better setup script error handling
- [ ] Automated GPU capability detection
- [ ] Health check scripts
- [ ] Performance tuning guidelines

## Phase 4: Testing & Validation

### Basic Functionality Tests
- [ ] Test setup-project.sh creates correct structure
- [ ] Test VSCode devcontainer workflow end-to-end
- [ ] Test JetBrains devcontainer workflow end-to-end
- [ ] Test dependency resolution with various packages

### ML Workflow Tests
- [ ] Test PyTorch training on GPU
- [ ] Test common libraries (transformers, diffusers, etc.)
- [ ] Test Jupyter notebook execution
- [ ] Test data loading and preprocessing
- [ ] Test model checkpointing to persistent volumes

### Edge Cases
- [ ] Test with no GPU available (graceful degradation)
- [ ] Test with multiple AMD GPUs
- [ ] Test external repository integration
- [ ] Test cleanup and recreation of containers

## Phase 5: Documentation & Release

### Final Documentation
- [ ] Complete README.md with all features
- [ ] Update CLAUDE.md with final architecture
- [ ] Add CONTRIBUTING.md if accepting contributions
- [ ] Create examples directory with sample projects

### Release Preparation
- [ ] Verify all TODO items completed
- [ ] Test on fresh system
- [ ] Create release notes
- [ ] Tag initial release version

## Future Enhancements (Post-Release)

- [ ] Multi-GPU support and configuration
- [ ] Additional framework support (JAX, TensorFlow)
- [ ] CI/CD examples for model training
- [ ] Integration with MLflow or Weights & Biases
- [ ] Windows WSL2 support documentation
- [ ] Pre-built container images for faster startup
- [ ] Podman support as alternative to Docker (nice to have)
  - [ ] Test VSCode devcontainer with Podman
  - [ ] Test JetBrains Gateway/devcontainer with Podman
  - [ ] Document Podman setup and limitations
  - Note: IDE support for Podman is less polished than Docker; don't over-invest time

## Notes

- **Target Hardware**: Consumer AMD GPUs (Strix Halo gfx1151, Steam Deck) - NOT data center GPUs
- **Base Image Decision**: Using `rocm/pytorch` (user-verified working on target hardware)
- **Documentation Philosophy**: Document real-world testing results, note gaps between AMD docs and consumer GPU reality
- Focus on getting basic VSCode + ROCm working first
- JetBrains support can be added in parallel or after VSCode is stable
- Test frequently with actual ML workloads, not just toy examples
- Document any ROCm quirks or workarounds discovered during development
- Maintain feedback loop with AMD contacts for issues discovered