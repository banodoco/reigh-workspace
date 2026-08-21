# 17 — Shots Pack v2: Generations / Variants (DDL + Repositories + Events)

> **SUPERSEDED by `27-build-spec.md` (Grok review, judged ADOPT).** Historical DDL/repository design evidence only; it is not a working build contract.
>
> **(Amended: Grok review — judged ADOPT.)** V1 adds exactly `generations` and `generation_variants`, retaining the one-primary partial unique index, unique media membership, `media` RESTRICT, soft delete, and atomic task completion. It does **not** add a per-generation event stream, nine event kinds, ten receipt-heavy commands, importer/replay keys, or a table-count conformance gate. `record_completion` is part of the task completion UoW and receipt; star/primary/delete are small writer-serialized pack commands. Existing `shots`/`shot_items` remain dormant and document-native placement remains the only Reigh placement authority. Thumbnails are a later cheap local task, not Phase-1 schema or a URL column.

> **Amended (doc 24 Q1):** Pack v2 owns relational generation identity and media membership only. Shot groups, pools, timing, and boundary overrides are document-native and are not represented by placement tables, commands, or events.

**Design spec for the pack migration that gives Reigh's content estate an Astrid-native home.** Extends the existing `shots` schema pack (`Astrid/astrid/packs/shots/`, currently migration version 1 with tables `shots`, `shot_items`) with a forward-only migration v2 creating two new owned tables — `generations` and `generation_variants` — plus the receipt-backed `GenerationRepository`, new registry vocabulary (stream type `generation.generation`, 9 event kinds, 10 command kinds), a `generations` SDK service + `media generations` CLI mount, and an atomic task-completion → generation command. Every table/command follows kernel conventions verified in `04-astrid-sqlite-schema.md` and the existing pack sources: lowercase Crockford ULID PKs, ISO-8601-UTC TEXT timestamps, DDL `CHECK`s for booleans and `json_valid`, pack FKs pointing inward to the kernel only, per-aggregate event streams, hash-chained events, and one `command_receipts` row per command with replay-first idempotency. Credits, auth, sharing, the slot system (`attempts`/`shot_slots`), and Postgres denormalizations are deliberately NOT modeled (binding owner decisions, docs 15 and 24 Q1).

**Key facts**
- Migration file: `Astrid/astrid/packs/shots/migrations/0002_generations.sql`; pack manifest version 1→2; second `migrations:` entry `{version: 2, name: generations}`; applied by the existing runner (SHA-256 checksum, `BEGIN IMMEDIATE`, atomic `schema_migrations` row) — no new runner work. [04 §2.3, 05 §5.4]
- `generations` = one row per gallery "family" (Reigh `generations`, 38k rows): ULID id, `project_id`, `task_id` (FK → kernel `tasks` SET NULL), `type`, `name`, self-FKs `based_on_generation_id` (SET NULL) / `parent_generation_id` (CASCADE) + `child_order`, `params_json`, `starred`, soft-delete `deleted_at`, timestamps. [01 §3.2, 07 §3.1]
- `generation_variants` = exact media rows under a generation (Reigh `generation_variants`, 40k rows): `media_id` FK → kernel `media` RESTRICT (bytes are the kernel currency, plugin law 2), `variant_type`, `name`, `params_json`, `is_primary`, `starred`, `viewed_at`, `created_at`; `UNIQUE (generation_id, media_id)` (unique media membership) + partial unique index `generation_one_primary` (one primary per generation). [04 §3.16/§3.13, 14 §4]
- One event stream per generation (`<generation_id>:generation.generation`), pattern-copied from the shots pack (`SHOT_STREAM_TYPE`; streams are derived, no `event_stream_id` column — `Astrid/astrid/packs/shots/repository.py`). There is no pack-v2 placement event vocabulary; placement mutations are timeline-document commands (doc 24 Q1).
- Every mutation is one `BEGIN IMMEDIATE` callback: receipt gate → validation (zero rows on rejection) → writes → hash-chained event(s) → heads → one receipt (`request_hash` over semantic fields, generated fields excluded). [04 §2.4, shots repo create/add_item/reorder]
- Deliberately dropped (owner cut list, docs 15 and 24 Q1): `storage_mode`, `local_handle_*`, `thumbnail_url`/`location` URLs (bytes become `media`), `shot_data`/`children` JSONB denormalizations, relational placement/order/boundary columns, `primary_variant_id` pointer (derived via partial index), `copied_from_share`/`shared_generations` (sharing cut), `pair_shot_generation_id`, the live slot system, and `attempts` (archived, not imported). Thumbnails remain a separate local-task capability consideration rather than a column (doc 24 considerations §2).
- `FORBIDDEN_TABLES` contains `variants` but enforcement is exact-name set intersection (`catalog.py:145`, `scripts/reshape/authority_lint.py:600`, `tests/v10/*`), so `generation_variants` does **not** collide. The `m4_gate.py` "frozen 20 tables" composition count and the conformance kit must be bumped to 22 (doc 24 Q1 removes the third proposed table).
- Import replay (future phase) uses receipt keys `reigh-import:v1:generation:{source_uuid}` and deterministic ULIDs derived from source UUIDs, matching the v10 migration machinery (`Astrid/scripts/migrations/v10/`, doc 11; doc 14 §4).

Sources: docs 01 §3.2, 04 §2–§7, 05 §2–§5, 07 §3.1, 13 §3, 14 §4, 15, 24 Q1/Q2 + considerations §2; repo `Astrid/astrid/packs/{shots,timeline,references}/{schema-pack.yaml,migrations/0001_initial.sql,repository.py,cli.py}`, `Astrid/astrid/core/{events/registry.py,migrations/{catalog.py,runner.py},schema_packs/registry.py}`, `Astrid/astrid/sdk/{client.py,shots.py,contracts.py}`.

