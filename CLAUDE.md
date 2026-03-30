# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: Two-Environment Architecture

This project has TWO separate Python environments connected by a `.pth` bridge. Understanding which environment each command targets is essential -- getting this wrong breaks ROCm GPU support.

```
/opt/venv/  (ROOT-OWNED, container-provided)          .venv/  (USER-OWNED, project-specific)
+-----------------------------------------+          +-----------------------------------+
| Python 3.12   (/opt/venv/bin/python)    |          | Python 3.12  (.venv/bin/python)   |
| torch, numpy, ROCm libraries            |          | tomli, tomli-w, ruff              |
| uv  (/opt/venv/bin/uv)                  |          | user's project dependencies       |
| ruff, pre-commit (dev tools)            |          |                                   |
|                                          |    .pth  |                                   |
| site-packages/ <-------------------------+---------+ _rocm_bridge.pth                  |
|   torch/, numpy/, etc.                   |  bridge  |   (contains path to /opt/venv     |
+-----------------------------------------+          |    site-packages)                 |
  Installed by: Dockerfile + sudo uv pip               +-----------------------------------+
  Write access: sudo only                                Installed by: uv add / uv sync
  Identity: IS a virtualenv (has pyvenv.cfg)             Write access: devcontainer user
                                                         Created by: uv venv
```

**How the .pth bridge works**: `.venv/lib/python3.12/site-packages/_rocm_bridge.pth` is a one-line file containing `/opt/venv/lib/python3.12/site-packages`. Python's site module reads `.pth` files at startup and adds each path to `sys.path`. This makes torch/numpy importable from `.venv` without copying them, AND without exposing them to pip's package resolution (unlike `--system-site-packages`).

**Why .pth instead of --system-site-packages**: `--system-site-packages` would allow `pip install torch` or `uv add torch` to overwrite the ROCm-optimized packages with PyPI versions, breaking GPU support. The `.pth` bridge makes packages importable but invisible to package managers.

**Why `/opt/venv` must stay root-owned**: If `/opt/venv` were user-writable, a stray `uv pip install` or `pip install` could overwrite ROCm packages. Root ownership ensures writes require explicit `sudo`, providing a safety barrier.

## CRITICAL: The VIRTUAL_ENV Timing Problem

`devcontainer.json` sets `VIRTUAL_ENV=/workspaces/PROJECT/.venv` via `containerEnv`. Container environment variables are set at container creation time, BEFORE `postCreateCommand` runs. Therefore:

**When `setup-environment.sh` starts, `VIRTUAL_ENV` points to a `.venv` that does not exist yet.**

Every `uv` command inherits this env var and tries to use the non-existent `.venv` as its target. This is the single most common source of breakage when editing `setup-environment.sh`.

### uv command behavior with VIRTUAL_ENV set to non-existent .venv

| Command | Result | Why |
|---------|--------|-----|
| `uv pip install ruff` | **FAILS** | Tries to use non-existent .venv |
| `sudo uv pip install ruff` | **FAILS** | sudo preserves VIRTUAL_ENV in this container |
| `env -u VIRTUAL_ENV uv pip install ruff` | **FAILS** | Without VIRTUAL_ENV, uv finds no target env |
| `uv pip install --python /opt/venv/bin/python ruff` | **WORKS** | --python overrides VIRTUAL_ENV |
| `sudo uv pip install --python /opt/venv/bin/python ruff` | **WORKS** | --python overrides everything |

**The rule**: Any `uv pip` command targeting `/opt/venv` MUST use `--python /opt/venv/bin/python`. This is the ONLY reliable way to target `/opt/venv` when `VIRTUAL_ENV` is set.

**Why `env -u VIRTUAL_ENV` doesn't work**: `/opt/venv` is a virtualenv (has `pyvenv.cfg`), not a system Python. When VIRTUAL_ENV is unset, uv looks for a system Python or an active venv. It doesn't find one because the system Python is `/usr/bin/python3.12` (externally managed, refuses installs) and `/opt/venv` is only discoverable via `--python` or VIRTUAL_ENV.

