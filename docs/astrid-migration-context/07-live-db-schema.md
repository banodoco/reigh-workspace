# 07 — Live Database Schema (PROD ground truth)

> **Status: REACHED.** The live production schema was dumped directly from the Supabase-hosted PostgreSQL 17.4 database on 2026-08-21 using `psql` 16 + the `DATABASE_URL` in `reigh-app/.env`. No local dev database exists on this workstation (Docker daemon down; no `supabase start` stack). Everything below is ground truth read from `pg_catalog`/`information_schema` — nothing was written.

## 1. Key facts

- **Server:** `aws-0-eu-north-1.pooler.supabase.com:5432`, db `postgres`, PostgreSQL 17.4 (aarch64), reached over SSL with `PGSSLMODE=require`.
- **Schema:** 51 tables, 20 views, 6 enum types, 42 user triggers, 243 indexes, 150 RLS policies on 46 RLS-enabled tables, 202 functions, 71 foreign keys, 129 check constraints, 1 sequence, 9 extensions in `public`; standard Supabase schemas (`auth`, `storage`, `realtime`, `graphql`, `cron`, `vault`, `net`, `supabase_migrations`, `extensions`, `graphql_public`) also present.
- **Migrations:** 465 recorded in `supabase_migrations.schema_migrations` vs 461 standard `.sql` files in `reigh-app/supabase/migrations/`. **4 migrations were applied to prod but are missing from the repo** (see §4).
- **No reverse drift:** every live table/enum/trigger maps to an applied migration (with the manual `_applied_` exception for `external_api_keys`).
- **Task pipeline core (13 tables):** `tasks`, `task_types`, `workers`, `system_logs`, `generations`, `generation_variants`, `shot_generations`, `shots`, `attempts`, `shot_slots`, `projects`, `users`, `credits_ledger`.
- **Row-scale (pg_class estimates):** `sentinel_ticks` 138k, `slot_first_migration_map` 121k, `attempts` 84k, `shot_data_audit` 83k, `system_logs` 67k, `tasks` 46k, `generation_variants` 40k, `generations` 38k, `shot_slots` 38k, `credits_ledger` 21k.

## 2. Connection method (no secrets)

| Item | Value |
|---|---|
| Tool | `/Library/PostgreSQL/16/bin/psql` (v16 client, installed on workstation) |
| URL source | `DATABASE_URL` key in `reigh-app/.env` (key present; also `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` present — values never printed) |
| Connection | `postgresql://postgres.<project-ref>:<redacted>@aws-0-eu-north-1.pooler.supabase.com:5432/postgres` |
| TLS | `PGSSLMODE=require` (Supabase pooler requires it) |
| User | `postgres.<project-ref>` (Supabase pooler user) |
| Password | `<redacted>` — sourced from `.env`, passed via `PGPASSWORD` env var, never on the command line |
| Timeout | `statement_timeout=30000` per session (read-only guard) |
| What was run | `SELECT`-only against `information_schema` / `pg_catalog`; no DML, no DDL, no transaction writes |
| Local dev DB | **None found**: `localhost:54322` refused connection; Docker daemon not running; `supabase status` could not inspect containers |

The debug tooling uses the same path: `reigh-app/scripts/debug/commands/sql.py` connects with `psycopg2.connect(os.getenv("DATABASE_URL"))`; `docs/debug-cli.md` documents `debug.py sql "..."` as raw SQL access (requires `DATABASE_URL`).

## 3. Full live schema dump

### 3.1 Tables and columns (51 tables, 547 columns)

#### `agent_node_catalog_metadata`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `agent_node_id` | uuid | NO | `` |
| `review_status` | text | NO | `'pending'::text` |
| `is_catalog_enabled` | boolean | NO | `false` |
| `is_featured` | boolean | NO | `false` |
| `is_default` | boolean | NO | `false` |
| `is_mandatory` | boolean | NO | `false` |
| `catalog_rank` | integer | NO | `1000` |
| `catalog_label` | text | yes | `` |
| `catalog_summary` | text | yes | `` |
| `service_metadata` | jsonb | NO | `'{}'::jsonb` |
| `reviewed_at` | timestamp with time zone | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `agent_node_install_targets`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `agent_node_id` | uuid | NO | `` |
| `label` | text | yes | `` |
| `source_type` | text | NO | `'git'::text` |
| `repo_url` | text | yes | `` |
| `manifest_url` | text | yes | `` |
| `archive_url` | text | yes | `` |
| `commit_sha` | text | yes | `` |
| `tag` | text | yes | `` |
| `branch` | text | yes | `` |
| `source_ref` | text | yes | `` |
| `manifest_path` | text | yes | `` |
| `expected_node_id` | text | NO | `` |
| `install_subdir` | text | yes | `` |
| `is_enabled` | boolean | NO | `false` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `agent_node_media`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `agent_node_id` | uuid | NO | `` |
| `owner_user_id` | uuid | NO | `` |
| `media_type` | text | NO | `` |
| `storage_bucket` | text | NO | `'agent-node-media'::text` |
| `storage_path` | text | NO | `` |
| `mime_type` | text | NO | `` |
| `file_size_bytes` | bigint | NO | `` |
| `width` | integer | yes | `` |
| `height` | integer | yes | `` |
| `duration_seconds` | numeric(10,3) | yes | `` |
| `alt_text` | text | yes | `` |
| `caption` | text | yes | `` |
| `display_order` | integer | NO | `0` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `agent_nodes`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `owner_user_id` | uuid | NO | `` |
| `slug` | text | NO | `` |
| `name` | text | NO | `` |
| `node_type` | text | NO | `'agent'::text` |
| `short_description` | text | yes | `` |
| `description` | text | yes | `` |
| `repo_url` | text | NO | `` |
| `expected_manifest_id` | text | NO | `` |
| `manifest` | jsonb | NO | `'{}'::jsonb` |
| `details` | jsonb | NO | `'{}'::jsonb` |
| `creator_discord_id` | text | yes | `` |
| `creator_display_name` | text | yes | `` |
| `is_public` | boolean | NO | `false` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `attempts`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `slot_id` | uuid | NO | `` |
| `project_id` | uuid | NO | `` |
| `task_id` | uuid | yes | `` |
| `params` | jsonb | yes | `` |
| `params_prompt` | text | yes | `(params ->> 'prompt'::text)` |
| `params_seed` | bigint | yes | `safe_bigint_from_text((params ->> 'seed'::text))` |
| `params_model` | text | yes | `(params ->> 'model'::text)` |
| `output_url` | text | yes | `` |
| `output_bucket` | text | yes | `` |
| `output_path` | text | yes | `` |
| `thumbnail_url` | text | yes | `` |
| `thumbnail_bucket` | text | yes | `` |
| `thumbnail_path` | text | yes | `` |
| `storage_mode` | attempt_storage_mode | NO | `'remote'::attempt_storage_mode` |
| `local_handle_id` | uuid | yes | `` |
| `local_file_name` | text | yes | `` |
| `local_file_size` | bigint | yes | `` |
| `local_file_mime` | text | yes | `` |
| `legacy_url_only` | boolean | NO | `false` |
| `status` | attempt_status | NO | `'queued'::attempt_status` |
| `attempt_type` | attempt_type | NO | `'original'::attempt_type` |
| `based_on` | uuid | yes | `` |
| `parent_attempt_id` | uuid | yes | `` |
| `child_order` | integer | yes | `` |
| `pair_shot_attempt_id` | uuid | yes | `` |
| `starred` | boolean | NO | `false` |
| `name` | text | yes | `` |
| `error_message` | text | yes | `` |
| `viewed_at` | timestamp with time zone | yes | `` |
| `superseded_by` | uuid | yes | `` |
| `deleted_at` | timestamp with time zone | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `credits_ledger`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `task_id` | uuid | yes | `` |
| `amount` | numeric(10,3) | NO | `` |
| `type` | credit_ledger_type | NO | `` |
| `metadata` | jsonb | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |

#### `dev_tasks`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `title` | text | NO | `` |
| `description` | text | yes | `` |
| `status` | text | NO | `'backlog'::text` |
| `area` | text | yes | `` |
| `notes` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `completed_at` | timestamp with time zone | yes | `` |
| `commit_hash` | text | yes | `` |
| `execution_details` | jsonb | yes | `` |
| `discord_thread_id` | text | yes | `` |

#### `divergence_log`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `timeline_id` | uuid | NO | `` |
| `spoke` | text | NO | `` |
| `spoke_version` | integer | NO | `0` |
| `spoke_hash` | text | yes | `` |
| `spoke_event_id` | text | yes | `` |
| `hub_version` | integer | NO | `0` |
| `hub_hash` | text | yes | `` |
| `hub_event_id` | text | yes | `` |
| `spoke_suffix` | jsonb | NO | `` |
| `hub_suffix` | jsonb | NO | `` |
| `chosen_side` | text | NO | `'undecided'::text` |
| `artifact_pointer` | jsonb | yes | `` |
| `created_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `resolved_at` | timestamp with time zone | yes | `` |

#### `effects`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `name` | text | NO | `` |
| `slug` | text | NO | `` |
| `code` | text | NO | `` |
| `category` | text | NO | `` |
| `description` | text | yes | `` |
| `is_public` | boolean | NO | `false` |
| `created_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |

#### `extension_install_state`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `timeline_id` | uuid | NO | `` |
| `extension_id` | text | NO | `` |
| `enabled` | boolean | NO | `true` |
| `installed_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `last_toggled_at` | timestamp with time zone | yes | `` |
| `toggle_reason` | text | yes | `` |
| `pack_version` | text | yes | `` |
| `schema_version` | integer | NO | `1` |
| `metadata` | jsonb | NO | `'{}'::jsonb` |

#### `extension_proposals`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `timeline_id` | uuid | NO | `` |
| `extension_id` | text | NO | `` |
| `status` | text | NO | `'draft'::text` |
| `payload` | jsonb | NO | `'{}'::jsonb` |
| `label` | text | yes | `` |
| `schema_version` | integer | NO | `1` |
| `created_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `base_version` | integer | NO | `1` |
| `expires_at` | timestamp with time zone | yes | `` |
| `accepted_at` | timestamp with time zone | yes | `` |
| `rejected_at` | timestamp with time zone | yes | `` |

#### `extension_settings`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `timeline_id` | uuid | NO | `` |
| `extension_id` | text | NO | `` |
| `schema_version` | integer | NO | `` |
| `values` | jsonb | NO | `'{}'::jsonb` |
| `last_written_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `created_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |

#### `external_api_keys`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `service` | character varying(50) | NO | `` |
| `key_value` | text | NO | `` |
| `metadata` | jsonb | yes | `'{}'::jsonb` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |
| `vault_secret_id` | uuid | yes | `` |

#### `generation_variants`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `generation_id` | uuid | NO | `` |
| `location` | text | NO | `` |
| `thumbnail_url` | text | yes | `` |
| `params` | jsonb | yes | `` |
| `is_primary` | boolean | NO | `false` |
| `variant_type` | text | yes | `` |
| `name` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `project_id` | uuid | yes | `` |
| `viewed_at` | timestamp with time zone | yes | `` |
| `starred` | boolean | NO | `false` |

#### `generations`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `tasks` | jsonb | yes | `` |
| `params` | jsonb | yes | `` |
| `location` | text | yes | `` |
| `type` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | yes | `` |
| `project_id` | uuid | NO | `` |
| `starred` | boolean | NO | `false` |
| `thumbnail_url` | text | yes | `` |
| `name` | text | yes | `` |
| `based_on` | uuid | yes | `` |
| `copied_from_share` | text | yes | `` |
| `shot_data` | jsonb | yes | `'{}'::jsonb` |
| `parent_generation_id` | uuid | yes | `` |
| `child_order` | integer | yes | `` |
| `is_child` | boolean | NO | `false` |
| `children` | jsonb | yes | `` |
| `primary_variant_id` | uuid | yes | `` |
| `pair_shot_generation_id` | uuid | yes | `` |
| `storage_mode` | text | NO | `'remote'::text` |
| `local_handle_id` | uuid | yes | `` |
| `local_file_name` | text | yes | `` |
| `local_file_size` | bigint | yes | `` |
| `local_file_mime` | text | yes | `` |

#### `local_media_handles`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `project_id` | uuid | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |

#### `model_family_for_model`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `model_name` | text | NO | `` |
| `route_family` | text | NO | `` |

#### `onboarding_config`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `key` | text | NO | `` |
| `value` | jsonb | NO | `` |
| `updated_at` | timestamp with time zone | yes | `now()` |

#### `pause_scaling`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `pool` | text | NO | `` |
| `until` | timestamp with time zone | NO | `` |
| `reason` | text | yes | `` |

#### `projects`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `name` | text | NO | `` |
| `user_id` | uuid | NO | `` |
| `aspect_ratio` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `settings` | jsonb | yes | `` |

#### `rate_limits`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `key` | text | NO | `` |
| `count` | integer | NO | `1` |
| `window_start` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `referral_sessions`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `referrer_username` | text | NO | `` |
| `referrer_user_id` | uuid | yes | `` |
| `visitor_fingerprint` | text | yes | `` |
| `session_id` | text | yes | `` |
| `visitor_ip` | inet | yes | `` |
| `first_visit_at` | timestamp with time zone | yes | `now()` |
| `last_visit_at` | timestamp with time zone | yes | `now()` |
| `visit_count` | integer | yes | `1` |
| `converted_at` | timestamp with time zone | yes | `` |
| `converted_user_id` | uuid | yes | `` |
| `is_latest_referrer` | boolean | yes | `true` |

#### `referrals`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `referrer_id` | uuid | NO | `` |
| `referred_id` | uuid | NO | `` |
| `referrer_username` | text | NO | `` |
| `session_id` | uuid | yes | `` |
| `created_at` | timestamp with time zone | yes | `now()` |

#### `resources`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `type` | text | NO | `` |
| `metadata` | jsonb | NO | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `is_public` | boolean | NO | `false` |
| `generation_id` | uuid | yes | `` |

#### `route_alias_map`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `alias` | text | NO | `` |
| `route_key` | text | NO | `` |

#### `route_backend_capabilities`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `backend` | text | NO | `` |
| `route_key` | text | NO | `` |
| `supports_route` | boolean | NO | `false` |
| `supports_missing_selector` | boolean | NO | `false` |
| `enabled` | boolean | NO | `true` |
| `capability_version` | bigint | NO | `1` |
| `expires_at` | timestamp with time zone | yes | `` |
| `min_worker_version` | text | yes | `` |
| `metadata` | jsonb | NO | `'{}'::jsonb` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |
| `updated_by` | uuid | yes | `` |

#### `route_backend_selectors`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `selector_namespace` | text | NO | `'production'::text` |
| `route_key` | text | NO | `` |
| `selected_backend` | text | NO | `` |
| `selector_version` | bigint | NO | `` |
| `enabled` | boolean | NO | `true` |
| `expires_at` | timestamp with time zone | yes | `` |
| `min_worker_version` | text | yes | `` |
| `reason` | text | yes | `` |
| `metadata` | jsonb | NO | `'{}'::jsonb` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |
| `updated_by` | uuid | yes | `` |

#### `sentinel_ticks`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `ts` | timestamp with time zone | NO | `now()` |
| `state` | text | NO | `` |
| `detail` | jsonb | yes | `` |

#### `settings`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `key` | text | NO | `` |
| `value` | text | NO | `` |

