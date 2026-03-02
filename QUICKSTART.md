# Quick Start Guide

This guide walks you through creating a new ML project using this ROCm template.

**Time required:** ~15 minutes (mostly waiting for container build)

## Prerequisites

Before starting, ensure you have:
- [ ] AMD GPU with ROCm 7.2 drivers installed (`amd-smi` works on host)
- [ ] Docker or Podman installed and running
- [ ] VSCode with "Dev Containers" extension (or JetBrains Gateway)

See [README.md](README.md#prerequisites) for detailed setup instructions.

---

## Step 1: Get the Template

Download or copy this template to start your new project. **Do not use `git clone`** - that would point your new project at this template's repository.

### Option A: Download ZIP (Easiest)

1. Go to the template repository on GitHub
2. Click **Code** → **Download ZIP**
3. Extract to your projects folder and rename:
   ```bash
   cd ~/projects
   unzip datascience-template-ROCm-main.zip
   mv datascience-template-ROCm-main my-ml-project
   cd my-ml-project
   ```

### Option B: Clone and Disconnect

If you prefer using git:
```bash
cd ~/projects
git clone https://github.com/thesteve0/datascience-template-ROCm.git my-ml-project
cd my-ml-project

# Remove the template's git history to start fresh
rm -rf .git .idea .vscode

# Initialize your own repository
git init
git add .
git commit -m "Initial project from ROCm template"
```

---

## Step 2: Run Project Setup

The setup script creates your project structure and configures the devcontainer:

```bash
./setup-project.sh
```

You'll be prompted to:
1. **Enter project name** (e.g., `my-ml-project`)
2. **Choose IDE** (vscode, jetbrains, or both)
3. **Enter git name and email**

This creates:
- `.devcontainer/` - Container configuration
- `src/`, `tests/`, `configs/` - Code directories
- `models/`, `datasets/`, `.cache/` - Data directories (persist across rebuilds)

---

## Step 3: Open in VSCode

```bash
code .
```

When VSCode opens, you'll see a notification:
> "Folder contains a Dev Container configuration file..."

Click **"Reopen in Container"**

**First build takes 5-10 minutes.** The container:
- Downloads the ROCm PyTorch image (~15GB)
- Installs development tools
- Configures your Python environment
- Sets up GPU access

You can watch progress in the terminal (View → Terminal).

---

## Step 4: Verify GPU Access

Once the container is running (you'll see the terminal prompt), test your GPU:

### Quick Test (30 seconds)
```bash
python hello-gpu.py
```

Expected output:
```
PyTorch version: 2.9.1+rocm7.2
ROCm available: True

Tensor on GPU: tensor([1., 2., 3.], device='cuda:0')
Device: cuda:0
GPU computation (t * 2 + 1): tensor([3., 5., 7.], device='cuda:0')

GPU: AMD Radeon 8060S
Memory: 96.0 GB

GPU is working! Run 'python test-gpu.py' for full benchmarks.
```

### Full Benchmark (2-3 minutes)
```bash
python test-gpu.py
```

This runs comprehensive CPU vs GPU comparisons and neural network training tests.

---

## Step 5: Start Coding

Your project is ready! Here's how to use it:

### Run Python Code
- **VSCode:** Open any `.py` file and press `Ctrl+F5` (Run Without Debugging)
- **Terminal:** `python src/my_ml_project/main.py`

### Add Dependencies

Edit `pyproject.toml` and add packages to the dependencies list:
```toml
[project]
dependencies = [
    "transformers",
    "datasets",
    "accelerate",
]
```

Then sync:
```bash
uv sync
```

The template automatically protects ROCm packages (torch, numpy, etc.) from being overwritten by PyPI versions.

### Create Your First Script

Create `src/my_ml_project/train.py`:
```python
import torch

# Your model and data here
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
print(f"Training on: {device}")

# Example: Simple tensor operation
x = torch.randn(1000, 1000, device=device)
y = torch.matmul(x, x.T)
print(f"Matrix multiplication result shape: {y.shape}")
```

Run it:
```bash
python src/my_ml_project/train.py
```

---

## Step 6 (Optional): Configure Claude Code

If you're using Claude Code for AI-assisted development, update `CLAUDE.md` to describe your specific project:

```bash
# Inside the container
claude

# Or edit CLAUDE.md directly with your project details
```

The template's CLAUDE.md contains generic information about the ROCm template. Replace it with:
- Your project's purpose and goals
- Key files and architecture
- Coding conventions
- Any project-specific instructions for Claude

---

## What's Next?

- **Add your ML code** to `src/your_project_name/`
- **Store models** in `models/` (persists across container rebuilds)
- **Store datasets** in `datasets/` (persists across container rebuilds)
- **Access host data** at `/data` (mounted from `~/data` on your host)

### Useful Commands

| Command | Purpose |
|---------|---------|
| `amd-smi` | Check GPU status |
| `python hello-gpu.py` | Quick GPU test |
| `python test-gpu.py` | Full GPU benchmark |
| `uv sync` | Install dependencies from pyproject.toml |
| `uv add <package>` | Add a new dependency |

### Troubleshooting

If something goes wrong, see [README.md#troubleshooting](README.md#troubleshooting) for common issues and solutions.

---

## Summary

1. **Download** template (don't `git clone`)
2. **Run** `./setup-project.sh`
3. **Open** in VSCode → "Reopen in Container"
4. **Wait** 5-10 minutes for first build
5. **Test** with `python hello-gpu.py`
6. **Code!**

You now have a fully configured ROCm PyTorch development environment.
