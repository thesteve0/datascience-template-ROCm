# Devcontainer Backup, Rollback, and Sharing

This document covers two related workflows:
- **Personal backup**: snapshot your container before a risky rebuild so you can roll back if it breaks
- **Team sharing**: distribute a working environment to other AMD GPU users

Both use the same core tool: `docker commit`.

## What Lives Where

Understanding what survives a container rebuild determines whether you need a snapshot at all.

| Location | Survives rebuild? | Examples |
|---|---|---|
| Project workspace (`/workspaces/PROJECT_NAME/`) | Yes — bind-mounted from host | `src/`, `tests/`, `.venv/`, `pyproject.toml`, `uv.lock`, `configs/` |
| `models/`, `datasets/`, `.cache/` | Yes — subdirectories of workspace | All your model weights and datasets |
| `_rocm_bridge.pth` | Yes — lives in `.venv/` | The bridge file itself survives; see caveat below |
| `/opt/venv` | **No** — inside container layer | ROCm's Python env with torch, numpy, ruff, pre-commit |
| System packages (`apt install ...`) | **No** — inside container layer | Anything installed via `sudo apt install` during the session |
| Manual `/opt/venv` installs | **No** — inside container layer | Packages installed via `pip install` outside the project venv |

**The `.pth` bridge caveat**: `.venv/lib/python3.12/site-packages/_rocm_bridge.pth` survives in
the workspace, but it points to `/opt/venv/lib/python3.12/site-packages`. If the rebuilt
container uses a different Python version, this path becomes stale and imports will fail with
a confusing "importing from source directory" error. `setup-environment.sh` recreates the
bridge file correctly, so as long as you run the setup script, this is handled automatically.

## The Simple Case: Just Use Git

If your workflow is:
- Add packages via `uv add somepackage`
- Install them into `.venv` (not `/opt/venv`)
- Keep `pyproject.toml` and `uv.lock` committed

Then a `git commit` before rebuilding is your only backup. After the rebuild, `setup-environment.sh`
restores `/opt/venv` tools (ruff, pre-commit) and `uv sync` restores your project dependencies
from `uv.lock`. Nothing is lost.

```bash
# Before a rebuild, just commit your current state
git add -A
git commit -m "snapshot before container rebuild"

# After rebuild, setup-environment.sh runs automatically via postCreateCommand
# Your dependencies are restored from uv.lock
```

This covers the vast majority of normal development workflows.

## Full Container Snapshot with `docker commit`

Use this when you have made changes that live inside the container layer and won't survive a rebuild:
- Installed system packages via `sudo apt install`
- Installed packages directly into `/opt/venv` (not into `.venv`)
- Made custom system configuration changes (modified config files in `/etc/`, etc.)

### Step 1: Find Your Running Container

```bash
# List running containers and find your devcontainer
docker ps --format "table {{.ID}}\t{{.Image}}\t{{.Names}}"
```

The devcontainer name typically includes your project name. The container ID is the first column.

Alternatively, from inside the devcontainer terminal:
```bash
# The hostname of the devcontainer is its container ID
hostname
```

### Step 2: Commit the Container to an Image

```bash
# Replace CONTAINER_ID with your actual container ID
# Replace myproject-rocm with a meaningful name for your snapshot
docker commit CONTAINER_ID myproject-rocm:before-upgrade

# Example with a timestamp for clarity
docker commit CONTAINER_ID myproject-rocm:$(date +%Y%m%d)
```

### Step 3: Verify the Snapshot

Before proceeding with the risky operation, confirm the snapshot works:

```bash
# Run a quick sanity check against your snapshot
docker run --rm myproject-rocm:before-upgrade python -c "import torch; print(torch.__version__)"
```

Now proceed with your rebuild or upgrade.

## Rolling Back to a Snapshot

If the rebuild breaks something and you need to revert:

### Option A: Use the snapshot as the devcontainer base image

Edit `.devcontainer/devcontainer.json`. The template uses a `Dockerfile` build — change the
`build` section to use your snapshot image directly:

