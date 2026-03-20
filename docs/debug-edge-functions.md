# Edge Function Debugging

Edge functions live in `./reigh-app/supabase/functions/`. They handle the task lifecycle and run on Supabase.

---

## Deploying

```bash
cd reigh-app
npx supabase functions deploy <function_name> --project-ref wczysqzxlwdndgxitrvc
```

Add `--no-verify-jwt` if the function needs to accept PAT auth directly (most do).

---

## Key Functions (Task Pipeline)

| Function | Role in Pipeline |
|----------|-----------------|
| `create-task` | Frontend → inserts task row |
| `claim-next-task` | Worker → claims a Queued task |
| `update-task-status` | Worker → status transitions + cascading failure |
| `complete_task` | Worker → marks Complete, triggers generation creation |
| `task-counts` | Orchestrator → reads queue depth for scaling decisions |
| `calculate-task-cost` | Post-completion → bills the user |
| `update-worker-model` | Worker → registers current model in `workers` table |

---

## Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| 401 "Invalid Token or Protected Header" | `verify_jwt` enabled + PAT auth | Add to `config.toml` with `verify_jwt = false`, redeploy with `--no-verify-jwt` |
| 409 "Invalid status transition" | Duplicate status update | Usually harmless; check if the real update succeeded |
| Task Complete but output_location empty | Two-step completion failed | Use `output_location` override in `complete_task` payload |

---

## What Writes to `system_logs`

| Source | `source_type` value | What's logged |
|--------|---------------------|---------------|
| Edge Functions | `edge_function` | Task lifecycle events from the functions above |
| Workers (GPU) | `worker` | Task processing steps, errors, via heartbeat |
| Orchestrators | `orchestrator_gpu` / `orchestrator_api` | Cycle tracking, segment coordination |
| Browser | `browser` | ALL console output (only when `VITE_PERSIST_LOGS=true`) |

Query logs: `cd reigh-app && python scripts/debug.py logs --source edge_function --hours 1`
