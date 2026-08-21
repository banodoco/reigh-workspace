# Unified Model Prior Art: the intended data model and decision history

**Source docs:** `docs/unified-data-model-plan-v{2..10}-20260813.md`, `docs/unified-data-master-plan-20260814.md`, `docs/astrid-first-sprint-plan-20260813.md`, `docs/astrid-first-sprint-plan-review-20260813.md` (all under /Users/peteromalley/Documents/reigh-workspace/)
**Prepared:** 2026-08-21 (read-only research; no repo files touched)

## 1. Summary

Eight consecutive plan versions (v2→v10) plus a master plan (2026-08-14) and an execution sprint plan trace the full design arc for replacing Reigh/Astrid's scattered file/Postgres/Supabase authorities with one durable local data substrate. The trajectory is a controlled collapse:

- **v2–v4 (2026-08-13):** one product, one logical model, two deployments (local SQLite, cloud Postgres→Turso); *preservationist migration* posture; a strangler importer carries existing project data across.
- **v5:** freezes the core ontology — **tasks execute; everything else is an event** — with mandatory task streams and a classification pass before import.
- **v6:** pivots to a **destructive greenfield** (27 tables); Postgres is dropped as an intermediate engine; only an optional file bootstrap importer survives.
- **v7:** **media-first** simplification to **22 tables**; references built in; event hash-chaining, plans' bookkeeping, and six v6 tables cut.
- **v8:** "ship Astrid first" standalone; importer becomes required one-shot cutover machinery; timeline continuity is a release veto.
- **v9:** a 20-brief usage census turns v8 into an *integration* plan for the existing Astrid — multi-source importer, 115-row disposition matrix, 22 tables kept, 16–29 calendar weeks.
- **v10 (normative baseline):** decisive reversal — **no legacy migration at all**. Fresh 20-table SQLite (14-table agent-agnostic kernel + timeline/shots/references packs), old authorities **deleted** rather than imported, only `media import` (bytes) survives. Plans/steps/groups/sessions/threads/leases/Supabase/FSA are cut. Runs become direct group handles over immutable tasks.
- **Master plan (2026-08-14):** lifts v10 into a vision: a reusable 14-table kernel plus domain *packs* (plugin laws, conformance kit, "boundary now, loader later"). Astrid = kernel + 3 in-tree packs; a future software-engineering agent = same kernel + its own packs.
- **Sprint plan + review:** 8-sprint (4-engineer) execution sequence with sprints 9–10 as conditional reserve; adversarial review → NEEDS REVISION with 10 concrete fixes (already applied per the 2026-08-14 revision note).

**Key facts**

- Normative target: **20 tables = 14 kernel + 1 timeline + 2 shots + 3 references**; one SQLite database + one managed-media root per product instance; one repository-owned writer (`BEGIN IMMEDIATE`); fresh projects only.
- Foundation invariant: **tasks execute; everything else is an event; every exact asset is media** — plus, in v10, "references add project semantics to media."
- Identity: SHA-256 of verified bytes for media (`UNIQUE (project_id, content_hash)`); UUID canonical timeline identity with ULID as a supported route address (v10 bridge); not a kernel-wide ULID scheme.
- **No stated strategy for moving Reigh/Postgres data into Astrid SQLite** — the final decision is explicitly *not to*: v10 deletes legacy/Supabase/Postgres authorities and imports bytes only. Reigh survives as the editor frontend over a preserved bridge wire contract.
- Implementation status: the v10 kernel schema, three pack migrations, schema-pack registry, and partial repositories already exist in `Astrid/astrid/` (verified 2026-08-21); executor, bridge, CLI/SDK, backup/doctor remain on the sprint plan.
- Decision makers referenced in the docs: the product owner ("the user"), the "Claude Fable 5 conversation" (v2/v3 critique), a "design-review chat" (v6), a 20-brief usage census (v9), and an OpenRouter chat review (v10 demolition). Plans do not name individual humans.

## 2. Condensed intended unified model (v10 + master plan, normative)

### 2.1 Layering and table inventory

