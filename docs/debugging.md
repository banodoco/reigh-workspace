# Debugging Router

> When something breaks, start here. This document routes you to the right repo, tool, and log.

---

## Repo Map

```
reigh-workspace/              <-- you are here
  reigh-app/                  Frontend (React/Vite) + Supabase edge functions + main debug CLI
  reigh-worker/               GPU worker (Python, runs on RunPod pods)
  reigh-worker-orchestrator/  Worker scaling + API task dispatch (runs on Railway)

External:
  ../Arnold/                  RunPod pod management (provides API key for pod commands)
```

---

## Quick Start

1. **A task failed or is stuck** — find your symptom in the Decision Table below
2. **Investigate a specific task** — `cd reigh-app && python scripts/debug.py task <task_id>`
3. **Check system health** — `cd reigh-worker && python -m debug health` or `cd reigh-worker-orchestrator && python scripts/debug.py health`
4. **Launch a test worker** — see [GPU Worker Debugging](./debug-gpu-worker.md) → "Starting / Restarting a Worker"
5. **Read logs for a task** — `cd reigh-app && python scripts/debug.py task <task_id>` (includes system_logs timeline)
6. **Deploy a fix** — find the right repo in the Repo Map, then see the component doc

### Cross-Cutting Diagnostics

These commands cross-reference orchestrator, worker, and task data to answer higher-level questions. All run from `cd reigh-app`:

| Symptom | Command | What it shows |
|---------|---------|---------------|
| Task bounced across workers | `debug.py task-journey <task_id>` | Every state transition: Queued→InProgress→Failed→requeued, with worker IDs and error snippets |
| Worker killed unexpectedly | `debug.py why-killed <worker_id>` | Kill reason + activity before kill. Flags if worker was productive recently |
| Worker lifecycle unclear | `debug.py worker-timeline <worker_id>` | Full timeline: spawn→init→promote→claim→complete→kill |
| Workers keep dying | `debug.py scaling-audit --hours 6` | Finds productive workers killed, wasted spawns, churn rate |

---

## End-to-End Request Flow

```
User clicks Generate
  → Frontend builds payload                          reigh-app/src/shared/lib/tasks/
  → Calls create-task edge function                  reigh-app/supabase/functions/create-task/
  → Row inserted in `tasks` table (status: Queued)
  → Worker polls claim-next-task edge function        reigh-app/supabase/functions/claim-next-task/
  → Worker processes task on GPU                      reigh-worker/worker.py
  → Worker calls complete_task edge function           reigh-app/supabase/functions/complete_task/
  → DB trigger creates generation row
  → Realtime broadcasts to UI                         reigh-app/src/ (React Query subscription)
  → Video appears in gallery
```

For pipelines (e.g., video travel): Orchestrator creates parent task → spawns child segment tasks → each child follows the flow above → stitch task joins outputs.

---

## system_logs: Your Central Log

Every layer writes to a single `system_logs` Postgres table in Supabase. This is where most debugging starts.

| Who writes | `source_type` value | What's logged |
|------------|---------------------|---------------|
| Edge Functions | `edge_function` | Task lifecycle events (create, claim, status, complete) |
| GPU Workers | `worker` | Processing steps, errors, heartbeat |
| Orchestrator | `orchestrator_gpu` / `orchestrator_api` | Scaling decisions, segment coordination |
| Browser | `browser` | All console output (only when `VITE_PERSIST_LOGS=true`) |

**How to query:**
```bash
# Best way — the debug CLI pulls system_logs + task data together:
cd reigh-app && python scripts/debug.py task <task_id>          # Full timeline for a task
cd reigh-app && python scripts/debug.py logs --source worker --hours 1   # Filter by source
cd reigh-app && python scripts/debug.py logs --latest --tag MyTag        # Browser logs by tag
```

**Critical**: `system_logs` has **48h retention**. For older issues, query `tasks.error_message` directly.

---

## Decision Table

### Tier 1: Task stuck or failing

| Symptom | Repo | Confirm With | Next Step |
|---------|------|-------------|-----------|
| Task stuck Queued (<5 min) | reigh-app (edge fn) | `debug.py queue` | Check worker heartbeat, `claim-next-task` fn, user's `cloud_enabled` setting |
| Task stuck Queued (backlog) | Orchestrator | `debug.py workers` + `debug.py queue` | Check orchestrator logs on Railway, RunPod quotas |
| Task In Progress then Failed | reigh-worker | `debug.py task <id>`, SSH logs on pod | Read error in worker logs → fix → push → pull on pod |
| Pipeline partially complete | Multiple | `debug.py pipeline <id>` | Find the failed child task, debug individually |
| Cascading failure stuck | reigh-app (edge fn) | `debug.py task <id>` → system_logs | Check `update-task-status` edge fn |

### Tier 2: Task completes but output is wrong

