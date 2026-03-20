# Orchestrator Debugging

The **reigh-worker-orchestrator** (`./reigh-worker-orchestrator/`) scales GPU workers and dispatches API tasks. It runs on Railway.

---

## Architecture

Two parallel pipelines:
- **GPU Orchestrator** — monitors task demand, spawns/terminates RunPod pods, monitors worker health
- **API Orchestrator** — claims and dispatches lightweight tasks (image editing via fal.ai/Wavespeed)

### Control loop (GPU, ~30s cycles)

1. Fetch active workers + count queued/active tasks via `task-counts` edge function
2. Compute target GPU count (`TASKS_PER_GPU_THRESHOLD=3`)
3. Check heartbeats, detect stuck/dead workers
4. Spawn new RunPod pods or terminate idle/unhealthy ones
5. Periodic: clean up orphaned tasks, check storage

---

## Key Config (env vars)

| Var | Default | Purpose |
|-----|---------|---------|
| `MIN_ACTIVE_GPUS` | 2 | Floor — always keep this many running |
| `MAX_ACTIVE_GPUS` | 10 | Ceiling |
| `TASKS_PER_GPU_THRESHOLD` | 3 | Scale up when queued tasks / GPUs > this |
| `GPU_IDLE_TIMEOUT_SEC` | 600 | Terminate after 10 min idle |
| `MAX_CONSECUTIVE_TASK_FAILURES` | 3 | Restart worker after N consecutive failures |

View current config: `python scripts/debug.py config` (add `--explain` for descriptions).

---

## Running Locally

```bash
cd reigh-worker-orchestrator

# Health overview
python -m gpu_orchestrator.main status

# Run one cycle
python -m gpu_orchestrator.main single

# Daemon mode
python -m gpu_orchestrator.main continuous

# API task loop
python -m api_orchestrator.main
```

---

## Debugging Issues

| Symptom | Check |
|---------|-------|
| Workers not spawning | Orchestrator logs on Railway, `task-counts` edge function, RunPod API quotas |
| Workers spawning but not claiming | Worker startup script, `claim-next-task` edge fn, `cloud_enabled` user setting |
| Workers dying repeatedly | `MAX_CONSECUTIVE_TASK_FAILURES`, worker heartbeat in `workers` table, RunPod pod logs |
| Orphaned tasks (stuck In Progress) | Orchestrator periodic cleanup, `workers` table heartbeat staleness |
| Too many workers | `MAX_ACTIVE_GPUS`, `GPU_IDLE_TIMEOUT_SEC`, check if tasks are completing |

---

## Useful Queries

```sql
-- Active workers and their health
SELECT id, status, current_model, last_heartbeat,
       NOW() - last_heartbeat as stale_for,
       metadata->>'runpod_id' as pod_id
FROM workers WHERE status = 'active' ORDER BY last_heartbeat DESC;

-- Worker failure streaks
SELECT w.id, COUNT(*) as recent_failures
FROM workers w JOIN tasks t ON t.worker_id = w.id
WHERE t.status = 'Failed' AND t.created_at > NOW() - interval '1 hour'
GROUP BY w.id ORDER BY recent_failures DESC;
```

---

## Deployment

```bash
cd reigh-worker-orchestrator
./deploy_to_railway.sh          # Both pipelines
./deploy_to_railway.sh --gpu    # GPU orchestrator only
./deploy_to_railway.sh --api    # API orchestrator only
```

---

## Emergency Actions

| Action | Script |
|--------|--------|
| Kill all workers + reset tasks | `python scripts/shutdown_all_workers.py` |
| Kill one worker + reset its tasks | `python scripts/terminate_single_worker.py` |
| Manually spawn a GPU pod | `python scripts/spawn_gpu.py` |
| Find orphaned pods (cost leak) | `python scripts/debug.py runpod` |
| Terminate orphaned pods | `python scripts/debug.py runpod --terminate` |
