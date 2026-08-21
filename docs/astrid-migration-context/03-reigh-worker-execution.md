# 03 — Reigh Worker Execution: Process Model, Task Discovery, Pipelines, Artifacts, Status, Failure, Deployment

> **Context doc for the Reigh→Astrid migration.** Covers how the GPU worker (`reigh-worker/`) executes tasks end-to-end: process model, boot sequence, pull-based task discovery via Supabase Edge Functions + Postgres RPCs, per-model execution pipelines, artifact upload to Supabase Storage + DB recording, status/heartbeat reporting, failure/retry semantics, and RunPod deployment. All claims are grounded in repo files (paths cited inline). This doc describes the *current* system; it makes no migration recommendations.

## Key facts (TL;DR)

- **Pull-based discovery, no push.** The worker polls `POST {SUPABASE_URL}/functions/v1/claim-next-task` every ~10 s (default `--poll-interval`), preceded by a `task-counts` gate call. Claiming is atomic on the server: the Postgres function `claim_next_task_service_role(...)` flips `tasks.status` `Queued → In Progress`, stamps `worker_id` + `generation_started_at` + route-claim columns, and returns `task_id`, `params` (JSONB), `task_type`, `project_id` (+ route decision fields).
- **Single-process model.** One Python 3.10 process (Wan2GP imported in-process), a `HeadlessTaskQueue` with 1 worker thread (default `--queue-workers 1`), a separate heartbeat-guardian child process, and (local-worker mode only) a localhost HTTP server. Exit paths: fatal error → exit 1; idle release → exit code 75 (`IDLE_RELEASE_EXIT_CODE`, `source/runtime/worker_protocol.py`); signals → clean shutdown.
- **Dispatch by `task_type`.** `TaskRegistry.dispatch()` routes WGP generation types to the in-process queue (direct queue tasks), orchestrator/segment/stitch/edit types to specialized handlers that **create child tasks in the DB via the `create-task` edge function** (dependency chains via `dependant_on`), and route-selected types to a **VibeComfy subprocess** (`vibecomfy run` scratchpad) when `claimed_backend == vibecomfy`.
- **Artifacts.** Outputs land in a local dir (`./outputs/<task_type>/<task_id>_<file>`) and are uploaded to Supabase Storage bucket `image_uploads` at `{userId}/tasks/{taskId}/{filename}` through the `complete_task` edge function (base64 for <2 MB, presigned PUT for ≥2 MB; thumbnail = first frame). `complete_task` sets `tasks.status='Complete'`, `tasks.output_location` = public URL, creates `generations`/`generation_variants` rows, triggers billing and timeline placement. The worker then deletes the local file (`cleanup_generated_files`, skipped in `--debug`).
- **Statuses.** Enum `task_status`: `Queued | In Progress | Complete | Failed | Cancelled`. Transition validation lives in the `update-task-status` edge function. Progress for orchestrators is written as repeated `In Progress` + `output_location`; per-step progress exists only in logs.
- **Liveness.** A guardian child process POSTs every 20 s to PostgREST RPC `func_worker_heartbeat_with_logs` → upserts the `workers` row (`last_heartbeat`, `status`, `metadata` with VRAM) and bulk-inserts buffered log lines into `system_logs`. The GPU orchestrator (separate process) monitors heartbeat freshness and kills/restarts workers.
- **Retry semantics.** Three error classes: **retryable** (generation_no_output, edge_function_transient, network_transient; max attempts 2–3) → requeue via `update-task-status` (`status=Queued`, `attempts+1`, `clear_worker`); **fatal** (CUDA driver/hardware, NVML, segfault; thresholds 1–2) → worker exits; **everything else** → `Failed`. OOM is deliberately **not** retryable.
- **Deployment.** RunPod pods (Ubuntu 22.04/24.04 + NVIDIA driver image, persistent `/workspace` volume) launched by `reigh-worker-orchestrator` (`gpu_orchestrator/`) via the `runpod-lifecycle` library; startup script clones/syncs the repo with `uv`, then runs `uv run --python 3.10 --extra cuda124 python worker.py --supabase-url … --supabase-access-token … --worker <id> --wgp-profile 1`. Also runs bare-metal/local (`run_worker.py --reigh-access-token …`).

---

## 1. Worker process architecture

### 1.1 Entry points

`pyproject.toml` declares the CLI scripts (`[project.scripts]`):

| Console script | Real entry point |
|---|---|
| `worker` | `source.runtime.entrypoints.worker:main` (→ `source.runtime.worker.server:main`) |
| `run_worker` | `source.runtime.entrypoints.run_worker:main` (same server, direct launcher) |
| `heartbeat_guardian` | `source.runtime.entrypoints.heartbeat_guardian:main` (guardian is spawned in-process, not run standalone — the entrypoint errors if run directly) |
| `headless_model_management` | `source.runtime.entrypoints.headless_model_management:main` (queue runner, for testing) |
| `headless_wgp` | `source.runtime.entrypoints.headless_wgp:WanOrchestrator` |

Root files `worker.py`, `run_worker.py`, `heartbeat_guardian.py`, `headless_model_management.py` are deprecation shims that forward to `source/runtime/entrypoints/*` (`pyproject.toml:42-56`, `worker.py`, `run_worker.py`).

### 1.2 Runtime topology (inside one worker host)

```
┌───────────────────────── worker process (python worker.py) ─────────────────────────┐
│ server.py:main()                                                                     │
│  ├─ signal handlers (SIGINT/SIGTERM → KeyboardInterrupt + shutdown diagnostics)      │
│  ├─ supabase client (service key | worker PAT | anon)  →  DB runtime config          │
│  ├─ optional local HTTP server (local-worker mode only; /health, /ingest, /cleanup)  │
│  ├─ preflight checks → publish workers.metadata (preflight_*)                        │
│  ├─ Wan2GP import (chdir into Wan2GP/, sys.argv spoof, apply --wgp-* overrides)      │
│  ├─ HeadlessTaskQueue  (1 worker thread + monitor thread; lazy WanOrchestrator)      │
│  ├─ warm-cache preload model (optional)                                              │
│  └─ main task claim loop (poll_next_task → process_single_task → status write)       │
└──────────────────────────────────────────────────────────────────────────────────────┘
        │ 20s heartbeats + buffered logs                     │ worker writes
        ▼                                                   ▼
┌─ heartbeat guardian child process ─┐            Supabase: PostgREST RPC
│ POST /rest/v1/rpc/                 │            func_worker_heartbeat_with_logs
│   func_worker_heartbeat_with_logs  │            + edge functions (claim/status/upload)
└────────────────────────────────────┘
```

