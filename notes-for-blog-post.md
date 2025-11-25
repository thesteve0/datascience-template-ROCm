# Blog Post Notes: ROCm PyTorch Container Journey

*Research conducted for porting CUDA devcontainer template to ROCm for consumer AMD GPUs*

## Project Context

Porting https://github.com/thesteve0/datascience-template-CUDA from NVIDIA CUDA to AMD ROCm for use with:
- AMD Ryzen AI Max+ 395 (Strix Halo - gfx1151 architecture)
- Custom Steam Deck with Ryzen chips
- Consumer AMD GPUs in general

## The Container Image Research Journey

### Starting Point: Finding Official AMD ROCm Containers

AMD hosts their official ROCm Docker images at: https://hub.docker.com/u/rocm

When I started researching, I found three main PyTorch-related containers:

1. **rocm/pytorch** - https://hub.docker.com/r/rocm/pytorch
2. **rocm/pytorch-training** - https://hub.docker.com/r/rocm/pytorch-training
3. **rocm/primus** - https://hub.docker.com/r/rocm/primus

### The Documentation Deep Dive

#### rocm/pytorch-training
First looked at the pytorch-training documentation:
- **Docs**: https://rocm.docs.amd.com/en/latest/how-to/rocm-for-ai/training/benchmark-docker/pytorch-training.html
- **Purpose**: Training-optimized environment
- **Contents** (v7.0.0):
  - PyTorch 2.9.0
  - Transformer Engine 2.2.0
  - Flash Attention 2.8.3
  - RCCL 2.26.6
- **Target Hardware**: AMD Instinct MI325X and MI300X (data center GPUs)
- **⚠️ Critical Discovery**: "The rocm/pytorch-training Docker Hub registry will be deprecated soon in favor of rocm/primus"

So this image is being phased out - not a good choice for a new template.

#### rocm/primus
Next investigated the new training framework:
- **Docs**: https://rocm.docs.amd.com/en/latest/how-to/rocm-for-ai/training/benchmark-docker/primus-pytorch.html
- **Purpose**: Unified, lightweight LLM training framework (replaces pytorch-training)
- **Key Features**:
  - YAML-based configuration
  - Multi-backend support (Megatron-LM, TorchTitan planned)
  - Preflight validation (cluster connectivity, GPU diagnostics)
  - Primus Turbo optimizations
- **Target Hardware**: MI355X, MI350X, MI325X, MI300X (data center only)
- **Contents** (v25.9):
  - ROCm 7.0.0
  - PyTorch 2.9.0
  - Primus 0.3.0

**Assessment**: This is overkill for consumer GPUs. It's designed for multi-node, multi-GPU data center deployments with advanced parallelism strategies. Not appropriate for a single Strix Halo laptop or Steam Deck.

#### rocm/pytorch
Finally looked at the general PyTorch image:
- **Docs**: https://rocm.docs.amd.com/en/latest/how-to/rocm-for-ai/inference/benchmark-docker/pytorch-inference.html
- **Purpose**: General-purpose PyTorch environment (inference-focused in docs)
- **Current Version**: ROCm 7.1.0 available
- **Key Features**:
  - Float8 support
  - FlashAttention v3 integration
  - Quarterly releases alongside ROCm updates
- **Target Hardware**: AMD Instinct MI300X Series (per documentation)

### The Documentation Problem

**Here's the critical issue I discovered**: All the official AMD documentation focuses almost exclusively on **data center GPUs** (MI300X series). Reading through the docs, you'd think these containers only work on expensive enterprise hardware.

But there's a separate documentation site: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html

This is the **ROCm for Radeon and Ryzen GPUs** guide, which reveals:
- ROCm 7.1 is a **preview release** for consumer GPUs
- Explicit support for Ryzen AI Max 300 Series (includes my AI Max+ 395!)
- PyTorch support in preview for Ryzen APUs
- Support for Radeon RX 7000/9000 Series
- Up to 128GB shared memory on Ryzen APUs

