# 17 — Shots Pack v2: Generations / Variants / Shot Placement (DDL + Repositories + Events)

**Design spec for the pack migration that gives Reigh's content estate an Astrid-native home.** Extends the existing `shots` schema pack (`Astrid/astrid/packs/shots/`, currently migration version 1 with tables `shots`, `shot_items`) with a forward-only migration v2 creating three new owned tables — `generations`, `generation_variants`, `shot_generation_items` — plus the receipt-backed `GenerationRepository`, placement commands on `ShotRepository`, new registry vocabulary (stream type `generation.generation`, 12 event kinds, 13 command kinds), a `generations` SDK service + `media generations` CLI mount, and an atomic task-completion → generation command. Every table/command follows kernel conventions verified in `04-astrid-sqlite-schema.md` and the existing pack sources: lowercase Crockford ULID PKs, ISO-8601-UTC TEXT timestamps, DDL `CHECK`s for booleans and `json_valid`, pack FKs pointing inward to the kernel only, per-aggregate event streams, hash-chained events, and one `command_receipts` row per command with replay-first idempotency. Credits, auth, sharing, the slot system (`attempts`/`shot_slots`), and Postgres denormalizations are deliberately NOT modeled (binding owner decisions, doc 15).

**Key facts**
- Migration file: `Astrid/astrid/packs/shots/migrations/0002_generations.sql`; pack manifest version 1→2; second `migrations:` entry `{version: 2, name: generations}`; applied by the existing runner (SHA-256 checksum, `BEGIN IMMEDIATE`, atomic `schema_migrations` row) — no new runner work. [04 §2.3, 05 §5.4]
- `generations` = one row per gallery "family" (Reigh `generations`, 38k rows): ULID id, `project_id`, `task_id` (FK → kernel `tasks` SET NULL), `type`, `name`, self-FKs `based_on_generation_id` (SET NULL) / `parent_generation_id` (CASCADE) + `child_order`, `params_json`, `starred`, soft-delete `deleted_at`, timestamps. [01 §3.2, 07 §3.1]
- `generation_variants` = exact media rows under a generation (Reigh `generation_variants`, 40k rows): `media_id` FK → kernel `media` RESTRICT (bytes are the kernel currency, plugin law 2), `variant_type`, `name`, `params_json`, `is_primary`, `starred`, `viewed_at`, `created_at`; `UNIQUE (generation_id, media_id)` (unique media membership) + partial unique index `generation_one_primary` (one primary per generation). [04 §3.16/§3.13, 14 §4]
- `shot_generation_items` = placement join (Reigh `shot_generations`, 12k rows): `shot_id` FK → `shots` CASCADE, `generation_id` FK → `generations` CASCADE, nullable `timeline_frame`, `sort_key` (normalized 0..n-1, 12-wide zero-padded, `UNIQUE (shot_id, sort_key)`), `metadata_json` (segment overrides), timestamps; `UNIQUE (shot_id, generation_id)` — a generation placed at most once per shot. [01 §3.2, 07 §3.1]
- One event stream per generation (`<generation_id>:generation.generation`), pattern-copied from the shots pack (`SHOT_STREAM_TYPE`; streams are derived, no `event_stream_id` column — `Astrid/astrid/packs/shots/repository.py`). Placement events append to the *shot* stream (`shot.generation_placed` / `_unplaced` / `_positioned`), mirroring `shot.item_added`.
- Every mutation is one `BEGIN IMMEDIATE` callback: receipt gate → validation (zero rows on rejection) → writes → hash-chained event(s) → heads → one receipt (`request_hash` over semantic fields, generated fields excluded). [04 §2.4, shots repo create/add_item/reorder]
- Deliberately dropped (owner cut list, doc 15): `storage_mode`, `local_handle_*`, `thumbnail_url`/`location` URLs (bytes become `media`), `shot_data`/`children` JSONB denormalizations (derived by query), `primary_variant_id` pointer (derived via partial index), `copied_from_share`/`shared_generations` (sharing cut), `position` column (superseded by `sort_key` + `timeline_frame`), `pair_shot_generation_id` (open question), the live slot system and `attempts` (archived, not imported).
- `FORBIDDEN_TABLES` contains `variants` but enforcement is exact-name set intersection (`catalog.py:145`, `scripts/reshape/authority_lint.py:600`, `tests/v10/*`), so `generation_variants` does **not** collide. The `m4_gate.py` "frozen 20 tables" composition count and the conformance kit must be bumped to 23.
- Import replay (future phase) uses receipt keys `reigh-import:v1:generation:{source_uuid}` and deterministic ULIDs derived from source UUIDs, matching the v10 migration machinery (`Astrid/scripts/migrations/v10/`, doc 11; doc 14 §4).

