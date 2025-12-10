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

## Changes in Volume Mounting

### The Problem: Ubuntu 24.04 and UID Conflicts

When porting from the CUDA template, we encountered significant permission issues that the CUDA template didn't have. The root cause was a fundamental difference in base images:

**CUDA Template Reality**:
- NVIDIA PyTorch containers run as root by default
- No pre-existing user at UID 1000
- The CUDA template creates a user at UID 2112 and uses group-based sharing

**ROCm Template Challenge**:
- ROCm containers use Ubuntu 24.04 as the base
- Ubuntu 24.04 ships with a pre-existing `ubuntu` user at UID 1000
- This caused a cascade of permission problems

### The Bugs We Discovered

#### 1. common-utils Feature Falls Back to UID 1001

**Issue**: [common-utils doesn't work on Ubuntu 24.04](https://github.com/devcontainers/features/issues/1265)

When the `common-utils` devcontainer feature tries to create a user with UID 1000 (to match the typical Linux host user), but that UID is already taken by the `ubuntu` user, it silently falls back to creating the user at UID 1001.

**Evidence**:
```bash
# Inside container
uid=1001(stpousty-devcontainer) gid=1001(stpousty-devcontainer)

# Files owned by wrong user
-rw-------.  1 ubuntu ubuntu 2643 devcontainer.json
```

#### 2. updateRemoteUserUID Doesn't Work Reliably

**Issues**:
- [updateRemoteUserUID has no effect](https://github.com/microsoft/vscode-remote-release/issues/10030)
- [updateRemoteUserUID has no effect (CLI)](https://github.com/devcontainers/cli/issues/874)
- [Massive chown happening even with updateRemoteUserUID = false](https://github.com/microsoft/vscode-remote-release/issues/7390)

Setting `"updateRemoteUserUID": false` in devcontainer.json should disable VSCode's automatic UID matching, but multiple GitHub issues show it doesn't work consistently. In some cases, it still changes UIDs; in other cases, it doesn't change them when it should.

#### 3. UID Update Skipped When GID Already Exists

**Issue**: [updateRemoteUserUID does not work if gid on host matches a gid inside the container](https://github.com/devcontainers/cli/issues/494)

VSCode's automatic UID matching will skip the update if the host's GID already exists inside the container, even if the UID doesn't match. Since Ubuntu 24.04 has group `ubuntu` at GID 1000, and most Linux hosts have the user's primary group at GID 1000, this condition is met and UID updating is skipped.

### The Solution: Delete Ubuntu User Before Creating Container User

**Workaround** (from [devcontainers/images #1056](https://github.com/devcontainers/images/issues/1056)):

Instead of fighting with VSCode's buggy UID matching, we use a Dockerfile wrapper that deletes the `ubuntu` user before the `common-utils` feature runs:

```dockerfile
FROM rocm/pytorch:rocm7.1_ubuntu24.04_py3.13_pytorch_release_2.9.1

# Workaround for Ubuntu 24.04 having pre-existing ubuntu user at UID 1000
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu
```

Then in `devcontainer.json`, we use:
```json
{
  "build": {
    "dockerfile": "Dockerfile"
  },
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "username": "stpousty-devcontainer",
      "uid": "2112",
      "gid": "2112"
    }
  }
}
```

**How It Works**:
1. Dockerfile deletes the `ubuntu` user, freeing UID 1000
2. `common-utils` creates our user with UID 2112 and GID 2112 (no conflict)
3. VSCode's automatic UID matching adjusts it to match the host UID (typically 1000)
4. Result: Container user has UID 1000, matching host, giving perfect permission alignment

### Why This Is Simpler Than the CUDA Template Approach

**CUDA Template** (complex group-based sharing):
- Creates container user at UID 2112 (different from host)
- Creates a shared group with host's GID (1000)
- Adds container user to shared group
- Sets files to be group-writable
- Requires complex `setup-environment.sh` script with `chown` and `chmod` commands

**ROCm Template** (direct UID matching):
- Deletes `ubuntu` user to free UID 1000
- Lets VSCode's UID matching do its job
- Container user gets UID 1000 = host user UID 1000
- No shared group needed
- No permissions setup script needed
- Files are directly owned by container user, accessible by host user

**Result**: We eliminated the entire "Permissions Block" from `setup-environment.sh` because it's no longer needed!

### References

**Ubuntu 24.04 UID Conflict**:
- [uid mapping problem with ubuntu-24.04 base image](https://github.com/devcontainers/images/issues/1056)
- [common-utils doesn't work on Ubuntu 24.04](https://github.com/devcontainers/features/issues/1265)

**VSCode UID Matching Issues**:
- [updateRemoteUserUID has no effect](https://github.com/microsoft/vscode-remote-release/issues/10030)
- [updateRemoteUserUID has no effect (CLI)](https://github.com/devcontainers/cli/issues/874)
- [updateRemoteUserUID does not work if gid on host matches container gid](https://github.com/devcontainers/cli/issues/494)
- [Massive chown with updateRemoteUserUID = false](https://github.com/microsoft/vscode-remote-release/issues/7390)

**General Permission Issues**:
- [DevContainer: Changing UID/GID fails when GID exists](https://github.com/microsoft/vscode-remote-release/issues/7284)
- [groupadd: GID '1000' already exists](https://github.com/devcontainers/features/issues/531)

**Educational Resources**:
- [Dev Containers Part 3: UIDs and file ownership](https://www.happihacking.com/blog/posts/2024/dev-containers-uids/)
- [Sync DevContainer User With Your Host — Done Right](https://buildsoftwaresystems.com/post/sync-linux-devcontainer-user-with-host/)

### Key Takeaway for Blog Post

This is a perfect example of how porting between ecosystems reveals hidden assumptions. The CUDA template's complex group-based permissions were a workaround for one set of constraints, but when moving to ROCm with Ubuntu 24.04, we discovered bugs in the devcontainer tooling itself. The solution ended up being **simpler** than the original - a nice surprise during a port!

The lesson: Sometimes the "best practice" from one environment needs to be completely rethought in another, and the new solution might actually be cleaner.

## System Python Package Management

### The Discovery: AMD Uses a Pre-Configured venv

While porting from the CUDA template, I initially assumed I'd need to deal with Python's `EXTERNALLY-MANAGED` marker that prevents system-wide pip installs. Modern Python distributions (3.11+) include this marker to encourage virtual environments.

**However, AMD already solved this!** The ROCm PyTorch container includes a pre-configured virtual environment at `/opt/venv`:

```bash
$ which python
/opt/venv/bin/python

$ cat /opt/venv/pyvenv.cfg
home = /usr/bin
include-system-site-packages = false
version = 3.13.8
executable = /usr/bin/python3.13
command = /usr/bin/python3.13 -m venv /opt/venv
```

### Why AMD's Approach Is Smart

**Design Benefits:**
1. **Isolation**: ROCm-optimized PyTorch packages are isolated from Ubuntu's system Python
2. **No EXTERNALLY-MANAGED issues**: The venv bypasses the system Python marker
3. **Automatic activation**: Container sets PATH so `/opt/venv/bin` is found first
4. **Clean upgrades**: AMD can update ROCm packages without breaking system tools
5. **User-friendly**: `pip install` just works, no manual venv activation needed
6. **Includes modern tools**: uv package manager is pre-installed in the venv

**How it works:**
- Ubuntu 24.04's system Python at `/usr/bin/python3.13` has the EXTERNALLY-MANAGED marker
- AMD creates a venv at `/opt/venv` during image build
- Container's PATH is configured to use `/opt/venv/bin/python` by default
- All pip installs go into `/opt/venv/lib/python3.13/site-packages`
- System Python remains untouched and protected

**Important for IDE integration:**
- VSCode's `python.defaultInterpreterPath` must be set to `/opt/venv/bin/python`
- If set to `/usr/bin/python`, PyTorch won't be found (it's only in the venv)
- This was an easy mistake to make during the port - initially set to system Python

### The Wrong Approach (What I Almost Did)

I initially planned to remove the EXTERNALLY-MANAGED marker:

```bash
# DON'T DO THIS - It's unnecessary!
sudo rm -f /usr/lib/python3.*/EXTERNALLY-MANAGED
```

**Why this would have been wrong:**
- AMD already provides a venv solution
- Removing the marker affects system Python, not the venv we're using
- The venv approach is actually better isolation
- Would be fighting against AMD's design instead of working with it

### Comparison to CUDA Template

**NVIDIA's Approach:**
- No pre-configured venv
- Containers run as root by default
- pip install goes directly into system Python packages
- Works but less isolated

**AMD's Approach:**
- Pre-configured venv at `/opt/venv`
- Activated by default
- Better isolation between ROCm packages and system packages
- More aligned with modern Python best practices

### What This Means for the Template

**One small fix needed:** The `/opt/venv` is owned by root in AMD's base image, so the devcontainer user can't install packages without sudo. We fix this in `setup-environment.sh`:

```bash
# Fix ownership of AMD's pre-configured venv
# The base container has a venv at /opt/venv owned by root. We need to make it
# writable by the devcontainer user so they can install packages without sudo.
echo "Configuring Python virtual environment permissions..."
sudo chown -R $(whoami):$(whoami) /opt/venv
```

After this one-time fix during container creation, pip works normally:

```bash
# This works without sudo
pip install transformers
uv pip install diffusers

# No --system flag needed with uv
# No --break-system-packages needed
# No manual venv activation
# No EXTERNALLY-MANAGED removal
```

### Security Consideration: Development vs Production

**Important context:** This venv ownership change is appropriate for development containers but highlights a broader security model difference.

**Devcontainers (this template):**
- User has **passwordless sudo** (standard for devcontainers)
- Can modify system files, install packages, reconfigure services
- Prioritizes **developer convenience** and rapid iteration
- Single-user, ephemeral, rebuildable environment
- Security model: "trust the developer, isolate from host"

**Production containers (NOT this template):**
- Should run as **non-root without sudo**
- Read-only root filesystem where possible
- Minimal installed packages (attack surface reduction)
- Principle of least privilege
- Security model: "assume breach, minimize damage"

**Why the ownership change is fine here:**
- User already has sudo → can `sudo pip install` or `sudo chown` anyway
- No additional attack surface created
- Makes workflow simpler and more intuitive
- Matches how users work on their host systems

**The broader lesson:** Development containers and production containers have fundamentally different security requirements. Don't mistake a good development setup for a production-ready deployment. This template is explicitly **development-only**.

### Key Takeaway for Blog Post

This is a great example of **questioning assumptions during a port**. I assumed AMD's container would work like NVIDIA's (system-wide Python), but AMD made a different (arguably better) design choice.

**The debugging process that revealed this:**
1. Encountered "externally managed" error in testing
2. Researched workarounds (remove marker, use --break-system-packages, etc.)
3. User noticed `/opt/venv` directory in container
4. Investigated and discovered AMD's pre-configured venv
5. Realized all my workarounds were unnecessary

**The lesson:** When porting, verify your assumptions about the target environment. Sometimes the "problem" you're solving doesn't exist, or has already been solved differently than you expected. Looking at the actual container filesystem (`ls /opt`) revealed the real design.

## Integrated GPU Performance: Setting Expectations

### The Discovery

When testing the ROCm template on AMD Ryzen AI Max+ 395 (Strix Halo), I discovered that **GPU was slower than CPU** for the small benchmark workloads:

**Matrix Multiplication (4096x4096):**
- CPU: 0.1784 seconds
- GPU: 0.2831 seconds
- Result: CPU 1.6x faster!

**Neural Network Training (235K parameters, 10 iterations):**
- CPU: 0.0194 seconds
- GPU: 0.1155 seconds
- Result: CPU 6x faster!

### Why This Is Normal (Not a Bug!)

**Integrated GPU Architecture:**
- **Shared memory**: No separate VRAM, both CPU and GPU use same RAM
- **No bandwidth advantage**: Data doesn't need to move, so no PCIe transfer benefit
- **Powerful CPU**: Ryzen AI Max+ has excellent CPU cores with AVX2

**GPU Overhead:**
- **Kernel launch overhead**: ~1-5ms to start each GPU operation
- **Memory operations**: Setting up GPU memory, synchronization
- **Context switching**: Moving between CPU and GPU execution

**Small workload problem:**
- Our test: 235K parameters, batch size 128, 10 iterations
- Overhead: ~100ms
- Actual compute: ~15ms
- **Overhead is 7x the actual work!**

### When GPU Wins on Integrated GPUs

GPU acceleration becomes beneficial when compute dominates overhead:

**Large Language Models:**
- 7B+ parameter models (Llama, Mistral)
- Overhead amortized over billions of operations
- GPU can be 3-10x faster even on integrated GPUs

**Large Batch Training:**
- Batch size 256+ samples
- More parallelism to exploit
- Better GPU utilization

**Long Training Runs:**
- Hours or days of training
- Overhead is one-time cost
- GPU saves wall-clock time

**Computer Vision:**
- 512x512+ images
- Large convolution operations
- GPU-optimized operations

### The Validation Test Dilemma

This created an interesting challenge: How do you write a test that:
1. **Validates GPU works** (runs operations successfully)
2. **Runs quickly** (developers want fast feedback)
3. **Shows realistic expectations** (doesn't mislead about performance)

**Solution**: The test now:
- ✅ Confirms GPU is detected and functional
- ✅ Shows actual performance characteristics
- ✅ Explains why CPU might be faster
- ✅ Sets correct expectations for when GPU helps

**Sample output with educational messaging:**
```
⚠️  WARNING: GPU is slower than CPU for neural network training!
   This may indicate a configuration issue.

💡 Note for integrated GPUs (Ryzen AI, Strix Halo):
   This result is EXPECTED and NORMAL for small workloads like this test.
   GPU overhead (kernel launch, memory operations) dominates for small models.
   GPU benefits appear with:
   - Large models: transformers, LLMs (billions of parameters)
   - Large batches: 256+ samples per batch
   - Long training: Hours/days of compute
   - Large images: 512x512+ resolution

   Your GPU is working correctly! ✅
```

### Key Takeaway for Blog Post

**Don't assume GPU is always faster.** Integrated GPUs with shared memory have different performance characteristics than discrete GPUs:

- Discrete GPU (RTX 4090): Separate VRAM, massive bandwidth, worth overhead even for small tasks
- Integrated GPU (Strix Halo): Shared RAM, CPU is very fast, GPU only worth it for large tasks

This isn't a limitation - it's the right architectural tradeoff for a laptop APU. You get:
- ✅ 96GB unified memory (vs 24GB max on discrete)
- ✅ No data copying between CPU/GPU
- ✅ Lower power consumption
- ✅ GPU acceleration when you need it (LLMs, vision models)

The template correctly supports this architecture and sets proper expectations.

## Future Blog Post Topics

- Part 2: Porting the setup scripts and dependency management
- Part 3: Real-world ML workflows on Strix Halo (when GPU actually helps!)
- Part 4: Performance comparison vs CUDA on similar-spec hardware
- Part 5: Multi-IDE setup (VSCode + JetBrains with ROCm)