```json
// Before (using Dockerfile build):
"build": {
  "dockerfile": "Dockerfile"
},

// After (using snapshot image directly):
"image": "myproject-rocm:before-upgrade",
```

Then use "Reopen in Container" in VSCode or reconnect via JetBrains Gateway. The devcontainer
will start from your snapshot.

### Option B: Run the snapshot directly for quick testing

```bash
# Mount your workspace into the snapshot for immediate access
docker run -it --rm \
  --device=/dev/kfd --device=/dev/dri --group-add=video \
  -v /path/to/your/project:/workspaces/PROJECT_NAME \
  myproject-rocm:before-upgrade \
  bash
```

### Cleaning Up Old Snapshots

Once you've confirmed the new setup works and no longer need the snapshot:

```bash
# Remove the snapshot image
docker rmi myproject-rocm:before-upgrade

# See cleanup-script.sh for broader Docker resource cleanup
```

## Sharing a Snapshot with Other AMD GPU Users

A committed image captures your entire working environment — ROCm libraries, installed tools,
custom configuration — and can be distributed to teammates running AMD hardware.

**Important**: The workspace bind-mount is NOT included in the snapshot. Project source code,
model weights, and datasets travel separately (via git and your normal file-sharing approach).

### Via a Container Registry (recommended for teams)

```bash
# On the machine with the working environment:

# 1. Commit the running container
docker commit CONTAINER_ID myproject-rocm:working-env

# 2. Tag for your registry (Docker Hub example)
docker tag myproject-rocm:working-env yourusername/myproject-rocm:working-env

# 3. Push
docker push yourusername/myproject-rocm:working-env
```

```bash
# On the recipient's machine:

# 1. Pull the image
docker pull yourusername/myproject-rocm:working-env

# 2. Update .devcontainer/devcontainer.json to use it
# Change "build": { "dockerfile": "Dockerfile" }
# to "image": "yourusername/myproject-rocm:working-env"

# 3. Reopen in container — setup-environment.sh runs and configures the workspace
```

GitHub Container Registry (`ghcr.io`) is a good alternative if your project is already on GitHub.

### Via File Transfer (offline / air-gapped)

```bash
# On the source machine:

# Export the image to a compressed file (~20-23GB for rocm/pytorch based images)
docker save myproject-rocm:working-env | gzip > myproject-rocm-working-env.tar.gz

# Transfer the file to the recipient (scp, USB drive, etc.)
```

```bash
# On the recipient's machine:

# Load the image
docker load < myproject-rocm-working-env.tar.gz

# Update devcontainer.json and reopen in container (same as registry approach above)
```

### What the Recipient Still Needs to Do

After pulling or loading the shared image and updating `devcontainer.json`:

1. **Their workspace is separate**: clone the project repo into their workspace
2. **Run setup**: `setup-environment.sh` still runs automatically via `postCreateCommand` —
   it creates their `.venv`, sets up the `.pth` bridge, and runs `uv sync`
3. **Git config**: `setup-environment.sh` configures git with `{{GIT_NAME}}` and `{{GIT_EMAIL}}`
   placeholders — they'll need to set their own git identity if not already configured

## Limitations and Caveats

**Workspace not included**: The snapshot captures the container layer only. Project files,
model weights, and datasets are not in the image — distribute those separately via git and
your normal data-sharing approach.

**Hardware specificity**: ROCm builds in the `rocm/pytorch` image are compiled for specific
GPU architectures. A snapshot that works on Strix Halo (gfx1151) may not work on other AMD
GPU families. Sharing is safest between machines with the same GPU architecture.

**Image size**: The `rocm/pytorch` base image is approximately 20GB. Snapshots will be
21-23GB. Plan for storage and transfer time accordingly.

**Host drivers not included**: The container does not include ROCm drivers. Recipients still
need ROCm 7.2+ drivers installed on their host system. See the main README for driver
installation guidance.

**Docker layer growth**: Each `docker commit` adds a new layer on top of the existing image.
If you commit repeatedly, consider periodically flattening or rebuilding from the Dockerfile
to keep image sizes manageable.
