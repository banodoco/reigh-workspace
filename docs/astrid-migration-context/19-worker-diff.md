# 19 — Worker + Orchestrator Cutover: Exact Diff onto the Bridge Claim Protocol

> **Phase-1 design artifact.** Specifies the worker-side changes to move `reigh-worker/` and
> `reigh-worker-orchestrator/` from the Supabase claim/status/upload transport onto Astrid's
> fenced attempt protocol (doc 14 §3). This doc names every replaced function, every new
> function, the bridge-client wire contract, env changes, keep/delete lists, the server-side
> atomic completion service, and a test plan. **Design spec for a future build — no repo edits,
> no implementation.** Evidence citations are repo-relative paths under
> `/Users/peteromalley/Documents/reigh-workspace/`.

## Summary

Both worker processes talk to Postgres only through HTTP today: the GPU worker via edge
functions (`claim-next-task`, `task-counts`, `update-task-status`, `complete_task`,
`generate-upload-url`, `get-task-output`, `get-orchestrator-children`) plus one raw PostgREST
heartbeat RPC, and the API orchestrator via the same edge functions plus direct service-role
PostgREST (phantom-claim recovery, metadata read/write, orphan reset, storage uploads). All of
that is deleted. In its place each worker becomes a bridge client: poll `POST /queue/claim`
with an `executor_id` + capability allowlist, drive a lease via `start`/`heartbeat`, stream
bytes into attempt-scoped quarantine via `outputs`, and settle with `complete`/`fail` — every
mutation (except heartbeat) idempotency-keyed and every attempt mutation fenced on
`lease_id` + `status_version`, with a `LeaseKeeper` that serializes heartbeat against terminal
ops so completion never submits a stale fence. Retry budgeting moves server-side into kernel
`TaskRepository.fail`/`expire_overdue` (max_attempts); client-side attempt counters, phantom
claims, signed-URL uploads, and the heartbeat `workers`/`system_logs` RPC are deleted. The API
orchestrator migrates; the GPU fleet orchestrator (RunPod spawner) is cut by the local-only
decision (doc 15 Q3).

### Key facts

- **Today's claim is a status flip, not a lease.** `claim_next_task_service_role` atomically
  moves `tasks.status` Queued→In Progress and stamps `worker_id`; no TTL column; liveness is
  inferred and swept by three recovery paths (doc 12 §2.3, §8). Astrid replaces this with
  `execution_attempts` rows carrying `lease_id`, `lease_expires_at` (300 s default),
  `status_version`, `heartbeat_counter`, and single-winner fenced transitions
  (`Astrid/astrid/core/repositories/tasks.py:1745` claim, `:1982` start, `:2204` heartbeat,
  `:2358` expire_overdue, `:2894` fail, `:3517` complete).
- **Heartbeat increments `status_version` and is deliberately not an event/receipt**
  (no `core.*.heartbeat` kind; `tasks.py:2204` docstring, doc 04 §3.9). The worker's lease
  keeper must therefore own the fence: terminal `complete`/`fail` must carry the version the
  last heartbeat returned, and heartbeat and terminal ops must not interleave.