| Layer | Tables | Role |
|---|---|---|
| **Kernel (14)** | `schema_migrations`, `projects`, `event_streams`, `events`, `command_receipts`, `runs`, `evidence_items`, `tasks`, `task_dependencies`, `execution_attempts`, `task_outputs`, `media`, `media_locations`, `media_relations` | Reusable task/event/run/media substrate. Media is deliberately kernel citizenship (source, diffs, logs, reports, generated assets all use it). |
| **Timeline pack (1)** | `timelines` | Editor document + asset registry, per-aggregate stream, whole-document CAS. |
| **Shots pack (2)** | `shots`, `shot_items` | Project-scoped shot containers; ordered exact-media placements. |
| **References pack (3)** | `project_references`, `media_references`, `reference_links` | Named entities (character/place/object/clothing/other), canonical/contextual media, typed links. |

Pack manifests declare `id`, `version`, `depends_on`, `migrations[]`, `stream_types[]`, `event_kinds[]`, `command_kinds[]`, `repositories[]`, `conformance[]`, `cli_mounts{}`, `bridge_mounts[]`. Startup performs one explicit `register_pack()`; no dynamic loader at GA. Catalog is *derived* from core manifest + installed pack manifests (not a hardcoded 20).

### 2.2 Entities and key fields

- **`schema_migrations`** — `PRIMARY KEY (pack, version)`, `name UNIQUE (pack, name)`, `checksum`, `applied_at`. Forward-only, dependency-ordered; "too-new" schema opens read-only/fails without mutation.
- **`projects`** — `id` PK, `slug UNIQUE`, `name`, `settings_json` (JSON), `event_head_seq` (project-wide event counter), `created_at`, `updated_at`. Project is the kernel isolation boundary ("workspace" in future products is a presentation alias).
- **`event_streams`** — `id` PK, `project_id` FK→projects (CASCADE), `stream_type` (open text, validated by registry: core registers `core.project`, `core.task`, `core.run`; timeline registers `timeline.timeline`), `aggregate_id`, `head_seq` (CAS token), `created_at`, `UNIQUE(project_id, stream_type, aggregate_id)`.
- **`events`** — `event_id` PK, `project_id` FK, `project_seq` (>0, `UNIQUE(project_id, project_seq)`), `stream_id` FK, `seq`, `subject_type`/`subject_id` (polymorphic — kernel records pack aggregates without FK), `changes_json` (JSON array), `kind` (namespaced, registry-validated), `schema_version`, `idempotency_key`, `txn_id`, `actor_kind` IN (local, system, executor), `payload_json`, `created_at`.
- **`command_receipts`** — `PRIMARY KEY (project_id, idempotency_key)`, `request_hash`, `command_kind`, `txn_id UNIQUE`, `primary_stream_id`, `resulting_stream_seq`, `first_project_seq`/`last_project_seq`, `event_ids_json`, `result_json`. Identical replay returns stored receipt; same key + different bytes fails before mutation.
- **`runs`** — `id` PK, `project_id` FK, `event_stream_id UNIQUE` FK, `kind`, `status` IN (running, succeeded, failed, cancelled), `title`, `input_json`, `result_json`, `started_at`, `finished_at`. Coordination/observation container; zero-or-many direct child tasks; never an executable parent; no step graph.
- **`evidence_items`** — `id` PK, `run_id` FK (CASCADE), optional `task_id` FK (SET NULL; must be a direct child of that run), `kind`, `summary`, `data_json`, optional `media_id`, `created_at`.
- **`tasks`** — `id` PK, `project_id` FK, `event_stream_id UNIQUE` FK (one task stream, begins `task.created`), nullable `run_id` + `run_ordinal` (checked pair; `UNIQUE(run_id, run_ordinal)` partial index), `capability`, `spec_json`, `spec_hash`, `input_manifest_json` (JSON array), `status` IN (queued, blocked, running, succeeded, failed, cancelled), `priority`, `available_at`, `max_attempts`, `winning_attempt_id`, `cancel_request_id`/`cancel_requested_at`, timestamps. Immutable executable spec; terminal tasks never resurrect.
- **`task_dependencies`** — `PRIMARY KEY (task_id, depends_on_task_id)`, `kind` IN (hard, soft), `ordinal`, `CHECK (task_id <> depends_on_task_id)`; same-project, acyclic, repository-enforced.
- **`execution_attempts`** — `id` PK, `task_id` FK (RESTRICT), `attempt_no` (`UNIQUE(task_id, attempt_no)`), `executor_id`, `status` IN (claimed, running, succeeded, failed, cancelled, expired), `status_version` (fencing CAS), `lease_id`, `lease_expires_at`, `heartbeat_counter`, `last_heartbeat_at`, `progress_json`, `error_json`, timestamps. Heartbeats are the deliberate non-event exception.
- **`task_outputs`** — `PRIMARY KEY (task_id, ordinal)`, `role`, `media_id` FK, `is_primary` (0/1, `CHECK (role = 'result' OR is_primary = 0)`), `params_json`; one primary result per task (partial unique index).
- **`media`** — `id` PK, `project_id` FK, `media_kind` IN (image, video, audio, text, document, data, other), `mime_type`, `byte_size`, `content_hash` (**`UNIQUE(project_id, content_hash)` — SHA-256 of verified bytes is identity**), `metadata_json`, `created_at`.
- **`media_locations`** — `id` PK, `media_id` FK (CASCADE), `realm` IN (managed_local, external_local, remote), `locator`, `verified_at`, `UNIQUE(media_id, realm, locator)`. Location is replaceable; never identity.
- **`media_relations`** — `PRIMARY KEY (from_media_id, to_media_id, kind, ordinal)`, `kind` IN (derived_from, variant_of, uses_as_input, mask_for, audio_for), `metadata_json`; acyclic (repository-enforced; one variant parent per media).
- **`timelines`** — `id` PK, `project_id` FK, `event_stream_id UNIQUE` FK, `name`, `document_json`, `asset_registry_json`, timestamps. Whole-document CAS: save atomically updates document + registry + appends event + advances head (`config_version` = `head_seq`) + writes receipt; stale `expected_version` → 409, no mutation.
- **`shots`** — `id` PK, `project_id` FK, `name`, `sort_key` (`UNIQUE(project_id, sort_key)`; lexicographic ordering), `metadata_json`, timestamps.
- **`shot_items`** — `id` PK, `shot_id` FK (CASCADE), `media_id` FK (RESTRICT), `sort_key` (`UNIQUE(shot_id, sort_key)`), `source_frame`, `metadata_json`.
- **`project_references`** — `id` PK, `project_id` FK, `kind` IN (character, place, object, clothing, other), `name`, `description`, `metadata_json`, `archived_at`.
- **`media_references`** — `id` PK, `reference_id` FK, `media_id` FK, `role` IN (canonical, used_as_input, depicts, inspired_by), `context_task_id` FK (required iff role=used_as_input), `ordinal`, `is_primary` (one primary canonical per reference), `metadata_json`; uniqueness partial indexes for global vs context-scoped rows.
- **`reference_links`** — `PRIMARY KEY (from_reference_id, to_reference_id, kind)`, `kind` IN (belongs_to, wears, located_in, associated_with, related_to); symmetric links stored in canonical order (repository-enforced).

