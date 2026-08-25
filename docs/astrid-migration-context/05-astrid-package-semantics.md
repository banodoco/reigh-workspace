# 05 — Astrid package semantics: how the package/CLI operates on data, and the intended unified model

**Scope:** Behavioral model of the `Astrid/` Python package as implemented in code (CLI + SDK + store layers), and the intended unified data model from the workspace plan docs. Every design-intent item is tagged **DESIGN/PLANNED**; everything verified in `Astrid/` source or a live database is tagged **IMPLEMENTED**. Read-only research; no repo files were modified.

**Prepared:** 2026-08-21. Sources: `Astrid/` source tree (paths cited inline), live SQLite at `Astrid/projects/.astrid/astrid.sqlite3`, and the plan docs under `docs/` (see §8).

## 1. Summary

Astrid today is a **local-first Python toolkit** whose semantic authority is one SQLite database (`<projects_root>/.astrid/astrid.sqlite3`) plus a content-addressed managed-media tree (`<projects_root>/.astrid/media/sha256/…`), both owned by exactly one repository write queue (single-writer). The implemented schema is the **20-table v10 kernel + packs model**: a 14-table agent-agnostic kernel (`projects`, `event_streams`, `events`, `command_receipts`, `runs`, `evidence_items`, `tasks`, `task_dependencies`, `execution_attempts`, `task_outputs`, `media`, `media_locations`, `media_relations`, `schema_migrations`) plus three in-tree schema packs — timeline (1 table `timelines`), shots (2 tables), references (3 tables). Verified by reading `Astrid/astrid/core/migrations/sql/core/0001_initial.sql` + the three pack migrations + a live database whose `schema_migrations` shows all four packs applied and exactly these 20 tables present.

**Key facts**

- **CLI surface (IMPLEMENTED):** `python3 -m astrid` dispatches exactly eight families — five product (`projects`, `timelines`, `media`, `tasks`, `runs`) and three operational (`serve`, `doctor`, `backup`) — plus two nested mounts (`timelines shots`, `media references`). One verb = one SDK call. Source: `Astrid/astrid/core/gateway/__init__.py`, `Astrid/astrid/core/cli/domain_product.py` (`PRODUCT_FAMILIES`), `Astrid/astrid/packs/*/schema-pack.yaml` (`cli_mounts`).
- **SDK surface (IMPLEMENTED):** `import astrid` exposes `discover`, `get_capability`, `invoke`, `generate`, `render`, `renderer_main`, `support`, `read_events`, `subscribe_events`, `AstridClient` (lazy), DTOs (`RenderContext`, `Capability`, `InvocationResult`, …) and the exception taxonomy. The client exposes **seven typed services**: `projects`, `timelines`, `media`, `tasks`, `runs`, `references`, `shots` (`Astrid/astrid/sdk/client.py`).
- **Storage (IMPLEMENTED):** all semantic state in one SQLite file per projects root; every meaningful mutation is an ordered, namespaced, hash-chained **event** appended atomically with its projection and a **command receipt** (idempotency). Tasks execute; everything else is an event; every exact asset is media (SHA-256 identity).
- **Timelines (IMPLEMENTED):** whole-document CAS — `timelines.document_json` + `asset_registry_json` advance atomically against the timeline stream head (`config_version` = stream head); stale saves → 409 `timeline_version_conflict`, zero mutation.
- **Understanding/media outputs (IMPLEMENTED):** understanding = zero-task `runs` + `evidence_items` (closed five-kind vocabulary: observation/measurement/validation/decision/error) pointing at exact media; generation/render = `tasks` → `execution_attempts` → `task_outputs` → `media`. The legacy file-based `runs/` dirs (e.g. `Astrid/runs/video-understanding/manifest.json`) are **pre-kernel legacy**; the kernel does not read them.
- **Intended unified model (DESIGN/PLANNED):** the plan docs (v10 + master plan + sprint plan) define exactly the 20-table schema that is now implemented, a kernel+packs layering with five plugin laws, an eight-family CLI, and an explicit **no data migration** posture for Reigh/Postgres → Astrid SQLite (v10 §1: import useful media bytes only; delete legacy authorities). The master plan's long-term vision is one reusable kernel with future agents as new pack compositions. The v10 implementation decisions artifact (`Astrid/docs/astrid-v10-implementation-decisions.md`) fixes managed-media layout, fan-out limits, and closed DDL vocabularies.
- **Gap note:** the plans are now largely *realized* in code (the migration SQL even cites v10 §2.2 as its source); remaining DESIGN items are the deferred/never items (editor FSA removal remnants, cloud sync, RunPod, publication, experiments, dynamic loader) plus the parts of the CLI census that the plan lists but the code has not shipped (e.g. `timelines copy` is in the plan table but not in `packs/timeline/cli.py` today).

## 2. CLI / API surface

### 2.1 CLI (IMPLEMENTED — `python3 -m astrid`)

