# 01 — Reigh PostgreSQL Schema (complete, migration-derived + live ground truth)

> **Status: COMPLETE.** Full PostgreSQL schema of Reigh, reconstructed from the authoritative migration chain `reigh-app/supabase/migrations/` (466 files: 461 standard + 2 `_applied_` + 3 `_hold_`), cross-checked against the generated client types `reigh-app/src/integrations/supabase/types.ts` (snapshot dated 2026-05-19, **stale** — lacks all May/June 2026 columns and several tables) and the live PROD dump in `07-live-db-schema.md` (read 2026-08-21 from `aws-0-eu-north-1.pooler.supabase.com`, PostgreSQL 17.4). Every claim cites its file. Nothing in this doc was written to any database.
>
> An engineer can recreate the schema by replaying `reigh-app/supabase/migrations/*.sql` in filename order against a fresh Supabase project, then applying the out-of-band additions listed in §12. The **live** DB is the final arbiter (51 tables / 20 views / 6 enums / 42 triggers / 243 indexes / 150 RLS policies / 202 functions).

## 1. Summary & key facts

**Table counts (exact):**
- **42 tables** are created by repo migrations; **1 is dropped** in-migration (`task_cost_configs`) → **41 migration-derived tables** expected in a clean replay.
- **Live DB has 51 tables** = 41 migration-derived + **10 live-only tables** created outside the migration chain: `attempts`, `shot_slots`, `agent_nodes`, `agent_node_catalog_metadata`, `agent_node_install_targets`, `agent_node_media`, `slot_first_migration_map`, `referrals`, `referral_sessions`, `shot_data_audit`.
- The capacity-reconciler variant's SQL dir (`reigh-worker-orchestrator-capacity-reconciler/sql/`) defines 3 more tables (`worker_capacity_intents`, `worker_capacity_route_backoffs`, `orchestrator_leases`) that are **NOT present in the live DB** — stale artifact (see §12.4).

**Enums (exact):**
- Migration-defined: **2** — `task_status` (5 values), `credit_ledger_type` (5 values).
- Live DB has **6** — the 2 above plus 4 live-only: `attempt_status`, `attempt_storage_mode`, `attempt_type`, `shot_slot_kind` (all lowercase values, from the out-of-band slot system).

**Key facts**
- Supabase project ref `wczysqzxlwdndgxitrvc` ("Reigh", org `ulyekujujoftqsnueirk`); host `https://wczysqzxlwdndgxitrvc.supabase.co`; pooler `postgresql://postgres.wczysqzxlwdndgxitrvc:<redacted>@aws-0-eu-north-1.pooler.supabase.com:5432/postgres`. Live PostgreSQL 17.4; REST v12.2.3; GoTrue v2.176.1; Storage v1.24.6. Local `config.toml` declares `major_version = 15` (local dev; no local DB exists on this machine).
- 466 migration files span 2024-08-01 → 2026-06-22; live `supabase_migrations.schema_migrations` records **465** versions → **4 prod-applied migrations are missing from the repo** (see §12.1).
- 2 enums, 13 migration-defined views (+7 live-only = 20), ~24 migration-defined active triggers (42 live incl. slot-system triggers), 122+ migration-defined indexes (243 live), 97 CREATE POLICY / 49 DROP POLICY statements → final policy set ~141 policy objects (150 live), 2 SQL enum types, 202 live functions in `public`.
- **Realtime publication (`supabase_realtime`):** `tasks`, `generations` (added 20250127000005), `timelines`, `timeline_agent_sessions` (added 2026032xxxxx). The old HTTP-broadcast triggers on tasks/generations were **dropped** by `20250917000000_migrate_generation_creation_to_edge_function.sql`.
- **pg_cron jobs (final):** `cleanup_system_logs_daily` (`0 3 * * *`, `func_cleanup_old_logs(48)`), `cleanup-rate-limits` (hourly), `discord_daily_stats` (`0 9 * * *` → net.http_post discord-daily-stats), `auto-fail-stale-tasks` (`*/5 * * * *`, final cadence after 20260331070000), `daily-shot-sync-check` (`0 3 * * *`), `route-contract-sentinel` (`* * * * *` → edge function, JWT from `vault.decrypted_secrets` name `sentinel_service_role_jwt`).
- **Extensions live (9):** `http` 1.6, `pg_cron` 1.6, `pg_net` 0.14.0, `pg_stat_statements` 1.11, `pg_trgm` 1.6, `pgcrypto` 1.3, `plpgsql` 1.0, `supabase_vault` 0.3.1, `uuid-ossp` 1.1. Migrations additionally `CREATE EXTENSION IF NOT EXISTS` `pgcrypto`, `pg_cron`, `pg_net`, `http`, `pg_trgm`, `vault`.
- **DB access layers:** `reigh-app` uses supabase-js (PostgREST + RPC) against generated types; `reigh-worker` and `reigh-worker-orchestrator` use the supabase-py REST client + edge functions (no SQLAlchemy/psycopg in app paths; `reigh-app/scripts/debug/.../sql.py` uses psycopg2 with `DATABASE_URL` for ops debugging). Orchestrators never run DDL at runtime.
- **Edge functions (46 in `reigh-app/supabase/functions/`)** are the DB write path for most flows: `create-task`, `claim-next-task`, `complete_task`, `update-task-status`, `task-counts`, `tasks-list`, `task-status`, `generate-upload-url`, `stripe-checkout`, `stripe-webhook`, `process-auto-topup`, `trigger-auto-topup`, `setup-auto-topup`, `complete-auto-topup-setup`, `grant-credits`, `generate-pat`, `revoke-pat`, `calculate-task-cost`, `ai-*` prompt/generation family, `timeline-import`, `ai-timeline-agent`, `route-contract-sentinel`, `delete-project`, `reigh-data-fetch`, `get-orchestrator-children`, `huggingface-upload`, `broadcast-realtime`, `discord-daily-stats`, `update-worker-model`, `trim-video`, `apply-image-transform`, `get-task-output`, `get-task-status`, `get-completed-segments`, `get-predecessor-output`, `update-shot-pair-prompts` + `_shared/`, `_tests/`. All listed in `supabase/config.toml` with `verify_jwt = false` (auth is handled in-function).

## 2. Enum types

| Enum | Values (exact, in order) | Origin |
|---|---|---|
| `public.task_status` | `Queued`, `In Progress`, `Complete`, `Failed`, `Cancelled` | `20250100000000_create_base_schema.sql` (CREATE TYPE); never altered |
| `public.credit_ledger_type` | `stripe`, `manual`, `spend`, `refund`, `auto_topup` | `20250113000000_add_credits_system.sql` (4 values) + `20250113000010_add_auto_topup_system.sql` (`ADD VALUE 'auto_topup'`) |
| `public.attempt_status` (live-only) | `queued`, `in_progress`, `complete`, `failed`, `cancelled` | out-of-band slot system; NOT in repo migrations |
| `public.attempt_storage_mode` (live-only) | `remote`, `local`, `uploading` | out-of-band |
| `public.attempt_type` (live-only) | `original`, `regen`, `edit`, `upscale`, `reposition`, `duplicate` | out-of-band |
| `public.shot_slot_kind` (live-only) | `image`, `video_segment`, `timeline_placement`, `project_asset` | out-of-band |

> Note the dual convention: `tasks.status` uses capitalized `task_status` values; the live `attempts.status` enum uses lowercase. `types.ts` (stale snapshot) lists only the 2 migration enums.

## 3. Table-by-table schema

Notation: PK = primary key, FK = foreign key, uq = unique constraint, idx = index, RLS = row-level security summary (full policy text in §8). `—` = no default. "added <file>" = column added later by that migration. Live-only tables marked ⚡.

### 3.1 Core task pipeline

#### `users` — profile/account table (id mirrors `auth.users.id`, no DB FK)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | — (PK) |
| name | text | YES | — |
| email | text | YES | — |
| api_keys | jsonb | YES | — (legacy; superseded by `user_api_tokens`) |
| settings | jsonb | YES | — (contains `ui.generationMethods.inCloud` used by claim eligibility) |
| credits | numeric(10,3) | NO | `0` (was integer; widened by `20250115000003_support_fractional_costs.sql`) |
| stripe_customer_id | text | YES | — (added `20250113000010`) |
| stripe_payment_method_id | text | YES | — (added `20250113000010`) |
| auto_topup_enabled | boolean | NO | `false` (added `20250113000010`) |
| auto_topup_amount | integer | YES | — (cents; added `20250113000010`) |
| auto_topup_threshold | integer | YES | — (cents; added `20250113000010`) |
| auto_topup_last_triggered | timestamptz | YES | — (added `20250113000010`) |
| given_credits | boolean | NO | `false` (added `20250210000001`) |
| onboarding | jsonb | NO | `'{}'` (added `20250211000001`) |
| avatar_url | text | YES | — (added `20251016000003`) |
| auto_topup_setup_completed | boolean | NO | `false` (added `20251218xxxx` onboarding batch) |
| onboarding_completed | boolean | NO | `false` (added `20260130300000`) |
| username | text | YES | — ⚡ live-only (referral system; no migration) |

- PK: `id`. FKs: none (user_id links are app-layer; other tables FK to `auth.users`).
- Unique: none besides PK.
- Indexes: `idx_users_stripe_customer (stripe_customer_id) WHERE stripe_customer_id IS NOT NULL`; `idx_users_auto_topup_enabled (auto_topup_enabled) WHERE auto_topup_enabled = true`; `idx_users_auto_topup_threshold (auto_topup_threshold) WHERE auto_topup_enabled = true`; `GIN (settings->'ui'->'generationMethods')` (added `20250912000000_optimize_welcome_bonus_flow` era).
- Triggers: `prevent_credit_manipulation` (BEFORE UPDATE → `prevent_direct_credit_updates()`, blocks direct credit writes except through ledger; `20250113000002_add_credit_protection.sql`); `auto_topup_trigger` (AFTER UPDATE OF credits WHEN `OLD.credits IS DISTINCT FROM NEW.credits` → `check_auto_topup_trigger()`, SECURITY DEFINER, calls edge fn `/functions/v1/trigger-auto-topup` via `net.http_post`, 1/hour rate-limit).
- RLS enabled. Policies: view own; update own; update own auto-topup settings; view own auto-topup settings; service role ALL/insert/delete; "Authenticated users can create their own user record" (INSERT, created `20250115000004`, **dropped** by `20250115000005` → final 8 policies incl. service-role ones).
- Row creation: `create_user_record_if_not_exists()` RPC (SECURITY DEFINER, `20250115000005`) and `auto_create_user_before_project()` trigger fn.

#### `projects`
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| name | text | NO | — |
| user_id | uuid | NO | FK → `users(id)` ON DELETE CASCADE |
| aspect_ratio | text | YES | — |
| created_at | timestamptz | NO | `now()` |
| settings | jsonb | YES | — |