**Key learning**: AMD has two separate documentation tracks - one for data center, one for consumer GPUs. Easy to miss the consumer GPU docs.

### Reality Check: What Actually Works

Despite the documentation saying these containers are for MI300X data center GPUs, I had already been using `rocm/pytorch` successfully on:
- My Framework laptop with Ryzen AI Max+ 395 (Strix Halo)
- Custom Steam Deck configuration

**This is the gap between documentation and reality** - the images work fine on consumer hardware, but the docs don't make this clear.

### Community Solutions Exploration

While researching, I also found several **community-built** Docker images specifically targeting consumer AMD GPUs:

1. **scottt/TheRock** - `docker.io/scottt/therock:pytorch-vision-dev-f41`
   - Bleeding-edge ROCm builds
   - Explicitly supports gfx1151 (Strix Halo)
   - Community discussion: https://github.com/ROCm/TheRock/discussions/244

2. **weiziqian/rocm_pytorch_docker_gfx1151**
   - GitHub: https://github.com/weiziqian/rocm_pytorch_docker_gfx1151
   - Ubuntu 24.04 + ROCm 7.0 + PyTorch 2.7.1
   - Built specifically for Strix Halo

3. **kyuz0/amd-strix-halo-vllm-toolboxes**
   - GitHub: https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes
   - Focused on vLLM serving

4. **gdkrmr/ollama-rocm-docker-gfx1151**
   - GitHub: https://github.com/gdkrmr/ollama-rocm-docker-gfx1151
   - Ollama support for Strix Halo

These exist because the official images don't explicitly mention gfx1151 support, so the community filled the gap.

### The Decision: rocm/pytorch

**Final choice**: Use official `rocm/pytorch` image

**Reasoning**:
1. ✅ **Real-world validation**: Already working on my Strix Halo and Steam Deck
2. ✅ **Unified workloads**: Handles both training and inference (my requirement)
3. ✅ **Official AMD support**: Better long-term stability, regular updates
4. ✅ **Not deprecated**: Unlike pytorch-training, this is actively maintained
5. ✅ **AMD contacts**: Since I have AMD contacts, prefer official images for issue escalation
6. ✅ **Appropriate scope**: Not overkill like primus (which targets multi-GPU clusters)

**Why NOT the others**:
- `rocm/pytorch-training`: Being deprecated, unclear future
- `rocm/primus`: Designed for data center multi-node training, excessive complexity
- Community images: Prefer official for long-term support, but they exist as fallback

## Key Insights for Blog Post

### 1. Documentation Fragmentation
AMD's ROCm documentation is split between data center (MI300X) and consumer (Radeon/Ryzen) with the consumer docs being harder to find. This creates confusion about what actually works on consumer hardware.

### 2. Documentation vs. Reality Gap
The main ROCm container docs focus on data center GPUs, but `rocm/pytorch` works fine on consumer hardware. Don't let the documentation scare you away from trying it on your Ryzen APU or Radeon GPU.

### 3. gfx1151 Support Status
Strix Halo (gfx1151) is officially supported in ROCm 7.1 preview, but:
- Official containers don't explicitly mention it
- Some features have limitations (hipBLASLt, AOTriton)
- Community has created workarounds and custom builds
- Real-world testing shows it works better than docs suggest

### 4. Consumer GPU vs Data Center Focus
The ML/AI ecosystem (including ROCm) is heavily focused on data center deployments. Consumer GPU users need to:
- Look for the specific Radeon/Ryzen documentation
- Test things despite documentation gaps
- Join community channels (AMD Developer Discord)
- Share real-world experiences to help others

### 5. Preview Release Caveat
ROCm 7.1 for consumer GPUs is marked as "preview" - this means:
- PyTorch support is still maturing
- Some rough edges expected
- Active development and improvements ongoing
- Perfect for development templates, but set realistic expectations

## Technical Details Worth Noting