Entry: `Astrid/astrid/__main__.py` → `astrid.core.gateway.main()` (`Astrid/astrid/core/gateway/__init__.py`). The gateway is session-free for `help`/`--version`/`serve`/`doctor`/`backup`; everything else composes one `AstridClient` and dispatches a family (`Astrid/astrid/core/gateway/dispatch.py` `_TOP_LEVEL_HANDLERS`).

| Family | Commands (IMPLEMENTED) | Source |
|---|---|---|
| `projects` | `create`, `list`, `show`, `update`, `select` | `astrid/core/cli/domain_projects.py` |
| `timelines` | `create`, `list`, `show`, `save`, `archive`, `history`, `diff` | `astrid/packs/timeline/cli.py` |
| `media` | `import`, `list`, `show`, `verify`, `relocate`, `relate` | `astrid/core/cli/domain_media.py` |
| `tasks` | `create`, `list`, `show`, `cancel`, `retry`, `events` | `astrid/core/cli/domain_tasks.py` |
| `runs` | `list`, `show` (with derived progress, `--evidence`), `cancel`, `retry-failed`, `events` | `astrid/core/cli/domain_runs.py` |
| `serve` | no subcommand (bridge HTTP server) | `astrid/core/gateway/dispatch.py` `_dispatch_serve` |
| `doctor` | default, `--json` | `astrid/core/doctor.py` |
| `backup` | `create`, `restore` | `astrid/core/backup/cli.py` |
| nested | `media references` (create/update/archive/associate/link/set-primary/list/show), `timelines shots` (list/create/add/remove/reorder) | `astrid/packs/references/cli.py`, `astrid/packs/shots/cli.py` |

Notes: `--json` prints the exact five-key envelope (`ok`/`data`/`error`/`receipt`/`idempotency_key`); stable exit codes 0/1/2 (`Astrid/astrid/sdk/contracts.py` `ENVELOPE_KEYS`, SKILL.md). Claim/start/heartbeat of task attempts are internal (no CLI verbs). Legacy task-mode CLI (`attach`/`next`/`start`/`ack`/`executors`/`orchestrators`/`sessions`/`packs`/`skills` as gateway verbs) is retired (`Astrid/astrid/packs/_core/skill/SKILL.md`).

### 2.2 SDK (IMPLEMENTED)

`import astrid` (`Astrid/astrid/__init__.py`, frozen export tuple): `discover`, `get_capability`, `invoke`, `generate`, `render`, `renderer_main`, `support`, `RenderContext`, `read_events`, `subscribe_events`, DTOs (`Capability`, `DiscoveryResult`, `EventStreamRecord`, `InvocationResult`, `CapabilityHandle`, `Port`, `Output`, `AliasRecord`, `Provenance`, `SafetyDeclaration`, `ExecError`), exceptions (`AstridSDKError` + `Capability*Error` family). Lazy `astrid.AstridClient` (`astrid/sdk/client.py`) composes the standard application on `open()` and exposes seven typed services — one method per CLI verb:

- `projects`: `create`, `list`, `show`, `update`, `select`
- `timelines`: `create`, `list`, `show`, `save` (CAS), `archive`, `history`, `diff`
- `media`: `import_file`, `import_directory`, `list`, `show`, `verify`, `relocate`, `relate`
- `tasks`: `create`, `list`, `show`, `cancel`, `retry`, `events`
- `runs`: `list`, `show`, `cancel`, `retry_failed`, `close`, `events`
- `references`: `create`, `update`, `archive`, `associate`, `set_primary`, `link`, `list`, `show`
- `shots`: `create`, `add_item`, `remove_item`, `reorder`, `list`, `show`

Every mutation returns a `DomainResult` (`Astrid/astrid/sdk/contracts.py`): immutable five-key envelope; `receipt` = committed `CommandReceipt` on mutations; `idempotency_key` always present. Service errors map to nine typed codes (`validation_error`, `not_found`, `conflict`, `stale_version`, `terminal_state`, `idempotency_mismatch`, `integrity_error`, `unavailable`, `internal`) in `Astrid/astrid/sdk/exceptions.py`.

Capability invocation (`sdk.invoke` / `client.invoke`) runs pack executors/orchestrators through the legacy capability runner (subprocess or in-process, `ASTRID_INTERNAL_INVOCATION=1`) with file-based outputs returned in `InvocationResult`; the two **task-mode adapters** (`rendering.timeline_visualize`, `generation.generate_image` — `Astrid/astrid/packs/rendering/executors/timeline_visualize/task_adapter.py`, `Astrid/astrid/packs/generation/executors/generate_image/task_adapter.py`) implement the kernel `TaskHandler` protocol and run as fenced kernel tasks with media-materialized outputs.

## 3. Data lifecycle (entry → event → timeline → render) with statuses