### 2.3 Relations / integrity rules

- **Foreign keys point inward only**: packs FK to kernel tables; the kernel never FKs to a pack; kernel events reference pack rows only via `events.subject_type`/`subject_id`. Cross-pack exchange uses kernel currencies only (`project_id`, `task_id`, `media_id`). No pack-to-pack FKs.
- **One semantic writer**: all mutations go through repositories on one kernel-owned write queue and short `BEGIN IMMEDIATE` unit of work (check idempotency → allocate `project_seq` → append registered events → advance heads → update projections → materialize runs/tasks/media → write receipt → commit). Bridge, CLI, SDK, executor, media import, and pack repositories are all clients.
- **Stream discipline**: every task has exactly one same-project stream starting `task.created`; timeline saves CAS against the timeline stream head; runs have their own stream; media/references/shots use the project stream (no independent CAS needed).
- **Conformance kit** (reusable): identical replay, mismatched-key rejection before mutation, statement-boundary old-or-complete crash behavior, same-project assertions, plus domain checks (timeline CAS, shot ordering, reference primary rules).
- **Database pragmas**: `foreign_keys=ON`, WAL, `synchronous=NORMAL` (FULL as documented durability option), `busy_timeout=5000`.

### 2.4 Statuses, IDs, timeline model, storage

