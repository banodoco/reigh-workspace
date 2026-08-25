# 13 — Migration Context Dossier: Reigh (Postgres/Supabase) → Astrid (SQLite)

**Consolidated synthesis of `01`–`12` in this directory. Prepared 2026-08-21. READ-ONLY research; no implementation. All claims cite the evidence docs by number; items not grounded in the docs are tagged `[INFERENCE]`.**

---

## 1. Executive Summary

Reigh is a production system whose data authority is **Supabase Postgres**: 51 live tables (547 columns, 202 functions, 150 RLS policies, 6 enums, 42 triggers, 243 indexes, 6 storage buckets) on a single hosted project, plus a **poll-based GPU/API worker fleet** (`reigh-worker`, `reigh-worker-orchestrator`) that reads and writes only through Supabase edge functions — 41 deployable functions, with `create-task` the sole INSERT path into the task queue. The frontend is a Vite/React SPA with no server component: it reads ~30 tables via PostgREST, calls ~20 RPCs and 12 edge functions, and gets live updates from `supabase_realtime` postgres_changes on 5+ tables. Task execution is a **status-machine lease** (atomic claim UPDATE; no lease TTL; recovery by heartbeat crash RPC, orchestrator orphan resets, and a 5-minute pg_cron sweep), with credits gated at claim and deducted at completion.

Astrid is a **local-first, single-writer SQLite kernel** (20 tables: 14 kernel + timeline/shots/references packs) with a hash-chained event log, command-receipt idempotency, SHA-256 content-addressed managed media, and a **frozen HTTP bridge** that already carries the video-editor timeline document (whole-document CAS, `config_version` = stream head, `409 timeline_version_conflict`, Range/ETag asset serving). The v10 plan's explicit posture is **no Postgres migration**: fresh database, delete legacy authorities, import media bytes only, keep Reigh as the editor over the bridge. Operator scripts (`Astrid/scripts/migrations/v10/`, 2026-08-21) prove the SDK-replay pattern works for a local file tree, but **nothing in Astrid can read Postgres today**.

The shape of the migration problem: **three separate surfaces must be decided independently** — (a) the video-editor timeline (bridge already solves it, tested end-to-end), (b) the task/queue/billing/worker pipeline (no Astrid analog; a full port means re-pointing or rebuilding the worker fleet and inventing a billing/credits replacement), and (c) the media/content estate (38k generations, 40k variants, 84k slot attempts, 12k placements, and an unmeasured `image_uploads` volume — the legacy-tree analog was ~8.5 GB unreferenced). Honest entity mapping (§3) shows **most Reigh concepts are GAP**: only `projects` and `timelines` exist today; everything else is partial, missing, or requires a design decision. Live-vs-repo drift (§2, §9) means any migration must be built against the **live** database, never the migration chain, and several production objects (the slot-first system in particular) have no recoverable DDL in this workspace.

---

## 2. Source Systems Inventory

### 2.1 Reigh source stack (what exists today)

**Database — Supabase Postgres (live ground truth, doc 07; schema detail doc 01):**

- **51 tables / 547 columns**, grouped by domain:
  - *Task pipeline core (13)*: `tasks` (45+ cols incl. route/claim columns, generated `prompt`/`seed`/`model`), `task_types` (28 rows, billing config), `workers` (~7k rows), `system_logs` (67k), `credits_ledger` (21k), plus the content tables `generations` (38k), `generation_variants` (40k), `shot_generations` (12k), `shots` (1.3k), `projects` (478), `users` (249), `attempts` (84k), `shot_slots` (38k). [07 §3.13, 01 §3]
  - *Slot-first media system (live-only, untracked)*: `attempts`, `shot_slots`, `slot_first_migration_map` (121k) + 4 lowercase enums + 18 triggers + `slot_first_*` RPCs. No repo migration; no `schema_migrations` entry. [01 §12.4, 07 §3.1, 12 §3.1]
  - *Timeline/editor system (Astrid-like)*: `timelines`, `timeline_events` (ULID event_ids, hash-chained, CAS), `timeline_event_contract`, `sync_bookmarks`, `divergence_log`, `timeline_checkpoints`, `timeline_agent_sessions`, `timeline_update_log`, `effects`, `extension_install_state`/`extension_settings`/`extension_proposals`, `local_media_handles`. [01 §3.3/§3.5, 07 §3.1]
  - *Auth/tokens/keys*: `user_api_tokens` (PATs, plaintext), `external_api_keys` (vault-encrypted). [01 §3.4]
  - *Route control plane*: `route_backend_selectors`, `route_backend_capabilities`, `route_alias_map`, `model_family_for_model` (claims gated on it in repo, **reverted in prod**). [01 §3.6, 12 §5.2]
  - *Commerce*: `credits_ledger` (immutable journal; balance = SUM), Stripe metadata in `users` (auto-topup fields), no separate payments table. [01 §3.1, 02 §7]
  - *Ops/auxiliary*: `sentinel_ticks` (144k), `pause_scaling`, `settings`, `onboarding_config`, `rate_limits`, `dev_tasks`, `training_data`(+segments+batches), `resources` (presets, 5.6k), `shared_generations` (shares), `referrals`/`referral_sessions`, `agent_nodes`/`agent_node_media`/`agent_node_install_targets`/`agent_node_catalog_metadata`, `shot_data_audit`. [01 §3.7–3.8, 07 §3.1]
- **20 views, 6 enums, 42 triggers, 243 indexes, 71 FKs, 129 CHECKs, 1 sequence, 9 extensions** (`http`, `pg_cron`, `pg_net`, `pg_stat_statements`, `pg_trgm`, `pgcrypto`, `plpgsql`, `supabase_vault`, `uuid-ossp`). [07 §1/§3]
- **202 functions** in `public` — task lifecycle RPCs (`claim_next_task_service_role` 7-param live, `complete_task_with_timing`, `func_worker_heartbeat_with_logs`, `cascade_task_failure`, `auto_fail_stale_tasks`), timeline RPCs (`append_timeline_event`, `batch_update_timeline_frames`, shot ops), billing (`refresh_user_balance`, `get_task_cost`), auth (`verify_api_token`), referrals, slot-first RPCs. [01 §4, 07 §3.11]
- **6 storage buckets**: `image_uploads` (public, media — created live, no migration), `temporary` (private 500 MB), `training-data` (private), `lora_files` (public), `timeline-assets` (public), `render-outputs` (private, user-folder RLS); path convention `{userId}/...`. [01 §9, 06 §8.F]
- **Auth**: Supabase GoTrue (Discord OAuth; email/password dev-only); `public.users.id` = `auth.users.id` (no FK); RLS on 46 tables (direct-owner / owner-via-join / service-role-bypass patterns); service role as privileged principal; PATs for workers; anon read surfaces (`settings`, `task_types`, `onboarding_config`, `shared_generations`, public resources, timeline-assets bucket). [01 §8/§10, 06 §4, 07 §3.10]
- **Scheduling**: 6 pg_cron jobs — `route-contract-sentinel` (1/min), `auto-fail-stale-tasks` (5/min), `discord_daily_stats` (daily 09:00), `cleanup_system_logs_daily` (03:00, 48 h retention), `daily-shot-sync-check`, `cleanup-rate-limits`. [01 §1, 10 §7]
- **Realtime publication**: `tasks`, `generations`, `timelines`, `timeline_agent_sessions` (per doc 02); client subscribes to `tasks`, `generations`, `shot_generations`, `generation_variants`, `timelines`. [02 §8, 06 §3.10]