- Indexes: `(user_id)`, `(user_id, id)` (idx_projects_user_id_id added `20250830000000_add_video_gallery_performance_indexes.sql`).
- Triggers: `auto_create_user_trigger` (BEFORE INSERT → `auto_create_user_before_project()`).
- RLS: 5 policies (`20251212000000_enable_rls_on_projects_and_shots.sql`): view/insert/update/delete own (`user_id = auth.uid()`), service_role ALL.
- Related RPC: `delete_project_with_extended_timeout(p_project_id)`.

#### `tasks` — the central job queue (claimed by GPU/API workers)
| Column | Type | Null | Default / notes |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| task_type | text | NO | — (registry in `task_types`; FK added by `20260213000000_add_tasks_task_type_fkey`) |
| params | jsonb | NO | — (holds `route_contract`, `model_name`, `orchestrator_details`, etc.) |
| status | task_status | NO | `'Queued'` |
| dependant_on | uuid[] | YES | — (was uuid; widened by `20260121000000_support_multiple_dependencies.sql`, GIN index) |
| output_location | text | YES | — (URL/path of result) |
| created_at | timestamptz | NO | `now()` |
| updated_at | timestamptz | YES | — |
| project_id | uuid | NO | FK → `projects(id)` ON DELETE CASCADE |
| generation_processed_at | timestamptz | YES | — |
| worker_id | text | YES | FK → `workers(id)` ON DELETE SET NULL (added `20250705000001`) |
| attempts | int | NO | `0` (added `20250712000002` era) |
| error_message | text | YES | — |
| result_data | jsonb | YES | `'{}'` |
| generation_started_at | timestamptz | YES | — (added `20250712000001`) |
| generation_created | boolean | NO | `false` (added `20250713000001`) |
| copied_from_share | text | YES | — (added `20251016000000`) |
| idempotency_key | text | YES | — (added `20260213200001`; UNIQUE partial) |
| materialized_inputs | jsonb | YES | — (added `20260505012055`; array of `{generation_id, kind: file|remote, target}`) |
| selector_namespace | text | YES | — (added `20260506110000`; check `~ '^[a-z][a-z0-9_-]{0,62}$'` or NULL) |
| route_key | text | YES | — (check: NULL or len 1..512, no whitespace) |
| selected_backend | text | YES | — (check: NULL or `wgp`/`vibecomfy`) |
| selector_version | bigint | YES | — (check: NULL or > 0) |
| route_selection_snapshot | jsonb | YES | — (check: NULL or object) |
| claimed_backend | text | YES | — (check as selected_backend) |
| claimed_selector_namespace | text | YES | — |
| claimed_route_key | text | YES | — |
| claimed_selector_version | bigint | YES | — |
| claimed_capability_version | bigint | YES | — |
| claim_decision_reason | text | YES | — |
| claim_decision_snapshot | jsonb | YES | — |
| support_state | text | YES | — (added `20260506120000`; check: NULL or `wgp_only`/`vibecomfy_supported`/`vibecomfy_unsupported`) |
| selected_profile | text | YES | — |
| selected_template_id | text | YES | — |
| route_run_id | text | YES | — |
| worker_contract_version | integer | YES | — (check: NULL or > 0) |

- PK `id`; FK `project_id → projects(id) CASCADE`; FK `worker_id → workers(id) SET NULL`; FK `task_type → task_types(name)` (added `20260213000000`).
- Unique: `idx_tasks_idempotency_key UNIQUE (idempotency_key) WHERE idempotency_key IS NOT NULL`.
- Indexes (17): `idx_status_created (status, created_at)`; `idx_project_status (project_id, status)`; `idx_tasks_worker_id (worker_id)`; `idx_tasks_dependant_on GIN (dependant_on) WHERE dependant_on IS NOT NULL`; `idx_tasks_queued_created (created_at) WHERE status='Queued'`; `idx_tasks_running_started (generation_started_at) WHERE status='In Progress'`; `idx_tasks_active_status (project_id, status) WHERE status='In Progress'`; `idx_tasks_status_generation_created (status, generation_created) WHERE status='Complete' AND generation_created=false`; `idx_tasks_poll_travel_stitch/single_image (task_type, status) WHERE generation_processed_at IS NULL AND task_type IN (...)`; `(status, worker_id)`; `(task_type) WHERE task_type IN ('travel_stitch','single_image')`; `(created_at DESC)`; `(status, project_id) WHERE status NOT IN (Complete,Failed,Cancelled)`; `idx_tasks_route_key_queued (route_key, created_at) WHERE status='Queued' AND route_key IS NOT NULL`; `idx_tasks_selected_backend_queued`; `idx_tasks_claimed_backend_active`; `idx_tasks_claimed_route_key_active` (last four added `20260506110000`).
- Triggers (migration-derived): `prevent_timing_manipulation_trigger` (BEFORE UPDATE → `prevent_timing_manipulation()`, protects generation_started_at/processed_at/created_at on non-service-role updates; `20250113000003`); `trigger_bill_cancelled_orchestrator` (AFTER UPDATE OF status WHEN → `'Cancelled'` → `bill_cancelled_orchestrator()`, bills completed child segments via `/functions/v1/calculate-task-cost`; `20260112140000`); `tasks_assert_claimable_trigger` (BEFORE INSERT OR UPDATE WHEN `status='Queued' AND task_type NOT LIKE '%_orchestrator'` → `tasks_assert_claimable()` requiring valid `params.route_contract` and at least one eligible backend; `20260513120200` — **DROPPED on live** by out-of-band migration `20260524010000_drop_tasks_assert_claimable_trigger`, see §12.1). Broadcast triggers `trigger_broadcast_task_status` were dropped (`20250917000000`).
- RLS: 7 policies. Service role ALL. Authenticated: SELECT own-project tasks (`project_id IN (SELECT p.id FROM projects p WHERE p.user_id = auth.uid())`), SELECT queued/in-progress tasks for claiming (`status = 'Queued' OR 'In Progress'`), UPDATE claim (`USING status='Queued'`, `WITH CHECK status IN ('Queued','In Progress')`), plus INSERT/UPDATE/SELECT owner policies from `20250113000003` (view/update own tasks, insert with `auth.uid() = project owner`).

#### `task_types` — task-type registry with billing metadata
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| name | text | NO | UNIQUE |
| run_type | text | NO | `'gpu'` (check `IN ('gpu','api')`) |
| category | text | NO | — |
| display_name | text | NO | — |
| description | text | YES | — |
| base_cost_per_second | decimal(10,6) | NO | — |
| cost_factors | jsonb | YES | `'{}'` |
| is_active | boolean | YES | `true` |
| created_at / updated_at | timestamptz | NO | `now()` / `now()` |
| billing_type | text | NO | `'per_second'` (added `20250203210000`) |
| unit_cost | decimal(10,6) | YES | — (added `20250203210000`) |
| tool_type | text | YES | — (added `20250902140000`) |
| content_type | text | YES | — (added `20250927000000`) |
| is_visible | boolean | YES | `false` (added `20260111100000`) |
| supports_progress | boolean | YES | `false` (added `20260111100000` era) |
| variant_type | text | YES | — (added `20260204191820`) |

- Seeded task_type names (18 inserts across 19 statements; base set copied from `task_cost_configs`): `single_image`, `travel_stitch`, `travel_orchestrator`, `image_upscale`, `image_edit`, `lora_training`, `travel_segment`, `edit_travel_kontext`, `edit_travel_flux` (from `task_cost_configs`), then `animate_character`, `join_clips_segment`, `join_clips_orchestrator`, `wan_2_2_i2v`, `qwen_image_style`, `image_inpaint`, `annotated_image_edit`, `individual_travel_segment`, `edit_video_orchestrator`, `edit_video_segment`, `qwen_image`, `qwen_image_2512`, `z_image_turbo`, `z_image_turbo_i2i`, `join_final_stitch`, `video_enhance`, `flux_klein_edit`. Live has **28 rows** (per reltuples).
- Indexes: `(name)`, `(run_type)`, `(category)`, `(is_active)`, `(billing_type)`, `(tool_type)`, `(content_type)`, `(is_visible)`.
- RLS: 2 policies — `task_types_select_authenticated` (SELECT TO authenticated, true) and `task_types_service_role_all` (ALL TO service_role) (`20260130200000_security_audit_fixes.sql`).
- Functions: `get_task_run_type(p_task_type text)` (SECURITY DEFINER, gpu fallback), `get_task_cost(p_task_type, p_duration_seconds, p_unit_count)`.

#### `workers` — GPU/API worker registry (heartbeat table)
| Column | Type | Null | Default |
|---|---|---|---|
| id | text | NO | — (PK, e.g. worker instance id) |
| instance_type | text | NO | — (`edge`/`server`/`manual`/…) |
| created_at | timestamptz | NO | `now()` |
| last_heartbeat | timestamptz | YES | `now()` → **made nullable**, default NULL by `20260121210000_make_worker_heartbeat_nullable.sql` |
| status | text | NO | `'active'` (check `IN ('active','inactive','terminated')`) |
| metadata | jsonb | YES | `'{}'` (holds `vram_total_mb`, `vram_used_mb`, model info) |
| current_model | text | YES | — (added `20251222000000_add_worker_model_affinity.sql`) |

- Indexes: `idx_workers_status (status)`, `idx_workers_last_heartbeat (last_heartbeat)`, `(current_model) WHERE status='active'`.
- RLS: 2 policies — "Service role can manage workers" (ALL), "Authenticated users can view workers" (SELECT) (`20250705000001`).
- Functions: `auto_register_worker(p_worker_id, p_instance_type)`, `func_update_worker_heartbeat(worker_id_param, vram_*_param)` (added crash-recovery: `20260331060000_add_crash_recovery_to_heartbeat.sql`), `func_worker_heartbeat_with_logs` (live), `func_reset_orphaned_tasks(failed_worker_ids)`.

#### `system_logs` — orchestrator/worker structured log sink
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| timestamp | timestamptz | NO | `now()` |
| source_type | text | NO | check `IN ('orchestrator_gpu','orchestrator_api','worker')` |
| source_id | text | NO | — |
| log_level | text | NO | check `IN ('DEBUG','INFO','WARNING','ERROR','CRITICAL')` |
| message | text | NO | — |
| task_id | uuid | YES | — |
| worker_id | text | YES | — |
| cycle_number | int | YES | — |
| metadata | jsonb | YES | `'{}'` |

- Indexes (6): `(timestamp DESC)`, `(log_level, timestamp DESC)`, `(source_type, source_id, timestamp DESC)`, `(task_id, timestamp DESC) WHERE task_id IS NOT NULL`, `(worker_id, timestamp DESC) WHERE worker_id IS NOT NULL`, `(source_type, cycle_number) WHERE cycle_number IS NOT NULL` (`20250115100000`).
- RLS: service-role-only write; authenticated read restricted (`20260121200000_restrict_system_logs_to_service_role.sql` + `20260313120000_restrict_worker_read_surfaces.sql`).
- Functions: `func_insert_logs_batch`, `func_cleanup_old_logs(retention_hours)` (cron), `v_recent_errors`, `v_worker_log_activity` views.