- **Status enums:** tasks: queued/blocked/running/succeeded/failed/cancelled; runs: running/succeeded/failed/cancelled; attempts: claimed/running/succeeded/failed/cancelled/expired.
- **IDs:** kernel tables use TEXT PKs; UUID remains canonical timeline identity and ULID is a supported route address in the timeline bridge — explicitly *not* a kernel-wide ULID scheme (master plan §5.6). Media identity is project-scoped SHA-256 of verified bytes. Slugs/names/locators are never identity.
- **Timeline model:** whole-document JSON (`config` + `registry.assets`) with numeric opaque `config_version` CAS; bridge routes `GET /health`, `GET /projects`, `GET /projects/:slug/timelines`, timeline load/save, `GET|HEAD .../assets/:key` (single-range 206 / invalid-range 416); 409 `timeline_version_conflict`, 422 `schema_incompatible`, 404 envelopes.
- **Storage layout:** one standalone SQLite application database (project catalog + all projects) + one managed-media root, owned by one Python process. Managed copy is the media-import default; `external_local` reference-in-place is explicit opt-in; remote realm reserved. No per-project file authorities, no sidecars, no JSONL semantic writers.

## 3. Stated migration / reconciliation strategy (Reigh/Postgres → Astrid SQLite)

**The definitive answer in the final plans is: there is no data migration.** v10 §1 and the master plan §4.1 are explicit:

- Start from a **fresh SQLite database**. Old project/timeline/run/thread/session/plan/lease/event-chain/audit-ledger/Supabase/editor-FSA authorities are **not migrated, not conditionally supported** — their modules and storage-specific tests are **deleted** as replacements land.
- The only ingestion is `media import <path>`: walk files, hash and probe bytes, copy into managed storage by default, create `media`/`media_locations` rows through the normal repository. **No semantic history is imported.**
- Reigh remains Astrid's frontend; its existing bridge wire shape, timeline CAS behavior, asset Range serving, and draft-safety rules are preserved (a mounted Astrid-facing surface), but no editor rewrite and no general plugin host.
- Supabase/Postgres is never an intermediate engine and never an input: "Supabase append/timeline I/O, hosted worker, RunPod, publication, cloud sync → CUT from local product / DEFER feature."

Historical (superseded) strategies for context — v2/v4/v5 would have migrated existing projects (multi-source importer, classification, cutover, parity gates); v6 kept an optional bootstrap importer; v7/v8 made a one-shot importer + continuity harness a release veto; v9 planned a full multi-authority import program. All of that was **demolished by v10**. For a future "Reigh runs on Astrid SQLite" effort, the prior art says: re-point the editor at the repository bridge, import media bytes, and delete the Postgres/Supabase estate — do not port rows.

## 4. Decision log (version → change vs previous)