**Application layer (doc 06):**

- **Vite + React SPA** (doc 06 — *not* Next.js as doc 02 says; see contradictions), pure browser, one Supabase client, cached-token fetch shim, React Query polling 2–30 s, realtime channels, optimistic timeline-drag RPCs, IndexedDB sync bookmarks (spoke `'local'`), localStorage auth token.
- **External "append service"** (`VITE_REIGH_APPEND_SERVICE_URL`): the only writer for video-editor `timelines.config`/`asset_registry` mutations; HTTP routes `/v1/timelines/{id}/config-replaced` (CAS `expected_version`, 409), `/app-bookmark`, `/app-divergence`; code **not in this workspace**. [06 §8.G.66]

**Worker pipeline (docs 02, 03, 12):**

- **GPU worker** (`reigh-worker/`): one Python process + heartbeat guardian; polls `task-counts` + `claim-next-task` every ~10 s; executes via WGP in-process or VibeComfy subprocess; uploads to `image_uploads` (base64 <2 MB, presigned ≥2 MB); retry classification (retryable: `generation_no_output` max 2, `edge_function_transient`/`network_transient` max 3; fatal: CUDA/NVML/segfault; OOM deliberately not retryable); RunPod deployment with service-role key in env. [03]
- **Orchestrators** (`reigh-worker-orchestrator/`): GPU capacity orchestrator (30 s cycle: spawn/health/orphan-reset/scale decision; uses `task-counts` RPC breakdowns; `pause_scaling` brake) and API orchestrator (`run_type=api`, fal/wavespeed/image/banodoco handlers, concurrency 20/50, phantom-claim recovery). [02 §2, 03 §6.3, 12 §6]
- **Capacity-reconciler variant** (`reigh-worker-orchestrator-capacity-reconciler/`): `worker_capacity_intents`, `worker_capacity_route_backoffs`, `orchestrator_leases` — **never deployed** (no such tables live). [01 §12.6, 12 §6.2]

**Task-queue mechanics (doc 12):** status-machine lease; atomic claim `UPDATE` (no `FOR UPDATE SKIP LOCKED` in the live 7-param function); eligibility = credits>0, `inCloud`/`onComputer` settings, <5 in-progress per user (orchestrators excluded), deps complete, run_type/pool filters, model affinity with 5-min starvation bypass; retries on `tasks.attempts` (cap 3) via requeue; recovery paths: heartbeat crash RPC, orchestrator orphan resets (15/30 min; 5 min API), 5-min cron auto-fail (In Progress >24 h → Failed; Queued w/ failed dep → Failed); cascades via `cascade_task_failure`. Live state at writing: 15 Queued, **0 In Progress**, 27,392 Complete / 14,678 Cancelled / 3,939 Failed; 2 active workers; scaling paused (`pause_scaling` set). [12 §1/§8]

### 2.2 Astrid target stack (what a move lands on; docs 04, 05, 08, 09)

- **20-table v10 kernel** (one SQLite DB per projects root, WAL, `synchronous=NORMAL`, `busy_timeout=5000`, `foreign_keys=ON`):
  - Kernel (14): `schema_migrations`, `projects`, `event_streams`, `events` (hash-chained SD2 envelope, `project_seq`/`seq` gap-free, `command_receipts` idempotency), `runs`, `tasks` (immutable admission: `capability`, `spec_json`/`spec_hash`, `input_manifest_json`, `status` CHECK queued/blocked/running/succeeded/failed/cancelled, `priority`, `available_at`, `max_attempts`, `winning_attempt_id`, `run_id`/`run_ordinal`), `task_dependencies` (hard/soft), `execution_attempts` (fenced: `status_version`, `lease_id`/`lease_expires_at` 300 s, `heartbeat_counter`; statuses claimed/running/succeeded/failed/cancelled/expired), `task_outputs` (→ media, one primary result), `media` (SHA-256 `content_hash`, `UNIQUE(project_id, content_hash)`), `media_locations` (`realm` managed_local/external_local/remote), `media_relations` (5 kinds incl. `variant_of`), `evidence_items` (5 kinds). [04 §3, 08 §2]
  - Packs: `timelines` (whole-document CAS, `config_version` = stream head), `shots` + `shot_items` (ordered exact-media placements), `project_references`/`media_references`/`reference_links`. [04 §3.15–3.17]
- **Single-writer architecture**: one writer thread owns the only writable connection; one command = one `BEGIN IMMEDIATE`; `FORBIDDEN_TABLES` (plans/steps/sessions/threads/leases/identity/variants/selections + accounts/billing/sync/importer/audit_ledger) must never be created. [04 §2.4]
- **Managed media tree**: `<root>/.astrid/media/sha256/<d2>/<d4>/<sha256>`; staging under `.staging/<txn_id>`; exclusive-owner `flock()` lock file. [04 §1/§5]
- **CLI/SDK**: 8 CLI families (projects, timelines, media, tasks, runs, serve, doctor, backup) + 2 nested mounts; SDK exposes 7 typed services; every mutation returns `DomainResult` with `receipt` + `idempotency_key`; 9 typed error codes. [05 §2]
- **Bridge (frozen contract, implemented)**: `GET /health`, `GET /projects`, `GET /projects/:slug/timelines`, `GET /projects/:slug/timelines/:ref`, `POST .../save` (CAS; hidden idempotency key `timeline.save:{project_id}:{timeline_id}:{expected_version}:{digest}`), `GET|HEAD .../assets/:key` (Range/ETag/304/416), `OPTIONS`. No auth (localhost + CORS allowlist); polling only; **no task/credit/generation routes**. Shared-writer contention proven by test (`test_m7_bridge_contention`). [09]
- **Migration machinery**: `Astrid/scripts/migrations/v10/` — SDK-only idempotent replay (`v10-migrate:{family}:{stable-id}` receipt keys, deterministic UUIDv5/ULID ids, SHA-256 media import, fence/zero-child run fidelity, dry-run + `.bak` backup + `verify.py`); consumes **files only, no Postgres reader exists**. [11]

---

## 3. Entity Mapping Table (Reigh domain concept → Astrid counterpart → status)