#### `credits_ledger` — immutable credit journal (balance = SUM(amount) per user)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| user_id | uuid | NO | FK → `users(id)` ON DELETE CASCADE |
| task_id | uuid | YES | FK → `tasks(id)` ON DELETE SET NULL |
| amount | numeric(10,3) | NO | — (was integer; `20250115000003`) |
| type | credit_ledger_type | NO | — |
| metadata | jsonb | YES | — (stripe ids for idempotency) |
| created_at | timestamptz | NO | `now()` |

- Unique: `UNIQUE (metadata->>'stripe_session_id') WHERE type='stripe' AND … IS NOT NULL`; `UNIQUE (metadata->>'stripe_payment_intent_id') WHERE type='auto_topup' AND … IS NOT NULL` (`20260130220000_add_stripe_idempotency.sql`).
- Indexes: `(user_id)`, `(type)`, `(created_at)`.
- Triggers: `credits_ledger_after_insert` (AFTER INSERT), `_after_update`, `_after_delete` → `refresh_user_balance()` which recomputes `users.credits` from the ledger (live shows after-insert ROW, after-update/delete STATEMENT — level drift from out-of-band work).
- RLS: 4 policies — user SELECT own (`auth.uid() = user_id`), service_role INSERT/UPDATE/DELETE.
- View: `user_credit_balance` (SELECT user_id, SUM(amount) balance FROM credits_ledger GROUP BY user_id — final simple form after `20260130230000_critical_fix_view_security.sql`).

#### `attempts` ⚡ live-only — slot-system attempt records (successor to generation_variants)
Full column dump in `07-live-db-schema.md` §3.1: `id, slot_id, project_id, task_id, params, params_prompt (generated), params_seed (generated), params_model (generated), output_url, output_bucket, output_path, thumbnail_url/bucket/path, storage_mode (attempt_storage_mode), local_handle_id, local_file_name/size/mime, legacy_url_only, status (attempt_status), attempt_type (attempt_type), based_on, parent_attempt_id, child_order, pair_shot_attempt_id, starred, name, error_message, viewed_at, superseded_by, deleted_at, created_at, updated_at`. 84k rows live. No RLS policies in migrations; live policies via join pattern.

#### `shot_slots` ⚡ live-only — slot-system timeline slots per shot
Full dump in `07-live-db-schema.md`; kind uses `shot_slot_kind` enum. 38k rows live.

#### `slot_first_migration_map` ⚡ live-only — slot-system migration bookkeeping (121k rows live, likely data-only mapping table).

### 3.2 Media / variants / gallery

#### `generations` — generation record (one per task output "family"; variants live in `generation_variants`)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| tasks | jsonb | YES | — |
| params | jsonb | YES | — |
| location | text | YES | — (primary output URL) |
| type | text | YES | — (`image`/`video`/…) |
| created_at | timestamptz | NO | `now()` |
| updated_at | timestamptz | YES | — |
| project_id | uuid | NO | FK → `projects(id)` ON DELETE CASCADE |
| shot_id | uuid | YES | FK → `shots(id)` ON DELETE SET NULL (added `20250202000000` era with timeline_frame) |
| timeline_frame | integer | YES | — (added same era) |
| starred | boolean | NO | `false` (added `20250201000000`) |
| thumbnail_url | text | YES | — (added `20250203100000`) |
| name | text | YES | — (added `20250204000000`) |
| urls | jsonb | YES | — (added `20250915000003`, then column usage simplified/removed `20250915000004`) |
| based_on | uuid | YES | FK → `generations(id)` ON DELETE SET NULL (added `20251012000000`) |
| copied_from_share | text | YES | — (added `20251016000000`) |
| parent_generation_id | uuid | YES | FK → `generations(id)` ON DELETE CASCADE (added `20260128000008`; child support v2 `20251120134059`) |
| child_order | integer | YES | — |
| is_child | boolean | NO | `false` |
| children | jsonb | YES | — |
| primary_variant_id | uuid | YES | FK → `generation_variants(id)` (added `20251201000000`) |
| pair_shot_generation_id | uuid | YES | FK → `shot_generations(id)` ON DELETE SET NULL (added `20260123200000`) |
| storage_mode | text | NO | `'remote'` (check `IN ('remote','local','uploading')`; added `20260421120000_generations_storage_mode.sql`) |
| local_handle_id | uuid | YES | FK → `local_media_handles(id)` ON DELETE SET NULL |
| local_file_name / local_file_size / local_file_mime | text / bigint / text | YES | — |
| shot_data | jsonb | YES | — (denormalized `{shot_id: [timeline_frames]}`; kept in sync by shot_generations triggers) |

- Indexes (15): `(project_id, created_at DESC)`, `(project_id, starred, created_at DESC)`, `(project_id, type, created_at DESC)`, `(shot_id)`, `(shot_id, timeline_frame)`, `(shot_id, timeline_frame, created_at DESC)`, `(based_on) WHERE based_on IS NOT NULL`, `(parent_generation_id) WHERE …`, `(parent_generation_id, pair_shot_generation_id) WHERE is_child AND pair…`, `(primary_variant_id) WHERE …`, `(thumbnail_url)`, `(type)`, `(name) WHERE name IS NOT NULL`, `GIN (params->'tool_type')`, `GIN (params->'originalParams'->'orchestrator_details'->>'prompt' gin_trgm_ops)` (prompt search), `(pair_shot_generation_id)`.
- Triggers: `trg_sync_variant_from_generation` (AFTER UPDATE OF location, thumbnail_url, name WHEN primary_variant_id NOT NULL → `sync_variant_from_generation_update()`); `audit_shot_data_trigger` ⚡ (AFTER ROW → `audit_shot_data_changes()`, writes `shot_data_audit`; live-only).
- RLS: 5 policies — service_role ALL; user SELECT/INSERT/UPDATE/DELETE via `project_id IN (SELECT id FROM projects WHERE user_id = auth.uid())` (finalized `20251021170000_fix_generations_update_policy.sql`).

#### `generation_variants` — variant rows per generation (original/upscaled/edit/…)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| generation_id | uuid | NO | FK → `generations(id)` ON DELETE CASCADE |
| location | text | NO | — |
| thumbnail_url | text | YES | — |
| params | jsonb | YES | — |
| is_primary | boolean | NO | `false` |
| variant_type | text | YES | — (`original`, `upscaled`, `edit`, …) |
| name | text | YES | — |
| created_at | timestamptz | NO | `now()` |
| project_id | uuid | YES | FK → `projects(id)` ON DELETE CASCADE (added `20251204000000`) |
| viewed_at | timestamptz | YES | — (added `20251228000000`) |
| starred | boolean | NO | `false` (added `20260209000000`) |

- Unique: `UNIQUE (generation_id) WHERE is_primary = true` (`20251201000001`).
- Indexes: `(generation_id)`, `(variant_type) WHERE NOT NULL`, `(viewed_at) WHERE NULL`, `(project_id) WHERE NOT NULL`, `(starred)`.
- Triggers (7): `trg_handle_variant_primary_switch` (BEFORE INSERT OR UPDATE OF is_primary WHEN `NEW.is_primary = true` → demotes old primary), `trg_sync_generation_from_variant` (AFTER INSERT OR UPDATE → pushes location/thumbnail/name to generation), `trg_auto_view_manual_upload` (BEFORE INSERT → `auto_view_manual_upload_variant()`, `20251228000001`), `trg_handle_variant_deletion` (AFTER DELETE → `handle_variant_deletion()`), `trg_clear_primary_variant_ref` (BEFORE DELETE → `clear_primary_variant_reference()`), `trg_prevent_original_variant_deletion` (BEFORE DELETE WHEN `OLD.variant_type='original'` → `prevent_original_variant_deletion()`, `20260330000000`), `trigger_set_variant_project_id` (BEFORE INSERT → `set_variant_project_id()`).
- RLS: 5 policies — service_role ALL; user CRUD via `EXISTS (SELECT 1 FROM generations g JOIN projects p … WHERE g.id = generation_variants.generation_id AND p.user_id = auth.uid())` (`20251201000000`).

#### `shot_generations` — join: shots ↔ generations (timeline placement)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| shot_id | uuid | NO | FK → `shots(id)` ON DELETE CASCADE |
| generation_id | uuid | NO | FK → `generations(id)` ON DELETE CASCADE |
| position | integer | NO | `0` (legacy position; superseded by timeline_frame) |
| timeline_frame | integer | YES | — (added `20250919000000` era) |
| metadata | jsonb | YES | — (segment overrides: `segmentOverrides.*`) |
| created_at | timestamptz | YES | `now()` |
| updated_at | timestamptz | YES | `now()` |

- Indexes (10): `(shot_id)`, `(generation_id)`, `(shot_id, generation_id)`, `(shot_id, position)`, `(shot_id, timeline_frame) WHERE NOT NULL`, `(shot_id, position) WHERE NOT NULL`, `(shot_id, generation_id) WHERE position IS NULL`, `(shot_id, generation_id, position) WHERE generation_id IS NOT NULL`, `(shot_id, created_at DESC)`, `(shot_id, position, created_at) WHERE generation_id IS NOT NULL`.
- Triggers: `sync_shot_generations_jsonb_row` (AFTER INSERT OR DELETE, per-row → `sync_shot_to_generation_jsonb()`), `sync_shot_generations_update_batch` (AFTER UPDATE, per-statement REFERENCING NEW TABLE → `sync_shot_data_update_batch()`; both from `20260218185000_per_statement_update_trigger.sql`), `auto_demote_on_timeline_remove` (AFTER UPDATE OF timeline_frame → `trigger_demote_on_timeline_remove()`, `20260224000000_auto_demote_trigger.sql`). Older per-row `sync_shot_generations`/`sync_shot_generations_jsonb` and protection triggers (`prevent_user_positioned_*`, `log_timeline_updates_trigger`, `prevent_drag_position_overwrites_trigger`) were dropped.
- RLS: 2 policies — service_role ALL; user ALL via join `EXISTS (SELECT 1 FROM shots s JOIN projects p ON s.project_id = p.id WHERE s.id = shot_generations.shot_id AND p.user_id = auth.uid())`.

#### `shots` — timeline shots (video-editor segments)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| name | text | NO | — |
| created_at | timestamptz | NO | `now()` |
| updated_at | timestamptz | YES | — |
| project_id | uuid | NO | FK → `projects(id)` ON DELETE CASCADE |
| settings | jsonb | YES | — |
| position | integer | YES | — (added `20250211000002_add_shot_position.sql`) |
| aspect_ratio | text | YES | — (added `20251003000000`) |