---

## 1. Pack identity and migration file spec

### 1.1 What changes (all under `Astrid/astrid/packs/shots/`)

> **Amended (doc 24 Q1):** The migration, manifest, repository, CLI, and composition changes below exclude relational shot placement.

| Artifact | Today | After v2 |
|---|---|---|
| `schema-pack.yaml` `version:` | `1` | `2` (manifest version bump; `depends_on: [core >= 1]` unchanged) |
| `schema-pack.yaml` `migrations:` | one entry `{version: 1, name: initial, path: migrations/0001_initial.sql, tables: [shots, shot_items]}` | add `{version: 2, name: generations, path: migrations/0002_generations.sql, tables: [generations, generation_variants]}` |
| `migrations/` | `0001_initial.sql` | + `0002_generations.sql` (this spec §2) |
| `schema-pack.yaml` `stream_types:` | `shot.shot` | + `generation.generation` |
| `schema-pack.yaml` `event_kinds:` | 4 (`shot.*`) | + 9 (§3) |
| `schema-pack.yaml` `command_kinds:` | 4 (`shot.*`) | + 10 (§3) |
| `schema-pack.yaml` `repositories:` | `ShotRepository` | + `GenerationRepository` |
| `schema-pack.yaml` `cli_mounts:` | `shots: timelines shots` | + `generations: media generations` |
| `repository.py` | `ShotRepository` (create/add_item/remove_item/reorder) | unchanged by pack v2 |
| new file | – | `generation_repository.py` (`GenerationRepository`) |
| `astrid/core/events/registry.py` `STREAM_AGGREGATE_RULES` | shot/timeline/reference rules | + rule for `generation.generation` (§3.1) |
| `astrid/sdk/` | 7 services | + `generations.py` (`GenerationsService`), wired into `AstridClient` (§6) |
| `astrid/packs/shots/cli.py` | 5 verbs | unchanged; add `astrid/packs/shots/generations_cli.py` for the `media generations` mount (§6) |
| composition/conformance | `STANDARD_SCHEMA_PACKS` frozen at 20 tables | 22 tables; bump `scripts/reshape/m4_gate.py` and conformance kit table-count expectations |

The `shots` pack keeps its pack id (`shots`): doc 14 calls this "the shots/content pack" and the registry is collision-free as long as one pack owns the two tables — extending `shots` with migration v2 is the smallest correct change. (A separate `content` pack would be defensible; see Open Questions Q1.)

### 1.2 Migration file contract (copy `0001_initial.sql`'s header style)

`0002_generations.sql` MUST:
- Open with a `-- Astrid shots schema pack generation-content migration: shots/0002_generations` header block: transcription provenance (doc 14 §4 sketch + this spec), contract notes (FKs inward only; `media_id` kernel currency; no PRAGMAs — connection-level settings are applied by the runner), and the SD1 note that no slug/ULID/default convenience columns or JSONB denormalizations are created.
- Be forward-only, checksummed by the runner (SHA-256 of exact bytes), and applied atomically with its `schema_migrations` row inside `BEGIN IMMEDIATE` (`runner.py` `apply_pending_migrations`). Statements split on `;` outside literals — keep the file plain DDL, no `CREATE TRIGGER` (guard logic lives in repositories, as in every existing pack), no semicolons inside strings.
- Not repeat PRAGMAs; not touch kernel tables; not add `users`/`billing`/`importer`/`variants`/legacy names (FORBIDDEN_TABLES).
- Version identity: `pack='shots', version=2, name='generations'`. Next migration in the pack would be `0003_*.sql` (versions ascend within a pack; `UNIQUE (pack, name)` prevents name reuse; name drift and checksum drift are rejected on probe — `runner.py`).

### 1.3 Registry wiring

> **Amended (doc 24 Q1):** Registry wiring adds only generation/variant vocabulary; no placement kinds are registered.

- `astrid/packs/__init__.py` `register_standard_schema_packs` already registers the whole `shots` pack — no change needed for pack inclusion; the yaml diff alone extends the composition.
- `astrid/core/events/registry.py` `STREAM_AGGREGATE_RULES`: add
  `"generation.generation": StreamAggregateRule(subject_type="generation", aggregate_is_project=False, ...)` — one stream per generation, aggregate_id = generation id, event project = stream project, event kind pack must equal stream type pack (all new kinds are declared by pack `shots`). Mirror the existing shot rule entry.
- The registry rejects collisions deterministically (`schema_packs/registry.py::_collect_collisions`): new names must not collide with core (`core.*`) or other packs (`timeline.*`, `reference.*`, `shot.*`). The chosen names in §3 are collision-free.
- `scripts/reshape/m4_gate.py:584` asserts a frozen composition table count (20) — update to 22; the conformance kit (`astrid/core/conformance/kit.py`) and any "20-table" tests get the same bump. Tests that assert `tables.isdisjoint(FORBIDDEN_TABLES)` keep passing (`generation_variants` is not an exact member).

---

## 2. DDL — `migrations/0002_generations.sql`

> **Amended (doc 24 Q1):** The DDL contains only `generations` and `generation_variants`; the proposed `shot_generation_items` table and its indexes are removed.