Sources: docs 01 §3.2, 04 §2–§7, 05 §2–§5, 07 §3.1, 13 §3, 14 §4, 15; repo `Astrid/astrid/packs/{shots,timeline,references}/{schema-pack.yaml,migrations/0001_initial.sql,repository.py,cli.py}`, `Astrid/astrid/core/{events/registry.py,migrations/{catalog.py,runner.py},schema_packs/registry.py}`, `Astrid/astrid/sdk/{client.py,shots.py,contracts.py}`.

---

## 1. Pack identity and migration file spec

### 1.1 What changes (all under `Astrid/astrid/packs/shots/`)

| Artifact | Today | After v2 |
|---|---|---|
| `schema-pack.yaml` `version:` | `1` | `2` (manifest version bump; `depends_on: [core >= 1]` unchanged) |
| `schema-pack.yaml` `migrations:` | one entry `{version: 1, name: initial, path: migrations/0001_initial.sql, tables: [shots, shot_items]}` | add `{version: 2, name: generations, path: migrations/0002_generations.sql, tables: [generations, generation_variants, shot_generation_items]}` |
| `migrations/` | `0001_initial.sql` | + `0002_generations.sql` (this spec §2) |
| `schema-pack.yaml` `stream_types:` | `shot.shot` | + `generation.generation` |
| `schema-pack.yaml` `event_kinds:` | 4 (`shot.*`) | + 12 (§3) |
| `schema-pack.yaml` `command_kinds:` | 4 (`shot.*`) | + 13 (§3) |
| `schema-pack.yaml` `repositories:` | `ShotRepository` | + `GenerationRepository` |
| `schema-pack.yaml` `cli_mounts:` | `shots: timelines shots` | + `generations: media generations` |
| `repository.py` | `ShotRepository` (create/add_item/remove_item/reorder) | + placement methods `place_generation` / `unplace_generation` / `position_generation` |
| new file | – | `generation_repository.py` (`GenerationRepository`) |
| `astrid/core/events/registry.py` `STREAM_AGGREGATE_RULES` | shot/timeline/reference rules | + rule for `generation.generation` (§3.1) |
| `astrid/sdk/` | 7 services | + `generations.py` (`GenerationsService`), wired into `AstridClient` (§6) |
| `astrid/packs/shots/cli.py` | 5 verbs | + `place`/`unplace`/`position`; new `astrid/packs/shots/generations_cli.py` for the `media generations` mount (§6) |
| composition/conformance | `STANDARD_SCHEMA_PACKS` frozen at 20 tables | 23 tables; bump `scripts/reshape/m4_gate.py` and conformance kit table-count expectations |

The `shots` pack keeps its pack id (`shots`): doc 14 calls this "the shots/content pack" and the registry is collision-free as long as one pack owns the three tables — extending `shots` with migration v2 is the smallest correct change. (A separate `content` pack would be defensible; see Open Questions Q1.)

### 1.2 Migration file contract (copy `0001_initial.sql`'s header style)

`0002_generations.sql` MUST:
- Open with a `-- Astrid shots schema pack generation-content migration: shots/0002_generations` header block: transcription provenance (doc 14 §4 sketch + this spec), contract notes (FKs inward only; `media_id` kernel currency; no PRAGMAs — connection-level settings are applied by the runner), and the SD1 note that no slug/ULID/default convenience columns or JSONB denormalizations are created.
- Be forward-only, checksummed by the runner (SHA-256 of exact bytes), and applied atomically with its `schema_migrations` row inside `BEGIN IMMEDIATE` (`runner.py` `apply_pending_migrations`). Statements split on `;` outside literals — keep the file plain DDL, no `CREATE TRIGGER` (guard logic lives in repositories, as in every existing pack), no semicolons inside strings.
- Not repeat PRAGMAs; not touch kernel tables; not add `users`/`billing`/`importer`/`variants`/legacy names (FORBIDDEN_TABLES).
- Version identity: `pack='shots', version=2, name='generations'`. Next migration in the pack would be `0003_*.sql` (versions ascend within a pack; `UNIQUE (pack, name)` prevents name reuse; name drift and checksum drift are rejected on probe — `runner.py`).

### 1.3 Registry wiring

- `astrid/packs/__init__.py` `register_standard_schema_packs` already registers the whole `shots` pack — no change needed for pack inclusion; the yaml diff alone extends the composition.
- `astrid/core/events/registry.py` `STREAM_AGGREGATE_RULES`: add
  `"generation.generation": StreamAggregateRule(subject_type="generation", aggregate_is_project=False, ...)` — one stream per generation, aggregate_id = generation id, event project = stream project, event kind pack must equal stream type pack (all new kinds are declared by pack `shots`). Mirror the existing shot rule entry.
