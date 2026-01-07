#!/bin/bash
set -e

# ==============================================================================
# ROCm Data Science DevContainer Setup Script
# Ported from: https://github.com/thesteve0/datascience-template-CUDA
# ==============================================================================

# Parse arguments
CLONE_REPO=""
IDE_CHOICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --clone-repo)
            CLONE_REPO="$2"
            shift 2
            ;;
        --ide)
            IDE_CHOICE="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--clone-repo <git-url>] [--ide <vscode|jetbrains|both>]"
            exit 1
            ;;
    esac
done

# ==============================================================================
# --- Configuration ---
# All project constants are defined here. Edit these values to change the setup.
# ==============================================================================

# Set the project name equal to the directory name
PROJECT_NAME=$(basename "$PWD")

# Automatically get Git identity from your global .gitconfig
GIT_NAME=$(git config user.name 2>/dev/null || echo "Your Name")
GIT_EMAIL=$(git config user.email 2>/dev/null || echo "your.email@example.com")

# Define the username and user ID for inside the container.
# Strategy: We delete the 'ubuntu' user (UID 1000) in the Dockerfile, then create
# our user with UID 2112 via common-utils. VSCode's automatic UID matching will
# then adjust it to match your host UID, giving automatic permission alignment.
DEV_USER=$(whoami)-devcontainer
DEV_UID=2112

# ==============================================================================
# --- IDE Selection ---
# ==============================================================================

if [ -z "$IDE_CHOICE" ]; then
    echo "Which IDE(s) do you want to configure?"
    echo "1) VSCode only"
    echo "2) JetBrains only"
    echo "3) Both VSCode and JetBrains"
    read -p "Enter choice [1-3]: " ide_num

    case $ide_num in
        1) IDE_CHOICE="vscode" ;;
        2) IDE_CHOICE="jetbrains" ;;
        3) IDE_CHOICE="both" ;;
        *)
            echo "Invalid choice. Defaulting to VSCode."
            IDE_CHOICE="vscode"
            ;;
    esac
fi

echo "IDE configuration: $IDE_CHOICE"

# ==============================================================================
# --- Script Logic ---
# ==============================================================================

echo "Setting up $PROJECT_NAME ROCm development environment..."

# Replace template placeholders in all relevant files
find . -name "*.json" -o -name "*.sh" -o -name "*.py" 2>/dev/null | xargs -r sed -i \
    -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
    -e "s/{{GIT_NAME}}/$GIT_NAME/g" \
    -e "s/{{GIT_EMAIL}}/$GIT_EMAIL/g" \
    -e "s/{{DEV_USER}}/$DEV_USER/g" \
    -e "s/{{DEV_UID}}/$DEV_UID/g"

# Create base directories
mkdir -p scripts

# Setup IDE configurations
if [ "$IDE_CHOICE" = "vscode" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo "Setting up VSCode devcontainer..."
    mkdir -p .devcontainer

    # Move/copy devcontainer files (these will be created from templates)
    if [ -f "devcontainer.json" ]; then
        mv devcontainer.json .devcontainer/
    fi
    if [ -f "Dockerfile" ]; then
        mv Dockerfile .devcontainer/
    fi
    if [ -f "setup-environment.sh" ]; then
        mv setup-environment.sh .devcontainer/
        chmod 755 .devcontainer/setup-environment.sh
    fi
fi

if [ "$IDE_CHOICE" = "jetbrains" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo "Setting up JetBrains configuration..."
    mkdir -p .idea

    # JetBrains devcontainer support is configured via .idea directory
    # This will be populated with appropriate configurations
    echo "Note: JetBrains devcontainer setup requires additional configuration"
    echo "See documentation for using JetBrains Gateway or PyCharm with devcontainers"
fi

# Move resolve-dependencies script
if [ -f "resolve-dependencies.py" ]; then
    mv resolve-dependencies.py scripts/
fi

# Handle repository modes
if [ -n "$CLONE_REPO" ]; then
    # External repo mode
    CLONED_REPO_NAME=$(basename "$CLONE_REPO" .git)
    echo "External repo mode: integrating $CLONED_REPO_NAME"

    # Check for naming conflicts
    if [ -d "$CLONED_REPO_NAME" ]; then
        echo "Error: Directory $CLONED_REPO_NAME already exists"
        exit 1
    fi

    # Update PYTHONPATH in devcontainer.json for external repo (if VSCode)
    if [ -f ".devcontainer/devcontainer.json" ]; then
        sed -i "s|\"PYTHONPATH\": \"/workspaces/$PROJECT_NAME/src\"|\"PYTHONPATH\": \"/workspaces/$PROJECT_NAME/$CLONED_REPO_NAME\"|g" .devcontainer/devcontainer.json
    fi

    # Clone repo
    git clone "$CLONE_REPO" "$CLONED_REPO_NAME"

    # Add to .gitignore
    echo "$CLONED_REPO_NAME/" >> .gitignore

    echo "Setup complete! External repo cloned to ./$CLONED_REPO_NAME"
    echo "PYTHONPATH set to /workspaces/$PROJECT_NAME/$CLONED_REPO_NAME"

else
    # Standalone mode
    echo "Standalone mode: creating project structure"

    # Create additional directories for standalone
    mkdir -p src/${PROJECT_NAME} {configs,tests,datasets,models,.cache}

    # Create Python structure
    touch src/__init__.py src/${PROJECT_NAME}/__init__.py tests/__init__.py

    # Create marker file to indicate standalone project
    # This will be used by setup-environment.sh to initialize uv project in the container
    touch .standalone-project
fi

# ==============================================================================
# --- Next Steps ---
# ==============================================================================

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "IDE: $IDE_CHOICE"
echo "Project: $PROJECT_NAME"
echo ""

if [ "$IDE_CHOICE" = "vscode" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo "VSCode Next Steps:"
    echo "  1. Open in VSCode: code ."
    echo "  2. Reopen in Container when prompted"
fi

if [ "$IDE_CHOICE" = "jetbrains" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo ""
    echo "JetBrains Next Steps:"
    echo "  1. Open with JetBrains Gateway or PyCharm"
    echo "  2. Configure devcontainer support"
fi

echo ""
if [ -n "$CLONE_REPO" ]; then
    echo "Dependency Management (External Repo):"
    echo "  Your cloned repo may have requirements.txt or pyproject.toml."
    echo "  If using requirements.txt:"
    echo "    1. In container: python scripts/resolve-dependencies.py requirements.txt"
    echo "    2. In container: uv pip install -r requirements-filtered.txt"
    echo "  If using pyproject.toml:"
    echo "    - In container: uv sync"
else
    echo "Dependency Management (uv Project):"
    echo "  This project uses uv for modern Python dependency management."
    echo "  Add dependencies:"
    echo "    - uv add <package>              # Add a dependency"
    echo "    - uv add --dev <package>        # Add a dev dependency"
    echo "    - uv sync                       # Install all dependencies"
    echo "  Note: ROCm-provided packages (PyTorch, etc.) are already available."
fi

echo ""
echo "Verify GPU Access:"
echo "  - rocm-smi"
echo "  - python -c 'import torch; print(torch.cuda.is_available())'"
echo ""