All IMPLEMENTED unless noted. The atomic command unit (from `Astrid/astrid/core/repositories/` + `Astrid/astrid/core/events/service.py` + `Astrid/astrid/core/store/uow.py`): one kernel-owned `BEGIN IMMEDIATE` transaction does — check idempotency key + canonical request hash + expected stream/attempt versions → allocate consecutive project seqs → append registered events + advance stream heads → update projections → write one `command_receipts` row → commit. Identical retry replays the stored receipt with zero new rows; same key + different bytes → `idempotency_mismatch` before any mutation.

### 3.1 Project
- **Entry:** `projects create` (`ProjectRepository.create` in `Astrid/astrid/core/repositories/projects.py`) inserts a `projects` row (id, immutable `slug`, `name`, `settings_json`, `event_head_seq=0`) and creates the `core.project` event stream; appends `core.project.created`; writes receipt.
- **Change:** `projects update` → `core.project.updated`. `projects select` is a **file-side preference only** (non-authoritative; `astrid/core/preferences.py`), not a DB mutation.

### 3.2 Timeline (whole-document CAS aggregate)
- **Entry:** `timelines create` (`Astrid/astrid/packs/timeline/repository.py`) derives a stable `timeline_id` from `(command_kind, project, idempotency_key)`; creates `timelines` row (`document_json`, `asset_registry_json`, `event_stream_id`) + a `timeline.timeline` stream; appends `timeline.created`; optionally sets the project default via `projects.settings_json` (`DEFAULT_TIMELINE_SETTINGS_KEY` — the **only** authority for default state).
- **Lifecycle events (IMPLEMENTED):** `timeline.created`, `timeline.saved`, `timeline.config_replaced`, `timeline.archived` (all registered in `Astrid/astrid/packs/timeline/schema-pack.yaml`).
- **Save:** whole-document CAS — `save(project, ref, config, registry, expected_version)` updates `document_json` + `asset_registry_json` together, appends `timeline.saved`, advances both heads, writes receipt. Stale `expected_version` (= stream head) → `TimelineVersionConflictError` → bridge 409 `timeline_version_conflict`, zero rows changed. `config_version` exposed to the editor equals the numeric stream head.
- **Archive:** event-backed terminal mutation — the table has **no `archived_at` column** (SD1); archived state is derived solely from the presence of a `timeline.archived` event on the stream. Archived timelines disappear from lists and reject further saves (`TimelineArchivedError`); `show`/`history`/`diff` still return them.
- **History/diff:** read `timeline.created/saved/archived` events in stream seq order; `version` = event seq.
- **Timeline document shape:** the loose editor document (`config`) is the Reigh editor timeline JSON — `{theme, theme_overrides?, tracks, clips}` with clips `{id, at, track, clipType, asset?/from-to/hold?, text?, params?, effects?, x/y/width/height?}` per `@banodoco/timeline-schema` (SKILL.md + `Astrid/examples/hype.timeline.json`). `registry` is `{"assets": {…}}`.

### 3.3 Media
- **Entry:** `media import` (`MediaService.import_file` / `import_directory`, `Astrid/astrid/sdk/media.py` + `Astrid/astrid/core/io/media_import.py`): file is hashed (SHA-256) and probed (MIME from filename, media kind from MIME) outside the transaction, staged to `<projects_root>/.astrid/media/.staging/<txn_id>`, fsynced, then atomically published to the content-addressed managed path `<projects_root>/.astrid/media/sha256/<digest[:2]>/<digest[2:4]>/<digest>` (dedupe: existing verified digest is reused, never overwritten). Inserts `media` row (`media_kind` in image/video/audio/text/document/data/other, `mime_type`, `byte_size`, `content_hash`, `metadata_json`) + `media_locations` row (realm `managed_local` default; `external_local` only explicit opt-in) + appends `core.media.imported`. Receipt returns the media id.
- **Verify:** re-hash the location bytes against `content_hash`; missing/mutated → typed error, **zero rows change** (`core.media.verified` event on success).
- **Relocate:** replace one location atomically, identity unchanged (`core.media.location_replaced`).
- **Relate:** materialize `media_relations` edges — frozen five kinds `derived_from|variant_of|uses_as_input|mask_for|audio_for`; one `variant_of` parent; acyclic variants (`core.media.related`).
- **Task outputs:** on task completion, produced files are verified and materialized as `media` + `media_locations` and ordered `task_outputs` rows (`role='result'` + `is_primary=1` uniquely identifies the primary result; `task_one_primary_result` partial unique index).

