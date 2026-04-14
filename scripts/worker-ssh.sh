#!/bin/bash
# SSH into a RunPod worker to check its status directly.
#
# Usage:
#   worker-ssh.sh <runpod_id>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCH_DIR="$SCRIPT_DIR/../reigh-worker-orchestrator"

if [ ! -d "$ORCH_DIR" ]; then
    echo "Error: reigh-worker-orchestrator not found at $ORCH_DIR"
    exit 1
fi

if [ -z "$1" ]; then
    echo "Usage: worker-ssh.sh <runpod_id>"
    echo ""
    echo "Find RunPod IDs with: worker-debug.sh workers"
    exit 1
fi

cd "$ORCH_DIR"
PYENV_VERSION=3.11.11 python scripts/ssh_to_worker.py "$1"
