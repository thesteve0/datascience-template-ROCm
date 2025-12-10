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
    pip freeze > ${WORKSPACE_DIR}/rocm-provided.txt
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