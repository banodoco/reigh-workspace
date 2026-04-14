#!/bin/bash
# Kill all active GPU workers and reset their tasks to Queued.
# The gpu-orchestrator will respawn fresh workers with latest code.
#
# Usage:
#   worker-kill.sh              # Shut down all workers
#   worker-kill.sh --status     # Show current worker status only

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCH_DIR="$SCRIPT_DIR/../reigh-worker-orchestrator"

if [ ! -d "$ORCH_DIR" ]; then
    echo "Error: reigh-worker-orchestrator not found at $ORCH_DIR"
    exit 1
fi

cd "$ORCH_DIR"

if [ "$1" = "--status" ]; then
    PYENV_VERSION=3.11.11 python scripts/shutdown_all_workers.py --status
else
    echo "yes" | PYENV_VERSION=3.11.11 python scripts/shutdown_all_workers.py --shutdown
fi
