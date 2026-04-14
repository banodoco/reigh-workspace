#!/bin/bash
# Manually spawn a GPU worker or manage existing ones.
#
# Usage:
#   worker-spawn.sh                    # Spawn a new worker
#   worker-spawn.sh list               # List active workers
#   worker-spawn.sh status <worker_id> # Check specific worker
#   worker-spawn.sh terminate <id>     # Terminate specific worker

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCH_DIR="$SCRIPT_DIR/../reigh-worker-orchestrator"

if [ ! -d "$ORCH_DIR" ]; then
    echo "Error: reigh-worker-orchestrator not found at $ORCH_DIR"
    exit 1
fi

cd "$ORCH_DIR"

ACTION="${1:-spawn}"

case "$ACTION" in
    list|status|spawn|terminate)
        shift 2>/dev/null || true
        PYENV_VERSION=3.11.11 python scripts/spawn_gpu.py "$ACTION" "$@"
        ;;
    *)
        echo "Usage: worker-spawn.sh [spawn|list|status|terminate] [args...]"
        exit 1
        ;;
esac
