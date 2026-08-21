# The Astrid ↔ Reigh Bridge

**Context doc 09 — every component, wire shape, and transfer path between Astrid's store (SQLite + files) and the Reigh editor frontend, for a future Reigh-on-Astrid migration.**
Researched 2026-08-21 from the `Astrid/` repo (`/Users/peteromalley/Documents/reigh-workspace/Astrid/`, git HEAD `9602c991`, mid-m8) and `reigh-app/` (`/Users/peteromalley/Documents/reigh-workspace/reigh-app/`, HEAD `6c02bd3ba`). Read-only research; no implementation.

## 1. Summary and key facts

The "bridge" is a **frozen HTTP wire contract** between the Reigh video editor and an Astrid-hosted local HTTP server. Astrid serves it; Reigh consumes it through one TypeScript data provider. It carries exactly one semantic object: **the timeline document** (loose `config` + `registry.assets` + a numeric CAS version), plus project/timeline discovery and byte-range asset serving. It is deliberately narrow: no tasks, runs, media-import, or orchestration routes exist on the bridge.

- **Server (Astrid):** `astrid serve` → `astrid/core/gateway/dispatch.py:_dispatch_serve` composes a repository-backed bridge (`astrid/packs/__init__.py:compose_standard_bridge`) and injects it into a stdlib `ThreadingHTTPServer` (`astrid/core/integrations/reigh/local_bridge_server.py`). Reads/writes go through kernel repositories/SDK services over one SQLite database at `<projects_root>/.astrid/astrid.sqlite3`. There is **no file/JSONL/FSA/Supabase fallback** in the server (m4 plan steps 21–22).
- **Client (Reigh):** `reigh-app/src/tools/video-editor/data/AstridBridgeDataProvider.ts` talks HTTP to `/api/astrid/*` (Vite dev proxy → `http://127.0.0.1:17333`, default `VITE_ASTRID_BRIDGE_PORT`). The wire shapes are the contract artifact `reigh-app/src/tools/video-editor/data/bridgeContract.ts` (zod schemas) and Astrid's normative copy `Astrid/docs/contracts/astrid-bridge-v10.md`.
- **Routes (all IMPLEMENTED):** `GET /health`, `GET /projects`, `GET /projects/:slug/timelines`, `GET /projects/:slug/timelines/:ref`, `POST /projects/:slug/timelines/:ref/save`, `GET|HEAD /projects/:slug/timelines/:ref/assets/:key` (Range/ETag), `OPTIONS` (CORS). One reserved-but-not-implemented route: `POST .../copy` (planned m6).
- **Astrid → Reigh:** plain HTTP polling, no websockets/event streams. Timeline+registry load pair polled every 30 s (`useTimelineQueries.ts:15,22`); discovery (health/projects/timelines) polls every 3 s while the project dropdown is open and the bridge is down/empty (`useAstridBridgeDiscovery.ts:37,90-112`). Assets stream via Range/ETag.
- **Reigh → Astrid:** whole-document **compare-and-swap save** — `POST …/save` with `{config, registry, expected_version}`. Stale `expected_version` → `409 timeline_version_conflict` (zero DB mutation) → the editor enters a "diverged" state (no silent overwrite). Saves are idempotent via a **hidden derived key** (`timeline.save:{project_id}:{timeline_id}:{expected_version}:{digest}`), committed atomically with a `timeline.saved` event, head advance, and receipt in one `BEGIN IMMEDIATE` transaction.
- **IDs:** canonical `timeline_id` = UUID; `timeline_ulid` = 26-char lowercase Crockford ULID (route address); `slug` = immutable project-scoped; `:ref` accepts UUID → ULID → slug in that order. `config_version` = the timeline stream head (`event_streams.head_seq`), an opaque integer to the editor.
- **Tasks/queue:** the bridge has **no task routes**. Tasks enter Astrid only through kernel repositories (SDK `TasksService`, CLI, executor) on the **same single writer queue** the bridge uses. The Reigh worker/orchestrator repos (`reigh-worker/`, `reigh-worker-orchestrator/`) contain **zero** Astrid references — orchestration stays on the Reigh/Supabase side. v10 `CUT`s the legacy Banodoco worker + task client + Supabase append service.
- **Status:** the repository-backed bridge and its contract are real and CI-gated (Astrid `tests/integrations/reigh/test_local_bridge_server.py` ~2500 lines; `tests/v10/test_m7_bridge_contention.py`; Reigh `AstridBridgeDataProvider.test.ts` 22 pass). Legacy file/Supabase bridge machinery still exists in both repos and is slated for deletion (v10 §1 CUT list, m6 teardown). Editor **FSA write mode is still implemented** in the client but v10 deletes it — the bridge is planned as the sole semantic editor path.

## 2. Bridge architecture (components and where they live)