| Symptom | Repo | Confirm With | Next Step |
|---------|------|-------------|-----------|
| Output has artifacts/seams | reigh-worker | `debug.py pipeline <id>` | Check FPS/resolution metadata → [Model Reference](./debug-models.md) |
| Task Complete but no generation | reigh-app (edge fn) | `debug.py task <id>` → system_logs | Check `complete_task` edge fn → [Edge Functions](./debug-edge-functions.md) |
| Generation exists, not in UI | reigh-app (frontend) | React Query cache, realtime subscription | Check subscription code in `reigh-app/src/` |

### Tier 3: Task creation issues

| Symptom | Repo | Confirm With | Next Step |
|---------|------|-------------|-----------|
| Task never appears in DB | reigh-app (frontend) | Chrome Network tab, `create-task` response | Check `reigh-app/src/shared/lib/tasks/` |
| Task created with bad params | reigh-app (frontend) | `debug.py task <id> --json` | Check `segmentTaskPayload.ts`, `payloadBuilder.ts` |

---

## Tools by Repo

Each repo has its own debug CLI. They share similar commands but target different layers.

| Repo | Run From | Key Commands |
|------|----------|-------------|
| **reigh-app** | `cd reigh-app && python scripts/debug.py` | `task`, `tasks`, `pipeline`, `queue`, `workers`, `logs`, `pod list/ssh`, `sql` |
| **reigh-worker** | `cd reigh-worker && python -m debug` | `task`, `tasks`, `worker`, `workers`, `health`, `orchestrator`, `config`, `runpod` |
| **Orchestrator** | `cd reigh-worker-orchestrator && python scripts/debug.py` | `task`, `tasks`, `worker`, `workers`, `health`, `orchestrator`, `config`, `railway`, `infra`, `runpod` |

### Standalone scripts (Orchestrator)

| Script | Purpose |
|--------|---------|
| `scripts/dashboard.py` | Real-time status dashboard |
| `scripts/view_logs_dashboard.py` | Interactive logs viewer |
| `scripts/monitor_worker.py` | Watch a worker until it starts logging |
| `scripts/spawn_gpu.py` | Manually spawn a GPU pod |
| `scripts/shutdown_all_workers.py` | Emergency: kill all workers, reset tasks to Queued |
| `scripts/terminate_single_worker.py` | Terminate one worker, reset its tasks |
| `scripts/ssh_to_worker.py` | SSH into a RunPod worker |
| `scripts/create_test_task.py` | Create a test task in DB |

### Standalone scripts (Worker)

| Script | Purpose |
|--------|---------|
| `scripts/gpu_diag.sh` | GPU/NVIDIA diagnostics on a pod |
| `scripts/create_test_task.py` | Create test task from known-good config |
| `scripts/run_worker_matrix.py` | Smoke test across model/guidance combinations |

See each repo's `debug/README.md` for full CLI reference.

---

## Key Gotchas

- **48h log retention**: `system_logs` is pruned after 48 hours. Use `tasks.error_message` for older issues.
- **PAT auth**: PAT goes in `Authorization: Bearer` header, NOT in `apikey` header. Edge functions accepting PATs need `verify_jwt = false` in `supabase/config.toml`.
- **cloud_enabled**: Workers can only claim tasks from users with cloud processing enabled. Check with `debug.py task <id>` or SQL query in [Worker doc](./debug-gpu-worker.md).
- **run_id uniqueness**: When duplicating test tasks, always set a new `run_id`. `complete_task` counts ALL children sharing a `run_id` — stale children cause false failures.
- **Worker init time**: ~3-4 min for CUDA/model imports after restart. Don't panic if it's not claiming immediately.

---

## Blast Radius

| If this is down... | What breaks | What still works |
|--------------------|------------|-----------------|
| **Supabase** | Everything (task creation, claiming, status, storage, realtime) | Nothing |
| **RunPod** | No new workers spawn | Existing workers finish current tasks |
| **Railway** | Orchestrator stops — no auto-scaling, no API task dispatch | GPU workers already running continue processing |
| **fal.ai / Wavespeed** | Image editing tasks fail | Video generation unaffected |

---

## Component Docs

Detailed debugging guides for each layer:

- [Debug CLI Reference](./debug-cli.md) — full command reference across all three repos
- [GPU Worker Debugging](./debug-gpu-worker.md) — SSH, pod management, logs, test tasks, fix-and-retry
- [Orchestrator Debugging](./debug-orchestrator.md) — scaling, Railway, config, deployment
- [Edge Function Debugging](./debug-edge-functions.md) — deployment, common issues, system_logs sources
- [Frontend Debugging](./debug-frontend.md) — logging flags, console debugging
- [Model & Guidance Reference](./debug-models.md) — internal names, guidance mapping, cross-model pitfalls