- Indexes: `(project_id, id)`.
- Triggers: `trigger_set_shot_position` (BEFORE INSERT → `set_new_shot_position()`), `trg_ensure_shot_parent_generation` (AFTER INSERT → `public.ensure_shot_parent_generation_after_insert()`, `20260218151500`), `shots_010_prevent_slot_project_drift` ⚡ live-only.
- RLS: 5 policies — service_role ALL; user CRUD via `project_id IN (SELECT id FROM projects WHERE user_id = auth.uid())`.
- RPCs: `create_shot_with_image`, `insert_shot_at_position`, `duplicate_shot`, `duplicate_shot_with_videos`, `duplicate_shot_generations`, `initialize_timeline_frames_for_shot`, `apply_timeline_frames`, `batch_update_timeline_frames`, `update_single_timeline_frame`, `reorder_normalized`, `normalize_shot_timeline`, `delete_and_normalize`, `unposition_and_normalize`, `fix_timeline_spacing`, `demote_orphaned_video_variants`, `update_shot_image_order_disabled` (disabled), `get_shared_shot_data`, `copy_shot_from_share`.

#### `resources` — user-owned resource registry (lora files, reference images, …)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| user_id | uuid | NO | FK → `users(id)` ON DELETE CASCADE |
| type | text | NO | — |
| metadata | jsonb | NO | — |
| created_at | timestamptz | NO | `now()` |
| is_public | boolean | NO | `false` (added `20251207000000`) |
| generation_id | uuid | YES | FK → `generations(id)` ON DELETE CASCADE (added `20260413110000`) |

- Indexes: `(is_public) WHERE is_public = true`, `(type, is_public) WHERE is_public = true`, `(generation_id)`.
- RLS: 2 policies — "Enable all access for resource owners" (ALL, `auth.uid() = user_id`), "Allow read access to public resources" (SELECT WHERE `is_public = true`, TO public).
- Functions: `upsert_asset_registry_entry` (20260329220000), `get_external_api_key_decrypted`, `save_external_api_key`, `delete_external_api_key` relate to `external_api_keys` instead.

#### `shared_generations` — public share links
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| share_slug | text | NO | UNIQUE |
| task_id | uuid | NO | FK → `tasks(id)` ON DELETE CASCADE |
| generation_id | uuid | NO | FK → `generations(id)` ON DELETE CASCADE |
| creator_id | uuid | YES | FK → `users(id)` ON DELETE SET NULL |
| created_at | timestamptz | YES | `now()` |
| view_count | integer | YES | `0` |
| last_viewed_at | timestamptz | YES | — |
| cached_generation_data | jsonb | YES | — |
| cached_task_data | jsonb | YES | — |
| creator_username / creator_name / creator_avatar_url | text | YES | — (added `20251016000002`) |
| shot_id | uuid | YES | FK → `shots(id)` ON DELETE SET NULL (added `20251016000003` era) |

- Unique: `UNIQUE (generation_id, creator_id)`.
- Indexes: `(share_slug)`, `(task_id)`, `(creator_id)`, `(generation_id)`, `(shot_id)`.
- RLS: 4 policies — public SELECT (USING true); INSERT own (`auth.uid() = creator_id`); UPDATE/DELETE own.
- Functions: `increment_share_view_count(share_slug_param)` (SECURITY DEFINER, granted to authenticated+anon), `get_shared_shot_data(share_slug_param)`, `copy_shot_from_share(share_slug_param, target_project_id)`.

#### `local_media_handles` — local-file storage mode handles (for local-first generation outputs)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| user_id | uuid | NO | FK → `auth.users(id)` ON DELETE CASCADE |
| project_id | uuid | YES | FK → `projects(id)` ON DELETE SET NULL |
| created_at | timestamptz | NO | `now()` |

- Indexes: `(user_id)`, `(project_id)`.
- RLS: 3 policies — view/insert/delete own (`auth.uid() = user_id`).

### 3.3 Timeline / video-editor system (Astrid-like file/store model)

#### `timelines` — timeline documents (JSON config + asset registry)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| project_id | uuid | NO | FK → `projects(id)` ON DELETE CASCADE |
| user_id | uuid | NO | FK → `auth.users(id)` ON DELETE CASCADE |
| name | text | NO | — |
| config | jsonb | NO | — |
| asset_registry | jsonb | NO | `'{"assets": {}}'` |
| created_at | timestamptz | NO | `timezone('utc', now())` |
| updated_at | timestamptz | NO | `timezone('utc', now())` |
| config_version | integer | NO | `1` (added `20260326100000_add_timeline_config_version.sql`) |

- Indexes: `(project_id)`, `(user_id)`.
- RLS: 4 policies — view/insert/update/delete own (`auth.uid() = user_id`).
- Realtime: added to `supabase_realtime` publication.
- Functions: `append_timeline_event(...)` and `create_timeline_with_initial_event(...)` mutate `timelines.config/config_version/asset_registry` atomically with `timeline_events`.

#### `timeline_events` — append-only event log (hash-chained, ULID event ids)
Columns (all NOT NULL unless noted): `event_id text` (check ULID `^[0-9A-HJKMNP-TV-Z]{26}$`), `timeline_id uuid` FK → timelines CASCADE, `version integer` (check > 0), `prev_hash text` (NULL or sha256 hex), `hash text` (sha256 hex), `kind text` (non-empty), `payload jsonb` (object), `schema_version integer` (> 0), `idempotency_key text` (NULL), `ts timestamptz`, `actor jsonb` default `'{}'` (object), `expected_version integer` (NULL or ≥0), `txn_id uuid`, `source_backend text`, `source_timeline_id text`, `source_event_id text`, `source_version integer` (>0 or NULL), `source_hash text`.
- PK: `(timeline_id, version)`; Unique: `(timeline_id, event_id)`; Unique index `(timeline_id, idempotency_key) WHERE idempotency_key IS NOT NULL`.
- RLS: 1 policy — SELECT own via timeline ownership EXISTS. Grants: authenticated SELECT only; service_role all (revokes from public/anon).
- Functions: `append_timeline_event(p_timeline_id uuid, p_events jsonb, p_projected_config jsonb, p_expected_config_version integer, p_projected_asset_registry jsonb DEFAULT NULL) RETURNS TABLE(config_version int, inserted_event_ids text[])` — SECURITY DEFINER, service_role-only, validates CAS/config_version/hash-chain/schema-version, then updates timelines atomically. `create_timeline_with_initial_event(p_timeline jsonb, p_event jsonb, p_projected_config jsonb, p_projected_asset_registry jsonb DEFAULT NULL) RETURNS TABLE(timeline_id uuid, config_version int, inserted_event_ids text[])` — same guards; inserts timeline + version-1 event.

#### `timeline_event_contract` — singleton schema-version row
- `id integer` PK (check id = 1), `current_schema_version integer` (> 0). Seeded `(1, 2)`.
- RLS: 1 policy — authenticated SELECT. Grants: SELECT authenticated; all service_role.

#### `sync_bookmarks` — per-(timeline, spoke) sync heads
- Columns: `timeline_id uuid` FK CASCADE, `spoke text` (check `IN ('local','app')`), `spoke_version int` default 0 (≥0), `spoke_hash text` (NULL or sha256), `spoke_event_id text` (NULL or ULID), `hub_version int` default 0, `hub_hash text`, `hub_event_id text`, `synced_at timestamptz` default utc now, `created_at`, `updated_at`. Consistency checks: `(version=0 AND hash IS NULL AND event_id IS NULL) OR (version>0 AND hash NOT NULL AND event_id NOT NULL)` for both spoke and hub.
- PK `(timeline_id, spoke)`; index `(timeline_id, synced_at DESC)`.
- RLS: SELECT own via timeline EXISTS; grants authenticated SELECT, service_role all.

#### `divergence_log` — keep-both divergence records
- Columns: `id uuid` PK, `timeline_id uuid` FK CASCADE, `spoke text` (local|app), `spoke_version/hash/event_id`, `hub_version/hash/event_id` (same checks), `spoke_suffix jsonb` (array), `hub_suffix jsonb` (array), `chosen_side text` default `'undecided'` (check `IN ('spoke','hub','undecided')`), `artifact_pointer jsonb` (object or NULL), `created_at`, `updated_at`, `resolved_at timestamptz`; resolution check: undecided ⇔ resolved_at NULL.
- Indexes: `(timeline_id, created_at DESC)`, `(timeline_id, spoke, created_at DESC)`.
- RLS: SELECT own via timeline EXISTS; grants authenticated SELECT, service_role all.

#### `timeline_agent_sessions` — agentic editing sessions on a timeline
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| timeline_id | uuid | NO | FK → timelines CASCADE |
| user_id | uuid | NO | FK → auth.users CASCADE |
| status | text | NO | `'waiting_user'` (check `IN ('waiting_user','processing','continue','done','cancelled','error')`) |
| turns | jsonb | NO | `'[]'` |
| model | text | NO | `'groq'` |
| summary | text | YES | — |
| created_at / updated_at | timestamptz | NO | `now()` |
| cancelled_at | timestamptz | YES | — (added `20260408113000`) |
| cancelled_by | uuid | YES | FK → auth.users SET NULL |
| cancel_source / cancel_reason | text | YES | — |
| proposal_policy | text | YES | — (added `20260622235001`; check NULL or `always`/`immediate`) |

- Indexes: `(timeline_id, status)`.
- RLS: 3 policies — view/insert/update own (`auth.uid() = user_id`).
- Realtime: in `supabase_realtime`.

#### `timeline_checkpoints`
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| timeline_id | uuid | NO | FK → timelines CASCADE |
| user_id | uuid | NO | FK → auth.users CASCADE |
| config | jsonb | NO | — |
| trigger_type | text | NO | check `IN ('session_boundary','edit_distance','semantic','manual')` |
| label | text | NO | — |
| edits_since_last_checkpoint | integer | NO | `0` |
| created_at | timestamptz | NO | `now()` |

- Indexes: `(timeline_id, created_at DESC)`.
- RLS: 4 policies — own CRUD.

#### `timeline_update_log` — debug audit of timeline_frame changes (log_timeline_updates_trigger was dropped; table remains)
- Columns: `id uuid` PK, `generation_id uuid` NOT NULL, `shot_id uuid`, `old_timeline_frame int`, `new_timeline_frame int`, `operation_type text` NOT NULL, `call_source text`, `metadata jsonb`, `created_at timestamptz` default now.
- RLS: 2 policies — `timeline_update_log_select_authenticated` (SELECT TO authenticated), `timeline_update_log_service_role_all` (`20260130210000_secure_settings_and_logging_tables.sql`).

#### `effects` — user-authored video-editor effects (code shaders)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| user_id | uuid | NO | FK → auth.users CASCADE |
| name | text | NO | — |
| slug | text | NO | — |
| code | text | NO | — |
| category | text | NO | check `IN ('entrance','exit','continuous')` |
| description | text | YES | — |
| is_public | boolean | NO | `false` |
| created_at / updated_at | timestamptz | NO | `timezone('utc', now())` |

- Unique: `(user_id, slug)`. Index: `(user_id)`.
- RLS: 4 policies — own CRUD.

#### `local_media_handles`, `timeline_*` extension tables — see §3.5 for extension tables.

### 3.4 Auth / tokens / keys

