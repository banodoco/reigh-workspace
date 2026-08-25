# Astrid SQLite Schema + File-Based Data Layout

**Context doc 04 — Astrid's on-disk store, for a future Reigh-on-Astrid migration.**
Researched 2026-08-21 from the `Astrid/` repo at `/Users/peteromalley/Documents/reigh-workspace/Astrid/`.

## 1. Summary

Astrid's data layer is a **v10 "kernel" event-sourced store**: one SQLite database
(`astrid.sqlite3`, WAL mode) holds 20 tables — a 14-table kernel (`core` pack:
`projects`, `event_streams`, `events`, `command_receipts`, `runs`, `tasks`,
`task_dependencies`, `execution_attempts`, `task_outputs`, `media`,
`media_locations`, `media_relations`, `evidence_items`, `schema_migrations`) plus
3 schema-pack-owned tables (`timelines` from the `timeline` pack, `shots` +
`shot_items` from `shots`, `project_references` + `media_references` +
`reference_links` from `references`). Schema is created by **forward-only, SHA-256
checksummed, dependency-ordered SQL migration files** (raw DDL, no ORM, no
sqlite-utils), applied transactionally and recorded in `schema_migrations` with a
pack-aware `(pack, version)` PK. Every command (project create, task admit, run
fan-out, media import, …) runs as **one callback inside one `BEGIN IMMEDIATE`
transaction** on a single dedicated writer thread, and writes a hash-chained event
(SD2 envelope inside `payload_json`: `{data, _integrity:{previous_event_hash,
event_hash}}`), a projection row, both heads (`projects.event_head_seq`,
`event_streams.head_seq`), and a `command_receipts` row for idempotent replay.

A **legacy file-based provenance store coexists** under `<projects_root>/<slug>/`:
`project.json`, `sources/<source_id>/`, `runs/<run_id>/run.json` + `manifest.json`
+ output media, `experiments/<experiment_id>/`, and `timelines/<ULID>/` with
assembly/display sidecars. The kernel DB is the new authority for projects/events;
the file tree is described in §5.

**Key facts**
- DB file: `<ASTRID_PROJECTS_ROOT>/.astrid/astrid.sqlite3`; default root is
  `<repo>/projects` (env `ASTRID_PROJECTS_ROOT` overrides; fallback
  `~/.astrid/projects`) — `astrid/core/foundation/project_paths.py:31-44`.
- Live DB found: `Astrid/projects/.astrid/astrid.sqlite3` (+ `-wal`, `-shm`,
  `.lock`); all 20 tables present, **all empty** (migrations applied
  2026-08-21T08:59:05Z). Only real rows are the 4 `schema_migrations` rows.
- Migration mechanism: `astrid/core/migrations/runner.py` + `catalog.py`; SQL in
  `astrid/core/migrations/sql/core/0001_initial.sql` and
  `astrid/packs/{timeline,shots,references}/migrations/0001_initial.sql`.
- ID format: canonical kernel IDs are **26-char lowercase Crockford-base32 ULIDs**
  (`astrid/core/ids.py`); event/txn ids are `uuid4().hex` (32 hex); stream id is
  `<project_id>:<stream_type>` (e.g. `<ulid>:core.project`).
- Timestamps: ISO 8601 UTC. Domain code emits trailing `Z` (`utc_now_iso` in
  `astrid/core/util/time.py`); the migration runner emits `+00:00` suffix.
- Status vocabularies are frozen DDL CHECKs (runs/tasks/attempts) or
  repository-enforced closed sets (evidence kinds, media kinds, relation kinds).
- Single-writer architecture: `DatabaseWriter` thread owns the only writable
  connection (FIFO queue); reads go through a separate read-only connection;
  transactions are owned by `UnitOfWork`, never by callers.
- Managed media is content-addressed: `.astrid/media/sha256/<d2>/<d4>/<sha256>`.

**File-layout tree (live evidence from repo + projects root)**

```
<ASTRID_PROJECTS_ROOT>/              (default: Astrid/projects)
├── .astrid/                         managed data root (MANAGED_ROOT_DIRNAME)
│   ├── astrid.sqlite3               kernel SQLite DB (WAL)
│   ├── astrid.sqlite3-wal / -shm    WAL sidecars
│   ├── astrid.sqlite3.lock          flock() process owner lock
│   ├── media/
│   │   ├── sha256/<d1><d2>/<d3><d4>/<64-hex-digest>   content-addressed bytes
│   │   └── .staging/<txn_id>/       per-transaction quarantine staging
│   ├── .restore-staging/            restore swap staging (backup/operations.py)
│   └── .restore-staging/restore-journal.json
├── <project-slug>/
│   ├── project.json                 legacy project provenance (schema_version 1)
│   ├── sources/<source_id>/
│   │   ├── source.json              legacy source sidecar (schema_version 1)
│   │   ├── <asset files>            raw source media (e.g. *.mp3)
│   │   └── analysis/                per-source analysis artifacts
│   ├── runs/<run_id>/
│   │   ├── run.json                 legacy run record (schema_version 1)
│   │   ├── manifest.json            executor result manifest (schema_version 2)
│   │   ├── logs/{stdout,stderr}.log
│   │   └── images|audio|videos|…/   run outputs (referenced by manifest.outputs[].path)
│   ├── experiments/<experiment_id>/ experiment.json + artifacts
│   └── timelines/<UPPERCASE-ULID>/
│       ├── assembly.json            last-written assembly projection
│       ├── assembly.jsonl           event log (append-only JSONL)
│       ├── assembly.head.json       head marker
│       ├── assembly.identity.json   identity sidecar (timeline_id = event_stream_id)
│       ├── assembly.checkpoint.json
│       ├── display.json             projected display
│       └── manifest.json            (+ .lock); tombstoned_at marks deletion
└── (Astrid repo root, for reference)
    ├── remotion/                    video-composition frontend (package.json, src/)
    └── artifacts/{m4,m7}/           CI/junit/finalizer artifacts (not a store)
```

