#!/bin/bash
set -e

echo "Setting up {{PROJECT_NAME}} ROCm PyTorch ML environment..."

# Note: No permissions block needed!
# By deleting the ubuntu user in the Dockerfile, common-utils creates our user
# with UID/GID that matches the host (1000:1000), giving automatic permission alignment.
# This is simpler than the CUDA template's group-sharing approach.

WORKSPACE_DIR="/workspaces/{{PROJECT_NAME}}"

# Generate rocm-provided.txt
echo "Extracting ROCm-provided packages..."
if [ -f /etc/pip/constraint.txt ]; then
    grep -E "==" /etc/pip/constraint.txt | sort > ${WORKSPACE_DIR}/rocm-provided.txt
else
    pip freeze > ${WORKSPACE_DIR}/rocm-provided.txt
fi

# Update system packages
sudo apt-get update && sudo apt-get install -y \
    git curl wget build-essential \
    && sudo rm -rf /var/lib/apt/lists/*

# Install uv package manager
echo "Installing uv package manager..."
curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

# Install development tools
sudo pip install --no-cache-dir black flake8 pre-commit

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