### 3.4 Tasks (the executable layer)
- **Entry:** `tasks create` (`TaskRepository.create`, `Astrid/astrid/core/repositories/tasks.py`): admits an **immutable** task — `capability`, `spec_json` (+ `spec_hash`), `input_manifest_json`, `priority`, `available_at`, `max_attempts`, optional `run_id`/`run_ordinal` and `dependencies` (hard/soft edges, same-project, acyclic). Creates `core.task` stream beginning with `core.task.created`. Status starts `queued` (or `blocked` behind hard deps).
- **Statuses (DDL CHECK, `core/0001_initial.sql`):** `tasks.status` ∈ `queued|blocked|running|succeeded|failed|cancelled`. `execution_attempts.status` ∈ `claimed|running|succeeded|failed|cancelled|expired` (with `status_version` optimistic fencing, `lease_id`/`lease_expires_at`, heartbeat counter).
- **Transition events (IMPLEMENTED):** `core.task.created`, `core.task.claimed`, `core.task.started`, `core.task.expired`, `core.task.cancelled`, `core.task.failed`, `core.task.retried`, `core.task.completed`. Heartbeat is deliberately a **non-event** narrow update fenced by `status_version`.
- **Attempt fencing:** claim/start require the attempt fence (`attempt_id`/`lease_id`/`expected_status_version`); terminal tasks never resurrect; stale attempts cannot materialize output (`Astrid/astrid/core/task_executor/service.py`, `ExecutionService`).
- **Cancel/retry:** `tasks cancel` — queued/blocked cancelled directly; running requires executor-owned fence. `tasks retry` — only eligible failed/expired tasks with budget remaining.

### 3.5 Runs (coordination/observation container)
- **Entry:** a run is created as the group handle for fan-out: one transaction creates the `runs` row + `core.run` stream + child `tasks` with unique `run_ordinal` + dependency edges + events + one receipt. A run may also be created **with zero tasks** (synchronous understanding) plus evidence.
- **Statuses (DDL):** `runs.status` ∈ `running|succeeded|failed|cancelled`. Run status is a **derived read model** over child task counts; a zero-task run derives `running` forever unless explicitly closed via `core.run.close` (`runs close` SDK method — `Astrid/astrid/sdk/runs.py`), which writes the terminal status + `core.run.closed` event.
- **Events:** `core.run.created`, `core.run.cancelled`, `core.run.retried`, `core.run.closed`, `core.run.continued` (receipt-linked fan-out continuation chunks), `core.evidence.recorded` (on the run stream).
- **Group ops:** `runs cancel` (every eligible child), `runs retry_failed` (optional `--task` subset), `runs show` (progress + `--evidence`), `runs events`.

### 3.6 Evidence
- `EvidenceRepository` (`Astrid/astrid/core/repositories/evidence.py`): `evidence_items` rows on a run, optional direct-child `task_id` and exact `media_id`; **closed five-kind vocabulary** `observation|measurement|validation|decision|error` (no DDL CHECK — enforced by the repository). Validation enforces same-project, direct-child task membership, and media-project agreement before any write. Event: `core.evidence.recorded`.

### 3.7 Render flow
- Rendering is **not** a kernel table concept: `sdk.render(timeline_path, …)` / `rendering.render` executor dispatch through `RenderService` (`Astrid/astrid/core/rendering/service.py`) and protocol-v1 renderer/planner/finalizer backends (`Astrid/astrid/packs/rendering/backends/{remotion,ffmpeg,threejs}/…`) — the timeline is read **from a file** (or via `timeline_visualize` task adapter from the kernel), rendered to `outputs/<name>` in an invocation workspace, then published to the requested `out_path` (default `video.mp4`). `RenderContext` (`Astrid/astrid/sdk/rendering.py`) is the third-party renderer facade (workspace paths, sanitized subprocess, redacted logs, attachments).
- Kernel-integrated path: `rendering.timeline_visualize` (task-mode adapter) runs as a fenced kernel task; the Remotion renderer itself (`Astrid/remotion/`, `@banodoco/timeline-composition`) is a Node sidecar invoked as a subprocess.

### 3.8 Session concept
- **Legacy (CUT):** the old task-mode runtime had `sessions/`, `.astrid-session` files, thread/variant authorities (`.astrid/threads.json`, `threads/`, `elements/managed/`) — all retired (SKILL.md "Retired legacy surface"; v10 §1.1 ledger rows CUT). v10 has **no session concept**: a session is just a process holding the exclusive-owner lock on the database while `AstridClient.open()` is alive (second owner fails closed with `unavailable`).

## 4. Media / understanding outputs

### 4.1 Kernel model (IMPLEMENTED — source of truth)
- **Any exact byte sequence is media**: imported footage, generated images/video/audio, transcripts-as-text, logs, reports. `media` (SHA-256 identity within a project) + `media_locations` (replaceable locators, realm-tagged) + `media_relations` (exact-asset lineage).
- **Understanding outputs** = zero-task `runs` + `evidence_items` (+ optional `media_id`) — the `understanding.understand` pack's `repository_adapter.py` (`Astrid/astrid/packs/understanding/executors/understand/repository_adapter.py`) invokes an LLM provider outside any transaction, normalizes reasoning/progress/final observations into ordered evidence entries, and commits one zero-task run + evidence in one `BEGIN IMMEDIATE` unit. Result: `run_id`, `evidence_ids`, `input_media_ids`, `output_media_ids` — no task/attempt/output identity.
- **Generation/render outputs** = `tasks` → fenced `execution_attempts` → verified `media` + `media_locations` → ordered `task_outputs` (primary result marker) → `derived_from`/`uses_as_input` relations to input media.
- **References/shots** add semantics over exact media: `project_references` (character/place/object/clothing/other) with `media_references` roles (`canonical|used_as_input|depicts|inspired_by`; one primary canonical; `used_as_input` requires a producing `context_task_id`), and `reference_links` (five kinds; only `related_to` symmetric, canonically ordered). `shots` + `shot_items` = ordered exact-media placements (`source_frame`, unique `sort_key`).

