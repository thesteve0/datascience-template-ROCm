# Project TODO

This file tracks the roadmap for porting the CUDA data science template to ROCm with improvements.

- [x] The new CLAUDE.md should explicitly state that we only use uv for project dependencies. When using Claude in the new project it should never suggest 'pip install...', it should always be 'uv add'. Same for all the pip commands.

There are a couple of things we need to handle right away
- [x] How to take the code and then run it on NVIDIA accelerators. AMD and NVIDIA PyTorch both look to see if 'cuda' is present so the code should just work, but we need to test that. This is similar to the instructions we needed to write on how to take this code to production. → See NVIDIA-TRAINING-PRODUCTION.md
- [x] How to back up your devcontainer environment. Before tasks that need a rebuild of the container, how do I back up the existing container so I can just roll back if the rebuild is broken → See DEVCONTAINER-SNAPSHOT.md
- [x] How to snapshot the current state of the devcontainer and share it with other users on AMD accelerators → See DEVCONTAINER-SNAPSHOT.md

### Documentation Improvements
- [ ] Write comprehensive README.md
  - [ ] Hardware requirements
  - [ ] ROCm driver installation guide
  - [ ] Quick start guide
  - [ ] Troubleshooting section
- [ ] Add example workflows
  - [ ] Fine-tuning example
  - [ ] Inference example
  - [ ] Multi1
## Phase 4: Testing & Validation

### Basic Functionality Tests
- [x] Test setup-project.sh creates correct structure
- [ ] Test VSCode devcontainer workflow end-to-end (requires running container)
- [ ] Test JetBrains devcontainer workflow end-to-end (requires JetBrains setup)
- [x] Test dependency resolution with various packages (mock test passed)

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