```sql
-- Astrid shots schema pack generation-content migration: shots/0002_generations
--
-- Adds the two relational content tables the Reigh gallery needs (doc 14
-- section 4 sketch; spec doc 17). FKs point inward to the kernel only
-- (plugin law 1); media_id is the kernel currency on variants (plugin law 2).
-- Contract notes:
--   * generations is a per-aggregate stream owner: its event stream is
--     derived as '<generation_id>:generation.generation' (shots-pack
--     pattern), so no event_stream_id convenience column exists.
--   * No URL/location/thumbnail columns: exact bytes are kernel media rows.
--   * No shot_data/children/primary_variant_id denormalizations (SD1);
--     derived by query.
--   * No PRAGMAs are repeated here (runner applies connection-level settings).

CREATE TABLE generations (
  id                      TEXT PRIMARY KEY,
  project_id              TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  task_id                 TEXT REFERENCES tasks(id) ON DELETE SET NULL,
  type                    TEXT NOT NULL,
  name                    TEXT,
  based_on_generation_id  TEXT REFERENCES generations(id) ON DELETE SET NULL,
  parent_generation_id    TEXT REFERENCES generations(id) ON DELETE CASCADE,
  child_order             INTEGER CHECK (child_order >= 0),
  params_json             TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(params_json)),
  starred                 INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0,1)),
  deleted_at              TEXT,
  created_at              TEXT NOT NULL,
  updated_at              TEXT NOT NULL,
  CHECK (based_on_generation_id IS NULL OR based_on_generation_id <> id),
  CHECK (parent_generation_id IS NULL OR parent_generation_id <> id)
);

CREATE TABLE generation_variants (
  id            TEXT PRIMARY KEY,
  generation_id TEXT NOT NULL REFERENCES generations(id) ON DELETE CASCADE,
  media_id      TEXT NOT NULL REFERENCES media(id) ON DELETE RESTRICT,
  variant_type  TEXT,
  name          TEXT,
  params_json   TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(params_json)),
  is_primary    INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0,1)),
  starred       INTEGER NOT NULL DEFAULT 0 CHECK (starred IN (0,1)),
  viewed_at     TEXT,
  created_at    TEXT NOT NULL,
  UNIQUE (generation_id, media_id)
);

-- generations page/index queries (gallery)
CREATE INDEX generations_project_page   ON generations(project_id, created_at DESC, id);
CREATE INDEX generations_project_starred ON generations(project_id, starred, created_at DESC, id);
CREATE INDEX generations_project_type   ON generations(project_id, type, created_at DESC, id);
CREATE INDEX generations_based_on       ON generations(based_on_generation_id) WHERE based_on_generation_id IS NOT NULL;
CREATE INDEX generations_parent         ON generations(parent_generation_id) WHERE parent_generation_id IS NOT NULL;
CREATE INDEX generations_task           ON generations(task_id) WHERE task_id IS NOT NULL;

-- variants: one primary per generation + membership lookups
CREATE UNIQUE INDEX generation_one_primary
  ON generation_variants(generation_id) WHERE is_primary = 1;
CREATE INDEX generation_variants_generation
  ON generation_variants(generation_id, is_primary, created_at, id);
CREATE INDEX generation_variants_media
  ON generation_variants(media_id, generation_id);
```

### 2.1 Column-by-column conventions (all tables)

> **Amended (doc 24 Q1):** Placement-only columns and foreign-key actions no longer apply to this migration.

| Rule | Value | Precedent |
|---|---|---|
| PKs | 26-char lowercase Crockford ULID (`generate_lowercase_ulid`), caller-supplied on import replay (deterministic) | `astrid/core/ids.py`; shots/references repos |
| Timestamps | TEXT, ISO 8601 UTC, `Z` suffix from `utc_now_iso()`; `created_at`/`updated_at` NOT NULL; `deleted_at`/`viewed_at` NULL | `astrid/core/util/time.py`; all kernel/pack tables |
| Booleans | `INTEGER NOT NULL DEFAULT 0 CHECK (x IN (0,1))` | `task_outputs.is_primary`, `media_references.is_primary` |
| JSON | `TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(...))`, canonical sorted-key compact JSON, 1 MiB input / 4 MiB output bound | `params_json`, `metadata_json` everywhere |
| Nullable domain text | `type` NOT NULL (repo-enforced closed set), `variant_type`/`name` NULL | `runs.kind` free text; `evidence_items.kind` repo-enforced |
| Self-FKs | `CHECK (x IS NULL OR x <> id)` | `task_dependencies` `CHECK (task_id <> depends_on_task_id)` |
| FK actions | `generations.project_id` CASCADE; `task_id` SET NULL; `based_on` SET NULL; `parent` CASCADE; `generation_variants.generation_id` CASCADE + `media_id` RESTRICT (variant pins bytes) | Reigh FK actions (doc 07 §3.6) + `shot_items.media_id` RESTRICT |

### 2.2 Design decisions baked into the DDL

> **Amended (doc 24 Q1):** These decisions now cover relational generation and variant state only.

