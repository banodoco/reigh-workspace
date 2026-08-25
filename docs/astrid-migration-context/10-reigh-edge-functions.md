# 10 — Reigh Supabase Edge Functions: Complete Reference

**Summary.** Reigh's entire server-side surface is 41 Supabase Edge Functions under `reigh-app/supabase/functions/` (plus `_shared/` helpers and `_tests/`). Every function authenticates internally via `_shared/auth.ts:authenticateRequest` (service-role key string match → Supabase user JWT via `auth.getUser` when `allowJwtUserAuth` is set → Personal Access Token lookup in `user_api_tokens`), and executes **all** DB access through an admin/service-role client (`supabaseAdmin`), bypassing RLS. The single task-creation entry point is `create-task`, which dispatches to per-family *resolvers* that build `TaskInsertObject` rows and INSERT into `tasks` with idempotency-key dedup; claims happen through `claim-next-task` → RPC `claim_next_task_service_role` / `claim_next_task_user_pat` (atomic `UPDATE … FROM`); completion through `complete_task` (uploads + generation row creation + billing trigger); billing through `calculate-task-cost` (credits_ledger `spend` rows, amount in **cents**). Credits are *not* checked at task creation — they gate **claiming** (RPC filters `users.credits > 0` and capacity `< 5` in-progress). Task rows carry a `route_contract` in `params` that a BEFORE INSERT trigger (`tasks_assert_claimable`) enforces, and the edge stamps it via RPC `derive_route_key`.

**Key facts**
- 41 deployable functions (see §2); `supabase/functions/` at repo top-level is an **empty leftover** (only `.`/`..` — verified by listing).
- All functions run Deno, import `serve` from `deno.land/std@0.224.0`, supabase-js `2.49.4` via esm.sh.
- Auth model: `user_api_tokens` stores **plaintext** 32-char PATs (`generate-pat` creates them; `authenticateRequest` compares tokens by equality).
- `config.toml` sets `verify_jwt = false` for 26 functions (platform gateway skips JWT enforcement; functions self-authenticate). The other 15 use the platform default `verify_jwt = true` (gateway requires a signed JWT; service-role keys pass because they are JWTs, raw PATs would not).
- Task statuses are an enum: `Queued | In Progress | Complete | Failed | Cancelled` (valid transitions in `update-task-status/transitions.ts`).
- `tasks` row minimal write at creation: `project_id, task_type, params, status='Queued', created_at, dependant_on` (+ `id` when worker pre-generates a UUID; + `idempotency_key`, + `materialized_inputs`, + route-contract columns after stamping).
- Credits: `users.credits` (integer, cents) is a materialized column maintained by `refresh_user_balance()` triggers on `credits_ledger`; ledger `amount` is integer cents; types enum: `stripe, manual, spend, refund, auto_topup`.
- 6 pg_cron jobs invoke 2 edge functions (`route-contract-sentinel` every minute; `discord-daily-stats` daily 09:00 UTC); the rest are pure DB functions (§7).
- Rate limiting: RPC `check_rate_limit(p_key, p_window_seconds, p_max_requests)` sliding-window counter, fail-open on RPC error; configs in `_shared/rateLimit.ts` (`webhook 100/min`, `userAction 60/min`, `expensive 30/min`, `taskCreation 120/min`, `read 120/min`).
- Logging: `SystemLogger` buffers and flushes to `system_logs` via RPC `func_insert_logs_batch` (`source_type='edge_function'`).
- Every claim/completion/cost operation is **not** wrapped in a DB transaction from the edge; atomicity comes from SQL functions (single `UPDATE … RETURNING` in claim, unique partial indexes in stripe webhook, idempotency-key unique constraint on `tasks`).

---

## 1. Function inventory (41) — quick classification

| Cluster | Functions |
|---|---|
| Task creation | `create-task` (+ 13 resolvers) |
| Task lifecycle (worker-facing) | `claim-next-task`, `complete_task`, `update-task-status`, `calculate-task-cost`, `update-worker-model` |
| Task reads (worker-facing) | `get-task-status`, `get-task-output`, `get-predecessor-output`, `get-orchestrator-children`, `get-completed-segments`, `task-status` (GET), `tasks-list`, `task-counts` |
| AI/LLM proxy (no task writes) | `ai-prompt`, `ai-voice-prompt`, `ai-generate-effect`, `ai-generate-sequence`, `ai-generate-sequence-component`, `ai-timeline-agent` (agent with tool calls) |
| Media processing | `generate-thumbnail`, `apply-image-transform`, `trim-video`, `huggingface-upload`, `generate-upload-url` |
| Billing | `stripe-checkout`, `stripe-webhook`, `grant-credits`, `setup-auto-topup`, `complete-auto-topup-setup`, `process-auto-topup`, `trigger-auto-topup` |
| Auth/token | `generate-pat`, `revoke-pat` |
| Data read (frontend) | `reigh-data-fetch`, `update-shot-pair-prompts`, `timeline-import`, `delete-project`, `broadcast-realtime` |
| Cron/internal | `route-contract-sentinel`, `discord-daily-stats` |

Total: **41 functions**, 45 directories under `functions/` including `_shared` and `_tests`.

---

## 2. Per-function reference

Auth column legend: **SR** = service-role key accepted; **JWT** = user Supabase JWT accepted (`allowJwtUserAuth: true`); **PAT** = Personal Access Token accepted. "Admin client" means the function uses the service-role key for all DB calls regardless of caller identity.

### 2.1 Task creation