| Version | Date | What changed |
|---|---|---|
| **v1 report** (`unified-data-model-report-20260813.md`) | 2026-08-13 | Design evidence + current-state record (superseded as a plan; remains the source of the domain-noun inventory). |
| **v2** | 2026-08-13 | Local SQLite first: Astrid/Python owns one SQLite DB per project (`projects/<slug>/.astrid/project.sqlite3`); browser editor goes through the bridge (never opens the DB); Turso cloud later via fresh-DB + migration replay; ULIDs + `legacy_ids`; WAL + `synchronous=FULL` initially. |
| **v3** | 2026-08-13 | "One system, two deployments": local SQLite deployment + cloud deployment (Postgres → Turso); same `/api/astrid/v2`; project-scoped tenancy (no `workspaces`); core DDL "retained unchanged"; retires the two-plane terminology. |
| **v4** | 2026-08-13 | 20-direction evidence investigation; pre-freeze DDL errata (adds `timeline_references`, `task_outputs`, receipts, change bookmarks); FSA identified as second timeline authority; single-writer not yet true (~10 direct-writer groups); milli-credit = $0.00001; 9-case cancellation matrix; canonical export = re-emission; measured 327 `.from()` callsites / 205 files. |
| **v5** | 2026-08-13 | Freezes ontology: **tasks execute; everything else is an event**; mandatory task stream + `projected_event_seq`; task-admission test; classification pass before import; image understanding = event, GPU generation = task; delegated cloud execution facts linked but not a second task authority. |
| **v6** | 2026-08-13 | **Destructive greenfield** (27 tables): tear down Supabase/cloud/accounts/billing/sync; Postgres dropped as intermediate (Turso/libSQL only); heartbeat events dropped; `materialization_receipts`; one optional `bootstrap import`; loopback pairing editor; 10 route families. |
| **v7** | 2026-08-13 | **Media-first, 22 tables** (27 − 8 + 3): renames `media_artifacts`→`media` etc.; adds references (`project_references`, `media_references`, `reference_links`); cuts generations/generation_variants/execution_submissions/materialization_receipts/command_receipt_events/change_bookmarks/timeline_references/actors; 4 stream types; drops event hash chaining and row_version parity counters; lexicographic shot `sort_key`; WAL NORMAL; loopback editor default. |
| **v8** | 2026-08-13 | **Ship Astrid first** (standalone): model unchanged (22 tables); timeline sync = first-class continuity gate; importer promoted to required cutover machinery (Stage 0 freeze → Stage G flip); `timeline_references` = read-only projection; CLI/SDK/execution/backup/doctor become product surfaces; strict teardown rule (no FSA/Supabase writers at GA). |
| **v9** | 2026-08-13 | 20-brief usage census → **integration plan** for the existing Astrid: 22 tables retained; multi-authority importer (Stage G classifies project files, two run dialects, sidecars); 115-row disposition matrix (INTEGRATE/KEEP-FILE-SIDE/DELETE/DEFER); 553 tests; doctor split (read-only + `--dev`); zero-config/no secrets; 23-family CLI; estimate 16–29 wk (4 eng, minimal) / 23–38 wk (deep). |
| **v10** | 2026-08-13 | **Decisive greenfield reversal**: no legacy preservation — fresh DB, delete old code, no importer beyond `media import`; **20 tables** (22 − `run_steps` − `run_step_tasks`); runs = direct group handles (`tasks.run_id`/`run_ordinal` + `task_dependencies`); plans/steps/groups/repeat/`for_each`/supersede/cursor/ack/hook/leases/sessions/threads CUT; 8 top-level CLI families; bridge wire shape kept; editor FSA deleted; 3-phase delivery; 12 GA acceptance items; 4 open implementation choices. |
| **v10 (revision)** | 2026-08-14 | Plugin/generalizable layering folded in: 14-table agent-agnostic **kernel** + in-tree timeline/shots/references **packs**; 5 plugin laws; pack-scoped migrations; registry-validated vocabularies; conformance kit; boundary now, loader later. |
| **Master plan** | 2026-08-14 | Vision document: kernel = 14 portable primitives; packs = manifest + migrations + registries + repositories + conformance; generalization map to a software-engineering agent; NOW (Astrid composition) / LATER (extract core when 2nd agent is real) / NEVER (no dormant platform, no loader, no accounts/billing/sync, no plan machinery, no generic repair); 10 vision principles; 13 strategic open questions. |
| **Sprint plan** | 2026-08-13 (rev. 08-14) | 8-sprint base forecast (4 engineers; 32–46 PW → 5–6 net PW/sprint); critical path schema→repositories→executor/media/bridge→SDK/CLI→serve/backup/doctor→dogfood/GA; sprints 9–10 conditional reserve; 3-engineer ≈ 11–13 sprints; solo ≈ 20–26; S1 backlog S1-01…S1-17 + review checklist. |
| **Sprint-plan review** | 2026-08-13 | Verdict **NEEDS REVISION**: (1) references/shots repositories scheduled in S4 but Phase 1 gate closes S3 (v10 §3 contradiction); (2) vocabulary freeze (S1-16 → S4) after its S2 media consumer; (3) S5 eight-family gate precedes S6 implementations; (4) 6-sprint and 3-engineer forecasts not reconciled; (5) weak media/backup command-level conformance acceptance. 10 concrete fixes; no architecture redesign. |