- **No `event_stream_id` column on `generations`.** The shots pack derives `stream_id = f"{aggregate_id}:{stream_type}"` (constant `SHOT_STREAM_TYPE`); the timeline/runs/tasks kernel tables store the column instead. Follow the pack I extend: derive. (If a future cross-aggregate lookup needs the join, add a `generation.event_stream_id` column in a forward-only v3.)
- **`type` is repo-enforced, not DDL-CHECKed.** Seed `GENERATION_TYPES = ("image", "video", "audio", "other")`; import maps unknown source `type` values → `'other'` or extends the constant (extending requires no migration — same posture as `evidence_items.kind`, doc 04 §3.14). Freeze into DDL CHECK in a later migration once the imported vocabulary is confirmed (Q4).
- **`generation_variants.variant_type` stays open text** (NULL allowed); the only hard rule is the protected `'original'` value (removal guard, §4.2.6). Vocabulary freeze is a later decision (Q4).
- **Soft delete for generations** (`deleted_at` + `generation.deleted` event), mirroring `project_references.archived_at` / `reference.archived` — the only kernel-adjacent soft-delete precedent (doc 04 §7). Bytes and variants survive; gallery lists hide deleted generations. Timeline-document commands decide how references to deleted generations are surfaced or removed. No cascade row deletion (doc 24 Q1).
- **`generation_variants` has no `project_id`** (denormalized in Reigh; derived from `generation_id`); same-project agreement between `generation.project_id` and `media.project_id` is repository-enforced (like shot items, `ShotMediaError`).
- **No triggers.** Reigh's generation/variant trigger behavior (primary demotion, generation/variant sync, original-variant protection) is replaced by repository-atomic commands inside the single writer. The old `shot_generations` placement triggers are not ported because placement is document-native (doc 24 Q1). [01 §3.2, 07 §3.4]

### 2.3 Placement is document-native (doc 24 Q1)

> **Amended (doc 24 Q1):** This section replaces the former placement-table design.

Shot groups, generation pools, timing, ordering, and boundary overrides live in `timelines.document_json`, the same CAS-versioned timeline document used by the video editor. They are edited through timeline document commands and the existing timeline load/save paths, not mirrored into relational placement rows.

`generations` and `generation_variants` remain relational because generation identity, task lineage, gallery metadata, exact media membership, and the one-primary invariant need indexed repository semantics. A timeline document references those generation/media identities; it does not become their source of truth.

Group duplication is a timeline-document command with **deep-copy** semantics: it copies group structure and media references, enqueues/copies generated final-video assets, and records the source group in `derived_from`/`based_on` lineage. The duplicate is independent and consumes additional disk except where content-addressed storage deduplicates identical bytes (doc 24 Q2).

Thumbnails are not placement state and do not return as a relational URL column. They are a separate fully local task/capability whose outputs enter managed media; Phase 1 must decide its scope for gallery-scale usability (doc 24 considerations §2).

---

## 3. Vocabulary additions (registry)

> **(Amended: Grok review — judged ADOPT.)** This section is superseded historical design. V1 adds no per-generation stream/event/command vocabulary; task completion's existing receipt/UoW is the atomicity record, and small generation mutations serialize through the writer without extending the event registry.

> **Amended (doc 24 Q1):** Placement events and commands are removed; timeline-document vocabulary owns shot-group edits.

Namespaced dotted names, all declared by pack `shots` in `schema-pack.yaml`. Validation: `_NAMESPACED_NAME_RE` (`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`), registry uniqueness, aggregate-rule agreement at append time (`events/registry.py`).

### 3.1 Stream type

| Stream type | Aggregate rule | subject_type | Subject |
|---|---|---|---|
| `generation.generation` | one per generation, aggregate_id = generation id, not project | `generation` | the generation the stream records |

### 3.2 Event kinds (9) — one stream per aggregate, hash-chained SD2 envelope `{data, _integrity:{previous_event_hash, event_hash}}`

| Event kind | Stream | data (payload `data` object; `changes_json` mirrors keys) |
|---|---|---|
| `generation.created` | generation | `{generation_id, project_id, type, task_id?, name?, based_on_generation_id?, parent_generation_id?, child_order?, params, starred, created_at}` — also carries the initial variant when created via `record_completion` (§5): `variants: [{variant_id, media_id, variant_type?, name?, params, is_primary}]` |
| `generation.updated` | generation | `{generation_id, name?, params?, type?}` — only mutable fields present |
| `generation.starred` | generation | `{generation_id, starred: true, previous: false}` |
| `generation.unstarred` | generation | `{generation_id, starred: false, previous: true}` |
| `generation.deleted` | generation | `{generation_id, deleted_at}` |
| `generation.variant_added` | generation | `{generation_id, variant_id, media_id, variant_type?, name?, params, is_primary, starred, viewed_at?}` |
| `generation.variant_updated` | generation | `{generation_id, variant_id, name?, params?, starred?, viewed_at?}` — only changed fields |
| `generation.variant_removed` | generation | `{generation_id, variant_id, media_id, variant_type?, was_primary}` |
| `generation.primary_changed` | generation | `{generation_id, previous_variant_id, new_variant_id}` (mirrors `reference.primary_changed` shape) |

`schema_version = 1` on all. `actor_kind` default `'local'` (bridge/worker paths pass `'executor'`/`'system'`). Heartbeat-style noise is not modeled — there is no non-event update in this pack.

### 3.3 Command kinds (10) — receipt identity (`command_receipts.command_kind`)

| Command kind | Repository method | Notes |
|---|---|---|
| `generation.create` | `GenerationRepository.create` | general create; optional initial variant for the completion path |
| `generation.record_completion` | `GenerationRepository.record_completion` | atomic task-completion → generation command (§5) |
| `generation.update` | `GenerationRepository.update` | mutable name/params/type |
| `generation.star` / `generation.unstar` | `star` / `unstar` | idempotent; no-op replay returns stored receipt |
| `generation.delete` | `delete` | soft-delete guard: already-deleted → `GenerationDeletedError` |
| `generation.add_variant` | `add_variant` | guards: duplicate media membership, generation deleted |
| `generation.update_variant` | `update_variant` | name/params/starred/viewed_at |
| `generation.remove_variant` | `remove_variant` | guard: `variant_type == 'original'` protected; clears primary flag on the removed primary |
| `generation.set_primary` | `set_primary` | replaces primary collision-safely (demote old, promote new, one txn) |

---

## 4. Repository design