#### `shared_generations`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `share_slug` | text | NO | `` |
| `task_id` | uuid | yes | `` |
| `generation_id` | uuid | NO | `` |
| `creator_id` | uuid | yes | `` |
| `created_at` | timestamp with time zone | yes | `now()` |
| `view_count` | integer | yes | `0` |
| `last_viewed_at` | timestamp with time zone | yes | `` |
| `cached_generation_data` | jsonb | yes | `` |
| `cached_task_data` | jsonb | yes | `` |
| `creator_username` | text | yes | `` |
| `creator_name` | text | yes | `` |
| `creator_avatar_url` | text | yes | `` |
| `shot_id` | uuid | yes | `` |

#### `shot_data_audit`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | integer | NO | `nextval('shot_data_audit_id_seq'::regclass)` |
| `generation_id` | uuid | yes | `` |
| `old_shot_data` | jsonb | yes | `` |
| `new_shot_data` | jsonb | yes | `` |
| `operation` | text | yes | `` |
| `changed_by` | text | yes | `` |
| `created_at` | timestamp with time zone | yes | `now()` |

#### `shot_generations`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `shot_id` | uuid | NO | `` |
| `generation_id` | uuid | NO | `` |
| `created_at` | timestamp with time zone | yes | `now()` |
| `timeline_frame` | integer | yes | `` |
| `metadata` | jsonb | yes | `` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `shot_slots`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `project_id` | uuid | NO | `` |
| `shot_id` | uuid | yes | `` |
| `position_index` | integer | NO | `` |
| `kind` | shot_slot_kind | NO | `` |
| `primary_attempt_id` | uuid | yes | `` |
| `timeline_frame` | integer | yes | `` |
| `metadata` | jsonb | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |

#### `shots`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `name` | text | NO | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | yes | `` |
| `project_id` | uuid | NO | `` |
| `settings` | jsonb | yes | `` |
| `position` | integer | NO | `1` |
| `aspect_ratio` | text | yes | `` |

#### `slot_first_migration_map`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `legacy_table` | text | NO | `` |
| `legacy_id` | uuid | NO | `` |
| `slot_id` | uuid | yes | `` |
| `attempt_id` | uuid | yes | `` |
| `duplicate_group_key` | text | yes | `` |
| `notes` | text | yes | `` |
| `migrated_at` | timestamp with time zone | NO | `now()` |

#### `sync_bookmarks`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `timeline_id` | uuid | NO | `` |
| `spoke` | text | NO | `` |
| `spoke_version` | integer | NO | `0` |
| `spoke_hash` | text | yes | `` |
| `spoke_event_id` | text | yes | `` |
| `hub_version` | integer | NO | `0` |
| `hub_hash` | text | yes | `` |
| `hub_event_id` | text | yes | `` |
| `synced_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `created_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |

#### `system_logs`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `timestamp` | timestamp with time zone | NO | `now()` |
| `source_type` | text | NO | `` |
| `source_id` | text | NO | `` |
| `log_level` | text | NO | `` |
| `message` | text | NO | `` |
| `task_id` | uuid | yes | `` |
| `worker_id` | text | yes | `` |
| `cycle_number` | integer | yes | `` |
| `metadata` | jsonb | yes | `'{}'::jsonb` |

#### `task_types`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `name` | text | NO | `` |
| `run_type` | text | NO | `'gpu'::text` |
| `category` | text | NO | `` |
| `display_name` | text | NO | `` |
| `description` | text | yes | `` |
| `base_cost_per_second` | numeric(10,6) | NO | `` |
| `cost_factors` | jsonb | yes | `'{}'::jsonb` |
| `is_active` | boolean | yes | `true` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |
| `billing_type` | text | NO | `'per_second'::text` |
| `unit_cost` | numeric(10,6) | yes | `NULL::numeric` |
| `tool_type` | text | yes | `` |
| `content_type` | text | yes | `` |
| `is_visible` | boolean | yes | `false` |
| `supports_progress` | boolean | yes | `false` |
| `variant_type` | text | yes | `` |

#### `tasks`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `task_type` | text | NO | `` |
| `params` | jsonb | NO | `` |
| `status` | task_status | NO | `'Queued'::task_status` |
| `dependant_on` | uuid[] | yes | `` |
| `output_location` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | yes | `` |
| `project_id` | uuid | NO | `` |
| `generation_processed_at` | timestamp with time zone | yes | `` |
| `worker_id` | text | yes | `` |
| `generation_started_at` | timestamp with time zone | yes | `` |
| `generation_created` | boolean | NO | `false` |
| `attempts` | integer | NO | `0` |
| `error_message` | text | yes | `` |
| `result_data` | jsonb | yes | `'{}'::jsonb` |
| `copied_from_share` | text | yes | `` |
| `idempotency_key` | text | yes | `` |
| `materialized_inputs` | jsonb | yes | `` |
| `selector_namespace` | text | yes | `` |
| `route_key` | text | yes | `` |
| `selected_backend` | text | yes | `` |
| `selector_version` | bigint | yes | `` |
| `route_selection_snapshot` | jsonb | yes | `` |
| `claimed_backend` | text | yes | `` |
| `claimed_selector_namespace` | text | yes | `` |
| `claimed_route_key` | text | yes | `` |
| `claimed_selector_version` | bigint | yes | `` |
| `claimed_capability_version` | bigint | yes | `` |
| `claim_decision_reason` | text | yes | `` |
| `claim_decision_snapshot` | jsonb | yes | `` |
| `support_state` | text | yes | `` |
| `selected_profile` | text | yes | `` |
| `selected_template_id` | text | yes | `` |
| `route_run_id` | text | yes | `` |
| `worker_contract_version` | integer | yes | `` |
| `prompt` | text | yes | `(params ->> 'prompt'::text)` |
| `seed` | bigint | yes | `safe_bigint_from_text((params ->> 'seed'::text))` |
| `model` | text | yes | `(params ->> 'model'::text)` |

#### `timeline_agent_sessions`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `timeline_id` | uuid | NO | `` |
| `user_id` | uuid | NO | `` |
| `status` | text | NO | `'waiting_user'::text` |
| `turns` | jsonb | NO | `'[]'::jsonb` |
| `model` | text | NO | `'groq'::text` |
| `summary` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | NO | `now()` |
| `cancelled_at` | timestamp with time zone | yes | `` |
| `cancelled_by` | uuid | yes | `` |
| `cancel_source` | text | yes | `` |
| `cancel_reason` | text | yes | `` |
| `proposal_policy` | text | yes | `` |

#### `timeline_checkpoints`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `timeline_id` | uuid | NO | `` |
| `user_id` | uuid | NO | `` |
| `config` | jsonb | NO | `` |
| `trigger_type` | text | NO | `` |
| `label` | text | NO | `` |
| `edits_since_last_checkpoint` | integer | NO | `0` |
| `created_at` | timestamp with time zone | NO | `now()` |

#### `timeline_event_contract`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | integer | NO | `` |
| `current_schema_version` | integer | NO | `` |

#### `timeline_events`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `event_id` | text | NO | `` |
| `timeline_id` | uuid | NO | `` |
| `version` | integer | NO | `` |
| `prev_hash` | text | yes | `` |
| `hash` | text | NO | `` |
| `kind` | text | NO | `` |
| `payload` | jsonb | NO | `` |
| `schema_version` | integer | NO | `` |
| `idempotency_key` | text | yes | `` |
| `ts` | timestamp with time zone | NO | `` |
| `actor` | jsonb | NO | `'{}'::jsonb` |
| `expected_version` | integer | yes | `` |
| `txn_id` | uuid | yes | `` |
| `source_backend` | text | yes | `` |
| `source_timeline_id` | text | yes | `` |
| `source_event_id` | text | yes | `` |
| `source_version` | integer | yes | `` |
| `source_hash` | text | yes | `` |

#### `timeline_update_log`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `generation_id` | uuid | NO | `` |
| `shot_id` | uuid | yes | `` |
| `old_timeline_frame` | integer | yes | `` |
| `new_timeline_frame` | integer | yes | `` |
| `operation_type` | text | NO | `` |
| `call_source` | text | yes | `` |
| `metadata` | jsonb | yes | `` |
| `created_at` | timestamp with time zone | yes | `now()` |