**Why sudo preserves VIRTUAL_ENV**: This container's sudoers configuration does NOT strip VIRTUAL_ENV. This is NOT default sudo behavior on all systems. Do not assume sudo will clean the environment.

## CRITICAL: setup-environment.sh Phase Timeline

The script runs as `postCreateCommand` under the devcontainer user (not root). Understanding what exists at each phase prevents ordering bugs.

### Phase 0: Entry Conditions
- `VIRTUAL_ENV=/workspaces/PROJECT/.venv` is set (but .venv does NOT exist)
- `/opt/venv` exists, is root-owned, contains Python 3.12 + torch + numpy + ROCm libs + uv
- PATH includes `/opt/venv/bin` (so `uv`, `python`, `ruff` resolve to /opt/venv versions)
- No `.venv`, no `pyproject.toml`, no `uv.lock` in the workspace

### Phase 1: System Setup (lines 14-38)
**State**: .venv does NOT exist. VIRTUAL_ENV points to non-existent .venv.

- Generates `rocm-provided.txt` from /opt/venv packages
- Installs ruff + pre-commit into `/opt/venv` (requires sudo + `--python`)
- Both `uv pip` calls MUST use `--python /opt/venv/bin/python` to bypass VIRTUAL_ENV

### Phase 2: Project Environment (lines 42-125, standalone mode only)
Entered only if `.standalone-project` marker exists (created by `setup-project.sh`).

**Step 2a** (lines 51-68): Create .venv
- `uv venv --python /opt/venv/bin/python .venv`
- Verifies Python version matches /opt/venv
- **After this step**: .venv exists, VIRTUAL_ENV now points to a real directory
- **Note**: `uv venv` does NOT include pip. Do not use `.venv/bin/pip`.

**Step 2b** (lines 70-81): Create .pth bridge
- Writes `/opt/venv/lib/python3.12/site-packages` into `.venv/lib/python3.12/site-packages/_rocm_bridge.pth`
- This bridge survives subsequent `uv add`/`uv sync` calls (verified by testing)

**Step 2c** (lines 84-86): Initialize uv project
- `uv init --no-readme` creates `pyproject.toml`

**Step 2d** (lines 88-109): Generate exclusion list (BOOTSTRAP STEP)
- Python stdlib script scans `/opt/venv` dist-info directories
- Appends `[tool.uv] exclude-dependencies = [...]` to `pyproject.toml`
- Uses ONLY stdlib (`pathlib` + file append) -- no external packages needed
- **Why stdlib**: Cannot use `uv add tomli-w` yet because the exclusion list doesn't exist yet, and without it `uv add` would try to pull torch/numpy from PyPI

**Step 2e** (line 113): Install project dependencies
- `uv add tomli tomli-w ruff` -- first uv project command
- Safe because exclusion list is now in place
- `uv add` modifies `[project].dependencies` in pyproject.toml AND runs sync
- Preserves the hand-written `[tool.uv]` section (verified by testing)

### Phase 3: Verification (lines 127+)
- Git identity configuration
- ROCm GPU verification (amd-smi / rocm-smi)
- Everything exists: .venv, pyproject.toml, uv.lock, .pth bridge

## Permissions Model

| Path | Owner | Read | Write | How to write |
|------|-------|------|-------|-------------|
| `/opt/venv/` | root:root | all users | root only | `sudo /opt/venv/bin/uv pip install --python /opt/venv/bin/python ...` |
| `.venv/` | devcontainer user | user | user | `uv add ...` or `uv sync` |
| `.pth` bridge | devcontainer user | user | user | Created by setup-environment.sh |
| `pyproject.toml` | devcontainer user | user | user | `uv add ...` or manual edit + `uv sync` |
| Workspace files | devcontainer user | user | user | Standard file operations |

**User identity**: The Dockerfile deletes the default `ubuntu` user (UID 1000). The `common-utils` devcontainer feature then creates the devcontainer user with a specified UID. VSCode's UID remapping adjusts it to match the host user, giving automatic permission alignment.

## Bootstrap Ordering (Why This Matters)

The dependency installation has a chicken-and-egg problem:

```
uv add/sync  --->  needs exclusion list to avoid pulling torch from PyPI
                          |
                   exclusion list writer  --->  could use tomli-w to write TOML
                          |
                   tomli-w  --->  would need to be installed by uv add
                          |
                   uv add  --->  needs exclusion list (circular!)
```

**Solution**: Break the cycle by writing the exclusion list with zero external packages:
1. `uv init --no-readme` creates a fresh `pyproject.toml` (no `[tool]` section)
2. Python stdlib script appends `[tool.uv]\nexclude-dependencies = [...]` via string append
3. Now `uv add tomli tomli-w ruff` is safe -- the exclusion list prevents ROCm package overwrites

**Why string append is safe here**: `uv init` creates a minimal pyproject.toml with only a `[project]` section. Appending `[tool.uv]` to the end is valid TOML. `uv add` subsequently modifies `[project].dependencies` but preserves the `[tool.uv]` section.

## Rules for Claude Code

### Behavioral Rules

1. **Never modify venv creation, .pth bridge, or bootstrap logic** as a first solution. Look for config-level fixes first (devcontainer.json, environment variables, IDE settings). Only propose changes as a last resort, and explicitly ask for user approval.

2. **Test in the container first**. When `setup-environment.sh` fails, the container usually stays running. Use `docker exec <container-id> bash -c "..."` to verify hypotheses BEFORE editing the script. Ask the user for the container ID from `docker ps`.

3. **Any `uv pip` command targeting `/opt/venv`** MUST use `--python /opt/venv/bin/python`. Never rely on VIRTUAL_ENV or uv's fallback discovery for this.

4. **Never `chown /opt/venv`**. It must stay root-owned to prevent accidental overwrites of ROCm packages.

5. **Never use `pip install` directly**. Users should use `uv add` for project dependencies. The setup script uses `uv pip install --python ...` only for installing tools into the root-owned `/opt/venv`.

6. **`uv venv` does not include pip**. Do not use `.venv/bin/pip`. Use `uv pip install` or `uv add` instead.

7. **Check what VIRTUAL_ENV is set to** when debugging any uv issue. It's the first thing to verify.

### Debugging Protocol

When `setup-environment.sh` fails during devcontainer build:

```bash
# 1. Get the container ID (container stays running after postCreateCommand failure)
docker ps

# 2. Check the environment
docker exec <id> bash -c "printenv VIRTUAL_ENV && printenv PATH && which uv"

# 3. Test your proposed fix with --dry-run
docker exec <id> bash -c "sudo /opt/venv/bin/uv pip install --python /opt/venv/bin/python --dry-run <package>"

# 4. Check if .venv exists and what's in it
docker exec <id> bash -c "ls -la /workspaces/PROJECT/.venv/bin/ 2>/dev/null || echo 'no .venv'"
```

**Testing Limitations**: Claude Code runs on the host, not inside the devcontainer. GPU tests, container operations, and setup-environment.sh can only be tested via `docker exec` or by asking the user to rebuild. Never assume a fix works without testing.

## Historical Context: What Broke and Why

**The old approach** (before current design): The script ran `sudo chown -R $(whoami):$(whoami) /opt/venv` to make it user-writable, then `uv pip install ruff` without sudo or `--python`. This worked because uv's fallback virtualenv discovery found `/opt/venv` via the uv binary's filesystem location (`/opt/venv/bin/uv`), bypassing the non-existent VIRTUAL_ENV.

**Why it was changed**: Chowning `/opt/venv` to the user removed the safety barrier against accidental ROCm package overwrites. The new design keeps `/opt/venv` root-owned and uses `sudo` + `--python` for intentional writes.

**Why naive fixes failed**:
- `sudo uv pip install ruff` -- sudo preserves VIRTUAL_ENV, uv tries non-existent .venv
- `sudo env -u VIRTUAL_ENV uv pip install ruff` -- uv has no target (no system Python, /opt/venv not discoverable without --python)
- The only working fix: `sudo uv pip install --python /opt/venv/bin/python ruff`

**Lesson**: The old code worked by accident through uv's undocumented fallback behavior. When any part of the environment changes (permissions, sudo usage, uv version), fallback behavior can silently break. Always use explicit targeting (`--python`) instead.