#### `user_api_tokens` — Personal Access Tokens (PAT) for workers/API
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| user_id | uuid | NO | FK → `auth.users(id)` ON DELETE CASCADE |
| token | text | NO | — (added `20250711000003`, made NOT NULL `20250713000008`; `jti_hash`/`expires_at`/`last_used` dropped) |
| label | text | YES | — |
| created_at | timestamptz | NO | `now()` |

- Unique: `UNIQUE (token)` (`idx_user_api_tokens_token`). Index: `(user_id)`.
- RLS: 1 policy — SELECT own. Functions: `verify_api_token()` (validates Bearer PAT), `generate-pat` / `revoke-pat` edge functions.

#### `external_api_keys` — per-user external-service keys (vault-encrypted)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| user_id | uuid | NO | FK → `auth.users(id)` ON DELETE CASCADE |
| service | varchar(50) | NO | — |
| key_value | text | NO | — |
| metadata | jsonb | YES | `'{}'` |
| created_at / updated_at | timestamptz | NO | `now()` |
| vault_secret_id | uuid | YES | — (added `20260105300000_vault_encryption_for_api_keys.sql`) |

- Unique: `(user_id, service)`. Indexes: `(user_id)`, `(service)`.
- Trigger: `update_external_api_keys_updated_at` (BEFORE UPDATE).
- RLS: 4 policies — own CRUD (file `_applied_20250105000000_create_external_api_keys.sql`; applied out-of-band, see §12.2).
- Functions: `save_external_api_key(p_service, p_key_value, p_metadata)`, `get_external_api_key_decrypted(p_service, p_user_id)`, `delete_external_api_key` (grants restricted by `20260309184500_restrict_external_api_key_function_grants.sql`).

### 3.5 Extension persistence (timeline extensions — M2/M3)

All three tables: `id uuid` PK default `gen_random_uuid()`, `user_id uuid` NOT NULL FK → `auth.users(id)` CASCADE, `timeline_id uuid` NOT NULL FK → `timelines(id)` CASCADE, `extension_id text` NOT NULL (check non-empty), `schema_version integer` NOT NULL (default 1, check > 0), `created_at`/`updated_at timestamptz` NOT NULL default `timezone('utc', now())`, `metadata jsonb` (default `'{}'`, object check on install_state only). RLS: 5 policies each — own CRUD with `auth.uid() = user_id AND EXISTS(timelines owned)` + service_role ALL. Grants: authenticated CRUD, service_role CRUD.

- `extension_install_state`: + `enabled boolean` default true, `installed_at timestamptz` default utc now, `last_toggled_at timestamptz`, `toggle_reason text`, `pack_version text`. Unique `(user_id, timeline_id, extension_id)`. Indexes: `(user_id)`, `(timeline_id)`, `(timeline_id, extension_id)`.
- `extension_settings`: + `values jsonb` NOT NULL default `'{}'` (object check), `last_written_at timestamptz` default utc now. Unique `(user_id, timeline_id, extension_id)`. Indexes same 3.
- `extension_proposals`: + `status text` default `'draft'`, `payload jsonb` default `'{}'` (object), `label text`, `base_version integer` default 1 (check > 0), `expires_at/accepted_at/rejected_at timestamptz` (added `20260622235000`). Final status check (superset of legacy + SDK): `IN ('draft','submitted','accepted','rejected','cancelled','expired','pending','stale')`. Indexes: `(user_id)`, `(timeline_id)`, `(timeline_id, extension_id)`, `(status)`, `(timeline_id, status)`, `(timeline_id, status, expires_at)`.

### 3.6 Route control plane (task routing: wgp vs vibecomfy backends)

#### `route_backend_selectors` — active selector per (namespace, route_key)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| selector_namespace | text | NO | `'production'` (check `^[a-z][a-z0-9_-]{0,62}$`) |
| route_key | text | NO | (check len 1..512, no whitespace) |
| selected_backend | text | NO | (check `IN ('wgp','vibecomfy')`) |
| selector_version | bigint | NO | (check > 0) |
| enabled | boolean | NO | `true` |
| expires_at | timestamptz | YES | — |
| min_worker_version | text | YES | — |
| reason | text | YES | — |
| metadata | jsonb | NO | `'{}'` (object check) |
| created_at / updated_at | timestamptz | NO | `now()` |
| updated_by | uuid | YES | — |

- Unique: `(selector_namespace, route_key)`.
- Indexes: `idx_route_backend_selectors_lookup (selector_namespace, route_key) WHERE enabled`, `(selected_backend, selector_namespace) WHERE enabled`, `(expires_at) WHERE NOT NULL`.
- RLS: 1 policy — service_role ALL (revokes from anon/authenticated).

#### `route_backend_capabilities` — backend × route support matrix
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| backend | text | NO | (check `IN ('wgp','vibecomfy')`) |
| route_key | text | NO | (check as above) |
| supports_route | boolean | NO | `false` |
| supports_missing_selector | boolean | NO | `false` (check: only wgp may true) |
| enabled | boolean | NO | `true` |
| capability_version | bigint | NO | `1` (check > 0) |
| expires_at / min_worker_version / metadata / created_at / updated_at / updated_by | — | — | as selectors |

- Unique: `(backend, route_key)`.
- Indexes: `(backend, route_key) WHERE enabled`, `(route_key, backend) WHERE enabled AND supports_missing_selector`, `(expires_at) WHERE NOT NULL`.
- RLS: 1 policy — service_role ALL.
- Function: `route_backend_claim_decision(p_selector_namespace text, p_route_key text, p_worker_backend text, p_now timestamptz DEFAULT now()) RETURNS TABLE(...)` — SECURITY DEFINER STABLE; decides eligibility with reason codes (`missing_capability`, `selector_disabled`, `backend_mismatch`, …). Backends seeded: `wgp`, `vibecomfy`.

#### `route_alias_map` — task_type alias → canonical route_key
- `alias text` PK, `route_key text` NOT NULL. Seeded from DIRECT_ROUTE_ALIASES (`20260513120000_derive_route_key.sql`): `z_image→z_image_turbo`, `z_image_turbo→z_image_turbo`, `z_image_turbo_i2i→z_image_turbo_i2i`, `qwen_image→qwen_image`, `qwen_image_2512→qwen_image_2512`, `optimised_t2i→wan_2_2_t2i`, `wan_2_2_t2i→wan_2_2_t2i`, `qwen_image_edit→qwen_image_edit`, `qwen_image_style→qwen_image_style`, `image_inpaint→image_inpaint`, `annotated_image_edit→annotated_image_edit`.

#### `model_family_for_model` — model_name → route family (single source of truth)
- `model_name text` PK, `route_family text` NOT NULL check `IN ('wan22_i2v','wan22_vace','ltx2','ltx2_distilled','qwen','z_image')`. Seeded with `wan_2_2_i2v`, `wan_2_2_vace_lightning_baseline_2_2_2`, `ltx2_22B_distilled_1_1`, `ltx2_22B`, `wan_2_2_t2i`, `wan_2_2_vace`, `z_image_turbo`, `z_image_turbo_i2i`, `qwen_image`, `qwen_image_2512`, `qwen_image_edit`, `qwen_image_style` (+ later seeds).

#### Related functions (route layer)
- `derive_route_key(p_task_type text, p_params jsonb) RETURNS text` — STABLE; builds `{slug(task_type)}__model-{family}__guidance-{key}__continuity-{case}__profile-{profile}` for travel/segment families via `model_family_for_model` (ignores `params.model_family` overrides), else alias-map lookup, else raw task_type. Helper `_route_slug(p_value text)` IMMUTABLE mirrors JS slug().
- `tasks_assert_claimable()` — see tasks triggers (dropped live).

### 3.7 Observability / ops / misc

#### `sentinel_ticks` — route-contract sentinel per-minute classifications
- `ts timestamptz` PK default now(), `state text` NOT NULL (OK|NO_WORK|UNCLAIMABLE_WORK|NO_READY_WORKERS|WORKERS_STUCK_INITIALIZING), `detail jsonb`. 138k rows live.

#### `pause_scaling` — per-pool scaling pause
- `pool text` PK, `until timestamptz` NOT NULL, `reason text`.

#### `settings` — key/value feature flags
- `key text` PK, `value text` NOT NULL. RLS: `settings_select_all` (SELECT TO authenticated, anon), `settings_service_role_all` (ALL). (Values include `disable_timeline_standardization`, etc.)

#### `onboarding_config` — onboarding flow templates
- `key text` PK, `value jsonb` NOT NULL, `updated_at timestamptz` default now(). Trigger: `onboarding_config_updated_at` (BEFORE UPDATE). RLS: public SELECT, service_role ALL. Functions: `copy_onboarding_template`, `copy_onboarding_template_admin`.

#### `rate_limits` — generic rate-limit counters
- `key text` PK, `count integer` NOT NULL default 1, `window_start timestamptz` NOT NULL default now(), `updated_at timestamptz` NOT NULL default now(). Index `(window_start)`. RLS: service_role ALL only. Functions: `check_rate_limit(p_key, p_max_requests, p_window_seconds)`, `cleanup_old_rate_limits()` (cron hourly).

#### `dev_tasks` — internal dev-task tracker (Discord-driven)
| Column | Type | Null | Default |
|---|---|---|---|
| id | uuid | NO | `gen_random_uuid()` (PK) |
| title | text | NO | — |
| description | text | YES | — |
| status | text | NO | `'backlog'` (check `IN ('backlog','todo','in_progress','done','cancelled')`) |
| area | text | YES | — |
| notes | text | YES | — |
| created_at | timestamptz | NO | `now()` |
| completed_at | timestamptz | YES | — |
| commit_hash | text | YES | — (added `20251218200002`) |
| execution_details | jsonb | YES | — (added `20251218200004`; replaces `tokens` int added `20251218200003`) |
| discord_thread_id | text | YES | — ⚡ live-only |

- Indexes: `(status)`, `(area) WHERE NOT NULL`, `(created_at DESC)`.
- RLS: 2 policies — authenticated ALL, service_role ALL (`20251218000000_create_dev_tasks.sql`).

#### `training_data`, `training_data_segments`, `training_data_batches` — LoRA training data pipeline
- `training_data`: `id uuid` PK, `user_id uuid` NOT NULL FK `auth.users(id)` CASCADE, `original_filename text` NOT NULL, `storage_location text` NOT NULL, `duration integer`, `metadata jsonb`, `created_at`/`updated_at`, `batch_id uuid` FK → `training_data_batches(id)` CASCADE (added `20250120000003`). Indexes `(user_id)`, `(created_at)`, `(batch_id)`.
- `training_data_segments`: `id uuid` PK, `training_data_id uuid` FK CASCADE, `start_time/end_time integer` NOT NULL, `segment_location text`, `description text`, `metadata jsonb`, timestamps. Indexes `(training_data_id)`, `(created_at)`.
- `training_data_batches`: `id uuid` PK, `user_id uuid` FK auth.users CASCADE, `name text` NOT NULL, `description text`, `metadata jsonb` default `'{}'`, timestamps. Indexes `(user_id)`, `(created_at)`.
- RLS: 4 policies each — own CRUD (`auth.uid() = user_id`).