### 4.2 Legacy file-based outputs (pre-kernel, NOT read by the kernel)
`Astrid/runs/<name>/manifest.json` + outputs dirs (e.g. `runs/video-understanding/`, `runs/audio-understanding/`) hold old file-based run results (`kind: "understanding.video_understand"`, `inputs`, `outputs` with `content_hash`, `schema_version: 1`); `projects/<slug>/runs/<id>/run.json` holds the legacy executor run record (`status: completed`, `tool_id`, `artifacts`). v10 CUTs both run dialects; `scripts/migrations/v10/MIGRATION.md` migrates completed legacy runs into kernel runs/tasks/evidence (see §7), and the repo-root `runs/` is explicitly skipped.

## 5. IMPLEMENTED data model (as in `Astrid/` code)

Source of truth: `Astrid/astrid/core/migrations/sql/core/0001_initial.sql` (kernel) + `Astrid/astrid/packs/{timeline,shots,references}/migrations/0001_initial.sql`. Verified live: `projects/.astrid/astrid.sqlite3` contains exactly the 20 tables + declared indexes; `schema_migrations` rows `(core,1)`, `(references,1)`, `(shots,1)`, `(timeline,1)`.

### 5.1 Kernel (14 tables)
| Table | Key columns / constraints |
|---|---|
| `schema_migrations` | `(pack, version)` PK, `name` UNIQUE per pack, `checksum`, `applied_at`; pack-aware forward-only migrations |
| `projects` | `id` PK, `slug` UNIQUE (immutable), `name`, `settings_json` (JSON, holds default timeline id), `event_head_seq` |
| `event_streams` | `id` PK, `project_id` FK, `stream_type` (OPEN text; vocabulary enforced by registry, not DDL), `aggregate_id`, `head_seq`; UNIQUE `(project_id, stream_type, aggregate_id)` |
| `events` | `event_id` PK, `project_seq` UNIQUE per project, `stream_id` FK, `seq`, `subject_type`/`subject_id` (polymorphic), `changes_json` (array), `kind` (namespaced, registry-validated), `schema_version`, `idempotency_key` UNIQUE per stream, `txn_id`, `actor_kind` ∈ local/system/executor, `payload_json`; hash-chain integrity via payload envelope (`_integrity`/`previous_event_hash`/`event_hash` — `Astrid/astrid/core/events/service.py`) |
| `command_receipts` | PK `(project_id, idempotency_key)`, `request_hash`, `command_kind`, `txn_id` UNIQUE, `primary_stream_id`, `first/last_project_seq`, `event_ids_json`, `result_json` |
| `runs` | `id` PK, `project_id`, `event_stream_id` UNIQUE, `kind`, `status` ∈ running/succeeded/failed/cancelled, `title`, `input_json`, `result_json`, `started_at`, `finished_at` |
| `evidence_items` | `id` PK, `run_id` FK (cascade), `task_id` FK (set null), `kind` (repository-enforced closed five), `summary`, `data_json`, `media_id` FK (set null) |
| `tasks` | `id` PK, `project_id`, `event_stream_id` UNIQUE, `run_id`/`run_ordinal` (nullable pair, UNIQUE ordinal per run), `capability`, `spec_json`, `spec_hash`, `input_manifest_json`, `status` ∈ queued/blocked/running/succeeded/failed/cancelled, `priority`, `available_at`, `max_attempts`, `winning_attempt_id`, `cancel_request_*`, timestamps |
| `task_dependencies` | PK `(task_id, depends_on_task_id)`, `kind` ∈ hard/soft, `ordinal`, no self-deps |
| `execution_attempts` | `id` PK, `task_id` FK, `attempt_no` UNIQUE per task, `executor_id`, `status` ∈ claimed/running/succeeded/failed/cancelled/expired, `status_version`, `lease_id`/`lease_expires_at`, `heartbeat_counter`, `progress_json`, `error_json`, timestamps |
| `task_outputs` | PK `(task_id, ordinal)`, `role`, `media_id` FK (restrict), `is_primary` (one `role='result' AND is_primary=1` per task), `params_json` |
| `media` | `id` PK, `project_id`, `media_kind` ∈ image/video/audio/text/document/data/other, `mime_type`, `byte_size`, `content_hash`, `metadata_json`; UNIQUE `(project_id, content_hash)` |
| `media_locations` | `id` PK, `media_id` FK (cascade), `realm` ∈ managed_local/external_local/remote, `locator`, `verified_at`; UNIQUE `(media_id, realm, locator)` |
| `media_relations` | PK `(from_media_id, to_media_id, kind, ordinal)`, `kind` ∈ derived_from/variant_of/uses_as_input/mask_for/audio_for, `metadata_json`; one `variant_of` parent per media (partial unique index); acyclic enforced by repository |

