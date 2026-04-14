#!/bin/bash
# Debug tasks, workers, and system health.
#
# Usage:
#   worker-debug.sh task <task_id>      # Investigate specific task
#   worker-debug.sh worker <worker_id>  # Investigate specific worker
#   worker-debug.sh tasks               # Analyze recent tasks
#   worker-debug.sh workers             # List recent workers
#   worker-debug.sh health              # System health check
#   worker-debug.sh orchestrator        # Orchestrator status
#   worker-debug.sh infra               # Infrastructure analysis
#
# Options:
#   --json          Output as JSON
#   --hours N       Time window in hours
#   --limit N       Limit results

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ORCH_DIR="$SCRIPT_DIR/../reigh-worker-orchestrator"

if [ ! -d "$ORCH_DIR" ]; then
    echo "Error: reigh-worker-orchestrator not found at $ORCH_DIR"
    exit 1
fi

cd "$ORCH_DIR"
PYENV_VERSION=3.11.11 python scripts/debug.py "$@"