#### `task_cost_configs` — legacy pricing table (created `20250712000000`, **dropped** `20250203220000`; NOT in live DB; base cost set: `single_image`, `travel_stitch`, `travel_orchestrator`, `image_upscale`, `image_edit`, `lora_training`, `travel_segment`, `edit_travel_kontext`, `edit_travel_flux`, `video_enhance`, … — superseded by `task_types`). Documented for completeness only; do not recreate.

### 3.8 Live-only tables ⚡ (out-of-band, no repo migration)

- `attempts`, `shot_slots`, `slot_first_migration_map` — the **slot system**: re-architects generations/variants/shots into `shot_slots` + `attempts` (enums `attempt_status`, `attempt_storage_mode`, `attempt_type`, `shot_slot_kind`; generated columns `params_prompt`, `params_seed`, `params_model`; 8+ triggers incl. `slot_first_*` lineage/project-consistency guards). Full DDL in `07-live-db-schema.md` §3.1/§3.4.
- `agent_nodes`, `agent_node_media`, `agent_node_install_targets`, `agent_node_catalog_metadata` — agent marketplace/catalog tables (`storage_bucket` default `'agent-node-media'`, `review_status` default `'pending'`, `source_type` default `'git'`); public views `public_agent_node_catalog`, `public_agent_node_install_targets`, `public_agent_node_media`.
- `referrals`, `referral_sessions`, `shot_data_audit` — referral system (`referrals`: `id, referrer_id, referrer_username, referred_id, session_id, created_at`; `referral_sessions`: `id, session_id, referrer_user_id, referrer_username, visitor_fingerprint, visitor_ip, visit_count, first/last_visit_at, converted_at, converted_user_id, is_latest_referrer`; `shot_data_audit`: `id bigserial, generation_id, operation, old_shot_data, new_shot_data, changed_by, created_at` fed by `audit_shot_data_changes` trigger) and the `referral_stats` view + `users.username` column. RPCs: `track_referral_visit(p_referrer_username, p_session_id?, p_visitor_fingerprint?, p_visitor_ip?) → text`, `create_referral_from_session(p_session_id, p_fingerprint) → text`, `verify_referral_security()`. No repo migration creates any of these — applied to prod outside migration tracking (see §12.4).

### 3.9 Capacity-reconciler SQL (NOT live; stale artifact)

`reigh-worker-orchestrator-capacity-reconciler/sql/20260514000000_create_worker_capacity_intents.sql` defines `worker_capacity_intents`, `worker_capacity_route_backoffs`, `orchestrator_leases` (full DDL in the file; CHECK constraints, partial unique on authoritative (pool, cycle_id), shadow flag). **Live probe confirms these tables do NOT exist in prod.** The other 6 files in that dir duplicate main-chain migrations (system_logs, monitoring views, legacy functions).

## 4. SQL functions / RPCs

**202 functions live in `public`** (see `07-live-db-schema.md` §3.11 for the full name list). The authoritative client catalog is `reigh-app/src/integrations/supabase/types.ts` §Functions (88 names in the 2026-05-19 snapshot; 72 with Args/Returns parsed below) plus the 2 service-role timeline RPCs added by `20260612100000` after that snapshot. Core families:

### 4.1 Task lifecycle / claiming (worker ↔ DB contract)
| Function | Signature (from types.ts / migrations) | Purpose |
|---|---|---|
| `claim_next_task_service_role` | `(p_worker_id text, p_include_active bool DEFAULT false, p_run_type text DEFAULT NULL, p_same_model_only bool DEFAULT false, p_max_task_wait_minutes int DEFAULT 5, p_worker_pool text DEFAULT NULL, p_task_types text[] DEFAULT NULL) → TABLE(task_id uuid, params jsonb, task_type text, project_id uuid, user_id uuid)` | Atomic claim: eligible users = credits>0, inCloud=true, <5 in-progress; model-affinity + starvation bypass; banodoco pool filtering; excludes `%_orchestrator` from counts. SECURITY DEFINER removed in `20250910220009` (RLS-based). Not in types.ts snapshot — live-only name in pg catalog. |
| `claim_next_task_user` | `(p_user_id uuid, p_include_active bool DEFAULT false, p_run_type text DEFAULT NULL) → TABLE(...)` | Claim for a specific user (local processing). Older `(p_user_id, p_include_active, p_run_type, p_same_model_only, p_max_task_wait_minutes)` overload dropped (`20260212000000`). |
| `func_claim_available_task` | `(worker_id_param text) → task row` | Legacy claim fn (pat-era). |
| `complete_task_with_timing` | `(p_task_id text, p_output_location text) → boolean` | Marks Complete + sets timing; edge `complete_task` uses this. |
| `func_update_task_status` | `(p_task_id text, p_status text, p_output_location text DEFAULT NULL, p_generation_started_at timestamptz DEFAULT NULL, p_table_name text DEFAULT NULL) → boolean` | Status transition helper. |
| `safe_update_task_status` | `(p_task_id text, p_status text, p_generation_started_at timestamptz DEFAULT NULL) → boolean` | Race-safe status update. |
| `safe_insert_task` | `(p_id uuid, p_project_id uuid, p_task_type text, p_params jsonb, p_dependant_on text DEFAULT NULL) → text` | Idempotent task insert. |
| `func_mark_task_complete` | `(task_id_param text, result_data_param jsonb DEFAULT NULL)` | Legacy complete. |
| `func_mark_task_failed` | (live) | Mark failed. |
| `func_reset_orphaned_tasks` | `(failed_worker_ids text[]) → number` | Re-queue tasks from dead workers. |
| `func_get_tasks_by_status` | `(status_filter text[]) → task rows` | Poll helper. |
| `func_update_worker_heartbeat` | `(worker_id_param text, vram_total_mb_param numeric DEFAULT NULL, vram_used_mb_param numeric DEFAULT NULL)` | Heartbeat + VRAM. `func_worker_heartbeat_with_logs` (live) adds log write. |
| `auto_register_worker` | `(p_worker_id text, p_instance_type text DEFAULT NULL)` | Upsert worker. |
| `all_dependencies_complete` | `(p_dependant_on uuid[]) → boolean` | Multi-dep gate. |
| `cascade_task_failure` | (live; `20260331040000_add_cascade_failure_rpc.sql`) | Fail dependent tasks. |
| `auto_fail_stale_tasks` | `() ` (cron) | Stale-task failover (`20260331050000`). |
| `get_task_run_type` / `get_task_model` | `(text) → text` / `(jsonb) → text` | run_type lookup / model from params. |
| `analyze_task_availability_service_role` / `_user_pat` | `(p_include_active bool, p_run_type text) / (p_include_active bool, p_user_id uuid) → jsonb` | Availability analysis. |
| `count_eligible_tasks_service_role` / `_user` / `_user_pat` | → number | Counts (capacity). |
| `count_queued_tasks_breakdown_service_role` | `(p_run_type text) → TABLE(blocked_by_capacity, blocked_by_credits, blocked_by_dependencies, eligible, ...)` | Queue breakdown. |
| `per_user_capacity_stats_service_role` | `()` | Per-user capacity. |

### 4.2 Shot / generation editing (timeline RPC surface)
`add_generation_to_shot(p_shot_id uuid, p_generation_id uuid, p_with_position bool DEFAULT true)`; `apply_timeline_frames(p_shot_id uuid, p_changes jsonb, p_update_positions bool DEFAULT false)`; `batch_update_timeline_frames(p_changes jsonb)`; `batch_update_timeline_positions(updates jsonb)`; `update_single_timeline_frame(p_generation_id uuid, p_new_timeline_frame int, p_metadata jsonb)`; `update_timeline_frame_debug(...)`; `debug_timeline_update(...)`; `get_recent_timeline_updates(p_generation_id uuid, p_minutes int)`; `timeline_sync_bulletproof(shot_uuid uuid, frame_changes jsonb, should_update_positions bool DEFAULT true)`; `initialize_timeline_frames_for_shot(p_shot_id uuid, p_frame_spacing int DEFAULT 50)`; `insert_shot_at_position(p_project_id uuid, p_shot_name text, p_position int)`; `reorder_normalized(p_shot_id uuid, p_new_order uuid[])`; `normalize_shot_timeline(p_shot_id uuid)`; `unposition_and_normalize(p_shot_id uuid, p_shot_generation_id uuid)`; `delete_and_normalize(p_shot_id uuid, p_shot_generation_id uuid)`; `fix_timeline_spacing(p_shot_id uuid)`; `demote_orphaned_video_variants(p_shot_id uuid)`; `count_unpositioned_generations(p_shot_id uuid)`; `create_shot_with_image(p_project_id uuid, p_shot_name text, p_generation_id uuid)`; `ensure_shot_association_from_params(p_generation_id uuid, p_params jsonb)`; `ensure_shot_parent_generation(p_shot_id uuid, p_project_id uuid DEFAULT NULL)`; `duplicate_shot(original_shot_id uuid, project_id uuid) → text`; `duplicate_shot_with_videos(original_shot_id uuid, project_id uuid) → jsonb` (+ helper `_duplicate_shot_with_videos_remap_jsonb` live); `duplicate_shot_generations(p_source_shot_id uuid, p_target_shot_id uuid)`; `create_shot_with_generations` (live); `check_shot_generations_functions()` / `check_shot_generations_triggers()` / `verify_shot_sync()` (diagnostics); `update_shot_image_order_disabled(...)` (disabled). Timeline-event RPCs: `append_timeline_event`, `create_timeline_with_initial_event` (see §3.3).

### 4.3 Credits / billing / referrals
`refresh_user_balance()` (trigger fn); `check_auto_topup_trigger()` (trigger fn, SECURITY DEFINER); `get_task_cost(p_task_type text, p_duration_seconds numeric, p_unit_count int DEFAULT NULL)`; `check_welcome_bonus_eligibility()`; `increment_share_view_count(share_slug_param text)`; `track_referral_visit(p_referrer_username text, p_session_id text DEFAULT NULL, p_visitor_fingerprint text DEFAULT NULL, p_visitor_ip inet DEFAULT NULL) → text` ⚡; `create_referral_from_session(p_session_id text, p_fingerprint text) → text` ⚡; `verify_referral_security()` ⚡.