| Function | Method | Purpose | Auth | Tables touched |
|---|---|---|---|---|
| `create-task` (`index.ts`) | POST | Unified task creation; validates project ownership, rate-limits, dispatches to family resolver, stamps route contract, INSERTs into `tasks` with idempotency dedup. Response `{task_id, status:"Task queued", meta?, deduplicated?}` or `{task_ids:[…]}` for batches. | SR (bypasses ownership), JWT, PAT (`JWT_AUTH_REQUIRED`) | R: `projects` (user_id, aspect_ratio), `task_types` (name, is_active — passthrough fallback), RPC `derive_route_key`; W: `tasks`; rate-limit RPC `check_rate_limit` |
| `claim-next-task` (`claim-next-task/index.ts`) | POST | Worker polls for work. Body: `worker_id?`, `run_type? ('gpu'\|'api'\|'banodoco-worker')`, `worker_pool? ('banodoco')`, `task_types?[]`, `same_model_only?`, `max_task_wait_minutes? (default 5)`, `debug?`. 200 = task JSON `{task_id, params, task_type, project_id}`; 204 = none. | SR → global claim; PAT → own-user claim; JWT not accepted here (`allowJwtUserAuth` not set) | RPC: `claim_next_task_service_role` (7 args) / `claim_next_task_user_pat`; debug RPC `analyze_task_availability_*` |
| `complete_task` (`complete_task/`) | POST | Worker completes a task: uploads file (base64 or storage-path reference), validates storage path security, creates `generations`/`generation_variants` row(s), marks task `Complete`, checks orchestrator completion, triggers cost calculation, timeline placement. Body: `{task_id, file_data+filename (base64) | storage_path, first_frame_data?, thumbnail_storage_path?, output_location?}`. | SR, JWT, PAT (`allowJwtUserAuth: true`, `ensureTaskActor`) | R: `tasks`, `tasks.task_types` join, `generations` (existing + predecessor + source), storage bucket `image_uploads`; W: `tasks` (status Complete, output_location, generation_processed_at, params thumbnail, result_data, generation_created), `generations`, `generation_variants`, `shot_generations` (via RPC `add_generation_to_shot`), RPCs `upsert_asset_registry_entry`, `insert_shot_at_position`, `duplicate_as_new_generation`, `update_timeline_config_versioned` (via ai-timeline-agent db helpers); triggers `calculate-task-cost` via internal HTTP fetch |
| `update-task-status` (`update-task-status/`) | POST | Worker/user status transitions with validation. Body: `{task_id, status, output_location?, attempts?, error_details?, clear_worker?, reset_generation_started_at?, result_data?}`. On Failed/Cancelled cascades via RPC `cascade_task_failure`; on Cancelled orchestrator runs cancellation billing. 409 on invalid transition. | SR, JWT, PAT (`allowJwtUserAuth: true`) | R: `tasks`, `projects`; W: `tasks`; RPC `cascade_task_failure`; triggers `calculate-task-cost` |
| `calculate-task-cost` (`calculate-task-cost/`) | POST | Computes task cost from duration and `task_types` billing config, inserts `credits_ledger` `spend` row (negative amount in cents). Skips sub-tasks (parent billed); orchestrators billed from summed sub-task durations; idempotent (skips if a `spend` row for task exists). Body `{task_id}`. | SR, PAT (JWT not enabled) | R: `tasks` (+ `projects(user_id)`, `task_types` FK), `credits_ledger` (existing spend), `users`; W: `credits_ledger` |
| `update-worker-model` (`update-worker-model/`) | POST | Worker heartbeat/model registry: upsert `workers` row (`current_model, last_heartbeat, status='active'`; insert with `instance_type` default `'external'`). Body `{worker_id, current_model, instance_type?}`. | SR, PAT (JWT not enabled; gateway may require JWT — see §2.7) | R/W: `workers` |

### 2.2 Task reads

| Function | Method | Purpose | Auth | Tables |
|---|---|---|---|---|
| `get-task-status` (`get-task-status/`) | POST | Legacy status read. Body `{task_id}` → `{status}`. | SR, PAT | R: `tasks` |
| `task-status` (`task-status/`) | GET | Banodoco-poller-facing read. `?task_id=<uuid>` → `{status, correlation_id?, message?, failure_code?, result?}` (reads `result_data` well-known fields). | SR, JWT | R: `tasks` |
| `get-task-output` (`get-task-output/`) | POST | Worker dependency output read. Body `{task_id}` → `{status, output_location, params, dependant_on}`. | SR, PAT | R: `tasks` |
| `get-predecessor-output` (`get-predecessor-output/`) | POST | Dependency outputs for orchestrator children: `dependant_on` array path + generation-sibling fallback (`parent_generation_id`+`child_order`). → `{predecessors:[{predecessor_id, output_location, status}], all_complete}`. | SR, PAT | R: `tasks`, `generations` |
| `get-orchestrator-children` (`get-orchestrator-children/`) | POST | Child tasks of an orchestrator (canonical `params.orchestration_contract.orchestrator_task_id` + legacy paths). Body `{orchestrator_task_id}` → `{tasks:[{id,task_type,status,params,output_location}]}`. | SR, PAT (JWT not enabled) | R: `tasks` |
| `get-completed-segments` (`get-completed-segments/`) | POST | Completed `travel_segment` tasks by run_id. Body `{run_id, project_id?}` → `[{segment_index, output_location}]`. | SR, PAT | R: `tasks` |
| `tasks-list` (`tasks-list/`) | POST | Project's tasks, newest first. Body `{projectId, status?[]}` → full rows. | SR, JWT, PAT | R: `tasks`, `projects` (ownership) |
| `task-counts` (`task-counts/`) | POST | Scaling/monitoring counts. Body `{run_type?, debug?}`. SR path: `totals{queued_only, active_only, queued_plus_active, blocked_by_capacity, blocked_by_deps, blocked_by_settings, potentially_claimable}`, `queued_tasks[]`, `active_tasks[]`, `users[]`. PAT path: per-user `totals`, `user_info`, `debug_summary`. | SR, PAT | R: RPCs `count_eligible_tasks_service_role`, `count_queued_tasks_breakdown_service_role`, `per_user_capacity_stats_service_role`, `count_eligible_tasks_user_pat`, `analyze_task_availability_user_pat`; `tasks`, `task_types`, `projects`, `users` |

### 2.3 AI / LLM proxy (no task writes)

All six call external LLMs with the caller's auth; none touch `tasks` (ai-timeline-agent creates tasks *indirectly* by calling `create-task` over HTTP).