## 5. Open questions from the plans

**From the master plan §6 (strategic; not blockers for v10 delivery):**
1. When does the "second agent" arrive, and what qualifies it as real? (Lean: funded milestone + named owner + ≥2 E2E journeys.)
2. Does the kernel become a published library or only an internal contract? (Lean: private shared library on 2nd composition; public only after 2 shipped products.)
3. What triggers a loader, and how dynamic? (Lean: explicit composition now; trusted application-declared set later; no discovery/hot-load.)
4. Where do identity/accounts/tenancy live when they arrive? (Lean: app shell/external service; `projects` stays the isolation boundary.)
5. Does `media` stay in the kernel at larger scale? (Lean: yes; scale bytes via location realms.)
6. Is "media" the permanent cross-agent term? (Lean: keep schema `media`; product copy may say "asset".)
7. Is the references pack reusable as-is? (Lean: keep Astrid-only for now; test reuse in 2nd agent.)
8. Which pack aggregates deserve their own stream/CAS? (Lean: per aggregate; timeline yes, shots/references default to project stream.)
9. Pack disable/upgrade/uninstall semantics? (Lean: fixed composition, forward-only migrations, no destructive uninstall in v10.)
10. How stable is the manifest contract? (Lean: internal contract now; version on `core/` extraction.)
11. How do pack CLI/bridge mounts coexist? (Lean: composition-owned mounts; Astrid keeps exactly 8 top-level families.)
12. When may packs depend on one another? (Lean: manifest dependencies OK; kernel currencies only for data exchange.)
13. When should the kernel itself evolve? (Lean: only when ≥2 real compositions share a primitive.)