### 4.4 Auth / keys / users / misc
`create_user_record_if_not_exists()`; `verify_api_token()`; `auto_create_user_before_project()` (trigger fn); `update_tool_settings_atomic(p_table_name text, p_tool_id text, p_id uuid, p_settings jsonb)`; `delete_project_with_extended_timeout(p_project_id uuid) → boolean`; `copy_onboarding_template(target_project_id uuid, target_shot_id uuid)`; `copy_onboarding_template_admin(...)`; `extract_discord_username(jwt_claims jsonb, user_metadata jsonb)`; `sanitize_discord_handle(...)`; `bytea_to_text`/`text_to_bytea`; `normalize_image_path`/`normalize_image_paths_in_jsonb`; `func_initialize_tasks_table(p_table_name text)`; `func_migrate_tasks_for_task_type(p_table_name text)`; `func_insert_logs_batch(...)`; `func_cleanup_old_logs(retention_hours int DEFAULT 48) → jsonb`; `check_rate_limit(p_key text, p_max_requests int, p_window_seconds int) → jsonb`; `cleanup_old_rate_limits()`; `upsert_asset_registry_entry(...)`; `route_backend_claim_decision(...)`; `derive_route_key(text, jsonb)`; `_route_slug(text)`; `tasks_assert_claimable()` (trigger fn, dropped live); `get_shared_shot_data(share_slug_param text) → jsonb`; `copy_shot_from_share(share_slug_param text, target_project_id uuid) → text`.
Extension helpers (pg_net/pg_http): `http(http_request)`, `http_get/head/patch/put`, `http_header`, `http_set_curlopt`, `http_reset_curlopt`, `http_list_curlopt`; composite types `http_header`, `http_request`, `http_response`; `show_limit()`, `show_trgm()` (pg_trgm).

> Trigger functions (24 migration-defined): `refresh_user_balance`, `prevent_direct_credit_updates`, `check_auto_topup_trigger`, `auto_create_user_before_project`, `prevent_timing_manipulation`, `bill_cancelled_orchestrator`, `tasks_assert_claimable`, `sync_shot_to_generation_jsonb`, `sync_shot_data_update_batch`, `trigger_demote_on_timeline_remove`, `set_new_shot_position`, `ensure_shot_parent_generation_after_insert`, `handle_variant_primary_switch`, `sync_generation_from_primary_variant`, `sync_variant_from_generation_update`, `auto_view_manual_upload_variant`, `handle_variant_deletion`, `clear_primary_variant_reference`, `prevent_original_variant_deletion`, `set_variant_project_id`, `update_onboarding_config_updated_at`, `update_external_api_keys_updated_at`, `create_generation_on_task_complete` (dropped), `audit_shot_data_changes` ⚡ live-only. Plus slot-system `slot_first_*` guards ⚡.

## 5. Views (20 live; 13 migration-defined)

| View | Migration-defined? | Notes |
|---|---|---|
| `user_credit_balance` | yes | `SELECT user_id, SUM(amount) AS balance FROM credits_ledger GROUP BY user_id` (final form after `20260130230000`) |
| `normalized_task_status` | yes | id + normalized/original status |
| `orchestrator_status` | yes | task/worker counts, security_invoker |
| `active_workers_health` | yes | workers + heartbeat age + VRAM % + current task |
| `recent_task_activity` | yes | tasks + duration + worker info |
| `worker_performance` | yes | tasks/worker aggregation |
| `task_queue_analysis` | yes | per task_type/status counts + ages |
| `task_types_with_billing` | yes | billing_type-aware primary_cost |
| `shot_statistics` | yes | per-shot counts (positioned/unpositioned/video/final-video) |
| `shot_final_videos` | yes | final video per generation (DISTINCT ON g.id; single-segment identity redesign was held) |
| `shot_generations_with_computed_position` | yes | timeline_frame w/ computed fallback |
| `v_recent_errors` | yes | system_logs ERROR rollup |
| `v_worker_log_activity` | yes | workers × logs |
| `referral_stats` | ⚡ live-only | users + visit/conversion aggregates |
| `project_asset_compositions`, `shot_compositions`, `slot_first_health` | ⚡ live-only | slot-system composition views |
| `public_agent_node_catalog`, `public_agent_node_install_targets`, `public_agent_node_media` | ⚡ live-only | agent marketplace public views |

Most are `security_invoker` after `20260130230000/20260130240000` security fixes. `CREATE MATERIALIZED VIEW` is not used.

## 6. Triggers (24 migration-derived active; 42 live)

Migration-derived active set (verified by ordered replay of CREATE/DROP TRIGGER):

| Table | Trigger | Timing | Function |
|---|---|---|---|
| credits_ledger | credits_ledger_after_insert | AFTER INSERT ROW | refresh_user_balance |
| credits_ledger | credits_ledger_after_update | AFTER UPDATE ROW | refresh_user_balance |
| credits_ledger | credits_ledger_after_delete | AFTER DELETE ROW | refresh_user_balance |
| users | prevent_credit_manipulation | BEFORE UPDATE ROW | prevent_direct_credit_updates |
| users | auto_topup_trigger | AFTER UPDATE OF credits ROW (WHEN credits changed) | check_auto_topup_trigger |
| projects | auto_create_user_trigger | BEFORE INSERT ROW | auto_create_user_before_project |
| tasks | prevent_timing_manipulation_trigger | BEFORE UPDATE ROW | prevent_timing_manipulation |
| tasks | trigger_bill_cancelled_orchestrator | AFTER UPDATE OF status ROW (WHEN → Cancelled) | bill_cancelled_orchestrator |
| tasks | tasks_assert_claimable_trigger | BEFORE INSERT OR UPDATE ROW (WHEN Queued, non-orchestrator) | tasks_assert_claimable — **dropped live** |
| generations | trg_sync_variant_from_generation | AFTER UPDATE OF location, thumbnail_url, name ROW (WHEN primary_variant_id NOT NULL) | sync_variant_from_generation_update |
| shot_generations | sync_shot_generations_jsonb_row | AFTER INSERT OR DELETE ROW | sync_shot_to_generation_jsonb |
| shot_generations | sync_shot_generations_update_batch | AFTER UPDATE STATEMENT (REFERENCING NEW TABLE) | sync_shot_data_update_batch |
| shot_generations | auto_demote_on_timeline_remove | AFTER UPDATE OF timeline_frame ROW | trigger_demote_on_timeline_remove |
| shots | trigger_set_shot_position | BEFORE INSERT ROW | set_new_shot_position |
| shots | trg_ensure_shot_parent_generation | AFTER INSERT ROW | ensure_shot_parent_generation_after_insert |
| generation_variants | trg_handle_variant_primary_switch | BEFORE INSERT OR UPDATE OF is_primary ROW (WHEN is_primary) | handle_variant_primary_switch |
| generation_variants | trg_sync_generation_from_variant | AFTER INSERT OR UPDATE ROW | sync_generation_from_primary_variant |
| generation_variants | trg_auto_view_manual_upload | BEFORE INSERT ROW | auto_view_manual_upload_variant |
| generation_variants | trg_handle_variant_deletion | AFTER DELETE ROW | handle_variant_deletion |
| generation_variants | trg_clear_primary_variant_ref | BEFORE DELETE ROW | clear_primary_variant_reference |
| generation_variants | trg_prevent_original_variant_deletion | BEFORE DELETE ROW (WHEN variant_type='original') | prevent_original_variant_deletion |
| generation_variants | trigger_set_variant_project_id | BEFORE INSERT ROW | set_variant_project_id |
| onboarding_config | onboarding_config_updated_at | BEFORE UPDATE ROW | update_onboarding_config_updated_at |
| external_api_keys | update_external_api_keys_updated_at | BEFORE UPDATE ROW | update_external_api_keys_updated_at |

Dropped during history (not active): broadcast triggers (`trigger_broadcast_task_status`, `trigger_broadcast_generation_created` — HTTP broadcast removed `20250917000000`), `sync_shot_generations`/`sync_shot_generations_jsonb` (row-level, replaced by batch triggers `2026021818xx`), `log_timeline_updates_trigger` (`20260218163000`), timeline protection triggers (`prevent_user_positioned_*`, `prevent_drag_position_overwrites_trigger`, `protect_user_positioned_timeline_frames_trigger` — `20260218210000`), `trg_auto_create_variant_after_generation` (`20260520000000_drop_disabled_auto_variant_trigger_function.sql`), `trigger_process_completed_tasks`, `ensure_user_exists_trigger`. Live adds 18 slot-system + audit triggers (`slot_first_*`, `audit_shot_data_trigger`, `agent_nodes_*` — see `07-live-db-schema.md` §3.4).

## 7. Indexes (243 live; 122+ migration-defined)

Full per-table inventory extracted from migrations: see the `CREATE INDEX` replay in §3 tables. Notable: GIN indexes on `tasks(dependant_on)` and `users(settings->'ui'->'generationMethods')` and `generations(params->'tool_type')`; trgm GIN on `generations(params->'originalParams'->'orchestrator_details'->>'prompt')`; partial unique `tasks(idempotency_key)`, `generation_variants(generation_id) WHERE is_primary`, `credits_ledger(metadata->>'stripe_session_id')`; partial indexes on tasks status columns for polling/claiming. Live index set (243) differs from the migration replay because of the out-of-band slot system (`attempts`, `shot_slots`) and the 4 missing migrations — full live list in `07-live-db-schema.md` §3.5.

## 8. RLS model (97 CREATE POLICY / 49 DROP POLICY statements; ~141 final policy objects; 150 live policies on 46 RLS-enabled tables)

Three canonical patterns (quoted from the migrations):

1. **Direct-owner** — `auth.uid() = user_id` (users, timelines, effects, timeline_agent_sessions, timeline_checkpoints, local_media_handles, extension_*, training_data*, external_api_keys, dev_tasks).
2. **Owner-via-join** — `project_id IN (SELECT id FROM projects WHERE user_id = auth.uid())` or `EXISTS (SELECT 1 FROM shots s JOIN projects p ON s.project_id = p.id WHERE s.id = shot_generations.shot_id AND p.user_id = auth.uid())` (tasks, generations, shots, shot_generations, generation_variants, projects, resources, shared_generations — survives project ownership changes).
3. **Service-role bypass** — `TO service_role USING (true) WITH CHECK (true)` on every RLS table; plus special surfaces:
   - `tasks`: cross-user claiming policies (authenticated UPDATE on `status='Queued'`, SELECT on queued/in-progress) added `20250910220009` after SECURITY DEFINER removal.
   - `workers`: authenticated SELECT (health/status), service_role ALL.
   - `settings`, `task_types`, `onboarding_config`, `task_cost_configs`(gone): read-only for authenticated/anon, service_role ALL.
   - `system_logs`: service-role write; `20260313120000_restrict_worker_read_surfaces.sql` restricts authenticated read.
   - `credits_ledger`: user SELECT own only; service_role writes.
   - `rate_limits`: service_role ONLY (no user policies).
   - `route_backend_selectors`/`route_backend_capabilities`: service_role ONLY (anon/authenticated revoked).
   - `timeline_events`/`sync_bookmarks`/`divergence_log`/`timeline_event_contract`: authenticated SELECT-only via timeline ownership; service_role full (explicit REVOKEs).
   - `user_api_tokens`: SELECT own only.
   - `storage.objects`: 25 policies across 6 buckets (see §9).
   - `resources`: public SELECT on `is_public = true` rows + owner ALL.
   - `shared_generations`: public SELECT (USING true) + owner INSERT/UPDATE/DELETE.
   - `dev_tasks`: authenticated ALL (dev tool).
   - `onboarding_config`: anon/authenticated SELECT, service_role ALL.

