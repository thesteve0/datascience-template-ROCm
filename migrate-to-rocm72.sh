#!/bin/bash
# Migration script: ROCm 7.1 (Python 3.13) → ROCm 7.2 (Python 3.12)
# Run this from the root of your existing project directory

set -e

echo "=== ROCm 7.2 Migration Script ==="
echo ""

# Check we're in a valid project directory
if [ ! -d ".devcontainer" ]; then
    echo "ERROR: .devcontainer directory not found."
    echo "Please run this script from the root of your project."
    exit 1
fi

if [ ! -f ".devcontainer/Dockerfile" ]; then
    echo "ERROR: .devcontainer/Dockerfile not found."
    exit 1
fi

if [ ! -f ".devcontainer/devcontainer.json" ]; then
    echo "ERROR: .devcontainer/devcontainer.json not found."
    exit 1
fi

echo "Found project: $(basename $(pwd))"
echo ""

# Step 1: Update Dockerfile
echo "Step 1: Updating Dockerfile..."

cat > .devcontainer/Dockerfile << 'EOF'
# ROCm PyTorch ML Development Container
# Base: Official AMD ROCm PyTorch image (Ubuntu 24.04)
FROM rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1

# Workaround for Ubuntu 24.04 having pre-existing ubuntu user at UID 1000
# This prevents common-utils from creating users at UID 1001
# See: https://github.com/devcontainers/images/issues/1056
RUN touch /var/mail/ubuntu && chown ubuntu /var/mail/ubuntu && userdel -r ubuntu

# Install uv package manager into /opt/venv (not bundled in ROCm 7.2 unlike 7.1)
# Symlink to /usr/local/bin so it's in PATH for all users
RUN /opt/venv/bin/pip install uv && \
    ln -s /opt/venv/bin/uv /usr/local/bin/uv

# The common-utils feature will now be able to create the user with the specified UID
EOF

echo "✓ Dockerfile updated"

# Step 1b: Update setup-environment.sh
echo "Step 1b: Updating setup-environment.sh..."

# Get the directory where this script is located (to find the template)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if the template setup-environment.sh exists
if [ -f "${SCRIPT_DIR}/setup-environment.sh" ]; then
    # Copy the template but preserve the project-specific placeholders that were already substituted
    # Extract current values from existing setup-environment.sh
    if [ -f ".devcontainer/setup-environment.sh" ]; then
        CURRENT_PROJECT=$(grep -oP '(?<=WORKSPACE_DIR="/workspaces/)[^"]+' .devcontainer/setup-environment.sh || echo "")
        CURRENT_GIT_NAME=$(grep -oP '(?<=git config --global user.name ")[^"]+' .devcontainer/setup-environment.sh || echo "")
        CURRENT_GIT_EMAIL=$(grep -oP '(?<=git config --global user.email ")[^"]+' .devcontainer/setup-environment.sh || echo "")

        # Copy template and substitute values
        cp "${SCRIPT_DIR}/setup-environment.sh" .devcontainer/setup-environment.sh

        if [ -n "$CURRENT_PROJECT" ]; then
            sed -i "s/{{PROJECT_NAME}}/${CURRENT_PROJECT}/g" .devcontainer/setup-environment.sh
        fi
        if [ -n "$CURRENT_GIT_NAME" ]; then
            sed -i "s/{{GIT_NAME}}/${CURRENT_GIT_NAME}/g" .devcontainer/setup-environment.sh
        fi
        if [ -n "$CURRENT_GIT_EMAIL" ]; then
            sed -i "s/{{GIT_EMAIL}}/${CURRENT_GIT_EMAIL}/g" .devcontainer/setup-environment.sh
        fi

        echo "✓ setup-environment.sh updated with fixed uv sync order"
    else
        echo "⚠ .devcontainer/setup-environment.sh not found - skipping"
    fi
else
    echo "⚠ Template setup-environment.sh not found at ${SCRIPT_DIR}/setup-environment.sh"
    echo "  Please manually update .devcontainer/setup-environment.sh"
    echo "  Key fix: Generate exclude-dependencies BEFORE running uv add/sync"
fi

# Step 2: Update devcontainer.json
echo "Step 2: Updating devcontainer.json..."