### ROCm vs CUDA Differences
- **GPU tool**: `rocm-smi` instead of `nvidia-smi`
- **Environment variables**: `HIP_VISIBLE_DEVICES` instead of `CUDA_VISIBLE_DEVICES`
- **Architecture**: gfx1151 (Strix Halo) vs CUDA compute capability
- **Memory**: Shared system memory (up to 128GB on Ryzen APUs) vs dedicated VRAM

### Container Image Tags Strategy
- `rocm/pytorch:latest-release` - Production stability (recommended starting point)
- `rocm/pytorch:latest-release-preview` - Newer PyTorch, limited testing
- `rocm/pytorch:latest` - Latest tested release
- Pin to specific versions after validation (e.g., ROCm 7.1.0)

### Dependency Management Challenge
ROCm containers come with pre-installed optimized libraries. Installing conflicting packages from PyPI can break GPU support. Solution: filter dependencies before installation (covered in resolve-dependencies.py).

## Resources for Blog Post

### Official AMD Resources
- ROCm Docker Hub: https://hub.docker.com/u/rocm
- ROCm for Radeon/Ryzen: https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html
- ROCm General Docs: https://rocm.docs.amd.com/
- PyTorch Training Docs: https://rocm.docs.amd.com/en/latest/how-to/rocm-for-ai/training/benchmark-docker/pytorch-training.html
- Primus Framework: https://rocm.blogs.amd.com/software-tools-optimization/primus/README.html

### Community Resources
- ROCm GitHub: https://github.com/ROCm/ROCm
- TheRock Discussions: https://github.com/ROCm/TheRock/discussions
- Community Docker builds for gfx1151 support

### Hardware Info
- Strix Halo Performance: https://www.phoronix.com/review/amd-strix-halo-rocm-benchmarks
- Ryzen AI Max+ 395: https://www.amd.com/en/products/processors/laptop/ryzen/ai-300-series/amd-ryzen-ai-max-plus-395.html

## Blog Post Angle Ideas

1. **"The Consumer GPU Gap"**: How AMD's documentation focuses on data center but the tools work for consumers
2. **"ROCm Container Confusion"**: Navigating multiple PyTorch images and making the right choice
3. **"Strix Halo ML Journey"**: Real-world ML development on a consumer AMD APU
4. **"CUDA to ROCm Port"**: Lessons learned adapting NVIDIA workflows to AMD
5. **"Preview Release Reality"**: What "preview" means for ROCm 7.1 on consumer GPUs

## Narrative Arc for Blog Post

1. **Setup**: Wanted to port CUDA devcontainer to ROCm for Strix Halo laptop
2. **Confusion**: Found multiple PyTorch containers, documentation focused on MI300X
3. **Discovery**: Found separate consumer GPU docs, learned about preview status
4. **Validation**: Realized I'd already been using rocm/pytorch successfully
5. **Decision**: Chose rocm/pytorch over deprecated/overkill alternatives
6. **Learning**: Gap between documentation and reality, importance of real-world testing
7. **Outcome**: Template will document consumer GPU reality, help others avoid confusion

## Quotes to Consider

*"The rocm/pytorch-training Docker Hub registry will be deprecated soon in favor of rocm/primus"* - Shows ecosystem evolution

*"ROCm 7.1 is a preview release featuring updates for Radeon and Ryzen on Linux usecases"* - Consumer GPU support is coming but still maturing

*"While AMD's official documentation focuses on data center GPUs (MI300X series), the rocm/pytorch image has been verified to work on consumer hardware"* - My key insight

## Call to Action Ideas

- Share your own ROCm consumer GPU experiences
- Join AMD Developer Discord
- Report issues to help improve consumer GPU support
- Try the template when it's ready
- Contribute real-world testing results

## Future Blog Post Topics

- Part 2: Porting the setup scripts and dependency management
- Part 3: Real-world ML workflows on Strix Halo
- Part 4: Performance comparison vs CUDA on similar-spec hardware
- Part 5: Multi-IDE setup (VSCode + JetBrains with ROCm)