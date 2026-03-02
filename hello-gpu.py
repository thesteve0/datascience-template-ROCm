#!/usr/bin/env python3
"""
Minimal GPU Hello World for ROCm PyTorch

A quick sanity check that PyTorch can access your AMD GPU.
Run this first, then use test-gpu.py for comprehensive benchmarks.

Usage:
    python hello-gpu.py
"""

import torch

print(f"PyTorch version: {torch.__version__}")
print(f"ROCm available: {torch.cuda.is_available()}")

if not torch.cuda.is_available():
    print("\nGPU not detected. Check:")
    print("  1. ROCm drivers installed on host (amd-smi)")
    print("  2. Container has GPU access (--device=/dev/kfd --device=/dev/dri)")
    exit(1)

# Create tensor on GPU
t = torch.tensor([1.0, 2.0, 3.0]).cuda()
print(f"\nTensor on GPU: {t}")
print(f"Device: {t.device}")

# Simple GPU operation
result = t * 2 + 1
print(f"GPU computation (t * 2 + 1): {result}")

# GPU info
print(f"\nGPU: {torch.cuda.get_device_name(0)}")
print(f"Memory: {torch.cuda.get_device_properties(0).total_memory / (1024**3):.1f} GB")

print("\nGPU is working! Run 'python test-gpu.py' for full benchmarks.")