### 5.2 Pack tables (6)
| Pack | Tables |
|---|---|
| timeline | `timelines` (`id`, `project_id`, `event_stream_id` UNIQUE, `name`, `document_json`, `asset_registry_json`, timestamps) — no slug/ULID/is_default columns (SD1); identity/metadata lives in event payloads and `projects.settings_json` |
| shots | `shots` (`id`, `project_id`, `name`, `sort_key` UNIQUE per project, `metadata_json`); `shot_items` (`id`, `shot_id` FK cascade, `media_id` FK restrict, `sort_key` UNIQUE per shot, `source_frame`, `metadata_json`) |
| references | `project_references` (`id`, `project_id`, `kind` ∈ character/place/object/clothing/other, `name`, `description`, `metadata_json`, `archived_at`); `media_references` (`id`, `reference_id`, `media_id`, `role` ∈ canonical/used_as_input/depicts/inspired_by, `context_task_id`, `ordinal`, `is_primary`, CHECKs); `reference_links` (PK `(from, to, kind)`, `kind` ∈ belongs_to/wears/located_in/associated_with/related_to) |

### 5.3 Identity scheme (IMPLEMENTED)
- Object ids: deterministic stable ids derived from `(command_kind, project scope, idempotency_key, ordinal)` (`astrid/sdk/contracts.py` `derive_stable_id`); event ids and txn ids are `uuid4().hex`; evidence ids default to lowercase Crockford-base32 **ULIDs** (`astrid/core/ids.py`). Timeline ids also support ULID-addressable routes; slug is immutable project identity.
- **ID authority note:** v10 plan says "UUID remains canonical identity and ULID remains a supported route address" (v10 §4.2).

### 5.4 Storage layout (IMPLEMENTED)
- `$ASTRID_PROJECTS_ROOT/.astrid/astrid.sqlite3` (+ `-wal`/`-shm`/`.lock`) — WAL, `synchronous=NORMAL`, `busy_timeout=5000`, `foreign_keys=ON` (PRAGMAs in migration + `store/database.py`).
- Managed media: `$ASTRID_PROJECTS_ROOT/.astrid/media/sha256/<2>/<2>/<64hex>`; staging: `.astrid/media/.staging/<txn_id>`; startup GC removes unreferenced staging only, never managed bytes (`core/io/media_import.py`).
- Exclusive-owner lock file (`astrid.sqlite3.lock` via `DatabaseOwnerLock`) — one writer process per DB.
- Repository layer: `astrid/core/repositories/{projects,tasks,media,runs,events,evidence}.py`; single-writer queue `astrid/core/store/writer.py` (dedicated writer thread, rejects transaction-control SQL); `UnitOfWork` per command (`store/uow.py`).

### 5.5 Pack/kernel boundaries (IMPLEMENTED)
- Schema-pack manifests (`astrid/packs/{timeline,shots,references}/schema-pack.yaml`) declare the 11 fields; vocabularies (`stream_types`/`event_kinds`/`command_kinds`) are registry-validated at startup (`astrid/core/events/registry.py`); plugin laws enforced: FK inward only, kernel currencies for cross-pack refs, packs never own a writer, conformance kit (`astrid/core/conformance/kit.py`), namespaced vocabularies.
- Kernel stream types: `core.project`, `core.task`, `core.run`, `core.media`; pack stream types: `timeline.timeline`, `shot.shot`, `reference.reference`.

## 6. INTENDED unified model from the plans (DESIGN/PLANNED)

All items in this section are **DESIGN/PLANNED** intent from the plan docs. Where the code already realizes the design, that is noted in §5/§7; here we record the plan's own normative statements.