#### `timelines`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `project_id` | uuid | NO | `` |
| `user_id` | uuid | NO | `` |
| `name` | text | NO | `` |
| `config` | jsonb | NO | `` |
| `asset_registry` | jsonb | NO | `'{"assets": {}}'::jsonb` |
| `created_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `updated_at` | timestamp with time zone | NO | `timezone('utc'::text, now())` |
| `config_version` | integer | NO | `1` |

#### `training_data`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `original_filename` | text | NO | `` |
| `storage_location` | text | NO | `` |
| `duration` | integer | yes | `` |
| `metadata` | jsonb | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | yes | `` |
| `batch_id` | uuid | yes | `` |

#### `training_data_batches`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `name` | text | NO | `` |
| `description` | text | yes | `` |
| `metadata` | jsonb | yes | `'{}'::jsonb` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | yes | `` |

#### `training_data_segments`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `training_data_id` | uuid | NO | `` |
| `start_time` | integer | NO | `` |
| `end_time` | integer | NO | `` |
| `segment_location` | text | yes | `` |
| `description` | text | yes | `` |
| `metadata` | jsonb | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `updated_at` | timestamp with time zone | yes | `` |

#### `user_api_tokens`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `gen_random_uuid()` |
| `user_id` | uuid | NO | `` |
| `label` | text | yes | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `token` | text | NO | `` |

#### `users`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | uuid | NO | `` |
| `name` | text | yes | `` |
| `email` | text | yes | `` |
| `api_keys` | jsonb | yes | `` |
| `settings` | jsonb | yes | `` |
| `credits` | numeric(10,3) | NO | `0` |
| `given_credits` | boolean | NO | `false` |
| `onboarding` | jsonb | NO | `'{}'::jsonb` |
| `stripe_customer_id` | text | yes | `` |
| `stripe_payment_method_id` | text | yes | `` |
| `auto_topup_enabled` | boolean | NO | `false` |
| `auto_topup_amount` | integer | yes | `` |
| `auto_topup_threshold` | integer | yes | `` |
| `auto_topup_last_triggered` | timestamp with time zone | yes | `` |
| `username` | text | yes | `` |
| `avatar_url` | text | yes | `` |
| `auto_topup_setup_completed` | boolean | NO | `false` |
| `onboarding_completed` | boolean | NO | `false` |

#### `workers`

| Column | Type | Nullable | Default / identity |
|---|---|---|---|
| `id` | text | NO | `` |
| `instance_type` | text | NO | `` |
| `created_at` | timestamp with time zone | NO | `now()` |
| `last_heartbeat` | timestamp with time zone | yes | `` |
| `status` | text | NO | `'active'::text` |
| `metadata` | jsonb | yes | `'{}'::jsonb` |
| `current_model` | text | yes | `` |

### 3.2 Enum types (6)

| Type | Values |
|---|---|
| `attempt_status` | `queued`, `in_progress`, `complete`, `failed`, `cancelled` |
| `attempt_storage_mode` | `remote`, `local`, `uploading` |
| `attempt_type` | `original`, `regen`, `edit`, `upscale`, `reposition`, `duplicate` |
| `credit_ledger_type` | `stripe`, `manual`, `spend`, `refund`, `auto_topup` |
| `shot_slot_kind` | `image`, `video_segment`, `timeline_placement`, `project_asset` |
| `task_status` | `Queued`, `In Progress`, `Complete`, `Failed`, `Cancelled` |

> Only the `attempt_*` and `task_status` columns are real Postgres enums. `tasks.status` is the enum `task_status` with capitalized values (`Queued`/`In Progress`/`Complete`/`Failed`/`Cancelled`), while `attempts.status` uses lowercase (`queued`/`in_progress`/`complete`/`failed`/`cancelled`) — two different conventions live side by side.
### 3.3 Views (20)

| View | Definition (first 200 chars) |
|---|---|
| `active_workers_health` | ` SELECT w.id,     w.instance_type,     w.status,     w.created_at,     w.last_heartbeat,         CASE             WHEN (w.last_heartbeat IS NOT NULL) THEN EXTRACT(epoch FROM (now() - w.last_heartbeat)...` |
| `normalized_task_status` | ` SELECT id,         CASE             WHEN (status = 'Complete'::task_status) THEN 'Complete'::task_status             WHEN (status = 'In Progress'::task_status) THEN 'In Progress'::task_status        ...` |
| `orchestrator_status` | ` SELECT count(         CASE             WHEN (status = 'Queued'::task_status) THEN 1             ELSE NULL::integer         END) AS queued_tasks,     count(         CASE             WHEN (status = 'In...` |
| `project_asset_compositions` | ` SELECT ss.project_id,     ss.shot_id,     ss.id AS slot_id,     ss.position_index,     ss.kind,     ss.timeline_frame,     ss.metadata AS slot_metadata,     ss.primary_attempt_id,     ss.created_at A...` |
| `public_agent_node_catalog` | ` SELECT node.id,     node.slug,     node.name,     node.node_type,     node.short_description,     node.description,     node.repo_url,     node.expected_manifest_id,     node.creator_discord_id,     ...` |
| `public_agent_node_install_targets` | ` SELECT target.id,     target.agent_node_id,     target.label,     target.source_type,     target.repo_url,     target.manifest_url,     target.archive_url,     target.commit_sha,     target.tag,     ...` |
| `public_agent_node_media` | ` SELECT media.id,     media.agent_node_id,     media.media_type,     media.storage_bucket,     media.storage_path,     media.mime_type,     media.file_size_bytes,     media.width,     media.height,   ...` |
| `recent_task_activity` | ` SELECT t.id,     t.status,     t.task_type,     COALESCE(t.attempts, 0) AS attempts,     t.worker_id,     t.created_at,     t.generation_started_at,     t.generation_processed_at,     t.updated_at,  ...` |
| `referral_stats` | ` SELECT u.id,     u.username,     u.name,     count(DISTINCT rs.id) AS total_visits,     count(DISTINCT rs.id) FILTER (WHERE (rs.converted_at IS NOT NULL)) AS conversions,     count(DISTINCT r.id) AS ...` |
| `shot_compositions` | ` SELECT ss.project_id,     ss.shot_id,     ss.id AS slot_id,     ss.position_index,     ss.kind,     ss.timeline_frame,     ss.metadata AS slot_metadata,     ss.primary_attempt_id,     ss.created_at A...` |
| `shot_final_videos` | ` SELECT DISTINCT ON (g.id) g.id,         CASE             WHEN ((timeline_img.positioned_image_count <= 2) AND (child_agg.child_count = 1) AND (child_agg.child_location IS NOT NULL) AND (child_agg.chi...` |
| `shot_generations_with_computed_position` | ` SELECT id,     shot_id,     generation_id,     timeline_frame,     metadata,     created_at,     COALESCE((timeline_frame)::bigint, ((row_number() OVER (PARTITION BY shot_id ORDER BY created_at) - 1)...` |
| `shot_statistics` | ` SELECT s.id AS shot_id,     s.project_id,     count(sg.id) AS total_generations,     count(sg.id) FILTER (WHERE (sg.timeline_frame IS NOT NULL)) AS positioned_count,     count(sg.id) FILTER (WHERE ((...` |
| `slot_first_health` | ` WITH slot_groups AS (          SELECT ss.project_id,             ss.shot_id,             ss.kind,             count(*) AS slot_count,             min(ss.position_index) AS min_position,             m...` |
| `task_queue_analysis` | ` SELECT task_type,     status,     count(*) AS task_count,         CASE             WHEN (status = 'Queued'::task_status) THEN avg((EXTRACT(epoch FROM (now() - created_at)) / 60.0))             ELSE N...` |
| `task_types_with_billing` | ` SELECT id,     name,     run_type,     category,     display_name,     description,     billing_type,         CASE             WHEN (billing_type = 'per_second'::text) THEN base_cost_per_second      ...` |
| `user_credit_balance` | ` SELECT user_id,     sum(amount) AS balance    FROM credits_ledger   GROUP BY user_id;...` |
| `v_recent_errors` | ` SELECT source_type,     source_id,     worker_id,     task_id,     count(*) AS error_count,     max("timestamp") AS last_error_time,     array_agg(DISTINCT message ORDER BY message) AS unique_message...` |
| `v_worker_log_activity` | ` SELECT w.id AS worker_id,     w.status,     w.last_heartbeat,     count(l.id) AS log_count,     count(l.id) FILTER (WHERE (l.log_level = 'ERROR'::text)) AS error_count,     count(l.id) FILTER (WHERE ...` |
| `worker_performance` | ` SELECT w.id AS worker_id,     w.instance_type,     w.status,     w.created_at AS worker_created_at,     w.last_heartbeat,     count(t.id) AS total_tasks_processed,     count(         CASE            ...` |

### 3.4 Triggers (42 user triggers)

| Table | Trigger | Timing/Level | Function |
|---|---|---|---|
| `agent_node_catalog_metadata` | `agent_node_catalog_metadata_owner_guard` | BEFORE ROW | `agent_node_catalog_metadata_owner_guard` |
| `agent_node_catalog_metadata` | `agent_node_catalog_touch_updated_at` | BEFORE STATEMENT | `agent_nodes_touch_updated_at` |
| `agent_node_install_targets` | `agent_node_install_targets_owner_guard` | BEFORE ROW | `agent_node_install_targets_owner_guard` |
| `agent_node_install_targets` | `agent_node_install_targets_touch_updated_at` | BEFORE STATEMENT | `agent_nodes_touch_updated_at` |
| `agent_node_media` | `agent_node_media_touch_updated_at` | BEFORE STATEMENT | `agent_nodes_touch_updated_at` |
| `agent_nodes` | `agent_nodes_touch_updated_at` | BEFORE STATEMENT | `agent_nodes_touch_updated_at` |
| `attempts` | `attempts_010_project_consistency` | BEFORE ROW | `slot_first_attempts_project_consistency` |
| `attempts` | `attempts_020_lineage_acyclic` | BEFORE ROW | `slot_first_check_lineage_acyclic` |
| `attempts` | `attempts_021_parent_acyclic` | BEFORE ROW | `slot_first_check_parent_acyclic` |
| `attempts` | `attempts_030_lineage_boundaries` | BEFORE ROW | `slot_first_validate_attempt_lineage_boundaries` |
| `attempts` | `attempts_040_prevent_primary_invalidation` | BEFORE STATEMENT | `slot_first_prevent_primary_attempt_invalidation` |
| `attempts` | `attempts_041_prevent_primary_delete` | BEFORE STATEMENT | `slot_first_prevent_primary_attempt_delete` |
| `attempts` | `attempts_updated_at` | BEFORE STATEMENT | `slot_first_set_updated_at` |
| `credits_ledger` | `credits_ledger_after_delete` | AFTER STATEMENT | `refresh_user_balance` |
| `credits_ledger` | `credits_ledger_after_insert` | AFTER ROW | `refresh_user_balance` |
| `credits_ledger` | `credits_ledger_after_update` | AFTER STATEMENT | `refresh_user_balance` |
| `external_api_keys` | `update_external_api_keys_updated_at` | BEFORE STATEMENT | `update_external_api_keys_updated_at` |
| `generation_variants` | `trg_auto_view_manual_upload` | BEFORE ROW | `auto_view_manual_upload_variant` |
| `generation_variants` | `trg_clear_primary_variant_ref` | BEFORE STATEMENT | `clear_primary_variant_reference` |
| `generation_variants` | `trg_handle_variant_deletion` | AFTER STATEMENT | `handle_variant_deletion` |
| `generation_variants` | `trg_handle_variant_primary_switch` | BEFORE ROW | `handle_variant_primary_switch` |
| `generation_variants` | `trg_prevent_original_variant_deletion` | BEFORE STATEMENT | `prevent_original_variant_deletion` |
| `generation_variants` | `trg_sync_generation_from_variant` | AFTER ROW | `sync_generation_from_primary_variant` |
| `generation_variants` | `trigger_set_variant_project_id` | BEFORE ROW | `set_variant_project_id` |
| `generations` | `audit_shot_data_trigger` | AFTER ROW | `audit_shot_data_changes` |
| `generations` | `trg_sync_variant_from_generation` | AFTER STATEMENT | `sync_variant_from_generation_update` |
| `onboarding_config` | `onboarding_config_updated_at` | BEFORE STATEMENT | `update_onboarding_config_updated_at` |
| `projects` | `auto_create_user_trigger` | BEFORE ROW | `auto_create_user_before_project` |
| `shot_generations` | `auto_demote_on_timeline_remove` | AFTER STATEMENT | `trigger_demote_on_timeline_remove` |
| `shot_generations` | `sync_shot_generations_jsonb_row` | AFTER ROW | `sync_shot_to_generation_jsonb` |
| `shot_generations` | `sync_shot_generations_update_batch` | AFTER STATEMENT | `sync_shot_data_update_batch` |
| `shot_slots` | `shot_slots_010_project_consistency` | BEFORE ROW | `slot_first_shot_slots_project_consistency` |
| `shot_slots` | `shot_slots_020_validate_primary` | BEFORE ROW | `slot_first_validate_primary_pointer` |
| `shot_slots` | `shot_slots_900_enforce_density` | AFTER ROW | `slot_first_enforce_slot_density` |
| `shot_slots` | `shot_slots_updated_at` | BEFORE STATEMENT | `slot_first_set_updated_at` |
| `shots` | `shots_010_prevent_slot_project_drift` | BEFORE STATEMENT | `slot_first_prevent_shot_project_drift` |
| `shots` | `trg_ensure_shot_parent_generation` | AFTER ROW | `ensure_shot_parent_generation_after_insert` |
| `shots` | `trigger_set_shot_position` | BEFORE ROW | `set_new_shot_position` |
| `tasks` | `prevent_timing_manipulation_trigger` | BEFORE STATEMENT | `prevent_timing_manipulation` |
| `tasks` | `trigger_bill_cancelled_orchestrator` | AFTER STATEMENT | `bill_cancelled_orchestrator` |
| `users` | `auto_topup_trigger` | AFTER STATEMENT | `check_auto_topup_trigger` |
| `users` | `prevent_credit_manipulation` | BEFORE STATEMENT | `prevent_direct_credit_updates` |

### 3.5 Indexes (243)

**`agent_node_catalog_metadata`** (4 indexes)

- `CREATE INDEX agent_node_catalog_default_mandatory_idx ON public.agent_node_catalog_metadata USING btree (is_mandatory DESC, catalog_rank, agent_node_id) WHERE (is_catalog_enabled AND (review_status = 'approved'::text) AND is_default)`
- `CREATE INDEX agent_node_catalog_featured_idx ON public.agent_node_catalog_metadata USING btree (catalog_rank, agent_node_id) WHERE (is_catalog_enabled AND (review_status = 'approved'::text) AND is_featured)`
- `CREATE UNIQUE INDEX agent_node_catalog_metadata_pkey ON public.agent_node_catalog_metadata USING btree (agent_node_id)`
- `CREATE INDEX agent_node_catalog_public_filter_idx ON public.agent_node_catalog_metadata USING btree (is_catalog_enabled, review_status, is_default, is_mandatory, is_featured, catalog_rank, agent_node_id)`

**`agent_node_install_targets`** (3 indexes)

- `CREATE INDEX agent_node_install_targets_enabled_idx ON public.agent_node_install_targets USING btree (agent_node_id, source_type, created_at DESC) WHERE is_enabled`
- `CREATE INDEX agent_node_install_targets_node_idx ON public.agent_node_install_targets USING btree (agent_node_id, created_at DESC)`
- `CREATE UNIQUE INDEX agent_node_install_targets_pkey ON public.agent_node_install_targets USING btree (id)`

**`agent_node_media`** (5 indexes)

- `CREATE INDEX agent_node_media_order_idx ON public.agent_node_media USING btree (agent_node_id, display_order, created_at, id)`
- `CREATE INDEX agent_node_media_owner_idx ON public.agent_node_media USING btree (owner_user_id, created_at DESC)`
- `CREATE UNIQUE INDEX agent_node_media_pkey ON public.agent_node_media USING btree (id)`
- `CREATE UNIQUE INDEX agent_node_media_storage_path_unique_idx ON public.agent_node_media USING btree (storage_bucket, storage_path)`
- `CREATE INDEX agent_node_media_type_idx ON public.agent_node_media USING btree (agent_node_id, media_type, display_order)`

**`agent_nodes`** (7 indexes)

- `CREATE INDEX agent_nodes_owner_created_idx ON public.agent_nodes USING btree (owner_user_id, created_at DESC)`
- `CREATE UNIQUE INDEX agent_nodes_owner_expected_manifest_unique ON public.agent_nodes USING btree (id, expected_manifest_id)`
- `CREATE UNIQUE INDEX agent_nodes_owner_integrity_unique ON public.agent_nodes USING btree (id, owner_user_id)`
- `CREATE UNIQUE INDEX agent_nodes_pkey ON public.agent_nodes USING btree (id)`
- `CREATE INDEX agent_nodes_public_browse_idx ON public.agent_nodes USING btree (created_at DESC, id) WHERE is_public`
- `CREATE INDEX agent_nodes_public_slug_idx ON public.agent_nodes USING btree (slug) WHERE is_public`
- `CREATE UNIQUE INDEX agent_nodes_slug_unique_idx ON public.agent_nodes USING btree (lower(slug))`

**`attempts`** (11 indexes)

- `CREATE INDEX attempts_based_on_lookup ON public.attempts USING btree (based_on) WHERE (based_on IS NOT NULL)`
- `CREATE INDEX attempts_pair_shot_lookup ON public.attempts USING btree (pair_shot_attempt_id) WHERE ((pair_shot_attempt_id IS NOT NULL) AND (deleted_at IS NULL))`
- `CREATE INDEX attempts_params_model_recent ON public.attempts USING btree (params_model, created_at DESC) WHERE (params_model IS NOT NULL)`
- `CREATE INDEX attempts_params_prompt_trgm ON public.attempts USING gin (params_prompt gin_trgm_ops) WHERE (params_prompt IS NOT NULL)`
- `CREATE INDEX attempts_parent_lookup ON public.attempts USING btree (parent_attempt_id, child_order, created_at DESC) WHERE ((parent_attempt_id IS NOT NULL) AND (deleted_at IS NULL))`
- `CREATE INDEX attempts_pending_in_slot ON public.attempts USING btree (slot_id, status) WHERE (status = ANY (ARRAY['queued'::attempt_status, 'in_progress'::attempt_status]))`
- `CREATE UNIQUE INDEX attempts_pkey ON public.attempts USING btree (id)`
- `CREATE INDEX attempts_project_recent ON public.attempts USING btree (project_id, created_at DESC) WHERE (deleted_at IS NULL)`
- `CREATE INDEX attempts_project_starred ON public.attempts USING btree (project_id, starred, created_at DESC) WHERE ((starred = true) AND (deleted_at IS NULL))`
- `CREATE INDEX attempts_slot_recent ON public.attempts USING btree (slot_id, created_at DESC, id DESC) WHERE (deleted_at IS NULL)`
- `CREATE INDEX attempts_task_lookup ON public.attempts USING btree (task_id) WHERE ((task_id IS NOT NULL) AND (deleted_at IS NULL))`

**`credits_ledger`** (6 indexes)

- `CREATE UNIQUE INDEX credits_ledger_pkey ON public.credits_ledger USING btree (id)`
- `CREATE INDEX idx_credits_ledger_created_at ON public.credits_ledger USING btree (created_at)`
- `CREATE UNIQUE INDEX idx_credits_ledger_stripe_payment_intent_unique ON public.credits_ledger USING btree (((metadata ->> 'stripe_payment_intent_id'::text))) WHERE ((type = 'auto_topup'::credit_ledger_type) AND ((metadata ->> 'stripe_payment_intent_id'::text) IS NOT NULL))`
- `CREATE UNIQUE INDEX idx_credits_ledger_stripe_session_unique ON public.credits_ledger USING btree (((metadata ->> 'stripe_session_id'::text))) WHERE ((type = 'stripe'::credit_ledger_type) AND ((metadata ->> 'stripe_session_id'::text) IS NOT NULL))`
- `CREATE INDEX idx_credits_ledger_type ON public.credits_ledger USING btree (type)`
- `CREATE INDEX idx_credits_ledger_user_id ON public.credits_ledger USING btree (user_id)`

**`dev_tasks`** (4 indexes)

- `CREATE UNIQUE INDEX dev_tasks_pkey ON public.dev_tasks USING btree (id)`
- `CREATE INDEX idx_dev_tasks_area ON public.dev_tasks USING btree (area) WHERE (area IS NOT NULL)`
- `CREATE INDEX idx_dev_tasks_created ON public.dev_tasks USING btree (created_at DESC)`
- `CREATE INDEX idx_dev_tasks_status ON public.dev_tasks USING btree (status)`

**`divergence_log`** (3 indexes)

- `CREATE UNIQUE INDEX divergence_log_pkey ON public.divergence_log USING btree (id)`
- `CREATE INDEX divergence_log_timeline_id_created_at_idx ON public.divergence_log USING btree (timeline_id, created_at DESC)`
- `CREATE INDEX divergence_log_timeline_id_spoke_created_at_idx ON public.divergence_log USING btree (timeline_id, spoke, created_at DESC)`

**`effects`** (3 indexes)

- `CREATE UNIQUE INDEX effects_pkey ON public.effects USING btree (id)`
- `CREATE INDEX effects_user_id_idx ON public.effects USING btree (user_id)`
- `CREATE UNIQUE INDEX effects_user_id_slug_key ON public.effects USING btree (user_id, slug)`

**`extension_install_state`** (5 indexes)

- `CREATE UNIQUE INDEX extension_install_state_pkey ON public.extension_install_state USING btree (id)`
- `CREATE INDEX extension_install_state_timeline_id_extension_id_idx ON public.extension_install_state USING btree (timeline_id, extension_id)`
- `CREATE INDEX extension_install_state_timeline_id_idx ON public.extension_install_state USING btree (timeline_id)`
- `CREATE INDEX extension_install_state_user_id_idx ON public.extension_install_state USING btree (user_id)`
- `CREATE UNIQUE INDEX extension_install_state_user_timeline_extension_unique ON public.extension_install_state USING btree (user_id, timeline_id, extension_id)`

**`extension_proposals`** (7 indexes)

- `CREATE UNIQUE INDEX extension_proposals_pkey ON public.extension_proposals USING btree (id)`
- `CREATE INDEX extension_proposals_status_idx ON public.extension_proposals USING btree (status)`
- `CREATE INDEX extension_proposals_timeline_id_extension_id_idx ON public.extension_proposals USING btree (timeline_id, extension_id)`
- `CREATE INDEX extension_proposals_timeline_id_idx ON public.extension_proposals USING btree (timeline_id)`
- `CREATE INDEX extension_proposals_timeline_id_status_expires_at_idx ON public.extension_proposals USING btree (timeline_id, status, expires_at)`
- `CREATE INDEX extension_proposals_timeline_id_status_idx ON public.extension_proposals USING btree (timeline_id, status)`
- `CREATE INDEX extension_proposals_user_id_idx ON public.extension_proposals USING btree (user_id)`

**`extension_settings`** (5 indexes)

- `CREATE UNIQUE INDEX extension_settings_pkey ON public.extension_settings USING btree (id)`
- `CREATE INDEX extension_settings_timeline_id_extension_id_idx ON public.extension_settings USING btree (timeline_id, extension_id)`
- `CREATE INDEX extension_settings_timeline_id_idx ON public.extension_settings USING btree (timeline_id)`
- `CREATE INDEX extension_settings_user_id_idx ON public.extension_settings USING btree (user_id)`
- `CREATE UNIQUE INDEX extension_settings_user_timeline_extension_unique ON public.extension_settings USING btree (user_id, timeline_id, extension_id)`

**`external_api_keys`** (4 indexes)

- `CREATE UNIQUE INDEX external_api_keys_pkey ON public.external_api_keys USING btree (id)`
- `CREATE UNIQUE INDEX external_api_keys_user_id_service_key ON public.external_api_keys USING btree (user_id, service)`
- `CREATE INDEX idx_external_api_keys_service ON public.external_api_keys USING btree (service)`
- `CREATE INDEX idx_external_api_keys_user_id ON public.external_api_keys USING btree (user_id)`

**`generation_variants`** (7 indexes)

- `CREATE UNIQUE INDEX generation_variants_pkey ON public.generation_variants USING btree (id)`
- `CREATE INDEX idx_generation_variants_generation_id ON public.generation_variants USING btree (generation_id)`
- `CREATE INDEX idx_generation_variants_project_id ON public.generation_variants USING btree (project_id) WHERE (project_id IS NOT NULL)`
- `CREATE INDEX idx_generation_variants_starred ON public.generation_variants USING btree (starred)`
- `CREATE INDEX idx_generation_variants_variant_type ON public.generation_variants USING btree (variant_type) WHERE (variant_type IS NOT NULL)`
- `CREATE INDEX idx_generation_variants_viewed_at_null ON public.generation_variants USING btree (viewed_at) WHERE (viewed_at IS NULL)`
- `CREATE UNIQUE INDEX idx_unique_primary_variant ON public.generation_variants USING btree (generation_id) WHERE (is_primary = true)`

**`generations`** (20 indexes)

- `CREATE UNIQUE INDEX generations_pkey ON public.generations USING btree (id)`
- `CREATE INDEX idx_generations_based_on ON public.generations USING btree (based_on) WHERE (based_on IS NOT NULL)`
- `CREATE INDEX idx_generations_has_shots ON public.generations USING btree (((shot_data <> '{}'::jsonb))) WHERE (shot_data <> '{}'::jsonb)`
- `CREATE INDEX idx_generations_name ON public.generations USING btree (name) WHERE (name IS NOT NULL)`
- `CREATE INDEX idx_generations_pair_shot_generation_id ON public.generations USING btree (pair_shot_generation_id) WHERE (pair_shot_generation_id IS NOT NULL)`
- `CREATE INDEX idx_generations_params_tool_type ON public.generations USING gin (((params -> 'tool_type'::text))) WHERE (params IS NOT NULL)`
- `CREATE INDEX idx_generations_parent_generation_id ON public.generations USING btree (parent_generation_id) WHERE (parent_generation_id IS NOT NULL)`
- `CREATE INDEX idx_generations_parent_pair_lookup ON public.generations USING btree (parent_generation_id, pair_shot_generation_id) WHERE ((is_child = true) AND (pair_shot_generation_id IS NOT NULL))`
- `CREATE INDEX idx_generations_primary_variant ON public.generations USING btree (primary_variant_id) WHERE (primary_variant_id IS NOT NULL)`
- `CREATE INDEX idx_generations_project_created_desc ON public.generations USING btree (project_id, created_at DESC) WHERE (project_id IS NOT NULL)`
- `CREATE INDEX idx_generations_project_id ON public.generations USING btree (project_id)`
- `CREATE INDEX idx_generations_project_starred ON public.generations USING btree (project_id, starred)`
- `CREATE INDEX idx_generations_project_starred_created ON public.generations USING btree (project_id, starred, created_at DESC) WHERE ((project_id IS NOT NULL) AND (starred IS NOT NULL))`
- `CREATE INDEX idx_generations_project_type_created ON public.generations USING btree (project_id, type, created_at DESC) WHERE ((project_id IS NOT NULL) AND (type IS NOT NULL))`
- `CREATE INDEX idx_generations_prompt_search ON public.generations USING gin (((((params -> 'originalParams'::text) -> 'orchestrator_details'::text) ->> 'prompt'::text)) gin_trgm_ops) WHERE ((((params -> 'originalParams'::text) -> 'orchestrator_details'::text) ->> 'prompt'::text) IS NOT NULL)`
- `CREATE INDEX idx_generations_shot_data_gin ON public.generations USING gin (shot_data)`
- `CREATE INDEX idx_generations_starred ON public.generations USING btree (starred)`
- `CREATE INDEX idx_generations_thumbnail_url ON public.generations USING btree (thumbnail_url) WHERE (thumbnail_url IS NOT NULL)`
- `CREATE INDEX idx_generations_type ON public.generations USING btree (type) WHERE (type IS NOT NULL)`
- `CREATE INDEX idx_generations_type_filter ON public.generations USING btree (type) WHERE (type IS NOT NULL)`

**`local_media_handles`** (3 indexes)

- `CREATE UNIQUE INDEX local_media_handles_pkey ON public.local_media_handles USING btree (id)`
- `CREATE INDEX local_media_handles_project_id_idx ON public.local_media_handles USING btree (project_id)`
- `CREATE INDEX local_media_handles_user_id_idx ON public.local_media_handles USING btree (user_id)`

**`model_family_for_model`** (1 index)

- `CREATE UNIQUE INDEX model_family_for_model_pkey ON public.model_family_for_model USING btree (model_name)`

**`onboarding_config`** (1 index)

- `CREATE UNIQUE INDEX onboarding_config_pkey ON public.onboarding_config USING btree (key)`

**`pause_scaling`** (1 index)

- `CREATE UNIQUE INDEX pause_scaling_pkey ON public.pause_scaling USING btree (pool)`

**`projects`** (3 indexes)

- `CREATE INDEX idx_projects_user_id ON public.projects USING btree (user_id)`
- `CREATE INDEX idx_projects_user_id_for_rls ON public.projects USING btree (user_id, id)`
- `CREATE UNIQUE INDEX projects_pkey ON public.projects USING btree (id)`

**`rate_limits`** (2 indexes)

- `CREATE INDEX idx_rate_limits_window_start ON public.rate_limits USING btree (window_start)`
- `CREATE UNIQUE INDEX rate_limits_pkey ON public.rate_limits USING btree (key)`

**`referral_sessions`** (6 indexes)

- `CREATE INDEX idx_referral_sessions_converted_at ON public.referral_sessions USING btree (converted_at)`
- `CREATE INDEX idx_referral_sessions_fingerprint ON public.referral_sessions USING btree (visitor_fingerprint)`
- `CREATE INDEX idx_referral_sessions_referrer ON public.referral_sessions USING btree (referrer_username)`
- `CREATE INDEX idx_referral_sessions_session_id ON public.referral_sessions USING btree (session_id)`
- `CREATE INDEX idx_referral_sessions_visitor_unconverted ON public.referral_sessions USING btree (visitor_fingerprint, converted_at, is_latest_referrer) WHERE (converted_at IS NULL)`
- `CREATE UNIQUE INDEX referral_sessions_pkey ON public.referral_sessions USING btree (id)`

**`referrals`** (4 indexes)

- `CREATE INDEX idx_referrals_referred ON public.referrals USING btree (referred_id)`
- `CREATE INDEX idx_referrals_referrer ON public.referrals USING btree (referrer_id)`
- `CREATE UNIQUE INDEX referrals_pkey ON public.referrals USING btree (id)`
- `CREATE UNIQUE INDEX referrals_referrer_id_referred_id_key ON public.referrals USING btree (referrer_id, referred_id)`

**`resources`** (4 indexes)

- `CREATE INDEX idx_resources_generation_id ON public.resources USING btree (generation_id)`
- `CREATE INDEX idx_resources_is_public ON public.resources USING btree (is_public) WHERE (is_public = true)`
- `CREATE INDEX idx_resources_type_is_public ON public.resources USING btree (type, is_public) WHERE (is_public = true)`
- `CREATE UNIQUE INDEX resources_pkey ON public.resources USING btree (id)`

**`route_alias_map`** (1 index)

- `CREATE UNIQUE INDEX route_alias_map_pkey ON public.route_alias_map USING btree (alias)`

**`route_backend_capabilities`** (5 indexes)

- `CREATE INDEX idx_route_backend_capabilities_expires_at ON public.route_backend_capabilities USING btree (expires_at) WHERE (expires_at IS NOT NULL)`
- `CREATE INDEX idx_route_backend_capabilities_lookup ON public.route_backend_capabilities USING btree (backend, route_key) WHERE (enabled = true)`
- `CREATE INDEX idx_route_backend_capabilities_missing_selector ON public.route_backend_capabilities USING btree (route_key, backend) WHERE ((enabled = true) AND (supports_missing_selector = true))`
- `CREATE UNIQUE INDEX route_backend_capabilities_pkey ON public.route_backend_capabilities USING btree (id)`
- `CREATE UNIQUE INDEX route_backend_capabilities_unique_route_backend ON public.route_backend_capabilities USING btree (backend, route_key)`

**`route_backend_selectors`** (5 indexes)

- `CREATE INDEX idx_route_backend_selectors_backend ON public.route_backend_selectors USING btree (selected_backend, selector_namespace) WHERE (enabled = true)`
- `CREATE INDEX idx_route_backend_selectors_expires_at ON public.route_backend_selectors USING btree (expires_at) WHERE (expires_at IS NOT NULL)`
- `CREATE INDEX idx_route_backend_selectors_lookup ON public.route_backend_selectors USING btree (selector_namespace, route_key) WHERE (enabled = true)`
- `CREATE UNIQUE INDEX route_backend_selectors_pkey ON public.route_backend_selectors USING btree (id)`
- `CREATE UNIQUE INDEX route_backend_selectors_unique_route ON public.route_backend_selectors USING btree (selector_namespace, route_key)`

**`sentinel_ticks`** (1 index)

- `CREATE UNIQUE INDEX sentinel_ticks_pkey ON public.sentinel_ticks USING btree (ts)`

**`settings`** (1 index)

- `CREATE UNIQUE INDEX settings_pkey ON public.settings USING btree (key)`

**`shared_generations`** (8 indexes)

- `CREATE INDEX idx_shared_generations_creator_id ON public.shared_generations USING btree (creator_id)`
- `CREATE INDEX idx_shared_generations_generation_id ON public.shared_generations USING btree (generation_id)`
- `CREATE INDEX idx_shared_generations_share_slug ON public.shared_generations USING btree (share_slug)`
- `CREATE INDEX idx_shared_generations_shot_id ON public.shared_generations USING btree (shot_id)`
- `CREATE INDEX idx_shared_generations_task_id ON public.shared_generations USING btree (task_id)`
- `CREATE UNIQUE INDEX shared_generations_generation_id_creator_id_key ON public.shared_generations USING btree (generation_id, creator_id)`
- `CREATE UNIQUE INDEX shared_generations_pkey ON public.shared_generations USING btree (id)`
- `CREATE UNIQUE INDEX shared_generations_share_slug_key ON public.shared_generations USING btree (share_slug)`

**`shot_data_audit`** (1 index)

- `CREATE UNIQUE INDEX shot_data_audit_pkey ON public.shot_data_audit USING btree (id)`

**`shot_generations`** (8 indexes)

- `CREATE INDEX idx_sg_generation_id ON public.shot_generations USING btree (generation_id)`
- `CREATE INDEX idx_sg_shot_id ON public.shot_generations USING btree (shot_id)`
- `CREATE INDEX idx_shot_generations_generation_id ON public.shot_generations USING btree (generation_id)`
- `CREATE INDEX idx_shot_generations_rls_check ON public.shot_generations USING btree (shot_id)`
- `CREATE INDEX idx_shot_generations_shot_generation_lookup ON public.shot_generations USING btree (shot_id, generation_id)`
- `CREATE INDEX idx_shot_generations_shot_id_created_at ON public.shot_generations USING btree (shot_id, created_at DESC) WHERE (created_at IS NOT NULL)`
- `CREATE INDEX idx_shot_generations_timeline_frame ON public.shot_generations USING btree (shot_id, timeline_frame) WHERE (timeline_frame IS NOT NULL)`
- `CREATE UNIQUE INDEX shot_generations_pkey ON public.shot_generations USING btree (id)`

**`shot_slots`** (5 indexes)

- `CREATE UNIQUE INDEX shot_slots_pkey ON public.shot_slots USING btree (id)`
- `CREATE INDEX shot_slots_primary_attempt_lookup ON public.shot_slots USING btree (primary_attempt_id) WHERE (primary_attempt_id IS NOT NULL)`
- `CREATE INDEX shot_slots_project_asset_lookup ON public.shot_slots USING btree (project_id, position_index) WHERE (kind = 'project_asset'::shot_slot_kind)`
- `CREATE INDEX shot_slots_project_shot_kind_position ON public.shot_slots USING btree (project_id, shot_id, kind, position_index)`
- `CREATE UNIQUE INDEX shot_slots_project_shot_kind_position_unique ON public.shot_slots USING btree (project_id, shot_id, kind, position_index) NULLS NOT DISTINCT`

**`shots`** (3 indexes)

- `CREATE INDEX idx_shots_project_id ON public.shots USING btree (project_id)`
- `CREATE INDEX idx_shots_project_id_for_rls ON public.shots USING btree (project_id, id)`
- `CREATE UNIQUE INDEX shots_pkey ON public.shots USING btree (id)`

**`slot_first_migration_map`** (5 indexes)

- `CREATE INDEX slot_first_migration_map_attempt_lookup ON public.slot_first_migration_map USING btree (attempt_id) WHERE (attempt_id IS NOT NULL)`
- `CREATE UNIQUE INDEX slot_first_migration_map_exact_duplicate_guard ON public.slot_first_migration_map USING btree (legacy_table, legacy_id, slot_id, attempt_id) NULLS NOT DISTINCT`
- `CREATE INDEX slot_first_migration_map_legacy_lookup ON public.slot_first_migration_map USING btree (legacy_table, legacy_id)`
- `CREATE UNIQUE INDEX slot_first_migration_map_pkey ON public.slot_first_migration_map USING btree (id)`
- `CREATE INDEX slot_first_migration_map_slot_lookup ON public.slot_first_migration_map USING btree (slot_id) WHERE (slot_id IS NOT NULL)`

**`sync_bookmarks`** (2 indexes)

- `CREATE UNIQUE INDEX sync_bookmarks_pkey ON public.sync_bookmarks USING btree (timeline_id, spoke)`
- `CREATE INDEX sync_bookmarks_timeline_id_synced_at_idx ON public.sync_bookmarks USING btree (timeline_id, synced_at DESC)`

**`system_logs`** (7 indexes)

- `CREATE INDEX idx_system_logs_cycle ON public.system_logs USING btree (source_type, cycle_number) WHERE (cycle_number IS NOT NULL)`
- `CREATE INDEX idx_system_logs_level ON public.system_logs USING btree (log_level, "timestamp" DESC)`
- `CREATE INDEX idx_system_logs_source ON public.system_logs USING btree (source_type, source_id, "timestamp" DESC)`
- `CREATE INDEX idx_system_logs_task ON public.system_logs USING btree (task_id, "timestamp" DESC) WHERE (task_id IS NOT NULL)`
- `CREATE INDEX idx_system_logs_timestamp ON public.system_logs USING btree ("timestamp" DESC)`
- `CREATE INDEX idx_system_logs_worker ON public.system_logs USING btree (worker_id, "timestamp" DESC) WHERE (worker_id IS NOT NULL)`
- `CREATE UNIQUE INDEX system_logs_pkey ON public.system_logs USING btree (id)`

**`task_types`** (10 indexes)

- `CREATE INDEX idx_task_types_active ON public.task_types USING btree (is_active)`
- `CREATE INDEX idx_task_types_billing_type ON public.task_types USING btree (billing_type)`
- `CREATE INDEX idx_task_types_category ON public.task_types USING btree (category)`
- `CREATE INDEX idx_task_types_content_type ON public.task_types USING btree (content_type)`
- `CREATE INDEX idx_task_types_is_visible ON public.task_types USING btree (is_visible)`
- `CREATE INDEX idx_task_types_name ON public.task_types USING btree (name)`
- `CREATE INDEX idx_task_types_run_type ON public.task_types USING btree (run_type)`
- `CREATE INDEX idx_task_types_tool_type ON public.task_types USING btree (tool_type)`
- `CREATE UNIQUE INDEX task_types_name_key ON public.task_types USING btree (name)`
- `CREATE UNIQUE INDEX task_types_pkey ON public.task_types USING btree (id)`

**`tasks`** (25 indexes)

- `CREATE INDEX idx_project_status ON public.tasks USING btree (project_id, status)`
- `CREATE INDEX idx_status_created ON public.tasks USING btree (status, created_at)`
- `CREATE INDEX idx_tasks_active_status ON public.tasks USING btree (status, project_id) WHERE (status <> ALL (ARRAY['Complete'::task_status, 'Failed'::task_status, 'Cancelled'::task_status]))`
- `CREATE INDEX idx_tasks_claimed_backend_active ON public.tasks USING btree (claimed_backend, claimed_selector_namespace, updated_at) WHERE ((status = 'In Progress'::task_status) AND (claimed_backend IS NOT NULL))`
- `CREATE INDEX idx_tasks_claimed_route_key_active ON public.tasks USING btree (claimed_route_key, updated_at) WHERE ((status = 'In Progress'::task_status) AND (claimed_route_key IS NOT NULL))`
- `CREATE INDEX idx_tasks_created_at ON public.tasks USING btree (created_at DESC)`
- `CREATE INDEX idx_tasks_dependant_on ON public.tasks USING gin (dependant_on) WHERE (dependant_on IS NOT NULL)`
- `CREATE UNIQUE INDEX idx_tasks_idempotency_key ON public.tasks USING btree (idempotency_key) WHERE (idempotency_key IS NOT NULL)`
- `CREATE INDEX idx_tasks_poll_single_image ON public.tasks USING btree (task_type, status) WHERE ((generation_processed_at IS NULL) AND (task_type = 'single_image'::text) AND (status = 'Complete'::task_status))`
- `CREATE INDEX idx_tasks_poll_travel_stitch ON public.tasks USING btree (task_type, status) WHERE ((generation_processed_at IS NULL) AND (task_type = 'travel_stitch'::text) AND (status = 'Complete'::task_status))`
- `CREATE INDEX idx_tasks_project_status_inprogress ON public.tasks USING btree (project_id, status) WHERE (status = 'In Progress'::task_status)`
- `CREATE INDEX idx_tasks_queued_created ON public.tasks USING btree (created_at) WHERE (status = 'Queued'::task_status)`
- `CREATE INDEX idx_tasks_route_key_queued ON public.tasks USING btree (route_key, created_at) WHERE ((status = 'Queued'::task_status) AND (route_key IS NOT NULL))`
- `CREATE INDEX idx_tasks_running_started ON public.tasks USING btree (generation_started_at) WHERE (status = 'In Progress'::task_status)`
- `CREATE INDEX idx_tasks_selected_backend_queued ON public.tasks USING btree (selected_backend, created_at) WHERE ((status = 'Queued'::task_status) AND (selected_backend IS NOT NULL))`
- `CREATE INDEX idx_tasks_status_created_at ON public.tasks USING btree (status, created_at)`
- `CREATE INDEX idx_tasks_status_generation_created ON public.tasks USING btree (status, generation_created) WHERE ((status = 'Complete'::task_status) AND (generation_created = false))`
- `CREATE INDEX idx_tasks_status_worker ON public.tasks USING btree (status, worker_id)`
- `CREATE INDEX idx_tasks_task_type ON public.tasks USING btree (task_type) WHERE (task_type = ANY (ARRAY['travel_stitch'::text, 'single_image'::text]))`
- `CREATE INDEX idx_tasks_worker_id ON public.tasks USING btree (worker_id)`
- `CREATE INDEX tasks_model_recent ON public.tasks USING btree (model, created_at DESC) WHERE (model IS NOT NULL)`
- `CREATE UNIQUE INDEX tasks_pkey ON public.tasks USING btree (id)`
- `CREATE INDEX tasks_prompt_trgm ON public.tasks USING gin (prompt gin_trgm_ops) WHERE (prompt IS NOT NULL)`
- `CREATE INDEX tasks_route_key ON public.tasks USING btree (route_key) WHERE (route_key IS NOT NULL)`
- `CREATE INDEX tasks_seed_recent ON public.tasks USING btree (seed, created_at DESC) WHERE (seed IS NOT NULL)`

**`timeline_agent_sessions`** (2 indexes)

- `CREATE UNIQUE INDEX timeline_agent_sessions_pkey ON public.timeline_agent_sessions USING btree (id)`
- `CREATE INDEX timeline_agent_sessions_timeline_id_status_idx ON public.timeline_agent_sessions USING btree (timeline_id, status)`

**`timeline_checkpoints`** (2 indexes)

- `CREATE UNIQUE INDEX timeline_checkpoints_pkey ON public.timeline_checkpoints USING btree (id)`
- `CREATE INDEX timeline_checkpoints_timeline_id_created_at_idx ON public.timeline_checkpoints USING btree (timeline_id, created_at DESC)`

**`timeline_event_contract`** (1 index)

- `CREATE UNIQUE INDEX timeline_event_contract_pkey ON public.timeline_event_contract USING btree (id)`

**`timeline_events`** (3 indexes)

- `CREATE UNIQUE INDEX timeline_events_pkey ON public.timeline_events USING btree (timeline_id, version)`
- `CREATE UNIQUE INDEX timeline_events_timeline_id_event_id_key ON public.timeline_events USING btree (timeline_id, event_id)`
- `CREATE UNIQUE INDEX timeline_events_timeline_id_idempotency_key_idx ON public.timeline_events USING btree (timeline_id, idempotency_key) WHERE (idempotency_key IS NOT NULL)`

**`timeline_update_log`** (1 index)

- `CREATE UNIQUE INDEX timeline_update_log_pkey ON public.timeline_update_log USING btree (id)`

**`timelines`** (3 indexes)

- `CREATE UNIQUE INDEX timelines_pkey ON public.timelines USING btree (id)`
- `CREATE INDEX timelines_project_id_idx ON public.timelines USING btree (project_id)`
- `CREATE INDEX timelines_user_id_idx ON public.timelines USING btree (user_id)`

**`training_data`** (4 indexes)

- `CREATE INDEX idx_training_data_batch_id ON public.training_data USING btree (batch_id)`
- `CREATE INDEX idx_training_data_created_at ON public.training_data USING btree (created_at)`
- `CREATE INDEX idx_training_data_user_id ON public.training_data USING btree (user_id)`
- `CREATE UNIQUE INDEX training_data_pkey ON public.training_data USING btree (id)`

**`training_data_batches`** (3 indexes)

- `CREATE INDEX idx_training_data_batches_created_at ON public.training_data_batches USING btree (created_at)`
- `CREATE INDEX idx_training_data_batches_user_id ON public.training_data_batches USING btree (user_id)`
- `CREATE UNIQUE INDEX training_data_batches_pkey ON public.training_data_batches USING btree (id)`

**`training_data_segments`** (3 indexes)

- `CREATE INDEX idx_training_data_segments_created_at ON public.training_data_segments USING btree (created_at)`
- `CREATE INDEX idx_training_data_segments_training_data_id ON public.training_data_segments USING btree (training_data_id)`
- `CREATE UNIQUE INDEX training_data_segments_pkey ON public.training_data_segments USING btree (id)`

**`user_api_tokens`** (3 indexes)

- `CREATE UNIQUE INDEX idx_user_api_tokens_token ON public.user_api_tokens USING btree (token)`
- `CREATE INDEX idx_user_api_tokens_user_id ON public.user_api_tokens USING btree (user_id)`
- `CREATE UNIQUE INDEX user_api_tokens_pkey ON public.user_api_tokens USING btree (id)`

**`users`** (7 indexes)

- `CREATE INDEX idx_users_auto_topup_enabled ON public.users USING btree (auto_topup_enabled) WHERE (auto_topup_enabled = true)`
- `CREATE INDEX idx_users_auto_topup_threshold ON public.users USING btree (auto_topup_threshold) WHERE (auto_topup_enabled = true)`
- `CREATE INDEX idx_users_generation_settings ON public.users USING gin ((((settings -> 'ui'::text) -> 'generationMethods'::text)))`
- `CREATE INDEX idx_users_stripe_customer ON public.users USING btree (stripe_customer_id) WHERE (stripe_customer_id IS NOT NULL)`
- `CREATE INDEX idx_users_username ON public.users USING btree (username)`
- `CREATE UNIQUE INDEX users_pkey ON public.users USING btree (id)`
- `CREATE UNIQUE INDEX users_username_key ON public.users USING btree (username)`

**`workers`** (5 indexes)

- `CREATE INDEX idx_workers_current_model ON public.workers USING btree (current_model) WHERE (status = 'active'::text)`
- `CREATE INDEX idx_workers_last_heartbeat ON public.workers USING btree (last_heartbeat)`
- `CREATE INDEX idx_workers_status ON public.workers USING btree (status)`
- `CREATE INDEX idx_workers_status_heartbeat ON public.workers USING btree (status, last_heartbeat)`
- `CREATE UNIQUE INDEX workers_pkey ON public.workers USING btree (id)`

### 3.6 Foreign keys (71)

| Constraint | Definition |
|---|---|
| `agent_node_catalog_metadata.agent_node_catalog_metadata_agent_node_id_fkey` | `FOREIGN KEY (agent_node_id) REFERENCES agent_nodes(id) ON DELETE CASCADE` |
| `agent_node_install_targets.agent_node_install_expected_identity_fk` | `FOREIGN KEY (agent_node_id, expected_node_id) REFERENCES agent_nodes(id, expected_manifest_id) ON UPDATE CASCADE ON DELETE CASCADE` |
| `agent_node_install_targets.agent_node_install_targets_agent_node_id_fkey` | `FOREIGN KEY (agent_node_id) REFERENCES agent_nodes(id) ON DELETE CASCADE` |
| `agent_node_media.agent_node_media_node_owner_fk` | `FOREIGN KEY (agent_node_id, owner_user_id) REFERENCES agent_nodes(id, owner_user_id) ON UPDATE CASCADE ON DELETE CASCADE` |
| `agent_nodes.agent_nodes_owner_user_id_fkey` | `FOREIGN KEY (owner_user_id) REFERENCES users(id) ON DELETE CASCADE` |
| `attempts.attempts_based_on_fkey` | `FOREIGN KEY (based_on) REFERENCES attempts(id) ON DELETE SET NULL` |
| `attempts.attempts_local_handle_id_fkey` | `FOREIGN KEY (local_handle_id) REFERENCES local_media_handles(id) ON DELETE RESTRICT` |
| `attempts.attempts_pair_shot_attempt_id_fkey` | `FOREIGN KEY (pair_shot_attempt_id) REFERENCES attempts(id) ON DELETE SET NULL` |
| `attempts.attempts_parent_attempt_id_fkey` | `FOREIGN KEY (parent_attempt_id) REFERENCES attempts(id) ON DELETE SET NULL` |
| `attempts.attempts_project_id_fkey` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `attempts.attempts_slot_id_fkey` | `FOREIGN KEY (slot_id) REFERENCES shot_slots(id) ON DELETE CASCADE` |
| `attempts.attempts_superseded_by_fkey` | `FOREIGN KEY (superseded_by) REFERENCES attempts(id) ON DELETE SET NULL` |
| `attempts.attempts_task_id_fkey` | `FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE SET NULL` |
| `credits_ledger.credits_ledger_task_id_fkey` | `FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE SET NULL` |
| `credits_ledger.credits_ledger_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE` |
| `divergence_log.divergence_log_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `effects.effects_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `extension_install_state.extension_install_state_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `extension_install_state.extension_install_state_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `extension_proposals.extension_proposals_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `extension_proposals.extension_proposals_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `extension_settings.extension_settings_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `extension_settings.extension_settings_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `external_api_keys.external_api_keys_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `generation_variants.generation_variants_generation_id_fkey` | `FOREIGN KEY (generation_id) REFERENCES generations(id) ON DELETE CASCADE` |
| `generation_variants.generation_variants_project_id_fkey` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `generations.generations_based_on_fkey` | `FOREIGN KEY (based_on) REFERENCES generations(id) ON DELETE SET NULL` |
| `generations.generations_local_handle_id_fkey` | `FOREIGN KEY (local_handle_id) REFERENCES local_media_handles(id) ON DELETE SET NULL` |
| `generations.generations_pair_shot_generation_id_fkey` | `FOREIGN KEY (pair_shot_generation_id) REFERENCES shot_generations(id) ON DELETE SET NULL` |
| `generations.generations_parent_generation_id_fkey` | `FOREIGN KEY (parent_generation_id) REFERENCES generations(id) ON DELETE CASCADE` |
| `generations.generations_primary_variant_id_fkey` | `FOREIGN KEY (primary_variant_id) REFERENCES generation_variants(id)` |
| `generations.generations_project_id_projects_id_fk` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `local_media_handles.local_media_handles_project_id_fkey` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL` |
| `local_media_handles.local_media_handles_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `projects.projects_user_id_users_id_fk` | `FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE` |
| `referral_sessions.referral_sessions_converted_user_id_fkey` | `FOREIGN KEY (converted_user_id) REFERENCES users(id)` |
| `referral_sessions.referral_sessions_referrer_user_id_fkey` | `FOREIGN KEY (referrer_user_id) REFERENCES users(id)` |
| `referrals.referrals_referred_id_fkey` | `FOREIGN KEY (referred_id) REFERENCES users(id)` |
| `referrals.referrals_referrer_id_fkey` | `FOREIGN KEY (referrer_id) REFERENCES users(id)` |
| `referrals.referrals_session_id_fkey` | `FOREIGN KEY (session_id) REFERENCES referral_sessions(id)` |
| `resources.resources_generation_id_fkey` | `FOREIGN KEY (generation_id) REFERENCES generations(id) ON DELETE CASCADE` |
| `resources.resources_user_id_users_id_fk` | `FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE` |
| `shared_generations.shared_generations_creator_id_fkey` | `FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE SET NULL` |
| `shared_generations.shared_generations_generation_id_fkey` | `FOREIGN KEY (generation_id) REFERENCES generations(id) ON DELETE CASCADE` |
| `shared_generations.shared_generations_shot_id_fkey` | `FOREIGN KEY (shot_id) REFERENCES shots(id) ON DELETE SET NULL` |
| `shared_generations.shared_generations_task_id_fkey` | `FOREIGN KEY (task_id) REFERENCES tasks(id) ON DELETE CASCADE` |
| `shot_generations.shot_generations_generation_id_generations_id_fk` | `FOREIGN KEY (generation_id) REFERENCES generations(id) ON DELETE CASCADE` |
| `shot_generations.shot_generations_shot_id_shots_id_fk` | `FOREIGN KEY (shot_id) REFERENCES shots(id) ON DELETE CASCADE` |
| `shot_slots.shot_slots_primary_attempt_fk` | `FOREIGN KEY (primary_attempt_id) REFERENCES attempts(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED` |
| `shot_slots.shot_slots_project_id_fkey` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `shot_slots.shot_slots_shot_id_fkey` | `FOREIGN KEY (shot_id) REFERENCES shots(id) ON DELETE CASCADE` |
| `shots.shots_project_id_projects_id_fk` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `slot_first_migration_map.slot_first_migration_map_attempt_id_fkey` | `FOREIGN KEY (attempt_id) REFERENCES attempts(id) ON DELETE SET NULL` |
| `slot_first_migration_map.slot_first_migration_map_slot_id_fkey` | `FOREIGN KEY (slot_id) REFERENCES shot_slots(id) ON DELETE SET NULL` |
| `sync_bookmarks.sync_bookmarks_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `tasks.tasks_project_id_projects_id_fk` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `tasks.tasks_task_type_fkey` | `FOREIGN KEY (task_type) REFERENCES task_types(name)` |
| `tasks.tasks_worker_id_fkey` | `FOREIGN KEY (worker_id) REFERENCES workers(id) ON DELETE SET NULL` |
| `timeline_agent_sessions.timeline_agent_sessions_cancelled_by_fkey` | `FOREIGN KEY (cancelled_by) REFERENCES auth.users(id) ON DELETE SET NULL` |
| `timeline_agent_sessions.timeline_agent_sessions_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `timeline_agent_sessions.timeline_agent_sessions_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `timeline_checkpoints.timeline_checkpoints_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `timeline_checkpoints.timeline_checkpoints_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `timeline_events.timeline_events_timeline_id_fkey` | `FOREIGN KEY (timeline_id) REFERENCES timelines(id) ON DELETE CASCADE` |
| `timelines.timelines_project_id_fkey` | `FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE` |
| `timelines.timelines_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `training_data.training_data_batch_id_fkey` | `FOREIGN KEY (batch_id) REFERENCES training_data_batches(id) ON DELETE CASCADE` |
| `training_data.training_data_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `training_data_batches.training_data_batches_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |
| `training_data_segments.training_data_segments_training_data_id_fkey` | `FOREIGN KEY (training_data_id) REFERENCES training_data(id) ON DELETE CASCADE` |
| `user_api_tokens.user_api_tokens_user_id_fkey` | `FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE` |

> Pattern: user-owned rows (`projects`, `resources`, `attempts`, `generations`, `credits_ledger`, …) FK to `public.users(id)` with `ON DELETE CASCADE`; auth-owned rows (`external_api_keys`, `local_media_handles`, `timeline_*`, `training_data*`, `user_api_tokens`, `effects`, `extension_*`) FK to `auth.users(id)` with `ON DELETE CASCADE`. `tasks.task_type` FK targets `task_types(name)` (string, not id). `shot_slots.primary_attempt_id` is `DEFERRABLE INITIALLY DEFERRED`.
### 3.7 Unique constraints (16, non-PK)

| Constraint | Definition |
|---|---|
| `agent_nodes.agent_nodes_owner_integrity_unique` | `UNIQUE (id, owner_user_id)` |
| `agent_nodes.agent_nodes_owner_expected_manifest_unique` | `UNIQUE (id, expected_manifest_id)` |
| `effects.effects_user_id_slug_key` | `UNIQUE (user_id, slug)` |
| `extension_install_state.extension_install_state_user_timeline_extension_unique` | `UNIQUE (user_id, timeline_id, extension_id)` |
| `extension_settings.extension_settings_user_timeline_extension_unique` | `UNIQUE (user_id, timeline_id, extension_id)` |
| `external_api_keys.external_api_keys_user_id_service_key` | `UNIQUE (user_id, service)` |
| `referrals.referrals_referrer_id_referred_id_key` | `UNIQUE (referrer_id, referred_id)` |
| `route_backend_capabilities.route_backend_capabilities_unique_route_backend` | `UNIQUE (backend, route_key)` |
| `route_backend_selectors.route_backend_selectors_unique_route` | `UNIQUE (selector_namespace, route_key)` |
| `shared_generations.shared_generations_share_slug_key` | `UNIQUE (share_slug)` |
| `shared_generations.shared_generations_generation_id_creator_id_key` | `UNIQUE (generation_id, creator_id)` |
| `shot_slots.shot_slots_project_shot_kind_position_unique` | `UNIQUE NULLS NOT DISTINCT (project_id, shot_id, kind, position_index) DEFERRABLE` |
| `slot_first_migration_map.slot_first_migration_map_exact_duplicate_guard` | `UNIQUE NULLS NOT DISTINCT (legacy_table, legacy_id, slot_id, attempt_id)` |
| `task_types.task_types_name_key` | `UNIQUE (name)` |
| `timeline_events.timeline_events_timeline_id_event_id_key` | `UNIQUE (timeline_id, event_id)` |
| `users.users_username_key` | `UNIQUE (username)` |

### 3.8 Check constraints (129, by table)

| Table | # checks |
|---|---|
| `divergence_log` | 14 |
| `tasks` | 13 |
| `timeline_events` | 11 |
| `attempts` | 11 |
| `agent_node_install_targets` | 10 |
| `sync_bookmarks` | 9 |
| `agent_nodes` | 7 |
| `agent_node_media` | 7 |
| `route_backend_capabilities` | 5 |
| `extension_proposals` | 5 |
| `route_backend_selectors` | 5 |
| `task_types` | 4 |
| `shot_slots` | 4 |
| `agent_node_catalog_metadata` | 4 |
| `extension_settings` | 3 |
| `extension_install_state` | 3 |
| `system_logs` | 2 |
| `timeline_event_contract` | 2 |
| `timeline_agent_sessions` | 2 |
| `model_family_for_model` | 1 |
| `dev_tasks` | 1 |
| `slot_first_migration_map` | 1 |
| `timeline_checkpoints` | 1 |
| `generations` | 1 |
| `workers` | 1 |
| `effects` | 1 |

> Heaviest: `divergence_log` (14), `tasks` (13), `timeline_events` (11), `attempts` (11), `agent_node_install_targets` (10), `sync_bookmarks` (9).
### 3.9 Sequences (1)

- `shot_data_audit_id_seq` (integer, start 1, increment 1) — used by `shot_data_audit.id`

### 3.10 RLS: enabled tables (46) and policies (150)

**RLS-enabled tables (46):** `agent_node_catalog_metadata`, `agent_node_install_targets`, `agent_node_media`, `agent_nodes`, `attempts`, `credits_ledger`, `dev_tasks`, `divergence_log`, `effects`, `extension_install_state`, `extension_proposals`, `extension_settings`, `external_api_keys`, `generation_variants`, `generations`, `local_media_handles`, `onboarding_config`, `projects`, `rate_limits`, `referral_sessions`, `referrals`, `resources`, `route_backend_capabilities`, `route_backend_selectors`, `settings`, `shared_generations`, `shot_generations`, `shot_slots`, `shots`, `slot_first_migration_map`, `sync_bookmarks`, `task_types`, `tasks`, `timeline_agent_sessions`, `timeline_checkpoints`, `timeline_event_contract`, `timeline_events`, `timeline_update_log`, `timelines`, `training_data`, `training_data_batches`, `training_data_segments`, `user_api_tokens`, `users`, `workers`

| Table | Policy | Cmd | Roles | USING / CHECK (truncated 160 chars) |
|---|---|---|---|---|
| `agent_node_catalog_metadata` | `agent_node_catalog_owner_insert` | INSERT | `public` | `(EXISTS ( SELECT 1    FROM agent_nodes node   WHERE ((node.id = agent_node_catalog_metadata.agent_node_id) AND (node.owner_user_id = auth.uid()))))` |
| `agent_node_catalog_metadata` | `agent_node_catalog_owner_read` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM agent_nodes node   WHERE ((node.id = agent_node_catalog_metadata.agent_node_id) AND (node.owner_user_id = auth.uid()))))` |
| `agent_node_catalog_metadata` | `agent_node_catalog_owner_update` | UPDATE | `public` | `(EXISTS ( SELECT 1    FROM agent_nodes node   WHERE ((node.id = agent_node_catalog_metadata.agent_node_id) AND (node.owner_user_id = auth.uid()))))` |
| `agent_node_catalog_metadata` | `agent_node_catalog_public_read` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM agent_nodes node   WHERE ((node.id = agent_node_catalog_metadata.agent_node_id) AND node.is_public)))` |
| `agent_node_install_targets` | `agent_node_install_targets_owner_all` | ALL | `public` | `(EXISTS ( SELECT 1    FROM agent_nodes node   WHERE ((node.id = agent_node_install_targets.agent_node_id) AND (node.owner_user_id = auth.uid()))))` |
| `agent_node_install_targets` | `agent_node_install_targets_public_read` | SELECT | `public` | `(is_enabled AND (EXISTS ( SELECT 1    FROM (agent_nodes node      JOIN agent_node_catalog_metadata catalog ON ((catalog.agent_node_id = node.id)))   WHERE ((node.id = agent_node_install_targets.agent_node_id) AND node.is_public AND (catalog.review_status = 'approved'::text) AND catalog.is_catalog_enabled))))` |
| `agent_node_media` | `agent_node_media_owner_all` | ALL | `public` | `(auth.uid() = owner_user_id)` |
| `agent_node_media` | `agent_node_media_public_read` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM agent_nodes node   WHERE ((node.id = agent_node_media.agent_node_id) AND node.is_public)))` |
| `agent_nodes` | `agent_nodes_owner_delete` | DELETE | `public` | `(auth.uid() = owner_user_id)` |
| `agent_nodes` | `agent_nodes_owner_insert` | INSERT | `public` | `(auth.uid() = owner_user_id)` |
| `agent_nodes` | `agent_nodes_owner_read` | SELECT | `public` | `(auth.uid() = owner_user_id)` |
| `agent_nodes` | `agent_nodes_owner_update` | UPDATE | `public` | `(auth.uid() = owner_user_id)` |
| `agent_nodes` | `agent_nodes_public_read` | SELECT | `public` | `is_public` |
| `attempts` | `attempts_delete_owner` | DELETE | `authenticated` | `((legacy_url_only = false) AND (EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = attempts.project_id) AND (p.user_id = auth.uid())))))` |
| `attempts` | `attempts_insert_owner` | INSERT | `authenticated` | `((legacy_url_only = false) AND (EXISTS ( SELECT 1    FROM (shot_slots ss      JOIN projects p ON ((p.id = ss.project_id)))   WHERE ((ss.id = attempts.slot_id) AND (ss.project_id = attempts.project_id) AND (p.user_id = auth.uid())))))` |
| `attempts` | `attempts_select_owner` | SELECT | `authenticated` | `((deleted_at IS NULL) AND (EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = attempts.project_id) AND (p.user_id = auth.uid())))))` |
| `attempts` | `attempts_service_role_all` | ALL | `service_role` | `true` |
| `attempts` | `attempts_update_owner` | UPDATE | `authenticated` | `((legacy_url_only = false) AND (EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = attempts.project_id) AND (p.user_id = auth.uid())))))` |
| `credits_ledger` | `Service role can delete credit ledger entries` | DELETE | `public` | `(auth.role() = 'service_role'::text)` |
| `credits_ledger` | `Service role can insert credit ledger entries` | INSERT | `public` | `(auth.role() = 'service_role'::text)` |
| `credits_ledger` | `Service role can update credit ledger entries` | UPDATE | `public` | `(auth.role() = 'service_role'::text)` |
| `credits_ledger` | `Users can view their own credit ledger` | SELECT | `public` | `(auth.uid() = user_id)` |
| `dev_tasks` | `Authenticated users can manage dev_tasks` | ALL | `public` | `(auth.role() = 'authenticated'::text)` |
| `dev_tasks` | `Service role can manage dev_tasks` | ALL | `public` | `(auth.role() = 'service_role'::text)` |
| `divergence_log` | `Users can view own divergence log` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = divergence_log.timeline_id) AND (timelines.user_id = auth.uid()))))` |
| `effects` | `Users can delete own effects` | DELETE | `public` | `(auth.uid() = user_id)` |
| `effects` | `Users can insert own effects` | INSERT | `public` | `(auth.uid() = user_id)` |
| `effects` | `Users can update own effects` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `effects` | `Users can view own effects` | SELECT | `public` | `(auth.uid() = user_id)` |
| `extension_install_state` | `Service role can manage all extension install state` | ALL | `service_role` | `true` |
| `extension_install_state` | `Users can delete own extension install state` | DELETE | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_install_state.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_install_state` | `Users can insert own extension install state` | INSERT | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_install_state.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_install_state` | `Users can update own extension install state` | UPDATE | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_install_state.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_install_state` | `Users can view own extension install state` | SELECT | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_install_state.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_proposals` | `Service role can manage all extension proposals` | ALL | `service_role` | `true` |
| `extension_proposals` | `Users can delete own extension proposals` | DELETE | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_proposals.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_proposals` | `Users can insert own extension proposals` | INSERT | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_proposals.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_proposals` | `Users can update own extension proposals` | UPDATE | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_proposals.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_proposals` | `Users can view own extension proposals` | SELECT | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_proposals.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_settings` | `Service role can manage all extension settings` | ALL | `service_role` | `true` |
| `extension_settings` | `Users can delete own extension settings` | DELETE | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_settings.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_settings` | `Users can insert own extension settings` | INSERT | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_settings.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_settings` | `Users can update own extension settings` | UPDATE | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_settings.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `extension_settings` | `Users can view own extension settings` | SELECT | `public` | `((auth.uid() = user_id) AND (EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = extension_settings.timeline_id) AND (timelines.user_id = auth.uid())))))` |
| `external_api_keys` | `Users can delete own external API keys` | DELETE | `public` | `(auth.uid() = user_id)` |
| `external_api_keys` | `Users can insert own external API keys` | INSERT | `public` | `(auth.uid() = user_id)` |
| `external_api_keys` | `Users can update own external API keys` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `external_api_keys` | `Users can view own external API keys` | SELECT | `public` | `(auth.uid() = user_id)` |
| `generation_variants` | `Service role has full access to generation_variants` | ALL | `public` | `((auth.jwt() ->> 'role'::text) = 'service_role'::text)` |
| `generation_variants` | `Users can create variants for their generations` | INSERT | `public` | `(EXISTS ( SELECT 1    FROM (generations g      JOIN projects p ON ((g.project_id = p.id)))   WHERE ((g.id = generation_variants.generation_id) AND (p.user_id = auth.uid()))))` |
| `generation_variants` | `Users can delete variants of their generations` | DELETE | `public` | `(EXISTS ( SELECT 1    FROM (generations g      JOIN projects p ON ((g.project_id = p.id)))   WHERE ((g.id = generation_variants.generation_id) AND (p.user_id = auth.uid()))))` |
| `generation_variants` | `Users can update variants of their generations` | UPDATE | `public` | `(EXISTS ( SELECT 1    FROM (generations g      JOIN projects p ON ((g.project_id = p.id)))   WHERE ((g.id = generation_variants.generation_id) AND (p.user_id = auth.uid()))))` |
| `generation_variants` | `Users can view variants of their generations` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM (generations g      JOIN projects p ON ((g.project_id = p.id)))   WHERE ((g.id = generation_variants.generation_id) AND (p.user_id = auth.uid()))))` |
| `generations` | `Allow trigger to update shot_data` | UPDATE | `postgres` | `true` |
| `generations` | `Service role can manage all generations` | ALL | `service_role` | `true` |
| `generations` | `Users can delete their own generations` | DELETE | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `generations` | `Users can insert generations for their projects` | INSERT | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `generations` | `Users can update their own generations` | UPDATE | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `generations` | `Users can view their own generations` | SELECT | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `local_media_handles` | `Users can delete own local media handles` | DELETE | `public` | `(auth.uid() = user_id)` |
| `local_media_handles` | `Users can insert own local media handles` | INSERT | `public` | `(auth.uid() = user_id)` |
| `local_media_handles` | `Users can view own local media handles` | SELECT | `public` | `(auth.uid() = user_id)` |
| `onboarding_config` | `Allow public read access to onboarding_config` | SELECT | `public` | `true` |
| `onboarding_config` | `Allow service role to modify onboarding_config` | ALL | `public` | `(auth.role() = 'service_role'::text)` |
| `projects` | `Projects: service role bypass` | ALL | `public` | `(auth.role() = 'service_role'::text)` |
| `projects` | `Projects: users access own projects` | ALL | `public` | `(user_id = auth.uid())` |
| `projects` | `Service role can manage all projects` | ALL | `service_role` | `true` |
| `projects` | `Users can delete their own projects` | DELETE | `public` | `(auth.uid() = user_id)` |
| `projects` | `Users can insert their own projects` | INSERT | `public` | `(auth.uid() = user_id)` |
| `projects` | `Users can update their own projects` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `projects` | `Users can view their own projects` | SELECT | `public` | `(auth.uid() = user_id)` |
| `rate_limits` | `Service role only` | ALL | `service_role` | `true` |
| `referral_sessions` | `anon_insert_sessions` | INSERT | `anon` | `true` |
| `referral_sessions` | `users_view_own_sessions` | SELECT | `authenticated` | `((referrer_user_id = auth.uid()) OR (converted_user_id = auth.uid()))` |
| `referrals` | `users_view_own_referrals` | SELECT | `authenticated` | `((referrer_id = auth.uid()) OR (referred_id = auth.uid()))` |
| `resources` | `Allow read access to public resources` | SELECT | `public` | `(is_public = true)` |
| `resources` | `Enable all access for resource owners` | ALL | `public` | `(auth.uid() = user_id)` |
| `route_backend_capabilities` | `route_backend_capabilities_service_role_all` | ALL | `service_role` | `true` |
| `route_backend_selectors` | `route_backend_selectors_service_role_all` | ALL | `service_role` | `true` |
| `settings` | `settings_select_all` | SELECT | `anon,authenticated` | `true` |
| `settings` | `settings_service_role_all` | ALL | `service_role` | `true` |
| `shared_generations` | `Shared generations are publicly viewable` | SELECT | `public` | `true` |
| `shared_generations` | `Users can create shares for their generations` | INSERT | `public` | `((auth.uid() = creator_id) AND (EXISTS ( SELECT 1    FROM (generations g      JOIN projects p ON ((p.id = g.project_id)))   WHERE ((g.id = shared_generations.generation_id) AND (p.user_id = auth.uid())))))` |
| `shared_generations` | `Users can delete their own shares` | DELETE | `public` | `(auth.uid() = creator_id)` |
| `shared_generations` | `Users can update their own shares` | UPDATE | `public` | `(auth.uid() = creator_id)` |
| `shot_generations` | `Service role can manage all shot_generations` | ALL | `service_role` | `true` |
| `shot_generations` | `Users can manage their shot generations` | ALL | `public` | `(EXISTS ( SELECT 1    FROM (shots s      JOIN projects p ON ((s.project_id = p.id)))   WHERE ((s.id = shot_generations.shot_id) AND (p.user_id = auth.uid()))))` |
| `shot_generations` | `sg: service role` | ALL | `public` | `(auth.role() = 'service_role'::text)` |
| `shot_generations` | `sg: user delete` | DELETE | `public` | `(EXISTS ( SELECT 1    FROM (shots s      JOIN projects p ON ((p.id = s.project_id)))   WHERE ((s.id = shot_generations.shot_id) AND (p.user_id = auth.uid()))))` |
| `shot_generations` | `sg: user insert` | INSERT | `public` | `((EXISTS ( SELECT 1    FROM (shots s      JOIN projects p ON ((p.id = s.project_id)))   WHERE ((s.id = shot_generations.shot_id) AND (p.user_id = auth.uid())))) AND (EXISTS ( SELECT 1    FROM (generations g      JOIN projects p2 ON ((p2.id = g.project_id)))   WHERE ((g.id = shot_generations.generation_id) AND (p2.user_id = auth.uid())))) AND (( SELECT s.project_id    FROM shots s   WHERE (s.id = shot_generations.shot_id)) = ( SELECT g.project_id    FROM generations g   WHERE (g.id = shot_generations.generation_id))))` |
| `shot_generations` | `sg: user select` | SELECT | `public` | `((EXISTS ( SELECT 1    FROM (shots s      JOIN projects p ON ((p.id = s.project_id)))   WHERE ((s.id = shot_generations.shot_id) AND (p.user_id = auth.uid())))) AND (EXISTS ( SELECT 1    FROM (generations g      JOIN projects p2 ON ((p2.id = g.project_id)))   WHERE ((g.id = shot_generations.generation_id) AND (p2.user_id = auth.uid())))))` |
| `shot_generations` | `sg: user update` | UPDATE | `public` | `(EXISTS ( SELECT 1    FROM (shots s      JOIN projects p ON ((p.id = s.project_id)))   WHERE ((s.id = shot_generations.shot_id) AND (p.user_id = auth.uid()))))` |
| `shot_slots` | `shot_slots_delete_owner` | DELETE | `authenticated` | `(EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = shot_slots.project_id) AND (p.user_id = auth.uid()))))` |
| `shot_slots` | `shot_slots_insert_owner` | INSERT | `authenticated` | `((EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = shot_slots.project_id) AND (p.user_id = auth.uid())))) AND (((kind = 'project_asset'::shot_slot_kind) AND (shot_id IS NULL)) OR ((kind <> 'project_asset'::shot_slot_kind) AND (EXISTS ( SELECT 1    FROM shots s   WHERE ((s.id = shot_slots.shot_id) AND (s.project_id = shot_slots.project_id)))))))` |
| `shot_slots` | `shot_slots_select_owner` | SELECT | `authenticated` | `(EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = shot_slots.project_id) AND (p.user_id = auth.uid()))))` |
| `shot_slots` | `shot_slots_service_role_all` | ALL | `service_role` | `true` |
| `shot_slots` | `shot_slots_update_owner` | UPDATE | `authenticated` | `(EXISTS ( SELECT 1    FROM projects p   WHERE ((p.id = shot_slots.project_id) AND (p.user_id = auth.uid()))))` |
| `shots` | `Service role can manage all shots` | ALL | `service_role` | `true` |
| `shots` | `Users can delete their own shots` | DELETE | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `shots` | `Users can insert their own shots` | INSERT | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `shots` | `Users can update their own shots` | UPDATE | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `shots` | `Users can view their own shots` | SELECT | `public` | `(project_id IN ( SELECT projects.id    FROM projects   WHERE (projects.user_id = auth.uid())))` |
| `slot_first_migration_map` | `slot_first_migration_map_select_owner` | SELECT | `authenticated` | `((EXISTS ( SELECT 1    FROM (shot_slots ss      JOIN projects p ON ((p.id = ss.project_id)))   WHERE ((ss.id = slot_first_migration_map.slot_id) AND (p.user_id = auth.uid())))) OR (EXISTS ( SELECT 1    FROM (attempts a      JOIN projects p ON ((p.id = a.project_id)))   WHERE ((a.id = slot_first_migration_map.attempt_id) AND (p.user_id = auth.uid())))))` |
| `slot_first_migration_map` | `slot_first_migration_map_service_role_all` | ALL | `service_role` | `true` |
| `sync_bookmarks` | `Users can view own sync bookmarks` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = sync_bookmarks.timeline_id) AND (timelines.user_id = auth.uid()))))` |
| `task_types` | `TaskTypes: authenticated read access` | SELECT | `public` | `((auth.role() = 'authenticated'::text) OR (auth.role() = 'service_role'::text))` |
| `task_types` | `TaskTypes: service role full access` | ALL | `public` | `(auth.role() = 'service_role'::text)` |
| `task_types` | `task_types_select_authenticated` | SELECT | `authenticated` | `true` |
| `task_types` | `task_types_service_role_all` | ALL | `service_role` | `true` |
| `tasks` | `Allow viewing own project tasks` | SELECT | `authenticated` | `(project_id IN ( SELECT p.id    FROM projects p   WHERE (p.user_id = auth.uid())))` |
| `tasks` | `Service role can manage all tasks` | ALL | `service_role` | `true` |
| `tasks` | `Users can create tasks` | INSERT | `public` | `(auth.uid() = ( SELECT p.user_id    FROM projects p   WHERE (p.id = tasks.project_id)))` |
| `tasks` | `Users can update their own tasks (no timing)` | UPDATE | `public` | `(auth.uid() = ( SELECT p.user_id    FROM projects p   WHERE (p.id = tasks.project_id)))` |
| `tasks` | `Users can view their own tasks` | SELECT | `public` | `(auth.uid() = ( SELECT p.user_id    FROM projects p   WHERE (p.id = tasks.project_id)))` |
| `timeline_agent_sessions` | `Users can insert own timeline agent sessions` | INSERT | `public` | `(auth.uid() = user_id)` |
| `timeline_agent_sessions` | `Users can update own timeline agent sessions` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `timeline_agent_sessions` | `Users can view own timeline agent sessions` | SELECT | `public` | `(auth.uid() = user_id)` |
| `timeline_checkpoints` | `Users can delete own timeline checkpoints` | DELETE | `public` | `(auth.uid() = user_id)` |
| `timeline_checkpoints` | `Users can insert own timeline checkpoints` | INSERT | `public` | `(auth.uid() = user_id)` |
| `timeline_checkpoints` | `Users can update own timeline checkpoints` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `timeline_checkpoints` | `Users can view own timeline checkpoints` | SELECT | `public` | `(auth.uid() = user_id)` |
| `timeline_event_contract` | `Authenticated users can read timeline event contract` | SELECT | `public` | `(auth.role() = 'authenticated'::text)` |
| `timeline_events` | `Users can view own timeline events` | SELECT | `public` | `(EXISTS ( SELECT 1    FROM timelines   WHERE ((timelines.id = timeline_events.timeline_id) AND (timelines.user_id = auth.uid()))))` |
| `timeline_update_log` | `timeline_update_log_select_authenticated` | SELECT | `authenticated` | `true` |
| `timeline_update_log` | `timeline_update_log_service_role_all` | ALL | `service_role` | `true` |
| `timelines` | `Users can delete own timelines` | DELETE | `public` | `(auth.uid() = user_id)` |
| `timelines` | `Users can insert own timelines` | INSERT | `public` | `(auth.uid() = user_id)` |
| `timelines` | `Users can update own timelines` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `timelines` | `Users can view own timelines` | SELECT | `public` | `(auth.uid() = user_id)` |
| `training_data` | `Users can delete their own training data` | DELETE | `public` | `(auth.uid() = user_id)` |
| `training_data` | `Users can insert their own training data` | INSERT | `public` | `(auth.uid() = user_id)` |
| `training_data` | `Users can update their own training data` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `training_data` | `Users can view their own training data` | SELECT | `public` | `(auth.uid() = user_id)` |
| `training_data_batches` | `Users can delete their own training data batches` | DELETE | `public` | `(auth.uid() = user_id)` |
| `training_data_batches` | `Users can insert their own training data batches` | INSERT | `public` | `(auth.uid() = user_id)` |
| `training_data_batches` | `Users can update their own training data batches` | UPDATE | `public` | `(auth.uid() = user_id)` |
| `training_data_batches` | `Users can view their own training data batches` | SELECT | `public` | `(auth.uid() = user_id)` |
| `training_data_segments` | `Users can delete their own training data segments` | DELETE | `public` | `(auth.uid() = ( SELECT training_data.user_id    FROM training_data   WHERE (training_data.id = training_data_segments.training_data_id)))` |
| `training_data_segments` | `Users can insert their own training data segments` | INSERT | `public` | `(auth.uid() = ( SELECT training_data.user_id    FROM training_data   WHERE (training_data.id = training_data_segments.training_data_id)))` |
| `training_data_segments` | `Users can update their own training data segments` | UPDATE | `public` | `(auth.uid() = ( SELECT training_data.user_id    FROM training_data   WHERE (training_data.id = training_data_segments.training_data_id)))` |
| `training_data_segments` | `Users can view their own training data segments` | SELECT | `public` | `(auth.uid() = ( SELECT training_data.user_id    FROM training_data   WHERE (training_data.id = training_data_segments.training_data_id)))` |
| `user_api_tokens` | `Users can view their own API tokens` | SELECT | `public` | `(auth.uid() = user_id)` |
| `users` | `Service role can delete users` | DELETE | `public` | `(auth.role() = 'service_role'::text)` |
| `users` | `Service role can do everything on users` | ALL | `service_role` | `true` |
| `users` | `Service role can insert users` | INSERT | `public` | `(auth.role() = 'service_role'::text)` |
| `users` | `Users can update their own auto-top-up settings` | UPDATE | `public` | `(auth.uid() = id)` |
| `users` | `Users can update their own profile` | UPDATE | `public` | `(auth.uid() = id)` |
| `users` | `Users can view their own auto-top-up settings` | SELECT | `public` | `(auth.uid() = id)` |
| `users` | `Users can view their own record` | SELECT | `public` | `(auth.uid() = id)` |
| `workers` | `Service role can manage workers` | ALL | `public` | `(auth.role() = 'service_role'::text)` |

> Policies follow three patterns: (1) `auth.uid() = user_id` direct-owner; (2) owner-via-join (`EXISTS (SELECT 1 FROM projects p WHERE p.user_id = auth.uid())`) for project-scoped tables; (3) `service_role` / `auth.role()='service_role'` full-access bypass. `tasks`, `generations`, `shots`, `shot_slots`, `attempts` use the join pattern so RLS survives project ownership changes. Full policy expressions are in `pg_policies` (re-query per §5).
### 3.11 Functions (202 in `public`)

`_duplicate_shot_with_videos_remap_jsonb, _route_slug, add_generation_to_shot, agent_node_catalog_metadata_owner_guard, agent_node_install_targets_owner_guard, agent_nodes_touch_updated_at, all_dependencies_complete, analyze_task_availability_service_role, analyze_task_availability_user, analyze_task_availability_user_pat, append_timeline_event, apply_timeline_frames, audit_shot_data_changes, auto_create_user_before_project, auto_create_variant_from_generation_insert, auto_fail_stale_tasks, auto_register_worker, auto_view_manual_upload_variant, batch_update_timeline_frames, batch_update_timeline_positions, bill_cancelled_orchestrator, broadcast_task_status_update, bytea_to_text, cascade_task_failure, check_auto_topup_trigger, check_rate_limit, check_shot_generations_functions, check_shot_generations_triggers, check_welcome_bonus_eligibility, claim_next_task_service_role, claim_next_task_user, claim_next_task_user_pat, cleanup_old_rate_limits, clear_primary_variant_reference, complete_task_with_timing, copy_onboarding_template, copy_onboarding_template_admin, copy_shot_from_share, count_eligible_tasks_service_role, count_eligible_tasks_user, count_eligible_tasks_user_pat, count_queued_tasks_breakdown_service_role, count_unpositioned_generations, create_referral_from_session, create_shot_with_generations, create_shot_with_image, create_timeline_with_initial_event, create_user_record_if_not_exists, debug_timeline_update, delete_and_normalize, delete_external_api_key, delete_project_with_extended_timeout, demote_orphaned_video_variants, derive_route_key, duplicate_as_new_generation, duplicate_shot, duplicate_shot_generations, duplicate_shot_with_videos, ensure_shot_association_from_params, ensure_shot_parent_generation, ensure_shot_parent_generation_after_insert, extract_discord_username, fix_timeline_spacing, func_claim_available_task, func_cleanup_old_logs, func_daily_task_stats, func_get_tasks_by_status, func_initialize_tasks_table, func_insert_logs_batch, func_mark_task_complete, func_mark_task_failed, func_migrate_tasks_for_task_type, func_reset_orphaned_tasks, func_update_task_status, func_update_worker_heartbeat, func_worker_heartbeat_with_logs, get_attempt_lineage, get_external_api_key_decrypted, get_recent_timeline_updates, get_shared_shot_data, get_task_cost, get_task_model, get_task_run_type, get_timeline_version, gin_extract_query_trgm, gin_extract_value_trgm, gin_trgm_consistent, gin_trgm_triconsistent, gtrgm_compress, gtrgm_consistent, gtrgm_decompress, gtrgm_distance, gtrgm_in, gtrgm_options, gtrgm_out, gtrgm_penalty, gtrgm_picksplit, gtrgm_same, gtrgm_union, handle_variant_deletion, handle_variant_primary_switch, http, http_delete, http_get, http_head, http_header, http_list_curlopt, http_patch, http_post, http_put, http_reset_curlopt, http_set_curlopt, increment_share_view_count, initialize_timeline_frames_for_shot, insert_shot_at_position, log_timeline_frame_updates, normalize_image_path, normalize_image_paths_in_jsonb, normalize_shot_timeline, per_user_capacity_stats_service_role, prevent_direct_credit_updates, prevent_drag_position_overwrites, prevent_original_variant_deletion, prevent_timing_manipulation, process_task_result, refresh_user_balance, reorder_normalized, route_backend_claim_decision, run_shot_sync_check, safe_bigint_from_text, safe_insert_task, safe_numeric_from_text, safe_update_task_status, sanitize_discord_handle, save_external_api_key, set_limit, set_new_shot_position, set_variant_project_id, show_limit, show_trgm, similarity, similarity_dist, similarity_op, slot_first_assert_project_access, slot_first_attempt_is_renderable, slot_first_attempts_project_consistency, slot_first_check_lineage_acyclic, slot_first_check_parent_acyclic, slot_first_complete_attempt, slot_first_create_composition_child_attempt, slot_first_create_pending_attempt, slot_first_delete_attempt, slot_first_duration_seconds, slot_first_enforce_slot_density, slot_first_fail_attempt, slot_first_log_primary_changed, slot_first_mark_attempt_in_progress, slot_first_prevent_primary_attempt_delete, slot_first_prevent_primary_attempt_invalidation, slot_first_prevent_shot_project_drift, slot_first_promote_attempt, slot_first_reorder_slots, slot_first_set_updated_at, slot_first_shared_shot_data, slot_first_shot_slots_project_consistency, slot_first_validate_attempt_lineage_boundaries, slot_first_validate_primary_pointer, slot_first_validate_slot_density, strict_word_similarity, strict_word_similarity_commutator_op, strict_word_similarity_dist_commutator_op, strict_word_similarity_dist_op, strict_word_similarity_op, sync_generation_from_primary_variant, sync_shot_data_update_batch, sync_shot_to_generation, sync_shot_to_generation_jsonb, sync_variant_from_generation_update, tasks_assert_claimable, text_to_bytea, timeline_sync_bulletproof, track_referral_visit, trigger_demote_on_timeline_remove, unposition_and_normalize, update_external_api_keys_updated_at, update_onboarding_config_updated_at, update_shot_image_order_disabled, update_single_timeline_frame, update_timeline_config_versioned, update_timeline_frame_debug, update_timeline_versioned, update_tool_settings_atomic, upsert_asset_registry_entry, urlencode, verify_api_token, verify_referral_security, verify_shot_sync, word_similarity, word_similarity_commutator_op, word_similarity_dist_commutator_op, word_similarity_dist_op, word_similarity_op`

> Includes the task-pipeline RPC surface used by workers/orchestrator: `claim_next_task_service_role`, `analyze_task_availability_*`, `func_worker_heartbeat_with_logs`, `func_mark_task_failed`, `add_generation_to_shot`, `batch_update_timeline_frames`, `create_shot_with_generations`, `_duplicate_shot_with_videos_remap_jsonb`, `auto_register_worker`, `cascade_task_failure`, `auto_fail_stale_tasks`, `bill_cancelled_orchestrator`, plus `urlencode`/`http_*` helpers.
### 3.12 Extensions (9)

`http, pg_cron, pg_net, pg_stat_statements, pg_trgm, pgcrypto, plpgsql, supabase_vault, uuid-ossp` — versions: http 1.6; pg_cron 1.6; pg_net 0.14.0; pg_stat_statements 1.11; pg_trgm 1.6; pgcrypto 1.3; plpgsql 1.0; supabase_vault 0.3.1; uuid-ossp 1.1

### 3.13 Row estimates (pg_class.reltuples, not exact)

| Table | est. rows |
|---|---|
| `sentinel_ticks` | 138204 |
| `slot_first_migration_map` | 121514 |
| `attempts` | 83872 |
| `shot_data_audit` | 83114 |
| `system_logs` | 67176 |
| `tasks` | 45946 |
| `generation_variants` | 40037 |
| `generations` | 38465 |
| `shot_slots` | 37642 |
| `credits_ledger` | 20759 |
| `shot_generations` | 11856 |
| `workers` | 6939 |
| `resources` | 5648 |
| `timeline_update_log` | 5493 |
| `shots` | 1273 |
| `route_backend_selectors` | 754 |
| `projects` | 478 |
| `users` | 249 |
| `timeline_events` | 114 |
| `rate_limits` | 110 |
| `route_backend_capabilities` | 70 |
| `timeline_checkpoints` | 46 |
| `dev_tasks` | 42 |
| `task_types` | 28 |
| `user_api_tokens` | 27 |
| `shared_generations` | 24 |
| `timeline_agent_sessions` | 24 |
| `timelines` | 21 |
| `referral_sessions` | 13 |
| `sync_bookmarks` | 1 |
| `pause_scaling` | 1 |
| `agent_node_media` | -1 |
| `agent_node_install_targets` | -1 |
| `agent_node_catalog_metadata` | -1 |
| `agent_nodes` | -1 |
| `referrals` | -1 |
| `external_api_keys` | -1 |
| `local_media_handles` | -1 |
| `onboarding_config` | -1 |
| `training_data_batches` | -1 |
| `training_data` | -1 |
| `training_data_segments` | -1 |
| `settings` | -1 |
| `effects` | -1 |
| `route_alias_map` | -1 |
| `model_family_for_model` | -1 |
| `timeline_event_contract` | -1 |
| `extension_install_state` | -1 |
| `extension_settings` | -1 |
| `extension_proposals` | -1 |
| `divergence_log` | -1 |

## 4. Drift: live vs `reigh-app/supabase/migrations/`

**Applied in `supabase_migrations.schema_migrations`: 465. Files in `reigh-app/supabase/migrations/`: 466 (461 standard + 2 `_applied_` + 3 `_hold_`).**

### 4.1 Applied in prod but MISSING from the repo (4) — real drift

| Version | Name | Effect (from name + repo context) |
|---|---|---|
| `20260507160420` | `drop_obsolete_claim_next_task_overload` | Drops an obsolete `claim_next_task` overload; applied to prod, no local file |
| `20260507160605` | `reload_postgrest_schema_after_claim_overload_drop` | PostgREST schema reload after the drop |
| `20260524000000` | `revert_route_backend_gating_in_claim_and_counts` | Reverts route-backend gating added 20260506110000–20260513120200 |
| `20260524010000` | `drop_tasks_assert_claimable_trigger` | Drops the `tasks_assert_claimable` trigger (created by `20260513120200_tasks_claimable_trigger.sql`, which IS in the repo and applied) |

**Consequence:** a fresh DB built by replaying the repo migrations would end in a state prod deliberately moved away from — it would still have the `tasks_assert_claimable` trigger and route-gated claims that prod reverted. Migrations 20260513120200 (create trigger) and 20260524010000 (drop it) both exist in prod history; only the create is in the repo. The repo's last `supabase/` change is 2026-06-24 (`d898ddb7`), so the four reverts were likely pushed to prod outside this repo's migration dir.

### 4.2 Applied manually to prod, not tracked in `schema_migrations` (2) — `_applied_` prefix

| File | Effect | Drift note |
|---|---|---|
| `_applied_20250105000000_create_external_api_keys.sql` | Created `external_api_keys` (table, indexes, RLS, trigger) | Applied out-of-band. **Version `20250105000000` collides with the tracked migration `20250105000000 add_animate_character_task_type`**, so this file can never be applied via `supabase` migration tracking; it lives only as an `_applied_` marker. Live table matches the file (verified: `external_api_keys` + `idx_external_api_keys_user_id`/`_service` indexes + 4 RLS policies + `update_external_api_keys_updated_at` trigger all present live). `20260105300000_vault_encryption_for_api_keys.sql` (tracked, applied) then `ALTER TABLE`-ed it (`vault_secret_id` present live). |
| `_applied_20260225000000_backfill_pair_shot_generation_id.sql` | Data backfill of `generations.pair_shot_generation_id` | Pure data backfill; no schema surface. |

### 4.3 Intentionally NOT applied (3) — `_hold_` prefix

| File | Why held |
|---|---|
| `_hold_20250910150000_fix_security_warnings.sql` | Security-linter fixes (search_path, extension-in-public) — superseded by later `security_audit_fixes` (20260130200000) and friends, which ARE applied |
| `_hold_20251218000000_dynamic_timeline_spacing.sql` | Old spacing algorithm — superseded by applied `20251218100000_dynamic_timeline_spacing` |
| `_hold_20260414_shot_final_videos_single_segment_identity.sql` | Candidate redesign of `shot_final_videos` view — not shipped; the view exists live but built by `20260123000001_shot_final_videos_view` |

### 4.4 Other findings

- **Top-level `supabase/` dir is a leftover**: it contains only an empty `functions/` and `.temp`; `reigh-app/supabase/` is the current, live schema source.
- **`reigh-worker-orchestrator-capacity-reconciler/sql/`** holds 7 SQL files (mostly duplicates of main migrations + `20260514000000_create_worker_capacity_intents.sql`). There is **no `worker_capacity_intents` table in the live DB** — that migration was never applied to prod (or was dropped). The reconciler variant's schema is a separate, likely stale artifact.
- **No live object is missing from the migrations** in the reverse direction: every live table/enum/trigger maps to an applied migration (the `_applied_` external_api_keys being the manual exception).
- `_applied_`/`_hold_` files are skipped by `supabase db reset` — a fresh local reset will NOT create `external_api_keys` (version collision) and will NOT apply the held files; it WILL create `tasks_assert_claimable` (see 4.1).

## 5. Re-obtaining the schema (procedure; only if needed)

The dump above is complete as of 2026-08-21. To re-obtain or extend it, from `reigh-app/` (password stays in `.env`):

```bash
# 1. Load DATABASE_URL from reigh-app/.env into the environment (never echo it)
set -a; . ./.env; set +a

