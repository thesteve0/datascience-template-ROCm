#!/bin/bash
set -e

echo "Setting up {{PROJECT_NAME}} ROCm PyTorch ML environment..."

# Note: No permissions block needed for workspace files!
# By deleting the ubuntu user in the Dockerfile, common-utils creates our user
# with UID/GID that matches the host (1000:1000), giving automatic permission alignment.
# This is simpler than the CUDA template's group-sharing approach.

WORKSPACE_DIR="/workspaces/{{PROJECT_NAME}}"

# Fix ownership of AMD's pre-configured venv
# The base container has a venv at /opt/venv owned by root. We need to make it
# writable by the devcontainer user so they can install packages without sudo.
#
# SECURITY NOTE: This devcontainer is designed for DEVELOPMENT ONLY.
# The user has passwordless sudo access (standard for devcontainers) for convenience.
# DO NOT use this configuration for production deployments - production containers should:
#   - Run as non-root user without sudo access
#   - Have read-only filesystems where possible
#   - Follow principle of least privilege
echo "Configuring Python virtual environment permissions..."
sudo chown -R $(whoami):$(whoami) /opt/venv

# Generate rocm-provided.txt
echo "Extracting ROCm-provided packages..."
if [ -f /etc/pip/constraint.txt ]; then
    grep -E "==" /etc/pip/constraint.txt | sort > ${WORKSPACE_DIR}/rocm-provided.txt
else
    uv pip freeze > ${WORKSPACE_DIR}/rocm-provided.txt
fi

# Update system packages
# Note: The ROCm container includes AMD internal repos (compute-artifactory.amd.com)
# that are unreachable outside AMD's network. This is expected and won't affect
# functionality. We preserve the repo files for documentation purposes.
# --allow-releaseinfo-change: Handles repos with updated release info
# --no-upgrade: Only install packages if not already present (preserves ROCm versions)
echo "Updating system packages (AMD internal repos may show errors - this is expected)..."
sudo apt-get update --allow-releaseinfo-change 2>&1 || true

sudo apt-get install -y --no-upgrade \
    git curl wget build-essential \
    && sudo rm -rf /var/lib/apt/lists/*

# Install development tools
# Note: AMD's ROCm container already includes uv package manager and uses a
# pre-configured venv at /opt/venv. After fixing venv ownership above,
# pip/uv install works without sudo.
uv pip install --no-cache-dir black flake8 pre-commit

# Initialize uv project for standalone mode
# The .standalone-project marker is created by setup-project.sh for new projects
if [ -f "${WORKSPACE_DIR}/.standalone-project" ]; then
    echo "Initializing uv project for standalone mode..."
    cd ${WORKSPACE_DIR}

    # Create venv from /opt/venv's Python for version consistency
    if [ ! -d ".venv" ]; then
        echo "Creating project virtual environment..."
        /opt/venv/bin/python -m venv .venv
    fi

    # Create .pth bridge to make ROCm packages accessible
    VENV_SITE_PACKAGES=$(find .venv/lib -type d -name "site-packages" | head -n 1)

    if [ -n "$VENV_SITE_PACKAGES" ]; then
        PTH_FILE="$VENV_SITE_PACKAGES/_rocm_bridge.pth"
        echo "/opt/venv/lib/python3.13/site-packages" > "$PTH_FILE"
        echo "✓ Created .pth bridge for ROCm packages"
    else
        echo "ERROR: Could not find site-packages in .venv"
        exit 1
    fi

    # Initialize project
    if [ ! -f "pyproject.toml" ]; then
        uv init --no-readme
    fi

    # Install TOML manipulation dependencies
    echo "Installing configuration tools..."
    uv add tomli tomli-w

    # Generate exclusion list from /opt/venv packages and add to pyproject.toml
    echo "Generating ROCm package exclusion list..."
    .venv/bin/python << 'PYEOF'
import json
from pathlib import Path
import tomli
import tomli_w

site_packages = Path('/opt/venv/lib/python3.13/site-packages')
packages = {d.name.split('-')[0].replace('_', '-').lower()
            for d in site_packages.glob('*.dist-info')}

# Read existing pyproject.toml and add exclude-dependencies
with open('pyproject.toml', 'rb') as f:
    config = tomli.load(f)

if 'tool' not in config:
    config['tool'] = {}
if 'uv' not in config['tool']:
    config['tool']['uv'] = {}

config['tool']['uv']['exclude-dependencies'] = sorted(packages)

with open('pyproject.toml', 'wb') as f:
    tomli_w.dump(config, f)

print(f"✓ Protected {len(packages)} ROCm packages from overwrite")
PYEOF

    # Verify ROCm packages accessible
    echo "Verifying ROCm package access..."
    if .venv/bin/python -c "import torch" 2>/dev/null; then
        TORCH_VERSION=$(.venv/bin/python -c "import torch; print(torch.__version__)")
        echo "✓ torch $TORCH_VERSION accessible from /opt/venv"
    else
        echo "⚠ Warning: Could not import torch"
    fi

    echo "✓ uv project initialized with ROCm protection"
fi

# Configure git identity
echo "Configuring git identity..."
git config --global user.name "{{GIT_NAME}}"
git config --global user.email "{{GIT_EMAIL}}"
git config --global init.defaultBranch main

# Verify ROCm installation
echo ""
echo "Verifying ROCm installation..."
if command -v rocm-smi &> /dev/null; then
    echo "ROCm SMI found. GPU status:"
    rocm-smi || echo "Warning: rocm-smi failed (this is normal if no GPU is available)"
else
    echo "Warning: rocm-smi not found in PATH"
fi

echo ""
echo "Setup complete!"
echo "Store models in ./models/ and datasets in ./datasets/ - they persist across container rebuilds"