### 6.1 Source of truth and migration posture (the crucial Reigh question)
- **v10 §1 (DESIGN, decisive):** build standalone local product on one 20-table SQLite authority; use the existing Reigh bridge wire shape; **delete legacy authorities instead of importing them**; replace plan/step orchestration with runs that directly group immutable tasks. "V10 removes the preservation project… There are no existing-user, historical-parity, or legacy-data promises. Astrid starts from a fresh SQLite database."
- **No Reigh/Postgres migration (DESIGN):** old project, timeline, run, thread, session, plan, lease, event-chain, audit-ledger, Supabase, and editor-FSA authorities are **not migrated or conditionally supported**; modules/tests deleted. The only ingestion retained is ordinary media import (walk files, hash/probe bytes, copy into managed storage, create `media`/`media_locations` rows). "Import useful media bytes only" (v10 §1; master plan §4.1 "fresh projects and byte-oriented `media import`, with no legacy semantic migration").
- **Editor/bridge (DESIGN, KEEP):** the Reigh editor remains the frontend; its existing bridge route/payload contract is preserved; editor FSA mode is deleted unconditionally; the repository bridge is the sole semantic editor path.
- **Master plan (DESIGN):** the vision is a reusable 14-table agent kernel + domain packs (timeline/shots/references for Astrid; future agents compose the unchanged kernel with their own packs). "One authority per product instance… one database, one media root, one transaction boundary, one semantic writer."

### 6.2 Intended entities + relations (DESIGN, but already realized — §5 matches)
The normative v10 §2.2 DDL is byte-for-byte the implemented migration (the SQL file headers state this). Intended relations: `projects 1—N event_streams/events/tasks/runs/media`; `runs 1—N tasks` via `tasks.run_id` + `run_ordinal`; `task_dependencies` DAG edges; `events` polymorphic subjects (`subject_type`/`subject_id`) so kernel events can describe pack rows without kernel→pack FKs; `task_outputs.media_id` as the executor→asset bridge; `media_relations` lineage; `evidence_items.run_id` (+ optional `task_id`, `media_id`).

### 6.3 ID scheme (DESIGN, realized)
- Plan: canonical identity via UUID, ULID as supported route address; deterministic command-derived ids for retry identity (v10 §4.2); lowercase ULIDs as kernel canonical form for evidence (decision artifact SD1). Implementation matches.

### 6.4 Statuses (DESIGN, realized)
- `tasks.status` queued/blocked/running/succeeded/failed/cancelled; `execution_attempts.status` claimed/running/succeeded/failed/cancelled/expired; `runs.status` running/succeeded/failed/cancelled; terminal immutability + fencing (v10 §5.1 kept invariants). All match the DDL.

### 6.5 Storage layout (DESIGN, realized)
- One SQLite DB per projects root; managed media at `<projects_root>/.astrid/media/sha256/<first2>/<next2>/<digest>`; per-transaction staging `.astrid/media/.staging/<txn_id>`; online backup + managed-media copy; doctor = quick_check + FK check + schema versions (v10 §4.3, decision artifact §5). Matches `core/io/media_import.py` + `core/backup/operations.py`.

### 6.6 Timeline model (DESIGN, realized)
- Whole-document CAS on `document_json` + `asset_registry_json`; numeric `config_version` = stream head; 409 on stale; no convenience columns for slug/ULID/is_default (SD1); history from `timeline.created/saved/archived` events.

### 6.7 Explicitly DESIGN-but-NOT-yet-implemented / deferred items (from v10 §1 ledger, master plan §4.3, sprint plan)
- **CUT/DEFER (DESIGN, not in code):** `runs` step/plan machinery, session/thread/lease-file authorities, `.env` scavenging (secrets resolution simplified to explicit → env → keychain), Supabase append/timeline I/O, hosted worker, RunPod, publication, cloud sync, experiments product, `runpod`/`worker`/`publish` CLIs, dynamic plugin loader, accounts/billing/tenancy tables, remote-worker platform in kernel, generic repair framework.
- **Partial (DESIGN list vs IMPLEMENTED CLI):** plan's `timelines` census includes `copy` and a `timelines shots` nested mount "when the editor journey needs CLI access" — `copy` is **not** present in `packs/timeline/cli.py` today; `references` plan census lists `set_primary` which IS implemented (`set-primary`); plan says five domain CLI families plus `serve`/`doctor`/`backup` — all implemented. The plan's `runs retry-failed` matches implemented `retry-failed`.
- **Sprint plan (DESIGN):** 8-sprint GA forecast (transaction core → executor/media → runs/evidence/references/shots → editor bridge → SDK/CLI → serve/backup/doctor → dogfood → release); much of Sprints 1–5 appears already built in this checkout.

## 7. Differences between IMPLEMENTED and DESIGN/PLANNED