- The registry rejects collisions deterministically (`schema_packs/registry.py::_collect_collisions`): new names must not collide with core (`core.*`) or other packs (`timeline.*`, `reference.*`, `shot.*`). The chosen names in §3 are collision-free.
- `scripts/reshape/m4_gate.py:584` asserts a frozen composition table count (20) — update to 23; the conformance kit (`astrid/core/conformance/kit.py`) and any "20-table" tests get the same bump. Tests that assert `tables.isdisjoint(FORBIDDEN_TABLES)` keep passing (`generation_variants` is not an exact member).

---

## 2. DDL — `migrations/0002_generations.sql`

```sql
-- Astrid shots schema pack generation-content migration: shots/0002_generations
--
-- Adds the three content tables the Reigh gallery/timeline needs (doc 14
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
  created_at    TEXT NOT NULL
);

CREATE TABLE shot_generation_items (
  id             TEXT PRIMARY KEY,
  shot_id        TEXT NOT NULL REFERENCES shots(id) ON DELETE CASCADE,
  generation_id  TEXT NOT NULL REFERENCES generations(id) ON DELETE CASCADE,
  timeline_frame INTEGER,
  sort_key       TEXT NOT NULL,
  metadata_json  TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(metadata_json)),
  created_at     TEXT NOT NULL,
  updated_at     TEXT NOT NULL,
  UNIQUE (shot_id, sort_key),
  UNIQUE (shot_id, generation_id)
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

-- placements: shot ordering, shot membership, reverse lookup, frame lookup
CREATE INDEX shot_generation_items_generation
  ON shot_generation_items(generation_id, shot_id);
CREATE INDEX shot_generation_items_timeline_frame
  ON shot_generation_items(shot_id, timeline_frame) WHERE timeline_frame IS NOT NULL;
```

### 2.1 Column-by-column conventions (all tables)

| Rule | Value | Precedent |
|---|---|---|
| PKs | 26-char lowercase Crockford ULID (`generate_lowercase_ulid`), caller-supplied on import replay (deterministic) | `astrid/core/ids.py`; shots/references repos |
| Timestamps | TEXT, ISO 8601 UTC, `Z` suffix from `utc_now_iso()`; `created_at`/`updated_at` NOT NULL; `deleted_at`/`viewed_at` NULL | `astrid/core/util/time.py`; all kernel/pack tables |
| Booleans | `INTEGER NOT NULL DEFAULT 0 CHECK (x IN (0,1))` | `task_outputs.is_primary`, `media_references.is_primary` |
| JSON | `TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(...))`, canonical sorted-key compact JSON, 1 MiB input / 4 MiB output bound | `params_json`, `metadata_json` everywhere |
| Nullable domain text | `type` NOT NULL (repo-enforced closed set), `variant_type`/`name` NULL, `timeline_frame` NULL (unpositioned) | `runs.kind` free text; `evidence_items.kind` repo-enforced |
| Self-FKs | `CHECK (x IS NULL OR x <> id)` | `task_dependencies` `CHECK (task_id <> depends_on_task_id)` |
| FK actions | `generations.project_id` CASCADE; `task_id` SET NULL; `based_on` SET NULL; `parent` CASCADE; `generation_variants.generation_id` CASCADE + `media_id` RESTRICT (variant pins bytes); `shot_generation_items.shot_id`/`generation_id` CASCADE | Reigh FK actions (doc 07 §3.6) + `shot_items.media_id` RESTRICT |

### 2.2 Design decisions baked into the DDL

- **No `event_stream_id` column on `generations`.** The shots pack derives `stream_id = f"{aggregate_id}:{stream_type}"` (constant `SHOT_STREAM_TYPE`); the timeline/runs/tasks kernel tables store the column instead. Follow the pack I extend: derive. (If a future cross-aggregate lookup needs the join, add a `generation.event_stream_id` column in a forward-only v3.)
- **`type` is repo-enforced, not DDL-CHECKed.** Seed `GENERATION_TYPES = ("image", "video", "audio", "other")`; import maps unknown source `type` values → `'other'` or extends the constant (extending requires no migration — same posture as `evidence_items.kind`, doc 04 §3.14). Freeze into DDL CHECK in a later migration once the imported vocabulary is confirmed (Q4).
- **`generation_variants.variant_type` stays open text** (NULL allowed); the only hard rule is the protected `'original'` value (removal guard, §4.2.6). Vocabulary freeze is a later decision (Q4).
- **Soft delete for generations** (`deleted_at` + `generation.deleted` event), mirroring `project_references.archived_at` / `reference.archived` — the only kernel-adjacent soft-delete precedent (doc 04 §7). Bytes, variants, and placements survive; lists hide deleted generations and shot composition joins exclude them. No cascade row deletion (Q5).
- **Placement ordering is dual**: `timeline_frame` (semantic, nullable — null = unpositioned, sorted last) and `sort_key` (physical order, `UNIQUE (shot_id, sort_key)`, renormalized to 0..n-1 12-wide zero-padded keys on every placement/removal/reposition — copy `_normalized_item_sort_key`/`_renormalize_items` from `shots/repository.py`). `UNIQUE (shot_id, generation_id)` encodes "at most one placement per generation per shot" (Reigh allows a generation in many shots but not twice in one).
- **`generation_variants` has no `project_id`** (denormalized in Reigh; derived from `generation_id`); same-project agreement between `generation.project_id` and `media.project_id` is repository-enforced (like shot items, `ShotMediaError`).
- **No triggers.** Reigh's 12 active content triggers (7 on `generation_variants`, 2 on `generations`, 3 on `shot_generations` — primary demotion, generation/variant sync, shot_data denormalization, placement demotion, original-variant protection) are all replaced by repository-atomic commands inside the single writer. [01 §3.2, 07 §3.4]