Sources: `source/runtime/worker/server.py` (whole `main()`), `source/runtime/worker/guardian.py`, `source/task_handlers/worker/heartbeat_utils.py:start_heartbeat_guardian_process` (spawns a daemon `multiprocessing.Process` named `guardian-<worker_id>`; **skipped on Windows**, heartbeats then sent inline at shutdown only, `server.py:~640`).

### 1.3 Boot sequence (in order)

1. `load_dotenv()`, `bootstrap_runtime_environment()` (sets `PYTHONWARNINGS`, `XDG_RUNTIME_DIR=/tmp/runtime-root`, `SDL_AUDIODRIVER=dummy`, `PYGAME_HIDE_SUPPORT_PROMPT`, adds Wan2GP to path) — `server.py:105-140`.
2. Parse CLI (`parse_args`): `--main-output-dir` (default `./outputs`), `--poll-interval` (10), `--debug`, `--worker` (worker id; auto = `RUNPOD_POD_ID` or `"local-worker"`), `--save-logging`, `--migrate-only`, `--colour-match-videos`, `--mask-active-frames` (default True), `--queue-workers` (1), `--preload-model`, `--db-type` (default `supabase`), `--supabase-url` (hard-coded default project), `--reigh-access-token` / `--supabase-access-token`, `--supabase-anon-key`, idle-release args (`--idle-release-minutes` default 15, `--idle-onboarding-grace-seconds` 60), and `--wgp-*` globals (attention-mode, compile, profile, vae-config, boost, transformer-quantization, dtype-policy, text-encoder-quantization, vae-precision, mixed-precision, preload-policy, preload) — `server.py:190-262`.
3. **Access token required** (`REIGH_ACCESS_TOKEN` env or CLI); sets `os.environ["WORKER_ID"]`, `WAN2GP_WORKER_MODE=true` — `server.py:350-370`.
4. DB runtime init (`_initialize_db_runtime`): builds supabase client, stores edge-function URLs (`SUPABASE_EDGE_COMPLETE_TASK_URL`, `_CREATE_TASK_URL`, `_CLAIM_TASK_URL`), validates config (missing service key is non-fatal with access-token auth) — `server.py:80-100`, `source/core/db/config.py:initialize_db_runtime`.
5. **Preflight** (`run_worker_preflight`): checks Wan2GP `models/` + `plugins/` dirs, writable `main_output_dir`, `UV_CACHE_DIR`; publishes `workers.metadata.preflight_*` + `ready_for_tasks` (or a local state file `/tmp/reigh_worker_preflight_<id>.json` when no service key) — `server.py:430-470`, `source/runtime/worker/preflight.py`.
6. **WGP import** (WGP backend only): `os.chdir(wan2gp_path)`, `sys.argv=["worker.py"]`, `import wgp`, apply `--wgp-*` overrides to `wgp.server_config`; failure → publish preflight failed + `sys.exit(1)` — `server.py:530-590`.
7. LoRA cache sweep (`cleanup_legacy_lora_collisions`, `sweep_lora_cache_from_env`) — `server.py:596-600`.
8. **Queue start**: `HeadlessTaskQueue(wan_dir, max_workers=1, main_output_dir=...)`, `task_queue.start(preload_model=warm_cache_plan.preload_model)`; warm-cache plan from `resolve_warm_cache_plan(backend, profile, cli_preload_model, pending_tasks)` (default WGP profile-1 preload `wan_2_2_i2v_lightning_baseline_2_2_2`; suppressed when queued tasks exist) — `server.py:601-680`, `source/runtime/worker/warm_cache.py`.
9. Final preflight publish `ready_for_tasks=True`, then the **claim loop** (below) — `server.py:760-833`.

### 1.4 Local-worker mode

When no service key exists and an access token is present (`_is_local_worker_mode`), a `ThreadingHTTPServer` starts on `127.0.0.1:REIGH_LOCAL_WORKER_PORT` (default 8765): `GET /health` (health payload), `POST /ingest`, `POST /cleanup` (auth via token file in `~/.reigh-local-files/.reigh-local-worker/`; `REIGH_LOCAL_WORKER_AUTH_OPTIONAL=1` is explicitly warned as insecure). It materializes browser-uploaded files into `~/.reigh-local-files` with a janitor sweep (`file_ttl_seconds` default 21600, `janitor_interval_seconds` 1800) — `server.py:395-430`, `source/runtime/worker/local_http.py`.

---

## 2. Task discovery protocol (PULL)

### 2.1 Claim loop

`server.py:~810-860`:

```
while True:
    poll_outcome, task_info = poll_next_task(worker_id, same_model_only=True,
                                             max_task_wait_minutes=int(os.getenv("MAX_TASK_WAIT_MINUTES", "5")))
    EMPTY → idle animation; idle_release check (exit IDLE_RELEASE_EXIT_CODE after idle-release-minutes of empty polls, unless queue has active work)
    ERROR → sleep(poll_interval), continue
    CLAIMED → execute, write status, sleep(1)
```

The worker never touches Postgres directly for discovery — **all DB access goes through HTTP to Supabase Edge Functions** (`source/core/db/task_claim.py:poll_next_task`), except the heartbeat guardian which calls a PostgREST RPC via curl.

### 2.2 Endpoint 1: `task-counts` (optimization gate)

`POST {SUPABASE_URL}/functions/v1/task-counts`, `Authorization: Bearer <token>`, payload `{run_type:"gpu", include_active:true, worker_backend, worker_profile, selector_namespace, selector_version, worker_contract_version}` (10 s timeout). Returns `totals` with `queued_only`, `eligible_queued`, `active_only`. If `queued_only==0` but `eligible_queued>0` it warns of replication lag and proceeds anyway; otherwise still proceeds to claim (counts are advisory only) — `source/core/db/task_claim.py:check_task_counts_supabase`.

### 2.3 Endpoint 2: `claim-next-task` (the claim)

`POST {SUPABASE_URL}/functions/v1/claim-next-task`, 15 s timeout. Request body (worker → edge):

```json
{ "worker_id": "...", "run_type": "gpu", "same_model_only": true,
  "worker_backend": "wgp|vibecomfy", "worker_profile": "1..5|default",
  "selector_namespace": "production", "selector_version": null,
  "worker_contract_version": 1, "max_task_wait_minutes": 5 }
```