---

## 2. DB file location, creation, and migration mechanism

### 2.1 Location
- Path derivation: `derive_database_path(projects_root)` →
  `${ASTRID_PROJECTS_ROOT}/.astrid/astrid.sqlite3`
  (`astrid/core/integrations/reigh/bridge_service.py:35,62-67`).
- Root resolution: `resolve_projects_root()` → `ASTRID_PROJECTS_ROOT` env, else
  `<repo>/projects`, else `~/.astrid/projects`
  (`astrid/core/foundation/project_paths.py:22-44`). The `.astrid` parent dir is
  created by the serve composition when the writer opens the DB.
- Live file: `Astrid/projects/.astrid/astrid.sqlite3` (348 KB), WAL mode; a
  `astrid.sqlite3.lock` sidecar is a process-lifetime `flock()`/`msvcrt`
  `DatabaseOwnerLock` held by the single writer
  (`astrid/core/store/ownership.py:68-69`).

### 2.2 Open protocol (`astrid/core/store/database.py`)
`open_database(path, registry, read_only=False)` is the **only** supported open:
1. `probe_database()` — read-only, nonmutating probe via
   `mode=ro` (or `immutable=1` when a WAL-header DB has no `-wal`/`-shm`
   sidecars, see `read_only_uri`, `runner.py:252-266`). Rejects: applied
   migrations newer than the composed registry (`MigrationTooNewError`), applied
   packs not in this composition, name drift, and exact-byte SHA-256 checksum
   drift of the migration SQL file (`runner.py:180-250`).
2. Writable opens then apply connection-level PRAGMAs and pending migrations.
   Read-only opens never apply PRAGMAs or migrations.

Connection-level PRAGMAs (`catalog.py:24-29`), applied per-open, **not
persisted**:
```
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;
```
(Verified on the live DB via raw sqlite3: journal_mode=wal; foreign_keys,
synchronous, busy_timeout are connection-scoped and read 0/1/0 on a raw
connection.)