> **(Amended: Grok review — judged ADOPT.)** The event-sourced repository below is not built for v1. Implement bounded reads plus only the small writer-serialized star/primary/soft-delete/needed variant-metadata operations; DDL constraints and the single writer enforce the surviving invariants.

### 4.1 `GenerationRepository` (`astrid/packs/shots/generation_repository.py`)

Copy the `ShotRepository` skeleton exactly: module constants for every kind (`GENERATION_STREAM_TYPE = "generation.generation"`, `GENERATION_CREATED_EVENT_KIND`, …, `GENERATION_CREATE_COMMAND_KIND`, …), typed error classes subclassing `RepositoryError` (`GenerationNotFoundError(project_id, generation_id)`, `GenerationValidationError`, `GenerationAlreadyExistsError`, `GenerationMediaError(media_id, project_id, detail)`, `GenerationPrimaryError(detail)`, `GenerationDeletedError(generation_id)`, `VariantNotFoundError`, `VariantProtectedError`), frozen slot dataclasses with `to_dict`/`from_mapping` (`GenerationReadModel`, `VariantReadModel`, `GenerationMutationReadModel`, `GenerationPrimaryChangeReadModel`, `GenerationDeleteReadModel`), `__init__(events, receipts)` composing `EventAppendService` + `ReceiptService`.

Every command method signature pattern (mirroring `shots/repository.py`):

```python
def <command>(self, uow: UnitOfWork, *, project_id: str, ..., idempotency_key: str,
              actor_kind: str = "local", <id>_id: str | None = None,
              created_at: str | None = None,
              command_kind: str = <KIND>) -> <ReadModel>:
```

### 4.2 Atomic guard checklist — every command, in order (zero rows change on any failure)

> **Amended (doc 24 Q1):** Placement positions and shot/generation agreement are not generation-repository guards.

1. **Receipt gate first**: `self._receipts.check(uow, project_id, idempotency_key, request_hash, command_kind)` — replay returns the stored read model verbatim; key reuse with different bytes → `ReceiptMismatchError` before any mutation. `request_hash = request_hash(command_kind, request)` over semantic fields only (`project_id`, ids, `type`, `name`, `params`, `is_primary`, …); generated values (`created_at` stamps, `uuid4().hex` event/txn ids) excluded (`GENERATED_FIELD_NAMES`, doc 04 §7).
2. **Project existence** (`SELECT id FROM projects WHERE id = ?`) → `ProjectNotFoundError`.
3. **Aggregate existence + project agreement** (generation rows: `WHERE id = ? AND project_id = ?`) → `GenerationNotFoundError`; deleted generations reject all mutating commands except `delete` (replay) → `GenerationDeletedError`.
4. **Media agreement** (add_variant): `media` row exists and `media.project_id == project_id` → `GenerationMediaError(detail="missing"|"foreign")`.
5. **Uniqueness**: `UNIQUE (generation_id, media_id)` membership pre-check → `GenerationValidationError("variant media already member")`; duplicate ids → `GenerationAlreadyExistsError`/`VariantNotFoundError`.
6. **Protected values**: `remove_variant` refuses `variant_type == 'original'` → `VariantProtectedError` (mirrors Reigh `trg_prevent_original_variant_deletion`).
7. **Self-reference**: `based_on_generation_id`/`parent_generation_id` must be same-project, existing, and `<> id` (DDL CHECK backs the last).
8. **Stream creation**: only on `create`/`record_completion` — `INSERT INTO event_streams (id, project_id, stream_type, aggregate_id, head_seq, created_at) VALUES ('<gen_id>:generation.generation', ?, 'generation.generation', ?, 0, ?)` (copy shots repo step 1).
9. **Writes → event append → heads → receipt** in one txn, then return the frozen read model.

### 4.3 Event + receipt semantics per command

> **Amended (doc 24 Q1):** Receipts cover generation and variant mutations only.