## Project Overview

This is a ROCm-based data science devcontainer template, ported from the CUDA version at https://github.com/thesteve0/datascience-template-CUDA. It provides development container configurations optimized for machine learning and data science work on AMD GPUs using ROCm.

### Key Objectives

1. **Port from CUDA to ROCm**: Adapt the NVIDIA PyTorch container setup to use AMD ROCm containers
2. **Incorporate Improvements**: Apply lessons learned from using the CUDA template in production
3. **Enhanced Dependency Management**: Better handling of conflicts between container-provided libraries and project requirements
4. **Multi-IDE Support**: Provide devcontainer configurations for both VSCode and JetBrains IDEs

### Repository Structure

Template files in the repository root (before `setup-project.sh` runs):
```
datascience-template-ROCm/
├── devcontainer.json          # Template for VSCode devcontainer
├── Dockerfile                 # Container image definition
├── setup-project.sh           # Initial project setup script (runs on host)
├── setup-environment.sh       # Post-creation environment configuration (runs in container)
├── resolve-dependencies.py    # Filters dependencies to avoid package conflicts
├── cleanup-script.sh          # Clean up Docker resources
├── CLAUDE.md                  # This file
├── TODO.md                    # Project roadmap and task tracking
└── README.md
```

After `setup-project.sh` runs, files are reorganized:
- `devcontainer.json`, `Dockerfile`, `setup-environment.sh` move to `.devcontainer/`
- `resolve-dependencies.py` moves to `scripts/`
- `CLAUDE.md` and `README.md` move to `template_docs/` (new skeleton versions created for user)
- `.standalone-project` marker created (triggers Phase 2 in setup-environment.sh)

### Target Hardware

This template is specifically designed for **consumer AMD GPUs**:
- AMD Ryzen AI Max+ 395 (Strix Halo - gfx1151 architecture)
- AMD Ryzen AI 300 Series (Strix Point - gfx1150 architecture)
- Custom Steam Deck configurations
- Similar consumer-grade AMD APUs with integrated graphics

**Official Documentation for Consumer GPUs**:
- [ROCm 7.2 for Radeon and Ryzen](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/index.html)
  - ROCm 7.2 is the first "production-ready" release for Strix Halo/Point
  - Native gfx1151/gfx1150 support (no HSA_OVERRIDE_GFX_VERSION needed)
  - PyTorch 2.9.1 with official production support
  - Up to 128GB shared memory on Ryzen APUs
- [Compatibility Matrix](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/compatibility/compatibilityryz/native_linux/native_linux_compatibility.html)

**Precision Support**: FP16 is the only officially validated precision type. Other data types (BF16, FP32, INT8) may work but have not been formally tested by AMD.

**Note**: While AMD's general ROCm documentation focuses on data center GPUs (MI300X series), the consumer GPU guide above and the `rocm/pytorch` image have been verified to work on Ryzen/Radeon hardware.

### Base Container

- **Image**: `rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1` (user-verified on Strix Halo and Steam Deck)
- **Python**: 3.12 (in `/opt/venv`, which is a virtualenv based on `/usr/bin/python3.12`)
- **PyTorch**: 2.9.1 with ROCm support
- Other candidates were evaluated and rejected:
  - `rocm/pytorch-training`: Being deprecated in favor of primus
  - `rocm/primus`: Data center only (MI300X, MI325X), overkill for single-GPU consumer hardware

## ROCm-Specific Considerations

### Key Differences from CUDA

- **Base Images**: Use AMD ROCm containers (e.g., `rocm/pytorch`) instead of NVIDIA
- **GPU Detection**: Use `amd-smi` (preferred) or `rocm-smi` instead of `nvidia-smi`
- **Driver Requirements**: ROCm drivers and ROCm runtime instead of NVIDIA drivers and CUDA toolkit
- **Environment Variables**: ROCm-specific variables (e.g., `HIP_VISIBLE_DEVICES` instead of `CUDA_VISIBLE_DEVICES`)
- **PyTorch Differences**: ROCm PyTorch builds may have different package names and dependencies
- **Container Runtime**: Requires `--device=/dev/kfd --device=/dev/dri --group-add=video --group-add=render`