---

## 3. Vocabulary additions (registry)

Namespaced dotted names, all declared by pack `shots` in `schema-pack.yaml`. Validation: `_NAMESPACED_NAME_RE` (`^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$`), registry uniqueness, aggregate-rule agreement at append time (`events/registry.py`).

### 3.1 Stream type

| Stream type | Aggregate rule | subject_type | Subject |
|---|---|---|---|
| `generation.generation` | one per generation, aggregate_id = generation id, not project | `generation` | the generation the stream records |

Placed events go on the existing `shot.shot` stream (subject `shot`), exactly like `shot.item_added`.

### 3.2 Event kinds (12) — one stream per aggregate, hash-chained SD2 envelope `{data, _integrity:{previous_event_hash, event_hash}}`

| Event kind | Stream | data (payload `data` object; `changes_json` mirrors keys) |
|---|---|---|
| `generation.created` | generation | `{generation_id, project_id, type, task_id?, name?, based_on_generation_id?, parent_generation_id?, child_order?, params, starred, created_at}` — also carries the initial variant + placement when created via `record_completion` (§5.5): `variants: [{variant_id, media_id, variant_type?, name?, params, is_primary}]`, `placement: {shot_id, item_id, timeline_frame?}` |
| `generation.updated` | generation | `{generation_id, name?, params?, type?}` — only mutable fields present |
| `generation.starred` | generation | `{generation_id, starred: true, previous: false}` |
| `generation.unstarred` | generation | `{generation_id, starred: false, previous: true}` |
| `generation.deleted` | generation | `{generation_id, deleted_at}` |
| `generation.variant_added` | generation | `{generation_id, variant_id, media_id, variant_type?, name?, params, is_primary, starred, viewed_at?}` |
| `generation.variant_updated` | generation | `{generation_id, variant_id, name?, params?, starred?, viewed_at?}` — only changed fields |
| `generation.variant_removed` | generation | `{generation_id, variant_id, media_id, variant_type?, was_primary}` |
| `generation.primary_changed` | generation | `{generation_id, previous_variant_id, new_variant_id}` (mirrors `reference.primary_changed` shape) |
| `shot.generation_placed` | shot | `{shot_id, item_id, generation_id, timeline_frame?, sort_key}` |
| `shot.generation_unplaced` | shot | `{shot_id, item_id, generation_id, timeline_frame?, sort_key}` |
| `shot.generation_positioned` | shot | `{shot_id, item_id, generation_id, previous_timeline_frame, timeline_frame, sort_key}` |

`schema_version = 1` on all. `actor_kind` default `'local'` (bridge/worker paths pass `'executor'`/`'system'`). Heartbeat-style noise is not modeled — there is no non-event update in this pack.

### 3.3 Command kinds (13) — receipt identity (`command_receipts.command_kind`)

| Command kind | Repository method | Notes |
|---|---|---|
| `generation.create` | `GenerationRepository.create` | general create; optional initial variant + placement for the completion path |
| `generation.record_completion` | `GenerationRepository.record_completion` | atomic task-completion → generation command (§5.5) |
| `generation.update` | `GenerationRepository.update` | mutable name/params/type |
| `generation.star` / `generation.unstar` | `star` / `unstar` | idempotent; no-op replay returns stored receipt |
| `generation.delete` | `delete` | soft-delete guard: already-deleted → `GenerationDeletedError` |
| `generation.add_variant` | `add_variant` | guards: duplicate media membership, generation deleted |
| `generation.update_variant` | `update_variant` | name/params/starred/viewed_at |
| `generation.remove_variant` | `remove_variant` | guard: `variant_type == 'original'` protected; clears primary flag on the removed primary |
| `generation.set_primary` | `set_primary` | replaces primary collision-safely (demote old, promote new, one txn) |
| `shot.place_generation` | `ShotRepository.place_generation` | placement insert + sort_key renormalization |
| `shot.unplace_generation` | `ShotRepository.unplace_generation` | placement delete + renormalization |
| `shot.position_generation` | `ShotRepository.position_generation` | set `timeline_frame` + renormalize (null = unpositioned) |