```
Reigh editor (browser)                         Astrid (localhost)
─────────────────────────                      ─────────────────────
AstridBridgeDataProvider.ts                    astrid serve  (_dispatch_serve,
───────────────────────  HTTP fetch ──────►    astrid/core/gateway/dispatch.py:128-233)
│ apiBaseUrl = '/api/astrid'                   │
│ assetBaseUrl (default apiBaseUrl)            └─ compose_standard_bridge()
│  │                                            │   astrid/packs/__init__.py:199-263
│  ▼ Vite dev proxy                             │   • opens .astrid/astrid.sqlite3
│ config/vite/vite.config.ts:52-56             │   • one DatabaseWriter (single queue)
│ '/api/astrid' → 127.0.0.1:$VITE_ASTRID_      │   • ProjectRepository, TimelineRepository
│   BRIDGE_PORT (default 17333)                │   • SDK ProjectsService, TimelinesService
│                                              │   • TimelineBridgeAdapter (pack mount)
│                                              ▼
│                                       LocalBridgeHTTPServer  (stdlib http.server,
│                                       astrid/core/integrations/reigh/
│                                         local_bridge_server.py)
│                                             │ bridge + writer + database_path
│                                             │ injected at construction (m4 step 21;
│                                             │   no post-construction reassignment)
│                                             ▼
│                                       TimelineBridgeAdapter
│                                       astrid/packs/timeline/bridge.py
│                                             │ maps frozen contract → SDK services,
│                                             │ derives hidden save idempotency key
│                                             ▼
│                                       TimelinesService.save/show/list  (SDK,
│                                       astrid/sdk/timelines.py) + kernel UoW
│                                             ▼
│                                       TimelineRepository.save  (whole-doc CAS)
│                                       astrid/packs/timeline/repository.py:840-1061
│                                             • UPDATE timelines document_json +
│                                               asset_registry_json
│                                             • append hash-chained 'timeline.saved'
│                                             • advance event_streams.head_seq
│                                             • write command_receipts row
│                                             — one BEGIN IMMEDIATE (receipt/event
│                                               atomicity)
```

Server-side components:

| Component | File | Role |
|---|---|---|
| HTTP server + routes | `Astrid/astrid/core/integrations/reigh/local_bridge_server.py` (1004 ln) | `ThreadingHTTPServer`; route grammar; CORS allowlist; Range/ETag byte serving; typed error serialization |
| Wire DTOs + errors | `Astrid/astrid/core/integrations/reigh/bridge_service.py` (372 ln) | Frozen payloads (`HealthStatus`, `ProjectRow`, `TimelineRow`, `TimelineLoad`, `TimelineSaveRequest`) and error classes (`BridgeError` family → 400/404/409/422/500 envelopes); `derive_database_path()`; `RECEIPT_SECRECY_FIELDS` |
| Bridge adapter (contract → SDK) | `Astrid/astrid/packs/timeline/bridge.py` (481 ln) | `TimelineBridgeAdapter`: slug/ref grammar, service mapping, hidden bridge save key (`_derive_bridge_save_key`), receipt-secrecy |
| Compose root | `Astrid/astrid/packs/__init__.py:199-263` | `compose_standard_bridge()` → `StandardBridgeComposition`; also `astrid/application.py:compose_standard_application` (shared app for SDK/CLI/tests) |
| Timeline repository (CAS writer) | `Astrid/astrid/packs/timeline/repository.py` | `save()`/`show()`/`list()`/`history()`/`diff()`; event kinds `timeline.saved` (`TIMELINE_SAVED_EVENT_KIND`, line 86), `timeline.config_replaced`, command kind `timeline.save` (line 94); `_BRIDGE_CANONICAL_TOP_KEYS` (line 144) |
| SDK service | `Astrid/astrid/sdk/timelines.py` (350 ln) | `create/list/show/save/archive/history/diff` with `DomainResult` envelope; ULID alias derivation |
| `serve` CLI | `Astrid/astrid/core/gateway/dispatch.py:128-233` | parses `--host/--port/--projects-root/--editor-path/--no-open-editor`; opens editor bundle (`_locate_reigh_editor`, line 99) |

Client-side components:

| Component | File | Role |
|---|---|---|
| Data provider | `reigh-app/src/tools/video-editor/data/AstridBridgeDataProvider.ts` (1162 ln) | implements `DataProvider`; `loadTimeline`, `loadAssetRegistry`, `saveTimeline`, `registerAsset`, `resolveAssetUrl`, `uploadAsset`, read-only errors |
| Wire contract artifact | `reigh-app/src/tools/video-editor/data/bridgeContract.ts` (145 ln) | zod schemas for every payload + error envelope; `BRIDGE_REQUEST_TIMEOUT_MS = 10_000`; `parseBridgePayload` (validate-don't-rewrite) |
| Discovery hook | `reigh-app/src/tools/video-editor/hooks/useAstridBridgeDiscovery.ts` | health → projects → timelines via react-query; 3 s recovery poll |
| Poll + persistence | `reigh-app/src/tools/video-editor/hooks/useTimelineQueries.ts` (30 s), `usePollSync.ts`, `useTimelinePersistence.ts` | cross-tab sync, poll-adoption gating, save debounce/backoff, conflict divergence, draft recovery |
| Dev proxy | `reigh-app/config/vite/vite.config.ts:52-56` | `/api/astrid` → `127.0.0.1:$VITE_ASTRID_BRIDGE_PORT` (default 17333), strip prefix |
| Local-mode wiring | `reigh-app/docs/structure_detail/tool_video_editor.md:137-139` | local mode = `?localProject`/`?localTimeline` URL params; provider = `AstridBridgeDataProvider`; both modes share `VideoEditorProvider` shell |

Contract docs: `Astrid/docs/contracts/astrid-bridge-v10.md` (normative, frozen for m1); `reigh-app/src/tools/video-editor/data/bridgeContract.ts` (client-side mirror; cross-repo drift is the documented risk — "the `astrid serve` repo should consume or mirror it", line 6-8).

## 3. Astrid → Reigh data flow (reads)

All reads are **HTTP GET/HEAD** against the dev-proxied base; there is no websocket, event stream, or file/snapshot export on the current bridge. The editor polls.

**Route table (server `do_GET`/`do_HEAD`/`do_POST`, `local_bridge_server.py:776-935`):**

| Method + path | Purpose | 200 body (server side) |
|---|---|---|
| `GET /health` | liveness | `{"ok": true, "projects_root": "<abs path>"}` |
| `GET /projects` | discovery | `{"projects": [{"slug", "name"}]}` (slug-ascending) |
| `GET /projects/:slug/timelines` | discovery | `{"timelines": [{"timeline_id", "timeline_ulid", "slug", "name", "is_default"}]}` |
| `GET /projects/:slug/timelines/:ref` | load document | full load payload (§5) |
| `GET\|HEAD /projects/:slug/timelines/:ref/assets/:key` | asset bytes | 200/206/304/416 with Range/ETag (§5) |
| `OPTIONS any` | CORS preflight | 204 |

**How the editor reads (client call graph):**
1. **Discovery** — `useAstridBridgeDiscovery` (used by `EditorProjectTimelineSelectors.tsx`): `GET /health` → `GET /projects` → `GET /projects/:slug/timelines`. Gated: projects/timelines only fetched when health is OK; dropdown-open refetch; 3 s `refetchInterval` while the bridge is down or the list is empty (`useAstridBridgeDiscovery.ts:79-113`).
2. **Timeline load** — `AstridBridgeDataProvider.loadTimeline` and `loadAssetRegistry` both call `fetchTimelinePayload(..., {fresh: true})` → `GET /projects/:slug/timelines/:ref` (`AstridBridgeDataProvider.ts:203-219, 451-493`). The shell's `useTimelineQueries` refetches **both every 30 000 ms** (`useTimelineQueries.ts:15,22`); the provider coalesces the concurrent pair onto one HTTP request so config and registry come from the same bridge revision (`AstridBridgeDataProvider.ts:519-527`). Fresh reads bypass the provider's payload cache; the cache only serves incidental reads (save's registry default, `registerAsset`'s merge base) (`:493-501`).
3. **Payload validation** — every response runs through the zod schemas in `bridgeContract.ts`; malformed payloads throw `BridgeContractError` → editor load-error card (never coerced into plausible data; a malformed registry used to become `{assets:{}}` and get PUT back — contract doc rule 1).
4. **Asset URLs** — `resolveAssetUrl(file)` maps registry `file` → asset key → `${assetBaseUrl}/projects/:slug/timelines/:ref/assets/:key` (`AstridBridgeDataProvider.ts:283-311, 860-866`). `assetBaseUrl` defaults to the apiBaseUrl so media fetches are same-origin through the Vite proxy (`:238-242`).
5. **Asset bytes** — served from the **persisted registry** via kernel `media`/`media_locations` rows: media_id or locator alias → project-scoped media row → actual bytes verified against content SHA-256 before streaming (`local_bridge_server.py:_serve_asset_from_persisted_registry:299-415`; managed realm → digest-tree path, external realm → reference-in-place path, `_resolve_verified_local_location:549-579`). Range grammar single-range only; malformed → 400, unsatisfiable → 416 `bytes */<size>`, ETag match → 304 (contract §9).
6. **Poll adoption** — `usePollSync` accepts polled remote data only when the editor is idle (no interaction/save in flight), version not stale, and stable-signature doesn't match local ("own echo"); otherwise the poll is rejected (`usePollSync.ts:59-113`). Accepted polls are server-authoritative commits that invalidate undo history across the remote boundary (`useTimelineHistory.ts:374-377`).

No authentication on the bridge: it binds `127.0.0.1` by default, CORS allows only exact `localhost:2222/3000/5173` and `127.0.0.1:2222/3000/5173` origins (`local_bridge_server.py:271-278`), and JSON responses are `Cache-Control: no-store` (contract §2.1/§2.4).

## 4. Reigh → Astrid data flow (writes)

**The only semantic write route is `POST /projects/:slug/timelines/:ref/save`** — a whole-document CAS. Everything else is local to the browser (drafts, checkpoints) or FSA sub-mode (legacy, slated for deletion).

**Save path (`AstridBridgeDataProvider.saveTimeline`, `:366-431`):**
1. Editor edits land in the timeline store; `useTimelinePersistence.scheduleSave` debounces 500 ms and POSTs `{config, registry, expected_version}` with a 10 s timeout (`useTimelinePersistence.ts:23, 183-186`; `bridgeContract.ts:BRIDGE_REQUEST_TIMEOUT_MS`).
2. `expected_version` = the client's last-known `config_version` (starts at 0 for a fresh timeline — `useTimelineSave.ts:41-44`). The bridge CAS is strict equality.
3. **Response 200** → the committed load shape with the new `config_version`; the provider caches it, the persistence hook updates `configVersionRef`, clears the IndexedDB draft (`useTimelinePersistence.ts:420-427`).
4. **Response 409 `timeline_version_conflict`** → `TimelineVersionConflictError(expectedVersion, actualVersion)` (`AstridBridgeDataProvider.ts:673-680`). On an initial attempt this is a genuine concurrent write: the editor **enters diverged state** (no reload-and-re-POST of local state — the old ladder "silently overwrote the other writer", the B4 incident fix; `useTimelinePersistence.ts:456-484`). On a *transport retry* a 409 may be a lost ack: the provider re-reads fresh state and, if it byte-matches the attempted save, acknowledges instead (`tryRecoverLostAck`, `:296-352`).
5. Transport failures (500/timeout) → exponential backoff retry 500→8000 ms, then a persistent watchdog banner (`useTimelinePersistence.ts:33-47, 265-293`).
6. **Asset registration** — `registerAsset` rides the combined save: it merges the entry into the cached registry and calls `saveTimeline` with the same `expected_version` (`AstridBridgeDataProvider.ts:425-445`). There is **no** `PUT /registry` route on the current bridge (the doc matrix §4.3 still describes one; the code and contract v10 do not — the combined-save design is authoritative).
7. **Upload** — `uploadAsset` writes the file into the user-selected project folder via the File System Access API (`sources/local-drops/…`) and then registers it via the combined save (`:487-526`); `onUpload()` throws `AstridBridgeReadOnlyError` (`:529-532`). In v10 this FSA write path is CUT: "the bridge is the sole semantic editor path; file selection may still provide bytes to media import" (v10 §1 cut table).

**Server save pipeline (`local_bridge_server.py do_POST:866-935` → `TimelineBridgeAdapter.save_timeline` → `TimelinesService.save` → `TimelineRepository.save`):**
1. Route-level parse: `TimelineSaveRequest.parse` → `config`/`registry` must be objects, `expected_version` integer-not-boolean (400 envelopes) (`bridge_service.py:150-192`).
2. Route-level schema guard: non-object `registry.assets` or non-canonicalizable payload → `422 schema_incompatible` with JSON-pointer `issues[]` (`local_bridge_server.py:_validate_save_payload_schema:940-1004`).
3. Bridge derives the hidden idempotency key `timeline.save:{project_id}:{timeline_id}:{expected_version}:{canonical-digest}` (`astrid/packs/timeline/bridge.py:_derive_bridge_save_key:330-369`; repository derivation mirrors it, `repository.py:928-946`).
4. Repository save in one UoW: `UPDATE timelines SET document_json, asset_registry_json` + append hash-chained `timeline.saved` event carrying the command delta + advance `event_streams.head_seq` (and project head) + write `command_receipts` — single `BEGIN IMMEDIATE` (`repository.py:840-1061`). Stale head → `TimelineVersionConflictError` before any allocation → `409` with the re-read current `config_version`, zero rows changed.
5. **Receipt secrecy:** response is the frozen load shape; `txn_id`, `request_hash`, `idempotency_key`, sequences, `event_ids_json`, `result_json` never appear (`bridge_service.py:RECEIPT_SECRECY_FIELDS:33-47`; contract §7).

**Legacy FSA sub-mode (client, still implemented):** when the user grants a directory handle, `fetchLocalTimelinePayload`/`saveTimeline` read/write `assembly.json` + `registry.json` directly under `<project>/sources/timelines/<ref>/` and resolve assets from `sources/` via File System Access (`AstridBridgeDataProvider.ts:695-760, 796-858`). Local-only; v10 deletes it ("Delete editor FSA mode instead of detecting old and new projects", v10 §3; "FSA and Supabase do not exist as authorities", NORTHSTAR.md).

## 5. Wire shape reference

Frozen in `Astrid/docs/contracts/astrid-bridge-v10.md` (§3–§9) and enforced by `reigh-app/.../bridgeContract.ts`.

**Load payload / save response (`bridgeTimelinePayloadSchema`):**
```json
{
  "timeline_id": "<canonical lowercase UUID 8-4-4-4-12>",
  "timeline_ulid": "<26-char lowercase Crockford ULID>",
  "slug": "<immutable project-scoped slug>",
  "name": "<display name>",
  "is_default": true,
  "config": { "output": {...}, "clips": [...], "tracks": [...] },   // loose; unknown keys preserved
  "registry": { "assets": { "<assetKey>": { "file", "src", "type", "duration", "generationId", "media_id" } } },
  "config_version": 7   // opaque integer; == timeline stream head (event_streams.head_seq)
}
```

**Save request (`POST …/save`):**
```json
{ "config": {...}, "registry": {...}, "expected_version": 6 }
```
- `expected_version` integer only (booleans rejected). No `idempotency_key` field on the wire; the server derives one (contract §6.1).

**Error envelope (every failing route):**
```json
{ "error": "<code>", "detail": "<human string>" }
```
- `409 timeline_version_conflict` adds `"config_version": <current head>` (client reload/retry data).
- `422 schema_incompatible` adds `"issues": [{"pointer": "/registry/assets", "code": "schema_incompatible", "message": "..."}]`.
- Full code vocabulary: `invalid_body`/`invalid_config`/`invalid_registry`/`invalid_expected_version`/`invalid_project`/`invalid_timeline` (400); `project_not_found`/`timeline_not_found`/`asset_not_found`/`asset_not_local` (404); `timeline_version_conflict` (409); `schema_incompatible` (422); `internal` (500); `not_found` (unknown route).

**Addressing / IDs (contract §8, v10 §6.11):**
- `:ref` resolution order: canonical lowercase UUID → lowercase 26-char Crockford ULID → immutable slug; else `400 invalid_timeline`.
- Project slug grammar: `^[a-z0-9]+(?:-[a-z0-9]+)*$` (`packs/timeline/bridge.py:87`).
- UUID/ULID grammars: `_UUID_RE`/`_ULID_RE` (`packs/timeline/bridge.py:44-51`).
- `config_version` is the numeric timeline stream head; a successful save advances it by exactly one (`repository.py:882-883`, contract §6.1). [INFERENCE: editor treats it as opaque; confirmed by "The integer is opaque to the editor, but on the server it equals the timeline stream head", contract §6.1.]
- Kernel IDs (project/task/media/run) are 26-char lowercase Crockford ULIDs (`astrid/core/ids.py`, sibling doc 04); event/txn ids are `uuid4().hex` (32 hex); stream id is `<project_id>:<stream_type>` (sibling doc 04). The bridge itself only exposes timeline UUID/ULID/slug addressing.

**Timestamps:** JSON routes carry no timestamps in the frozen payloads; the kernel records `created_at` ISO-8601 UTC (e.g. fixture clock `2026-08-20T00:00:00.000000+00:00`, `tests/v10/_m7_fixture.py:FIXTURE_CLOCK`). Asset responses carry `ETag` (`"{mtime_ns:x}-{size:x}"`) and `Last-Modified` (RFC 1123) derived from the verified file (`local_bridge_server.py:388-390`).

**Streaming vs polling:** polling only. Discovery: 3 s while down/empty and dropdown open. Document/registry: 30 s (`useTimelineQueries.ts:15,22`). Save: single POST per debounced edit with 10 s request timeout. No SSE/websocket on either side of the current bridge. [INFERENCE: no streaming transport exists in either repo's bridge code; none found in greps.]

## 6. Task/queue interplay through the bridge

**The bridge does not touch tasks.** Route grammar admits only `health|projects|timelines|assets|save` (`local_bridge_server.py:780-940`); there is no task endpoint, no task payload field, and `TimelineBridgeAdapter` only composes project+timeline services (`packs/timeline/bridge.py`).

- **v10 plan says:** the bridge surface is exactly the frozen routes (§4.2); the legacy "Reigh append service/timeline I/O/data provider; Banodoco worker/task client; RunPod integrations" are `CUT/DEFER` from the local product (v10 §1 table; openrouter-chat-20260814 §1). Tasks are kernel tables reached by CLI/SDK/executor, not by the editor.
- **What code exists:** legacy `Astrid/astrid/core/integrations/reigh/task_client.py` (Banodoco worker claim loop), `worker/banodoco_worker.py`, `append_service.py` (Supabase append server), `data_provider.py` (`SupabaseDataProvider`), `timeline_io.py`, `supabase_client.py`, `worker_jwt.py`, `event_construction.py` (`config_to_events`/`asset_registry_to_events`) — all still present in the repo but unused by the repository bridge; v10 CUTs them and m6 teardown deletes old authorities.
- **Where orchestration lives today:** `reigh-worker-orchestrator/` and `reigh-worker/` have **zero** matches for `astrid|17333|/api/astrid|ASTRID` (grepped both repos) — the GPU pipeline stays entirely on the Reigh/Supabase side. Production-mode editor (`SupabaseDataProvider`) writes through the Reigh append service, unrelated to the Astrid bridge.
- **Shared writer proof:** `tests/v10/test_m7_bridge_contention.py` races two HTTP save clients against the real bridge, then queues a service/CLI timeline save and an executor task admission on the **same** `app.writer` queue: results are one 200 + one 409 (winner's head), then both service save and task create succeed, with one event + one receipt per mutation (`:238-314`). This is the concrete evidence that bridge saves, SDK saves, and task admission serialize on one writer queue with no cross-authority conflict.
- **Legacy actor for editor events:** legacy event construction tags editor writes with `REIGH_LOCAL_EDITOR_ACTOR = TimelineActor(type="human", id="reigh-app:local-editor", display="Reigh local editor")` (`astrid/core/integrations/reigh/local_bridge.py:80-83`); the repository-backed `TimelineRepository.save` defaults `actor_kind="local"` (`repository.py:849`) — the editor's saves are "local" actor events in the new model.

## 7. IMPLEMENTED vs DESIGN status

| Bridge piece | Status | Evidence |
|---|---|---|
| `GET /health` | IMPLEMENTED | `local_bridge_server.py:786-788`; contract §3 |
| `GET /projects` | IMPLEMENTED | `:789-795`; contract §4 |
| `GET /projects/:slug/timelines` | IMPLEMENTED | `:797-806`; contract §5.1 |
| `GET /projects/:slug/timelines/:ref` | IMPLEMENTED | `:808-820`; contract §5.2 |
| `POST …/save` (CAS) | IMPLEMENTED | `:884-935` + `packs/timeline/bridge.py` + `repository.py:840-1061` |
| `GET/HEAD …/assets/:key` (Range/ETag/304/416) | IMPLEMENTED | `:311-421, 575-770`; contract §9 |
| `OPTIONS` CORS | IMPLEMENTED | `:874-883`; contract §2.3/§10 |
| Hidden save idempotency key + receipt | IMPLEMENTED | `packs/timeline/bridge.py:287-326`; `repository.py:928-961` |
| Receipt secrecy in responses | IMPLEMENTED | `bridge_service.py:33-47`; `TimelineLoad.to_dict` |
| In-tree contract tests (m1 §12 substitute) | IMPLEMENTED | `Astrid/tests/integrations/reigh/test_local_bridge_server.py` (2511 ln); m4 gate `scripts/reshape/m4_gate.py:197-200` |
| Real-bridge contention + shared-writer lane | IMPLEMENTED | `tests/v10/test_m7_bridge_contention.py`; CI `.github/workflows/ci.yml:95-99` |
| Client provider + contract artifact | IMPLEMENTED | `reigh-app/.../AstridBridgeDataProvider.ts`; `bridgeContract.ts`; 22-pass test suite |
| e2e real-bridge Playwright lane | IMPLEMENTED | `reigh-app/tests/e2e/timeline/real-bridge.spec.ts`, `real-bridge-serve.mjs`; `REAL_BRIDGE=1 npm run test:e2e:timeline:realbridge` |
| Latency gates (GET p95 + save p95 ≤ 500 ms warm, 10 s hard deadline) | IMPLEMENTED (gate) / save lane FLAKY (see gaps) | `reigh-app/scripts/bridge-latency-report.mjs:GET_SAVE_P95_SLO_MS`; both repos' `.github/workflows/bridge-latency.yml`; incident `timeline-save-latency-error-20260812` T2.4 |
| `POST …/copy` (save-as-copy) | **DESIGN (reserved; m6)** | contract §11: "not registered" in m4; `TimelinesService` "no `copy` verb"; `TimelineBridgeAdapter` has no copy path |
| Editor FSA write mode | IMPLEMENTED but **CUT in v10** | `AstridBridgeDataProvider.ts:695-858, 487-526`; v10 §1/§3 "Delete editor FSA mode unconditionally" |
| Legacy Supabase/append/task-client modules | Present but **CUT in v10** (m6 teardown) | `integrations/reigh/{append_service,data_provider,task_client,worker_jwt,supabase_client,timeline_io,event_construction}.py`; v10 §1 cut table |
| Bridge over file/JSONL authorities | REMOVED (no fallback) | `local_bridge_server.py` docstring: "no fallback to file/JSONL/FSA/Supabase"; m4 step 22 removed sidecar asset fallback |
| Legacy file→DB import | IMPLEMENTED as one-time migration (not part of bridge) | `Astrid/scripts/migrations/v10/MIGRATION.md` (project/timeline/media/run families, receipted, idempotent) |

**CI gates that pin the bridge:** Astrid `.github/workflows/ci.yml` m1/m4/m7 lanes + `bridge-latency.yml` (runs the Reigh reporter against the PR checkout, `ASTRID_PYTHON=python3`); reigh-app `.github/workflows/bridge-latency.yml` + `Makefile:bridge-latency-check`; m4 gate `scripts/reshape/m4_gate.py` (bridge lane = `test_local_bridge_server.py`); m7 dogfood lane (`tests/v10/test_m7_dogfood.py`) includes editor save/409/draft-recovery/asset-Range through the real bridge (m7 brief).

## 8. Pointers

**Code — Astrid (bridge authority):**
- `Astrid/astrid/core/integrations/reigh/local_bridge_server.py` — routes, CORS, Range/ETag, error serialization
- `Astrid/astrid/core/integrations/reigh/bridge_service.py` — DTOs, `TimelineSaveRequest.parse`, error classes, `derive_database_path`, `RECEIPT_SECRECY_FIELDS`
- `Astrid/astrid/packs/timeline/bridge.py` — `TimelineBridgeAdapter` (contract→SDK mapping, hidden save key)
- `Astrid/astrid/packs/__init__.py:199-263` — `compose_standard_bridge` (serve composition root)
- `Astrid/astrid/application.py` — `compose_standard_application` (shared app for SDK/CLI/tests)
- `Astrid/astrid/core/gateway/dispatch.py:128-233` — `_dispatch_serve` (CLI entry)
- `Astrid/astrid/packs/timeline/repository.py` — CAS save, event kinds, `_BRIDGE_CANONICAL_TOP_KEYS`
- `Astrid/astrid/sdk/timelines.py` — typed service envelope
- `Astrid/docs/contracts/astrid-bridge-v10.md` — the frozen wire contract (normative)
- `Astrid/scripts/migrations/v10/MIGRATION.md` — legacy file→SQLite import
- Legacy (v10 CUT): `Astrid/astrid/core/integrations/reigh/{append_service,data_provider,task_client,worker_jwt,supabase_client,timeline_io,event_construction,local_bridge}.py`, `Astrid/astrid/core/integrations/worker/banodoco_worker.py`, `Astrid/astrid/core/timeline/eventlog/{local_fs,supabase,reigh_events}.py`
- Tests: `Astrid/tests/integrations/reigh/test_local_bridge_server.py`, `test_local_bridge_helpers.py`, `test_append_service.py`, `test_event_construction.py`; `Astrid/tests/v10/test_m7_bridge_contention.py`, `test_m7_dogfood.py`; `Astrid/tests/v10/_m7_fixture.py`

**Code — reigh-app (client):**
- `reigh-app/src/tools/video-editor/data/AstridBridgeDataProvider.ts`, `bridgeContract.ts`, `DataProvider.ts`
- `reigh-app/src/tools/video-editor/hooks/useAstridBridgeDiscovery.ts`, `useTimelineQueries.ts`, `usePollSync.ts`, `useTimelinePersistence.ts`, `useTimelineSave.ts`, `timelineStore.ts`
- `reigh-app/config/vite/vite.config.ts:52-56` — `/api/astrid` proxy
- `reigh-app/tests/e2e/timeline/{astrid-bridge-stub.mjs, real-bridge-serve.mjs, real-bridge.spec.ts, support.ts}`
- `reigh-app/scripts/{bridge-latency-report.mjs, bridge-latency-seed.py}`; `reigh-app/Makefile:bridge-latency-check`
- Docs: `reigh-app/docs/structure_detail/tool_video_editor.md:137-139` (local mode), `reigh-app/docs/video-editor/provider-compatibility-matrix.md` §4.3/§10.2 (Astrid limitations)
- Tests: `reigh-app/src/tools/video-editor/data/AstridBridgeDataProvider.test.ts` (22 pass / 3 pre-existing), `providerCompatibility.astrid.test.ts`, `hooks/useAstridBridgeDiscovery.test.tsx`, `components/EditorProjectTimelineSelectors.test.tsx`, `pages/VideoEditorPage.test.tsx`

**Plan docs:**
- `docs/unified-data-model-plan-v10-20260813.md` — §4.2 "SDK and bridge" (frozen surface, payload fields, CAS, idempotency key, draft safety), §5.3 GA item 6 (bridge lane), §1 cut table (FSA/Supabase/append deleted), §3 editor-wiring gate
- `docs/unified-data-master-plan-20260814.md` — §1.2 (bridge as "mounted Astrid-facing surface over timeline and media capabilities", line 45), §2.3 plugin laws (bridge handlers use the one writer), §6.11 identity contract (UUID canonical / ULID address)
- `.megaplan/initiatives/astrid-first/NORTHSTAR.md` — "Reigh timeline-sync requirement stays live… editor↔Astrid bridge contract keeps working", "Single writer: repositories are the only semantic writers; bridge, CLI, SDK, executor, media import all route through them"
- `.megaplan/initiatives/astrid-first/briefs/m1.md` (thin frozen bridge routes, S1-09/10), `m4.md` (full route surface, disposition lane), `m6.md` (serve wiring, teardown)
- `.megaplan/initiatives/astrid-first/docs/astrid-first-sprint-plan-20260813.md` (Sprint 1 item 9-10, Sprint 4 "Full editor bridge"), `openrouter-chat-20260814-plugin-data.md` (§4.2, changes vs v9 items 8-9)

## 9. Gaps / unverified

- **Latency-fixture serving path unclear.** `reigh-app/scripts/bridge-latency-seed.py` builds a *legacy file-based* fixture (LocalFsBackend `assembly.jsonl`, `display.json`, `assembly.identity.json`, `project.json` — lines 44-116) with no SQLite write, then `bridge-latency-report.mjs:356-360` boots `astrid serve --projects-root <temp>`. No file→DB bootstrap exists in the serve composition root (`compose_standard_bridge` only creates the DB dir + writer; no project seeding found). How the repository-backed serve resolves that fixture's project/timeline rows is **unverified** — possibly the gate currently 404s on GET or relies on the v10 migration scripts being run first. The reigh-app workflow header says the save gate "is expected to FAIL here — that is the recorded pre-fix baseline, not a weakened SLO" until "the astrid incremental-log fix (T2.1)" lands (`reigh-app/.github/workflows/bridge-latency.yml:9-11`), which suggests at least the save lane is currently red. The related incident is `timeline-save-latency-error-20260812` (T2.4 MUST-FIX 5, save ~1 s+).
- **`registerAsset` doc drift.** `reigh-app/docs/video-editor/provider-compatibility-matrix.md` §4.3 still describes "`registerAsset` PUTs `/registry` with `expected_version`", but the current client code and contract v10 have no `PUT /registry` route — registration rides the combined save (`AstridBridgeDataProvider.ts:425-445`). The doc matrix is stale relative to code. The matrix also says "No server-side CAS — versionConflictIsSoft: true" in §10.2, contradicting the now-strict bridge CAS; the code's comment (B5, `:359-364`) says the bridge can adopt `expected_version` independently, i.e. the matrix predates the server-side CAS. [INFERENCE: docs lag code by ~1 release; the code + contract v10 are authoritative.]
- **`config_version` semantics at the boundary.** Contract §6.1 says the server's integer equals `event_streams.head_seq` and a save advances it by exactly one. The client only treats it opaquely. The `timeline.created` event also advances the head (head starts at 0 then goes to 1 on create — `repository.py:739-768`), so a fresh timeline's first load may report `config_version` 1, while `useTimelineSave.ts:41-44` initializes the client ref to 0 and relies on the first load to sync. Edge: `normalizeConfigVersion` defaults missing `config_version` to 1 (`AstridBridgeDataProvider.ts:177-179`). Not flagged as a bug; simply a boundary detail worth confirming during migration.
- **FSA sub-mode behavior on a migration.** The client can silently operate in the local-directory (FSA) sub-mode when a persisted directory handle matches the project layout (`getProjectRootHandleOptional`), bypassing the bridge for reads AND writes. v10 deletes this; today it is a second semantic writer from the bridge's perspective (and from the repo's own single-writer rule). Migration must ensure the FSA path is removed or never activated (v10 §1: "Delete editor FSA mode unconditionally").
- **Unread internals (out of scope but adjacent):** full `test_local_bridge_server.py` body (2511 ln — behavior covered by contract §12 substitute; spot-read only), `local_bridge.py` legacy helpers (1098 ln — mostly legacy file paths; only `resolve_bridge_projects_root` is imported by the server), `TimelineRepository` create/archive/history/diff internals, `TimelinesService` remaining 230 lines, `useTimelineQueries`/`VideoEditorProvider` full poll wiring, the real-bridge Playwright spec body.
- **Live data state:** sibling doc 04 reports `Astrid/projects/.astrid/astrid.sqlite3` has all 20 tables present but **empty except `schema_migrations`** (migrations applied 2026-08-21T08:59:05Z). So the production bridge DB currently has no projects/timelines to serve; `GET /projects` would return `[]` and `GET /projects/:slug/...` would 404. [Cross-checked at research time; do not assume this is still true when the migration runs.]
- **Auth/transport security:** none beyond localhost binding + CORS allowlist; no TLS, no token. v10 keeps this (local product, zero secrets). Production Reigh (Supabase mode) is a separate, unrelated transport.