**From v10 §7 (implementation choices, must close before named milestones — tracked via the sprint plan's S1-16 decision artifact):**
1. Managed-media root + reference-in-place/staging policy — before Phase 1 media fixtures (S1-16a).
2. Bounded fan-out limit (max children/events per transaction) + chunked continuation envelope — before Phase 1 receipt tests (S1-16b).
3. Closed vocabularies: media relation kinds, reference kinds/roles/link kinds, evidence kinds — before references/media repositories freeze (S1-16c).
4. Supported OS/browser/package matrix owner + deadline (S1-16d; Sprint 5 deadline before Phase 2).

**From the sprint-plan review (delivery-mechanics questions):**
- Dependency-preserving compressed 6-sprint map (or demote 6 to a theoretical lower bound).
- Reconcile 3-engineer forecast (11–13 sprints) vs headline 10–12.
- Explicit idempotency/envelope conformance for `backup create/restore`, or a normative v10 amendment exempting operational commands.

**Observed gap:** the sprint plan repeatedly references a required `docs/astrid-v10-implementation-decisions.md` artifact; it is **not present** in `docs/` as of 2026-08-21, so choices 1–4 above are still open.

## 6. Pointers to exact plan files/sections

- **Vision/architecture:** `docs/unified-data-master-plan-20260814.md` — §2.1 kernel table roles; §2.2 pack model; §2.3 plugin laws (5 laws); §2.4 extension seams; §3 generalization map + 3.4 factoring test ("delete a pack, kernel stays green; compose a second agent, no kernel change"); §4 NOW/LATER/NEVER; §5 principles (5.1 atomic truth, 5.2 events, 5.3 exact bytes, 5.4 one writer, 5.5 fenced attempts, 5.6 ULID/UUID identity, 5.7 conformance kit, 5.8 dependency direction, 5.9 generalize from sameness, 5.10 modular operation); §6 open questions.
- **Normative schema/contract (controls if docs differ):** `docs/unified-data-model-plan-v10-20260813.md` — §1 cut list + 1.1 complete v9 disposition ledger; §2.1 table inventory + run-grouping; §2.2 full creation DDL (PRAGMAs, all 20 tables, indexes); §2.3 repository constraints + command unit shape; §3 three phases + gates; §4.1 eight CLI families; §4.2 SDK + frozen bridge routes/payloads/errors; §4.3 backup/doctor/secrets; §5.1 kept invariants; §5.2 dropped invariants; §5.3 twelve GA acceptance items; §6 risks; §7 resolved decisions + 4 open choices; §8 final recommendation.
- **Execution sequence:** `docs/astrid-first-sprint-plan-20260813.md` — §1.3 estimate/forecast table; §2.1 sprint map (S1–S10); §2.2 parallel-lane openings; §2.3 GA-acceptance coverage table; §3 per-sprint detail (S1 backlog S1-01…S1-17 in §6, gates in §3); §4 team variants; §5 risks/buffer policy.
- **Adversarial review:** `docs/astrid-first-sprint-plan-review-20260813.md` — §1 coverage matrices; §2 contradictions (2 high-severity); §3 weak acceptance criteria; §4 internal consistency; §6 ten concrete fixes.
- **Decision history:** `docs/unified-data-model-plan-v2|v3|v4|v5|v6|v7|v8|v9-20260813.md` — each has a "Changes vs previous" section and a head disposition table (§1). v7 §1.2 has the exact 27→22 arithmetic; v9 §1 has the 115-row disposition matrix; v4 §1 has the 20-direction verdicts.
- **Execution program (not read for this doc):** `.megaplan/initiatives/astrid-first/NORTHSTAR.md` (+ chain.yaml, milestone briefs) operationalizes the sprint plan.
- **Implementation status in repo (verified 2026-08-21):** `Astrid/astrid/core/migrations/sql/core/0001_initial.sql` (pack-aware `schema_migrations` PK `(pack,version)`, open `stream_type`, kernel tables; zero occurrences of `run_steps`/`run_step_tasks`); `Astrid/astrid/packs/{timeline,shots,references}/migrations/0001_initial.sql`; `Astrid/astrid/core/schema_packs/{manifest,registry,standard}.py` with `STANDARD_SCHEMA_PACKS = ("timeline","shots","references")` and `register_pack`; `Astrid/astrid/core/migrations/runner.py` (dependency-ordered, checksummed, too-new detection); `Astrid/astrid/core/repositories/` (projects, tasks, runs, evidence, media, events — partial); tests `Astrid/tests/v10/test_catalog_migrations.py`, `Astrid/tests/packs/test_pack_migration_m4_shells.py`. Executor, bridge server, CLI/SDK, backup/doctor, and the remaining repositories are still sprint-plan items (planned).

## 7. Gaps / unverified

- `.megaplan/initiatives/astrid-first/NORTHSTAR.md`, `chain.yaml`, and milestone briefs were not read (execution-program level, outside this doc's scope); they may contain later decisions not reflected here.
- `docs/astrid-v10-implementation-decisions.md` (required by sprint S1-16a–d) is absent from `docs/` — the four v10 §7 vocabularies/layout/fan-out/matrix choices remain formally open.
- Middle sections of the v10 plan were read with per-line truncation; the full DDL for `events`, `tasks`, `task_outputs`, and `evidence_items` was partially elided, though every table's identity/relationship/constraint columns and the complete index list were captured. The sprint plan's ticket-level prose (S2–S8 work items) was read in full; lines elided at the 768-char boundary were lists, not decisions.
- "Who made each decision": the plans attribute decisions to review conversations ("Claude Fable 5 conversation" v2/v3, "design-review chat" v6, 20-brief census v9, OpenRouter chat review v10) and the product owner; no individual names are recorded in the docs. [INFERENCE] The same planner authored the series; revision notes (2026-08-14) state the master-plan layering and review fixes were "folded in."
- Repo presence checks were shallow (schema/migrations/registry/repository modules + test files only); full conformance to the 20-table catalog (indexes, CHECKs, partial indexes) and the state of executor/bridge/CLI work were not exhaustively verified — treat "implemented" as "kernel schema + pack scaffolding + partial repositories present," not "Phase 1 gate passed."
- Whether a Reigh-side (reigh-app/reigh-worker) analysis of bridge/worker contracts already exists elsewhere in this migration-context series is outside this doc; cross-reference the sibling docs (e.g. ReighAppData, LiveDbProbe, ReighTaskPipeline, ReighWorkerExec outputs) for current-state grounding.