### 2.3 Migration runner (`astrid/core/migrations/runner.py`)
- Migrations are raw SQL files; DDL transcribed "byte-for-semantic-content" from
  the normative plan `unified-data-model-plan-v10-20260813.md` §2.2 (stated in
  each file's header comment).
- Registry: `astrid/core/schema_packs/registry.py` composes the code-declared
  `core` pack (`events/registry.py:core_schema_pack_manifest()`, no YAML) with
  in-tree schema packs declared by `astrid/packs/{timeline,shots,references}/schema-pack.yaml`.
  Collisions (pack id, owned table, migration version/name, stream/event/command
  kinds, repos, mounts) are rejected deterministically at freeze time.
- Ordering: `topological_migration_order` — post-order DFS over `depends_on`
  (packs declare e.g. `depends_on: [core >= 1]`), versions ascending within a
  pack; cycles rejected. Applied order on the live DB: core, references, shots,
  timeline.
- Application (`apply_pending_migrations`): each pending migration's SQL is
  split on `;` outside string literals; PRAGMA statements run before
  `BEGIN IMMEDIATE`; the DDL **plus the `schema_migrations` row** commit in one
  transaction (atomic, exactly-once). Row: `(pack, version, name, checksum,
  applied_at)` with `checksum` = lowercase SHA-256 hex of the migration file's
  exact bytes; `applied_at` = `datetime.now(timezone.utc).isoformat()`
  (i.e. `…+00:00` suffix).
- `schema_migrations` PK `(pack, version)`, `UNIQUE (pack, name)`, pack DEFAULT
  `'core'`.

### 2.4 Write path (single writer)
- `DatabaseWriter` (`astrid/core/store/writer.py`): one writer thread owns one
  writable connection; `submit(callback)` runs callbacks FIFO and synchronously;
  SQLite busy after `busy_timeout` → typed `WriterBusyError`. `close()` drains
  the queue and stops the thread. Read traffic uses
  `read_only_connection()` (separate `mode=ro` connection).
- `UnitOfWork` (`astrid/core/store/uow.py`): one command = one callback = one
  `BEGIN IMMEDIATE` … `COMMIT`/`ROLLBACK`. Callers get a `WriterSession` facade
  that rejects transaction-control statements; rows are `sqlite3.Row`.
- Sequence allocation is in-transaction and gap-free: `next_project_seq` does
  `UPDATE projects SET event_head_seq = event_head_seq + 1 … RETURNING
  event_head_seq`; `next_stream_seq` mirrors on `event_streams.head_seq`
  (`uow.py:170-199`).
- `FORBIDDEN_TABLES` (`catalog.py:70-99`): v9-era tables (plans, steps,
  sessions, threads, leases, identity, variants, selections) and platform tables
  (accounts, billing, sync, importer, audit_ledger, …) must never be created.

---

## 3. Table-by-table schema

All `*_json` columns are validated with `CHECK (json_valid(...))`; JSON payloads
are canonical (sorted keys, compact separators, bounded 1 MiB input / 4 MiB
output / depth 100 — `astrid/core/receipts/canonical.py`). All `TEXT` ids and
timestamps are ISO 8601 UTC strings unless noted.

### 3.1 `schema_migrations` (kernel)
| column | type | null | default | notes |
|---|---|---|---|---|
| pack | TEXT | NOT NULL | `'core'` | CHECK length(trim(pack)) > 0 |
| version | INTEGER | NOT NULL | – | CHECK version > 0 |
| name | TEXT | NOT NULL | – | |
| checksum | TEXT | NOT NULL | – | SHA-256 hex of migration file bytes |
| applied_at | TEXT | NOT NULL | – | ISO UTC `+00:00` |

PK `(pack, version)`; UNIQUE `(pack, name)`.

### 3.2 `projects` (kernel) — project read model
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase Crockford ULID (PK) |
| slug | TEXT | NOT NULL | – | UNIQUE; immutable grammar `^[a-z0-9]+(?:-[a-z0-9]+)*$` (repo-enforced) |
| name | TEXT | NOT NULL | – | |
| settings_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid; repository-owned key `default_timeline_id` |
| event_head_seq | INTEGER | NOT NULL | 0 | CHECK >= 0; project-global event counter |
| created_at / updated_at | TEXT | NOT NULL | – | ISO UTC `Z` |

### 3.3 `event_streams` (kernel) — per-aggregate event stream
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | `<project_id>:<stream_type>` (e.g. `<ulid>:core.project`) |
| project_id | TEXT | NOT NULL | – | FK → projects(id) ON DELETE CASCADE |
| stream_type | TEXT | NOT NULL | – | open (no CHECK); vocabulary registry-enforced: core.project/task/run/media, timeline.timeline, reference.reference, shot.shot |
| aggregate_id | TEXT | NOT NULL | – | the aggregate the stream records (subject) |
| head_seq | INTEGER | NOT NULL | 0 | CHECK >= 0; per-stream event counter |
| created_at | TEXT | NOT NULL | – | |

UNIQUE `(project_id, stream_type, aggregate_id)`. One `core.project` stream per
project (`aggregate_id = project_id`, enforced by registry rule).

### 3.4 `events` (kernel) — append-only event log (single ordered record)
| column | type | null | default | notes |
|---|---|---|---|---|
| event_id | TEXT | NOT NULL | – | `uuid4().hex` (32 hex) PK |
| project_id | TEXT | NOT NULL | – | FK → projects ON DELETE CASCADE |
| project_seq | INTEGER | NOT NULL | – | CHECK > 0; project-global, gap-free |
| stream_id | TEXT | NOT NULL | – | FK → event_streams(id) ON DELETE RESTRICT |
| seq | INTEGER | NOT NULL | – | CHECK > 0; per-stream, gap-free 1..head |
| subject_type | TEXT | NOT NULL | – | = aggregate rule (project/task/run/media/timeline/…) |
| subject_id | TEXT | NOT NULL | – | = stream aggregate_id |
| changes_json | TEXT | NOT NULL | – | CHECK json_valid AND json_type='array' (array of changed field-name strings) |
| kind | TEXT | NOT NULL | – | namespaced event kind, registry-enforced |
| schema_version | INTEGER | NOT NULL | – | CHECK > 0 |
| idempotency_key | TEXT | NOT NULL | – | caller-supplied; UNIQUE per stream |
| txn_id | TEXT | NOT NULL | – | `uuid4().hex`; groups a command's events |
| actor_kind | TEXT | NOT NULL | – | CHECK IN ('local','system','executor') |
| payload_json | TEXT | NOT NULL | – | SD2 envelope (see §4.1) |
| created_at | TEXT | NOT NULL | – | |

UNIQUE `(project_id, project_seq)`, UNIQUE `(stream_id, seq)`, UNIQUE
`(stream_id, idempotency_key)`.
Indexes: `events_project_changes (project_id, project_seq)`,
`events_stream_kind_seq (stream_id, kind, seq)`,
`events_subject (project_id, subject_type, subject_id, project_seq)`.

### 3.5 `command_receipts` (kernel) — idempotent command results
| column | type | null | default | notes |
|---|---|---|---|---|
| project_id | TEXT | NOT NULL | – | FK → projects ON DELETE CASCADE |
| idempotency_key | TEXT | NOT NULL | – | |
| request_hash | TEXT | NOT NULL | – | SHA-256 of canonical `{command_kind, request-minus-generated}` |
| command_kind | TEXT | NOT NULL | – | namespaced, registry-enforced |
| txn_id | TEXT | NOT NULL | – | UNIQUE; doubles as exposed `receipt_id` |
| primary_stream_id | TEXT | NULL | – | FK → event_streams ON DELETE RESTRICT |
| resulting_stream_seq | INTEGER | NULL | – | stream seq after the command |
| first_project_seq / last_project_seq | INTEGER | NOT NULL | – | inclusive range, CHECK last >= first > 0 |
| event_ids_json | TEXT | NOT NULL | – | CHECK json array of event ids in order |
| result_json | TEXT | NOT NULL | – | complete command result (CHECK json_valid) |
| created_at | TEXT | NOT NULL | – | |

PK `(project_id, idempotency_key)`.

### 3.6 `runs` (kernel) — run aggregate / fan-out root
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| project_id | TEXT | NOT NULL | – | FK → projects ON DELETE CASCADE |
| event_stream_id | TEXT | NOT NULL | – | UNIQUE, FK → event_streams ON DELETE RESTRICT |
| kind | TEXT | NOT NULL | – | free text (executor kind) |
| status | TEXT | NOT NULL | – | CHECK IN ('running','succeeded','failed','cancelled') |
| title | TEXT | NULL | – | |
| input_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| result_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid; close folds declared outcome |
| started_at | TEXT | NOT NULL | – | |
| finished_at | TEXT | NULL | – | |

UNIQUE `(id, project_id)` (composite FK target for `tasks`).

### 3.7 `tasks` (kernel) — immutable executable task admission
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| project_id | TEXT | NOT NULL | – | FK → projects ON DELETE CASCADE |
| event_stream_id | TEXT | NOT NULL | – | UNIQUE, FK → event_streams ON DELETE RESTRICT |
| run_id | TEXT | NULL | – | nullable; CHECK `(run_id IS NULL AND run_ordinal IS NULL) OR (run_id IS NOT NULL AND run_ordinal IS NOT NULL)` |
| run_ordinal | INTEGER | NULL | – | index in fan-out set; CHECK >= 0 |
| capability | TEXT | NOT NULL | – | executor capability id |
| spec_json | TEXT | NOT NULL | – | immutable executable spec (CHECK json_valid) |
| spec_hash | TEXT | NOT NULL | – | SHA-256 of canonical `{spec, input_manifest}` |
| input_manifest_json | TEXT | NOT NULL | `'[]'` | CHECK json array |
| status | TEXT | NOT NULL | – | CHECK IN ('queued','blocked','running','succeeded','failed','cancelled') |
| priority | INTEGER | NOT NULL | 0 | higher = claimed first |
| available_at | TEXT | NOT NULL | – | claim gate |
| max_attempts | INTEGER | NOT NULL | 1 | CHECK > 0 |
| winning_attempt_id | TEXT | NULL | – | |
| cancel_request_id / cancel_requested_at | TEXT | NULL | – | cooperative cancel |
| created_at / updated_at / finished_at | TEXT | | | |

FK `(run_id, project_id) → runs(id, project_id) ON DELETE RESTRICT`.
Indexes: `tasks_run_ordinal UNIQUE(run_id, run_ordinal) WHERE run_id IS NOT NULL`,
`tasks_claim_order (status, available_at, priority DESC, id)`,
`tasks_project_status (project_id, status, created_at, id)`,
`tasks_run_status (run_id, status, run_ordinal) WHERE run_id IS NOT NULL`.

### 3.8 `task_dependencies` (kernel)
| column | type | null | default | notes |
|---|---|---|---|---|
| task_id | TEXT | NOT NULL | – | FK → tasks ON DELETE CASCADE |
| depends_on_task_id | TEXT | NOT NULL | – | FK → tasks ON DELETE RESTRICT |
| kind | TEXT | NOT NULL | `'hard'` | CHECK IN ('hard','soft') |
| ordinal | INTEGER | NOT NULL | 0 | CHECK >= 0 |

PK `(task_id, depends_on_task_id)`; CHECK `task_id <> depends_on_task_id`.
Index `task_dependencies_reverse (depends_on_task_id, task_id)`.

### 3.9 `execution_attempts` (kernel) — leased attempt per task
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| task_id | TEXT | NOT NULL | – | FK → tasks ON DELETE RESTRICT |
| attempt_no | INTEGER | NOT NULL | – | CHECK > 0 |
| executor_id | TEXT | NULL | – | who claimed |
| status | TEXT | NOT NULL | – | CHECK IN ('claimed','running','succeeded','failed','cancelled','expired') |
| status_version | INTEGER | NOT NULL | 1 | CHECK > 0; optimistic fence |
| lease_id | TEXT | NULL | – | |
| lease_expires_at | TEXT | NULL | – | default lease 300 s (DEFAULT_LEASE_SECONDS) |
| heartbeat_counter | INTEGER | NOT NULL | 0 | CHECK >= 0 |
| last_heartbeat_at | TEXT | NULL | – | |
| progress_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| error_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| created_at / updated_at / finished_at | TEXT | | | |

UNIQUE `(task_id, attempt_no)`; index `attempts_lease_expiry (status, lease_expires_at)`.
Heartbeat is deliberately **not** an event (no `core.*.heartbeat` kind).

### 3.10 `task_outputs` (kernel) — task → media result links
| column | type | null | default | notes |
|---|---|---|---|---|
| task_id | TEXT | NOT NULL | – | FK → tasks ON DELETE RESTRICT |
| ordinal | INTEGER | NOT NULL | – | CHECK >= 0 |
| role | TEXT | NOT NULL | – | free text; `'result'` is the primary-output role |
| media_id | TEXT | NOT NULL | – | FK → media ON DELETE RESTRICT |
| is_primary | INTEGER | NOT NULL | 0 | CHECK IN (0,1) |
| params_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| created_at | TEXT | NOT NULL | – | |

PK `(task_id, ordinal)`; CHECK `role = 'result' OR is_primary = 0`.
Indexes: `task_one_primary_result UNIQUE(task_id) WHERE role='result' AND is_primary=1`,
`task_outputs_media (media_id, task_id)`.

### 3.11 `media` (kernel) — byte-identity media registry
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| project_id | TEXT | NOT NULL | – | FK → projects ON DELETE CASCADE |
| media_kind | TEXT | NOT NULL | – | CHECK IN ('image','video','audio','text','document','data','other') |
| mime_type | TEXT | NOT NULL | – | derived from file name |
| byte_size | INTEGER | NOT NULL | – | CHECK >= 0 |
| content_hash | TEXT | NOT NULL | – | lowercase SHA-256 hex of file bytes (sole identity) |
| metadata_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| created_at | TEXT | NOT NULL | – | |

UNIQUE `(project_id, content_hash)` (project-scoped dedupe);
index `media_project_page (project_id, created_at, id)`.

### 3.12 `media_locations` (kernel) — concrete byte locations
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| media_id | TEXT | NOT NULL | – | FK → media ON DELETE CASCADE |
| realm | TEXT | NOT NULL | `'managed_local'` | CHECK IN ('managed_local','external_local','remote') |
| locator | TEXT | NOT NULL | – | path or URL for the realm |
| verified_at | TEXT | NULL | – | m4 byte-verification stamp |
| created_at | TEXT | NOT NULL | – | |

UNIQUE `(media_id, realm, locator)`.

### 3.13 `media_relations` (kernel)
| column | type | null | default | notes |
|---|---|---|---|---|
| from_media_id | TEXT | NOT NULL | – | FK → media ON DELETE CASCADE |
| to_media_id | TEXT | NOT NULL | – | FK → media ON DELETE CASCADE |
| kind | TEXT | NOT NULL | – | CHECK IN ('derived_from','variant_of','uses_as_input','mask_for','audio_for') |
| ordinal | INTEGER | NOT NULL | 0 | CHECK >= 0 |
| metadata_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| created_at | TEXT | NOT NULL | – | |

PK `(from_media_id, to_media_id, kind, ordinal)`; CHECK from ≠ to.
Indexes: `media_relations_to (to_media_id, kind, from_media_id)`,
`media_one_variant_parent UNIQUE(from_media_id) WHERE kind='variant_of'`.

### 3.14 `evidence_items` (kernel) — run evidence records
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| run_id | TEXT | NOT NULL | – | FK → runs ON DELETE CASCADE |
| task_id | TEXT | NULL | – | FK → tasks ON DELETE SET NULL (direct child of run only) |
| kind | TEXT | NOT NULL | – | **no DDL CHECK**; closed repo set: observation, measurement, validation, decision, error |
| summary | TEXT | NOT NULL | – | non-empty |
| data_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| media_id | TEXT | NULL | – | FK → media ON DELETE SET NULL (same project) |
| created_at | TEXT | NOT NULL | – | |

Indexes: `evidence_run_time (run_id, created_at, id)`,
`evidence_task (task_id, id) WHERE task_id IS NOT NULL`.

### 3.15 `timelines` (timeline pack) — timeline document aggregate
| column | type | null | default | notes |
|---|---|---|---|---|
| id | TEXT | NOT NULL | – | lowercase ULID PK |
| project_id | TEXT | NOT NULL | – | FK → projects ON DELETE CASCADE |
| event_stream_id | TEXT | NOT NULL | – | UNIQUE, FK → event_streams ON DELETE RESTRICT |
| name | TEXT | NOT NULL | – | |
| document_json | TEXT | NOT NULL | – | CHECK json_valid; full timeline document |
| asset_registry_json | TEXT | NOT NULL | `'{}'` | CHECK json_valid |
| created_at / updated_at | TEXT | NOT NULL | – | |

No slug/ULID/default columns (SD1): immutable slug + ULID live in
`timeline.created` event payloads; the project default timeline id lives in
`projects.settings_json.default_timeline_id` (repository-owned key).

### 3.16 `shots` + `shot_items` (shots pack)
`shots`: id (ULID PK), project_id (FK CASCADE), name, sort_key, metadata_json,
created_at, updated_at; UNIQUE `(project_id, sort_key)`.
`shot_items`: id (ULID PK), shot_id (FK → shots CASCADE), media_id (FK → media
RESTRICT), sort_key, source_frame INTEGER NULL, metadata_json, created_at;
UNIQUE `(shot_id, sort_key)`; index `shot_items_media (media_id, shot_id)`.

### 3.17 `project_references`, `media_references`, `reference_links` (references pack)
`project_references`: id (ULID PK), project_id (FK CASCADE), kind CHECK IN
('character','place','object','clothing','other'), name (CHECK length(trim)>0),
description DEFAULT '', metadata_json, created_at, updated_at, **archived_at
TEXT NULL (soft-delete)**; index `references_project_kind (project_id, kind, name, id)`.

`media_references`: id (ULID PK), reference_id (FK CASCADE), media_id (FK
CASCADE), role CHECK IN ('canonical','used_as_input','depicts','inspired_by'),
context_task_id (FK → tasks RESTRICT, nullable), ordinal, is_primary,
metadata_json, created_at; CHECKs: `role='canonical' OR is_primary=0`;
`role <> 'used_as_input' OR context_task_id IS NOT NULL`;
`context_task_id IS NULL OR role IN ('used_as_input','inspired_by')`.
Indexes: `reference_one_primary_canonical UNIQUE(reference_id) WHERE
role='canonical' AND is_primary=1`; `reference_canonical_ordinal
UNIQUE(reference_id, ordinal) WHERE role='canonical'`;
`media_reference_global_unique UNIQUE(reference_id, media_id, role) WHERE
context_task_id IS NULL`; `media_reference_context_unique UNIQUE(reference_id,
media_id, role, context_task_id) WHERE context_task_id IS NOT NULL`;
`media_references_media (media_id, role, reference_id)`;
`media_references_task (context_task_id, role, reference_id) WHERE
context_task_id IS NOT NULL`.

`reference_links`: PK `(from_reference_id, to_reference_id, kind)`, both FKs →
project_references CASCADE, kind CHECK IN ('belongs_to','wears','located_in',
'associated_with','related_to'), metadata_json, created_at; CHECK from ≠ to;
index `reference_links_to (to_reference_id, kind, from_reference_id)`.

### 3.18 Index inventory (total, verified on live DB)
16 kernel + 9 pack indexes = 25 named CREATE INDEX statements; PK/UNIQUE
constraints add implicit indexes. Partial indexes (WHERE): `tasks_run_ordinal`,
`task_one_primary_result`, `tasks_run_status`, `media_one_variant_parent`,
`evidence_task`, `media_reference_*` (2), `media_references_task`,
`reference_one_primary_canonical`, `reference_canonical_ordinal`.

---

## 4. Core abstraction semantics

### 4.1 Events — the single ordered record (event sourcing)
- Every committed command appends ≥1 event. Global order: `project_seq`
  (gap-free per project, allocated by `UPDATE … RETURNING` on
  `projects.event_head_seq`); per-stream order: `seq` (1..head on
  `event_streams.head_seq`). Reads order by `project_seq ASC, seq ASC` (or
  `seq` within a stream), capped at 10 000 rows (default 1000) —
  `repositories/events.py`.
- **SD2 integrity envelope** inside `payload_json`
  (`events/service.py:30-45`, `receipts/canonical.py`):
  ```json
  {"data": {"<domain fields only>"},
   "_integrity": {"previous_event_hash": "<sha256 hex | null at genesis>",
                  "event_hash": "<sha256 hex>"}}
  ```
  `event_hash` = SHA-256 of the canonical JSON of the envelope **with
  `_integrity.event_hash` omitted** (self-referential); `previous_event_hash`
  = stored `event_hash` of the previous event on the same stream.
  `verify_stream` recomputes the whole genesis-to-head chain and fails on any
  gap/reorder/tamper (`events/service.py:430-560`).
- Vocabulary is registry-enforced, namespaced dotted names: stream types
  `core.project|task|run|media`, `timeline.timeline`, `reference.reference`,
  `shot.shot`; event kinds like `core.project.created`, `core.task.completed`,
  `core.run.created`, `core.media.imported`, `core.evidence.recorded`;
  command kinds like `core.project.create`, `timeline.save`
  (`events/registry.py:76-163`). An event kind's pack must equal its stream
  type's pack; subject = stream aggregate; event project = stream project.
- `changes_json` = array of changed field-name strings (e.g.
  `["slug","name","settings"]`).

### 4.2 Streams and aggregates
`event_streams` is the per-aggregate ledger. `stream_id` = `<project_id>:<stream_type>`.
Aggregate rules (`events/registry.py:262-297`): `core.project` → subject_type
`project`, aggregate_id must equal project_id (one such stream per project);
`core.task` → `task`; `core.run` → `run`; `core.media` → `media`;
`timeline.timeline` → `timeline`; `reference.reference` → `reference`;
`shot.shot` → `shot`.

### 4.3 Sessions — **not a v10 table**
`session`/`thread`/`lease`/`identity` tables are on `FORBIDDEN_TABLES`.
Command-level idempotency is instead carried by `command_receipts`
(`ReceiptService.check` gate before any mutation; replay returns the stored
result; key reuse with a different request_hash/kind → `ReceiptMismatchError`).
`events.actor_kind` ('local','system','executor') is the closest notion of an
actor. Legacy run records carry an optional `session_id` string (file store).

### 4.4 Timelines
Kernel: `timelines` table (document_json + asset_registry_json) with its own
event stream (`timeline.created/saved/archived/config_replaced` events; CAS
saves via `uow.cas_stream_head`). Legacy file store additionally keeps
`timelines/<ULID>/` assembly + display sidecars (see §5); timeline reads/writes
historically bridged to reigh-app Supabase `timelines` rows via
`astrid/core/integrations/reigh/SupabaseDataProvider` ("legacy compatibility
bridge") — `astrid/core/project/schema.py` header.

### 4.5 JSON vs columns
Projections are columns (id/slug/name/status/…); document/domain payloads are
canonical JSON: `settings_json`, `spec_json`, `input_manifest_json`,
`progress_json`, `error_json`, `result_json`, `payload_json`, `changes_json`,
`event_ids_json`, `metadata_json` (media/shot/reference), `document_json`,
`asset_registry_json`, `data_json`, `params_json`, `result_json`. No
soft-delete in kernel tables (only `project_references.archived_at` and legacy
timeline `manifest.json.tombstoned_at`).

---

## 5. File-based layout and path conventions

All functions in `astrid/core/foundation/project_paths.py`:
- `<root>/<slug>/` = `project_dir(slug, root=resolve_projects_root(root))`.
- `project.json` = `project_dir/<slug>/project.json`; `sources_dir` =
  `…/sources`; `source_dir` = `…/sources/<source_id>` with `source.json` and
  `analysis/`; `runs_dir` = `…/runs`; `run_dir` = `…/runs/<run_id>` with
  `run.json`; `experiments_dir` = `…/experiments`; `experiment_dir` =
  `…/experiments/<experiment_id>` with `experiment.json`.
- Slug grammar: `^[a-z0-9][a-z0-9_-]{0,62}$` (file-store) / stricter
  `^[a-z0-9]+(?:-[a-z0-9]+)*$` (kernel repo); run/source ids:
  `^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$`; experiment ids lowercase
  `^[a-z0-9][a-z0-9._-]*$`.
- Timeline dirs (`astrid/core/timeline/paths.py`): `…/timelines/<26-char ULID>/`
  with `assembly.json`, `assembly.jsonl` (append-only event log),
  `assembly.head.json`, `assembly.identity.json` (carries `timeline_id` = event
  stream id + embedded display block), `assembly.checkpoint.json`,
  `display.json` (projected display; regenerated from `assembly.jsonl` when
  stale — "repair" path), `manifest.json` (tombstone marker:
  `tombstoned_at`).
- Managed media (`astrid/core/io/media_import.py:60-82`): `managed_media_path` =
  `<root>/.astrid/media/sha256/<digest[:2]>/<digest[2:4]>/<digest>`; staging =
  `<root>/.astrid/media/.staging/<txn_id>` (txn_id = `uuid4().hex`, 32 hex);
  digest = lowercase 64-hex SHA-256 of file bytes. `walk_media_files` never
  walks into `.astrid`.
- Backup (`astrid/core/backup/operations.py:26-48`): a backup dir = snapshot
  `astrid.sqlite3` (via `sqlite3.Connection.backup`), `media/` copy of the
  sha256 tree (excluding `.staging`/`cache`/`logs`/`packs`/`.env`),
  `backup.json` envelope (version 1, created_at, pack migration state, media
  count, page count). Restore stages under `.astrid/.restore-staging/` with
  journal `restore-journal.json`, validates `PRAGMA quick_check` +
  `foreign_key_check` + schema probe, then atomically swaps.
- Run outputs: relative to the run dir (e.g. `images/output_000.png`,
  `audio/output_000.mp3`); `run.json.artifacts.outputs[]` records
  `{path, bytes, content_hash: "sha256:<hex>", type: "file", source:
  "manifest"}`; `manifest.json.outputs[]` likewise (see §6).
- `remotion/` in the repo root is the video-composition frontend
  (`package.json`, `remotion.config.ts`, `src/`) used by the rendering pack
  (`astrid/packs/rendering/backends/remotion/`) — not a data store.
- `artifacts/{m4,m7}/` hold CI/junit/finalizer JSON (writer_uow-junit.xml,
  v10_contract-junit.xml, …) — process artifacts, not store state.
- `.oracle/` holds epic/plan markdown (plan.md, m1-gate.md, findings/) — planning
  docs, not store state.

---

## 6. Sample rows

### 6.1 Real DB (`Astrid/projects/.astrid/astrid.sqlite3`) — only `schema_migrations` has rows
```
SELECT pack, version, name, substr(checksum,1,16), applied_at FROM schema_migrations;
core       |1|initial|0c39b31ea23a2d74|2026-08-21T08:59:05.500578+00:00
references |1|initial|1174cfd233deb635|2026-08-21T08:59:05.526350+00:00
shots      |1|initial|3e717f76589774e1|2026-08-21T08:59:05.529915+00:00
timeline   |1|initial|41241db1756c1ae2|2026-08-21T08:59:05.532817+00:00
```
All 19 domain tables: count 0 (fresh migration run 2026-08-21T08:59:05Z; no
projects created yet).

### 6.2 Constructed example rows (from repository INSERT SQL, not observed in a DB)
`projects` after `ProjectRepository.create` (`repositories/projects.py:342-360`):
```
id='01jzk9f4jv7x5kq2h8c3m6n9pw' slug='my-project' name='My Project'
settings_json='{}' event_head_seq=1
created_at='2026-08-21T09:00:00Z' updated_at='2026-08-21T09:00:00Z'
```
`event_streams` (same txn): `id='01jzk…pw:core.project'` (project_id same,
stream_type='core.project', aggregate_id=project_id, head_seq=1).
`events` (via `uow.append_event`): event_id=`uuid4().hex`, project_seq=1,
stream_id=`<ulid>:core.project`, seq=1, subject_type='project', subject_id=id,
changes_json=`["slug","name","settings"]`, kind='core.project.created',
schema_version=1, idempotency_key=<caller key>, txn_id=`uuid4().hex`,
actor_kind='local',
payload_json=`{"data":{"slug":"my-project","name":"My Project","settings":{}},"_integrity":{"previous_event_hash":null,"event_hash":"<64-hex>"}}`,
created_at='2026-08-21T09:00:00Z'.
`command_receipts`: request_hash = SHA-256 of canonical
`{"command_kind":"core.project.create","request":{"project_id":…,"slug":…,"name":…,"settings":…}}`,
first=last=1, event_ids=[event_id], result_json = the read model dict.

### 6.3 Real file-store samples (`Astrid/projects/music3-cybernetic/`)
`project.json` (real, verbatim shape):
```json
{"created_at":"2026-08-17T11:40:22Z","default_timeline_id":null,
 "description":"MiniMax Music 3 generated tracks — cybernetic pop experiments",
 "name":"music3-cybernetic","schema_version":1,"slug":"music3-cybernetic",
 "updated_at":"2026-08-17T11:40:22Z"}
```
`runs/01M084YM7YA4CZR70MSZVRA5ZP/run.json` (real, trimmed): run_id (uppercase
ULID), project_slug, schema_version 1, status `"completed"`, invocation
`"cli"`, tool_id `"generation.generate_image"`, argv, artifacts.outputs[]
`[{path:"images/output_000.png", bytes:13119153,
content_hash:"sha256:19805ee5…8e142e", type:"file", source:"manifest"}]`,
manifest_path `"runs/…/manifest.json"`, metadata {cost_usd, executor_version,
pid, returncode, …}.
`runs/…/manifest.json` (real): schema_version 2, kind, model, seed,
inputs/outputs, request, request_id (uuid), duration_ms 50430,
source_urls, applied_features/dropped_features/warnings.
Timeline dir sample (`Astrid/projects/h3-derope-video/timelines/01M00A2ZH9J0WTA5ZY46JXYE28/`):
assembly.checkpoint.json, assembly.json, manifest.json, manifest.json.lock,
assembly.head.json, assembly.jsonl, assembly.identity.json, display.json.

---

## 7. ID / timestamp / status conventions

**IDs**
- Kernel aggregate ids (projects, runs, tasks, attempts, media, evidence,
  timelines, shots, shot_items, references): 26-char **lowercase Crockford
  base32 ULID** — 48-bit ms timestamp + 80-bit random, monotonic within a
  millisecond; alphabet `0123456789abcdefghjkmnpqrstvwxyz` (`astrid/core/ids.py`).
- `events.event_id`, `txn_id` (also exposed receipt_id), media staging txn:
  `uuid.uuid4().hex` (32 lowercase hex).
- `event_streams.id`: `<project_id>:<stream_type>`.
- Legacy file store ids differ: run dirs and timeline dirs use **UPPERCASE**
  26-char Crockford ULIDs (`01M084YM7YA4CZR70MSZVRA5ZP`); file-store
  run/source ids validate to `^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$`.
- `schema_migrations` key: `(pack, version)`.

**Timestamps**
- All TEXT, ISO 8601 UTC. Domain helpers (`astrid/core/util/time.py`):
  `utc_now_iso()` → `…Z` (microsecond precision by default), seconds/millis
  variants. Migration runner uses `datetime.now(timezone.utc).isoformat()` →
  `…+00:00`. Observed live `applied_at` values carry `+00:00`; observed file
  records (`project.json`, `run.json`) carry `Z`. No timezone is ever stored in
  a non-UTC form. Kernel commands accept optional `created_at` overrides
  (generated timestamps are excluded from request hashes via
  `GENERATED_FIELD_NAMES`).

**Statuses / enums (all frozen; DDL CHECK unless noted)**
- runs: `running, succeeded, failed, cancelled` (DDL).
- tasks: `queued, blocked, running, succeeded, failed, cancelled` (DDL);
  admission starts `queued`; `blocked` from unsatisfied deps.
- execution_attempts: `claimed, running, succeeded, failed, cancelled, expired`
  (DDL); default lease 300 s; heartbeat is a non-event liveness update.
- evidence_items.kind (no CHECK, repo-enforced): `observation, measurement,
  validation, decision, error`.
- media.media_kind: `image, video, audio, text, document, data, other`.
- media_locations.realm: `managed_local, external_local, remote`.
- media_relations.kind: `derived_from, variant_of, uses_as_input, mask_for,
  audio_for`.
- task_dependencies.kind: `hard, soft`.
- project_references.kind: `character, place, object, clothing, other`;
  media_references.role: `canonical, used_as_input, depicts, inspired_by`;
  reference_links.kind: `belongs_to, wears, located_in, associated_with,
  related_to`.
- events.actor_kind: `local, system, executor` (DDL).
- Schema/format versions: file-store `schema_version` 1 (project/source/run),
  manifest schema_version 2, `PROJECT_SCHEMA_VERSION = SOURCE_SCHEMA_VERSION =
  RUN_SCHEMA_VERSION = 1` (`project/schema.py:18-20`); kernel migration version
  1 (all packs); backup format version 1.

**Soft-delete**
- Kernel: none (no `deleted_at` on kernel tables). `project_references.archived_at`
  (nullable) is the only DB soft-delete; legacy timeline store uses
  `manifest.json.tombstoned_at`. Runs/tasks have terminal statuses instead.

---

## Gaps / unverified
- The only live kernel DB (`Astrid/projects/.astrid/astrid.sqlite3`) has zero
  domain rows — no real-world row samples for kernel tables could be captured;
  §6.2 rows are constructed from repository INSERT statements and are tagged as
  such. Other `.sqlite3` files found in the workspace (ComfyUI `user/comfyui.db`,
  a browser-profile `first_party_sets.db`) are unrelated to Astrid.
- Cross-repo DB scan was bounded (workspace contains large vendor trees); a
  handful of additional Astrid DB copies could exist under
  `Astrid-packification-oracle/` or `pipeline-tests-*/` but none surfaced in
  targeted scans of those directories.
- The `timeline` kernel table (v10) and the legacy `timelines/<ULID>/` file
  store overlap in purpose; the migration/coexistence contract between them
  (and the Supabase bridge) is stated in code docstrings but no runtime
  evidence (rows in both) exists to confirm which is authoritative at any point
  in time. [INFERENCE] the kernel table is the new authority and the file tree
  a legacy cache per `project/schema.py` header.
- `Astrid/astrid/core/threads/ids.py` (referenced by `timeline/paths.py` for
  `is_ulid`) was not read; timeline ULID grammar (26-char Crockford) is
  corroborated by on-disk directory names and `validate_timeline_ulid`.
- `astrid/core/store/ownership.py` lock semantics beyond the lock-file path
  (fcntl/msvcrt `LOCK_EX | LOCK_NB`) were not fully read; the `.lock` sidecar
  and `OwnerLockError` behavior are confirmed.
- Read concurrency details of `read_only_connection()` (connection lifetime,
  pooling) were not fully read (`writer.py:301-475` elided).