---

## 4. Repository design

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

1. **Receipt gate first**: `self._receipts.check(uow, project_id, idempotency_key, request_hash, command_kind)` — replay returns the stored read model verbatim; key reuse with different bytes → `ReceiptMismatchError` before any mutation. `request_hash = request_hash(command_kind, request)` over semantic fields only (`project_id`, ids, `type`, `name`, `params`, positions, `is_primary`, …); generated values (`created_at` stamps, sort keys, `uuid4().hex` event/txn ids) excluded (`GENERATED_FIELD_NAMES`, doc 04 §7).
2. **Project existence** (`SELECT id FROM projects WHERE id = ?`) → `ProjectNotFoundError`.
3. **Aggregate existence + project agreement** (generation rows: `WHERE id = ? AND project_id = ?`) → `GenerationNotFoundError`; deleted generations reject all mutating commands except `delete` (replay) → `GenerationDeletedError`.
4. **Media agreement** (add_variant): `media` row exists and `media.project_id == project_id` → `GenerationMediaError(detail="missing"|"foreign")`.
5. **Uniqueness**: `UNIQUE (generation_id, media_id)` membership pre-check → `GenerationValidationError("variant media already member")`; duplicate ids → `GenerationAlreadyExistsError`/`VariantNotFoundError`.
6. **Protected values**: `remove_variant` refuses `variant_type == 'original'` → `VariantProtectedError` (mirrors Reigh `trg_prevent_original_variant_deletion`).
7. **Self-reference**: `based_on_generation_id`/`parent_generation_id` must be same-project, existing, and `<> id` (DDL CHECK backs the last).
8. **Position bounds** (placement ops): insertion/resolved position within `0 .. count`; `timeline_frame >= 0` when not null; shot/generation project agreement on both rows before any write.
9. **Stream creation**: only on `create`/`record_completion` — `INSERT INTO event_streams (id, project_id, stream_type, aggregate_id, head_seq, created_at) VALUES ('<gen_id>:generation.generation', ?, 'generation.generation', ?, 0, ?)` (copy shots repo step 1).
10. **Writes → event append → heads → receipt** in one txn, then return the frozen read model.

### 4.3 Event + receipt semantics per command

