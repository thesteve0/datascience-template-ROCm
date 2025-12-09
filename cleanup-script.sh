#!/bin/bash

PROJECT_NAME="{{PROJECT_NAME}}"

echo "Cleaning up $PROJECT_NAME ROCm development environment..."

# Detect container runtime (Docker or Podman)
if command -v docker &> /dev/null; then
    RUNTIME="docker"
elif command -v podman &> /dev/null; then
    RUNTIME="podman"
else
    echo "Error: Neither docker nor podman found"
    exit 1
fi

echo "Using container runtime: $RUNTIME"

# Stop any running devcontainer
echo "Stopping any running devcontainers..."
$RUNTIME ps -q --filter "label=devcontainer.metadata" | xargs -r $RUNTIME stop

echo "Cleanup complete. Volumes preserved."
echo ""
echo "Current volumes for this project:"
$RUNTIME volume ls --filter "name=${PROJECT_NAME}-" --format "  - {{.Name}}"
echo ""
echo "For full cleanup (deletes all data and volumes):"
echo "  $RUNTIME volume rm ${PROJECT_NAME}-models ${PROJECT_NAME}-datasets ${PROJECT_NAME}-cache-hf ${PROJECT_NAME}-cache-torch"