| Aspect | IMPLEMENTED (verified in `Astrid/` code/DB) | DESIGN/PLANNED (plan docs) | Delta |
|---|---|---|---|
| Schema | 20 tables exactly (14 kernel + 6 pack), live DB confirmed | v10 §2.2 same 20 tables | None (migration is transcription of plan) |
| CLI | 8 families + 2 nested mounts; `timelines` verbs create/list/show/save/archive/history/diff | v10 §4.1 adds `timelines copy`; otherwise identical | `copy` unimplemented |
| Storage root | `<projects_root>/.astrid/astrid.sqlite3` + `media/sha256` tree | decision artifact §5 layout | None |
| Task/run statuses | DDL CHECKs + repository-enforced closed vocabularies | v10 §2.2 + §5.1 | None |
| Legacy data | `scripts/migrations/v10/` **exists and migrates** legacy projects/timelines/media/completed runs into the kernel via SDK only (idempotent, `v10-migrate:*` receipt keys) | v10 §1 says "no legacy migration; delete old authorities" — but the migration tooling was built as a bounded one-way SDK replay, and legacy files are left untouched; repo-root `runs/` explicitly skipped | The plan's "no migration" posture is softened in practice: a migration script exists, though it is a fresh-data ingestion, not a compatibility import |
| Understanding | zero-task run + evidence (kernel), plus legacy file runs ignored | v10 §2.1 "synchronous understanding creates run evidence without a task" | None (realized) |
| Render | file-based render + task-mode adapter for `timeline_visualize`; Remotion/ffmpeg/threejs backends | v10 keeps capability/renderer manifests file-side; no render table | None |
| Sessions | no session concept; owner lock only | sessions CUT | None |
| Editor | bridge server implemented (`serve`), FSA writers still present in codebase as legacy (e.g. `integrations/reigh/` legacy modules exist but are not the bridge path) | FSA deleted unconditionally, bridge sole mode | Legacy modules remain in-tree (source parts bin); the plan called for deletion in replacement commits — [INFERENCE] cleanup ongoing |
| Kernel/pack layering | manifests + registries + conformance kit + plugin laws implemented | master plan §2.3 | None |
| Dynamic loader / second agent | absent | boundary-now-loader-later; deferred until a second agent is real | None (matches) |

## 8. Pointers to plan files

- **Normative schema/contract (controls if docs differ):** `docs/unified-data-model-plan-v10-20260813.md` — §1 cut list + §1.1 disposition ledger; §2.1 table inventory + run grouping; §2.2 full creation DDL (the implemented SQL); §2.3 repository constraints + atomic command unit; §3 three phases + gates; §4.1 eight-family CLI table; §4.2 SDK + frozen bridge routes/payloads/errors; §4.3 backup/doctor/secrets; §5.1 kept invariants; §5.3 GA acceptance; §7 resolved decisions (incl. "Import old projects/history? No. Import useful media bytes only.").
- **Vision/architecture:** `docs/unified-data-master-plan-20260814.md` — §1 vision; §2.1 kernel table roles; §2.2 pack model; §2.3 five plugin laws; §2.4 extension seams; §3 generalization map + §3.4 factoring test; §4 NOW/LATER/NEVER (incl. "No return of plan/step machinery", "no legacy semantic migration"); §5 vision principles.
- **Delivery sequence:** `docs/astrid-first-sprint-plan-20260813.md` — §1 assumptions (incl. "no production users or legacy data must be migrated"); §2 sprint map + parallel lanes + GA coverage; §3 per-sprint detail (S1 transaction core through S8 release); sprint gates.
- **Executed decisions:** `Astrid/docs/astrid-v10-implementation-decisions.md` — §5 managed media root/staging layout; §6 fan-out max (256 children/command) + continuation envelope; §7 locked DDL vocabularies; §8 closed evidence kinds; §9 platform matrix.
- **Migration tooling:** `Astrid/scripts/migrations/v10/MIGRATION.md` — what migrates (projects/timelines/media/completed runs), what is skipped, idempotency keys, fidelity paths, verify steps.
- **Related context doc:** `docs/astrid-migration-context/08-unified-model-prior-art.md` (peer doc — plan-history condensation; confirms the "no migration" stance of v10).

## Gaps / unverified

- **Legacy-module deletion status:** the plan calls for deleting FSA/Supabase semantic-writer modules in replacement commits; legacy modules (e.g. `integrations/reigh/append_service.py`, `supabase_client.py`, `timeline_io.py`) still exist on disk. Whether they are dead code or still imported by a live path was not exhaustively traced — flagged `[INFERENCE]` in §7.
- **`timelines copy`:** listed in the plan census, absent from `packs/timeline/cli.py`; not verified against the SDK service either (not in `TimelinesService` method list) — unimplemented.
- **Live DB content:** the observed `projects/.astrid/astrid.sqlite3` has schema + migrations only (0 rows in all domain tables — a test/sandbox DB); behavioral claims about rows are grounded in the migration DDL, repository code, and the v10 migration doc, not in live row data.
- **Rendering end-to-end:** the Remotion backend's exact published-output layout and the `timeline_visualize` renderer's output manifest were sampled (paths + manifests) but not executed (read-only constraint); the `RenderContext`/`RenderService` flow is documented from source.
- **Understanding LLM details:** the `repository_adapter.py` flow was read; live provider outputs were not re-run (read-only).
- **Cross-doc consistency:** peer doc `08-unified-model-prior-art.md` was available and used for the plan-history stance; docs `unified-data-model-plan-v9..v4` and the sprint-plan review were not read in full (superseded by v10; noted per §8 pointers).
- **Secrets:** no secret values were read or recorded; only key names and code paths.