- **create** — one stream, one `generations` row (`sort_key`-style nothing; no ordering column), `generation.created`, receipt with `result = GenerationReadModel.to_dict()`, `primary_stream_id = "<gen_id>:generation.generation"`, `resulting_stream_seq = 1`.
- **star / unstar** — `UPDATE generations SET starred = ?, updated_at = ?`; event `generation.starred`/`generation.unstarred`; `changes_json = ["starred"]`. Idempotent toggles: an identical retry replays; a same-state request under a *different* key still appends an event (it is a real mutation record, matching the "every meaningful mutation is an event" posture, doc 05 §1).
- **add_variant** — `INSERT generation_variants` (+ optional demote/promote when `is_primary=1` and a primary exists: `UPDATE ... SET is_primary=0` on the old primary in the same txn — the partial unique index would otherwise reject); event `generation.variant_added` (+ `generation.primary_changed` when primary switched); receipt result carries the variant + `is_primary` + generation `updated_at`.
- **set_primary** — demote current `is_primary=1` row (if any), promote target; event `generation.primary_changed` with previous/new variant ids; `GenerationPrimaryError(detail="missing_variant"|"already_primary"|...)` patterns per `ReferencePrimaryError`; receipt result `GenerationPrimaryChangeReadModel` (mirror `ReferencePrimaryChangeReadModel`).
- **remove_variant** — guard original; delete row; if the deleted row was primary, no replacement is auto-promoted (zero-primary is legal under the partial index — Reigh's primary-ref clear trigger is replaced by this invariant); event `generation.variant_removed` with `was_primary`; kernel `media` row, location, and bytes are untouched (mirror shot_items removal note in `sdk/shots.py`).
- **delete** — set `deleted_at` + `updated_at`; event `generation.deleted`; `list`/`show`/placement joins filter `deleted_at IS NULL`; bytes/variants/placements preserved (Q5 for hard-delete semantics).
- **update** — mutable `name`/`params`/`type` only; `project_id` and all FK facts immutable; event `generation.updated` with only changed fields in `changes_json` (mirror `reference.updated`, `REFERENCE_UPDATED_EVENT_KIND`).

### 4.4 Shot placement methods (extend `ShotRepository`)

Add three methods to `astrid/packs/shots/repository.py` (same file as the existing shot aggregate commands; same constants section gets `SHOT_PLACE_GENERATION_COMMAND_KIND`, `SHOT_GENERATION_PLACED_EVENT_KIND`, …). They operate on `shot_generation_items` rows, renormalize `sort_key` with the existing `_renormalize_items`-style pass (factor a shared helper or duplicate the 15-line pattern), refresh `shots.updated_at`, append exactly one event on the shot stream, and write one receipt. Guards: shot exists + project match; generation exists, same project, not deleted; `UNIQUE (shot_id, generation_id)` pre-check for place; `UNIQUE (shot_id, sort_key)` maintained by renormalization; `position_generation` takes `timeline_frame: int | None` and re-orders unpositioned items by `(timeline_frame ASC NULLS LAST, created_at, id)`.

Reasoning: the rows are shot-owned (FK cascade from `shots`), the aggregate owner of the stream is the shot, and the shots pack already owns the placement vocabulary (`shot.*`). The SDK surface (§6) still exposes them as generation/content operations.

### 4.5 Read paths (no transactions, `writer.read_only_connection()`)

- `GenerationRepository.list(writer, project_id, *, type=None, starred_only=False, deleted=False, limit=1000)` — `generations_project_page`-ordered, filters via the type/starred indexes; returns `GenerationListRow` + first-variant thumbnails resolved from `generation_variants` (primary or earliest) — no `thumbnail_url` column.
- `show(writer, project_id, generation_id)` — generation + ordered variants (primary first) + placements per shot.
- `ShotRepository.show` extended to include `shot_generation_items` in the shot read model (positions + generations), and `list` gains a `with_generations` flag; the shot composition read (what `shot_final_videos` view served) is a query joining placements → generations → variants, excluding `deleted_at IS NOT NULL` generations.

---

## 5. The atomic completion command — `generation.record_completion`

Doc 14 §3 requires task completion, media materialization, generation projection, and shot placement to commit in ONE writer transaction ("completion atomicity" risk). Spec:

```python
def record_completion(self, uow: UnitOfWork, *, project_id: str, task_id: str,
                      type: str, params: Mapping, variant: {...}, placement: {...} | None,
                      idempotency_key: str, actor_kind: str = "executor",
                      generation_id: str | None = None, created_at: str | None = None) -> GenerationReadModel
```

Inside the caller's single `BEGIN IMMEDIATE` callback, in order:
1. Receipt gate (command kind `generation.record_completion`); replay returns stored result.
2. Load `tasks` row; require terminal status (`succeeded`) and `winning_attempt_id` set → else `GenerationValidationError` (never a live lease; doc 15 Q2). Same-project check.
3. Inline the task-output materialization step (verify staged bytes → `media` + `media_locations` + `task_outputs` rows + `derived_from`/`uses_as_input` relations) using the same code `TaskRepository.complete` runs — as an inner idempotent unit keyed by the task's own receipt (two receipts, two `txn_id`s, same SQLite txn — legal: receipts are rows, `txn_id UNIQUE` per row; `first/last_project_seq` ranges just partition the txn's events).
4. Create the `generation.generation` stream + `generations` row + `generation.created` event (carrying the variant and optional placement facts, §3.2).
5. Insert initial `generation_variants` row (`is_primary=1`) and, when `placement` is given, the `shot_generation_items` row via the shot placement code path (renormalization included) with its `shot.generation_placed` event.
6. Write the single `generation.record_completion` receipt (result = `GenerationReadModel` incl. variant + placement).

