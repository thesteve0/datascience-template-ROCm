#!/bin/bash
set -e

# ==============================================================================
# ROCm Data Science DevContainer Setup Script - Existing Repository Mode
#
# Wraps an existing git repository with ROCm devcontainer infrastructure.
# The repository becomes the devcontainer workspace root — not a subdirectory.
#
# Usage: Run from the datascience-template-ROCm directory.
#        The target repository will be cloned as a sibling directory.
#
# Example:
#   ./setup-project-existing.sh --repo git@github.com:user/my-ml-project.git --ide jetbrains
# ==============================================================================

# Parse arguments
CLONE_REPO=""
IDE_CHOICE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)
            CLONE_REPO="$2"
            shift 2
            ;;
        --ide)
            IDE_CHOICE="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 --repo <git-url> [--ide <vscode|jetbrains|both>]"
            echo ""
            echo "This script adds ROCm devcontainer infrastructure to an existing git repository."
            echo "The repository is cloned as a sibling directory to the template."
            echo ""
            echo "Run this from the datascience-template-ROCm directory."
            exit 1
            ;;
    esac
done

if [ -z "$CLONE_REPO" ]; then
    echo "Error: --repo is required"
    echo "Usage: $0 --repo <git-url> [--ide <vscode|jetbrains|both>]"
    exit 1
fi

# ==============================================================================
# --- Configuration ---
# ==============================================================================

TEMPLATE_DIR="$PWD"

# Derive project name from repo URL (strips .git suffix)
PROJECT_NAME=$(basename "$CLONE_REPO" .git)

# Target directory: sibling of the template directory
PARENT_DIR=$(dirname "$PWD")
TARGET_DIR="$PARENT_DIR/$PROJECT_NAME"

# Git identity from global .gitconfig
GIT_NAME=$(git config user.name 2>/dev/null || echo "Your Name")
GIT_EMAIL=$(git config user.email 2>/dev/null || echo "your.email@example.com")

# Container user identity
DEV_USER=$(whoami)-devcontainer
DEV_UID=2112

# ==============================================================================
# --- Validate template directory ---
# ==============================================================================

echo "Validating template directory..."
for required in devcontainer-existing.json Dockerfile setup-environment-existing.sh resolve-dependencies.py; do
    if [ ! -f "$TEMPLATE_DIR/$required" ]; then
        echo "Error: Required file '$required' not found in $TEMPLATE_DIR"
        echo "Make sure you are running this script from the datascience-template-ROCm directory."
        exit 1
    fi
done
echo "✓ Template files found"

# ==============================================================================
# --- IDE Selection ---
# ==============================================================================

if [ -z "$IDE_CHOICE" ]; then
    echo ""
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
# --- Clone repository ---
# ==============================================================================

if [ -d "$TARGET_DIR" ]; then
    echo "Error: Target directory already exists: $TARGET_DIR"
    echo "Remove it first or choose a different location."
    exit 1
fi

echo ""
echo "Cloning $CLONE_REPO"
echo "  into $TARGET_DIR ..."
git clone "$CLONE_REPO" "$TARGET_DIR"
echo "✓ Repository cloned"

cd "$TARGET_DIR"

# ==============================================================================
# --- Check for existing devcontainer ---
# ==============================================================================

if [ -d ".devcontainer" ]; then
    echo ""
    echo "⚠ Warning: This repository already has a .devcontainer/ directory."
    echo "  It will be overwritten with the ROCm devcontainer configuration."
    read -p "  Continue? [y/N]: " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        cd "$TEMPLATE_DIR"
        rm -rf "$TARGET_DIR"
        echo "Aborted. Removed $TARGET_DIR."
        exit 1
    fi
fi

# ==============================================================================
# --- Copy devcontainer infrastructure ---
# ==============================================================================

echo ""
echo "Setting up devcontainer configuration..."
mkdir -p .devcontainer

cp "$TEMPLATE_DIR/devcontainer-existing.json"         .devcontainer/devcontainer.json
cp "$TEMPLATE_DIR/Dockerfile"                         .devcontainer/Dockerfile
cp "$TEMPLATE_DIR/setup-environment-existing.sh"      .devcontainer/setup-environment-existing.sh
chmod 755 .devcontainer/setup-environment-existing.sh

echo "✓ Devcontainer configuration copied"

# Copy utility scripts
mkdir -p scripts
cp "$TEMPLATE_DIR/resolve-dependencies.py"  scripts/

if [ -f "$TEMPLATE_DIR/test-gpu.py" ]; then
    cp "$TEMPLATE_DIR/test-gpu.py" .
fi
if [ -f "$TEMPLATE_DIR/hello-gpu.py" ]; then
    cp "$TEMPLATE_DIR/hello-gpu.py" .
fi
if [ -f "$TEMPLATE_DIR/cleanup-script.sh" ]; then
    cp "$TEMPLATE_DIR/cleanup-script.sh" .
    chmod 755 cleanup-script.sh
fi

echo "✓ Utility scripts copied"

# ==============================================================================
# --- Replace template placeholders ---
# ==============================================================================

echo "Configuring project: $PROJECT_NAME"

# Replace in devcontainer config files
find .devcontainer -name "*.json" -o -name "*.sh" | xargs sed -i \
    -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
    -e "s/{{GIT_NAME}}/$GIT_NAME/g" \
    -e "s/{{GIT_EMAIL}}/$GIT_EMAIL/g" \
    -e "s/{{DEV_USER}}/$DEV_USER/g" \
    -e "s/{{DEV_UID}}/$DEV_UID/g"