- **Retry moves server-side.** Kernel `fail`/`expire_overdue` requeue within `max_attempts`
  (task `attempt_no < max_attempts` → requeued, else terminal failed; `tasks.py:2358`).
  `tasks.max_attempts` is a kernel column (default 1, admission sets 3 per doc 14 §2).
  The worker deletes its `is_retryable` attempts math and `requeue_task_for_retry`; it sends
  one `fail` with the error and the server decides budget (doc 14 §3: "Delete client-side
  retry counters … receipt replay and fenced attempts replace them").
- **Upload disappears; staging replaces it.** The `complete_task` base64/presigned upload
  path (`task_status.py:_update_task_status_supabase_legacy`, orchestrator
  `storage_utils.py:upload_to_supabase_storage`) is replaced by
  `POST /tasks/{task}/attempts/{attempt}/outputs`, which streams bytes into the kernel's
  per-transaction quarantine staging (`astrid/core/io/media_import.py:staging_path`,
  `.staging/<txn_id>/`), and the server-side completion service publishes them into the
  SHA-256 managed tree inside the completion transaction (doc 14 §3).
- **Executor identity is not a workers-table row.** Astrid adds no worker-registry table
  (doc 14 §4: "Do not add users, billing, worker-registry, task-types…"). `executor_id` is
  audit attribution on attempts (`execution_attempts.executor_id`); liveness is lease expiry,
  not a heartbeat sweep. The guardian's `func_worker_heartbeat_with_logs` RPC and the
  `workers`/`system_logs` writes are deleted; logs become local files.
- **The API orchestrator is migrated; the GPU fleet orchestrator is cut.** Doc 15 Q3 binds
  local-only workers on the `astrid serve` host; `reigh-worker-orchestrator/gpu_orchestrator/`
  (RunPod spawn/scale) and `reigh-worker-orchestrator-capacity-reconciler/` have no local
  counterpart and are delete-listed. `api_orchestrator/` moves onto the same bridge client.
- **[INFERENCE] Server-side routes named here** (`/queue/claim`, `/tasks/.../attempts/...`,
  `/queue/summary`, executor heartbeat) are the doc-14 §3 contract (route list is normative)
  minus what §4 calls `[BUILD]`; exact path grammar follows the existing bridge grammar in
  `Astrid/astrid/core/integrations/reigh/local_bridge_server.py` (parts-based dispatch,
  `{error, detail}` envelopes, 400/404/409/422/500 codes).

---

## 1. Current transport inventory (what each file calls today)

Every DB touch below is HTTP; the worker never opens Postgres directly (doc 03 §2.1). "edge"
= `POST {SUPABASE_URL}/functions/v1/…`; "RPC" = `POST {SUPABASE_URL}/rest/v1/rpc/…`;
"PostgREST" = supabase-python client / direct table API.

| File | Functions | Transport calls today |
|---|---|---|
| `reigh-worker/source/core/db/task_claim.py` | `poll_next_task(worker_id, same_model_only, max_task_wait_minutes)` | edge `claim-next-task` (httpx POST, 15 s): `{worker_id, run_type:"gpu", same_model_only, worker_backend, worker_profile, selector_namespace, selector_version, worker_contract_version, max_task_wait_minutes}`; 200→`{task_id, params, task_type, project_id}`, 204→EMPTY, else ERROR (`:324-463`). Route guard `_claim_route_guard` (`:113-155`) is inert on prod claims (doc 12 §2.2.5) |
| | `check_task_counts_supabase(run_type)` | edge `task-counts` (10 s): `{run_type:"gpu", include_active, worker_backend, worker_profile, selector_namespace, selector_version, worker_contract_version}` → `{totals:{queued_only, eligible_queued, active_only}}` (`:196-264`) |
| | `_orchestrator_has_incomplete_children(id)` | edge `get-orchestrator-children` (30 s); on failure assumes incomplete (`:295-322`) |
| | `check_my_assigned_tasks(worker_id)` | returns `None` — lost-claim recovery deferred to heartbeat timeout (doc 03 §2.4) |
| `reigh-worker/source/core/db/task_status.py` | `update_task_status_supabase` / `update_task_status` | wrapper → `_update_task_status_supabase_legacy` (`:210-245`) |
| | `_update_task_status_supabase_legacy(task_id, status, output_location, thumbnail_url)` | STATUS_COMPLETE + local file: edge `complete_task` base64 (<2 MB) or `generate-upload-url` → signed PUT → `complete_task{storage_path}` (≥2 MB) (`:248-495`); COMPLETE + existing storage URL / JSON passthrough: `complete_task{storage_path}` (`:496-634`); any other status: edge `update-task-status` (`:638-682`). All via `_call_edge_function_with_retry` |
| | `_mark_task_failed_via_edge_function(task_id, error)` | edge `update-task-status` `{status:"Failed", output_location:error}` (`:89-125`) |
| | `requeue_task_for_retry(task_id, error, attempts, category)` | edge `update-task-status` `{status:"Queued", attempts:N, error_details, clear_worker:true}` (`:129-192`) |
| | `mark_task_failed_supabase` / `reset_generation_started_at(task_id)` | edge `update-task-status` Failed / `{reset_generation_started_at:true}` (`:684-743`) |
| `reigh-worker/source/core/db/task_polling.py` | `query_task_status(task_id)` | edge `get-task-output`; fallback supabase client `tasks` table (`:90-114`) |
| | `get_task_output_location_from_db(_result)`, `get_task_params_result` | edge `get-task-output`; direct-DB fallback `client.table("tasks")` (`:244-393`) |
| | `poll_task_status(_result)` | loop over the above (orchestrator child polling) |
| `reigh-worker/source/core/db/lifecycle/task_status_retry.py` | `requeue_task_for_retry` | edge `update-task-status` → fallback `requeue_task_direct_db` (supabase client UPDATE) |
| `reigh-worker/source/core/db/lifecycle/task_status_complete_remote.py` | `mark_task_failed_via_edge_function`, `complete_task_with_remote_output` | edge `update-task-status` / `complete_task` |
| `reigh-worker/source/runtime/worker/guardian.py` | `send_heartbeat_with_logs(worker_id, vram_total, vram_used, logs, config, status)` | raw `curl POST {db_url}/rest/v1/rpc/func_worker_heartbeat_with_logs`, `Prefer: return=representation`, body `{worker_id_param, vram_total_mb_param, vram_used_mb_param, logs_param, status_param}` (10 s) → upsert `workers` + bulk `system_logs` (`:57-115`) |
| | `guardian_main(worker_id, worker_pid, log_queue, config)` | 20 s loop; worker-death detection → one `status="crashed"` heartbeat then exit (`:117-171`) |
| `reigh-worker/source/task_handlers/worker/heartbeat_utils.py` | `start_heartbeat_guardian_process(worker_id, supabase_url, supabase_key)` | spawns daemon `Process`; config carries `db_url` + `api_key` |
| `reigh-worker/source/media/video/storage.py` | `upload_intermediate_file_to_storage(local, task_id, filename)` | edge `generate-upload-url` `{artifact_class:"intermediate"}` → signed PUT → public URL (latent tails, chained segment outputs) (`:31-98`) |
| | `upload_and_get_final_output_location` / `resolve_final_output_location` | local-path passthrough (no transport) |
| `reigh-worker/source/runtime/worker/server.py` | main claim loop (`:810-1010`) | `poll_next_task` → `process_single_task` → `_update_task_complete` (= `update_task_status_supabase`), `update_task_status` (orchestrator progress), `requeue_task_for_retry`, `mark_task_failed` paths; `cleanup_generated_files` after success |
| `reigh-worker-orchestrator/api_orchestrator/task_utils.py` | `count_tasks(client, run_type)` | edge `task-counts` (`:41-114`) |
| | `claim_next_task(client, worker_id, run_type, known_active_ids)` | edge `claim-next-task` (30 s); on timeout `_recover_phantom_claim` does direct PostgREST SELECT of In-Progress tasks on own worker_id (`:117-207`) |
| | `mark_complete_via_edge_function` | edge `complete_task` (no output) or `update-task-status` (URL-only) (`:208-278`) |
| | `mark_failed_via_edge_function` / `mark_failed` / `mark_complete` | edge `update-task-status` Failed (`:280-346`) |
| | `update_task_metadata` / `get_task_metadata` | direct PostgREST (service role) on `tasks.metadata` (`:363-417+`) |
| `reigh-worker-orchestrator/api_orchestrator/storage_utils.py` | `upload_to_supabase_storage_only` | direct POST `storage/v1/object/image_uploads/{api-orchestrator/tasks/.../intermediates/...}` (service role) (`:37-106`) |
| | `upload_to_supabase_storage` → `_upload_direct_base64` / `_upload_presigned_url` | <2 MB: edge `complete_task` base64; ≥2 MB: edge `generate-upload-url` → PUT → edge `complete_task{storage_path}` (`:109-351`) |
| | `download_and_upload_to_supabase` / `process_external_url_result` | download external URL → `upload_to_supabase_storage` (`:355-441`) |
| `reigh-worker-orchestrator/api_orchestrator/database.py` | `DatabaseClient.register_worker` / `update_heartbeat` | supabase client upsert/update `workers` (`:23-50`) |
| | `DatabaseClient.reset_orphaned_tasks(worker_id)` | PostgREST: In-Progress tasks on own worker → `status=Queued, worker_id=NULL, generation_started_at=NULL, attempts+1` guarded `<3` (`:51-108`, doc 12 §3.2.3) |
| `reigh-worker-orchestrator/api_orchestrator/main.py` | `main_async` | boot: `DatabaseClient` + `reset_orphaned_tasks`; loop: `count_tasks` → `claim_next_task` ×`to_claim` → `spawn_task` → `process_api_task` → `mark_complete`/`mark_failed` (`:133-285`) |

Retry/failure classification lives in `reigh-worker/source/task_handlers/worker/fatal_error_handler.py`
(`RETRYABLE_ERROR_PATTERNS` max 2–3, `FATAL_ERROR_PATTERNS` → worker exit) and the requeue
decision in `server.py:936-990`. Worker entrypoints: `worker`/`run_worker` → `source.runtime.entrypoints.*`
→ `source.runtime.worker.server:main` (`pyproject.toml`, doc 03 §1.1).

---

## 2. Target wire protocol (from doc 14 §3, restated as the client contract)

Base: `ASTRID_BRIDGE_URL` (see §4). All bodies JSON; errors are the bridge envelope
`{"error": "<code>", "detail": "..."}` (bridge convention,
`Astrid/astrid/core/integrations/reigh/bridge_service.py:BRIDGE_ERROR_ENVELOPE_KEYS`).
Every state-changing request **except heartbeat** carries `Idempotency-Key`; every attempt
mutation carries `lease_id` + `status_version`.

| Route | Method | Request | Success | Errors (code → meaning) |
|---|---|---|---|---|
| `/queue/claim` | POST | `{executor_id, capabilities:[...], lease_duration:300, idempotency_key}` | 200 `{task_id, project_id, attempt_id, attempt_no, lease_id, lease_expires_at, status_version, spec, input_manifest}`; 204 no work | 400 `invalid_body`; 409 `idempotency_mismatch`; 500 `internal` |
| `/tasks/{task_id}/attempts/{attempt_id}/start` | POST | `{lease_id, status_version}` + `Idempotency-Key` | 200 attempt model (refreshed fence) | 409 `stale_status_version` / `lease_mismatch` / `attempt_not_live` / `task_not_running`; 404 `attempt_not_found` |
| `/tasks/{task_id}/attempts/{attempt_id}/heartbeat` | POST | `{lease_id, status_version, progress?}` (no key) | 200 `{status_version, lease_expires_at, heartbeat_counter}` | 409 `stale_status_version` / `lease_mismatch` / `lease_expired` / `attempt_not_live` |
| `/tasks/{task_id}/attempts/{attempt_id}/outputs` | POST | `{lease_id, status_version}` + `Idempotency-Key` + streamed bytes (multipart or chunked; one logical set) | 200 `{staging_txn_id, staged:[{filename, sha256, byte_size}]}` | 409 fence errors; 413 size; 500 `internal` |
| `/tasks/{task_id}/attempts/{attempt_id}/complete` | POST | `{lease_id, status_version, staged_manifest:{staging_txn_id, outputs:[{ordinal, role, is_primary, filename, sha256, relations?}]}}` + `Idempotency-Key` | 200 `{task_id, attempt_id, media_ids:[...], receipt_id}` | 409 fence errors; 422 `manifest_mismatch` (staged bytes ≠ manifest); 500 `internal` |
| `/tasks/{task_id}/attempts/{attempt_id}/fail` | POST | `{lease_id, status_version, error:{message, category?}}` + `Idempotency-Key` | 200 `{task_id, attempt_id, outcome:"requeued"\|"failed", attempt_no}` | 409 fence errors |
| `GET /tasks/{task_id}` (read) | GET | — | 200 `{status, spec, outputs:[...], winning_attempt_id}` | 404 `task_not_found` |
| `GET /queue/summary?capability=…` (read) | GET | — | 200 `{queued, running, blocked, by_capability:{...}}` | — |
| `POST /executors/{executor_id}/heartbeat` [BUILD, optional] | POST | `{status:"active"\|"crashed"\|"terminated", vram?, logs?}` | 200 `{ok:true}` | — |
| `GET /projects/{slug}/media/{media_id}/content` [BUILD] | GET | — | 200 stream (Range/ETag, verified bytes) | 404 `media_not_found` / `asset_not_local` |

Server-side `[BUILD]` items this doc depends on (specified in doc 14 §3–4, not built today):
cross-project capability-aware claim (extend `TaskRepository.claim`), attempt-scoped staging
route + cleanup + lost-ack tests, `ExecutorBridgeAdapter`, media serving route, and the
periodic `expire_overdue` maintenance loop in `astrid serve`.

---

## 3. Per-file diff table (deliverable 1)

Convention: **today's function(s)** → **new function(s)**; "delete" = remove entirely.

### 3.1 `reigh-worker/source/core/db/` — GPU worker DB layer

| File | Today | Becomes |
|---|---|---|
| `task_claim.py` | `poll_next_task`, `check_task_counts_supabase`, `_orchestrator_has_incomplete_children`, `_claim_route_guard`, `_requeue_backend_mismatch`, `_fail_closed_claim_decision`, `check_my_assigned_tasks`, `init_db_supabase` | Replace whole file with thin facade over the bridge client (§4): `poll_next_task(executor_id, capabilities, lease_seconds)` → `bridge.claim(...)`; `ClaimPollOutcome.CLAIMED/EMPTY/ERROR` preserved; `task_info` becomes `ClaimResult` (task_id, project_id, attempt_id, attempt_no, lease_id, lease_expires_at, status_version, spec). Delete counts gate, route guard, orchestrator-children edge, requeue helpers, assigned-tasks check, `init_db_supabase` (config validation moves to bridge config §4) |
| `task_status.py` | `update_task_status_supabase`, `_update_task_status_supabase_legacy` (base64/presigned/complete_task), `_mark_task_failed_via_edge_function`, `requeue_task_for_retry`, `mark_task_failed_supabase`, `reset_generation_started_at`, `TaskStatusUpdateResult` | Replace with terminal-op facade over bridge client + `LeaseKeeper` (§5): `complete_task_via_bridge(task_id, attempt_id, lease_id, status_version, staged_manifest)` → `keeper.complete(...)`; `fail_task_via_bridge(task_id, attempt_id, lease_id, status_version, error)` → `keeper.fail(...)`; `progress_via_bridge(progress_json)` → `keeper.progress(...)` (heartbeat with progress). Delete: base64/presigned upload branches, storage-URL passthrough, `reset_generation_started_at` (billing clock cut), `requeue_task_for_retry` (server budget). Keep `_extract_video_thumbnail` (thumbnail still derived client-side and staged as a second output with role `thumbnail` [INFERENCE]) |
| `task_polling.py` | `query_task_status`, `get_task_output_location_from_db(_result)`, `get_task_params_result`, `poll_task_status(_result)` | Replace edge/DirectDB paths with bridge read `GET /tasks/{task_id}`: `query_task_status(task_id)` → `bridge.get_task(task_id)`; params come from claim `spec_json.params` (no re-fetch needed for owned work; keep read route for child/poller lookups). Delete direct-DB fallback + `_TaskPollOptions` timeout loop (child polling replaced by kernel dependency gating + `GET /tasks/{id}`) |
| `lifecycle/task_status_retry.py` | `requeue_task_for_retry`, `requeue_task_direct_db` | Delete (server-side budget in `TaskRepository.fail`; doc 14 §3) |
| `lifecycle/task_status_complete_remote.py` | `mark_task_failed_via_edge_function`, `complete_task_with_remote_output` | Delete; replaced by §5 terminal ops. `lifecycle/task_status_complete.py` / `task_claim_flow.py` / `task_status_runtime.py` / `task_status_update_edge.py` / `task_polling_helpers.py` — sweep for edge references; keep only local-only helpers ([INFERENCE] bodies not read in this pass; grep `functions/v1`/`rest/v1` and delete those paths) |
| `edge_helpers.py`, `db/edge/*`, `db/config.py` (SUPABASE_* constants, `_call_edge_function_with_retry`, `EDGE_FAIL_PREFIX`, retryable status set) | HTTP-retry helper + env config | Delete edge helper modules; keep a minimal localhost HTTP client in the new bridge module (§5) with 2 retries on connection errors / 5xx for **idempotent-keyed** calls only, none for heartbeat |

### 3.2 `reigh-worker/source/runtime/worker/` — process model

| File | Today | Becomes |
|---|---|---|
| `guardian.py` | `send_heartbeat_with_logs` (PostgREST curl), `guardian_main` (20 s loop + crash heartbeat) | Rewrite to `executor_heartbeat_via_bridge(executor_id, status, vram)` → optional `POST /executors/{id}/heartbeat` (§4; route [BUILD]); primary job becomes **attempt-lease heartbeat while executing**: `guardian_main` owns a `LeaseKeeper` handle and calls `keeper.heartbeat()` every 30 s for the active attempt. On worker-process death: best-effort final `status="crashed"`; liveness is otherwise enforced by lease expiry (no server crash-recovery sweep needed — doc 12 §8's heartbeat crash-recovery path is superseded by `expire_overdue`) |
| `heartbeat_utils.py` | `start_heartbeat_guardian_process(worker_id, supabase_url, supabase_key)` | `start_heartbeat_guardian_process(executor_id, bridge_client, lease_keeper)`; config carries bridge URL + executor_id, no Supabase credentials |
| `server.py` | claim loop (`:810-1010`): poll → process → `_update_task_complete`/`update_task_status`/`requeue_task_for_retry` | Claim loop: `poll_next_task` → on CLAIMED call `bridge.start(task_id, attempt_id, lease_id, status_version, key)` (advances claimed→running; refresh fence) → `process_single_task` (unchanged, §7) → success: `stage_outputs` + `keeper.complete(...)`; failure: `keeper.fail(...)` with `error.category` from `is_retryable_error` (classification kept for messaging/worker-exit only — no attempts math); orchestrator progress: `keeper.progress(progress_json)` instead of `update_task_status(In Progress)`; `cleanup_generated_files` unchanged. Fence-loss handling: any 409 fence error on start/heartbeat → abort work, drop the lease, do not call complete/fail. Fatal worker errors (`FatalWorkerError`) still exit the process (§7) |
| `preflight.py`, `warm_cache.py`, `health_labels.py` | publish preflight/warm-cache into `workers.metadata` (supabase) or local state file | Keep local state file path only; drop `workers.metadata` publish. `write_worker_route_state` → writes executor capabilities to local state instead of route columns |
| `idle_release.py`, `status_display.py`, `local_http.py` | unchanged semantics | Keep as-is (no transport) |

### 3.3 `reigh-worker/source/media/video/storage.py`

| Function | Today | Becomes |
|---|---|---|
| `upload_intermediate_file_to_storage` | edge `generate-upload-url` (intermediate) → signed PUT → public URL | `upload_intermediate_to_astrid(local_file, task_id, filename)` → bridge media route `POST /projects/{slug}/media` [BUILD, content bridge doc 14 §4] → returns `media_id`; cross-worker references become `media_id`s (spec `input_manifest` resolves to media during admission, doc 14 §2). Latent-tail / chained-segment producers hand the media_id to consumers instead of a URL |
| `upload_and_get_final_output_location` / `resolve_final_output_location` | local passthrough | Keep (local output path until staging) |

### 3.4 `reigh-worker-orchestrator/` — API orchestrator

| File | Function | Becomes |
|---|---|---|
| `api_orchestrator/task_utils.py` | `count_tasks` | `count_tasks(client, capabilities)` → `GET /queue/summary` [BUILD] (replaces `task-counts` edge + `potentially_claimable` derivation) |
| | `claim_next_task` + `_recover_phantom_claim` | `claim_next_task(client, executor_id, capabilities, lease_seconds)` → `bridge.claim(...)`. **Delete `_recover_phantom_claim`** (doc 14: "Delete … phantom-claim recovery"; a lost claim response is harmless — the lease is short and `expire_overdue` requeues it; the orchestrator's `active_task_ids` set is retained for its own dedupe) |
| | `mark_complete_via_edge_function`, `mark_failed_via_edge_function`, `mark_complete`, `mark_failed` | `mark_complete(client, task, attempt, lease_id, status_version, staged_manifest)` / `mark_failed(...)` → bridge `complete`/`fail` via the shared client + keeper (§5) |
| | `update_task_metadata` / `get_task_metadata` | `get_task_metadata` → `GET /tasks/{task_id}`; `update_task_metadata` → delete (no `tasks.metadata` column in kernel; metadata rides in `spec_json`/`progress_json`) |
| `api_orchestrator/storage_utils.py` | `upload_to_supabase_storage`, `_upload_direct_base64`, `_upload_presigned_url`, `upload_to_supabase_storage_only`, `download_and_upload_to_supabase`, `process_external_url_result` | Replace upload fns with `stage_outputs_via_bridge(...)` (§5) → complete manifest. `download_and_upload_to_supabase` keeps its download half; the upload half becomes a media import via bridge media route |
| `api_orchestrator/database.py` | `DatabaseClient.register_worker`, `update_heartbeat`, `reset_orphaned_tasks` | Delete class. Executor registration → nothing (no workers table); heartbeat → executor heartbeat route (optional); orphan reset → delete (lease expiry covers; doc 14 §3) |
| `api_orchestrator/main.py` | `main_async` (boot register/reset; loop count→claim→spawn→mark) | Boot: construct `BridgeClient(executor_id, capabilities)` (no DB client, no reset). Loop: `count_tasks` → `claim_next_task` → `spawn_task` → `process_api_task` (handlers unchanged) → `stage_outputs` + `mark_complete` / `mark_failed`. `TASK_HANDLERS`/`SUPPORTED_TASK_TYPES` keep-list §7 |
| `gpu_orchestrator/`, `reigh-worker-orchestrator-capacity-reconciler/` | RunPod fleet spawn/scale, capacity intents, `pause_scaling`, sentinel consumer | **Delete from active scope** (doc 15 Q3 local-only; doc 12 §6 machinery is cloud-only). No migration of `worker_capacity_intents`/`orchestrator_leases` (FORBIDDEN_TABLES per doc 04 §2.4) |

---

## 4. Env / config changes (deliverable 3)

### 4.1 New

| Var / flag | Default | Meaning |
|---|---|---|
| `ASTRID_BRIDGE_URL` / `--bridge-url` | `http://127.0.0.1:8765` [INFERENCE — `astrid serve` port is a CLI choice, `create_local_bridge_server(port=0)`; 8765 mirrors the existing local-worker port doc 03 §1.4; pin the real value at cutover] | Base URL of `astrid serve`; replaces `SUPABASE_URL` everywhere |
| `EXECUTOR_ID` / `--executor-id` | hostname (`"local-executor"` fallback, replacing `RUNPOD_POD_ID`/`"local-worker"`, doc 03 §1.3) | Stamped into `execution_attempts.executor_id`; used in claim + heartbeat routes |
| `EXECUTOR_CAPABILITIES` / derived from `--worker-backend` + `--wgp-profile` | e.g. `["reigh.wgp", "reigh.t2v", "reigh.i2v", "reigh.vace", …]` for WGP; `["reigh.vibecomfy", ...route caps]` for VibeComfy | The capability allowlist for `/queue/claim`; replaces `worker_backend/profile/selector_*`/`route_backend_claim_decision` machinery. Capability names normalized per doc 14 §2 (`image-upscale` → `reigh.image_upscale`); exact strings [DECIDE] with the CapabilityMap agent |
| `LEASE_SECONDS` | 300 (kernel `DEFAULT_LEASE_SECONDS`) | Lease duration requested on claim |
| `HEARTBEAT_SECONDS` | 30 (doc 14 §3: "heartbeat more frequently, e.g. every 30 seconds") | Lease-keeper heartbeat cadence; must be ≪ `LEASE_SECONDS` |
| `ASTRID_MEDIA_ROOT` (worker-side only, informational) | `astrid serve`'s projects root | Not needed by the worker (no direct FS access); listed so operators know bytes land in the managed tree |
| `POLL_INTERVAL` / `--poll-interval` | 2 s active, 5–10 s idle (doc 15 Q7; today 10 s) | Claim poll cadence |
| `MAX_TASK_WAIT_MINUTES` | 5 | Kept: starvation hint for the [BUILD] cross-project claim (maps to today's `max_task_wait_minutes`, doc 03 §2.3) |

### 4.2 Deleted (Supabase surface)

- `SUPABASE_URL`, `SUPABASE_ACCESS_TOKEN` (worker PAT/service token), `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`, `REIGH_ACCESS_TOKEN` — all auth tokens/PATs cut (doc 14 §1, doc 15 Q5). The worker authenticates to the bridge by localhost binding + CORS, not credentials.
- `SUPABASE_EDGE_CLAIM_TASK_URL`, `SUPABASE_EDGE_COMPLETE_TASK_URL`, `SUPABASE_EDGE_UPDATE_TASK_URL`, `SUPABASE_EDGE_TASK_COUNTS_URL`, `SUPABASE_EDGE_GET_TASK_OUTPUT_URL`, `SUPABASE_EDGE_GET_ORCHESTRATOR_CHILDREN_URL` (`task_claim.py:207-209,297-299,396-400`; `task_status.py:91-93,270-273,640-642,705-708`).
- `REIGH_SELECTOR_VERSION`, `ROUTE_SELECTOR_VERSION`, `REIGH_WORKER_PROFILE`-style selector plumbing (`task_claim.py:_selector_namespace/_selector_version/_worker_profile`), `SUPABASE_ALLOW_DIRECT_QUERY_FALLBACK` (`config.py:279-282`), `GUARDIAN_LEGACY_PARSE_SUCCESS` (`guardian.py` JSON-parse escape hatch), `CREATE_GENERATION_IN_EDGE` (edge-side generations — replaced by the kernel completion service §6).
- CLI flags `--supabase-url`, `--supabase-access-token`, `--reigh-access-token` (`server.py` parse_args, doc 03 §1.3). Access-token boot gate (`os.environ["WORKER_ID"]`, `WAN2GP_WORKER_MODE`) stays but no token is read.
- RunPod/orchestrator env (GPU orchestrator cut): `RUNPOD_API_KEY`, `pause_scaling` reads, sentinel webhook URL — out of local scope.

### 4.3 Kept unchanged

`--main-output-dir`, `--debug`, `--queue-workers`, `--preload-model`, `--wgp-*` overrides, `--idle-release-minutes`, `--idle-onboarding-grace-seconds`, `--save-logging`, `--mask-active-frames`, `--colour-match-videos`, `VIBECOMFY_PYTHON`/`VIBECOMFY_CWD` (subprocess runner, doc 03 §3.3), `REIGH_LOCAL_WORKER_PORT` + local-worker auth (worker's own localhost HTTP server is independent of Supabase).

---

## 5. New worker-side bridge client module (deliverable 2)

Location: `reigh-worker/source/core/bridge/client.py` (+ `fence.py`, `lease_keeper.py`); the API
orchestrator mirrors it at `reigh-worker-orchestrator/api_orchestrator/bridge/`. [DECIDE] whether
this becomes a shared package; the repos share no dependency today, so a vendored copy is
acceptable for phase 1 ([INFERENCE] — no shared lib exists; doc 03 §1.1 shows separate pyprojects).

### 5.1 `BridgeClient`

```python
class BridgeClient:
    def __init__(self, base_url: str, executor_id: str, capabilities: list[str],
                 timeout_s: float = 15.0): ...

    def claim(self, lease_seconds: int = 300, idempotency_key: str) -> ClaimResult | None
        # POST /queue/claim  {executor_id, capabilities, lease_duration}
        # 204 -> None (EMPTY); 200 -> ClaimResult; 409 idempotency_mismatch -> raise
        # Idempotency key: f"reigh-exec:v1:claim:{executor_id}:{uuid4().hex}" (fresh per poll;
        #   a retried poll under the same key replays the stored result — no double-claim)

    def start(self, task_id, attempt_id, lease_id, status_version, idempotency_key) -> Fence
        # POST /tasks/{t}/attempts/{a}/start {lease_id, status_version}
        # Returns refreshed {status_version, lease_expires_at}

    def heartbeat(self, task_id, attempt_id, lease_id, status_version,
                  progress: dict | None = None) -> Fence
        # POST .../heartbeat — NO idempotency key (kernel: heartbeat is event-less/receipt-less)

    def stage_outputs(self, task_id, attempt_id, lease_id, status_version,
                      idempotency_key, files: list[Path]) -> StagingReceipt
        # POST .../outputs — streamed; returns {staging_txn_id, staged:[{filename, sha256, byte_size}]}
        # key: f"reigh-exec:v1:outputs:{task_id}:{attempt_id}:{manifest_sha256}"  (stable across
        #   byte-identical re-uploads after a crash)

    def complete(self, task_id, attempt_id, lease_id, status_version,
                 idempotency_key, staged_manifest) -> CompletionResult
        # POST .../complete; key: f"reigh-exec:v1:complete:{task_id}:{attempt_id}:{manifest_sha256}"
        #   -> replay-safe: identical bytes + same key = stored result, zero new rows

    def fail(self, task_id, attempt_id, lease_id, status_version,
             idempotency_key, error: dict) -> FailResult
        # POST .../fail; key: f"reigh-exec:v1:fail:{task_id}:{attempt_id}"

    def get_task(self, task_id) -> TaskView          # GET /tasks/{id} (read-only)
    def queue_summary(self, capabilities) -> dict    # GET /queue/summary
    def executor_heartbeat(self, status, vram=None)  # POST /executors/{id}/heartbeat (optional)
```

Serialization rules (kernel conventions, doc 04 §2/§3):
- IDs: `task_id`/`attempt_id`/`project_id` = lowercase 26-char Crockford ULIDs; `lease_id` =
  generated by the server on claim (free TEXT in DDL; [INFERENCE] propose `uuid4().hex` to match
  kernel `txn_id` convention) — the client treats it as opaque.
- Timestamps: ISO-8601 UTC with trailing `Z` (`utc_now_iso`, doc 04 §4.5).
- `status_version`/`attempt_no`: ints; the client never computes them, only echoes the latest
  fence the server returned.
- Idempotency keys are stable per logical operation (see per-method keys above) so an HTTP
  retry replays; `complete`/`outputs` keys include a SHA-256 of the canonical staged manifest so
  a post-crash re-run that re-prepares **identical bytes** replays, while different bytes under
  the same key get `409 idempotency_mismatch` (mirrors doc 14 §2's admission rule and
  `ReceiptService.check`, `astrid/core/receipts/canonical.py`).
- Error mapping: bridge envelope `{"error","detail"}` → typed `FenceError` subclasses:
  `stale_status_version`, `lease_mismatch`, `lease_expired`, `attempt_not_live`,
  `task_not_running`, `attempt_not_found` (409), `idempotency_mismatch` (409),
  `manifest_mismatch` (422), `invalid_body` (400), `internal` (500).
- Retry policy: retry (≤2, short backoff) only on connection errors and 5xx for calls carrying
  an idempotency key (`claim`/`start`/`outputs`/`complete`/`fail`); **no retry for `heartbeat`**
  (a missed heartbeat is harmless — the next one refreshes the lease; a fence error is
  terminal for the attempt). No `_call_edge_function_with_retry` port (doc 03 §4.2's 3× retry
  existed to paper over flaky cloud edges; localhost needs only blip tolerance).

### 5.2 Fence handling

- The client holds one fence per active attempt: `{lease_id, status_version, lease_expires_at}`.
- **Heartbeat** sends the current `status_version`; the response's new `status_version` becomes
  the fence (each heartbeat bumps it, kernel `tasks.py:2204`).
- **complete/fail** must send the fence exactly as of the last completed heartbeat. If the
  server still answers `stale_status_version` (a fence raced in through the writer FIFO), the
  client refreshes from the error response and retries **once**; a second fence failure is
  terminal — the attempt is lost or the lease expired, so the worker aborts (see §5.3).
- **start** after claim uses the claim response's `status_version`; `start` bumps it again, and
  the worker switches its fence to the start response.
- Any fence error on `start`/`heartbeat` marks the lease **lost**: the worker aborts the
  in-flight generation (no partial output is staged), never calls complete/fail, and lets
  `expire_overdue` requeue the task for another attempt.

**(Amended doc 26/Grok)** For an orchestrator, heartbeat is also the parent-visibility contract: the parent remains `running` under a long-lived fence while its coordinator waits, but it does not occupy a GPU execution slot. R5's bounded `progress_json` is therefore load-bearing progress, not optional telemetry; the keeper must continue heartbeating for the entire orchestration lifetime.

### 5.3 `LeaseKeeper` (serializes heartbeat vs complete/fail)

```python
class LeaseKeeper:
    """One lock; owns the live fence; serializes heartbeat against terminal ops."""
    def __init__(self, client: BridgeClient, task_id, attempt_id): ...
    def adopt(self, fence: Fence) -> None            # after claim/start
    def heartbeat_loop(self, interval_s: float, progress_fn=None) -> None
        # loop: with self._lock: client.heartbeat(...); update fence
        # exit conditions: stop() called, fence error (-> lost), or lease window gone
    def progress(self, progress_json: dict) -> bool  # heartbeat carrying progress (orchestrators)
    def complete(self, idempotency_key, staged_manifest) -> CompletionResult
    def fail(self, idempotency_key, error: dict) -> FailResult
    def lost(self) -> bool
    def stop(self) -> None
```

Guarantees (doc 14 §3: "the worker's lease keeper must serialize heartbeat with complete/fail
so completion cannot submit a stale fence"):
- Every network call (`heartbeat`, `complete`, `fail`, `start`) executes **while holding the
  keeper lock**, so at most one fence-mutating call is in flight per attempt. Localhost calls
  are milliseconds; the lock is not a throughput concern.
- `complete`/`fail` snapshot `(lease_id, status_version)` under the lock immediately before the
  HTTP call — always the post-last-heartbeat fence.
- On `lost()` the heartbeat loop exits and `complete`/`fail` raise `LeaseLostError`; the caller
  aborts execution and skips staging.
- The guardian owns the keeper for its 30 s heartbeat cadence; `server.py`'s task thread owns
  it for the terminal op. Both share the same keeper instance (created per claimed attempt).

**(Amended doc 26/Grok)** Orchestrator recovery is a cutover requirement, not follow-up polish. Every accepted child R1 call has a deterministic key and receipt. After coordinator/worker crash and parent reclaim, the coordinator must replay each identical stable child plan and key with the current live reclaim fence (doc 18 §2.4), rebuild the logical-child→kernel-ULID map from replay responses, and only then resume aggregation; it must never guess that an unacknowledged child was absent or create a replacement under a new key. The long-lived parent keeper plus this crash-replay path is the real orchestrator cutover risk and must be designed now.

### 5.4 Staging flow (worker side)

1. Generation finishes → local output file(s) at `<main_output_dir>/<task_type>/<task_id>_<file>`
   (unchanged, doc 03 §4.1) + optional thumbnail (cv2 first-frame, unchanged).
2. `bridge.stage_outputs(task, attempt, lease_id, status_version, key, files)` streams bytes to
   the attempt-scoped quarantine; server records digests and returns `staging_txn_id`.
3. `bridge.complete(..., staged_manifest)` with `outputs:[{ordinal:0, role:"result",
   is_primary:true, filename, sha256}, {ordinal:1, role:"thumbnail", is_primary:false, ...}]`.
   Lineage relations (`derived_from` input media, `variant_of`, `uses_as_input`) ride in each
   output's optional `relations` (kernel `media_relations` kinds, doc 04 §3.13).
4. On success: `cleanup_generated_files` (unchanged, doc 03 §4.5). On `manifest_mismatch` or
   fence error: staging is GC'd server-side; worker handles per §5.2.

---

## 6. Server-side atomic completion service (deliverable 5)

`[BUILD]` in `Astrid/astrid/core/integrations/reigh/` — one service (`ReighCompletionService`)
that composes the **existing kernel repositories** inside one writer transaction. Kernel facts
used: `TaskRepository.complete` is already atomic for bytes→media→outputs→terminal state
(`Astrid/astrid/core/repositories/tasks.py:3517-3703`, injected `media_repo.materialize_prepared`
per output, `task_outputs` rows, attempt `succeeded` + version bump, task `succeeded` +
`winning_attempt_id`, dependent unblocking `_unblock_eligible_dependents:4073`, run projection
`_update_run_projection_on_child_terminal:4115`, `core.task.completed` event + one complete
receipt). The completion service adds the Reigh projection steps (generation, shot placement)
**in the same `BEGIN IMMEDIATE`** via the writer FIFO (doc 04 §2.4: one command = one callback).

### Phase A — outside the writer (no lock held)

1. **Verify staged bytes.** Locate the attempt's quarantine (`.astrid/media/.staging/<txn_id>`,
   `media_import.py:staging_path`); `verify_staged_media` re-hashes each staged file and
   requires a match with the staged manifest (`media_import.py:817`). Missing/ mismatched →
   `422 manifest_mismatch`, GC staging, **zero writer work**.
2. **Prepare.** `prepare_media_file(path)` per staged file → `PreparedMedia` (digest, byte_size,
   mime, kind) (`media_import.py:428`). Hashing happens here, outside the txn (the kernel never
   hashes under the writer lock).
3. **Build the output list** deterministically: `{ordinal, role ("result" for primary),
   is_primary (exactly one), label, prepared, relations}` — mirroring
   `TaskRepository._normalize_completion_outputs` (`tasks.py:3941`). Lineage targets come from
   `spec_json.output_policy` (based_on_generation_id) and `input_manifest` (derived_from
   input media ids).
4. **Resolve project_id** (from task row, read-only connection) and build the complete idempotency
   key from the request (`reigh-exec:v1:complete:{task}:{attempt}:{manifest_sha256}`).

### Phase B — one `writer.submit(callback)`, one `BEGIN IMMEDIATE`

Exact kernel calls in order:

| # | Call | What it commits |
|---|---|---|
| B1 | `TaskRepository.complete(uow, project_id, task_id, attempt_id, lease_id, expected_status_version, idempotency_key, outputs, media_repo=MediaRepository(...), actor_kind="executor")` | Fence checks (task running / attempt live / lease match / version match — `tasks.py:3555-3600`); per output `media_repo.materialize_prepared(uow, project_id, prepared, idempotency_key=<completion key + ordinal>, realm="managed_local", relations=...)` → bytes published/verified-reused, `media` row (project-scoped SHA-256 dedupe), `media_locations`, `media_relations`, `core.media.imported`/`core.media.related` events (`media.py:1603`); `task_outputs` inserts; attempt → `succeeded` (version+1, finished_at); task → `succeeded`, `winning_attempt_id`, `finished_at`; hard dependents unblocked; parent run projection recomputed; `core.task.completed` event; **one complete receipt** (`tasks.py:3601-3940`) |
| B2 | `GenerationsRepository.create_generation(uow, project_id, task_id, media_id=<primary>, type=<from capability>, based_on_generation_id=<output_policy>, params_json=<spec_json.params>, ...)` + `create_variant(...)` per non-primary output — **[BUILD]** per doc 14 §4 DDL (`generations`/`generation_variants` pack tables) | Generation projection + pack events/receipts, same txn |
| B3 | `ShotGenerationsRepository.add_item(uow, project_id, shot_id, generation_id, timeline_frame=<output_policy.timeline_placement>, sort_key=...)` — **[BUILD]** (`shot_generation_items` per doc 14 §4); if the placement targets `shot_items` directly instead, `ShotRepository.add_item(uow, ...)` (`Astrid/astrid/packs/shots/repository.py:747`) | Shot placement, same txn |
| B4 | Optional timeline registry entry: `TimelineRepository.save(uow, project_id, timeline_id, config=..., registry=<merged asset registry>, expected_version=<head>)` (`Astrid/astrid/packs/timeline/repository.py:840`) **only when** `output_policy.timeline_placement.timeline_id` is set and a registry entry is required | Timeline document CAS update. **Risk:** full-document CAS on the editor's timeline — a registry-only append that preserves the editor's `config` is **[BUILD]**, or defer this step for v1 and let the editor's save path absorb new assets ([DECIDE], see §8) |

If any B step raises (fence error, manifest mismatch, generation conflict, CAS 409), the whole
callback rolls back: task stays `running`, no media/outputs/generation rows exist, no receipt;
the attempt lease then expires and `expire_overdue` requeues (or fails exhausted) — the worker
never sees a half-committed task. **This is the "completion atomicity" risk of doc 14 §R2.**
Note B2/B3 are new pack repos whose commands run inside the same UoW as B1 — kernel precedent
for multi-repository single-txn composition is the v10 migration's `runs.create → claim →
start → complete` sequence per run (doc 11 §4), but those were separate commits; single-txn
composition of task + pack mutations is **[INFERENCE]** consistent with `UnitOfWork` (doc 04
§2.4) and is exactly what doc 14 §3 mandates ("one writer transaction").

### Phase C — after commit

1. GC staged bytes (`gc_unreferenced_staging`, `media_import.py:968`), keeping live txn ids.
2. Respond `200 {task_id, attempt_id, media_ids, receipt_id}` — receipt-secrecy rules apply
   (never expose `txn_id`/`idempotency_key`/`request_hash`; `bridge_service.py:RECEIPT_SECRECY_FIELDS`).
3. The maintenance loop in `astrid serve` continues calling `TaskRepository.expire_overdue`
   periodically ([BUILD], doc 14 §3) — this is what retries/fails work whose worker vanished.

---

## 7. Keep-list vs delete-list (deliverable 4)

### Keep (no change, or local-only change)

| Item | Where | Note |
|---|---|---|
| `TaskRegistry.dispatch` + all task handlers | `reigh-worker/source/task_handlers/tasks/task_registry.py:1550+`, `tasks/`, `travel/`, `join/`, `edit_video_orchestrator.py`, `qwen_handler.py`, `models/comfy/vibecomfy_adapter.py` | Doc 14 §3: "Keep TaskRegistry and the current WGP/VibeComfy handlers initially". Handlers consume `spec_json.params` = today's `params` shape (doc 03 §3) |
| `HeadlessTaskQueue`, `task_processor.py`, `headless_wgp.py` | queue internals | Unchanged; direct-queue task types keep routing via capability (route resolution `template_routing.py` replaced by capability allowlist) |
| `task_conversion.py` param whitelist, `download_utils.py`, `output_paths.py`, `fatal_error_handler.py` | | Keep; `fatal_error_handler` drops its attempts math (max_attempts constants) but keeps `FATAL_ERROR_PATTERNS` worker-exit semantics and `is_retryable_error` for error **category** tagging on `fail` |
| `cleanup_generated_files`, local output layout | `worker_utils.py`, doc 03 §4.5 | Unchanged (local filesystem only) |
| Idle release, warm cache, preflight local-state file, status display, local HTTP server | `idle_release.py`, `warm_cache.py`, `preflight.py` (local file path), `local_http.py` | Keep; drop the `workers.metadata` publish half |
| API orchestrator handlers + dispatch | `reigh-worker-orchestrator/api_orchestrator/task_handlers.py`, `fal_utils.py`, `wavespeed_utils.py`, `video_utils.py`, `image_utils.py` | Unchanged; only transport call sites replaced |
| `shadow_side_effects.py` | orchestrator | Keep as the test harness (shadow mode maps to bridge stubs) [INFERENCE] |
| Worker entrypoints (`worker`, `run_worker`, `headless_model_management`) | `source/runtime/entrypoints/*` | Keep; CLI flags change per §4. `heartbeat_guardian` entrypoint stays an in-process-only spawn (still errors standalone) |

### Delete

| Item | Where | Replaced by |
|---|---|---|
| Client-side retry counters + requeue | `server.py:936-990` attempts math; `requeue_task_for_retry`/`requeue_task_direct_db` (`lifecycle/task_status_retry.py`); `_requeue_backend_mismatch`/`_fail_closed_claim_decision` (`task_claim.py`) | Server budget in `TaskRepository.fail`/`expire_overdue` (max_attempts) |
| Phantom-claim recovery | `api_orchestrator/task_utils.py:_recover_phantom_claim:117-150` | Nothing (lease expiry; doc 14 §3) |
| Signed-URL / base64 upload path | `task_status.py:_update_task_status_supabase_legacy` upload branches; `storage_utils.py:_upload_direct_base64/_upload_presigned_url/upload_to_supabase_storage*`; `media/video/storage.py:upload_intermediate_file_to_storage` | `outputs` staging route + media import route (§5.4, §6) |
| Heartbeat RPC + workers/system_logs | `guardian.py:send_heartbeat_with_logs` curl RPC; `heartbeat_utils.py` supabase config; `DatabaseClient.register_worker/update_heartbeat/reset_orphaned_tasks` (`database.py`) | Lease-expiry liveness + optional executor heartbeat route; logs to local files |
| `task-counts` edge gate | `task_claim.py:check_task_counts_supabase`, `task_utils.py:count_tasks` | `GET /queue/summary` [BUILD] |
| `complete_task`/`update-task-status`/`get-task-output`/`generate-upload-url`/`get-orchestrator-children` edge calls | all files above | Bridge routes (§2) |
| Route-selector claim machinery | `_claim_route_guard`, `_selector_*`, `claimed_backend` checks | Capability allowlist on `/queue/claim` |
| `reset_generation_started_at` | `task_status.py` | Credits/billing clock cut (doc 15 Q5); kernel has no billing clock |
| GPU fleet orchestrator + capacity reconciler + sentinel/pause_scaling consumers | `gpu_orchestrator/`, `-capacity-reconciler/` | Out of local scope (doc 15 Q3); kernel has no worker-registry tables (doc 14 §4) |
| `_call_edge_function_with_retry`, `EDGE_FAIL_PREFIX`, `edge_helpers.py`, `db/edge/*` | worker + orchestrator | Localhost bridge client retry policy (§5.1) |

---

## 8. Test plan (deliverable 6)

All against the real bridge + kernel (`astrid serve` on a scratch projects root), one worker
process or a test double implementing `BridgeClient`. Failure semantics asserted: fences reject
stale mutations with **zero rows changed**; receipts make replays exactly-once; nothing partial
can commit.

| # | Scenario | Setup | Assert |
|---|---|---|---|
| T1 | **Replay idempotency (complete)** | Claim → start → stage bytes → complete with key K. Repeat complete with same key K + identical manifest (simulated network retry / lost ack) | Second call returns the stored result, `receipt_id` equal, zero new `task_outputs`/`media`/`events` rows; task `succeeded` once |
| T2 | **Replay mismatch (complete)** | As T1, but second complete under K with **different** staged bytes/manifest | `409 idempotency_mismatch`; no rows changed |
| T3 | **Fence staleness (complete)** | Claim → start (v1) → heartbeat (v2) → **suppress keeper refresh** → complete with stale v1 | `409 stale_status_version`; attempt still live (`running`, same `lease_id`); no media/outputs. Then retry with v2 → `200`; exactly one completion |
| T4 | **Fence staleness (fail)** | Same shape with `fail` and stale version | `409 stale_status_version`, zero rows; retry with fresh version → `200 outcome:"requeued"` |
| T5 | **Lease expiry → requeue → attempt 2 → terminal fail** | Claim (attempt 1, lease 300 s), `start`, then stop heartbeats; run `expire_overdue` after expiry (or wait for the serve maintenance loop) | Attempt 1 → `expired`, task requeued `queued`; next claim → `attempt_no:2`, fresh `attempt_id`/`lease_id`/`status_version:1`; `fail` attempt 2 with budget exhausted (attempt_no ≥ max_attempts=3… use admission with `max_attempts:2` for the test) → `outcome:"failed"`, task terminal `failed`, subsequent claims → 204 |
| T6 | **Crash recovery** | Claim + start, kill worker process mid-generation (SIGKILL), no crash heartbeat | Lease expires → `expire_overdue` requeues (attempt 2) → a fresh worker claims and completes successfully. Old attempt's outputs (if any staged) are GC'd; no terminal double-write |
| T7 | **Cancellation** | Claim + start a long task; issue cancel (bridge task route / SDK `TaskRepository.cancel`); then worker calls complete/fail with its fence | Attempt → `cancelled`, task → `cancelled`; late `complete`/`fail` → `409 attempt_not_live` (or `task_not_running`), zero rows changed; staged bytes GC'd |
| T8 | **Keeper serialization** | Start heartbeat loop at 30 s; concurrently fire complete at t=29.9 s (inside lock window) | Exactly one terminal outcome; complete's fence equals the post-heartbeat `status_version`; no `stale_status_version` observed (repeat 50×) |
| T9 | **Atomic completion** | Claim → stage 2 outputs (result + thumbnail) with relations; complete with a poisoned second file (staged bytes ≠ manifest hash) | `422 manifest_mismatch` (or fence error), task still `running`; `task_outputs`/`media`/`generations`/shot rows all zero; staging GC'd; lease expiry then requeues |
| T10 | **Dependency unblocking** | Two tasks, B hard-depends on A (doc 14 §2 `task_dependencies`); complete A | A `succeeded`; B auto-advances `blocked`→`queued` in the same transaction (`_unblock_eligible_dependents`); B claimable next poll |
| T11 | **Orchestrator progress** | Orchestrator task; worker sends `progress` heartbeats then completes with a JSON-typed output manifest (existing `[ORCHESTRATOR_COMPLETE]` JSON path, doc 03 §3.1) | `progress_json` lands on the attempt; completion's primary output is the JSON-passed media id; no `In Progress` status pings exist anywhere |
| T12 | **Claim capability gate** | Worker claims with capabilities `["reigh.t2v"]`; queue holds a `reigh.i2v` task and a `reigh.t2v` task | Only the t2v task is ever returned; the i2v task stays `queued` (cross-project claim allowlist, doc 14 §3 `[BUILD]`) |

**Lost-ack / guard tests** (T1, T2, T4) double as the "lost-ack tests" doc 14 §4 lists for the
bridge staging routes. **Fence-error matrix** (T3/T4/T7) must assert the typed code AND the
"zero rows changed" invariant (kernel commands check all fences before any mutation —
`tasks.py:3555+`). **Idempotency scope**: keys are per logical op; T1/T2 prove byte-stable
replay semantics across a worker crash (re-stage identical bytes → same key → replay).

---

## 9. Open questions

1. **Exact capability strings** for the allowlist (e.g. `reigh.wgp.t2v` vs `reigh.t2v`, wildcard
   `reigh.wgp.*` vs enumerated): the claim service matches on these — confirm with the
   CapabilityMap artifact before freezing the client default.
2. **`astrid serve` port** for `ASTRID_BRIDGE_URL` (bridge server binds `port=0` by default;
   §4.1 default is [INFERENCE]) and whether `serve` exposes the executor routes on the same
   listener.
3. **Generation projection transaction boundary**: doc 14 §3 mandates one writer transaction
   (B1+B2+B3+B4 in one `BEGIN IMMEDIATE`), but that requires nesting pack-repository commands
   inside `TaskRepository.complete`'s UoW. Confirm the kernel composition root exposes a
   multi-repository single-callback UoW; otherwise the generation/shot steps must be a
   follow-on command gated on the completion receipt (loses strict atomicity for those rows).
4. **Timeline registry entry (B4)**: registry-only append [BUILD] vs deferring to the editor
   save path — a full-document CAS from the completion service risks clobbering editor state.
5. **Staging transport**: multipart vs chunked streaming for `POST .../outputs`, and the
   per-attempt staging quota / GC trigger (doc 14 §4: "attempt-scoped staging, cleanup,
   request-size limits").
6. **Executor observability**: kernel has no worker table (doc 14 §4); is the optional executor
   heartbeat route enough for operator visibility, or should `execution_attempts` carry
   `last_heartbeat_at` semantics (already present) plus VRAM in `progress_json`?
7. **`progress_json` schema** for orchestrator progress pings (today's `In Progress` +
   `output_location` writes; doc 03 §5.1) — needs a canonical shape the app can poll.
8. **Shared bridge client** (vendored copies in both repos vs a shared package) and whether the
   orchestrator keeps its `shadow_side_effects` harness against bridge stubs.
9. **`max_task_wait_minutes` / starvation** mapping into the [BUILD] cross-project claim
   (kernel claim has no starvation parameter today; doc 03 §2.3's model-affinity logic is
   capability-level, not model-level, after the cutover).
10. **API task types**: the api orchestrator's `SUPPORTED_TASK_TYPES` are cloud-API families
    (`fal`/`wavespeed`); confirm they remain in the local capability allowlist or are cut with
    the cloud surface (doc 15 Q5).