Legend: **EXISTS** = a same-named or semantically equivalent table exists in the kernel/packs; **PARTIAL** = a structural counterpart exists but semantics/fields/behaviors differ materially; **GAP** = no counterpart; **DESIGN-NEEDED** = GAP with a required design decision (not derivable from existing code). Be honest: most rows are GAP/DESIGN-NEEDED. [All mappings are the synthesizer's reconciliation of docs 01/04/05/07/12; status is grounded in the cited docs.]

| Reigh concept (doc 01/07 table) | Astrid counterpart (doc 04/05/08) | Status | Notes |
|---|---|---|---|
| `users` (profile, credits, settings, onboarding) | none — kernel has no user/account concept; `projects` is the isolation boundary | **GAP / DESIGN-NEEDED** | No accounts/billing/tenancy in kernel (`FORBIDDEN_TABLES`); v10 defers identity to app shell/external service. [04 §2.4, 08 §5.Q4] |
| `projects` | `projects` (kernel) | **EXISTS** | slug UNIQUE, name, `settings_json`, `event_head_seq`. Reigh `aspect_ratio`/`user_id`/`settings` → `settings_json` (legacy keys pattern shown in v10 scripts). [04 §3.2, 11 §5] |
| `shots` (+ position, aspect_ratio, settings, parent generation) | `shots` + `shot_items` (shots pack) | **PARTIAL** | Pack shots have `sort_key` ordering + `shot_items` (media placements, `source_frame`); no position/aspect_ratio/settings columns, no parent-generation invariant, no shot-generation join table. [04 §3.16, 01 §3.2] |
| `shot_generations` (timeline_frame, metadata, RPC-normalized positions) | `shot_items` (ordered media placements) | **PARTIAL** | `shot_items` ≈ placement rows (`sort_key`/`source_frame`/`metadata_json`) but no `timeline_frame` integer semantics, no pair metadata (`metadata.pair_*`, `enhanced_prompt`), no normalize/reorder RPCs. [04 §3.16, 06 §6.1] |
| `generations` (media row: location, params, based_on, children, primary_variant_id, shot_data) | `task_outputs` + `media` + `media_relations` | **PARTIAL / DESIGN-NEEDED** | Astrid models produced bytes as media + ordered outputs + `derived_from`/`variant_of` relations; no `generations` aggregate, no `based_on`/`parent_generation_id`/`children` family, no `primary_variant_id` pointer, no `shot_data` denormalization. [04 §3.10–3.13, 01 §3.2] |
| `generation_variants` (is_primary, variant_type, viewed_at, starred) | `media_relations` (`variant_of`, one parent) | **PARTIAL / DESIGN-NEEDED** | One-`variant_of`-parent + acyclic exists; no primary-flag semantics per family, no gallery/viewed/starred state, no original-variant-deletion guard, no primary-switch trigger. [04 §3.13, 01 §3.2] |
| `tasks` (params JSONB, status enum, dependant_on[], attempts, route/claim cols) | `tasks` (kernel) | **PARTIAL** | Same name, different contract: kernel tasks are immutable admissions (`capability`+`spec_json`+`spec_hash`, `max_attempts`, `priority`, `available_at`, deps hard/soft); Reigh tasks are mutable free-form JSONB job rows with per-family payload contracts, billing fields, route/claim columns, `dependant_on` array, `worker_id`, timing columns. Status vocabularies differ (Queued/In Progress vs queued/running; Complete vs succeeded). [04 §3.7, 10 §3, 12 §3.2] |
| `attempts` TABLE (84k, slot-first media attempts) | `execution_attempts` (kernel) | **GAP / DESIGN-NEEDED** | Name collision with different meaning: Reigh `attempts` = media-attempt history per shot-slot (lineage `parent_attempt_id`/`based_on`/`pair_shot_attempt_id`, `attempt_type` original/regen/edit/upscale/reposition/duplicate, storage fields); kernel `execution_attempts` = fenced execution attempts of a *task* (lease, status_version). No slot/primary-attempt concept in Astrid. [12 §3.1 vs 04 §3.9] |
| `task_types` (28 rows, billing config, run_type) | none (`tasks.capability` free text) | **GAP / DESIGN-NEEDED** | No task-type registry/catalog, no billing metadata, no run_type (gpu/api) separation in kernel. [01 §3.1, 10 §4] |
| `workers` (registry, heartbeat, model) | none (`execution_attempts.executor_id` only) | **GAP** | No worker registry, no heartbeat table, no current_model affinity. [03 §5.2, 04 §3.9] |
| `credits_ledger` (21k, immutable journal) | none (`FORBIDDEN_TABLES` incl. billing) | **GAP / DESIGN-NEEDED** | Billing is explicitly out of the kernel; a Reigh-on-Astrid design must choose a replacement ledger (local wallet, external payments service, or drop). [04 §2.4, 08 §4, 02 §7] |
| Payments (Stripe checkout/webhook/auto-topup) | none | **GAP** | No Stripe integration; v10 defers payments/cloud. [06 §5, 08 §6.7] |
| `timelines` (config, asset_registry, config_version) | `timelines` (timeline pack) | **EXISTS** | Whole-document CAS on both sides; `config_version` = stream head; 409 on stale. This is the best-mapped entity. [01 §3.3, 04 §3.15, 09 §5] |
| `timeline_events` (hash-chained, ULID event_ids, source_* fields) | `events` (hash-chained SD2 envelope) | **PARTIAL** | Both are hash-chained append logs; Astrid events are registry-validated, namespaced, per-stream with `_integrity` envelope; Reigh timeline_events carry sync-protocol fields (`expected_version`, `source_backend`, `source_timeline_id`, `source_event_id`) with no Astrid equivalent. History replay is a design choice (replay-as-events vs collapse-to-latest). [01 §3.3, 04 §4.1, 11 §6] |
| `sync_bookmarks` (spoke/hub heads) | none | **GAP / DESIGN-NEEDED** | Cross-device spoke/hub sync (IndexedDB local spoke); Astrid is single-writer local — sync may be unnecessary or must be redesigned. [01 §3.3, 06 §6.2] |
| `divergence_log` (keep-both) | none | **GAP** | Astrid CAS is strict 409; no keep-both divergence record. [01 §3.3, 09 §4] |
| `timeline_checkpoints` | none | **GAP** | No checkpoint/undo-snapshot concept in kernel. [01 §3.3, 06 §3.9] |
| `timeline_agent_sessions` | none | **GAP** | Agentic editing sessions (turns, status, model) have no kernel counterpart; `ai-timeline-agent` edge fn persists here. [01 §3.3, 06 §7.1] |
| `timeline_event_contract`, `timeline_update_log` | none (`events.schema_version` per event) | **GAP** | Singleton schema-version row and debug audit log absent; audit could be rebuilt on events. [01 §3.3] |
| `extension_install_state` / `extension_settings` / `extension_proposals` | none | **GAP** | Editor extension platform persistence has no kernel counterpart. [01 §3.5, 06 §3.9] |
| `effects` (code shaders) | none | **GAP** | User-authored effect catalog absent. [01 §3.3, 06 §7.1] |
| `resources` (presets/loras, public/owned) | `media` + `media_locations` (+ references pack) | **PARTIAL / DESIGN-NEEDED** | Bytes can be media; but preset semantics (type, is_public, featured, generation_id link) and public-read RLS have no counterpart. [01 §3.2, 04 §3.11] |
| `local_media_handles` (pending local upload) | `media_locations.realm` (managed_local/external_local) | **PARTIAL** | Local-first storage exists in Astrid; the pending-materialization handle flow (insert handle → generations.location=null → materialize) has no direct equivalent. [01 §3.2, 04 §3.12, 06 §3.3] |
| `shared_generations` (public share links, view counts) | none | **GAP / DESIGN-NEEDED** | Public sharing (slug, creator cache, anon RPCs `get_shared_shot_data`/`increment_share_view_count`/`copy_shot_from_share`) has no local-first counterpart. [01 §3.2, 06 §8.B.17] |
| `user_api_tokens` (PATs) | none | **GAP** | No auth/token concept in Astrid (localhost bridge, no tokens). [01 §3.4, 09 §3] |
| `external_api_keys` (vault-encrypted) | none (secrets → explicit/env/keychain per v10) | **GAP / DESIGN-NEEDED** | v10 simplifies secrets resolution to explicit → env → keychain. [01 §3.4, 05 §6.7] |
| `agent_nodes` + catalog/install/media (marketplace) | none | **GAP** | Agent marketplace/catalog absent; v10 has no plugin marketplace. [01 §3.8, 08 §6.7] |
| `referrals` / `referral_sessions` / `referral_stats` | none | **GAP** | Referral acquisition system (anon-insert sessions, fingerprint/IP) absent. [01 §3.8, 06 §3.6] |
| `training_data` / `training_data_segments` / `training_data_batches` | none (media could hold bytes) | **GAP / DESIGN-NEEDED** | LoRA training-data pipeline absent; v10 DEFERs training product. [01 §3.7, 05 §6.7] |
| Storage buckets (`image_uploads`, `temporary`, `training-data`, `lora_files`, `timeline-assets`, `render-outputs`) | managed media tree + `media_locations` + bridge asset serving | **PARTIAL** | Astrid serves assets via Range/ETag from verified media; no public-URL semantics, no signed URLs, no per-bucket policies, no `{userId}` path conventions (single-writer local). [04 §5, 09 §5] |
| `route_backend_selectors` / `route_backend_capabilities` / `route_alias_map` / `model_family_for_model` | none | **GAP** | Route control plane (wgp vs vibecomfy selection) is Reigh-specific; live claims ignore it anyway (prod reverted gating). [01 §3.6, 12 §5.2] |
| `sentinel_ticks` / `pause_scaling` | none | **GAP** | Queue-health sentinel and scaling brake absent. [12 §4] |
| `settings` (feature flags) / `onboarding_config` / `rate_limits` / `dev_tasks` | `projects.settings_json` (repository-owned keys only) | **PARTIAL / GAP** | No global KV store, no onboarding templates, no rate-limit counters, no dev-task tracker in kernel. [01 §3.7, 04 §3.2] |
| `slot_first_migration_map` (121k) | `command_receipts` (idempotency) | **GAP** | Reigh's migration bookkeeping for the slot system; Astrid's receipt ledger serves the analogous purpose for its own migrations. [01 §3.1, 04 §3.5] |
| `shot_data_audit` (83k) | `events` (audit trail) | **PARTIAL** | Astrid events are the audit trail; Reigh's trigger-fed audit table could be re-expressed as events. [01 §3.8, 04 §4.1] |

---

## 4. Task/Queue Migration Mapping

### 4.1 Reigh model (docs 02, 03, 12)

- **Storage**: one `tasks` row per job — status enum `Queued | In Progress | Complete | Failed | Cancelled`, free-form `params` JSONB (per-family contracts), `dependant_on uuid[]`, `attempts int` (cap 3), `worker_id`, `generation_started_at`/`generation_processed_at` (billing clock), `idempotency_key` (unique partial), `materialized_inputs`, route/claim snapshot columns, `result_data`.
- **Claim**: atomic `UPDATE tasks SET status='In Progress', worker_id, generation_started_at, claimed_* ... FROM ready_tasks WHERE rn=1` in `claim_next_task_service_role` (7-param, live = pre-route pool version; repo = route-gated, **not deployed**). Eligibility: credits>0, `inCloud`/`onComputer`, <5 In Progress per user (orchestrators excluded), deps complete, run_type/pool filters, model affinity with 5-min starvation FIFO fallback. No lease column; no `FOR UPDATE SKIP LOCKED` in the live function. [12 §2]
- **Execution**: workers poll every 10 s; orchestrator chains create child tasks via the same `create-task` edge (deps-chained); heartbeat every 20 s (guardian → `func_worker_heartbeat_with_logs`, logs to `system_logs`). [03 §2/§5]
- **Retry**: worker-side classification (retryable patterns, per-category max 2–3) → requeue (`status='Queued'`, `attempts+1`, `clear_worker`); heartbeat crash recovery (attempts<3 requeue, ≥3 fail + cascade); orchestrator orphan resets; API startup reset. Cap = 3 everywhere. Live retry usage ≈ 0 (46,007 attempts=0, 17 at 1, 0 at ≥2). [12 §3.2]
- **Cleanup**: pg_cron `auto_fail_stale_tasks` (5 min; In Progress >24 h → Failed; Queued w/ failed dep → Failed); `cascade_task_failure` propagates to orchestrator chains via 5 params-ref paths; terminal states final. [02 §9, 12 §8]
- **Capacity/health**: `task-counts` RPC breakdowns → GPU orchestrator scaling; `route-contract-sentinel` (1/min) classifies into `sentinel_ticks`, pages + sets `pause_scaling` after 5 consecutive alarms (live: 65% UNCLAIMABLE_WORK; scaling paused at writing); capacity-reconciler variant (intents/backoffs/orchestrator_leases) **not deployed**. [12 §4/§6]
- **Billing**: credits gated at claim; cost computed at completion (`calculate-task-cost`, duration × `task_types` config; fallback 0.0278/s; orchestrator = sum of child durations; sub-tasks skipped); single negative `credits_ledger` `spend` row, idempotent; balance trigger-recomputed; no refunds. [02 §7, 10 §4]

### 4.2 Astrid model (docs 04, 05, 08)

- **Storage**: `tasks` rows are **immutable admissions** — `capability`, `spec_json` (+`spec_hash`), `input_manifest_json`, `priority`, `available_at`, `max_attempts`, `run_id`/`run_ordinal`, `status` CHECK `queued|blocked|running|succeeded|failed|cancelled`; `task_dependencies` (hard/soft, acyclic); **`execution_attempts` rows** per attempt (fenced: `status_version` CAS, `lease_id`/`lease_expires_at` default 300 s, `heartbeat_counter`, `last_heartbeat_at`; statuses `claimed|running|succeeded|failed|cancelled|expired`); `task_outputs` → verified `media`; `runs` as fan-out group handles; `command_receipts` idempotency (key + request_hash, replay returns stored result).
- **Claim/execute**: `tasks.claim` (system/executor actor) → `tasks.start` (status-version fence) → heartbeats as **non-event** narrow updates → `tasks.complete` (materializes media) / `fail` / `expire`. Terminal tasks never resurrect; stale attempts cannot materialize output. [05 §3.4]
- **Retry**: `tasks.retry` only for failed/expired tasks with budget remaining; attempt history preserved as rows. [05 §3.4]
- **Cancel**: queued/blocked cancelled directly; running requires executor-owned fence; cooperative cancel via `cancel_request_id`/`cancel_requested_at`. [05 §3.4]

### 4.3 What maps, what must be re-designed

| Reigh mechanic | Astrid mechanic | Verdict |
|---|---|---|
| `tasks` row + status enum | `tasks` row + status CHECK | **Maps with renaming** (Queued↔queued, In Progress↔running, Complete↔succeeded, Failed↔failed, Cancelled↔cancelled); `params` JSONB → `spec_json`/`input_manifest_json` + `capability` needs a task-type taxonomy. |
| `tasks.attempts` counter (cap 3) | `execution_attempts` rows + `max_attempts` | **Astrid is richer** — each attempt is a fenced row with lease/heartbeat/error; Reigh's counter collapses history. Migration can materialize one attempt row per counted retry. |
| Atomic claim UPDATE + worker stamp | `tasks.claim` with executor_id + attempt fence | **Maps**; Astrid's `status_version` fence is stronger than Reigh's bare status re-check. |
| `dependant_on uuid[]` | `task_dependencies` (hard) | **Maps**; soft deps are Astrid-only extra. |
| `idempotency_key` unique partial | `command_receipts` (key + request_hash) | **Astrid is stronger** (request-hash mismatch rejection, replay-by-receipt). |
| `worker_id` + `workers` registry + heartbeat | `execution_attempts.executor_id` + heartbeat_counter/last_heartbeat_at | **Partial**; no worker registry table, no VRAM metadata, no current_model affinity. Registry is a GAP. |
| `generation_started_at`/`processed_at` billing clock | attempt `started_at`/`finished_at` | **Maps** (fence timestamps). |
| Credits gating (`credits>0`, <5 in-progress) | none | **Must be re-designed** (no billing in kernel). Per-user concurrency cap must be re-implemented as a claim-side check. |
| Model affinity + starvation bypass | `priority` + `available_at` ordering | **Partial** — priority replaces affinity; starvation needs a design decision. |
| Orphan resets / stale sweeps / 24 h auto-fail | lease expiry (`expired`) + retry budget | **Maps in spirit**; 300 s default lease vs 24 h Reigh threshold — cadence must be re-tuned. |
| Heartbeat crash recovery | lease expiry + heartbeat non-event | **Maps**; crash → expired → retry. |
| `cascade_task_failure` (orchestrator chains) | run-level `runs.cancel`/`retry_failed` + dependency edges | **Partial** — Reigh's 5 param-ref chain linking (orchestrator_task_id_ref, orchestration_contract, orchestrator_details, originalParams) has no structural analog; must be re-expressed via run membership or explicit deps. |
| `sentinel_ticks` / `pause_scaling` / capacity scaling | none | **GAP** — queue-health observability and capacity management must be re-designed (or dropped for local use). |
| `task-counts` breakdowns for scaling | none (no workers registry) | **GAP**. |
| Billing (`calculate-task-cost`, `credits_ledger`, auto-topup) | none (`FORBIDDEN_TABLES` billing) | **Must be re-designed or outsourced**. |
| Realtime push on status change | none (bridge is polling) | **Must be re-designed** (SSE/websocket on the bridge, or accept 15–30 s polling). |
| `task_types` registry | `capability` strings | **Must be re-designed** (capability taxonomy + billing config). |
| `attempts` TABLE (slot media attempts) | `media_relations` + `task_outputs` | **Must be re-designed** — slot/primary-attempt model has no Astrid equivalent; decide whether media lineage via `derived_from`/`variant_of`/`uses_as_input` suffices. |
| Orchestrator child-task creation (`create-task` passthrough) | `runs.create` fan-out with run_ordinal + dependencies | **Maps** (fan-out limit 256/command with continuation envelope). |

---

## 5. Identity & Typing Differences

| Dimension | Reigh (docs 01, 07, 10, 12) | Astrid (docs 04, 05, 08, 09) | Migration impact |
|---|---|---|---|
| Object IDs | UUIDv4 everywhere (`gen_random_uuid()`), including `tasks`/`generations`/`projects`/`credits_ledger`; `timeline_events.event_id` = 26-char ULID (CHECK regex); `worker_id` = free text (`gpu-<ts>-<hex>`) | Aggregates = 26-char **lowercase Crockford ULID**; events/txn = `uuid4().hex`; stream id = `<project_id>:<stream_type>`; deterministic UUIDv5 ids in migration replays | Every FK/ID must be re-mapped; deterministic id derivation (`derive_stable_id`/`derive_ulid`) is available for replay; timeline UUID↔ULID dual addressing already exists in the bridge (`:ref` resolves UUID → ULID → slug). No UUIDv7 appears in any doc. [11 §4, 09 §5] |
| Media identity | Storage URLs (`{userId}/tasks/{taskId}/{file}` public/signed URLs) as `location`/`output_location`/`thumbnail_url` | SHA-256 of bytes, project-scoped `UNIQUE(project_id, content_hash)`; `media_locations` replaceable locators | Media must be re-hashed on import (v10 scripts already do this); dedupe by bytes; public/signed URL semantics gone. [04 §3.11, 11 §5] |
| Timestamps | `timestamptz` native PG columns (`now()`, `timezone('utc', now())`) | TEXT ISO 8601 UTC (`Z` domain code, `+00:00` runner) | Mechanical conversion; preserve original timestamps in `settings.legacy`/metadata (v10 pattern). [04 §7, 11 §5] |
| Enums | Postgres ENUMs: `task_status` capitalized (`Queued`/`In Progress`/…), `credit_ledger_type` lowercase; live adds lowercase `attempt_status`/`attempt_storage_mode`/`attempt_type`/`shot_slot_kind` — two conventions side by side | Frozen DDL CHECKs (tasks/runs/attempts statuses, realms, relation kinds, reference kinds) + repository-enforced closed sets (evidence kinds, stream/event kinds) | Map value-for-value (e.g. `In Progress` → `running`); registry-validated vocabularies mean new kinds require code changes, not just data. [01 §2, 07 §3.2, 04 §7] |
| JSON payloads | Free-form JSONB `tasks.params` per-family contracts (orchestrator_details, orchestration_contract, lineage fields, route_contract); `result_data` envelope; no size/depth limits | Canonical JSON (sorted keys, compact, bounded 1 MiB in / 4 MiB out / depth 100); `spec_json`/`input_manifest_json`/`payload_json` with `json_valid` CHECKs; SD2 `_integrity` envelope | Reigh payloads must be re-canonicalized and size-validated; spec_hash = SHA-256 of canonical `{spec, input_manifest}`. [04 §3/§4.1, 10 §3.3] |
| Versioning/CAS | `timelines.config_version` integer + append-service `expected_version` + 409; `sync_bookmarks` spoke/hub heads for cross-device sync; stripe partial-unique idempotency | `config_version` = timeline stream head; whole-document CAS save + 409 `timeline_version_conflict`; `status_version` optimistic fence on attempts; command receipts for idempotency | **Already aligned for the editor timeline** (09 §4/§5); sync_bookmarks keep-both divergence has no Astrid analog (strict 409). [01 §3.3, 09 §5, 05 §3.2] |
| Event log | `timeline_events` (version, prev_hash, hash, kind, payload, actor, expected_version, txn_id, source_* provenance) | `events` (project_seq/seq, hash-chained SD2 envelope, idempotency_key per stream, txn_id, actor_kind local/system/executor) | Both hash-chained append logs; Astrid events are the only ledger for ALL mutations (not just timelines) — a superset role. [01 §3.3, 04 §4.1] |
| Migration bookkeeping | `supabase_migrations.schema_migrations` (465 applied vs 466 files, 4 missing, `_applied_`/`_hold_` specials) | `schema_migrations` PK `(pack, version)` + SHA-256 checksum + dependency-ordered packs | Different mechanisms entirely; Reigh's ledger is itself drifting (see §9). [07 §4, 04 §2.3] |

---

## 6. Security Model

### 6.1 Reigh today (docs 01, 06, 07, 10)

- **Auth**: Supabase GoTrue; Discord OAuth (only public sign-in); JWT sessions in localStorage; dev email/password path. `public.users.id` mirrors `auth.users.id` (no FK; app-layer invariant).
- **RLS**: enabled on **46 tables**, **150 policies** in three patterns — (1) direct-owner `auth.uid() = user_id`; (2) owner-via-join (`project_id IN (SELECT id FROM projects WHERE user_id = auth.uid())` — survives project ownership changes); (3) service-role full bypass. Special surfaces: cross-user task claiming policies, authenticated-read workers/settings/task_types, service-role-only system_logs/credits_ledger/rate_limits/route tables, authenticated-SELECT-only timeline event tables, public-read `shared_generations`/public resources/`timeline-assets` bucket. [01 §8, 07 §3.10]
- **Edge functions**: 41 functions; auth via `_shared/auth.ts` (service-role key match → user JWT → PAT); **all DB access via the admin/service-role client, bypassing RLS**; per-function `verify_jwt` config; rate limiting via `rate_limits` RPC. [10 §1/§2]
- **PATs**: `user_api_tokens` stores **plaintext** 32-char tokens; `generate-pat`/`revoke-pat`; PAT path uses `claim_next_task_user_pat` (no credits/run_type constraints). [10, 01 §3.4]
- **Secrets**: service-role keys in app/worker env; Stripe/webhook secrets; `external_api_keys` vault-encrypted; Vault for sentinel JWT. [01 §11, 03 §7.1]
- **Storage**: per-bucket RLS (25 policies across 6 buckets), `{userId}` first-folder ownership, signed URLs (1 h), public buckets for media. [01 §9, 06 §8.F]
- **Anon/public surfaces**: `/share/:shareId` RPCs, public resources, `settings`/`task_types`/`onboarding_config` SELECT, timeline-assets public reads. [06 §4]

### 6.2 Astrid target (docs 04, 05, 09)

- **No auth**: local-first; bridge binds `127.0.0.1` by default with CORS allowlist (localhost:2222/3000/5173); no TLS, no tokens, no sessions. The only "actor" notion is `events.actor_kind ∈ local|system|executor`. [09 §3, 04 §4.3]
- **Single writer**: exclusive-owner `flock()` lock on the DB; one writer thread; read-only connections. Security = process ownership + filesystem, not RLS. [04 §2.4]
- **No tenancy**: `projects` is the isolation boundary; no accounts/billing/sync/tenancy tables (FORBIDDEN). [04 §2.4, 08 §5.Q4]
- **Secrets**: v10 simplifies to explicit → env → keychain (no in-DB vault). [05 §6.7]

### 6.3 What happens to auth/tenancy/RLS in a local-first world

- **RLS disappears as a mechanism** — replaced by single-writer exclusivity + repository-enforced ownership (same-project assertions, pack laws). The 150 policies are irrelevant *if* one user owns one machine/DB.
- **Tenancy collapses**: multi-user tenancy (auth.users, RLS owner-via-join) only survives if the design keeps per-user DBs/projects-roots or reintroduces an account layer — which the kernel forbids today. Decision needed.
- **PATs and service role vanish**; worker auth must become either local trust (localhost bridge extended to tasks) or a new token scheme if workers stay remote.
- **Public surfaces** (share links, public presets, anon reads) have no local counterpart — local-first means "public" is either dropped or re-implemented as explicit sharing/export.
- **Storage RLS → filesystem**: `{userId}` path conventions and signed URLs disappear; media is content-addressed managed bytes served by the bridge with Range/ETag.
- **Audit/evidence**: RLS logging gives way to the event log (every mutation is a receipted, actor-tagged event).

---

## 7. Bridge-First Strategy

### 7.1 What the frozen bridge (doc 09) already gives Reigh

- **Timeline document read/write**: `GET /projects/:slug/timelines/:ref` (load: `config` + `registry.assets` + `config_version`) and `POST .../save` (whole-document CAS with `expected_version`; 409 `timeline_version_conflict` with current head; hidden derived idempotency key `timeline.save:{project_id}:{timeline_id}:{expected_version}:{digest}`; receipt-secrecy — no internal ids leaked). [09 §4/§5]
- **Discovery**: `GET /health`, `GET /projects`, `GET /projects/:slug/timelines` (slug-ascending; `timeline_id`/`timeline_ulid`/`name`/`is_default`). [09 §3]
- **Asset serving**: `GET|HEAD .../assets/:key` with single-range 206 / 416 / 304 ETag; bytes verified against content SHA-256; served from managed or external_local realms. [09 §3]
- **Client-side implementation**: `AstridBridgeDataProvider.ts` (1162 lines) + zod `bridgeContract.ts`; 22 passing tests + real-bridge Playwright e2e lane; poll-adoption gating, draft recovery, 409 diverged state, lost-ack recovery. [09 §7]
- **Proven single-writer**: `test_m7_bridge_contention` proves bridge saves, SDK saves, and task admission serialize on one writer queue without cross-authority conflict. [09 §6]
- **Latency/CI gates** pin the contract (GET/save p95 ≤500 ms warm; both repos' CI). [09 §7]

### 7.2 What it lacks (the gaps a full migration must fill)

- **Tasks/queue**: no task routes at all; the bridge adapter composes only project+timeline services. Workers (`reigh-worker`/`reigh-worker-orchestrator`) have **zero Astrid references**; orchestration stays Supabase-side today. [09 §6]
- **Credits/billing**: nothing — no ledger, no balance, no gating. [09 §1]
- **Auth**: none (localhost trust); cannot serve multi-user or remote-worker flows without new transport/token design. [09 §3]
- **Generations/media gallery**: no generation/variant/shot-timeline routes; assets flow only through the timeline registry. The shot-timeline RPCs (`batch_update_timeline_frames`, `reorder_normalized`, `add_generation_to_shot`, …) have no bridge surface. [09 §1, 06 §8.C]
- **Realtime**: polling only (3 s discovery, 30 s timeline); no push channel for task/generation updates. [09 §3]
- **Public sharing/referrals/agent sessions**: absent. [06 §8]
- **Not-yet-built bridge items**: `POST .../copy` reserved (m6); the v10 plan also CUTs legacy Supabase/append/FSA modules (still present in-tree as a parts bin). [09 §7]
- **Editor FSA sub-mode** is still implemented client-side and is a second semantic writer; v10 deletes it unconditionally — a migration must ensure it is never activated. [09 §4/§9]

### 7.3 Strategy implication

The bridge already covers the **video-editor timeline** end-to-end (the "biggest single external seam" per doc 06 §8.G.66 — the append service — is effectively replaceable by it). A bridge-first migration means: keep the editor's `SupabaseDataProvider` → `AstridBridgeDataProvider` swap (already built and tested), land project/timeline/media discovery on Astrid, and treat **tasks, credits, generations, and the worker pipeline as a separate workstream** that either extends the bridge (new frozen routes) or remains on Supabase while Reigh runs hybrid. Extending the bridge is a DESIGN-NEEDED decision, not an implemented path. [06 §8, 09 §1]

---

## 8. Migration Machinery

### 8.1 What the v10 scripts already provide (doc 11)

- **SDK-only idempotent replay**: every mutation through `AstridClient`/repositories (no raw SQL writes, no importer tables); stable receipt keys `v10-migrate:{family}:{stable-id}`; kernel `command_receipts` gates make reruns replay with zero new rows and changed requests fail as `idempotency_mismatch`. [11 §4]
- **Deterministic IDs**: `derive_stable_id` (UUIDv5 over `\x1f`-joined components) for media; `derive_ulid` (SHA-256 → 26-char Crockford) for timelines/tasks/runs; `:id2`/`:slug2` suffixed keys for collisions. [11 §4]
- **SHA-256 media import**: hash outside the transaction, `media_id = derive_stable_id(core.media.import, project_id, key, 0)`, realm `managed_local` (copy into the digest tree) or `external_local` (reference in place); project-scoped byte dedupe; `media_map.json` reuse. [11 §2/§5]
- **Run fidelity paths**: fence path (`runs.create` → `tasks.claim` → `tasks.start` → `tasks.complete`, executor `"v10-migration"`, `derived_from` relations to input media) and zero-child path (`runs.create(children=[])` → `core.run.close` command, dedicated key) — the only way to terminalize a zero-task run. [11 §5]
- **Guards**: `--apply` refuses unless the kernel DB has **zero project rows**; refuses to clobber an existing `.bak`; requires the exclusive-owner lock (stop `astrid serve`); forbids concurrent migrations. [11 §1]
- **Verification**: `verify.py` — counts vs inventory; every referenced file has a media row with matching SHA-256 and on-disk location; event hash chain genesis→head; no forbidden tables (`migration_`/`legacy_`/`importer_`/`import_` prefixes); legacy files untouched (read-only proof). [11 §2]
- **Contradiction resolution**: v10 plan's "no data migration" is a **product-surface** commitment (no importer family/tables/parity machinery in the product); the scripts are **operator scripts outside the product** (`scripts/`, not `astrid/`), now the sanctioned legacy-data path per SKILL.md/getting-started. The plan was never revoked — it was scoped. [11 §8]

### 8.2 What a net-new Reigh source adapter must do (all `[INFERENCE]` design, grounded in doc 11 §7 + 07)

1. **Read Postgres — nothing in Astrid does today.** No psycopg/asyncpg/PG driver anywhere; the only Supabase code is a thin HTTP write wrapper for legacy timeline eventlog. A Reigh adapter needs (a) an export step producing an inventory-like JSON from the live DB (SELECT-only, via `DATABASE_URL` path already documented in doc 07 §5), or (b) a new Python source adapter with a PG driver.
2. **Map the 51-table schema**: at minimum users→projects, projects, shots, shot_generations→shot_items, generations/variants→media+relations+outputs, tasks→kernel tasks/runs/attempts, credits_ledger (decision-dependent), timeline tables→timeline pack, media from storage URLs (download `image_uploads`/`timeline-assets`/`render-outputs` bytes, hash, import). Media from storage requires export tooling the v10 scripts don't have (they walk a local tree).
3. **Preserve live fidelity**: row counts, timestamps, statuses (enum value mapping §5), lineage (`based_on`, `parent_generation_id`, `pair_shot_generation_id`, attempt lineage), billing history, idempotency (map `tasks.idempotency_key` → receipt keys).
4. **Reuse unchanged**: receipt-keyed SDK replay, `derive_stable_id`/`derive_ulid`, SHA-256 media import, fence/zero-child run fidelity, dry-run + backup + verify, guards. New keys would follow `v10-migrate-reigh:{family}:{stable-id}`.
5. **Decide scope against the plan**: v10's posture says import media bytes only and delete legacy authorities — a full Reigh data migration contradicts that posture unless scoped as operator scripts like v10 (which is exactly how the existing scripts resolve it). This is a user decision (§10), not a technical given.

---

## 9. Risks

1. **Data loss — `attempts` table (84k rows)**: slot-first media-attempt history with lineage (`parent_attempt_id`, `based_on`, `pair_shot_attempt_id`, `superseded_by`), storage fields, and primary-attempt pointers. Its DDL is **not recoverable from this repo** (no migration, no `schema_migrations` entry; live `pg_proc`/`pg_get_viewdef` only), and **no callers exist in the checked-out repos** (writers are on deployed-but-unchecked code or were backfill-only). Migrating it without understanding its live writers risks loss or mis-modeling. [12 §3.1, 01 §12.4]
2. **Data loss — ledger history & balance semantics**: `credits_ledger` (21k rows) is immutable and balance = SUM(amount); `users.credits` is trigger-maintained. Billing has no Astrid home (FORBIDDEN). Dropping or re-deriving the ledger breaks billing correctness, Stripe idempotency (`metadata.stripe_session_id`/`stripe_payment_intent_id` partial-unique), auto-topup, and the no-refund reality. [01 §3.1, 02 §7, 10 §4]
3. **Drift — live vs migrations**: 4 prod-applied migrations missing from the repo (claim-overload drop, PostgREST reload, route-gating revert, assert-trigger drop); `_applied_` `external_api_keys` version collision; 3 `_hold_` files; stale `types.ts`. **Building against the repo reproduces prod's deliberately-reverted state** (route-gated claims + assert trigger). [07 §4, 12 §5.2, 01 §12]
4. **Drift — the slot system**: `attempts`/`shot_slots`/`slot_first_*` contradict doc 07's "no reverse drift" claim; a full live snapshot of these objects (views, RPC bodies, RLS, triggers) is recommended before any migration touches them. [12 §3.1/§9, 07 vs 01/12]
5. **Billing correctness**: fractional-cent math on `numeric(10,3)`; orchestrator billing (parent absorbs; sub-tasks skipped; cancelled orchestrators billed for completed segments); no automatic refunds; `credit_ledger_type` enum value `refund` with no writer; credits gating in-flight tasks at claim. Any port must preserve the ledger invariants or explicitly accept divergence. [02 §7, 10 §4]
6. **Realtime UX**: the app depends on postgres_changes push for tasks/generations/variants/shot_generations/timelines + agent sessions; the bridge is polling-only (15–30 s worst case). Without push, React Query invalidation freshness degrades; timeline saves already tolerate polling, but the task/progress UX does not. [06 §3.10, 09 §3]
7. **409/CAS semantics**: editor timeline CAS is solved (bridge), but the *shot* timeline (travel/segments UI) uses non-CAS normalized RPCs (`batch_update_timeline_frames`, `reorder_normalized`, `delete_and_normalize`) with optimistic updates — no Astrid equivalent exists for these; single-writer removes cross-client races locally but concurrent browser tabs still collide (the bridge's poll-adoption gating handles the video editor only). [06 §3.2/§8.C, 09 §3]
8. **Single-writer contention**: one DB per projects root, exclusive owner lock — `astrid serve` must be stopped during migration (`--apply` fails otherwise); multi-user/multi-process access requires design (per-user roots or a server). [11 §1, 04 §2.4]
9. **Media volume**: `image_uploads` (and other buckets) size is unmeasured; the legacy-file analog cataloged ~8.5 GB unreferenced media that was never imported (cataloged only). SHA-256 hashing and copying 8.5 GB+ (plus referenced media) is a real I/O cost; unreferenced/orphaned storage objects need an explicit policy (import / skip / delete). [11 §1/§6, 07 §3.13]
10. **Unreferenced data**: 210 unresolvable media refs in the v10 inventory analog; orphaned generations/attempts/storage rows, `system_logs` (67k, 48 h retention), `sentinel_ticks` (144k), `slot_first_migration_map` (121k) — all carry no product value post-migration and must be explicitly disposed. [11 §6, 12 §4]
11. **Worker pipeline re-pointing**: `reigh-worker`/`reigh-worker-orchestrator` have zero Astrid references; the fleet reads Supabase edge functions exclusively. Any full migration either keeps Supabase running as the task backend (hybrid) or rebuilds claim/complete/heartbeat/upload endpoints against Astrid (large). [09 §6, 03]
12. **RLS/tenancy semantics loss**: 150 policies encode ownership/join rules; a local-first single-writer model drops them wholesale. If multiple users ever share a store, the ownership filters must be re-implemented — silently losing them is a data-exposure/safety risk. [07 §3.10, 08 §5.Q4]

---

## 10. Open Questions for the User (numbered, decision-worthy)

1. **Goal**: Is this migration about moving *existing Reigh production data* onto Astrid SQLite, or about *re-pointing the editor at Astrid* while Reigh's task/billing estate stays on Supabase (the v10 plan's own posture)? The dossier can support either, but the two designs differ by an order of magnitude.
2. **Worker fleet**: Do the GPU/API workers (and orchestrators) move onto Astrid (new task endpoints, executor adapter, upload path), stay on Supabase in a hybrid, or get retired? This decides whether §4's queue mapping is implementation or analysis.
3. **Billing**: What happens to credits/ledger/Stripe? (a) port a ledger into a new local wallet, (b) keep a remote payments service, (c) drop billing for local-first. The kernel forbids billing tables — a pack or external service is required either way.
4. **Tenancy**: Is one-user-per-projects-root acceptable, or must a single store serve multiple users (which re-introduces identity/RLS-like ownership)?
5. **`attempts` table**: Is the 84k-row slot-first media-attempt history in scope? Who is its live writer today (no callers in any checked-out repo)? Do we snapshot its DDL from prod first?
6. **Timeline history**: Replay `timeline_events` history as Astrid events, or collapse to the latest document (bridge load shape) and lose history? v10 precedent collapses chains.
7. **Sync**: Is cross-device timeline sync (`sync_bookmarks` spoke/hub, IndexedDB, divergence_log keep-both) required, or does single-writer local suffice?
8. **Media scope**: Export *all* `image_uploads`/`timeline-assets`/`render-outputs` bytes (measure first), or only referenced media (generations/tasks/shared links)? What happens to orphans and the unmeasured multi-GB tail?
9. **Public surfaces**: Share links (`shared_generations`, `get_shared_shot_data`), public presets/resources, anon reads, and referrals — keep (requires a server-side share path) or drop in local-first?
10. **Task log parity**: Does the app need historical task/generation/ledger read parity (`tasks-list`, `task-status`, ledger pages, gallery) after migration, or is a fresh-start acceptable for those surfaces?
11. **Realtime**: Is the 15–30 s polling fallback acceptable for tasks/progress, or must the bridge gain a push channel (SSE/websocket)?
12. **Live-drift remediation**: Before any migration, should we recover the 4 prod-only migrations + slot-system DDL into the repo (or at least snapshot them from `pg_proc`/`pg_get_viewdef`)? Without this, migration tooling has no trustworthy schema source.
13. **Credits/refunds**: With no automatic refund path and fractional-cent accounting, what is the desired ledger semantics at cutover (freeze balances? migrate history? recompute)?
14. **Route control plane**: The route/selector machinery (`route_backend_selectors`, `route_backend_capabilities`, claim-decision columns) is written at task creation but **ignored by live claims** — migrate it, drop it, or resolve the inconsistency first?
15. **Timeline agent sessions / AI surfaces**: `ai-timeline-agent` sessions, effects, and extension persistence — port locally, or keep as hosted edge functions?

---

## 11. Recommended Next Steps (for a migration DESIGN phase — not implementation)

### 11.1 Read order for the design team

1. **`09-astrid-bridge.md`** — the frozen contract; the only implemented transfer path; defines what exists vs what must be invented.
2. **`10-reigh-edge-functions.md` §2.1/§3** — task creation (the sole INSERT path) and payload contracts; every task shape a design must carry.
3. **`12-reigh-task-internals.md`** — live claim/lease/retry reality vs repo; the drift that invalidates repo-based reasoning.
4. **`11-astrid-v10-migration.md`** — the machinery pattern (receipt-keyed SDK replay) that a Reigh adapter would extend.
5. **`04-astrid-sqlite-schema.md` + `05-astrid-package-semantics.md`** — the target store's tables, invariants, and CLI/SDK surface.
6. **`06-reigh-app-data-usage.md` §8** — the full A–G contract a replacement backend must serve (the acceptance checklist).
7. **`07-live-db-schema.md`** — ground truth for every object; use it as the schema source, never `types.ts` or the migration chain alone.

### 11.2 Additional probes that would sharpen the design (all read-only)

- **Exact live row counts and volumes** (not `reltuples`): per-table counts, `image_uploads`/`timeline-assets`/`render-outputs` object counts + total bytes, storage bucket policies. (Doc 07 §5 has the psql recipe.)
- **Full live snapshots of untracked objects**: `attempts`/`shot_slots`/`slot_first_*` views, RPC bodies, triggers, RLS (from `pg_proc`/`pg_get_viewdef`/`pg_policies`) — plus confirm who writes `attempts` today (grep deployed branches for `slot_first_*` callers).
- **The 4 prod-only migrations' content** (from prod history or unpushed branches) to decide whether route gating returns.
- **Append-service contract** (the Python append service is not in this workspace): its exact SQL semantics for `config-replaced`/`app-bookmark`/`app-divergence`, to confirm the bridge fully subsumes it.
- **Worker claim-response fields**: whether the deployed `claim-next-task` edge forwards `attempts` and route fields (docs 03/12 disagree with repo code); needed for queue re-pointing design.
- **Realtime subscription inventory**: exact publication membership vs client channels, to scope a push replacement.
- **A dry-run of `scripts/migrations/v10/migrate_all.py --dry-run`** against a scratch root to observe the fence/zero-child split mechanics firsthand (read-only; does not apply).

### 11.3 Design-phase deliverables (proposed)

1. **Decision record** answering §10 (numbered), starting with Q1 (goal) and Q2 (worker fleet) — everything else branches from them.
2. **Live-schema freeze**: snapshot all 51 tables + 202 functions + RLS + untracked slot objects into a migration-source artifact (the repo's `07` doc is the seed).
3. **Source-adapter spec**: Postgres → inventory-JSON export + new `migrate_*` phases reusing the v10 SDK-replay machinery with `v10-migrate-reigh:` receipt keys (doc 11 §7 sketch).
4. **Entity mapping sign-off**: the §3 table, refined per design decisions (which GAPs become DESIGN-NEEDED implementations vs explicit drops).
5. **Bridge extension proposal**: frozen routes for tasks/credits/generations (or a documented decision to keep them off the bridge and hybrid on Supabase).
6. **Queue mapping spec**: §4's table expanded into a state-machine equivalence + eligibility/priority/fencing design for Astrid-side claiming.
7. **Billing replacement design**: ledger/wallet/Stripe decision with idempotency and fractional-cent semantics.
8. **Media export/import plan**: bucket export tooling, SHA-256 import, dedupe, orphan policy, and storage cost/bandwidth estimates (measure first).
9. **Cutover runbook**: order of operations (backup live DB → stop workers → freeze → export → import → verify → bridge cutover → teardown), borrowing v10's guards (zero-row refuse, `.bak`, exclusive lock, verify).
10. **Rollback posture**: Reigh stays fully functional on Supabase until the bridge+data cutover is verified — the hybrid interim is the natural rollback path.
