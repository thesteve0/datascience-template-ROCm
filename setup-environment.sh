#!/bin/bash
set -e

echo "Setting up {{PROJECT_NAME}} ROCm PyTorch ML environment..."

# Note: No permissions block needed for workspace files!
# By deleting the ubuntu user in the Dockerfile, common-utils creates our user
# with UID/GID that matches the host (1000:1000), giving automatic permission alignment.
# This is simpler than the CUDA template's group-sharing approach.

WORKSPACE_DIR="/workspaces/{{PROJECT_NAME}}"
PYTHON_VERSION=$(/opt/venv/bin/python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

# Generate rocm-provided.txt
echo "Extracting ROCm-provided packages..."
if [ -f /etc/pip/constraint.txt ]; then
    grep -E "==" /etc/pip/constraint.txt | sort > ${WORKSPACE_DIR}/rocm-provided.txt
else
    sudo /opt/venv/bin/uv pip freeze --python /opt/venv/bin/python > ${WORKSPACE_DIR}/rocm-provided.txt
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

# Install development tools into /opt/venv via sudo (avoids slow recursive chown).
# /opt/venv stays root-owned; users add packages via `uv add` into .venv, never directly here.
# Ruff replaces black (formatter) + flake8 (linter) with a single fast tool
sudo /opt/venv/bin/uv pip install --python /opt/venv/bin/python --no-cache-dir ruff pre-commit

# Initialize uv project for standalone mode
# The .standalone-project marker is created by setup-project.sh for new projects
if [ -f "${WORKSPACE_DIR}/.standalone-project" ]; then
    echo "Initializing uv project for standalone mode..."
    cd ${WORKSPACE_DIR}

    # Detect /opt/venv Python version for consistency
    CONTAINER_PYTHON_VERSION=$(/opt/venv/bin/python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    echo "Container Python version: $CONTAINER_PYTHON_VERSION"

    # Create venv from /opt/venv's Python for version consistency
    if [ ! -d ".venv" ]; then
        echo "Creating project virtual environment with Python $CONTAINER_PYTHON_VERSION..."
        /opt/venv/bin/uv venv --python /opt/venv/bin/python .venv

        # CRITICAL: Verify the venv uses the same Python version
        VENV_PYTHON_VERSION=$(.venv/bin/python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")

        if [ "$VENV_PYTHON_VERSION" != "$CONTAINER_PYTHON_VERSION" ]; then
            echo "ERROR: venv Python version mismatch!"
            echo "  Container /opt/venv: Python $CONTAINER_PYTHON_VERSION"
            echo "  Created .venv: Python $VENV_PYTHON_VERSION"
            echo "  This will cause binary incompatibility with ROCm packages."
            echo "  Please report this issue at: https://github.com/thesteve0/datascience-template-ROCm/issues"
            exit 1
        fi

        echo "✓ Created .venv with Python $VENV_PYTHON_VERSION"
    fi

    # Create .pth bridge to make ROCm packages accessible
    VENV_SITE_PACKAGES=$(find .venv/lib -type d -name "site-packages" | head -n 1)
    CONTAINER_SITE_PACKAGES="/opt/venv/lib/python${CONTAINER_PYTHON_VERSION}/site-packages"

    if [ -n "$VENV_SITE_PACKAGES" ]; then
        PTH_FILE="$VENV_SITE_PACKAGES/_rocm_bridge.pth"
        echo "$CONTAINER_SITE_PACKAGES" > "$PTH_FILE"
        echo "✓ Created .pth bridge: $VENV_SITE_PACKAGES/_rocm_bridge.pth -> $CONTAINER_SITE_PACKAGES"
    else
        echo "ERROR: Could not find site-packages in .venv"
        exit 1
    fi

    # Initialize project
    if [ ! -f "pyproject.toml" ]; then
        uv init --no-readme
    fi

    # CRITICAL: Generate exclusion list BEFORE any uv add/sync commands
    # This prevents uv from installing PyTorch/numpy/etc from PyPI
    # Uses only Python stdlib (tomllib for reading, string append for writing)
    # so no external packages are needed for the bootstrap step
    echo "Generating ROCm package exclusion list..."
    .venv/bin/python << PYEOF
from pathlib import Path

site_packages = Path('/opt/venv/lib/python${CONTAINER_PYTHON_VERSION}/site-packages')
packages = sorted({d.name.split('-')[0].replace('_', '-').lower()
                   for d in site_packages.glob('*.dist-info')})

# Append [tool.uv] exclusion list to pyproject.toml
# Safe because uv init creates a fresh file without a [tool] section
with open('pyproject.toml', 'a') as f:
    f.write('\n[tool.uv]\nexclude-dependencies = [\n')
    for pkg in packages:
        f.write(f'    "{pkg}",\n')
    f.write(']\n')

print(f"✓ Protected {len(packages)} ROCm packages from overwrite")
PYEOF

    # Now safe to use uv add - exclusion list is in place
    echo "Adding project dependencies..."
    uv add tomli tomli-w ruff

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
if command -v amd-smi &> /dev/null; then
    echo "AMD SMI found. GPU status:"
    amd-smi || echo "Warning: amd-smi failed (this is normal if no GPU is available)"
elif command -v rocm-smi &> /dev/null; then
    echo "ROCm SMI found (note: amd-smi is preferred). GPU status:"
    rocm-smi || echo "Warning: rocm-smi failed (this is normal if no GPU is available)"
else
    echo "Warning: Neither amd-smi nor rocm-smi found in PATH"
fi

echo ""
echo "Setup complete!"
echo "  - Ruff linter/formatter installed and configured"
echo "  - Store models in ./models/ and datasets in ./datasets/ - they persist across container rebuilds"