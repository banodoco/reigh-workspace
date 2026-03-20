# Debug CLI Reference

All three repos have a debug CLI. They query the same Supabase DB but surface different perspectives.

All require `.env` with `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`.

---

## Reigh-App — `python scripts/debug.py`

The broadest tool. Covers tasks, pipelines, queue, workers, logs, pods, and raw SQL.

```bash
# Task investigation
debug.py task <task_id>                    # Full analysis with logs
debug.py task <task_id> --json             # JSON output
debug.py pipeline <task_id>                # Trace multi-task pipeline (works with any task in chain)

# Listing tasks
debug.py tasks --status Failed --hours 2
debug.py tasks --type travel_segment --limit 20

# System state
debug.py queue                             # Queue depth, stuck tasks, worker capacity
debug.py workers                           # Active workers, heartbeat, pod IDs, failures

# Logs
debug.py logs --source edge_function --hours 1
debug.py logs --latest                     # Most recent browser session
debug.py logs --latest --tag MyTag         # Filter by tag

# Pod management
debug.py pod list                          # All RunPod pods with SSH commands
debug.py pod ssh <pod_id>                  # Get SSH command for a pod
debug.py pod worker <pod_id>               # Print full worker setup instructions

# Raw queries
debug.py query tasks status=Failed --limit 5
debug.py sql "SELECT ..."                  # Raw SQL (needs psycopg2)
```

Pod commands read RunPod API key from `../Arnold/.env` automatically.

---

## Reigh-Worker — `python -m debug`

Worker-focused. Includes diagnostics and config inspection.

```bash
# Task investigation
debug.py task <task_id>                    # Task analysis with logs
debug.py task <task_id> --logs-only        # Just the log timeline

# Worker investigation
debug.py worker <worker_id>                # Full worker analysis
debug.py worker <worker_id> --check-logging   # Is worker.py running?
debug.py worker <worker_id> --startup      # View initialization logs
debug.py worker <worker_id> --logs-only    # Just the log timeline

# System overview
debug.py tasks                             # Recent task statistics
debug.py workers                           # Recent worker status
debug.py health                            # Overall system health
debug.py orchestrator                      # Is orchestrator running?

# Configuration & Infrastructure
debug.py config                            # View timing/scaling settings
debug.py config --explain                  # With detailed explanations
debug.py runpod                            # Find orphaned pods ($$$ leak!)
debug.py runpod --terminate                # Terminate orphaned pods

# JSON output for any command
<command> --json
```

---

## Reigh-Worker-Orchestrator — `python scripts/debug.py`

Orchestrator-focused. Adds Railway, infra, and storage commands.

```bash
# Task investigation
debug.py task <task_id>                    # Task analysis with logs
debug.py task <task_id> --logs-only        # Just the log timeline

# Worker investigation
debug.py worker <worker_id>                # Full worker analysis
debug.py worker <worker_id> --check-logging
debug.py worker <worker_id> --startup
debug.py worker <worker_id> --logs-only

# System overview
debug.py tasks                             # Recent task statistics
debug.py workers                           # Recent worker status
debug.py health                            # Overall system health
debug.py orchestrator                      # Is orchestrator running?

# Configuration & Infrastructure
debug.py config                            # View timing/scaling settings
debug.py config --explain                  # With detailed explanations
debug.py railway                           # Railway deployment status
debug.py infra                             # Infrastructure analysis
debug.py runpod                            # Find orphaned pods
debug.py runpod --terminate                # Terminate orphaned pods
debug.py storage                           # Storage inspection

# JSON output for any command
<command> --json
```