Response:
- `200` → `{task_id, params, task_type, project_id}` (edge function `reigh-app/supabase/functions/claim-next-task/index.ts:115-122`; the DB function's `RETURNING` additionally carries route fields: `selector_namespace, route_key, selected_backend, selector_version, route_selection_snapshot, task_*` copies, `claimed_backend, claimed_selector_namespace, claimed_route_key, claimed_selector_version, claimed_capability_version, claim_decision_reason, claim_decision_snapshot` — `reigh-app/supabase/migrations/20260507215500_respect_task_selector_namespace_in_claims.sql`).
- `204` → no task (`ClaimPollOutcome.EMPTY`).
- other/exception → `ClaimPollOutcome.ERROR` (worker sleeps and retries).

The worker validates the claim with `_claim_route_guard`: if `claimed_backend`/`selected_backend`/`claim_decision_reason` are present they must match the worker's own `worker_backend` and the reason must be `eligible` or `missing_selector_wgp_capability_supported`; mismatch → requeue (`backend_mismatch`) or fail-closed via `mark_task_failed_via_edge_function` — `source/core/db/task_claim.py:_claim_route_guard`.

### 2.4 Server-side claim semantics (Postgres)

The edge function calls the RPC `claim_next_task_service_role(p_worker_id, p_include_active=false, p_run_type, p_same_model_only, p_max_task_wait_minutes, p_worker_backend, p_selector_namespace)` — latest repo version `20260507215500_...sql`:

- **Atomic claim**: `UPDATE tasks ... FROM ready_tasks ... WHERE rn = 1 ... RETURNING` with `FOR UPDATE SKIP LOCKED`, ordered by model-affinity then `created_at ASC` (FIFO).
- **Sets**: `status='In Progress'`, `worker_id=p_worker_id`, `generation_started_at = COALESCE(existing, NOW())` (preserved on re-claim, `20260121170000_fix_claim_preserve_generation_started_at.sql`), `updated_at=NOW()`, and the `claimed_*` route columns from the live `route_backend_claim_decision(...)` selector.
- **Eligibility**: `tasks.status='Queued'`, `task_types.is_active`, `get_task_run_type(task_type)=run_type` (or VibeComfy GPU workers may take api-class types when route-selected), `users.credits > 0`, user setting `settings->ui->generationMethods->>inCloud = true`, **< 5 In Progress tasks per user** (orchestrators excluded from the count), `all_dependencies_complete(dependant_on)` (multi-dependency support, `20260121000000_support_multiple_dependencies.sql`), selector namespace match, and `route_backend_claim_decision(...) .eligible`.
- **Model affinity + starvation protection**: when `same_model_only` and the worker has `workers.current_model` set, it prefers tasks whose `get_task_model(params) = current_model`; if any eligible task has waited > `max_task_wait_minutes`, it falls back to FIFO — `20260323213000_add_max_task_wait_to_claim.sql`.
- Worker row lookup: `SELECT current_model FROM workers WHERE id = p_worker_id AND status = 'active'` (so a non-active worker gets no affinity).
- User-token path (local workers): `claim_next_task_user_pat(p_user_id, ...)` restricts to that user's tasks.

**Lost-claim recovery**: `check_my_assigned_tasks()` returns None under PAT auth — "Tasks that lose their HTTP response are recovered by heartbeat timeout instead" (`task_claim.py`). The GPU orchestrator's orphan-task reconciliation (see §7) resets tasks on dead/error workers.

### 2.5 Payload received (the task JSON)

`task_info["params"]` is the `tasks.params` JSONB column, the full task contract (whitelist in `source/task_handlers/tasks/task_conversion.py:param_whitelist`): `prompt`, `model` (optional; default from `TASK_TYPE_TO_MODEL`), `resolution`, `video_length`, `num_inference_steps`, `guidance_scale`, `seed`, `negative_prompt`, `image`/`image_url`/`mask_url`, `video_guide`/`video_mask`/`image_start`/`image_end`/`image_refs`, `audio_guide`, `activated_loras`/`loras`/`additional_loras`, `phase_config`, `travel_chain_details`, `orchestrator_details`, `segment_image_download_dir`, etc. Orchestrator params like `portions_to_regenerate` (edit_video) and `clip_list` (join) ride inside params too.

### 2.6 How tasks get *created* (context)

Frontend creates tasks via the `create-task` edge function; **orchestrators running inside the worker create child tasks via the same edge** (`source/core/db/task_completion.py:add_task_to_db` → `POST /functions/v1/create-task` with `{family, project_id, input, dependant_on:[...], route_snapshot_fields}`), returning a server-assigned UUID. Callers: travel orchestrator (`source/task_handlers/travel/orchestrator.py:2261,2378,2483` — `travel_segment`/`travel_stitch`/`join_clips_orchestrator`), join task builder (`source/task_handlers/join/task_builder.py:144,183,279,316` — `join_clips_segment`/`join_final_stitch`), stitch upscaler (`stitch.py:813`). Children are chained with `dependant_on` (single or list), and the claim RPC only picks tasks whose dependencies are all `Complete`.

---

## 3. Execution pipelines per model

### 3.1 Dispatch (`TaskRegistry.dispatch`, `source/task_handlers/tasks/task_registry.py:1550+`)

Priority: (1) **direct queue task types** → `_handle_direct_queue_task` (route-resolved WGP or VibeComfy); (2) **specialized handlers** (orchestrators and helpers); (3) unknown types fall through to the queue.

Specialized handlers table:

| task_type | handler | behavior |
|---|---|---|
| `travel_orchestrator` | `travel.orchestrator.handle_travel_orchestrator_task` | resolves plan, creates `travel_segment` children (deps-chained), then `travel_stitch`, then optionally a `join_clips_orchestrator`; reports progress as `In Progress`; returns `[ORCHESTRATOR_COMPLETE]<json>` marker when done |
| `travel_segment` / `individual_travel_segment` | `travel.segments.segment_queue.handle_travel_segment_via_queue` | builds WGP `generation_params` (VACE video_guide, SVI latent tails, image refs, structure guidance, LoRA dedup, Uni3C) and submits to the queue (`task_registry.py:147-150`, big impl in `task_registry.py`) |
| `travel_stitch` | `handle_travel_stitch_task` | downloads segment outputs, stitches, upscales |
| `join_clips_orchestrator` | `join.orchestrator` | chains `join_clips_segment` (VLM-enhanced transitions) + `join_final_stitch` |
| `edit_video_orchestrator` | `edit_video_orchestrator.py` | splits source video at `portions_to_regenerate`, extracts "keeper" segments, reuses the join chain to regenerate transitions (`edit_video_orchestrator.py` docstring: 164-frame example) |
| `join_clips_segment` | join handler (route-resolved; VibeComfy allowed) | transition generation between two clips |
| `join_final_stitch` | `join.final_stitch` | concatenates segments + audio |
| `inpaint_frames` | `handle_inpaint_frames_task` | WGP VACE inpainting over corrupted frame ranges |
| `magic_edit`, `extract_frame`, `create_visualization`, `rife_interpolate_images`, `comfy` | specialized | auxiliary pipelines |

### 3.2 Direct queue (WGP) pipeline

1. `db_task_to_generation_task(params, task_id, task_type, wan2gp_path, debug_mode)` — whitelists params, applies Qwen prompt expansion (qwen task types), runs `QwenHandler` preprocessing for qwen/z_image types, defaults `video_length=1` for `wan_2_2_t2i`, returns a `GenerationTask(id, model, prompt, parameters)` — `source/task_handlers/tasks/task_conversion.py`.
2. `HeadlessTaskQueue.submit_task` → priority queue (fair policy) → worker thread `process_task_impl` (`source/task_handlers/queue/task_processor.py:90-320`):
   - `queue._switch_model(task.model)` → `orchestrator.load_model(model_key)` (WanOrchestrator from `headless_wgp.py`; lazy init; checks WGP ground truth, `wgp_init.py`).
   - `reset_generation_started_at(task.id)` — billing clock starts after model load (`task_status.py:reset_generation_started_at`, edge `update-task-status` with `reset_generation_started_at:true`).
   - `execute_generation_impl` → `convert_to_wgp_task` (typed `TaskConfig.from_db_task`, downloads LoRAs from URLs, validates) → chooses generation path by model capability: `generate_vace` (needs `video_guide`; error if absent), `generate_flux`, else `generate_t2v` (covers t2v, z_image single-frame) — `task_processor.py:500-570`.
   - WGP-global patching under a lock: `phase_config` patches, `svi2pro`/`sliding_window`/`sliding_window_defaults`/`svi_empty_frames_mode` patches for SVI continuation, restored in `finally` — `task_processor.py:_execute_generation_with_patches`.
   - **Generation timeout**: POSIX `SIGALRM` after 1200 s (`GENERATION_TIMEOUT_SECONDS`) → `RuntimeError("Generation timeout ...")`; disabled on Windows — `task_processor.py:445-465`.
   - Single-frame video → PNG conversion for image tasks (`_convert_single_frame_video_to_png`, 3 cv2 attempts; skipped for `travel_segment`).
   - Output path existence re-check with a 2 s retry, plus deep diagnostics on phantom outputs.
3. Post-generation (in `server.py:process_single_task`): travel chaining (`travel_chain_details.enabled` → `handle_travel_chaining_after_wgp`), then `move_wgp_output_to_task_type_dir` renames output into `<main_output_dir>/<task_type>/<task_id>_<filename>` (`source/utils/output_paths.py:prepare_output_path`, collision-safe).

### 3.3 VibeComfy pipeline (route-selected, `claimed_backend == vibecomfy`)

`resolve_task_route` (`source/task_handlers/tasks/template_routing.py`) decides WGP vs VibeComfy per task using `SPRINT_2_SELECTOR_MAP`/`SECTION3A_ROUTE_SUPPORT_MAP`, stamped `route_contract` in params, backend env, and capability tables; unsupported feature combos fail closed with a reason. `handle_vibecomfy_resolved_task` (`source/models/comfy/vibecomfy_adapter.py`) then:

- materializes inputs (downloads image/video URLs into a per-task run workspace `<main_output_dir>/<task_id>/input/`),
- writes a Python **scratchpad** per route (z_image_turbo, qwen_image_2512, qwen_image_edit, image_upscale, wan_2_2_t2i, wan_2_2_i2v, animate_character, video_enhance, flux_klein_edit, LTX first/last + control variants, travel VACE routes),
- runs `vibecomfy run <scratchpad> --memory-profile N [--ensure-packs --ensure-models]` as a **subprocess** (VIBECOMFY_PYTHON / VIBECOMFY_CWD), with dynamic LoRA selectors/downloads,
- post-processes (RIFE frame interpolation for LTX first/last routes, resize to contract dimensions/fps from `VideoArtifactContract`),
- discovers the output from stdout markers/metadata JSON/run workspace, and returns the local output path (uploaded by the same `complete_task` path).

### 3.4 Model catalog (`source/task_handlers/tasks/task_types.py`)

| Task types (subset) | Default WGP model | Notes |
|---|---|---|
| `t2v`, `t2v_22`, `generate_video`, `wan_2_2_t2i` | `t2v`, `t2v_2_2` | text→video; t2i forced `video_length=1` |
| `i2v`, `i2v_22`, `wan_2_2_i2v` | `i2v_14B`, `i2v_2_2`, `wanvideo_wrapper_22_14b_i2v_kijai` | image→video |
| `vace`, `vace_21`, `vace_22` | `vace_14B_cocktail_2_2` | requires `video_guide` |
| `ltxv`, `ltx2` | `ltxv_13B`, `ltx2_19B` | |
| `hunyuan`, `flux` | `hunyuan`, `flux` | flux maps `video_length→num_images` |
| `qwen_image`, `qwen_image_2512`, `qwen_image_edit`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit`, `qwen_image_hires` | `qwen_image_20B` / `qwen_image_2512_20B` / `qwen_image_edit_20B` | image gen/edit via `QwenHandler` |
| `z_image_turbo`, `z_image_turbo_i2i` | `z_image`, `z_image_img2img` | fast t2i/i2i (guidance_scale 0, 8 steps) |
| `image-upscale`, `image_upscale`, `animate_character`, `video_enhance`, `flux_klein_edit` | `basic_image_upscale`, `wan22_animate_native_first_stage`, `basic_video_enhance`, `flux2_klein_4b_image_edit_distilled` | app-active VibeComfy routes |
| `travel_segment`, `inpaint_frames`, `join_clips_segment` | `wan_2_2_vace_lightning_baseline_2_2_2` | specialized WGP handlers |

Dependencies enabling the media stack: Wan2GP (`Wan2GP/` git submodule pinned to banodoco/Wan2GP), `smplfitter` and `decord` (Wan2GP deps; decord used in `source/media/structure/*` for fast frame loading), `rembg`, `mediapipe`, `insightface`, `audio-separator`, `pyannote.audio` (Wan2GP audio/pose stack) — `pyproject.toml`.

### 3.5 Input materialization

Any URL in params is downloaded locally before use: `download_image_if_url` / `download_video_if_url` (`source/utils/download_utils.py`, streaming to `<target_dir>/<unique>`), used across travel (`travel_guide.py:149`), join (`final_stitch.py`, `generation.py`), edit (`edit_video_orchestrator.py:228`), Qwen (`qwen_handler.py:355`), VibeComfy (`vibecomfy_adapter.py:1428`). Source media typically lives in Supabase Storage public URLs. Structure guidance videos are fetched via `download_and_extract_motion_frames` (`media/structure/download.py`). Predecessor latent tails are fetched from `{SUPABASE_URL}/storage/v1/object/public/image_uploads/{userId}/tasks/{predecessor_task_id}/latent_tail.pt` (`task_registry.py:479-483`).

---

## 4. Artifact storage + DB recording

### 4.1 Local layout

- `--main-output-dir` (default `./outputs`), subdir per task type: `outputs/<task_type>/<task_id>_<filename>` (`prepare_output_path`; filename collision counter; sanitized for storage via `sanitize_filename_for_storage`).
- WGP writes its own scratch outputs under `Wan2GP/outputs`-style locations during generation; final artifact is moved into the task-type dir.
- VibeComfy uses per-task run workspace under the main output dir.
- Local worker materialization dir `~/.reigh-local-files` (janitor-swept).

### 4.2 Upload: two modes in `complete_task` path (`source/core/db/task_status.py:_update_task_status_supabase_legacy`)

The worker's `STATUS_COMPLETE` write is special: it **uploads the file** and completes the task in one flow, via edge `POST /functions/v1/complete_task` (canonical name `complete_task`, underscore):

- **MODE 1 — base64** (`file < 2 MB`): payload `{task_id, file_data:<b64>, filename}` plus `first_frame_data`/`first_frame_filename` for videos (thumbnail = first frame via cv2, or existing `<video>.jpg` poster). Edge uploads to Storage, returns `{public_url, thumbnail_url}`.
- **MODE 3 — presigned** (`≥ 2 MB`): (1) `POST /functions/v1/generate-upload-url` `{task_id, filename, content_type, generate_thumbnail_url:is_video}` → `{upload_url, storage_path, token, expires_at, thumbnail_upload_url?, thumbnail_storage_path?}`; (2) PUT the file (and thumbnail) directly to the signed URL (timeout 600 s for the main file); (3) `complete_task` `{task_id, storage_path, thumbnail_storage_path?}`.
- **MODE 4 / JSON outputs**: if `output_location` is already a `…/storage/v1/object/public/image_uploads/…` URL (orchestrator referencing a child's upload, or JSON metadata containing one), the worker extracts the `storage_path` and calls `complete_task` with it (`output_location` passthrough for JSON), avoiding a second upload.
- Storage paths: bucket `image_uploads`, `{userId}/tasks/{taskId}/{filename}` and `{userId}/tasks/{taskId}/thumbnails/{filename}` (`reigh-app/supabase/functions/_shared/storagePaths.ts`); user id comes from `resolveTaskStorageActor` on the edge side.
- Edge-side retry helper: `_call_edge_function_with_retry` (3 retries, retryable statuses `{500,502,503,504}`, `EDGE_FAIL_PREFIX="[EDGE_FAIL"` marker) — `source/core/db/edge_helpers.py`, `config.py:RETRYABLE_STATUS_CODES`.
- Upload failure at any step → `_mark_task_failed_via_edge_function(task_id, "Upload failed: …")` (status `Failed` with the error in `output_location`).

### 4.3 DB writes on completion (`reigh-app/supabase/functions/complete_task/handler.ts`)

Order of operations: actor/ownership validation → optional params normalization (`tasks.params` update) → `createGenerationFromTask` (inserts `generations` row: `location` = public URL, `thumbnail_url`, `media_type` from `content_type`, `created_as: 'generation'|'variant'`, `params`, `is_primary`, `variant_type`; also `generation_variants`; marks `tasks.generation_created=true`) → timeline placement (adds media clip via `upsert_asset_registry_entry` + timeline state) → **`tasks.update({status:"Complete", output_location: finalOutputLocation, generation_processed_at})` with `.eq("id",taskId).eq("status","In Progress")`** → cost calculation (`triggerCostCalculationIfNotSubTask` → `calculate-task-cost`) → `result_data` (billing outcome, follow-up issues) → `cleanupMaterializedInputs`. Response: `{success, public_url, thumbnail_url, follow_up, task_id, generation_id, has_thumbnail}`.

The `tasks` columns involved (from migrations): `id, task_type, params(jsonb), status(task_status enum), dependant_on, output_location(text), created_at, updated_at, project_id, generation_processed_at` (`20250100000000_create_base_schema.sql`) + later `worker_id`, `attempts int default 0`, `error_message text`, `result_data jsonb` (`20250202000000_add_missing_columns.sql`), `generation_started_at timestamptz` (`20250712000001`), `copied_from_share`, `idempotency_key`, `generation_created bool`, `materialized_inputs` (`20260505012055`), route/claim columns (`20260506110000_add_route_backend_selector_control_plane.sql`).

### 4.4 Intermediates

`upload_intermediate_file_to_storage(local_file, task_id, filename)` → `generate-upload-url` with `artifact_class:"intermediate"` → signed PUT → public URL returned (used for cross-worker artifacts like latent tails and chained segment outputs; `source/media/video/storage.py`, `source/utils/output_paths.py`).

### 4.5 Local cleanup

After a successful non-orchestrator task, `cleanup_generated_files(output_location, task_id, debug_mode)` deletes the local output file/dir (skipped in debug mode) — `source/task_handlers/worker/worker_utils.py`. Post-upload, the file exists only in Storage.

---

## 5. Status reporting + heartbeats

### 5.1 Status values and who writes them

`task_status` enum: `Queued, In Progress, Complete, Failed, Cancelled` (`20250100000000_create_base_schema.sql`). Worker constants `STATUS_QUEUED/IN_PROGRESS/COMPLETE/FAILED` (`source/core/db/config.py:72-75`).

| Transition | Writer | Mechanism |
|---|---|---|
| `Queued → In Progress` | **server-side** claim RPC (atomic UPDATE) | `claim-next-task` |
| `In Progress → In Progress` (progress ping, orchestrators only) | worker | `update-task-status` edge with `output_location` (`server.py:916,931`) |
| `In Progress → Complete` | worker | `complete_task` edge (with file upload, §4) |
| `In Progress → Queued` (retry) | worker | `update-task-status` `{status:"Queued", attempts:N, error_details, clear_worker:true}` (`task_status.py:requeue_task_for_retry`) |
| `In Progress → Failed` | worker | `update-task-status` `{status:"Failed", output_location: error_message}` (`mark_task_failed_supabase`) |
| `In Progress → Failed` (upload/completion failure) | worker | same via `_mark_task_failed_via_edge_function` |
| `Cancelled` / cascades | app | `update-task-status` cascade (`handleCascadingTaskFailure`) |

Transition validation server-side (`update-task-status/transitions.ts`): `Queued→[In Progress, Failed, Cancelled]`, `In Progress→[Complete, Failed, Cancelled, Queued]`, `Complete/Failed/Cancelled→[]`. `reset_generation_started_at:true` with same status `In Progress` bypasses transition validation. `update-task-status/payload.ts` maps: `error_details → tasks.error_message`, `attempts → tasks.attempts`, `clear_worker → worker_id=null, generation_started_at=null`, optional `result_data` passthrough (hoisted by the new `task-status` GET reader for pollers: `correlation_id`, `message`, `failure_code`).

### 5.2 Heartbeats (identity + liveness)

- **Guardian process**: spawned at boot (`start_heartbeat_guardian_process`), loops every **20 s**: if worker PID dead → one heartbeat with `status="crashed"` and exits; else reads VRAM via `nvidia-smi` (`get_vram_info`), drains up to 100 buffered log entries (shared `LogBuffer` fed by a `CustomLogInterceptor` over all logging), appends preflight status + route labels, and POSTs — `source/runtime/worker/guardian.py:guardian_main`, `send_heartbeat_with_logs`.
- **Transport**: raw `curl` to `POST {SUPABASE_URL}/rest/v1/rpc/func_worker_heartbeat_with_logs` with `Authorization: Bearer <service key or access token>` + `Prefer: return=representation`, body `{worker_id_param, vram_total_mb_param, vram_used_mb_param, logs_param:[{level,message,metadata,task_id}], status_param}` (10 s curl timeout) — direct PostgREST, not an edge function.
- **Server side** (`20250115100000_create_system_logs.sql:96`, latest `20251019000001_add_status_param_to_heartbeat.sql`): upserts `workers` row (`id=worker_id`, `instance_type='external'` if new, `status=status_param`, `last_heartbeat=NOW()`, `metadata` merged with `{vram_total_mb, vram_used_mb, vram_timestamp}`), then bulk-inserts each log into `system_logs(timestamp, source_type='worker', source_id=worker_id, log_level, message, task_id, worker_id, metadata)`.
- **workers table columns**: `id, instance_type, status, last_heartbeat, metadata(jsonb), created_at, current_model` (current_model read by claim RPC; `instance_type` set by orchestrator on spawn).
- **Preflight metadata**: worker also writes `workers.metadata` directly (supabase client) with `preflight_status, preflight_ok, preflight_failed_checks, ready_for_tasks` (`preflight.py:publish_preflight_metadata`), and warm-cache state (`warm_cache.py` → `workers.metadata` or local file). Startup phase is also tracked by the orchestrator via `metadata.startup_phase` (written by the startup script).
- **Shutdown**: final heartbeat with `status="terminated"` before exit (`server.py:finally`), plus `guardian_process.terminate()`.

### 5.3 Progress events

No per-step DB progress for plain generation tasks. Progress exists at three levels: (a) WGP callback `send_cmd("progress", [pct, status])` → debug logs (`models/wgp/generators/wgp_params.py`); (b) component logs (`headless_logger.progress`) → local log file + intercepted into the heartbeat log queue (→ `system_logs`); (c) orchestrator tasks write `In Progress` + partial `output_location` via `update-task-status` (`server.py:916,931`; travel orchestrator emits `"N/M segments complete"` style via `TaskResult.orchestrating`, `core/params/task_result.py`). A terminal chat display (`WorkerStatusDisplay`) is cosmetic only.

---

## 6. Failure modes and retry semantics

### 6.1 Classification (`source/task_handlers/worker/fatal_error_handler.py`)

- **FATAL_ERROR_PATTERNS** (conservative, kill-the-worker):
  - `cuda_driver` (driver init failures; threshold 2 consecutive),
  - `cuda_hardware` (GPU fell off bus, catastrophic driver failure, launch timed out + watchdog; threshold 1),
  - `nvml` (NVML library missing; threshold 2),
  - `system_critical` (bus error, segfault, "Fatal Python error … core dumped"; threshold 1).
  - Trigger → `FatalWorkerError` → `sys.exit(1)` (`server.py:1010`), after `run_summary`. Counter resets on each successful task (`reset_fatal_error_counter`).
  - Explicitly removed: `model_corruption` and `critical_oom` categories — those fail the task, not the worker; OOM is "almost always recoverable by retrying with smaller batch sizes", and the OOM comment in `RETRYABLE_ERROR_PATTERNS` explains OOM is **intentionally not retryable** on the same worker (would fail identically; manual requeue or worker exclusion required).
- **RETRYABLE_ERROR_PATTERNS** (requeue task, not worker):
  - `generation_no_output` (`No output generated`, `Generation produced no output`) — max 2 attempts,
  - `edge_function_transient` (`[EDGE_FAIL:*:HTTP_500]`, `5XX_TRANSIENT`, `TIMEOUT`, `NETWORK`, worker edge errors) — max 3,
  - `network_transient` (ConnectionError/reset/refused, unreachable, timed out) — max 3,
  - default `DEFAULT_MAX_ATTEMPTS = 2`.
- `is_retryable_error(message) → (bool, category, max_attempts)`; `is_fatal_error` additionally inspects exception types (`torch.cuda`, `MemoryError`/`OSError` + cannot allocate memory).

### 6.2 Worker-side retry flow (`server.py:936-990`)

On handler failure or unhandled exception:
```
if is_retryable and task_info.attempts < max_attempts:
    requeue_task_for_retry(task_id, error_message, attempts, category)
       → update-task-status {status:"Queued", attempts:attempts+1, error_details:"Retry N (cat): …", clear_worker:true}
else:
    _update_task_complete(task_id, STATUS_FAILED, error_message)   # Failed + error text
```
Note: `task_info.get("attempts", 0)` — the repo's claim RPC `RETURNING` does not include `attempts`, so the value is expected in the edge response/params (see Gaps). Requeued tasks keep `error_message` history; `clear_worker` unassigns the worker and nulls `generation_started_at` (billing restarts on next claim).

### 6.3 Orchestrator-side failure handling (outer watchdog)

`reigh-worker-orchestrator/gpu_orchestrator/control_loop.py` (30 s cycle) monitors workers, not tasks directly:

- **Stuck tasks**: `task_stuck_timeout_sec` (1200 s default) since `generation_started_at`/`updated_at` → mark worker `error`, terminate pod (`_check_stuck_tasks`).
- **Idle scale-down**: `gpu_idle_timeout_sec` (300 s) / overcapacity `30 s` → `terminated` (intentional, not counted as failure).
- **Heartbeat freshness**: stale heartbeat + active task → `error` (`STALE_HEARTBEAT_ACTIVE_TASK`); no heartbeat at all → `NO_HEARTBEAT`; idle with tasks queued → `IDLE_WITH_TASKS_QUEUED`; `GPU_READY_NOT_CLAIMING`; failsafe stale threshold 7200 s.
- **Failure streaks**: repeated task failures on one worker → restart (`task_failure_loop`), OOM-like.
- **Orphan reconciliation (Phase 7)**: `reset_orphaned_tasks(failed worker_ids)` → sets their `In Progress` tasks back to `Queued` and clears `worker_id`; `reset_unassigned_orphaned_tasks(timeout_minutes=15)` (In Progress tasks with no worker); `reset_stale_assigned_tasks(timeout_minutes=30)` (stale assigned tasks; excludes `api-worker-*`). This is the safety net for claimed-but-crashed tasks.
- **Failure-rate circuit breaker**: `max_worker_failure_rate` over `failure_window_minutes` blocks scale-up when exceeded (only `error` status counts, not `terminated`).
- Spawning timeouts (`spawning_timeout_sec` 300), SSH health checks, storage health (`REIGH_DISK_*`), GPU-not-detected timeout.

### 6.4 Known-fragile points (observed in code comments)

- Phantom output paths (fresh file briefly missing on network volumes → 2 s retry + deep diagnostics, `task_processor.py:180-260`).
- Lost claim responses (claim succeeded, HTTP lost) → recovered by heartbeat timeout + orphan reset (`task_claim.py:check_my_assigned_tasks`).
- Windows console Ctrl+C propagation through MKL/numpy crashing subprocesses (guardian skipped on Windows).
- Edge function cold starts / CDN 5xx → `[EDGE_FAIL` markers, retried 3×.
- Generation SIGALRM timeout (1200 s) as a GPU-deadlock guard.
- Idle release exits worker with `IDLE_RELEASE_EXIT_CODE` when no tasks for `--idle-release-minutes` (suppressed in service mode; suppressed while queue has active work).

---

## 7. Deployment / config

### 7.1 Cloud (RunPod) — `reigh-worker-orchestrator/`

- **Orchestrator** (`gpu_orchestrator/`): async control loop on Railway (`railway.json`) with phases spawn → early-termination → spawning handle → health check → error cleanup → orphan reconcile → scale decision. Uses `runpod_lifecycle` package (`launch`, `terminate`, network volumes; `worker_spawner.py`).
- **Worker ID**: `gpu-<YYYYMMDD_HHMMSS>-<8 hex>` (`worker_spawner.py:generate_worker_id`).
- **Spawn**: `launch(launch_config)` creates a RunPod pod (container image + `RUNPOD_INSTANCE_TYPE` GPU, disk size, network volume `/workspace`); `create_worker_record` inserts `workers` row `status='spawning'` + `metadata.runpod_id`; when pod is RUNNING with SSH port 22, the startup script is written via SSH and executed (`launch_worker_process`).
- **Startup script** (`gpu_orchestrator/runpod/worker_startup.template.sh`): exports route-contract env (below), installs `python3.10-venv/dev ffmpeg git curl`, installs `uv` (`UV_LINK_MODE=copy`, `UV_CACHE_DIR=/workspace/.uv-cache`), `git fetch/checkout main/reset --hard origin/main` + submodule sync (Wan2GP), `uv sync --locked --python 3.10 --extra cuda124` (sync sentinel hash check), import validation, then:
  ```bash
  uv run --python 3.10 --extra cuda124 python worker.py \
    --supabase-url "$SUPABASE_URL" \
    --supabase-access-token "$SUPABASE_SERVICE_ROLE_KEY" \
    --worker "$WORKER_ID" \
    --wgp-profile 1 [--debug] [--preload-model ...]
  ```
  `nohup`, log tee to `/tmp/worker_startup_<id>.log` (symlinked into repo `logs/`), Jupyter Lab on 8888, worker-phase updates via `metadata.startup_phase` (deps_installing → deps_verified → worker_starting → ready, waiting on preflight state `ready_for_tasks`), `wait_worker_preflight_ready_or_exit` guards startup completion.
- **Worker env (names only)**, from `worker_spawner.py:_build_worker_env` + template + `env.example`: `WORKER_ID, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY, SUPABASE_SERVICE_KEY, REPLICATE_API_TOKEN, MAX_TASK_WAIT_MINUTES, REIGH_BACKEND/WORKER_BACKEND, REIGH_WORKER_PROFILE/WGP_PROFILE, REIGH_WORKER_POOL/WORKER_POOL, REIGH_SELECTOR_NAMESPACE/ROUTE_SELECTOR_NAMESPACE, REIGH_SELECTOR_VERSION/ROUTE_SELECTOR_VERSION, REIGH_WORKER_CONTRACT_VERSION, REIGH_WORKER_RUN_ID/WORKER_RUN_ID, SUPABASE_EDGE_COMPLETE_TASK_URL, SUPABASE_EDGE_MARK_FAILED_URL, REIGH_WARM_CACHE_PRELOAD_MODEL, REIGH_WARM_CACHE_SOURCE, REIGH_WARM_CACHE_SKIP_REASON, VIBECOMFY_MEMORY_PROFILE, UV_LINK_MODE, UV_CACHE_DIR`.
- Orchestrator-side env (names only): `SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY, SUPABASE_ACCESS_TOKEN, RUNPOD_API_KEY, REPLICATE_API_TOKEN, FAL_KEY, WAVESPEED_API_KEY, API_WORKER_*, MIN_ACTIVE_GPUS, MAX_ACTIVE_GPUS, TASKS_PER_GPU_THRESHOLD, MACHINES_TO_KEEP_IDLE, GPU_IDLE_TIMEOUT_SEC, GPU_OVERCAPACITY_IDLE_TIMEOUT_SEC, TASK_STUCK_TIMEOUT_SEC, SPAWNING_TIMEOUT_SEC, GPU_HEALTH_CHECK_TIMEOUT_SEC, ERROR_CLEANUP_GRACE_PERIOD_SEC, FAILSAFE_STALE_THRESHOLD_SEC, GRACEFUL_SHUTDOWN_TIMEOUT_SEC, ORCHESTRATOR_POLL_SEC, MAX_TASK_WAIT_MINUTES, RUNPOD_INSTANCE_TYPE, RUNPOD_CONTAINER_IMAGE, RUNPOD_CONTAINER_DISK_SIZE_GB, REIGH_* route contract vars, REIGH_DISK_*, REIGH_ARTIFACT_*, REIGH_LORA_*` (`env.example`).
- Secrets policy: the worker repo `.env` / `this.env` contain live credentials (`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ACCESS_TOKEN`, `REPLICATE_API_TOKEN`, `RUNPOD_API_KEY`, `FAL_KEY`, `REIGH_LIVE_TEST_TOKEN`, plus LLM keys in `this.env`) — **values redacted in this doc**; only key names listed.

### 7.2 Local / bare-metal

- `uv sync --locked --python 3.10 --extra cuda124` then `uv run --python 3.10 python run_worker.py --reigh-access-token <token> --wgp-profile 4 --idle-release-minutes 15` (`README.md`); Windows `start_worker.bat`; `--migrate-only` exits after DB init; default `--supabase-url` points at the production project.
- Credentials come from the Reigh app ("worker token"), stored in `REIGH_ACCESS_TOKEN` (preferred, avoids CLI-arg echo) or CLI args.
- `runpod-lifecycle` git dep (`pyproject.toml`) is used for live-test pods; `scripts/live_test/` builds variant fresh/prebuilt validation matrices on RunPod for backend smoke tests.

### 7.3 Runtime config keys used by the worker (names only)

From `.env.example`, `server.py`, and modules: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`/`SUPABASE_SERVICE_KEY`, `SUPABASE_ANON_KEY`, `SUPABASE_ACCESS_TOKEN`, `REIGH_ACCESS_TOKEN`, `WORKER_ID`, `WORKER_DB_CLIENT_AUTH_MODE` (`service`|`worker`), `MAX_TASK_WAIT_MINUTES`, `RUNPOD_POD_ID`, `REIGH_BACKEND`/`WORKER_BACKEND`, `REIGH_WORKER_PROFILE`/`WGP_PROFILE`, `REIGH_WORKER_POOL`/`WORKER_POOL`, `REIGH_SELECTOR_NAMESPACE`/`ROUTE_SELECTOR_NAMESPACE`, `REIGH_SELECTOR_VERSION`/`ROUTE_SELECTOR_VERSION`, `REIGH_WORKER_CONTRACT_VERSION`, `REIGH_WORKER_RUN_ID`/`WORKER_RUN_ID`, `REIGH_CLAIM_TELEMETRY`, edge URL overrides (`SUPABASE_EDGE_COMPLETE_TASK_URL`, `_CLAIM_TASK_URL`, `_CREATE_TASK_URL`, `SUPABASE_EDGE_UPDATE_TASK_URL`, `SUPABASE_EDGE_TASK_COUNTS_URL`, `SUPABASE_EDGE_GET_TASK_OUTPUT_URL`, `SUPABASE_EDGE_GET_ORCHESTRATOR_CHILDREN_URL`), `REIGH_WARM_CACHE_*` (`PRELOAD_MODEL`, `MANIFEST`, `CONFIG`, `SKIP_REASON`, `SOURCE`), `REIGH_PREFLIGHT_STATE_DIR`, `REIGH_LOCAL_WORKER_*` (`PORT`, `DIR`, `AUTH_OPTIONAL`, `FILE_TTL_SECONDS`, `JANITOR_INTERVAL_SECONDS`), `REIGH_DISK_*` (`CLAIM_MIN_FREE_MB`, `WRITE_MIN_FREE_MB`, `WRITE_RESERVE_MB`, `HEALTH_PATHS`, `NEAR_FULL_PCT`), `REIGH_ARTIFACT_CLEANUP_PATHS`, `REIGH_LORA_*`, `GUARDIAN_LEGACY_PARSE_SUCCESS`, `VIBECOMFY_*` (`MEMORY_PROFILE`, `PYTHON`, `CWD`/`PATH`, `RUN_ENSURE_FLAGS`), `UV_CACHE_DIR`, `UV_LINK_MODE`, `WAN2GP_WORKER_MODE` (set by worker), `REIGH_WORKER_PROFILE`.

---

## Gaps / unverified

- **`attempts` in the claim response**: the worker reads `task_info.get("attempts", 0)` (`server.py:941,966`) and `_int_attempts(task_data.get("attempts"))` (`task_claim.py`), but the repo's latest `claim_next_task_service_role` migration (`20260507215500`) does **not** include `attempts` in its `RETURNING`, and `claim-next-task/index.ts` returns only `task_id/params/task_type/project_id`. The deployed claim function may differ from repo migrations (repo may lag the deployment). Where `attempts` actually arrives (top-level vs inside `params`) is unverified; if absent, first retry decisions treat attempts as 0.
- **Route-decision fields in the edge response**: worker `_claim_route_guard` expects `claimed_backend`/`selected_backend`/`claim_decision_reason` in the claim response, but `claim-next-task/index.ts` (repo) returns only 4 fields. The DB function returns them; whether the deployed edge function forwards them is unverified (worker comment says "Older task responses do not include route decision fields", implying newer ones do).
- **Live DB schema drift**: `reigh-app/supabase/migrations/` may not equal the production schema (migrations stop at 2026-06-22; the worker repo code references behaviors like `result_data` hoisting that match newer functions). Verify against live DB (see `LiveDbProbe` doc) before relying on exact columns.
- **smplfitter usage**: present as a dependency (Wan2GP SMPL/pose stack) but no direct import found in `reigh-worker/source/`; [INFERENCE] it is exercised inside the Wan2GP submodule, not the worker code.
- **Billing internals**: `calculate-task-cost` edge and `triggerCostCalculationIfNotSubTask` were not read in full; the worker-side contract is only `reset_generation_started_at` + `complete_task` triggering cost calc ([INFERENCE] from handler imports).
- **`task-status` (GET) reader** is used by the banodoco poller, not the GPU worker; included for completeness.
- **API orchestrator** (`api_orchestrator/`, run_type=api, fal/replicate handlers) is a separate execution path not covered in depth here; the GPU worker's "HTTP API" is the Supabase edge-function surface, not the orchestrator's own endpoints.
- **progress pings for plain tasks**: no per-step DB progress writes exist for non-orchestrator tasks; WGP progress is log-only. If the product requires progress UI during generation, that data lives only in `system_logs` (via heartbeats) — unverified whether the app consumes it.
- **Orchestrator SSH/health details**: `_perform_basic_health_check`, SSH key material, and RunPod pod-status polling internals read only at summary level.