The event `generation.created` is the atomicity record: a crash before commit rolls everything back; a crash after commit is replayed via the receipt. The old Reigh split path (edge `createGenerationFromTask` vs DB trigger — contradiction #8 in the README) is gone: this is the only generation-creation path from task completion.

---

## 6. SDK service surface + CLI mounts

### 6.1 `GenerationsService` (`astrid/sdk/generations.py`)

Copy the `ShotsService` skeleton (`astrid/sdk/shots.py`): no SQL, no writer of its own, delegates to `GenerationRepository`/`ShotRepository`, every mutation returns one `DomainResult` five-key envelope with `receipt` + `idempotency_key`, errors via `map_error`. Deterministic ids: derive `generation_id` from `(generation.create, project_id, idempotency_key)` and variant/placement ids from `(command_kind, aggregate scope, key, ordinal)` via `derive_stable_id` (`sdk/contracts.py:310`) so retries replay. Methods (one per CLI verb):

`create(project, type, *, name, params, based_on_generation_id, parent_generation_id, child_order, task_id, idempotency_key=None)`, `list(project, *, type=None, starred_only=False, deleted=False)`, `show(project, generation_id)`, `update(project, generation_id, *, name, params, type)`, `star`/`unstar(project, generation_id)`, `delete(project, generation_id)`, `add_variant(project, generation_id, media_id, *, variant_type, name, params, is_primary, idempotency_key=None)`, `update_variant(project, generation_id, variant_id, *, name, params, starred, viewed_at)`, `remove_variant(project, generation_id, variant_id)`, `set_primary(project, generation_id, variant_id)`, `place(project, shot_id, generation_id, *, timeline_frame=None, metadata=None, idempotency_key=None)`, `unplace(project, shot_id, generation_id)`, `position(project, shot_id, generation_id, *, timeline_frame)`.

Wire-up: `astrid/sdk/client.py` gets a `generations` property (→ `self._app.generations_service`), the import block adds `from astrid.sdk.generations import GenerationsService`, and the standard application composition (`astrid/application/...`, where `projects_service`/`shots_service` are constructed) adds `generations_service` + registers `GenerationRepository` into the writer-owning composition. `runs close`-style SDK-only facades (doc 14: "a public `RunsService.create` facade is needed") are out of scope here but the composition note stands.

### 6.2 CLI

- New nested mount `media generations` (family key `generations`, declared in `schema-pack.yaml` `cli_mounts`) — mirror `media references` (`astrid/packs/references/cli.py`): verbs `list/create/show/update/star/unstar/delete/add-variant/remove-variant/set-primary/variants?` — one verb = one SDK call, `--json` envelope, exit codes 0/1/2, `_add_idempotency_key`/`_add_project_arg` helpers copied from the shots CLI.
- `timelines shots` gains `place`, `unplace`, `position` (placement verbs) delegating to the same SDK service methods.

### 6.3 Bridge mounts

`schema-pack.yaml` `bridge_mounts` stays `[]` for the shots pack: the frozen timeline bridge routes are untouched (doc 09), and the `ReighContentBridgeAdapter` routes (projects/shots/generations/variants/media) are a separate phase-1 artifact that consumes these repositories. The bridge DTOs will map 1:1 to the read models above.

---

## 7. Import/replay notes (future phase, design guardrails)

- Receipt keys: `reigh-import:v1:generation:{source_uuid}`, `...:variant:{source_uuid}`, `...:placement:{source_uuid}` (doc 14 §4; v10 pattern `v10-migrate:{family}:{stable-id}` — doc 11).
- Deterministic ids: map source UUID → ULID via the v10 deterministic derivation (`derive_stable_id`/`derive_ulid`), preserving the mapping for FK remapping (`based_on`, `parent_generation_id`, `task_id`, `shot_id`, `media_id`).
- Preserve original timestamps via `created_at`/`updated_at` overrides (kernel commands accept them; generated stamps excluded from request hashes) and keep the raw source row in `params_json`/metadata as an audit artifact (doc 13 §5.4).
- Media: bytes are hashed on import; `location`/`thumbnail_url` strings are NOT imported (they are Supabase URLs); unimportable/expired URLs are cataloged in the export manifest (doc 15 Q4: referenced objects only).
- Import order (doc 14 §4): projects → media → tasks/runs/attempts → generations/variants → placements → timelines/references. Never import an `In Progress` task as a live lease (doc 15 Q2); deleted/terminal-only semantics map to `deleted_at`/terminal task statuses.
- Export is SELECT-only from live prod (doc 07, not repo migrations) — ground truth per README contradiction #1.

---

## 8. Parity — represented vs deliberately dropped

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
| `thumbnail_url` | ✗ | derived from primary variant's media on read |
| `name` | ✓ `name` (nullable) | |
| `based_on` uuid | ✓ `based_on_generation_id` | SET NULL, same-project + `<> id` CHECK |
| `copied_from_share` | ✗ **dropped** | sharing cut (doc 15 Q5) |
| `shot_data` jsonb | ✗ **dropped** | trigger-maintained denormalization; `shot_generation_items` replaces it (read-side join) |
| `parent_generation_id` / `child_order` / `is_child` | `parent_generation_id` + `child_order` ✓; `is_child` ✗ derived (`parent_generation_id IS NOT NULL`) | |
| `children` jsonb | ✗ **dropped** | derived by query (avoid trigger-sync cache) |
| `primary_variant_id` | ✗ **dropped** | derived via `generation_one_primary` partial unique index; no trigger-synced pointer (SD1) |
| `pair_shot_generation_id` | ✗ **dropped** | final-video/pair semantics — Q2 |
| `storage_mode`, `local_handle_id`, `local_file_name/size/mime` | ✗ **dropped** | pending-materialization machinery; local media import materializes bytes (doc 15) |

### 8.2 `generation_variants` (live, doc 07 §3.1)

| Reigh column | Pack v2 | Notes |
|---|---|---|
| `id` | ✓ ULID | |
| `generation_id` | ✓ FK CASCADE | |
| `location` | ✗ → `media_id` FK RESTRICT | exact bytes; one row per variant |
| `thumbnail_url` | ✗ | media-derived |
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

| Reigh column | Pack v2 | Notes |
|---|---|---|
| `id` | ✓ ULID | |
| `shot_id` | ✓ FK CASCADE | |
| `generation_id` | ✓ FK CASCADE | + `UNIQUE (shot_id, generation_id)` (one placement per shot) |
| `created_at` / `updated_at` | ✓ | |
| `timeline_frame` int NULL | ✓ nullable | unpositioned = NULL, sorted last |
| `metadata` jsonb | ✓ `metadata_json` | segment overrides |
| `position` int | ✗ **dropped** | legacy; superseded by `timeline_frame` + `sort_key` (normalized 0..n-1); computed-position view (`shot_generations_with_computed_position`) becomes the sort_key order |
| shot `position`/`aspect_ratio`/`settings` (shots table) | existing shots pack (`sort_key`, `metadata_json`) | mapped in doc 13 §3; no pack-v2 change |

### 8.4 Cut wholesale (binding, doc 15 + doc 14 §4)

`shared_generations`, credits/`credits_ledger`, users/auth/RLS/PATs, referrals, `attempts`/`shot_slots`/`slot_first_*` (archived as read-only JSONL export — never mapped to kernel tables), `task_types` registry, `shot_data_audit`, `resources`, `external_api_keys`, `local_media_handles`, `shot_final_videos` view (replaced by the composition read in §4.5), timeline-agent sessions (Q6).

---

## 9. Conventions checklist (acceptance gate for the implementer)

- [ ] ULID lowercase Crockford PKs; `uuid4().hex` event/txn ids; stream id `<aggregate>:generation.generation`; `schema_migrations (pack='shots', version=2, name='generations')`.
- [ ] ISO-8601-UTC TEXT timestamps; `CHECK (json_valid(...))` on all `*_json`; booleans `CHECK IN (0,1)`; canonical JSON bounds (1 MiB in / 4 MiB out).
- [ ] `FORBIDDEN_TABLES` untouched; no new forbidden names; 23-table composition expectations updated.
- [ ] One command = one `BEGIN IMMEDIATE` callback = receipt gate → validation → writes → event(s) → heads → receipt; identical retry replays stored receipt; changed bytes under same key → `ReceiptMismatchError`.
- [ ] Registry vocabulary declared in `schema-pack.yaml` and `STREAM_AGGREGATE_RULES` before any mutation; event kind pack == stream type pack; subject = stream aggregate.
- [ ] No triggers, no URL/denormalization columns, no soft-delete beyond `deleted_at`, no shims or aliases; every read through `read_only_connection()`.

---

## Open questions

1. **Pack identity** — doc 14 says "shots/content pack": keep pack id `shots` with migration v2 (this spec) or split a new `content` pack (`depends_on: [core >= 1, shots >= 1]`) owning the three tables? Registry supports either; v2-in-shots is the smaller change and matches the phase-1 doc title.
2. **`pair_shot_generation_id`** — dropped here (still-image pair for final-video rendering). If the local gallery needs pair/final-video semantics, add a nullable self-referencing FK to `shot_generation_items` (or a `generations.pair_shot_generation_id` FK) in a forward-only v3 with the pair-placement guard in the repository.
3. **`tasks` jsonb → single `task_id`** — Reigh may record multiple task ids per generation; confirm single-FK is sufficient for the completion path, else model a `generation_tasks` join table (would be a 4th table in this migration).
4. **Closed vocabularies** — freeze `type` and `variant_type` into DDL CHECKs in a later migration once the live distinct-value sets are exported (the exporter should emit `SELECT DISTINCT type FROM generations` and variants for this).
5. **Deletion semantics** — soft-delete (`deleted_at`) chosen; confirm no product path needs hard delete + byte GC (kernel has no deletion precedent; `media` rows are RESTRICT-pinned by variants).
6. **Placement ordering** — does the local v1 need a whole-shot permutation reorder for placements (like `shot.reordered`) in addition to `timeline_frame` positioning, or is position-based ordering sufficient for the gallery/timeline UX?
7. **Completion atomicity** — `generation.record_completion` as one composite receipt (this spec) vs two commands (task-complete then generation-create) with a reconciliation sweep; the composite is required by doc 14's atomicity risk — confirm before build.
8. **Variant starring** — `generation_variants.starred` exists but no standalone star command is specced (covered by `update_variant`); confirm the gallery doesn't need a dedicated variant-star verb.