RLS is enabled on 25 tables via migrations (`ALTER TABLE … ENABLE ROW LEVEL SECURITY`): users, projects, tasks, generations, shots, shot_generations, resources, credits_ledger, system_logs, task_types, workers, user_api_tokens, training_data(+segments+batches), shared_generations, generation_variants, settings, onboarding_config, rate_limits, timelines, effects, timeline_agent_sessions, timeline_checkpoints, timeline_update_log, route_backend_selectors, route_backend_capabilities, timeline_events, timeline_event_contract, sync_bookmarks, divergence_log, extension_*, local_media_handles, dev_tasks (+ storage.objects). Live: **46 RLS-enabled tables** (adds the slot-system/live-only tables). No FORCE RLS anywhere.

## 9. Storage buckets + path conventions (Supabase Storage)

| Bucket | Public | file_size_limit | Path convention | Policies |
|---|---|---|---|---|
| `temporary` | private | 524288000 (500 MB) | `{user_id}/{filename}` | auth upload/read/delete (first path segment = `auth.uid()`), service_role ALL (`20250105000001`) |
| `training-data` | private (was public; **made private** `20251212000001_security_hardening.sql`) | default | `{user_id}/{filename}` | auth CRUD own (`20250120000000`) |
| `lora_files` | public | default | `{user_id}/...` | auth CRUD own; SELECT open to authenticated (`20250710000000` + `20251212000001`) |
| `image_uploads` ⚡ | public [INFERENCE — no migration creates it; app uses `getPublicUrl` (`src/shared/lib/media/imageUploader.ts`, `src/tools/character-animate/pages/uploadMedia.ts`); created via dashboard] | default | `{user_id}/uploads/{file}`, `{user_id}/thumbnails/{file}`, `{user_id}/tasks/{task_id}/{file}`, `{user_id}/tasks/{task_id}/thumbnails/{file}` (`src/shared/lib/storagePaths.ts` + `supabase/functions/_shared/storagePaths.ts`; `MEDIA_BUCKET = 'image_uploads'`) | 4 policies (`20250710000001`, hardened `20251212000001`): insert/update/delete where `auth.uid() = owner` or first folder, select by bucket |
| `timeline-assets` | **public** (made public `20260407020000_make_timeline_assets_public.sql` to avoid 15–25s signed URLs) | default | `{user_id}/{timeline_id}/{asset}` (user-first folder) | auth CRUD own + `timeline_assets_public_read` SELECT (anyone) |
| `render-outputs` | private | default | `{user_id}/{timeline_id}/{task_id}.mp4` | auth CRUD own (user-first folder; `20260428130000`) |

Additional bucket referenced by live-only code: `agent-node-media` (default in `agent_node_media.storage_bucket`, ⚡ live-only). No `storage.buckets` migration exists for `image_uploads` — it is a live-created bucket. Bucket object names are `{user_id}/...`; RLS uses `(storage.foldername(name))[1] = auth.uid()::text`.

## 10. Auth model

- **Platform auth schema (GoTrue v2.176.1, managed):** `auth.users`, `auth.identities`, `auth.sessions`, `auth.refresh_tokens`, `auth.mfa_factors`, `auth.one_time_tokens`, etc. — standard Supabase; not replicated in migrations. Signup enabled (`config.toml: enable_signup=true`, email `double_confirm_changes=true`, `enable_confirmations=false`, JWT expiry 3600s, refresh-token rotation on).
- **Profile table = `public.users`** with `id` = `auth.users.id` — **no DB FK** (app-layer invariant). Row created via `create_user_record_if_not_exists()` RPC (called by frontend on auth) or `auto_create_user_before_project()` BEFORE INSERT trigger on `projects` (creates `users` row if missing).
- **RLS everywhere** keys off `auth.uid()` / `auth.role()` / `auth.jwt()` (metadata: `full_name`, `name`, `email`).
- **Service role** (`SUPABASE_SERVICE_ROLE_KEY`) bypasses RLS and is the only principal allowed to write `credits_ledger`, `system_logs`, `rate_limits`, route tables, and timeline-event tables.
- **Personal Access Tokens:** `user_api_tokens` (raw token, UNIQUE) + `verify_api_token()`; edge functions `generate-pat`/`revoke-pat`; PATs let workers/orchestrator act as a user (claim `_user`/`_user_pat` variants).
- **Anonymous access:** `anon` role has SELECT on `settings`, `task_types`, `onboarding_config`, public `resources` (`is_public=true`), `shared_generations`, `timeline-assets` bucket, and storage buckets' read policies where noted. `enable_anonymous_sign_ins = false`.

## 11. Connection config (secrets masked)

| Item | Value |
|---|---|
| Project ref | `wczysqzxlwdndgxitrvc` (project name "Reigh"; org `ulyekujujoftqsnueirk`) |
| Supabase URL | `https://wczysqzxlwdndgxitrvc.supabase.co` (in `reigh-app/.env` `SUPABASE_URL`, `.env.local`) |
| Pooler / DATABASE_URL | `postgresql://postgres.wczysqzxlwdndgxitrvc:<redacted>@aws-0-eu-north-1.pooler.supabase.com:5432/postgres` (`reigh-app/.env` `DATABASE_URL`; pooler-url also in `supabase/.temp/pooler-url`; TLS `PGSSLMODE=require`) |
| Region | `aws-0-eu-north-1` |
| Live Postgres | 17.4.1.048 (`.temp/postgres-version`; live probe confirms 17.4) — local `config.toml` declares 15 |
| REST | v12.2.3 (`postgrest-version`); GoTrue v2.176.1; Storage v1.24.6 |
| Keys (never print values) | `SUPABASE_ANON_KEY` (VITE_), `SUPABASE_SERVICE_ROLE_KEY`, `DATABASE_URL`, plus `FAL_API_KEY`, `STRIPE_PUBLISHABLE_KEY`, `VITE_REIGH_APPEND_SERVICE_URL`, `VITE_API_TARGET_URL`, `VITE_APP_ENV`; dev/test creds in `.env.local` (`TEST_USER_EMAIL`, `TEST_USER_PASSWORD`, `DEV_USER_ID`, `DEV_USER_EMAIL`, `DEV_USER_PASSWORD`) |
| In-DB secrets | `vault` schema: `vault.create_secret('<service-role-jwt>', 'sentinel_service_role_jwt')` (used by sentinel cron), `external_api_keys.vault_secret_id` |
| GUCs used by functions | `app.supabase_url`, `app.service_role_key` (read via `current_setting(..., true)`) — set at DB level; `supabase.service_role_key` for pg_net calls |
| DB access stack | supabase-js / supabase-py (REST + RPC); no ORM DDL at runtime; debug tooling: `reigh-app/scripts/debug/.../sql.py` (psycopg2, `DATABASE_URL`), root `./debug`, `docs/debug-cli.md` |

## 12. Migration vs live drift (summary; details in `07-live-db-schema.md` §4)

1. **4 prod-applied migrations missing from repo** (`supabase_migrations.schema_migrations` = 465 vs 461 repo standard files): `20260507160420_drop_obsolete_claim_next_task_overload`, `20260507160605_reload_postgrest_schema_after_claim_overload_drop`, `20260524000000_revert_route_backend_gating_in_claim_and_counts`, `20260524010000_drop_tasks_assert_claimable_trigger`. **Consequence:** replaying the repo ends with `tasks_assert_claimable` trigger + route-gated claims that prod deliberately reverted.
2. **`_applied_` files (2):** `_applied_20250105000000_create_external_api_keys.sql` (applied out-of-band; version collides with tracked `20250105000000 add_animate_character_task_type`; live table verified) and `_applied_20260225000000_backfill_pair_shot_generation_id.sql` (data only).
3. **`_hold_` files (3):** `_hold_20250910150000_fix_security_warnings.sql`, `_hold_20251218000000_dynamic_timeline_spacing.sql`, `_hold_20260414_shot_final_videos_single_segment_identity.sql` — intentionally not applied; superseded by applied equivalents.
4. **Out-of-band live objects with no repo migration at all** (applied outside `schema_migrations` tracking): the slot system (`attempts`, `shot_slots`, `slot_first_migration_map` + 4 enums + 18 triggers + ~7 views + slot RPCs), the agent-node marketplace (`agent_nodes`, `agent_node_media`, `agent_node_install_targets`, `agent_node_catalog_metadata` + public views), the referral system (`referrals`, `referral_sessions`, `referral_stats` view, `users.username`, `dev_tasks.discord_thread_id`, `shot_data_audit` + `audit_shot_data_trigger`, RPCs `track_referral_visit`/`create_referral_from_session`/`verify_referral_security`). The live probe's "no reverse drift" claim does not account for these — they exist live but their DDL is not recoverable from this repo.
5. **`types.ts` (2026-05-19) is a stale snapshot** — missing the May/June 2026 route columns, timeline-event contract tables, extension tables, and all live-only tables/columns; it also shows only 2 enums. Do not use it as schema source of truth.
6. **Capacity-reconciler `sql/`** (`worker_capacity_intents`, `worker_capacity_route_backoffs`, `orchestrator_leases`) is **not applied to prod** (confirmed by live probe).
7. **Top-level `supabase/` dir** (empty `functions/`, `.temp/linked-project.json` → same project ref) is a 3-month-old leftover; `reigh-app/supabase/` is current.
8. **Order anomalies** in the migration dir (e.g. `20250203220000_drop_task_cost_configs_table.sql` before `20250712000000_create_task_cost_configs.sql`) indicate a renumbered/backfilled history; `task_cost_configs` is absent live (dropped) — `task_types` is the pricing registry.
9. **Trigger-level drift:** live shows several migration triggers at different levels/timings (e.g. `credits_ledger_after_delete` AFTER STATEMENT live vs AFTER DELETE ROW in migration) — attributable to the out-of-band slot work re-creating them.

## 13. Gaps / unverified

- **Exact SQL of the 4 missing prod migrations and the out-of-band slot/referral/agent-node DDL** is not recoverable from this repo (only from prod `pg_proc`/`pg_views`/history or unpushed branches); the live doc §3 has the resulting objects.
- **Full function bodies** (202 functions) are not included; `types.ts` gives signatures for 88 (72 parsed; the rest have `Args: undefined`), and the two June RPC bodies were read directly (`20260612100000`). Live function list in `07-live-db-schema.md` §3.11.
- **`image_uploads` bucket** has no creation migration — public flag is [INFERENCE] from `getPublicUrl` usage; verify in `storage.buckets` (single SELECT).
- **Which of the 4 missing prod migrations created the slot/referral/agent tables** is unknown; `slot_first_migration_map`'s 121k rows suggest a large data backfill ran in prod.
- **Task-type seed completeness:** the repo inserts 18+ names but live has 28 rows — the extra rows may come from missing/out-of-band migrations; verify against live `task_types` if exact billing rows are needed for migration.
- Referral RPCs/columns are exercised by frontend code (`useAuthReferralFinalize.ts`, `useReferralTracking.ts`) but have no repo DDL — treat as live-only surface that the Astrid migration must account for.
- Row counts cited are `pg_class.reltuples` estimates (see `07-live-db-schema.md` §3.13), not exact.