| Function | Method | Provider/model | Purpose | Auth | Tables |
|---|---|---|---|---|---|
| `ai-prompt` | POST | Fireworks `kimi-k2p5` + OpenAI `gpt-5-mini` | `generate_prompts`, `edit_prompt`, `generate_summary`, `enhance_segment_prompt` (single/batch) | SR (skips rate limit), JWT, PAT | rate-limit RPC only |
| `ai-voice-prompt` | POST | Groq `whisper-large-v3-turbo` + `openai/gpt-oss-20b` | Transcribe audio (multipart) or text instructions → clean prompt | SR, JWT, PAT | none |
| `ai-generate-effect` | POST | Anthropic `claude-opus-4-6` (streamed) | Generate/edit code effects (entrance/exit/continuous) with `// FIELD:` envelope parsing + self-invoke retry | JWT (+SR), rate-limited | none |
| `ai-generate-sequence` | POST | Anthropic `claude-opus-4-6` | Generate/repair timeline sequence drafts (JSON `{drafts:[{clipType,hold,params}]}`); classifier preamble → `path:"code"` redirect | JWT (+SR), rate-limited | none |
| `ai-generate-sequence-component` | POST | Anthropic `claude-opus-4-6` | Generate custom sequence component code + manifest | JWT (+SR), rate-limited | none |
| `ai-timeline-agent` | POST | Session agent loop (tiered: Groq `openai/gpt-oss-20b` triage, Fireworks `kimi-k2p5` easy/okay, Anthropic `claude-opus-4-6` hard; loop limit 8, 50s soft timeout); tools call `create-task`/timeline RPCs | Conversational timeline editor: `{session_id, user_message?, selected_clips?, proposal_policy?}`; persists `timeline_agent_sessions.turns`; enforces session ownership + cancelled state | JWT (user JWT only — PAT can't drive Banodoco handoff), SR | R/W: `timeline_agent_sessions`, `timelines`, `shots`, `projects`, `resources`, `generations`, `shot_generations`, `tasks`; RPCs `insert_shot_at_position`, `duplicate_as_new_generation`, `upsert_asset_registry_entry`, `ensure_shot_parent_generation`, `update_timeline_config_versioned`; HTTP → `create-task`, `ai-prompt`, `enqueue-task` (external orchestrator) |

### 2.4 Media processing

| Function | Method | Purpose | Auth | Tables / Storage |
|---|---|---|---|---|
| `generate-thumbnail` | POST | Fetch main image → 1/3-size JPEG thumb → upload to `image_uploads` bucket → `generations.thumbnail_url`. Fallback: main URL. Body `{generation_id, main_image_url, user_id}`. | SR only (`requireServiceRole`) | W: `generations`; storage `image_uploads` |
| `apply-image-transform` | POST | Canvas transform (translate/scale/rotate/flip) of a generation image → upload PNG+thumb → either new `generations`+`generation_variants` (create_as_generation) or new variant `variant_type='repositioned'`. Body `{generation_id, user_id, transform, source_image_url?, source_variant_id?, create_as_generation?, make_primary?, variant_name?, tool_type?}`. | SR only | R: `generations`, `generation_variants`; W: `generations`, `generation_variants`; storage `image_uploads` |
| `trim-video` | POST | Replicate `lucataco/trim-video` trim → download → upload MP4 → optionally update `generation_variants` (`location`, `params.duration_seconds`). Body `{video_url, start_time, end_time, project_id, user_id, generation_id?, variant_id?, test_mode?}`. | SR, JWT, PAT | R: `projects`, `generation_variants`; W: `generation_variants`; storage `image_uploads` |
| `huggingface-upload` | POST | Upload LoRA files + sample videos + README to a HuggingFace repo from storage `temporary` bucket; cleans up temp assets. Multipart form: `loraStoragePaths` (JSON), `loraDetails` (JSON), `sampleVideos` (JSON), `repoNameOverride?`, `isPrivate?`. | JWT, SR, PAT (`allowJwtUserAuth`) | R: RPC `get_external_api_key_decrypted(user, 'huggingface')`; storage `temporary` (download/remove); external HF API |
| `generate-upload-url` | POST | Signed upload URL for a task output (MODE 3 completion). Body `{task_id, filename, content_type, generate_thumbnail_url?}` → `{upload_url, storage_path, token, expires_at, thumbnail_*?}`. Path `{userId}/tasks/{taskId}/{filename}` in `image_uploads`. | SR, PAT (JWT not enabled) | R: `tasks` (actor resolution); storage `image_uploads` `createSignedUploadUrl` |

### 2.5 Billing

| Function | Method | Purpose | Auth | Tables |
|---|---|---|---|---|
| `stripe-checkout` | POST | Create Stripe Checkout session (one-time payment for credits, optional auto-topup config in metadata). Body `{amount (USD 5–100), autoTopupEnabled?, autoTopupAmount?, autoTopupThreshold?}` → `{checkoutUrl, sessionId, amount, userId}`. | JWT, SR, PAT | R: `users` (email); external Stripe |
| `stripe-webhook` | POST | Verify Stripe signature (HMAC-SHA256) or service-role Bearer. Events: `checkout.session.completed` → `credits_ledger` insert `{type:'stripe', amount: cents, metadata.stripe_session_id}` (idempotency via unique partial index on `metadata->>'stripe_session_id'`); `payment_intent.succeeded` (autoTopup) → `credits_ledger {type:'auto_topup', metadata.stripe_payment_intent_id}`; `payment_intent.payment_failed` → disable `users.auto_topup_enabled` on card_declined/expired_card; also completes auto-topup setup (users: `auto_topup_enabled, auto_topup_setup_completed, auto_topup_amount, auto_topup_threshold, stripe_customer_id, stripe_payment_method_id`). | **None required** (Stripe signature or SR Bearer; `auth.required:false`) | R: `credits_ledger`; W: `credits_ledger`, `users`; external Stripe |
| `grant-credits` | POST | Admin grant or welcome bonus. Body `{userId, amount, description?, isWelcomeBonus?}`. Welcome bonus = $5, atomic claim via `users.given_credits` flip; inserts `credits_ledger {type:'manual', amount: cents}`; rollback claim on ledger failure. Admin grants require service role. | JWT (welcome bonus), SR (admin) | R/W: `users` (upsert with `{id,name:'',email:'',credits:0,given_credits:false}`), W: `credits_ledger` |
| `setup-auto-topup` | POST | Persist auto-topup prefs. Body `{autoTopupEnabled, autoTopupAmount, autoTopupThreshold}` → `users.auto_topup_enabled/amount/threshold` (cents); disable clears amounts, keeps Stripe ids. | JWT, SR, PAT | W: `users` |
| `complete-auto-topup-setup` | POST | Post-checkout: retrieve session+payment intent, persist `stripe_customer_id, stripe_payment_method_id, auto_topup_setup_completed` (+ amounts when enabled). Body `{sessionId, expectedUserId?}`. | SR only | W: `users`; external Stripe |
| `process-auto-topup` | POST | Charge saved payment method off-session. Body `{userId}`. Eligibility: enabled + payment ids + balance ≤ threshold; atomic rate-limit claim via `users.auto_topup_last_triggered` (null or >1h old); on success insert `credits_ledger {type:'auto_topup'}`; disables on card errors. | SR only | R/W: `users`; W: `credits_ledger`; external Stripe |
| `trigger-auto-topup` | POST | Sweep: finds eligible users (enabled, setup complete, balance ≤ threshold), rate-limits per user, then HTTP-calls `process-auto-topup` per user. Body `{userId?}` → `{summary, results[]}`. | SR only | R: `users`; HTTP → `process-auto-topup` |

### 2.6 Auth / tokens / data

| Function | Method | Purpose | Auth | Tables |
|---|---|---|---|---|
| `generate-pat` | POST | Create 32-char alphanumeric PAT. Body `{label?}` → `{token}` (shown once). Rate limit 10/min. | JWT, SR, PAT | W: `user_api_tokens` (`user_id, token, label`) |
| `revoke-pat` | POST | Delete PAT by id (scoped to user). Body `{tokenId}` → `{success:true}`. | JWT, SR, PAT | W: `user_api_tokens` |
| `reigh-data-fetch` | POST | Frontend project hydration: `{project_id, shot_id?, task_id?, timeline_id?}` → projects, shots, shot_generations (+joined generations), generations (is_child=false, limit 100), tasks, timelines. `tasks` select includes `result_data, dependant_on, error_message, attempts, generation_created, generation_started_at, generation_processed_at, worker_id`. | SR, JWT, PAT | R: `projects`, `shots`, `shot_generations`, `generations`, `generation_variants` (primary_variant join), `tasks`, `timelines` |
| `update-shot-pair-prompts` | POST | Write `shot_generations.metadata.enhanced_prompt` per positioned timeline image (N-1 prompts). Body `{shot_id, task_id?, enhanced_prompts[]}`. | SR, JWT, PAT | R: `shot_generations`, `generations`; W: `shot_generations` |
| `timeline-import` | POST | Import Banodoco timeline + asset registry. Body `{project_id, timeline_id, timeline, asset_registry?, create_if_missing?, expected_version?}`. Rejects service-role (user JWT required); ownership via `projects.user_id`; versioned writes via external Reigh append service (`REIGH_APPEND_SERVICE_URL` + internal token) or `update_timeline_*` RPCs. | JWT only (service-role explicitly rejected) | R: `timelines`; W: `timelines` (via append service) |
| `delete-project` | POST | Project deletion. Body `{projectId}` → RPC `delete_project_with_extended_timeout`. Rate limit 10/min. | JWT, SR, PAT | RPC `delete_project_with_extended_timeout` |
| `broadcast-realtime` | POST | Realtime broadcast. Body `{channel, event, payload}`. | SR only (`requireServiceRole`) | Realtime (no tables) |

### 2.7 Cron/internal

| Function | Method | Purpose | Auth | Tables |
|---|---|---|---|---|
| `route-contract-sentinel` | POST | One-minute tick: loads queued tasks + workers, probes `route_backend_claim_decision` per task/backend, classifies `OK|NO_WORK|UNCLAIMABLE_WORK|NO_READY_WORKERS|WORKERS_STUCK_INITIALIZING`, inserts `sentinel_ticks` row, pages `SENTINEL_WEBHOOK_URL` after 5 consecutive alarm ticks and upserts `pause_scaling`. | SR only | R: `tasks`, `workers`; W: `sentinel_ticks`, `pause_scaling`; RPC `route_backend_claim_decision` |
| `discord-daily-stats` | POST | Daily stats → Discord webhook embed + QuickChart image. Uses RPC `func_daily_task_stats` with direct `tasks` fallback (paginated, since 2026-02-08). | SR only | R: RPC `func_daily_task_stats`; fallback `tasks` (created_at, task_type, status='Complete') |

**Deployment config note.** `reigh-app/supabase/config.toml` declares `verify_jwt = false` for: `ai-prompt, broadcast-realtime, calculate-task-cost, claim-next-task, complete_task, complete-auto-topup-setup, create-task, discord-daily-stats, generate-pat, generate-thumbnail, generate-upload-url, get-completed-segments, get-predecessor-output, grant-credits, process-auto-topup, revoke-pat, setup-auto-topup, stripe-checkout, stripe-webhook, task-counts, tasks-list, trigger-auto-topup, update-shot-pair-prompts, get-task-status, get-task-output, reigh-data-fetch, update-task-status`. The other 15 (`ai-generate-effect, ai-generate-sequence, ai-generate-sequence-component, ai-timeline-agent, ai-voice-prompt, apply-image-transform, delete-project, get-orchestrator-children, huggingface-upload, route-contract-sentinel, task-status, timeline-import, trim-video, update-worker-model`) are absent from config.toml → platform default `verify_jwt = true` (gateway requires a signed project JWT; service-role keys pass as JWTs; raw PATs would be rejected at the gateway unless the deployed config differs — see Gaps). There is no Railway deployment for the edge functions themselves; they deploy via Supabase. `reigh-worker-orchestrator/railway.json` deploys the orchestrator (FastAPI), not the functions.

---

## 3. Task creation flow — exact structure (MOST IMPORTANT)

### 3.1 The single INSERT path

All task rows are created through **`create-task`** (`functions/create-task/index.ts`) — the only edge function that INSERTs into `tasks` (plus, indirectly, worker child tasks via `create-task`'s passthrough resolver; the ai-timeline-agent's `create_generation_task` tool also POSTs to `create-task` over HTTP with the service-role key rather than inserting directly).

Flow (from `create-task/index.ts:serve`):
1. `bootstrapEdgeHandler` (POST, `JWT_AUTH_REQUIRED`, strict JSON body).
2. Parse body: `family` (required), `project_id` (required), `input` (required object), optional `idempotency_key`, optional `materialized_inputs` (`[{generation_id, kind:'file'|'remote', target}]`).
3. Rate limit (non-service-role): `RATE_LIMITS.taskCreation` = 120/min.
4. Ownership: service-role bypasses; otherwise `projects.user_id` must equal caller (`auth.userId` from JWT or PAT). Also reads `projects.aspect_ratio`.
5. Resolver lookup: `registry.ts` map (13 families) → else `task_types` active-row lookup → `createWorkerPassthroughResolver(family)` (worker-created child tasks, e.g. `join_clips_segment`, category `processing`).
6. Resolver returns `{ tasks: TaskInsertObject[], meta? }`; each task is passed through `stampTaskRouteContract` (`routeContract.ts`) which calls RPC `derive_route_key(p_task_type, p_params)` and writes the contract both as top-level columns and `params.route_contract`. Orchestrator-parent types (`*_orchestrator`) are exempt from the claimability requirement (stamp only when derive returns a key).
7. Per task: idempotency key resolution — batch >1 with a request key → `sha256(baseKey:index)`; then `INSERT INTO tasks` with `.select('id').single()`. On `23505` with `idempotency_key` in message → fetch existing by `idempotency_key`, verify `project_id` matches (non-SR), return existing id as `deduplicated: true`.
8. Response: single → `{task_id, status:"Task queued", meta?, deduplicated?}`; batch → `{task_ids:[…], status:"Task queued", meta?}`.

### 3.2 The exact column set written

`TaskInsertObject` (`create-task/resolvers/types.ts`) — all optional except `params`, `project_id`, `task_type`:

```ts
interface TaskInsertObject {
  attempts?: number;               // never set at creation (defaults NULL)
  copied_from_share?: string | null;
  created_at?: string;             // resolvers set new Date().toISOString()
  dependant_on?: string[] | null;  // null for frontend tasks; worker passthrough lifts input.dependant_on
  error_message?: string | null;
  generation_created?: boolean;
  generation_processed_at?: string | null;
  generation_started_at?: string | null;
  id?: string;                     // worker passthrough honors input.task_id (pre-generated UUID)
  idempotency_key?: string | null;
  materialized_inputs?: MaterializedInputRecord[] | null;  // from body
  output_location?: string | null;
  params: Record<string, unknown>; // REQUIRED — full payload JSON (§3.3)
  project_id: string;              // REQUIRED
  result_data?: Record<string, unknown> | null;
  status?: TaskStatus;             // resolvers set "Queued"
  task_type: string;               // REQUIRED
  updated_at?: string | null;
  worker_id?: string | null;
  // Route-contract columns (stamped by stampTaskRouteContract):
  route_key?: string | null;
  selector_namespace?: string | null;   // default 'production'
  selected_backend?: string | null;
  selector_version?: string | null;
  route_selection_snapshot?: Record<string, unknown> | null;
  support_state?: string | null;
  selected_profile?: string | null;
  selected_template_id?: string | null;
  route_run_id?: string | null;
  worker_contract_version?: string | null;
}
```

DB defaults (base schema `20250100000000_create_base_schema.sql` + later migrations): `id` = `gen_random_uuid()`, `status` default `'Queued'`, `created_at` = `now()`, `params` NOT NULL. `dependant_on` was migrated from `uuid` (single FK) to `uuid[]` (`20260121000000_support_multiple_dependencies.sql`). The `tasks_assert_claimable` BEFORE INSERT trigger (`20260513120200_tasks_claimable_trigger.sql`) requires `params.route_contract` present and probes `route_backend_claim_decision` for `selected_backend` (or both `wgp`/`vibecomfy` when NULL) — this is why the edge always stamps the route contract before inserting.

`route_contract` JSON (from `stampTaskRouteContract` / `selectedRoute.ts`):
```json
{
  "route_key": "<derive_route_key result>",
  "selector_namespace": "production",
  "selected_backend": null | "wgp" | "vibecomfy",
  "selector_version": null,
  "route_selection_snapshot": null | {},
  "support_state": null,
  "selected_profile": null,
  "selected_template_id": null,
  "route_run_id": null,
  "worker_contract_version": null,
  "derived_at": "ISO8601",
  "derived_by": "edge_function",
  "derive_route_key_version": 1
}
```
The same fields are written as top-level task columns; `params.route_contract` is the embedded copy.

### 3.3 Payload JSON per task type (concrete examples)

Resolver registry (`create-task/resolvers/registry.ts`) — 13 families:

| family | task_type written | tasks per request | Notes |
|---|---|---|---|
| `image_generation` | `wan_2_2_t2i` \| `qwen_image` \| `qwen_image_style` \| `qwen_image_2512` \| `z_image_turbo` | `prompts.length × imagesPerPrompt` (≤16 each) | model_name switch |
| `image_upscale` | `image-upscale` | 1 | task_type uses a hyphen (`image-upscale`) |
| `individual_travel_segment` | `individual_travel_segment` | 1 | worker passthrough if `orchestrator_task_id_ref` |
| `join_clips` | `join_clips_orchestrator` | 1 | orchestrator; per-join overrides |
| `video_enhance` | `video_enhance` | 1 | |
| `z_image_turbo_i2i` | `z_image_turbo_i2i` | `numImages` (1–N) | |
| `magic_edit` | `qwen_image_edit` | `numImages` (1–16) | |
| `masked_edit` | `image_inpaint` | 1 | |
| `travel_between_images` | `travel_between_images` | 1 | orchestrator |
| `crossfade_join` | `travel_stitch` | 1 | worker passthrough if `orchestrator_task_id_ref` |
| `edit_video_orchestrator` | `edit_video_orchestrator` | 1 | |
| `character_animate` | `animate_character` | 1 | |
| `klein_edit` | `flux_klein_edit` | `numImages` (1–4) | |
| (none — passthrough) | any active `task_types.name` | 1 | worker child tasks: input dumped into `params` as-is |

**Common envelope for orchestrator families** (`taskContracts.ts` — `composeTaskFamilyPayload`): every travel/join task's `params` contains:
```json
{
  "contract_version": 1,
  "task_family": "<family>",
  "orchestrator_details": { "orchestrator_task_id": "...", "run_id": "...", "generation_source": "...", "parsed_resolution_wh": "...", "model_name": "...", "input_image_paths_resolved": [...], ... },
  "orchestration_contract": { "contract_version": 3, "task_family": "...", "orchestrator_task_id": "...", "run_id": "...", "parent_generation_id": "...", "child_generation_id": "...", "child_order": 0, "shot_id": "..." },
  "task_view_contract": { "contract_version": 1, "input_images": [...], "prompt": "...", "model_name": "...", "resolution": "..." },
  "family_contract": { "contract_version": 1, "...": "family-specific" }
}
```

**Example A — `image_generation` (video-type base `wan_2_2_t2i`; params from `imageGeneration.ts:buildTaskParams`):**
```json
{
  "task_id": "wan_2_2_t2i_2608211012_a1b2c3",
  "model": "optimised-t2i",
  "prompt": "a woman walking through a forest at sunset",
  "resolution": "832x480",
  "seed": 123456789,
  "steps": 12,
  "add_in_position": false,
  "negative_prompt": "blurry",
  "additional_loras": { "https://.../in_scene_different_object.safetensors": 0.5 },
  "style_reference_image": "https://...", "subject_reference_image": "https://...",
  "style_reference_strength": 1.1,
  "shot_id": "<uuid>",
  "timeline_placement": { "timeline_id": "<uuid>", "source_clip_id": "...", "target_track": "...", "insertion_time": 3.5, "intent": "after_source" }
}
```
Row: `task_type='wan_2_2_t2i'`, `status='Queued'`, `created_at=now`, `dependant_on=null`. Lineage fields via `setTaskLineageFields` (`shared/lineage.ts`) add `shot_id`, `based_on`, `source_variant_id`, `create_as_generation`, `tool_type`, `timeline_placement`, `placement_intent`.

**Example B — `character_animate` → `animate_character` (`characterAnimate.ts`):**
```json
{
  "orchestrator_task_id": "character_animate_2608211012_a1b2c3",
  "run_id": "20260821101200000",
  "character_image_url": "https://.../char.png",
  "motion_video_url": "https://.../motion.mp4",
  "prompt": "natural expression; preserve outfit details",
  "mode": "animate",
  "resolution": "480p",
  "seed": 111111
}
```
Row: `task_type='animate_character'`, status Queued. Defaults: mode `animate`, resolution `480p`, prompt default, seed 111111, `random_seed: true`.

**Example C — `individual_travel_segment` (frontend-created; `individualTravelSegment.ts`):** one row `task_type='individual_travel_segment'` with a large flat params object (~40 keys) plus `orchestrator_details` and `individual_segment_params` mirrors. Key top-level params: `model_name` (default `wan_2_2_i2v_lightning_baseline_2_2_2`), `project_id`, `shot_id`, `base_prompt`, `fps_helpers: 16`, `seed_to_use`, `segment_index`, `guidance_scale: 1`, `guidance2_scale: 1`, `guidance_phases: 2`, `is_last_segment`, `num_inference_steps` (default 6), `parsed_resolution_wh`, `num_frames` (min(input,81), default 49), `amount_of_motion: 0.5`, `parent_generation_id` (via RPC `ensure_shot_parent_generation` when only shot_id given), `child_generation_id?`, `input_image_paths_resolved: [start, end?]`, `make_primary_variant: true`, `orchestrator_details` (includes `generation_source:'individual_segment'`, `seed_base`, `flow_shift:5`, `sample_solver:'euler'`, `guidance_phases`, `num_inference_steps`, `model_switch_phase:1`, `additional_loras`, `fps_helpers:16`, `independent_segments:true`, optional `segment_frames_expanded`/`frame_overlap_expanded`/`stitched_start_frame`/`guidance_start_frame` from sibling-task layout query), `individual_segment_params` (mirror subset + `random_seed`, `advanced_mode`), plus the four contract blocks.

**Example D — `join_clips` → `join_clips_orchestrator` (`joinClips.ts`):** one row; `orchestrator_details` includes `orchestrator_task_id`, `clip_list` (`[{url, name?}]`), `run_id`, `shot_id`, `prompt`, `gap_frame_count: 23`, `context_frame_count: 15`, `replace_mode: true`, `enhance_prompt: false`, `model: 'wan_2_2_vace_lightning_baseline_2_2_2'`, `num_inference_steps: 6`, `guidance_scale: 3.0`, `seed: -1`, `priority: 0`, `motion_mode: 'basic'`, `selected_phase_preset_id: '__builtin_vace_default__'`, `phase_config` (3-phase default with HF LoRA URLs + multipliers), optional `per_join_settings[]`, `audio_url`, `video_edit_mode` (+ `source_video_*`, `portions_to_regenerate`), `additional_loras`; plus the four contract blocks (`family_contract.mode` = `multi_clip_join`|`video_edit_join`).

**Example E — `travel_between_images` (`travelBetweenImages.ts`):** one `travel_between_images` row; `orchestrator_details` carries `generation_source:'batch'`, `orchestrator_task_id`, `run_id`, `input_image_paths_resolved`, `num_new_segments_to_generate` (N-1), expanded arrays `base_prompts_expanded`, `negative_prompts_expanded`, `segment_frames_expanded`, `frame_overlap_expanded`, optional `phase_configs_expanded`/`loras_per_segment_expanded`/`motion_settings_expanded`, `parsed_resolution_wh`, `model_name`, `seed_base`, `steps: 20`, `after_first_post_generation_saturation: 1`, `after_first_post_generation_brightness: 0`, `debug_mode_enabled: false`, `enhance_prompt: false`, `show_input_images: true`, `generation_mode: 'batch'`, `dimension_source: 'project'`, `amount_of_motion: 0.5`, `advanced_mode: false`, `independent_segments: true`, `parent_generation_id?`; plus contracts (family_contract has `image_count`, `segment_count`, `has_pair_ids`, `read_contract`).

**Example F — `magic_edit` → `qwen_image_edit` (`magicEdit.ts`):** per-image rows (numImages): `{seed, image, prompt, output_format:'jpeg', qwen_edit_model:'qwen-edit', enable_sync_mode:false, max_wait_seconds:300, enable_base64_output:false, negative_prompt?, in_scene?, resolution, add_in_position:false, loras?}` + lineage (`shot_id`, `based_on`, `source_variant_id`, `create_as_generation`, `tool_type`, `timeline_placement`, `placement_intent`) + optional `hires_fix` params.

**Example G — `video_enhance` (`videoEnhance.ts`):** one row: `{tool_type:'video-enhance', video_url, enable_interpolation, enable_upscale, interpolation:{num_frames:1, use_calculated_fps:true, video_quality:'high', ...}, upscale:{upscale_factor:2, color_fix:true, output_quality:'high', ...}, shot_id?, based_on?+parent_generation_id?+is_primary:true, source_variant_id?}`.

**Example H — `klein_edit` → `flux_klein_edit`:** per-image rows `{seed, image, prompt, klein_model:'flux-klein-4b'|'flux-klein-9b', strength:0.6, num_inference_steps:8, output_format:'png', negative_prompt?}` + lineage.

**Example I — worker passthrough (`workerPassthrough.ts`):** used for any active `task_types` name without a resolver (worker-created children like `join_clips_segment`, `banodoco_*`, `travel_segment`). It honors `input.task_id` as the row `id` (so siblings can reference it in `dependant_on`), lifts `input.dependant_on`, and dumps the **entire input object into `params` unmodified**.

**Lineage fields** (`shared/lineage.ts` `setTaskLineageFields`) are the common cross-cutting keys: `shot_id`, `based_on`, `source_variant_id`, `create_as_generation`, `tool_type`, `timeline_placement` (`{timeline_id, source_clip_id, target_track, insertion_time, intent}`), `placement_intent` (`{timeline_id, anchor_clip_id, anchor_generation_id?, anchor_variant_id?, relation:'after', preferred_track_id, fallback_at, fallback_track_id}`).

### 3.4 What happens after insert (lifecycle)

- **Claim** (worker): `claim-next-task` RPCs flip `status Queued → In Progress`, set `worker_id`, `updated_at`, `generation_started_at = now()` in one atomic `UPDATE … FROM ready_tasks … RETURNING` (see §6). Eligibility: `users.credits > 0`, `settings.ui.generationMethods.inCloud != false` (SR path), `onComputer != false` (PAT path), in-progress < 5, dependencies complete, not orchestrator (for claiming), run_type match, banodoco pool separation, model affinity (`get_task_model` = `workers.current_model`) with starvation bypass after `max_task_wait_minutes`.
- **Completion**: `complete_task` — file to `image_uploads` bucket at `{userId}/tasks/{taskId}/{filename}` (or reuse `storage_path`), then:
  - `generations` routing (`generation.ts`): `variant_on_child` (if `child_generation_id`) → `variant_on_parent` (stitch tasks with `parent_generation_id`) → `child_generation` (parent exists) → `standalone`. Skips when `task_types.category='orchestration'` or `params.skip_generation === true`.
  - Generation row insert columns (from handlers + `generation-core.ts`): `project_id, location, thumbnail_url, type ('image'|'video' by content_type), based_on, params, tasks (jsonb array containing [taskId]), parent_generation_id, child_order, is_child, storage_mode, starred, name`. Variant insert: `generation_id, location, thumbnail_url, params, is_primary, variant_type, name, created_at, viewed_at?`. Link via RPC `add_generation_to_shot` when `params.shot_id` (or lineage `shot_id`) present.
  - `tasks` update: `{status:'Complete', output_location, generation_processed_at: now()}` guarded by `.eq('status','In Progress')`; then `markTaskFailed` if DB error; materialized-input cleanup; orchestrator completion check (updates orchestrator task status when all segments done — `orchestratorCore.ts`); timeline placement (asset registry + versioned config) when `timeline_placement`/`placement_intent` present; then (service-role only) `triggerCostCalculationIfNotSubTask` → HTTP POST `calculate-task-cost`.
- **Status updates** (`update-task-status`): transitions `Queued→[In Progress|Failed|Cancelled]`, `In Progress→[Complete|Failed|Cancelled|Queued]`, terminal states frozen. `buildTaskUpdatePayload` sets `status`, `updated_at`, `generation_started_at` (on In Progress or reset), `generation_processed_at` (on Complete), plus optional `output_location`, `attempts`, `error_message`, `worker_id=null`+`generation_started_at=null` (clear_worker), `result_data`. Failed/Cancelled → `cascade_task_failure(p_orchestrator_task_id, p_failed_task_id, p_failure_status, p_is_orchestrator_task)`; Cancelled orchestrators with completed children get billed for elapsed time via `handleOrchestratorCancellationBilling`.

---

## 4. Credits / billing enforcement

**Model: no debit at creation.** Task creation never touches credits. Billing is two-stage:

1. **Claim gating** (DB RPCs, §6): `users.credits > 0` required; 5-in-progress capacity per user; settings toggles (`inCloud` for SR claims, `onComputer` for PAT claims).
2. **Post-completion metering** (`calculate-task-cost`):
   - Duration = `ceil((generation_processed_at − generation_started_at)/1000)`, min 1s. Orchestrators: sum of completed sub-task durations (`params.orchestration_contract.orchestrator_task_id` / `params.orchestrator_task_id_ref` canonical, legacy `params.orchestrator_task_id`/`orchestrator_details` paths, UUID-validated, self-reference guarded — `_shared/billing.ts`).
   - Sub-tasks are skipped for direct billing (parent absorbs). Idempotency: existing `credits_ledger` row `{type:'spend', task_id}` → skip.
   - Rate: `task_types.base_cost_per_second × duration` (billing_type `per_second`), or `unit_cost` (billing_type `per_unit`), modified by `cost_factors` (`resolution` multiplier map, `frameCount` additive × count (× duration for per_second), `modelType` multiplier map). Fallback if no active `task_types` config: **0.0278/sec** (matches DB `get_task_cost()` default). `video_enhance` special-case compound pricing: FILM `$0.0013`/compute-second + FlashVSR `$0.0005`/megapixel, from `params.result` metrics.
   - Ledger row: `{user_id: projects.user_id, task_id, amount: -cost, type:'spend', metadata:{task_type, billing_type, duration_seconds, base_cost_per_second, unit_cost, cost_factors, task_params, calculated_at, task_type_id, cost_breakdown?}}`. Amount is in **cents** (fractional cents supported as integer math — `20250115000003_support_fractional_costs.sql`).
   - `users.credits` is refreshed by AFTER INSERT/UPDATE/DELETE triggers on `credits_ledger` (`refresh_user_balance` = `SUM(amount)`).
   - Insufficient credits → **no hard failure anywhere**: tasks just stop being claimable (claim RPC filters), and `task-counts` reports them under `blocked_by_capacity`/`blocked_by_settings`. There is no `get_credits` RPC and no `enqueue_*` RPC; the prompt's examples don't exist in this codebase.
- **Purchases** (positive ledger): `stripe` (checkout session, `metadata.stripe_session_id`, idempotent via unique partial index), `manual` (admin grant / welcome bonus, amount = dollars × 100), `auto_topup` (off-session payment intent, `metadata.stripe_payment_intent_id`). Auto-topup sweep: `trigger-auto-topup` (SR) → `process-auto-topup` (SR, atomic 1-hour claim via `auto_topup_last_triggered`).
- **Cancellation refunds**: none found — cancelled orchestrators with completed segments are *billed* (earliest start → now) rather than refunded.

---

## 5. Frontend invocation patterns

**All invocation is client-side fetch** to `https://<project-ref>.supabase.co/functions/v1/<name>` with `Authorization: Bearer <access_token>` + `apikey: <publishable key>`; there is no server-side proxy in reigh-app (Next.js app router doesn't wrap these).

- **Canonical helper**: `src/integrations/supabase/functions/invokeSupabaseEdgeFunction` (POST, 20s default timeout, AbortSignal support, typed error mapping) and direct `supabase().functions.invoke(...)`.
- **Task creation** (`src/shared/lib/taskCreation/createTask.ts`): builds `{family, project_id, input, idempotency_key (UUID), materialized_inputs?}`; retries once on timeout (15s), same idempotency key across retries; before posting it materializes local-only generations to storage (`materializeLocalGeneration`) and, when a `localWorkerSession` exists, attaches `materialized_inputs` records `{generation_id, kind, target}`.
- **AI endpoints**: `useAIInteractionService` (`ai-prompt`), `useAgentSession` (`ai-timeline-agent`, includes `session_id`, `proposal_policy`), `supabase().functions.invoke('ai-prompt', {task:'enhance_segment_prompt'})` in `submitSegmentTask.ts` / `enhancePromptsForBatch.ts`, `huggingface-upload` (multipart formData), `trim-video` (`useTrimSave`).
- **Billing**: `useCredits` → `stripe-checkout`, `grant-credits`; `useAutoTopup` → `setup-auto-topup`; `useApiTokens` → `generate-pat`/`revoke-pat`; `useTaskCancellation`/`useTaskPlaceholder` → `update-task-status` (status Cancelled).
- **Workers (not frontend)**: `reigh-worker`/`reigh-worker-orchestrator` call `claim-next-task`, `complete_task`, `generate-upload-url`, `update-task-status`, `task-counts` with the service-role key (`SUPABASE_SERVICE_ROLE_KEY`) — `reigh-worker-orchestrator/api_orchestrator/task_utils.py` builds the URL map, `storage_utils.py` uses `complete_task` + `generate-upload-url` (presigned path ≥ threshold). **Note:** `task_utils.py` references a `mark-task-failed` function that does **not** exist in the repo tree (gap — presumably deployed ad hoc or removed; `complete_task`/`update-task-status` cover failure marking).
- **Timeline/append service**: `timeline-import` and ai-timeline-agent persistence call an **external Reigh append service** (`REIGH_APPEND_SERVICE_URL` + `REIGH_APPEND_SERVICE_INTERNAL_TOKEN`, endpoints `/v1/timelines/{id}/config-replaced`, `/v1/timelines/create-with-config`) — `_shared/reighAppendService.ts`.
- **ai-timeline-agent → create-task**: the agent's `create_generation_task` tool POSTs to `create-task` with the service-role key and an `idempotency_key` of the form `timeline-agent:<sha256(payload)[:40]>`; batch variations use per-index derived keys.

---

## 6. RPC inventory (called by edge functions, with signatures)

From edge code + migrations. Signatures use `p_` params as called by the functions.

| RPC | Signature (as called) | Purpose |
|---|---|---|
| `claim_next_task_service_role` | `(p_worker_id text, p_include_active boolean, p_run_type text, p_same_model_only boolean, p_max_task_wait_minutes int, p_worker_pool text, p_task_types text[])` → `TABLE(task_id uuid, params jsonb, task_type text, project_id uuid, user_id uuid)` | Atomic claim (single `UPDATE…FROM`), SECURITY DEFINER. Eligibility: credits>0, inCloud, <5 in-progress (excl. orchestrators), deps complete (`all_dependencies_complete`), run_type via `get_task_run_type`, banodoco pool split, model affinity via `get_task_model` vs `workers.current_model` with starvation bypass. `20250131000100`, `20250203200001`, `20260504120000`, `20260506113000`, `20260507165000`, `20260507215500`. |
| `claim_next_task_user_pat` | `(p_user_id uuid, p_include_active boolean)` → `TABLE(task_id, params, task_type, project_id)` | Same for one user; checks `onComputer` setting. `20250914000001+`. |
| `count_eligible_tasks_service_role` | `(p_include_active boolean, p_run_type text)` → int | Capacity-limited claimable count. |
| `count_queued_tasks_breakdown_service_role` | `(p_run_type text)` → row `(claimable_now, blocked_by_capacity, blocked_by_deps, blocked_by_settings, total_queued)` | Unclaimable breakdown for scaling. |
| `per_user_capacity_stats_service_role` | `()` → rows `(user_id, in_progress_tasks, queued_tasks, …)` | Per-user capacity. |
| `count_eligible_tasks_user_pat` | `(p_user_id uuid, p_include_active boolean)` → int | PAT-path count. |
| `analyze_task_availability_service_role` | `(p_include_active boolean, p_run_type text)` → jsonb | Debug: `{total_tasks, eligible_tasks, rejection_reasons{no_credits, cloud_disabled, concurrency_limit, dependency_blocked}}`. |
| `analyze_task_availability_user_pat` | `(p_user_id uuid, p_include_active boolean)` → jsonb | Debug: `{user_info{credits,…}, projects[], recent_tasks[], eligible_count}`. |
| `check_rate_limit` | `(p_key text, p_window_seconds int, p_max_requests int)` → `{allowed, count, reset_at}` | Sliding-window counter (table-backed). `20251212001252`. |
| `derive_route_key` | `(p_task_type text, p_params jsonb)` → text | Route selector key from task type + params (model family, guidance kind/mode, continuity case, profile; honors `_source_task_type`). `20260513120000`. |
| `route_backend_claim_decision` | `(p_selector_namespace text, p_route_key text, p_worker_backend text, now())` → `(eligible boolean, decision_reason text)` | Claimability probe used by `tasks_assert_claimable` trigger + sentinel. |
| `ensure_shot_parent_generation` | `(p_shot_id uuid, p_project_id uuid)` → text (parent generation id) | Creates/reuses the parent generation row for a shot. `20260218143000` (+ trigger `20260218151500`). |
| `add_generation_to_shot` | `(p_shot_id, p_generation_id, p_with_position)` | Link generation → shot_generations. Many fix migrations (20250130xx series). |
| `insert_shot_at_position` | `(p_project_id, p_shot_name, p_position)` | Create shot (ai-timeline-agent clips tool). |
| `duplicate_as_new_generation` | `(p_shot_id, p_generation_id, p_project_id)` | Duplicate generation (agent tool). |
| `upsert_asset_registry_entry` | `(p_timeline_id, p_asset_id, p_entry)` | Timeline asset registry (complete_task placement, agent registry tool). |
| `update_timeline_config_versioned` / `update_timeline_versioned` | `(p_timeline_id, p_expected_version, p_config, …)` | Optimistic-concurrency timeline writes (complete_task placement, ai-timeline-agent db.ts). |
| `cascade_task_failure` | `(p_orchestrator_task_id, p_failed_task_id, p_failure_status, p_is_orchestrator_task)` → text[] | Marks related tasks Failed/Cancelled. |
| `func_insert_logs_batch` | `(logs jsonb)` → `{inserted, errors}` | SystemLogger flush → `system_logs`. |
| `get_external_api_key_decrypted` | `(p_user_id, p_service)` → rows `(key_value)` | HF token retrieval (huggingface-upload). |
| `delete_project_with_extended_timeout` | `(p_project_id)` | Cascade project deletion (5-min timeout). |
| `func_daily_task_stats` | `()` → day buckets | Discord stats. Fallback direct query exists. |
| `func_cleanup_old_logs` | `(48)` | Cron: purge system_logs > 48h. |
| `auto_fail_stale_tasks` | `()` | Cron: fail stale In Progress tasks. |
| `run_shot_sync_check` | `()` | Cron: verify shot sync (raises warnings). |

Not used by edge functions but central to billing: `get_task_run_type(text)`, `get_task_model(jsonb)`, `all_dependencies_complete(uuid[])`, `get_task_cost()` (DB-side default 0.0278 — the edge mirrors this constant).

---

## 7. Cron / scheduled

pg_cron jobs (all defined in migrations; pg_cron + pg_net extensions):

| Job | Schedule | Action | Migration |
|---|---|---|---|
| `route-contract-sentinel` | `* * * * *` (every minute) | `net.http_post` → `route-contract-sentinel` edge fn with service-role JWT from Vault (`sentinel_service_role_jwt`) | `20260513120300_sentinel_infra.sql` |
| `discord_daily_stats` | `0 9 * * *` (09:00 UTC) | `net.http_post` → `discord-daily-stats` edge fn | `20260205210535_add_discord_stats_cron.sql` |
| `auto-fail-stale-tasks` | `*/5 * * * *` (every 5 min) | `SELECT auto_fail_stale_tasks()` | `20260213200000`, freq bump `20260331070000` |
| `daily-shot-sync-check` | `0 3 * * *` (03:00 UTC) | `SELECT run_shot_sync_check()` | `20260213300000_schedule_shot_sync_check.sql` |
| `cleanup_system_logs_daily` | `0 3 * * *` | `SELECT func_cleanup_old_logs(48)` | `20250115110000_add_system_logs_cron_cleanup.sql` |
| `cleanup-rate-limits` | (commented out) hourly | `cleanup_old_rate_limits()` | `20251212001252_add_rate_limiting.sql` |

Only **two** cron jobs hit edge functions; the rest are pure SQL. There are no `functions.schedule()` (Supabase v2 scheduling) declarations in the repo — scheduling is entirely pg_cron.

---

## 8. Gaps / unverified

- **`mark-task-failed`** — referenced by `reigh-worker-orchestrator/api_orchestrator/task_utils.py` (`fail` endpoint) but absent from `reigh-app/supabase/functions/`. Either deployed ad hoc (not in repo) or dead reference. Unverified in live prod.
- **`enqueue-task`** — referenced by reigh-app `renderRouter.ts` and `delegateToBanodocoAgent.ts` (`ORCHESTRATOR_TASK_ENQUEUE_URL`); it's an **external orchestrator** endpoint, not a Supabase function. Its contract (SD-034 envelope) lives in the worker-orchestrator repo, not here.
- **Config drift**: `config.toml` is the local dev config. 15 functions are absent from the `verify_jwt=false` list, implying gateway JWT enforcement in local dev; whether prod matches this exactly (e.g., whether PAT calls to `update-worker-model`/`get-orchestrator-children` actually work in prod) is unverified.
- **`tasks` current column set** (route columns, `materialized_inputs`, `idempotency_key`, `result_data`, etc.) verified in edge code but the live-DB column list should be cross-checked against `07-live-db-schema.md`; the base-schema definition in this doc reflects migrations only.
- **`credits_ledger` unique partial indexes** (`metadata->>'stripe_session_id'` where type='stripe'; `metadata->>'stripe_payment_intent_id'` where type='auto_topup') are claimed in `stripe-webhook` comments to come from migration `20260130220000` — that migration file was not located in the repo listing (checked 466 files by name; may be under a different name or applied in prod only).
- **`claim_next_task_user_pat` drift**: the migration history shows a `DROP … claim_next_task_user_pat` overload fix (`20260212000000`); final deployed signature assumed `(p_user_id uuid, p_include_active boolean)` — verified against `20250914000001` + drop migration, not against live DB.
- **Task-type registry completeness**: `task_types` rows evolve via ~19 seed migrations (from `20250105000000` to `20260413000000` + `20260513150000_extend_model_family_seed`); the exact live set (names, `run_type`, `billing_type`, costs) should be read from the DB, not just migrations.
- **`generate-thumbnail`/`apply-image-transform` are service-role-only** — the "called automatically by task completion trigger" comment on `generate-thumbnail` could not be verified against a trigger in the read migrations; no trigger calling it was found in the edge function set (complete_task generates thumbnails inline via transforms).
- **Refund path**: no edge function or RPC performing `type='refund'` ledger writes was found in the read surface.
- **`promptEnvelope.ts`, `aiCodegenRetry.ts`, `rpcDecoders.ts`, `payloadNormalization.ts`, `errorMessage.ts`, `edgeOperation.ts`, `edgeRequest.ts`, `http.ts`, `taskStatusSemantics.ts`, `orchestratorReferenceLookup.ts`** exist as shared infra and are covered indirectly here; they are utility modules without their own DB surface.
- Worker-side claim/complete behavior (heartbeat, retries) is out of scope (worker repos); only the HTTP contracts are documented above.
