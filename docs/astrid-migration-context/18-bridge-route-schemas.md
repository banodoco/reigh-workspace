# 18 — Bridge Route Schemas: Task, Queue, Attempt, Media, and Content Reads

**Context doc 18 — normative HTTP schemas for the new bridge routes (tasks, queue/claim, attempts, media, content reads), phase-1 design artifact for the Reigh→Astrid migration.**
Researched 2026-08-21. Sources: `docs/astrid-migration-context/09-astrid-bridge.md` (frozen wire contract), `Astrid/docs/contracts/astrid-bridge-v10.md` (normative contract), `Astrid/astrid/core/integrations/reigh/local_bridge_server.py` + `bridge_service.py` + `astrid/packs/timeline/bridge.py` (implemented server), `reigh-app/src/tools/video-editor/data/bridgeContract.ts` (client zod artifact), `docs/astrid-migration-context/14-codex-migration-design.md` §2/§3 (the contract being spec'd), `15-owner-decisions-defaults.md` (binding scope), `04`/`05` (kernel schema + SDK), `10` (create-task resolvers), `12` (Reigh lease/retry), `06` (frontend read surfaces). Docs 16/17 were not yet written at research time; this doc is written to be compatible with the doc-14 §4 content-pack DDL and the doc-13 §7.3 bridge-first strategy. **DESIGN SPEC — read-only, no implementation.**

## 1. Summary and key facts

This doc extends the frozen bridge (`astrid serve`, one SQLite store, one writer queue) **additively**: every existing route (§1 of `astrid-bridge-v10.md`) is unchanged, and every new route below follows the same wire conventions exactly — split-path route grammar, `{"error","detail"}` error envelope with status extras, per-field `400 invalid_*` codes, `422 schema_incompatible` with JSON-pointer `issues[]`, `409` conflicts carrying current-state data, receipt secrecy (no `txn_id`/`request_hash`/`idempotency_key`/sequences ever), `Cache-Control: no-store` JSON, localhost binding + exact-origin CORS, ISO-8601-UTC `Z` timestamps, 26-char lowercase Crockford ULID aggregate ids, `^[a-z0-9]+(?:-[a-z0-9]+)*$` project slugs. New routes fall into four adapters per doc 14 §1: **ReighTaskBridgeAdapter** (admission + reads), **ExecutorBridgeAdapter** (claim/start/heartbeat/outputs/complete/fail), **ReighContentBridgeAdapter** (projects/shots/gallery), and **media serving** (general `…/media/{media_id}/content`).

Key facts:

- **Admission** (`POST /projects/:slug/tasks`) ports the 13-family resolver registry from `reigh-app/supabase/functions/create-task/resolvers/registry.ts`; request body `{family, input, materialized_inputs?}`; **`Idempotency-Key` header required**; `201` first insert, `200` idempotent replay, `409 idempotency_mismatch` on key reuse with different bytes (doc 14 §2). Batches commit atomically as a `run` (doc 14 §2; `runs.create` fan-out via a `[BUILD]` `RunsService.create` facade).
- **Kernel mapping** (doc 14 §2): `tasks.capability` = normalized `reigh.<task_type>` (e.g. `image-upscale` → `reigh.image_upscale`); `spec_json` = `{schema_version:1, family, source_task_type, params, output_policy}`; `input_manifest_json` = `[{role, media_id}]` (media resolved at admission); `priority`, `available_at=now`, `max_attempts=3`, `status=queued|blocked`; hard `task_dependencies` edges.
- **Fenced executor protocol** (doc 14 §3): `POST /queue/claim` (global, capability allowlist), then per-attempt `start` → `heartbeat` → `outputs` (attempt/lease-scoped quarantine) → `complete`|`fail`. Every state-changing request **except heartbeat** carries an `Idempotency-Key`; every attempt mutation carries `lease_id` + latest `status_version`; kernel fence violations map to typed `409` codes with a current-state `attempt` extra. Leases default 300 s (`DEFAULT_LEASE_SECONDS`, `astrid/core/repositories/tasks.py:118`); heartbeat every 30 s increments `status_version` and extends the lease (doc 14 §3).
- **Completion is atomic** (doc 14 §3): one writer transaction verifies/prepares staged bytes, completes the task, inserts `task_outputs` + `media` + `media_locations` + relations, creates/updates the generation projection, applies shot placement and optional timeline registry entry. It replaces Reigh's multi-step `complete_task` sequence; credits/billing are **cut** (doc 15 Q5).
- **Media content** (`GET|HEAD /projects/:slug/media/:media_id/content`) reuses the frozen asset byte-serving semantics (§9 of the contract: 200/206/304/416/400, single-range grammar, stat-derived `ETag`/`Last-Modified`, `Cache-Control: private, no-cache`, SHA-256 verification before streaming) with direct ULID media addressing instead of registry keys.
- **Content reads** mirror the app's PostgREST surface (doc 06 §3.1–§3.3, §8.B): project read with `settings`, shots ordered by position (`sort_key`), generations/variants gallery reads with primary-variant joins and head-counts, over the doc-14 §4 content-pack tables (`generations`, `generation_variants`, `shot_generation_items`).
- **Polling only** (doc 15 Q7): claim 1–2 s while work is active, 5–10 s idle; heartbeat 30 s; timeline/document 30 s; discovery 3 s. No SSE/websocket.
- **Auth posture unchanged**: localhost binding + exact-origin CORS allowlist; no tokens, no RLS, no per-user tenancy (doc 15). `executor_id` is **audit attribution** (`events.actor_kind='executor'`), never a credential; workers are same-host local processes (doc 15 Q3).
- **Lease expiry is a serve-side maintenance loop, not a route** (doc 14 §3): repeatedly calls `TaskRepository.expire_overdue` on the writer queue; requeues within `max_attempts`, terminally fails exhausted work.
- **Reserved routes**: `POST /projects/:slug/timelines/:ref/copy` (frozen m6 reservation, contract §11 — stays unregistered); `POST /tasks/:task_id/cancel` and `GET /queue/summary` are declared-but-not-normative follow-ups (doc 14 §4 lists cancellation in the app workstream; doc 14 §3 lists a global queue summary as `[BUILD]`).

## 2. Common behavior (extends contract §2)

### 2.1 Base, grammar, and method surface

- Base path is unchanged: `/api/astrid` via the Vite dev proxy → `http://127.0.0.1:17333` (`ASTRID_BRIDGE_PORT`, default 17333).
- Routes are parsed by splitting the decoded path on `/` and matching exact segment counts (pattern in `local_bridge_server.py do_GET/do_POST`, lines ~776–935). The extension adds new part-count patterns to the same dispatcher; any unknown path keeps returning `404 {"error":"not_found"}`.
- Path notation in this doc uses the frozen contract's `:param` style (`/projects/:slug/tasks`); doc 14's `{slug}` spelling denotes the same segment. `:task_id` and `:media_id` are **26-char lowercase Crockford ULIDs** (kernel aggregate ids, `astrid/core/ids.py`); `:attempt_no` is a positive integer (`execution_attempts.attempt_no`, `CHECK > 0`).
- New methods: the executor and admission routes are `POST`; content/media reads are `GET` (+ `HEAD` for media content). `OPTIONS` any path stays `204` (CORS).

### 2.2 JSON envelope, caching, and body size

- Every JSON response (success and error): `Content-Type: application/json`, `Cache-Control: no-store`, UTF-8 (unchanged, contract §2.1/§2.4). Byte routes (media content): `Cache-Control: private, no-cache`.
- JSON request bodies must be JSON objects; parse failure or non-object body → `400 invalid_body` (existing `_read_request_body` semantics).
- **New: body-size guard before read.** JSON routes reject a `Content-Length` above the kernel canonical input bound (1 MiB; `astrid/core/receipts/canonical.py`) with **`413 payload_too_large`** and `"limit_bytes"` extra (frozen contract has no 413; this is a deliberate addition for the task/queue routes — doc 14 §4 "request-size limits"). The `/outputs` staging route has its own larger limits (§9).
- Canonical-JSON bounds apply to every payload that reaches a repository command: 1 MiB in / 4 MiB out / depth 100; a payload that cannot canonicalize → `422 schema_incompatible` with `issues[]` (existing `_validate_save_payload_schema` pattern).

### 2.3 Error envelope and vocabulary (frozen ∪ new)

Frozen codes (unchanged; `bridge_service.py` error classes): `400 invalid_body | invalid_config | invalid_registry | invalid_expected_version | invalid_project | invalid_timeline`; `404 project_not_found | timeline_not_found | asset_not_found | asset_not_local`; `409 timeline_version_conflict` (+`config_version`); `422 schema_incompatible` (+`issues[]`); `500 internal`; `404 not_found` (unknown route).

New codes this spec adds (same envelope shape, status-specific extras):

| Status | Code | Extra fields | Raised when |
|---|---|---|---|
| 400 | `invalid_family` | — | `family` missing / not a string / not in the code-declared allowlist |
| 400 | `invalid_input` | — | `input` missing / not an object |
| 400 | `invalid_materialized_inputs` | — | `materialized_inputs` present but not an array of well-formed entries |
| 400 | `invalid_executor` | — | `executor_id` missing / empty on claim |
| 400 | `invalid_capabilities` | — | `capabilities` missing / empty / not a string array |
| 400 | `invalid_lease_seconds` | — | `lease_seconds` present but not a positive integer (boolean rejected, mirroring `invalid_expected_version`) |
| 400 | `invalid_attempt` | — | `:attempt_no` not a positive integer, or `attempt_id` mismatches the route's task+attempt pairing shape |
| 400 | `invalid_lease_id` | — | `lease_id` missing / not a string on a fenced route |
| 400 | `invalid_status_version` | — | `status_version` missing / not an integer (boolean rejected) |
| 400 | `invalid_outputs` | — | `outputs` missing / not an array on complete |
| 400 | `invalid_staged_outputs` | — | a `staging_key` references no quarantined file (complete-side) |
| 400 | `invalid_error` | — | `error` missing / not an object / `message` > 4000 chars (`MAX_ERROR_PAYLOAD_CHARS`) on fail |
| 404 | `task_not_found` | — | no `tasks` row for `:task_id` |
| 404 | `attempt_not_found` | — | no `execution_attempts` row for the route's task+attempt_no (or the attempt belongs to another task) |
| 404 | `media_not_found` | — | no `media` row for `:media_id` in the route project, or no verified local bytes |
| 404 | `media_not_local` | — | the media row's only location is `remote`/HTTP (never served locally) |
| 409 | `idempotency_mismatch` | — | the `Idempotency-Key` was already committed under a different canonical request hash (`ReceiptMismatchError`, kernel `command_receipts.request_hash`) |
| 409 | `stale_status_version` | `"attempt": {…current…}` | attempt's stored `status_version` ≠ caller's `status_version` |
| 409 | `lease_mismatch` | `"attempt": {…}` | caller's `lease_id` ≠ attempt's `lease_id` (caller does not own the attempt) |
| 409 | `attempt_not_live` | `"attempt": {…}` | attempt not in `claimed`/`running` (already terminal/expired) |
| 409 | `lease_expired` | `"attempt": {…}` | attempt live but `lease_expires_at` passed (kernel `_iso_gt` check) |
| 409 | `task_terminal` | `"attempt": {…}` | task already in a terminal status; fence command rejected before mutation |
| 409 | `attempt_budget_exhausted` | `"attempt": {…}` | `max_attempts` reached; no requeue possible |
| 413 | `payload_too_large` | `"limit_bytes": <int>` | request body exceeds the route's byte limit before it is read |
| 422 | `unsupported_family` | `"issues": [{"pointer": "/family", "code": "unsupported_family", "message": …}]` | family not in the allowlist (distinct from a malformed request) |

Fence `409` extras: every fence code adds `"attempt": {"attempt_id", "attempt_no", "status", "status_version", "lease_id", "lease_expires_at", "heartbeat_counter", "last_heartbeat_at"}` (the **current** attempt read model) so the client can resync/retry without a second round trip — the same "re-read current head on conflict" pattern as `timeline_version_conflict`'s `config_version` (contract §6.2). `attempt_budget_exhausted` additionally carries `"max_attempts": <int>`.

### 2.4 Idempotency (new header semantics)

- **Header:** `Idempotency-Key: <key>` on every state-changing request except heartbeat (doc 14 §3). Key grammar: printable ASCII, 1–200 chars; the server does not generate keys for these routes (unlike the hidden save key on `…/save`, which stays derived and unchanged).
- **Commit semantics:** the key is passed into the repository command's caller-key slot, so the commit writes one `command_receipts` row under `(project_id, key)` with `request_hash` = SHA-256 of the canonical `{command_kind, request-minus-generated}` (`astrid/core/receipts/canonical.py`). Replay with the same key returns the stored result — `200` — with zero new rows.
- **Mismatch:** same key, different canonical request bytes → kernel `ReceiptMismatchError` → **`409 idempotency_mismatch`** (doc 14 §2; `command_receipts` PK + request-hash gate, doc 04 §3.5/§4.3).
- **Proposed key namespaces** (caller-chosen; documented for cross-client discipline, not enforced): admission `reigh.admit:{uuid}`, claim `reigh.claim:{uuid}`, attempt `reigh.attempt:{attempt_id}:{verb}:{uuid}`.
- **Receipt secrecy unchanged** (§7): keys, hashes, `txn_id`, sequences, `event_ids_json`, `result_json` never appear in any response or header. Replay responses expose only the frozen DTO shape.
- **Claim special case:** a claim that finds no work returns `204` with **no receipt**; a replayed key therefore re-queries the queue. A claim that won a task is receipted under the **claimed task's project**, so the cross-project claim service (doc 14 §3 `[BUILD]`) must scope receipt lookups by resolved project. [INFERENCE — receipt-on-no-work behavior follows from kernel `claim` returning `None` without a receipt row; verify in implementation.]

### 2.5 CORS and auth posture

- CORS allowlist unchanged (exact-origin; `localhost:2222/3000/5173` + `127.0.0.1:2222/3000/5173`; `local_bridge_server.py:271-278`) with **one addition**: `Access-Control-Allow-Headers` gains `Idempotency-Key` → `"Content-Type, Range, If-None-Match, If-Modified-Since, Idempotency-Key"` so the browser editor can POST tasks. `Access-Control-Expose-Headers` unchanged (`Accept-Ranges, Content-Length, Content-Range, Content-Type, ETag, Last-Modified`); methods stay `GET, HEAD, POST, OPTIONS`; `Max-Age 86400`; `Vary: Origin`.
- **Auth posture:** unchanged — `127.0.0.1` bind (default), exact-origin CORS, no tokens/TLS/sessions (doc 15 Q3/Q5; doc 09 §3). Executor clients are **not browsers**: they do not need CORS and must send plain HTTP to the loopback address; `executor_id` is stamped into `execution_attempts.executor_id` and `events.actor_kind='executor'` as **audit attribution**, never an auth check (doc 14 §1 "executor_id audit attribution").
- Workers must never open SQLite or repositories directly; the bridge is their only surface (doc 14 §3, doc 15 Q3).

### 2.6 Addressing, IDs, timestamps

- `:slug` grammar `^[a-z0-9]+(?:-[a-z0-9]+)*$` → `400 invalid_project`; unknown project → `404 project_not_found` (never an empty authority view).
- `:task_id`/`:media_id`/`:attempt_id` are lowercase Crockford ULIDs; a malformed id is `400 invalid_task`/`invalid_media_id`-style per-route (grammar `_ULID_RE` in `packs/timeline/bridge.py:51`). `:attempt_no` is a positive integer.
- All timestamps on the wire are ISO-8601 UTC with trailing `Z` (`utc_now_iso`, `astrid/core/util/time.py`), e.g. `2026-08-20T00:00:00.000000+00:00` → normalize to `Z`.
- Status vocabularies on the wire use the **kernel** lowercase forms: `tasks.status ∈ queued|blocked|running|succeeded|failed|cancelled`; `execution_attempts.status ∈ claimed|running|succeeded|failed|cancelled|expired` (doc 04 §3.7/§3.9). Reigh's `Queued|In Progress|Complete|Failed|Cancelled` maps value-for-value (doc 13 §4.3).

### 2.7 Polling cadence (client contract)

| Surface | Cadence | Source |
|---|---|---|
| `POST /queue/claim` | 1–2 s while work is active; 5–10 s idle backoff | doc 15 Q7; doc 14 §3 |
| `POST …/heartbeat` | every 30 s (lease 300 s → ≥2 heartbeats per lease) | doc 14 §3; doc 04 §3.9 |
| Timeline/document + task reads | 30 s | doc 09 §3 |
| Discovery (health/projects) | 3 s while down/empty | doc 09 §3 |

## 3. Route index

| # | Route | Methods | Purpose | Success | Key errors |
|---|---|---|---|---|---|
| R1 | `/projects/:slug/tasks` | `POST` | task admission (13-family resolvers) | `201` new, `200` replay | 400 family/input, 404 project, 409 idempotency_mismatch, 413 size |
| R2 | `/projects/:slug/tasks` | `GET` | task reads (list, status filter, cursor) | `200` | 400 invalid_project, 404 project_not_found |
| R3 | `/queue/claim` | `POST` | fenced global claim by capability | `200` claimed, `204` no work | 400 executor/capabilities/lease, 409 idempotency_mismatch |
| R4 | `/tasks/:task_id/attempts/:attempt_no/start` | `POST` | claimed→running; allocate staging | `200` | 404 task/attempt, 409 fences |
| R5 | `/tasks/:task_id/attempts/:attempt_no/heartbeat` | `POST` | extend lease (non-event, no key) | `200` | 404, 409 fences |
| R6 | `/tasks/:task_id/attempts/:attempt_no/outputs` | `POST` | stream files into attempt quarantine | `200` | 400 fence/outputs, 413 size, 404, 409 fences |
| R7 | `/tasks/:task_id/attempts/:attempt_no/complete` | `POST` | atomic completion (outputs→media→generation→placement) | `200` | 400 outputs, 404, 409 fences, 422 schema |
| R8 | `/tasks/:task_id/attempts/:attempt_no/fail` | `POST` | fail / requeue within budget | `200` | 400 error, 404, 409 fences |
| R9 | `/projects/:slug/media/:media_id/content` | `GET`, `HEAD` | media bytes, Range/ETag | `200/206/304/416` | 400 media, 404 media_not_found/media_not_local, 400 Range |
| R10 | `/projects/:slug` | `GET` | project read (settings) | `200` | 400/404 project |
| R11 | `/projects/:slug/shots`, `/projects/:slug/shots/:shot_id` | `GET` | shots list / shot with items | `200` | 400/404 project, 404 shot_not_found |
| R12 | `/projects/:slug/generations`, `…/:generation_id`, `…/:generation_id/variants`, `/projects/:slug/variants` | `GET` | gallery reads | `200` | 400/404 project, 404 generation_not_found |
| — | maintenance loop (lease expiry) | — | serve-side sweep, **not a route** | — | — |

## 4. R1 — Task admission: `POST /projects/:slug/tasks`

Adapter: `ReighTaskBridgeAdapter` → ported family resolver (registry ported from `reigh-app/supabase/functions/create-task/resolvers/registry.ts`, doc 10 §3) → `TasksService.create` / `[BUILD] RunsService.create` (doc 14 §2).

### 4.1 Request

Header: **`Idempotency-Key` (required)**. Body (JSON object, ≤ 1 MiB):

| Field | Type | Req | Notes |
|---|---|---|---|
| `family` | string | ✔ | one of the 13 allowlisted families (table §4.3) |
| `input` | object (loose) | ✔ | the existing per-family payload; canonicalizable (≤1 MiB, depth ≤100); unknown keys preserved |
| `materialized_inputs` | array | – | `[{media_id \| generation_id, kind: 'file'\|'remote', target, url?}]`; server resolves `generation_id`→`media_id` at admission; unknown media/generation → `422 schema_incompatible` issue at the entry pointer |
| `priority` | integer | – | maps to `tasks.priority` (default 0; higher claimed first) |
| `available_at` | string | – | ISO-8601 UTC gate (default `now`); claim gate |
| `dependant_on` | array<string> | – | Reigh-compat dependency ids → hard `task_dependencies` edges (same project, acyclic — kernel validates) |

Example (doc 14 §2):

```json
{
  "family": "image_generation",
  "input": { "model": "optimised-t2i", "prompt": "…", "resolution": "832x480", "seed": 123, "steps": 12 },
  "materialized_inputs": [ { "media_id": "<ulid>", "kind": "file", "target": "style_reference_image" } ]
}
```

### 4.2 Response

- **`201 Created`** (first commit) and **`200 OK`** (idempotent replay) share the body; replay adds `"deduplicated": true` (mirrors Reigh create-task's `deduplicated` flag, doc 10 §2.1). Single-task body:

```json
{
  "task_id": "<26-char ULID>",
  "project_id": "<26-char ULID>",
  "capability": "reigh.wan_2_2_t2i",
  "status": "queued",
  "run_id": null,
  "run_ordinal": null,
  "deduplicated": false
}
```

- Batch families (image_generation ×N, z_image_turbo_i2i, magic_edit, klein_edit) commit **atomically as one `run`** with ordered children (doc 14 §2):

```json
{
  "run_id": "<26-char ULID>",
  "task_ids": ["<ulid>", "<ulid>", "…"],
  "project_id": "<26-char ULID>",
  "status": "queued",
  "deduplicated": false
}
```

- `task_id`s are ordered by `run_ordinal`; the run's `tasks` all commit or none do (one `BEGIN IMMEDIATE`, one receipt; doc 04 §2.4, doc 14 §2 "atomic fan-out").
- Receipt secrecy: no `idempotency_key`, `txn_id`, hashes, or sequences in the body.

### 4.3 Family → capability allowlist (normalized per doc 14 §2, sources doc 10 §3.3)

| family | Reigh task_type(s) | capability (admitted) | Tasks/request |
|---|---|---|---|
| `image_generation` | `wan_2_2_t2i`, `qwen_image`, `qwen_image_style`, `qwen_image_2512`, `z_image_turbo` | `reigh.<task_type>` | `prompts × imagesPerPrompt` (≤16) — batch |
| `image_upscale` | `image-upscale` | `reigh.image_upscale` | 1 |
| `individual_travel_segment` | `individual_travel_segment` | `reigh.individual_travel_segment` | 1 |
| `join_clips` | `join_clips_orchestrator` | `reigh.join_clips_orchestrator` | 1 |
| `video_enhance` | `video_enhance` | `reigh.video_enhance` | 1 |
| `z_image_turbo_i2i` | `z_image_turbo_i2i` | `reigh.z_image_turbo_i2i` | `numImages` — batch |
| `magic_edit` | `qwen_image_edit` | `reigh.qwen_image_edit` | `numImages` (1–16) — batch |
| `masked_edit` | `image_inpaint` | `reigh.image_inpaint` | 1 |
| `travel_between_images` | `travel_between_images` | `reigh.travel_between_images` | 1 (orchestrator) |
| `crossfade_join` | `travel_stitch` | `reigh.travel_stitch` | 1 |
| `edit_video_orchestrator` | `edit_video_orchestrator` | `reigh.edit_video_orchestrator` | 1 |
| `character_animate` | `animate_character` | `reigh.animate_character` | 1 |
| `klein_edit` | `flux_klein_edit` | `reigh.flux_klein_edit` | `numImages` (1–4) — batch |

- Normalization rule: `capability = "reigh." + task_type` verbatim (hyphens preserved, e.g. `image-upscale` → `reigh.image_upscale`, doc 14 §2); original `task_type` string retained in `spec_json.source_task_type`.
- **No unknown-family passthrough.** The old `task_types`-row lookup and `createWorkerPassthroughResolver` (doc 10 §2.1/§3.3) are replaced by this code-declared allowlist (doc 14 §2). Worker-created child tasks are admitted through the same route with an explicit `family` (doc 14 keeps orchestrator contracts in specs; structural `runs.create` fan-out is the later redesign).

### 4.4 Kernel landing shape (doc 14 §2)

`spec_json` = `{"schema_version": 1, "family": "<family>", "source_task_type": "<task_type>", "params": {…resolved worker payload…}, "output_policy": {"create_generation": true, "shot_id": …, "based_on_generation_id": …, "timeline_placement": {…}}}` — the `output_policy` object comes from the resolver's lineage fields (`shot_id`, `based_on`, `create_as_generation`, `timeline_placement`, `placement_intent`; doc 10 §3.3 lineage). `spec_hash` = SHA-256 of canonical `{spec, input_manifest}` (kernel `compute_spec_hash`). `input_manifest_json` = `[{"role": "<target>", "media_id": "<ulid>"}]`. Status = `queued`, or `blocked` when any hard dependency is present (kernel `_initial_status_from_dependencies`).

### 4.5 Errors

`400 invalid_body/invalid_family/invalid_input/invalid_materialized_inputs`; `400 invalid_project` (slug grammar); `404 project_not_found`; `409 idempotency_mismatch`; `413 payload_too_large`; `422 schema_incompatible` (non-canonicalizable payload, unknown media reference) and `422 unsupported_family`; `500 internal` (defensive only).

## 5. R2 — Task reads: `GET /projects/:slug/tasks`

Adapter: `ReighTaskBridgeAdapter` → `TasksService.list` + `show` (read-only, transaction-free reads on the writer's read-only connection — no writer contention, doc 04 §2.4).

Query: `?status=queued|blocked|running|succeeded|failed|cancelled` (repeatable), `?limit=1..200` (default 50), `?cursor=<opaque>` (pagination cursor; see §12). `200`:

```json
{
  "tasks": [
    {
      "task_id": "<ulid>", "project_id": "<ulid>", "capability": "reigh.wan_2_2_t2i",
      "status": "queued", "priority": 0, "available_at": "…Z", "created_at": "…Z",
      "max_attempts": 3, "run_id": null, "run_ordinal": null,
      "spec": { "schema_version": 1, "family": "image_generation", "source_task_type": "wan_2_2_t2i", "params": {…}, "output_policy": {…} },
      "input_manifest": [ {"role": "style_reference_image", "media_id": "<ulid>"} ],
      "winning_attempt_id": null,
      "current_attempt": null
    }
  ],
  "next_cursor": "<opaque|null>"
}
```

- `current_attempt` is the live `execution_attempts` read model (`attempt_id, attempt_no, status, status_version, lease_id, lease_expires_at, heartbeat_counter, last_heartbeat_at`) when the task is `running`, else `null` — gives the app's 3–5 s pending-task polls (doc 06 §3.4) the fence state without a second call.
- `400 invalid_project`; `404 project_not_found`. Errors never include receipts/sequences.

## 6. R3 — Fenced claim: `POST /queue/claim`

Adapter: `ExecutorBridgeAdapter` → `[BUILD]` capability-aware cross-project claim (doc 14 §3: kernel `TaskRepository.claim` is currently **project-scoped** and cannot filter by capability; the claim service adds the allowlist and iterates claimable projects in deterministic order).

Header: **`Idempotency-Key` (required).** Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `executor_id` | string | ✔ | executor self-id; audit attribute (`execution_attempts.executor_id`, `events.actor_kind='executor'`), not a credential |
| `capabilities` | array<string> | ✔ | non-empty allowlist of `reigh.*` capability ids the executor can run; only matching tasks are claimable |
| `lease_seconds` | integer | – | default 300 (`DEFAULT_LEASE_SECONDS`), positive; requested lease for the claimed attempt |
| `max_task_wait_minutes` | integer | – | optional FIFO/starvation fallback window (Reigh parity, doc 12 §2.1) [INFERENCE: doc 14 does not carry this field; Reigh claim's 5-min starvation is the precedent] |

### 6.1 Response — `200 OK` (claim won)

```json
{
  "task": {
    "task_id": "<ulid>", "project_id": "<ulid>", "capability": "reigh.wan_2_2_t2i",
    "status": "running", "priority": 0, "available_at": "…Z", "created_at": "…Z",
    "max_attempts": 3, "run_id": null, "run_ordinal": null,
    "spec": { "schema_version": 1, "family": "image_generation", "source_task_type": "wan_2_2_t2i", "params": {…}, "output_policy": {…} },
    "input_manifest": [ {"role": "style_reference_image", "media_id": "<ulid>"} ]
  },
  "attempt": {
    "attempt_id": "<ulid>", "attempt_no": 1, "status": "claimed", "status_version": 1,
    "lease_id": "<ulid>", "lease_expires_at": "…Z", "heartbeat_counter": 0,
    "last_heartbeat_at": null
  },
  "media": { "style_reference_image": { "media_id": "<ulid>", "url": "http://127.0.0.1:17333/api/astrid/projects/<slug>/media/<ulid>/content" } }
}
```

- Every doc-14 §3 field is present: `project_id`, `attempt_id`, `attempt_no`, `lease_id`, `lease_expires_at`, `status_version`, plus the full task spec and input manifest. Kernel claim returns the identical `{task, attempt}` pair (`TaskClaimReadModel`, `astrid/core/repositories/tasks.py:539-560`).
- `media` renders input-media bridge URLs (or local paths) for the existing worker handlers (doc 14 §2: "The claim adapter may render those into bridge URLs or local paths expected by existing handlers"). External model/LoRA URLs stay URLs in `spec.params`.
- Claim commits: attempt row (`claimed`, version 1, leased), task `queued|blocked → running`, `core.task.claimed` event, both heads, one receipt (kernel `claim`, `tasks.py:1745-1978`).

### 6.2 Response — `204 No Content`

No eligible work (capability ∩ queue empty, `available_at` in future, or hard deps incomplete). Mirror of Reigh claim's 204 (doc 10 §2.1). **No receipt** (§2.4); client backs off to the idle cadence (§2.7).

### 6.3 Errors

`400 invalid_body/invalid_executor/invalid_capabilities/invalid_lease_seconds`; `409 idempotency_mismatch` (replay of a *won* claim returns the stored `{task, attempt}` — never re-claims); `413 payload_too_large`; `500 internal`. Note: a replayed claim key whose original request won must **not** claim again; replay correctness is the lost-ack test doc 14 §3 calls out.

## 7. R4 — Start: `POST /tasks/:task_id/attempts/:attempt_no/start`

Adapter: `ExecutorBridgeAdapter` → `TaskRepository.start` (kernel fence: attempt must belong to the task, be `claimed`, `lease_id` match, exact `status_version`; `tasks.py:1982-2198`), then allocate the attempt's staging quota.

Header: **`Idempotency-Key` (required).** Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `lease_id` | string | ✔ | from the claim response |
| `status_version` | integer | ✔ | latest fence (1 right after claim) |

`200`:

```json
{
  "attempt": {
    "attempt_id": "<ulid>", "attempt_no": 1, "status": "running", "status_version": 2,
    "lease_id": "<ulid>", "lease_expires_at": "…Z", "heartbeat_counter": 0,
    "last_heartbeat_at": null
  },
  "staging": {
    "upload_url": "http://127.0.0.1:17333/api/astrid/tasks/<task_id>/attempts/<attempt_no>/outputs",
    "quota_bytes": 68719476736,
    "max_request_bytes": 2147483648
  }
}
```

- Start transitions `claimed → running` (`core.task.started` event, version +1). The in-process `ExecutionService.execute` handler path is **not** used here: the bridge executor adapter exposes the repository start and returns staging info for the external worker to stream into (doc 14 §3 worker protocol; the local WGP/VibeComfy handlers stay in `reigh-worker`, doc 14 §4 "Keep `TaskRegistry` and the current WGP/VibeComfy handlers initially").
- Staging is attempt/lease-scoped: quarantine root `<projects_root>/.astrid/media/.staging/<txn_id>` (kernel staging layout, doc 04 §5) with the `txn_id` recorded in `progress_json` under the reserved `staging_txn_id` key (`task_executor/service.py:STAGING_TXN_ID_KEY`). **The `txn_id` never appears in the response** (receipt secrecy; the worker only needs `upload_url`).
- Defaults proposed: `quota_bytes` 64 GiB per attempt, `max_request_bytes` 2 GiB per `/outputs` request; env-tunable (`ASTRID_BRIDGE_MAX_STAGING_TOTAL_BYTES`, `ASTRID_BRIDGE_MAX_STAGING_REQUEST_BYTES`). [INFERENCE — no kernel constant exists; Reigh's signed-URL path had 1 h expiry with no size cap (doc 02 §6).]

Errors: `404 task_not_found / attempt_not_found`; `409 stale_status_version / lease_mismatch / attempt_not_live / lease_expired / task_terminal` (each with the current `attempt` extra); `409 idempotency_mismatch`; `400 invalid_lease_id/invalid_status_version`; `413`.

## 8. R5 — Heartbeat: `POST /tasks/:task_id/attempts/:attempt_no/heartbeat`

Adapter: `ExecutorBridgeAdapter` → `TaskRepository.heartbeat` — the kernel's deliberate **non-event, no-receipt** narrow update (doc 04 §3.9, `tasks.py:2204-2353`): exact-predicate `UPDATE` on `(id, task_id, status IN claimed|running, lease_id, status_version)`; `heartbeat_counter +1`, `last_heartbeat_at=now`, `lease_expires_at=now+lease_seconds`, `status_version +1`.

**No `Idempotency-Key`** (doc 14 §3: every state-changing request except heartbeat carries a key; kernel writes no receipt). Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `lease_id` | string | ✔ | |
| `status_version` | integer | ✔ | latest fence; response returns the next version |
| `lease_seconds` | integer | – | default 300; the extension window for this beat |
| `progress` | object | – | optional loose progress object; merged into `progress_json` (bounded, canonicalizable) |

`200`:

```json
{ "attempt": { "attempt_id": "<ulid>", "attempt_no": 1, "status": "running",
  "status_version": 3, "lease_id": "<ulid>", "lease_expires_at": "…Z",
  "heartbeat_counter": 1, "last_heartbeat_at": "…Z" } }
```

- The worker's lease keeper must **serialize heartbeat with complete/fail** so completion cannot submit a stale fence (doc 14 §3: "the worker's lease keeper must serialize heartbeat with complete/fail"); the bridge never retries heartbeats.
- Errors: `404 task_not_found/attempt_not_found`; `409 stale_status_version / lease_mismatch / attempt_not_live / lease_expired / task_terminal`; `400 invalid_lease_id/invalid_status_version`; `413`.

## 9. R6 — Outputs (staged quarantine): `POST /tasks/:task_id/attempts/:attempt_no/outputs`

Adapter: `ExecutorBridgeAdapter` → attempt-scoped staging writer: bytes stream to the attempt's quarantine dir (created at start), recorded in `progress_json` (staged-file ledger) inside the same writer transaction as the receipt. Doc 14 §3: "Streams output into attempt/lease-scoped quarantine." Request is **`multipart/form-data`** (the only non-JSON route; mirrors the editor's eventual upload needs — doc 14 §4 `POST /projects/{slug}/media` is the separate general-upload route, out of scope here).

Header: **`Idempotency-Key` (required).** Parts:

| Part | Content | Req | Notes |
|---|---|---|---|
| `fence` | JSON `{"lease_id": "<ulid>", "status_version": <int>}` | ✔ | latest fence (fails the request if stale) |
| `manifest` | JSON `{"outputs": [{"key", "role", "content_type", "size", "sha256"}]}` | – | optional predeclaration; the server re-verifies actual bytes at complete |
| file parts (arbitrary names) | raw bytes | ✔ (≥1) | streamed to quarantine; filename = part name |

`200`:

```json
{
  "staged": [
    { "key": "out_0.png", "size": 1048576, "sha256": "<64-hex>", "role": "result" }
  ],
  "attempt": { "attempt_id": "<ulid>", "attempt_no": 1, "status": "running", "status_version": 3, "lease_id": "<ulid>", "lease_expires_at": "…Z", "heartbeat_counter": 1, "last_heartbeat_at": "…Z" }
}
```

- The server computes `sha256` over received bytes (identity = SHA-256, doc 04 §3.11); a `manifest` `sha256` mismatch → `400 invalid_staged_outputs` and the request is rejected atomically.
- **Size limits:** per-request `max_request_bytes` (2 GiB default) and per-attempt `quota_bytes` (64 GiB default) → `413 payload_too_large` with `"limit_bytes"`. Bytes are hashed while streaming; only verified files become `staged` entries.
- Whether staging is a receipted event (`core.task.outputs_staged`) or a non-event narrow update (heartbeat-style) is an open kernel-design decision (§17); the wire contract only requires idempotent replay of the `staged` list. [INFERENCE]
- Errors: `400 invalid_body/invalid_lease_id/invalid_status_version`; `400 invalid_staged_outputs`; `404 task_not_found/attempt_not_found`; `409` fences (with `attempt` extra); `409 idempotency_mismatch`; `413 payload_too_large`; `500 internal` (disk/write failures → typed, no partial-commit exposure).

## 10. R7 — Complete: `POST /tasks/:task_id/attempts/:attempt_no/complete`

Adapter: `ExecutorBridgeAdapter` → **one atomic Reigh completion service** (doc 14 §3, `[BUILD]`): in one `BEGIN IMMEDIATE` — verify/prepare staged bytes → `TaskRepository.complete` (fenced) → insert `task_outputs` + `media` + `media_locations` + `media_relations` lineage → create/update the generation projection → shot placement (+ optional timeline registry entry). Replaces Reigh's multi-step `complete_task` (upload→generation→task row→placement→billing); **no billing step** (credits cut, doc 15).

Header: **`Idempotency-Key` (required).** Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `lease_id` | string | ✔ | |
| `status_version` | integer | ✔ | latest fence — the worker's keeper must not heartbeat after this |
| `outputs` | array | ✔ | `[{staging_key, role, is_primary?, params?}]`; `role='result'` is the primary-output role; at most one `is_primary` per task (kernel `task_one_primary_result` partial unique index, doc 04 §3.10) |

`200`:

```json
{
  "task": { "task_id": "<ulid>", "project_id": "<ulid>", "capability": "reigh.wan_2_2_t2i",
    "status": "succeeded", "winning_attempt_id": "<ulid>", "max_attempts": 3, "finished_at": "…Z" },
  "attempt": { "attempt_id": "<ulid>", "attempt_no": 1, "status": "succeeded", "status_version": 4,
    "lease_id": "<ulid>", "lease_expires_at": "…Z", "heartbeat_counter": 2, "last_heartbeat_at": "…Z", "finished_at": "…Z" },
  "outputs": [ { "ordinal": 0, "role": "result", "is_primary": true, "media_id": "<ulid>", "media": { "media_id": "<ulid>", "content_hash": "<64-hex>", "byte_size": 1048576, "mime_type": "image/png", "url": "http://127.0.0.1:17333/api/astrid/projects/<slug>/media/<ulid>/content" } } ],
  "generation": { "generation_id": "<ulid>", "name": null, "type": "image", "starred": false } | null,
  "placement": { "shot_id": "<ulid>", "item_id": "<ulid>", "timeline_frame": 3.5 } | null
}
```

- `generation`/`placement` are non-null only when `output_policy.create_generation`/`shot_id` were set at admission (doc 14 §3 steps 4–5). `task_outputs` rows are keyed `(task_id, ordinal)` with `role`/`is_primary`/`params_json` (doc 04 §3.10).
- A staged `staging_key` missing from quarantine → `400 invalid_staged_outputs` with the missing key in `detail`; nothing commits.
- Errors: `400 invalid_body/invalid_outputs/invalid_lease_id/invalid_status_version/invalid_staged_outputs`; `404 task_not_found/attempt_not_found`; `409 stale_status_version/lease_mismatch/attempt_not_live/lease_expired/task_terminal`; `409 idempotency_mismatch`; `413`; `422 schema_incompatible` (non-canonicalizable `params`/metadata); `500 internal` — a completion that fails mid-transaction rolls back entirely (doc 14 risk "completion atomicity").

## 11. R8 — Fail: `POST /tasks/:task_id/attempts/:attempt_no/fail`

Adapter: `ExecutorBridgeAdapter` → `TaskRepository.fail` (kernel `TaskFailReadModel` outcomes `requeued`|`failed`, `tasks.py:581-590, 664-694`): within `max_attempts` the task returns to `queued` (attempt `failed`, a new claim later creates the next `attempt_no`); at budget exhaustion the task terminates `failed`. This replaces Reigh's worker-side retry classification + requeue + `tasks.attempts` counter (doc 12 §3.2) — the kernel's attempt rows and budget are the single source of truth (doc 15 Q1: `execution_attempts` is the only attempt ledger).

Header: **`Idempotency-Key` (required).** Body:

| Field | Type | Req | Notes |
|---|---|---|---|
| `lease_id` | string | ✔ | |
| `status_version` | integer | ✔ | |
| `error` | object | ✔ | `{"code": "<string>", "message": "<≤4000 chars>", "retryable": <bool>}`; `message` bounded by `MAX_ERROR_PAYLOAD_CHARS` (4000, `task_executor/service.py`); stored in `execution_attempts.error_json` |

`200`:

```json
{ "outcome": "requeued" | "failed",
  "task": { "task_id": "<ulid>", "project_id": "<ulid>", "status": "queued" | "failed", "max_attempts": 3 },
  "attempt": { "attempt_id": "<ulid>", "attempt_no": 1, "status": "failed", "status_version": 4, "error": { "code": "…", "message": "…", "retryable": true }, "finished_at": "…Z" } }
```

- `outcome` is the kernel's decision, not the worker's claim: a `retryable: true` error with budget → `requeued`; anything at budget → `failed`. Reigh's per-category retry maxima (2–3, doc 12 §3.2) collapse into `max_attempts=3` per doc 14 §2.
- Errors: `400 invalid_body/invalid_error/invalid_lease_id/invalid_status_version`; `404 task_not_found/attempt_not_found`; `409 stale_status_version/lease_mismatch/attempt_not_live/lease_expired/task_terminal`; `409 idempotency_mismatch`; `413`.

## 12. R9 — Media content: `GET|HEAD /projects/:slug/media/:media_id/content`

Adapter: `ReighContentBridgeAdapter` (media) → kernel `media`/`media_locations` (project-scoped ULID lookup), with the **exact** frozen byte-serving wire semantics of `…/timelines/:ref/assets/:key` (contract §9; `local_bridge_server.py:_serve_resolved_asset:620-770`): bytes verified against `media.content_hash` before streaming (`_resolve_verified_local_location` pattern); managed realm → digest-tree path, external_local → reference-in-place; `remote`/HTTP locators never served locally.

- Resolution: `:media_id` must be a valid ULID → else `400 invalid_media_id`; `media.resolve_media(project_id=…, media_id=…)` — a cross-project media id is indistinguishable from unknown → `404 media_not_found` (same posture as asset `asset_not_found`, doc 09 §3).
- **Headers** (identical to §9.1): `Content-Type` (mime from `media.mime_type`), `Accept-Ranges: bytes`, `Cache-Control: private, no-cache`, `ETag` `"{mtime_ns:x}-{size:x}"`, `Last-Modified` (RFC 1123).
- **Status codes** (identical to §9.2): no `Range` + full body ≤ 64 MiB → `200`; `If-None-Match` match → `304` (validators + cache headers, no body); full body > 64 MiB → `206` initial 1 MiB chunk; single valid range → `206` with `Content-Range`; malformed `Range` → `400` text/plain (`invalid Range header`/`empty Range`); unsatisfiable → `416` `Content-Range: bytes */<size>` + `Content-Length: 0`. Range grammar §9.3 verbatim (single range only; open-ended; suffix; end-clamping). `HEAD` mirrors `GET` with no body.
- CORS: same allowlist; `Access-Control-Expose-Headers` already covers `Accept-Ranges, Content-Length, Content-Range, Content-Type, ETag, Last-Modified`.
- Errors: `400 invalid_media_id`; `404 media_not_found / media_not_local`; `500 internal` (fails closed when the repository bridge is not composed).

## 13. R10–R12 — Content reads (projects, shots, gallery)

Adapter: `ReighContentBridgeAdapter` (projects/shots/generations/variants) over kernel `projects`, `shots`/`shot_items`, and the doc-14 §4 content-pack tables (`generations`, `generation_variants`, `shot_generation_items`). All read-only; all responses `Cache-Control: no-store`; pagination via opaque `?cursor=` (opaque, server-generated, encodes `created_at`+id ordering; no page numbers — polling-friendly analog of PostgREST range). [INFERENCE — cursor shape; no bridge precedent.]

### 13.1 `GET /projects/:slug` — project read (doc 06 §8.B.8 analog)

`200`:

```json
{ "project_id": "<ulid>", "slug": "<slug>", "name": "<name>",
  "settings": { "default_timeline_id": "<ulid>", "aspect_ratio": "16:9", "…": "repository-owned keys only" },
  "created_at": "…Z", "updated_at": "…Z" }
```

- `settings` = `projects.settings_json` passthrough (repository-owned keys only, doc 04 §3.2). Reigh's `aspect_ratio` column migrates into `settings_json.aspect_ratio` [INFERENCE — no column exists in the kernel; doc 10 §2.1 reads `projects.aspect_ratio` at admission].
- `400 invalid_project`; `404 project_not_found`.

### 13.2 `GET /projects/:slug/shots` and `GET /projects/:slug/shots/:shot_id` (doc 06 §3.2)

`200` list (`{"shots": [...]}`, ordered `sort_key` asc — the kernel `UNIQUE(project_id, sort_key)` order, doc 04 §3.16; Reigh's `position` maps to `sort_key`):

```json
{ "shots": [ { "shot_id": "<ulid>", "name": "Getting Started", "sort_key": 0,
    "metadata": {}, "created_at": "…Z", "updated_at": "…Z", "item_count": 3 } ] }
```

`200` single (`/shots/:shot_id`) adds `items` ordered by `sort_key` asc (positioned items by `timeline_frame` asc per doc 06 §3.2; both columns exist in the v2 DDL — order by `sort_key`):

```json
{ "shot": { "shot_id": "<ulid>", "name": "…", "sort_key": 0, "metadata": {}, "created_at": "…Z", "updated_at": "…Z" },
  "items": [ { "item_id": "<ulid>", "generation_id": "<ulid>", "timeline_frame": 3.5, "sort_key": 0, "metadata": { "enhanced_prompt": "…" }, "created_at": "…Z" } ] }
```

- `shot_generation_items.metadata_json` carries the Reigh `shot_generations.metadata` payload (incl. `enhanced_prompt`, doc 06 §3.2). `shot_not_found` → `404 shot_not_found` (new code; keep parallel to `project_not_found`).

### 13.3 Gallery: `GET /projects/:slug/generations`, `…/:generation_id`, `…/:generation_id/variants`, `GET /projects/:slug/variants` (doc 06 §3.3, §8.B.11–12)

`GET /projects/:slug/generations?limit=100&cursor=…&starred=true` — `200`:

```json
{ "generations": [ { "generation_id": "<ulid>", "name": null, "type": "image", "starred": false,
    "created_at": "…Z", "updated_at": "…Z",
    "primary_variant": { "variant_id": "<ulid>", "media_id": "<ulid>", "variant_type": "original", "name": "Original", "is_primary": true, "starred": false, "viewed_at": null } | null,
    "variant_count": 2 } ],
  "next_cursor": "<opaque|null>" }
```

- Ordered `created_at desc, id asc` (Reigh gallery order, doc 06 §3.3); `starred=true` filters. `variant_count` is the head-count the gallery reads today (doc 06 §3.3 "exact head count").

`GET /projects/:slug/generations/:generation_id` — `200`:

```json
{ "generation": { "generation_id": "<ulid>", "task_id": "<ulid>|null", "name": null, "type": "image",
    "based_on_generation_id": "<ulid>|null", "parent_generation_id": "<ulid>|null", "child_order": null,
    "params": {}, "starred": false, "created_at": "…Z", "updated_at": "…Z",
    "variants": [ { "variant_id": "<ulid>", "media_id": "<ulid>", "variant_type": "original", "name": "Original", "is_primary": true, "starred": false, "viewed_at": null, "created_at": "…Z" } ],
    "items": [ { "item_id": "<ulid>", "shot_id": "<ulid>", "timeline_frame": 3.5 } ] } }
```

- Field names follow the doc-14 §4 DDL exactly (`based_on_generation_id`, `parent_generation_id`, `child_order`, `params_json`, `starred`, `variant_type`, `is_primary`, `viewed_at`, `timeline_frame`, `sort_key`, `metadata_json`); JSON keys drop the `_json` suffix (kernel read-model style, doc 04 §3).

`GET /projects/:slug/generations/:generation_id/variants` — `200`: `{"variants": [ <variant row, ordered created_at desc> ]}`.

`GET /projects/:slug/variants?limit&cursor` — `200`: `{"variants": [ <variant row + generation_id + media_id + variant_type + is_primary + starred + viewed_at + created_at> ], "next_cursor": …}` (the variants-first gallery read, doc 06 §3.3: `generation_variants.select(...).eq('project_id').order(created_at desc)`).

- Errors: `400 invalid_project`; `404 project_not_found`; `404 generation_not_found` (new code for unknown `:generation_id`); `422` never applies (pure reads).

## 14. Internal maintenance loop — lease expiry (NOT a route)

Doc 14 §3: "Run a maintenance loop in `astrid serve` that repeatedly calls `TaskRepository.expire_overdue`."

- **Placement:** a serve-side loop owned by the serve composition root (`compose_standard_bridge` / `_dispatch_serve`), on a background thread that **submits through the same `DatabaseWriter` queue** as every other command — no second writer, no raw SQL (doc 04 §2.4 single-writer law). It is deliberately not an HTTP route: no client should be able to trigger expiry, and the sweep must run even when no client is connected.
- **Kernel call:** `TaskRepository.expire_overdue(uow, *, project_id, now)` — currently **project-scoped** (finds live `claimed|running` attempts with `lease_expires_at <= now` in one project, order `lease_expires_at ASC, task_id ASC, attempt_no ASC`; `tasks.py:2358-2568`). The loop therefore iterates projects, or a `[BUILD]` cross-project sweep wraps it (doc 14 §3's periodic-expiry BUILD item).
- **Semantics** (kernel, `TaskExpiryReadModel`): one expired attempt per command → attempt `expired` (version +1, `finished_at`), task exits `running`, `core.task.expired` event, then **requeue within `max_attempts`** (`queued`, next claim creates the next `attempt_no`) or **terminal `failed`** when the budget is exhausted. Expiry never extends a lease and never races heartbeat: both serialize on the writer FIFO, and heartbeat's exact predicates reject an already-expired lease (`tasks.py:2304-2321`).
- **Cadence:** proposal — default every 60 s, env-tunable (`ASTRID_BRIDGE_EXPIRY_SWEEP_SECONDS`). Rationale: leases are 300 s and heartbeats 30 s, so a 60 s sweep bounds stale-lease recovery to ~1 min (vs Reigh's 24 h auto-fail cron, doc 02 §6 — the kernel model is strictly tighter; doc 13 §4.3 "300 s default lease vs 24 h Reigh threshold"). [INFERENCE — no constant exists; 60 s is a proposal.]
- **No new table, no `FORBIDDEN_TABLES` risk:** expiry uses kernel commands only; no sentinel/`sentinel_ticks`/`pause_scaling` analog is built (scaling is out of scope for local-only workers, doc 15 Q3/Q5).

## 15. Reserved routes

1. **`POST /projects/:slug/timelines/:ref/copy` (frozen m6 reservation, contract §11) — stays reserved.** The extension must **not** register it; its planned semantics (optional target name, derived idempotency key from source identity+head+payload, `409 timeline_version_conflict` on stale source head, fresh timeline with `config_version 0`, receipt secrecy) are unchanged from the frozen contract.
2. **`POST /tasks/:task_id/cancel` — declared, not normative in this spec.** Doc 14 §4 routes task cancellation to the local client; kernel `TasksService.cancel` exists (queued/blocked direct; running requires the executor-owned fence `attempt_id`+`lease_id`+`status_version`, `tasks.py:2575-2810`). Wire shape (request `{lease_id?, status_version?}` for running tasks; `Idempotency-Key` required; `200` canceled task; same 404/409 fence vocabulary) is a follow-up contract once phase 2 freezes the app workstream.
3. **`GET /queue/summary` — declared, not normative in this spec.** Doc 14 §3 lists a global queue summary (`[BUILD]`) as the local replacement for Reigh's `task-counts` RPC (doc 10 §2.2). Local-only workers make scaling moot (doc 15 Q3), but the app's pending-task badges and the executor's claim gating benefit from `{"queued": n, "running": n, "claimable_by": {"<capability>": n}}`. Add only if phase 2 needs it.

## 16. bridgeContract.ts additions (zod)

Add to `reigh-app/src/tools/video-editor/data/bridgeContract.ts` (and mirror in the Astrid-side normative contract), in the existing style — `z.looseObject`, optional fields, `parseBridgePayload` validate-don't-rewrite, exported `z.infer` types:

| Schema | Route(s) | Fields (zod) |
|---|---|---|
| `bridgeCreateTaskRequestSchema` | R1 | `family: z.string()`, `input: jsonObject`, `materialized_inputs: z.array(z.looseObject({ media_id: z.string().optional(), generation_id: z.string().optional(), kind: z.string(), target: z.string(), url: z.string().optional() })).optional()`, `priority: z.number().optional()`, `available_at: z.string().optional()`, `dependant_on: z.array(z.string()).optional()` |
| `bridgeTaskCreatedSchema` | R1 | `task_id: z.string().optional()`, `run_id: z.string().optional()`, `task_ids: z.array(z.string()).optional()`, `project_id: z.string().optional()`, `capability: z.string().optional()`, `status: z.string().optional()`, `run_ordinal: z.number().nullable().optional()`, `deduplicated: z.boolean().optional()` |
| `bridgeTaskRowSchema` / `bridgeTaskListSchema` | R2 | task row per §5; list `{tasks: array, next_cursor: z.string().nullable().optional()}` |
| `bridgeClaimRequestSchema` / `bridgeClaimResponseSchema` | R3 | request `{executor_id, capabilities: z.array(z.string()), lease_seconds: z.number().optional(), max_task_wait_minutes: z.number().optional()}`; response `{task: bridgeTaskRowSchema, attempt: bridgeAttemptSchema, media: z.record(jsonObject).optional()}` |
| `bridgeAttemptSchema` | R3–R8 | `{attempt_id, attempt_no, status, status_version, lease_id, lease_expires_at, heartbeat_counter, last_heartbeat_at, finished_at: z.string().nullable().optional(), error: jsonObject.optional()}` |
| `bridgeStartRequestSchema` / `bridgeStartResponseSchema` | R4 | request `{lease_id, status_version}`; response `{attempt, staging: {upload_url, quota_bytes, max_request_bytes}}` |
| `bridgeHeartbeatRequestSchema` / `bridgeHeartbeatResponseSchema` | R5 | request `{lease_id, status_version, lease_seconds: z.number().optional(), progress: jsonObject.optional()}`; response `{attempt}` |
| `bridgeStagedOutputsSchema` | R6 | `{staged: z.array(z.looseObject({key, size, sha256, role})), attempt}` |
| `bridgeCompleteRequestSchema` / `bridgeCompletionSchema` | R7 | request `{lease_id, status_version, outputs: z.array(z.looseObject({staging_key, role, is_primary: z.boolean().optional(), params: jsonObject.optional()}))}`; response per §10 |
| `bridgeFailRequestSchema` / `bridgeFailResultSchema` | R8 | request `{lease_id, status_version, error: {code, message, retryable}}`; response `{outcome: z.enum(['requeued','failed']), task, attempt}` |
| `bridgeFenceErrorEnvelopeSchema` | all 409s | extends `bridgeErrorEnvelopeSchema` with `attempt: bridgeAttemptSchema.optional()`, `max_attempts: z.number().optional()` |
| `bridgePayloadTooLargeSchema` | 413 | `error: z.string(), detail: z.string(), limit_bytes: z.number()` |
| `bridgeProjectSchema` | R10 | `{project_id, slug, name, settings: jsonObject, created_at, updated_at}` |
| `bridgeShotsSchema` / `bridgeShotSchema` | R11 | per §13.2 |
| `bridgeGenerationsSchema` / `bridgeGenerationSchema` / `bridgeVariantsSchema` | R12 | per §13.3 |
| `bridgeMediaContentErrorSchema` | R9 | `media_not_found`/`media_not_local` envelope |

Constants to add: `BRIDGE_IDEMPOTENCY_KEY_HEADER = 'Idempotency-Key'`; `BRIDGE_STAGING_TIMEOUT_MS` (proposal 120 000 for `/outputs`; JSON routes keep `BRIDGE_REQUEST_TIMEOUT_MS = 10_000`); fence code constants (`BRIDGE_STALE_STATUS_VERSION_CODE = 'stale_status_version'`, `BRIDGE_LEASE_MISMATCH_CODE = 'lease_mismatch'`, `BRIDGE_LEASE_EXPIRED_CODE = 'lease_expired'`, `BRIDGE_ATTEMPT_NOT_LIVE_CODE = 'attempt_not_live'`, `BRIDGE_TASK_TERMINAL_CODE = 'task_terminal'`, `BRIDGE_BUDGET_EXHAUSTED_CODE = 'attempt_budget_exhausted'`, `BRIDGE_IDEMPOTENCY_MISMATCH_CODE = 'idempotency_mismatch'`, `BRIDGE_PAYLOAD_TOO_LARGE_CODE = 'payload_too_large'`). `parseBridgePayload` reuse is mandatory (rule: never coerce a malformed payload; the editor's poll-adoption gating must treat a fence 409 as "in-flight resync", not data).

## 17. Open questions

1. **Claim receipt on no-work:** should `204` claims write a receipt (replayable "no work at T0") or stay receipt-free (re-query on replay)? This spec assumes receipt-free (§2.4/§6.2); kernel `claim` returning `None` has no stored result to replay. Confirm in the cross-project claim service build.
2. **Staging event vs non-event:** does `/outputs` append an event (new kind like `core.task.outputs_staged`) or stay a non-event narrow update (heartbeat-style) with the receipt only? The kernel's event-registry freeze means a new kind is a schema-pack change; the wire contract is neutral (§9).
3. **`aspect_ratio` and project settings:** Reigh's `projects.aspect_ratio` (read at task creation, doc 10 §2.1) has no kernel column — confirm migration into `settings_json.aspect_ratio` and whether `GET /projects/:slug` should also surface `timeline` defaults beyond `default_timeline_id`.
4. **Queue ordering without model affinity:** doc 13 §4.3 maps model affinity + 5-min starvation to `priority` + `available_at`; is the executor's `max_task_wait_minutes` claim parameter needed at all for local workers, or is pure `priority DESC, available_at ASC, id ASC` (kernel claim order) sufficient?
5. **Generation/timeline placement on complete:** the completion service (doc 14 §3) "adds the shot placement and optional timeline registry entry" — for timeline entry, does it call the existing CAS `TimelinesService.save` (advancing `config_version`) or a lower-level registry mutation? CAS-on-complete vs placement-without-version-advance is a design decision that affects editor polling.
6. **Cancel route timing:** `POST /tasks/:task_id/cancel` is declared but not normative here; it becomes normative in phase 2 with the app workstream (doc 14 §4). Same for `GET /queue/summary`.
7. **Size-limit constants:** `max_request_bytes` 2 GiB, `quota_bytes` 64 GiB, sweep 60 s are proposals (`[INFERENCE]`); confirm against expected WGP/VibeComfy output sizes before freezing.
8. **Polling freshness for the app:** doc 06 §8.D realtime equivalences are polling-only per doc 15 Q7; the 1–2 s active claim cadence only covers workers. The app's task/generation badges keep 3–5 s polling unless a push channel is later added.
9. **Cross-project claim determinism:** the claim service iterates projects; define the deterministic project iteration order (slug asc? priority-weighted?) so concurrent executors cannot livelock on the same project order. [INFERENCE — no precedent in kernel `claim`.]

## 18. Grounding pointers

- Frozen wire conventions: `Astrid/docs/contracts/astrid-bridge-v10.md` §1–§11; `Astrid/astrid/core/integrations/reigh/{local_bridge_server.py,bridge_service.py}`; `astrid/packs/timeline/bridge.py`; doc 09.
- Route contract being spec'd: doc 14 §2 (admission/kernel shape), §3 (worker protocol/fences/maintenance loop), §4 (build items, content-pack DDL).
- Kernel semantics: doc 04 §3.7–§3.12 (tasks/attempts/outputs/media), §2.4 (single writer), §5 (staging/media layout); `astrid/core/repositories/tasks.py` (`DEFAULT_LEASE_SECONDS`, `claim`/`start`/`heartbeat`/`expire_overdue`/`fail`, `TaskTransitionError` reasons, `TaskClaimReadModel`/`TaskExpiryReadModel`); `astrid/core/task_executor/service.py` (`STAGING_TXN_ID_KEY`, `MAX_ERROR_PAYLOAD_CHARS`); `astrid/sdk/tasks.py` (service surface).
- Reigh contracts carried forward: doc 10 §2.1/§3 (create-task, 13 families, materialized_inputs, dedupe); doc 12 §2–§3 (claim params, retry cap 3); doc 06 §3.1–§3.4/§8.B (content read surfaces).
- Binding scope: doc 15 (credits/auth/sharing cut, local-only workers, polling cadence, capability normalization, attempts archived).