# 2. Connect read-only over SSL; psql 16 is at /Library/PostgreSQL/16/bin/psql
psql "$DATABASE_URL" -c 'SET statement_timeout = 30000; SELECT version();'

# 3. Example SELECT-only dump used for this doc (indexes):
psql "$DATABASE_URL" --tuples-only --no-align --field-separator=$'\t' -c "SET statement_timeout=120000; SELECT schemaname, tablename, indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY 1,2;"

# 4. Per-object sources (all SELECT-only):
#    tables+columns:   information_schema.columns / pg_attribute + pg_attrdef
#    enums:            pg_type + pg_enum
#    triggers:         pg_trigger + pg_proc (exclude tgisinternal)
#    RLS:              pg_policies, pg_class.relrowsecurity
#    functions:        pg_proc + pg_get_function_identity_arguments
#    FKs/unique/check: pg_constraint (contype 'f'/'u'/'c')
#    applied migrations: supabase_migrations.schema_migrations
```

Alternative tools present on the workstation: `supabase` CLI (`supabase db dump` requires db-url/local stack), and the repo debug CLIs (`python scripts/debug.py sql "SELECT …"` from `reigh-app`; `./debug` from workspace root) which use the same `DATABASE_URL`.

## 6. Gaps / unverified

- **Full policy expressions** are included truncated to 160 chars for readability; complete `pg_policies.qual`/`with_check` text is in the DB (re-query via §5).
- **Function bodies** are not included (202 functions; names only). Bodies are in `pg_proc.prosrc` — re-query if a specific RPC's logic is needed for the migration.
- **View definitions** included truncated to 200 chars; full text via `pg_get_viewdef(oid)`.
- **Data contents** were never read (schema-only dump by design); row counts are `reltuples` estimates, `-1` = never analyzed.
- **Local dev DB** does not exist on this workstation (Docker down, no supabase stack); no DEV-vs-PROD comparison was possible. Everything above is PROD.
- The 4 prod-applied-but-uncommitted migrations (§4.1) are the only object-level divergence found; their exact SQL is not recoverable from the repo (only from prod's `pg_proc`/history or the team's unpushed branch).