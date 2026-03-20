# Debugging Router

> When something breaks, start here. This document routes you to the right repo, tool, and log.

---

## Repo Map

```
Reigh-Collection/             <-- you are here
  Reigh-App/                  Frontend (React/Vite) + Supabase edge functions + main debug CLI
  Reigh-Worker/               GPU worker (Python, runs on RunPod pods)
  Reigh-Worker-Orchestrator/  Worker scaling + API task dispatch (runs on Railway)

External:
  ../Arnold/                  RunPod pod management (provides API key for pod commands)
```

---

## Quick Start

1. **A task failed or is stuck** — find your symptom in the Decision Table below
2. **Investigate a specific task** — `cd Reigh-App && python scripts/debug.py task <task_id>`
3. **Check system health** — `cd Reigh-Worker && python -m debug health` or `cd Reigh-Worker-Orchestrator && python scripts/debug.py health`
4. **Launch a test worker** — see [GPU Worker Debugging](./docs/debug-gpu-worker.md) → "Starting / Restarting a Worker"
5. **Read logs for a task** — `cd Reigh-App && python scripts/debug.py task <task_id>` (includes system_logs timeline)
6. **Deploy a fix** — find the right repo in the Repo Map, then see the component doc

---

## End-to-End Request Flow

```
User clicks Generate
  → Frontend builds payload                          Reigh-App/src/shared/lib/tasks/
  → Calls create-task edge function                  Reigh-App/supabase/functions/create-task/
  → Row inserted in `tasks` table (status: Queued)
  → Worker polls claim-next-task edge function        Reigh-App/supabase/functions/claim-next-task/
  → Worker processes task on GPU                      Reigh-Worker/worker.py
  → Worker calls complete_task edge function           Reigh-App/supabase/functions/complete_task/
  → DB trigger creates generation row
  → Realtime broadcasts to UI                         Reigh-App/src/ (React Query subscription)
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
cd Reigh-App && python scripts/debug.py task <task_id>          # Full timeline for a task
cd Reigh-App && python scripts/debug.py logs --source worker --hours 1   # Filter by source
cd Reigh-App && python scripts/debug.py logs --latest --tag MyTag        # Browser logs by tag
```

**Critical**: `system_logs` has **48h retention**. For older issues, query `tasks.error_message` directly.

---

## Decision Table

### Tier 1: Task stuck or failing

| Symptom | Repo | Confirm With | Next Step |
|---------|------|-------------|-----------|
| Task stuck Queued (<5 min) | Reigh-App (edge fn) | `debug.py queue` | Check worker heartbeat, `claim-next-task` fn, user's `cloud_enabled` setting |
| Task stuck Queued (backlog) | Orchestrator | `debug.py workers` + `debug.py queue` | Check orchestrator logs on Railway, RunPod quotas |
| Task In Progress then Failed | Reigh-Worker | `debug.py task <id>`, SSH logs on pod | Read error in worker logs → fix → push → pull on pod |
| Pipeline partially complete | Multiple | `debug.py pipeline <id>` | Find the failed child task, debug individually |
| Cascading failure stuck | Reigh-App (edge fn) | `debug.py task <id>` → system_logs | Check `update-task-status` edge fn |

### Tier 2: Task completes but output is wrong

| Symptom | Repo | Confirm With | Next Step |
|---------|------|-------------|-----------|
| Output has artifacts/seams | Reigh-Worker | `debug.py pipeline <id>` | Check FPS/resolution metadata → [Model Reference](./docs/debug-models.md) |
| Task Complete but no generation | Reigh-App (edge fn) | `debug.py task <id>` → system_logs | Check `complete_task` edge fn → [Edge Functions](./docs/debug-edge-functions.md) |
| Generation exists, not in UI | Reigh-App (frontend) | React Query cache, realtime subscription | Check subscription code in `Reigh-App/src/` |

### Tier 3: Task creation issues

| Symptom | Repo | Confirm With | Next Step |
|---------|------|-------------|-----------|
| Task never appears in DB | Reigh-App (frontend) | Chrome Network tab, `create-task` response | Check `Reigh-App/src/shared/lib/tasks/` |
| Task created with bad params | Reigh-App (frontend) | `debug.py task <id> --json` | Check `segmentTaskPayload.ts`, `payloadBuilder.ts` |

---

## Tools by Repo

Each repo has its own debug CLI. They share similar commands but target different layers.

| Repo | Run From | Key Commands |
|------|----------|-------------|
| **Reigh-App** | `cd Reigh-App && python scripts/debug.py` | `task`, `tasks`, `pipeline`, `queue`, `workers`, `logs`, `pod list/ssh`, `sql` |
| **Reigh-Worker** | `cd Reigh-Worker && python -m debug` | `task`, `tasks`, `worker`, `workers`, `health`, `orchestrator`, `config`, `runpod` |
| **Orchestrator** | `cd Reigh-Worker-Orchestrator && python scripts/debug.py` | `task`, `tasks`, `worker`, `workers`, `health`, `orchestrator`, `config`, `railway`, `infra`, `runpod` |

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
- **cloud_enabled**: Workers can only claim tasks from users with cloud processing enabled. Check with `debug.py task <id>` or SQL query in [Worker doc](./docs/debug-gpu-worker.md).
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

- [Debug CLI Reference](./docs/debug-cli.md) — full command reference across all three repos
- [GPU Worker Debugging](./docs/debug-gpu-worker.md) — SSH, pod management, logs, test tasks, fix-and-retry
- [Orchestrator Debugging](./docs/debug-orchestrator.md) — scaling, Railway, config, deployment
- [Edge Function Debugging](./docs/debug-edge-functions.md) — deployment, common issues, system_logs sources
- [Frontend Debugging](./docs/debug-frontend.md) — logging flags, console debugging
- [Model & Guidance Reference](./docs/debug-models.md) — internal names, guidance mapping, cross-model pitfalls