- **create** — one stream, one `generations` row (no ordering column), `generation.created`, receipt with `result = GenerationReadModel.to_dict()`, `primary_stream_id = "<gen_id>:generation.generation"`, `resulting_stream_seq = 1`.
- **star / unstar** — `UPDATE generations SET starred = ?, updated_at = ?`; event `generation.starred`/`generation.unstarred`; `changes_json = ["starred"]`. Idempotent toggles: an identical retry replays; a same-state request under a *different* key still appends an event (it is a real mutation record, matching the "every meaningful mutation is an event" posture, doc 05 §1).
- **add_variant** — `INSERT generation_variants` (+ optional demote/promote when `is_primary=1` and a primary exists: `UPDATE ... SET is_primary=0` on the old primary in the same txn — the partial unique index would otherwise reject); event `generation.variant_added` (+ `generation.primary_changed` when primary switched); receipt result carries the variant + `is_primary` + generation `updated_at`.
- **set_primary** — demote current `is_primary=1` row (if any), promote target; event `generation.primary_changed` with previous/new variant ids; `GenerationPrimaryError(detail="missing_variant"|"already_primary"|...)` patterns per `ReferencePrimaryError`; receipt result `GenerationPrimaryChangeReadModel` (mirror `ReferencePrimaryChangeReadModel`).
- **remove_variant** — guard original; delete row; if the deleted row was primary, no replacement is auto-promoted (zero-primary is legal under the partial index — Reigh's primary-ref clear trigger is replaced by this invariant); event `generation.variant_removed` with `was_primary`; kernel `media` row, location, and bytes are untouched (mirror shot_items removal note in `sdk/shots.py`).
- **delete** — set `deleted_at` + `updated_at`; event `generation.deleted`; gallery `list`/`show` filters respect `deleted_at`; bytes and variants are preserved (Q5 for hard-delete semantics). Timeline-document reference handling is outside this repository (doc 24 Q1).
- **update** — mutable `name`/`params`/`type` only; `project_id` and all FK facts immutable; event `generation.updated` with only changed fields in `changes_json` (mirror `reference.updated`, `REFERENCE_UPDATED_EVENT_KIND`).

### 4.4 No relational placement repository

> **Amended (doc 24 Q1):** Do not add generation placement methods, constants, read models, or receipts to `ShotRepository` or `GenerationRepository`.

Shot-group mutations are commands against `timelines.document_json` and use the timeline repository's existing CAS/event semantics. The generation repository neither mirrors those mutations nor appends placement events.

### 4.5 Read paths (no transactions, `writer.read_only_connection()`)

> **Amended (doc 24 Q1; thumbnails per doc 24 considerations §2):** Relational reads serve gallery content; timeline-document reads serve shot groups.

- `GenerationRepository.list(writer, project_id, *, type=None, starred_only=False, deleted=False, limit=1000)` — `generations_project_page`-ordered, filters via the type/starred indexes; returns `GenerationListRow` + primary/earliest variant media facts. It does not fabricate a thumbnail URL; thumbnail media is produced by a separate local task/capability.
- `show(writer, project_id, generation_id)` — generation + ordered variants (primary first), with no placement projection.
- Shot-group reads load the CAS-versioned timeline document and resolve its generation/media references through these relational reads. No `ShotRepository` placement expansion or relational composition join is added.

---

## 5. The atomic completion command — `generation.record_completion`

> **Amended (doc 24 Q1):** Atomic completion keeps task completion, managed media, generation/variant creation, and required timeline asset-registry visibility in one transaction; shot-group placement remains a separate timeline-document edit.

Doc 14 §3 requires task completion, media materialization, and generation projection to commit in ONE writer transaction ("completion atomicity" risk). Spec:

```python
def record_completion(self, uow: UnitOfWork, *, project_id: str, task_id: str,
                      type: str, params: Mapping, variant: {...},
                      timeline_visibility: {...} | None = None,
                      idempotency_key: str, actor_kind: str = "executor",
                      generation_id: str | None = None, created_at: str | None = None) -> GenerationReadModel
```

Inside the caller's single `BEGIN IMMEDIATE` callback, in order:
1. Receipt gate (command kind `generation.record_completion`); replay returns stored result.
2. Load `tasks` row; require terminal status (`succeeded`) and `winning_attempt_id` set → else `GenerationValidationError` (never a live lease; doc 15 Q2). Same-project check.
3. Inline the task-output materialization step (verify staged bytes → `media` + `media_locations` + `task_outputs` rows + `derived_from`/`uses_as_input` relations) using the same code `TaskRepository.complete` runs — as an inner idempotent unit keyed by the task's own receipt (two receipts, two `txn_id`s, same SQLite txn — legal: receipts are rows, `txn_id UNIQUE` per row; `first/last_project_seq` ranges just partition the txn's events).
4. Create the `generation.generation` stream + `generations` row + `generation.created` event (carrying the initial variant facts, §3.2).
5. Insert the initial `generation_variants` row (`is_primary=1`).
6. When `timeline_visibility` is requested, run the internal evented asset-registry merge against the current timeline head and advance `config_version` in the same unit of work. This makes the generated media addressable without changing `shotGroups`, `poolGenerationIds`, clip ordering, timing, or boundaries (docs 20 §18.5/§19.4; doc 24 Q1).
7. Write the single `generation.record_completion` receipt (result = `GenerationReadModel` including the variant and any resulting timeline registry version).