# Replace in cleanup script (has {{PROJECT_NAME}})
if [ -f "cleanup-script.sh" ]; then
    sed -i \
        -e "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" \
        -e "s/{{DEV_USER}}/$DEV_USER/g" \
        -e "s/{{DEV_UID}}/$DEV_UID/g" \
        cleanup-script.sh
fi

echo "✓ Placeholders replaced"

# ==============================================================================
# --- Create required directories ---
# ==============================================================================

mkdir -p models datasets .cache
echo "✓ Created models/, datasets/, .cache/"

# ==============================================================================
# --- Update .gitignore ---
# ==============================================================================

for entry in ".existing-project" ".venv/" "models/" "datasets/" ".cache/" "rocm-provided.txt"; do
    if ! grep -qxF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
        echo "  Added '$entry' to .gitignore"
    fi
done

# ==============================================================================
# --- Write marker file ---
# ==============================================================================

touch .existing-project
echo "✓ Marked as existing project (setup-environment-existing.sh will handle venv and deps)"

# ==============================================================================
# --- IDE-specific setup ---
# ==============================================================================

if [ "$IDE_CHOICE" = "jetbrains" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo "Creating .idea/ with Python module configuration..."

    rm -rf .idea
    mkdir -p .idea

    cat > ".idea/${PROJECT_NAME}.iml" << IDEA_IML_EOF
<?xml version="1.0" encoding="UTF-8"?>
<module type="PYTHON_MODULE" version="4">
  <component name="NewModuleRootManager">
    <content url="file://\$MODULE_DIR\$">
      <sourceFolder url="file://\$MODULE_DIR\$/src" isTestSource="false" />
      <sourceFolder url="file://\$MODULE_DIR\$/tests" isTestSource="true" />
      <excludeFolder url="file://\$MODULE_DIR\$/.venv" />
      <excludeFolder url="file://\$MODULE_DIR\$/.cache" />
      <excludeFolder url="file://\$MODULE_DIR\$/models" />
      <excludeFolder url="file://\$MODULE_DIR\$/datasets" />
    </content>
    <orderEntry type="jdk" jdkName="Python 3.12 (${PROJECT_NAME})" jdkType="Python SDK" />
    <orderEntry type="sourceFolder" forTests="false" />
  </component>
</module>
IDEA_IML_EOF

    cat > .idea/misc.xml << 'IDEA_MISC_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectRootManager" version="2" project-jdk-name="Python 3.12 (${PROJECT_NAME})" project-jdk-type="Python SDK" />
</project>
IDEA_MISC_EOF
    sed -i "s/\${PROJECT_NAME}/${PROJECT_NAME}/g" .idea/misc.xml

    cat > .idea/modules.xml << IDEA_MODULES_EOF
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="ProjectModuleManager">
    <modules>
      <module fileurl="file://\$PROJECT_DIR\$/.idea/${PROJECT_NAME}.iml" filepath="\$PROJECT_DIR\$/.idea/${PROJECT_NAME}.iml" />
    </modules>
  </component>
</project>
IDEA_MODULES_EOF

    cat > .idea/vcs.xml << 'IDEA_VCS_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="VcsDirectoryMappings">
    <mapping directory="" vcs="Git" />
  </component>
</project>
IDEA_VCS_EOF

    cat > .idea/.gitignore << 'IDEA_GITIGNORE_EOF'
workspace.xml
tasks.xml
usage.statistics.xml
dictionaries
shelf
aws.xml
dataSources/
dataSources.local.xml
caches/
IDEA_GITIGNORE_EOF

    cat > .idea/ruff.xml << 'IDEA_RUFF_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project version="4">
  <component name="RuffConfigService">
    <option name="enableRuff" value="true" />
    <option name="useRuffFormat" value="true" />
    <option name="runRuffOnSave" value="true" />
    <option name="showRuleCode" value="true" />
  </component>
</project>
IDEA_RUFF_EOF

    echo "  ✓ .idea/ configured as Python project"
    echo "  ✓ Ruff linter/formatter enabled by default"
fi

# ==============================================================================
# --- Summary ---
# ==============================================================================

echo ""
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo "Project:  $PROJECT_NAME"
echo "Location: $TARGET_DIR"
echo "IDE:      $IDE_CHOICE"
echo ""
echo "Next steps:"
echo ""

if [ "$IDE_CHOICE" = "vscode" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo "  VSCode:"
    echo "    cd $TARGET_DIR"
    echo "    code ."
    echo "    → Reopen in Container when prompted"
    echo ""
fi

if [ "$IDE_CHOICE" = "jetbrains" ] || [ "$IDE_CHOICE" = "both" ]; then
    echo "  JetBrains:"
    echo "    Open $TARGET_DIR with JetBrains Gateway or PyCharm"
    echo "    → Configure devcontainer support"
    echo "    → Manually set Python interpreter to /workspaces/$PROJECT_NAME/.venv/bin/python"
    echo ""
fi

echo "When the container starts, setup-environment-existing.sh will automatically:"
echo "  - Create .venv using /opt/venv's Python (version-matched for ROCm compatibility)"
echo "  - Bridge ROCm packages (torch, numpy, etc.) into .venv via .pth file"
echo "  - Add ROCm package exclusions to your pyproject.toml"
echo "  - Run uv sync to install your project's dependencies"
echo ""
echo "Note: If your project uses hatchling without [tool.hatch.build.targets.wheel]"
echo "configured, uv sync will automatically use --no-install-project."
echo "See .devcontainer/setup-environment-existing.sh for details."