# Add --shm-size=8G if not present
if ! grep -q '"--shm-size=' .devcontainer/devcontainer.json; then
    sed -i 's/"--ipc=host",/"--ipc=host",\n    "--shm-size=8G",/' .devcontainer/devcontainer.json
    echo "  ✓ Added --shm-size=8G"
else
    echo "  - --shm-size already present"
fi

# Add ROCBLAS_USE_HIPBLASLT if not present
if ! grep -q 'ROCBLAS_USE_HIPBLASLT' .devcontainer/devcontainer.json; then
    sed -i 's/"ROCM_HOME": "\/opt\/rocm",/"ROCM_HOME": "\/opt\/rocm",\n    "ROCBLAS_USE_HIPBLASLT": "1",\n    "PYTORCH_CUDA_ALLOC_CONF": "expandable_segments:True",/' .devcontainer/devcontainer.json
    echo "  ✓ Added ROCBLAS_USE_HIPBLASLT and PYTORCH_CUDA_ALLOC_CONF"
else
    echo "  - ROCm 7.2 env vars already present"
fi

echo "✓ devcontainer.json updated"

# Step 3: Update .python-version
echo "Step 3: Updating .python-version..."

if [ -f ".python-version" ]; then
    echo "3.12" > .python-version
    echo "✓ .python-version updated to 3.12"
else
    echo "3.12" > .python-version
    echo "✓ .python-version created with 3.12"
fi

# Step 4: Update pyproject.toml
echo "Step 4: Updating pyproject.toml..."

if [ -f "pyproject.toml" ]; then
    # Update requires-python
    if grep -q 'requires-python = ">=3.13"' pyproject.toml; then
        sed -i 's/requires-python = ">=3.13"/requires-python = ">=3.12"/' pyproject.toml
        echo "  ✓ Updated requires-python to >=3.12"
    elif grep -q 'requires-python = ">=3.12"' pyproject.toml; then
        echo "  - requires-python already set to >=3.12"
    else
        echo "  ⚠ Could not find requires-python line - please update manually"
    fi

    # Remove exclude-dependencies section (will be regenerated)
    # This is complex with sed, so we'll use Python if available
    if command -v python3 &> /dev/null; then
        python3 << 'PYEOF'
import re

with open('pyproject.toml', 'r') as f:
    content = f.read()

# Remove [tool.uv] section with exclude-dependencies
# Pattern matches from [tool.uv] to the next section or end of file
pattern = r'\[tool\.uv\]\nexclude-dependencies = \[[\s\S]*?\]\n*'
new_content = re.sub(pattern, '', content)

if new_content != content:
    with open('pyproject.toml', 'w') as f:
        f.write(new_content)
    print("  ✓ Removed old exclude-dependencies (will be regenerated)")
else:
    print("  - No exclude-dependencies section found")
PYEOF
    else
        echo "  ⚠ Python not available - please manually remove [tool.uv] exclude-dependencies section"
    fi
else
    echo "  ⚠ pyproject.toml not found - will be created on container rebuild"
fi

echo "✓ pyproject.toml updated"

# Step 5: Delete stale files
echo "Step 5: Cleaning stale files..."

if [ -d ".venv" ]; then
    rm -rf .venv
    echo "  ✓ Deleted .venv (Python 3.13 binaries incompatible)"
else
    echo "  - .venv not found"
fi

if [ -f "uv.lock" ]; then
    rm -f uv.lock
    echo "  ✓ Deleted uv.lock (will be regenerated)"
else
    echo "  - uv.lock not found"
fi

if [ -f "rocm-provided.txt" ]; then
    rm -f rocm-provided.txt
    echo "  ✓ Deleted rocm-provided.txt (will be regenerated)"
else
    echo "  - rocm-provided.txt not found"
fi

echo "✓ Stale files cleaned"

echo ""
echo "=== Migration Complete ==="
echo ""
echo "Next steps:"
echo "  1. Review the changes: git diff"
echo "  2. Rebuild container in VSCode: Ctrl+Shift+P → 'Dev Containers: Rebuild Container'"
echo "  3. Verify after rebuild:"
echo "     - python --version  # Should show 3.12.x"
echo "     - uv --version"
echo "     - python -c 'import torch; print(torch.__version__)'"
echo ""
echo "If something goes wrong, restore with: git checkout -- .devcontainer/ .python-version pyproject.toml"