The event `generation.created` is the atomicity record: a crash before commit rolls everything back; a crash after commit is replayed via the receipt. The old Reigh split path (edge `createGenerationFromTask` vs DB trigger — contradiction #8 in the README) is gone: this is the only generation-creation path from task completion.

---

## 6. SDK service surface + CLI mounts

### 6.1 `GenerationsService` (`astrid/sdk/generations.py`)

> **Amended (doc 24 Q1):** The SDK service has no placement verbs and delegates only relational content operations.

Copy the `ShotsService` skeleton (`astrid/sdk/shots.py`): no SQL, no writer of its own, delegates to `GenerationRepository`, every mutation returns one `DomainResult` five-key envelope with `receipt` + `idempotency_key`, errors via `map_error`. Deterministic ids: derive `generation_id` from `(generation.create, project_id, idempotency_key)` and variant ids from `(command_kind, aggregate scope, key, ordinal)` via `derive_stable_id` (`sdk/contracts.py:310`) so retries replay. Methods (one per CLI verb):

`create(project, type, *, name, params, based_on_generation_id, parent_generation_id, child_order, task_id, idempotency_key=None)`, `list(project, *, type=None, starred_only=False, deleted=False)`, `show(project, generation_id)`, `update(project, generation_id, *, name, params, type)`, `star`/`unstar(project, generation_id)`, `delete(project, generation_id)`, `add_variant(project, generation_id, media_id, *, variant_type, name, params, is_primary, idempotency_key=None)`, `update_variant(project, generation_id, variant_id, *, name, params, starred, viewed_at)`, `remove_variant(project, generation_id, variant_id)`, `set_primary(project, generation_id, variant_id)`.

Wire-up: `astrid/sdk/client.py` gets a `generations` property (→ `self._app.generations_service`), the import block adds `from astrid.sdk.generations import GenerationsService`, and the standard application composition (`astrid/application/...`, where `projects_service`/`shots_service` are constructed) adds `generations_service` + registers `GenerationRepository` into the writer-owning composition. `runs close`-style SDK-only facades (doc 14: "a public `RunsService.create` facade is needed") are out of scope here but the composition note stands.

### 6.2 CLI

> **Amended (doc 24 Q1):** Pack-v2 CLI additions are generation/variant-only.

- New nested mount `media generations` (family key `generations`, declared in `schema-pack.yaml` `cli_mounts`) — mirror `media references` (`astrid/packs/references/cli.py`): verbs `list/create/show/update/star/unstar/delete/add-variant/remove-variant/set-primary/variants?` — one verb = one SDK call, `--json` envelope, exit codes 0/1/2, `_add_idempotency_key`/`_add_project_arg` helpers copied from the shots CLI.

### 6.3 Bridge mounts

`schema-pack.yaml` `bridge_mounts` stays `[]` for the shots pack: the frozen timeline bridge routes are untouched (doc 09), and the `ReighContentBridgeAdapter` routes (projects/generations/variants/media) are a separate phase-1 artifact that consumes these repositories. **Amended (doc 24 Q1):** shot groups use the existing timeline document load/save CAS routes rather than a new `/shots` content route. The bridge DTOs will map 1:1 to the read models above.

---

## 7. Import/replay notes (future phase, design guardrails)

> **(Amended: Grok review — judged ADOPT.)** Historical evidence only. Fresh start removes importer/replay keys, deterministic legacy-ID mapping, production exports, and replay ordering from the journey.

> **Amended (doc 24 Q1):** Any future replay maps generation/variant rows only; placement belongs in the timeline document rather than an import receipt family.

- Receipt keys: `reigh-import:v1:generation:{source_uuid}`, `...:variant:{source_uuid}` (doc 14 §4; v10 pattern `v10-migrate:{family}:{stable-id}` — doc 11).
- Deterministic ids: map source UUID → ULID via the v10 deterministic derivation (`derive_stable_id`/`derive_ulid`), preserving the mapping for FK remapping (`based_on`, `parent_generation_id`, `task_id`, `media_id`).
- Preserve original timestamps via `created_at`/`updated_at` overrides (kernel commands accept them; generated stamps excluded from request hashes) and keep the raw source row in `params_json`/metadata as an audit artifact (doc 13 §5.4).
- Media: bytes are hashed on import; `location`/`thumbnail_url` strings are NOT imported (they are Supabase URLs); unimportable/expired URLs are cataloged in the export manifest (doc 15 Q4: referenced objects only).
- Import order (doc 14 §4): projects → media → tasks/runs/attempts → generations/variants → timelines/references (including any document-native shot groups). Never import an `In Progress` task as a live lease (doc 15 Q2); deleted/terminal-only semantics map to `deleted_at`/terminal task statuses.
- Export is SELECT-only from live prod (doc 07, not repo migrations) — ground truth per README contradiction #1.

---

## 8. Parity — represented vs deliberately dropped

> **Amended (doc 24 Q1/Q2; thumbnails per doc 24 considerations §2):** Parity now separates relational generation/media facts from document-native composition facts.

### 8.1 `generations` (Reigh live, doc 07 §3.1 / doc 01 §3.2)

| Reigh column | Pack v2 | Notes |
|---|---|---|
| `id` uuid | `generations.id` ULID | deterministic ULID on import |
| `project_id` | ✓ `generations.project_id` | FK CASCADE |
| `tasks` jsonb | `generations.task_id` FK → kernel `tasks` | single producing task (completion path); multi-task families → `params_json` (Q3) |
| `params` jsonb | ✓ `params_json` | canonical sorted-key JSON |
| `location` text | ✗ → `generation_variants.media_id` | bytes are kernel media; no URL column |
| `type` text | ✓ `type` | repo-enforced set, DDL freeze later (Q4) |
| `created_at` / `updated_at` | ✓ | ISO-8601 UTC |
| `starred` bool | ✓ `starred` | `CHECK IN (0,1)` |
| `thumbnail_url` | ✗ | no URL column; a separate local thumbnail task/capability produces managed-media output |
| `name` | ✓ `name` (nullable) | |
| `based_on` uuid | ✓ `based_on_generation_id` | SET NULL, same-project + `<> id` CHECK |
| `copied_from_share` | ✗ **dropped** | sharing cut (doc 15 Q5) |
| `shot_data` jsonb | ✗ **dropped** | trigger-maintained denormalization; shot groups/pools live in `timelines.document_json` (doc 24 Q1) |
| `parent_generation_id` / `child_order` / `is_child` | `parent_generation_id` + `child_order` ✓; `is_child` ✗ derived (`parent_generation_id IS NOT NULL`) | |
| `children` jsonb | ✗ **dropped** | derived by query (avoid trigger-sync cache) |
| `primary_variant_id` | ✗ **dropped** | derived via `generation_one_primary` partial unique index; no trigger-synced pointer (SD1) |
| `pair_shot_generation_id` | ✗ **dropped** | pair/group structure is document-native; group duplicate is a deep-copy document command with lineage (doc 24 Q1/Q2) |
| `storage_mode`, `local_handle_id`, `local_file_name/size/mime` | ✗ **dropped** | pending-materialization machinery; local media import materializes bytes (doc 15) |

### 8.2 `generation_variants` (live, doc 07 §3.1)

| Reigh column | Pack v2 | Notes |
|---|---|---|
| `id` | ✓ ULID | |
| `generation_id` | ✓ FK CASCADE | |
| `location` | ✗ → `media_id` FK RESTRICT | exact bytes; one row per variant |
| `thumbnail_url` | ✗ | no URL column; thumbnails are separate local-task outputs in managed media |
| `params` | ✓ `params_json` | |
| `is_primary` | ✓ + `generation_one_primary` partial unique index | one primary per generation (replaces `trg_handle_variant_primary_switch`) |
| `variant_type` | ✓ `variant_type` (NULL allowed) | `'original'` protected from removal |
| `name` | ✓ (nullable) | |
| `created_at` | ✓ | |
| `project_id` | ✗ derived | same-project enforced by repository |
| `viewed_at` | ✓ `viewed_at` (nullable) | gallery seen-marker |
| `starred` | ✓ `starred` | |
| (unique media membership) | ✓ `UNIQUE (generation_id, media_id)` | doc 14 requirement |

### 8.3 `shot_generations` (live, doc 07 §3.1)

> **Amended (doc 24 Q1):** This legacy table is not recreated. Every placement field maps into the timeline document instead of pack-v2 DDL.

| Reigh column | Pack v2 | Notes |
|---|---|---|
| `id` | ✗ relational row | document-native group/item identity where needed |
| `shot_id` | ✗ relational FK | group membership in `timelines.document_json` |
| `generation_id` | ✗ placement FK | generation reference in the document; the referenced generation remains relational |
| `created_at` / `updated_at` | ✗ placement timestamps | timeline document revision/CAS history is authoritative |
| `timeline_frame` int NULL | ✗ relational column | document-native timing |
| `metadata` jsonb | ✗ placement JSON row | document-native boundary and segment overrides |
| `position` int | ✗ relational column | document array/order structure |
| shot `position`/`aspect_ratio`/`settings` | ✗ pack-v2 placement state | focused shot mode edits the same timeline document as the video editor |

### 8.4 Cut wholesale (binding, doc 15 + doc 14 §4)

`shared_generations`, credits/`credits_ledger`, users/auth/RLS/PATs, referrals, `attempts`/`shot_slots`/`slot_first_*` (archived as read-only JSONL export — never mapped to kernel tables), `task_types` registry, `shot_data_audit`, `resources`, `external_api_keys`, `local_media_handles`, `shot_final_videos` view (composition is document-native; doc 24 Q1), timeline-agent sessions (Q6).

---

## 9. Conventions checklist (acceptance gate for the implementer)

> **Amended (doc 24 Q1):** Acceptance excludes relational placement artifacts.

- [ ] ULID lowercase Crockford PKs; `uuid4().hex` event/txn ids; stream id `<aggregate>:generation.generation`; `schema_migrations (pack='shots', version=2, name='generations')`.
- [ ] ISO-8601-UTC TEXT timestamps; `CHECK (json_valid(...))` on all `*_json`; booleans `CHECK IN (0,1)`; canonical JSON bounds (1 MiB in / 4 MiB out).
- [ ] `FORBIDDEN_TABLES` untouched; no new forbidden names; 22-table composition expectations updated.
- [ ] One command = one `BEGIN IMMEDIATE` callback = receipt gate → validation → writes → event(s) → heads → receipt; identical retry replays stored receipt; changed bytes under same key → `ReceiptMismatchError`.
- [ ] Registry vocabulary declared in `schema-pack.yaml` and `STREAM_AGGREGATE_RULES` before any mutation; event kind pack == stream type pack; subject = stream aggregate.
- [ ] No triggers, no URL/denormalization columns, no soft-delete beyond `deleted_at`, no shims or aliases; every read through `read_only_connection()`.
- [ ] No `shot_generation_items` table, placement command/event vocabulary, placement repository methods, or placement CLI verbs; shot groups load and save through the CAS-versioned timeline document (doc 24 Q1).

---

## Open questions

> **Amended (doc 24 Q1/Q2; thumbnails per doc 24 considerations §2):** Pair-item and placement-table questions are closed. Placement is document-native, and group duplication is a deep-copy document command with source lineage.

1. **Pack identity** — doc 14 says "shots/content pack": keep pack id `shots` with migration v2 (this spec) or split a new `content` pack (`depends_on: [core >= 1, shots >= 1]`) owning the two tables? Registry supports either; v2-in-shots is the smaller change and matches the phase-1 doc title.
2. **`tasks` jsonb → single `task_id`** — Reigh may record multiple task ids per generation; confirm single-FK is sufficient for the completion path, else model a `generation_tasks` join table (would be a third table in this migration).
3. **Closed vocabularies** — freeze `type` and `variant_type` into DDL CHECKs in a later migration once the live distinct-value sets are exported (the exporter should emit `SELECT DISTINCT type FROM generations` and variants for this).
4. **Deletion semantics** — soft-delete (`deleted_at`) chosen; confirm no product path needs hard delete + byte GC (kernel has no deletion precedent; `media` rows are RESTRICT-pinned by variants).
5. **Variant starring** — `generation_variants.starred` exists but no standalone star command is specced (covered by `update_variant`); confirm the gallery doesn't need a dedicated variant-star verb.
6. **Thumbnail task scope** — decide in Phase 1 whether local thumbnail generation is mandatory for v1 gallery acceptance; it remains a separate local task/capability with managed-media output, not a `thumbnail_url` column (doc 24 considerations §2).

### Closed by owner decision

- **Placement authority (doc 24 Q1):** shot groups, pools, timing, ordering, pairs, and boundary overrides live only in `timelines.document_json`; do not add pair-item or placement tables.
- **Group duplicate (doc 24 Q2):** deep-copy structure and media refs, enqueue/copy generated final-video assets, and record `derived_from`/`based_on` source lineage. This is not an open schema choice.
- **Completion atomicity (docs 20 §17.7/§18.5; doc 24 Q1):** one composite receipt and writer transaction commits task/media/generation/variant state plus any required evented timeline asset-registry visibility; there is no reconciliation path and no relational placement step.