### Verifying GPU Access

```bash
# Check GPU visibility (amd-smi is preferred, rocm-smi still works)
amd-smi

# Test PyTorch GPU access
python -c "import torch; print(f'GPU available: {torch.cuda.is_available()}'); print(f'GPU count: {torch.cuda.device_count()}')"
```

## IDE Support

### VSCode

- Configuration in `.devcontainer/devcontainer.json` (created by setup script)
- Automatically detects and prompts to reopen in container
- Extensions auto-installed (Python, Jupyter, linting, formatting)
- `python.defaultInterpreterPath` set to `/opt/venv/bin/python`
- Integrated terminal runs inside container with GPU access

### JetBrains (PyCharm/Gateway)

- Uses same `devcontainer.json` as VSCode (shared configuration)
- Backend specified in `customizations.jetbrains.backend: "IU"` (IntelliJ IDEA Ultimate)
- `.idea/` directory pre-configured by `setup-project.sh` with `PYTHON_MODULE` type
  - Source roots: `src/` pre-configured as Sources, `tests/` as Test Sources
  - Excludes: `.venv/`, `models/`, `datasets/`, `.cache/` pre-configured as Excluded
- **Manual configuration still required for Python interpreter**:
  1. File -> Project Structure (`Ctrl+Alt+Shift+S`)
  2. Project -> SDK dropdown -> Add SDK -> Add Python Interpreter
  3. Location: Local Machine, Environment: Select existing, Type: **uv**
  4. Path to uv: `/opt/venv/bin/uv`
  5. Environment: Select `Python 3.12 (/workspaces/PROJECT_NAME/.venv)`
- Ruff linter/formatter enabled by default via `.idea/ruff.xml`

**Python Interpreter Limitation**: JetBrains does not support automatic interpreter configuration in devcontainers ([IJPL-174150](https://youtrack.jetbrains.com/issue/IJPL-174150)).

## Claude Code Integration

### Claude Code Feature

The devcontainer includes the Claude Code feature (`ghcr.io/anthropics/devcontainer-features/claude-code:1`), which provides:

- Claude Code CLI available inside the devcontainer
- Google Cloud credentials mounted from host for Vertex AI authentication
- Environment variables passed from host to container

### Required Configuration

**Host Environment Variables** (set on your host machine):
```bash
export ANTHROPIC_VERTEX_PROJECT_ID="your-gcp-project-id"
export ANTHROPIC_VERTEX_REGION="us-east5"  # or your preferred region
export CLAUDE_CODE_USE_VERTEX="true"
```

**Mounted Credentials:**
- Host `~/.config/gcloud` -> Container `/home/stpousty-devcontainer/.config/gcloud` (read-only)

### External Data Mount

The devcontainer mounts your host's `~/data` directory at `/data` in the container. This allows access to datasets and files outside the project directory without copying them into the workspace.

**Use Cases:**
- Access large datasets stored on host without duplication
- Share data between multiple projects
- Keep proprietary data outside version control
- Reference pre-trained models stored centrally

## Important Resources

### Official AMD Documentation
- **[ROCm 7.2 for Radeon and Ryzen GPUs](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/index.html)** - Primary documentation for consumer GPU support
- **[ROCm 7.2 Compatibility Matrix](https://rocm.docs.amd.com/projects/radeon-ryzen/en/docs-7.2/docs/compatibility/compatibilityryz/native_linux/native_linux_compatibility.html)** - Supported precision types and hardware
- **[ROCm General Documentation](https://rocm.docs.amd.com/)** - Data center GPU focused (MI300X series)

### Base Template
- **[CUDA Template Repository](https://github.com/thesteve0/datascience-template-CUDA)** - Original NVIDIA-based template being ported

### Community Resources
- AMD Developer Discord (for consumer GPU support questions)
- [ROCm GitHub Issues](https://github.com/ROCm/ROCm/issues) - For reporting bugs and tracking gfx1151-specific issues

## Current Status

Template is feature-complete with ROCm 7.2 support. Ready for end-to-end testing and release preparation.