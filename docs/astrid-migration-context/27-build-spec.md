# 27 — Reigh-on-Astrid working build specification

> **Status: CURRENT WORKING BUILD CONTRACT. (Amended: Grok review — judged ADOPT/MODIFY; Amended: engineering-answers judgment.)**
> This document consolidates the surviving build requirements from docs 16–21 and 26 after the ratified owner decisions in docs 15, 24, 25, and `grok/second-opinion-decisions.md`. Where an older design artifact conflicts with this document, this document controls. The ratified constitution still outranks it.

## 1. Product boundary

Reigh is a local, single-user editor over one Astrid SQLite database and Astrid's SHA-256 managed media tree. The browser and one same-host worker process communicate only with the loopback `astrid serve` listener. Workers never open SQLite; all mutations enter the existing single writer queue.

The v1 product has no Supabase authority, importer, replay layer, rollback authority, auth tenancy, billing, remote workers, autoscaling, outbound generation provider, runtime plugin loader, or second shot-placement store. Docs 11 migration scripts and doc 13 §§8–11 are historical evidence, not journey work.

The following are binding:

- Capability IDs are flat `reigh.<normalized_task_type>` names. `family` remains the frontend admission key.
- Each capability has exactly one code-declared local executor binding.
- Shipped Comfy workflows are in-repo `ready_templates`; user workflows are immutable snapshots with a pinned digest.
- Dead task types are rejected, never aliased.
- Orchestrator parents remain leased and running; only their fenced executor may admit allowlisted children.
- Shot groups, pools, timing, order, and boundary overrides live in the CAS-versioned timeline document.
- Generations and variants are relational rows; placement is document structure.
- Render runs through Astrid/Remotion and publishes a managed MP4 for browser playback.
- Media is always copied into the managed tree.
- Polling is 2 seconds active, 10 seconds idle, and 30 seconds for timeline safety refreshes. No SSE.

## 2. Authority and storage

### 2.1 Structured state

One Astrid SQLite file is the only structured authority. Existing kernel task, attempt, output, media, event, receipt, run, and dependency tables remain unchanged. Do not add a Reigh task-types table, worker registry, provider registry, placement table, staging ledger, or alias table.

### 2.2 Generation pack v2

The `shots` pack advances to migration v2 with exactly two new tables:

```sql
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

CREATE UNIQUE INDEX generation_one_primary
  ON generation_variants(generation_id) WHERE is_primary = 1;
```

Add the paging, project, lineage, task, and media lookup indexes from doc 17 §2. The schema keeps soft deletion, `media_id ... ON DELETE RESTRICT`, unique media membership, and at most one primary variant.

### 2.3 Generation behavior

There is no `generation.generation` event stream and no generation-specific event vocabulary in v1. `record_completion` runs inside the task completion unit of work and creates the generation plus initial primary variant when the task output policy requests it.

Star/unstar, set-primary, variant metadata update, and soft-delete are small pack commands serialized through the one writer. They enforce the DDL invariants but do not append per-generation events or create a second CAS protocol. A second independent writer is the trigger to reconsider event streams; it is not anticipated for v1.

`shot_generation_items` does not exist. Existing `shots`/`shot_items` tables remain dormant and are not Reigh authority. References, evidence, and understanding surfaces are unchanged.

## 3. Capability registry and admission

### 3.1 Shipped capabilities

The code registry carries the retained flat IDs from doc 16, plus render:

| Family | Capability or capabilities | One local binding |
|---|---|---|
| `image_generation` | `reigh.wan_2_2_t2i`, `reigh.qwen_image`, `reigh.qwen_image_style`, `reigh.qwen_image_2512`, `reigh.z_image_turbo` | WGP for Wan; VibeComfy for the others |
| `image_upscale` | `reigh.image_upscale` | VibeComfy |
| `individual_travel_segment` | `reigh.individual_travel_segment` | WGP |
| `join_clips` | `reigh.join_clips_orchestrator` | WGP |
| `video_enhance` | `reigh.video_enhance` | VibeComfy |
| `z_image_turbo_i2i` | `reigh.z_image_turbo_i2i` | VibeComfy |
| `magic_edit` | `reigh.qwen_image_edit` | VibeComfy |
| `masked_edit` | `reigh.image_inpaint`, `reigh.annotated_image_edit` | VibeComfy |
| `travel_between_images` | `reigh.travel_orchestrator`, `reigh.wan_2_2_i2v` | WGP |
| `crossfade_join` | `reigh.travel_stitch` | WGP |
| `edit_video_orchestrator` | `reigh.edit_video_orchestrator` | WGP |
| `character_animate` | `reigh.animate_character` | VibeComfy |
| `klein_edit` | `reigh.flux_klein_edit` | VibeComfy |
| render/export | `rendering.timeline_visualize` | Astrid Remotion |

The worker-child allowlist is limited to the currently written local child types: `reigh.join_clips_segment`, `reigh.join_final_stitch`, `reigh.travel_segment`, `reigh.travel_stitch`, and `reigh.join_clips_orchestrator`. Each is available only when its one local binding and prerequisites pass the boot availability probe.

The active-but-dead or inactive legacy names identified in docs 16/26—including `edit_video_segment`, `edit_travel_flux`, `image_edit`, underscore `image_upscale`, `magic_edit`, and `single_image`—are rejected. There are no aliases or compatibility admission paths.

### 3.2 Registry entry

Each shipped entry contains only what runtime admission needs:

```text
capability id
frontend family
input validator / resolver
output policy
one executor binding
availability probe
optional ready_template path + digest
```

The registry does not select among bindings. Process-level Wan SHA, ComfyUI/node versions, and runtime ABI details belong in the boot manifest. A task pins only output-relevant provenance in `spec_json`: source family/type, definition version, workflow digest when applicable, and model hash.

### 3.3 Custom workflows

User-facing declarative YAML is trimmed to `{id, ports, workflow_path, digest, output_policy}`. Admission snapshots and hashes the workflow bytes and creates `local.<slug>` or uses one generic `local.workflow.run`; both feed the same generic VibeComfy handler. There is no runtime Python/plugin loading and no promotion service; moving a vetted workflow into `ready_templates` is an in-repo, restart-visible change.

### 3.4 Task identity

The kernel ULID is the task identity everywhere. Workers do not pre-generate UUID task IDs, and there is no `logical_task_id` cache or alias table. Dependency edges and deterministic child-admission keys use kernel ULIDs directly.

### 3.5 Public and executor child admission

The public R1 request is project-scoped `{family, input, materialized_inputs?, priority?}` with a required `Idempotency-Key`. Browser callers cannot request worker-child families.

An executor child request must also carry a server-validated internal envelope containing the running parent task ULID, parent attempt number, executor ID, lease ID, and current fence. Admission requires:

1. the parent is the caller's live, unexpired leased attempt;
2. the requested child is on the child-only allowlist;
3. the deterministic key is `reigh.orch:v1:<parent>:<role>:<index>`;
4. dependencies are hard edges to kernel task ULIDs; and
5. the child inherits the parent's project/run context.

This gate is executor-only. A browser request for `travel_segment` or another child family is forbidden even when the type exists in the registry.

Orchestrator parents remain `running` and heartbeat throughout child execution without occupying GPU capacity. The fenced executor replays child admissions after a crash or lost acknowledgment, observes hard dependencies, and explicitly completes or fails the parent. Structural whole-graph runs remain deferred.

### 3.6 Capability change taxonomy and conformance

**(Amended: engineering-answers judgment)**

The registry entry in §3.2 is a compiler-enforced type and the entire public/executor seam; handlers may not append executor-private fields to the wire contract. Changes use this checked-in taxonomy:

| Change | Classification | Required action |
|---|---|---|
| Executor internals, environment/tool versions, resource use, or performance with unchanged public behavior | compatible implementation change | bump the boot/build manifest and pass the existing fixtures |
| Model hash, workflow digest, or definition semantics that can change outputs | output-determinative change | bump `definition_version` as needed and pin the new output-relevant provenance on newly admitted tasks |
| Input schema, family resolution, output policy, or externally observable semantics | public contract change | reviewed resolver/contract migration; use a new capability ID only when the public I/O is genuinely incompatible |

Each shipped capability lands with a representative conformance fixture covering accepted input, completion-manifest file count/media shape, required provenance, error-category mapping, and truthful unavailability when a prerequisite is removed. Fixtures arrive with the capability in Phase A or B rather than recreating the broad all-capability Phase-A matrix. Completion provenance names the boot/build manifest hash; CI result hashes are evidence, not runtime authority.

## 4. Surviving HTTP contract

All routes share the existing bridge listener, the local-trust posture in §4.7, canonical JSON rules, receipt secrecy, media Range/ETag behavior, and timeline whole-document CAS. Existing health, discovery, project, timeline load/save, and asset routes remain frozen.

### 4.1 Route set

| Route | Purpose | Idempotency |
|---|---|---|
| `POST /projects/:slug/tasks` | Public family admission, internal fenced child admission, and render admission | required |
| `GET /projects/:slug/tasks` and `GET /projects/:slug/tasks/:task_id` | Task/progress/output reads used by polling | none |
| `POST /projects/:slug/tasks/:task_id/cancel` | Common queued/running cancellation | none |
| `POST /queue/claim` | Claim eligible work and create a leased `running` attempt | none; work or `204` |
| `POST /tasks/:task_id/attempts/:attempt_no/heartbeat` | Extend lease and carry bounded progress | none |
| `POST /tasks/:task_id/attempts/:attempt_no/complete` | Multipart files + fence + output manifest; server hashes and commits atomically | required |
| `POST /tasks/:task_id/attempts/:attempt_no/fail` | Fenced failure; server applies retry budget | required |
| `GET|HEAD /projects/:slug/media/:media_id/content` | Verified managed bytes with Range/ETag | none |
| `GET /projects/:slug/generations` | Bounded gallery page with primary variant summary | none |
| `GET /projects/:slug/generations/:generation_id` | Generation detail including its variants | none |

There is no standalone start route, outputs/staging route, render route, executor heartbeat, queue summary, or project-wide `GET /variants` in v1. Render submits through R1 using family `render_export`, resolves to `rendering.timeline_visualize`, and is observed/cancelled through the common task routes. Variant data is returned by generation detail until measured UI needs justify another read surface.

### 4.2 Claim

`POST /queue/claim` accepts `{executor_id, capabilities, lease_seconds?}`. A successful claim creates the next kernel execution attempt directly in `running` state with `attempt_id`, `attempt_no`, `lease_id`, `lease_expires_at`, and the kernel's current fence/version, then returns the task spec and resolved managed input media. No work returns `204` and writes no receipt.

Claim ordering is one global deterministic selection by priority, availability, creation time, then task ULID. `[INFERENCE]` This replaces project iteration and old model-affinity/starvation fields; `max_task_wait_minutes` is not part of the contract.

### 4.3 Heartbeat

Heartbeat accepts the current lease/fence and optional bounded progress. It extends the lease and returns the next current fence. It appends no event and writes no receipt.

The worker owns a small mutex around heartbeat versus complete/fail. Once a terminal operation begins, new heartbeats stop; the terminal call uses the last returned fence. This is the only client-side concurrency mechanism required by the protocol.

### 4.4 Complete

Complete is one `multipart/form-data` request. It carries a JSON fence/manifest part plus one or more raw output files. The server streams each file to request-scoped quarantine, computes SHA-256 itself, verifies declared size/type constraints, durably installs each verified object into CAS as specified in §5, and only then submits one completion callback to the writer.

The request does not expose `staging_txn_id`, upload URLs, or quarantine paths. A transport failure before commit leaves no authoritative rows and cleanup may remove request-scoped bytes. Replaying the same completion key returns the stored result; changed semantic input under the same key returns `409 conflict`.

### 4.5 Fail and cancel

Fail carries the current lease/fence and bounded `{code, message, retryable}` data. The server, not the worker, applies `max_attempts`, returning `requeued` or terminal `failed`. Cancel uses the common kernel cancellation service without a public idempotency-key requirement; a running cancel is fenced, while a queued/blocked cancel does not invent an executor attempt, and a repeated cancel returns the current terminal state.

### 4.6 Error surface

New build-facing errors use five public categories: `invalid_body`, `not_found`, `conflict`, `capability_unavailable`, and `payload_too_large`. Internal logs map repository-specific lease, expiry, attempt-state, and validation reasons without exposing a fence-error encyclopedia.

A `409 conflict` may include only the current attempt number, lease expiry, and current fence when that is necessary for the owning executor to stop or resynchronize. It does not return the full task/attempt model.

The existing frozen timeline errors, especially `timeline_version_conflict`, remain unchanged. The executor-only child gate may return `child_admission_forbidden`; this is a security boundary, not an attempt-state taxonomy. Unknown/dead capabilities map to `capability_unavailable` with a local setup or unsupported hint.

### 4.7 Local-trust boundary

**(Amended: engineering-answers judgment)**

Loopback and CORS are necessary but insufficient: hostile web pages, DNS rebinding, another local process, malicious archives/workflows/media, and path or parser attacks remain in scope. V1 therefore uses these low-cost controls:

1. bind only to loopback and validate `Host` against the configured loopback host and port on every request;
2. have the launcher mint a per-boot request token and deliver it out of band to the app and worker; require it on every mutation and executor-only route;
3. require a non-simple custom header on every mutation so a foreign browser origin must pass the strict CORS preflight;
4. keep application, SQLite, managed-media, quarantine, model, and setup directories mode `0700`, and secret-bearing files mode `0600`, or platform-equivalent ACLs;
5. resolve all media/archive paths through canonical confined roots; reject absolute paths, `..`, zip-slip entries, and symlink escapes; user filenames are display metadata, never authority;
6. enforce bounded request, archive expansion, JSON/YAML depth/alias, decoded-media dimension, time, memory, and output limits; and
7. allow user Comfy workflows to use only reviewed node types; workflow digests do not make arbitrary Python nodes safe.

Distribution/acquisition credentials and signing material remain in the environment/keychain, never product SQLite. The per-boot token is a local request capability, not an account, login, JWT/RLS layer, or cloud-auth surface. These controls reduce confused-deputy and cross-user risk but do not claim to defeat malicious code already running as the same OS user. An actor × vector × control × residual-risk table and hostile-page, path/symlink, archive, YAML and decode-bomb fixtures accompany the surfaces they protect. `[INFERENCE]`

## 5. Atomic completion unit of work

**(Amended: engineering-answers judgment)**

`[INFERENCE]` Crash-safe completion uses the following explicit order. SQLite COMMIT containing the completion receipt is the single irreversible **product-state** point. The byte tree may gain an invisible orphan before then, but a committed row may never point to absent or non-durable bytes.

The complete route first streams files into request-scoped quarantine and verifies server-computed hash, size and type outside the writer lock. It then durably publishes every verified object into the SHA-256 tree **before** `BEGIN IMMEDIATE`: same-filesystem temporary file, file `fsync`, atomic install-if-absent (or verify the already-existing hash object), then parent-directory `fsync`. Ordinary overwrite-style `rename` is not treated as a portable dedupe primitive. Publication is idempotent and may leave only unreferenced CAS objects after a crash.

Only after all objects are durable does the route submit one callback. That callback opens one transaction and performs:

1. receipt replay/mismatch check for the completion key;
2. current live lease/fence validation;
3. O(stat) validation that every prepared hash object is present; no copy or filesystem publication occurs under the writer lock;
4. `media`, `media_locations`, `media_relations`, and `task_outputs` writes;
5. task and attempt transition to succeeded with one winning attempt;
6. when requested, `generations` plus initial `generation_variants` creation through `record_completion`;
7. when required for addressability, the internal evented asset-registry merge against the current timeline head, without editing shot groups, pools, timing, or boundaries;
8. completion receipt write; and
9. commit.

Any failure rolls back every authoritative row. SQLite uses a demonstrated durable-commit setting (`synchronous=FULL` or an equivalent already guaranteed by the kernel). Poisoned, mismatched, missing, or over-limit bytes cannot produce a successful task or visible generation. Quarantine is request-owned and boot-swept. Unreferenced CAS objects are reported but retained until the deferred age-gated, reference-checked GC exists; Phase A does not add a media-GC subsystem.

The Phase-A crash matrix injects process death at labeled upload/hash/publish/transaction/commit/response boundaries, plus `SQLITE_IOERR`, `SQLITE_FULL`, filesystem exhaustion, replay, and concurrent identical-byte publication. After recovery and retry it asserts DB→tree totality, exactly one semantic completion per key, no partial rows, and only unreferenced tree orphans. In-lock work is O(stat), never O(copy). `[INFERENCE]`

Render completion uses the same transaction, sets `create_generation=false`, commits a primary `video/mp4` task output, and exposes it through the common media content route.

## 6. Worker client and process model

Run one local worker process beside `astrid serve`, supervised by the local launcher. The process may dispatch WGP, VibeComfy, and Astrid render handlers internally, but it uses one bridge client and one claim loop.

The bridge client implements only `claim`, `heartbeat`, `complete`, `fail`, task reads, fenced child admission, and media download. Admission/complete/fail may retry transport failures using the same key. Claim and heartbeat are re-issued as fresh operations; neither has a receipt. There is no worker registry, executor heartbeat route, queue-summary gate, phantom-claim recovery, direct database fallback, signed upload, provider handler, or cloud fleet process.

Fal and Wavespeed handlers, secrets, retries, and routing are deleted. The former `api_orchestrator` process is not ported. Local capability handlers that formerly lived under an API run type move behind the single worker's VibeComfy binding.

Process boot creates a secret-free availability manifest covering the pinned Wan build, local model hashes, ComfyUI/VibeComfy nodes, ready-template digests, Remotion/Node/ffmpeg, and disk preflight. The bridge advertises only capabilities whose single binding is available; direct calls to unavailable entries return `422 capability_unavailable` with setup guidance.

### 6.1 Model acquisition and repair

**(Amended: engineering-answers judgment)**

Setup uses a small crash-resumable journal separate from product SQLite. It is non-authoritative operational installation state and can be rebuilt by `doctor`; it is not a second product database. Each artifact follows:

```text
absent -> downloading(offset) -> verifying -> staged -> installed(verified)
                    \-> corrupt(reason) -> repairing --------------------^
```

A signed, versioned distribution manifest names content hash, byte size, license identity/text hash, supported OS/architecture, tier requirements and dependencies. Hardware/VRAM/RAM/disk discovery selects a compatible bundle before download. Downloads use HTTP Range resume; install is hash verification followed by same-filesystem stage, atomic rename and directory `fsync`. Disk preflight includes download, unpack/working and output headroom. Boot may use a stored verification stamp plus size for the fast path; `doctor` performs deep re-hash and targeted repair.

Model/node/tool acquisition in explicit setup mode is the only sanctioned outbound networking. Task execution never falls back to the network, and acceptance blocks outbound networking after setup. A capability is advertised only after the complete prerequisite closure is verified; otherwise `capability_unavailable` names `missing_prerequisites` and one actionable doctor/setup command. Kill-during-download/verify/rename, hash mismatch, disk-full and repair are setup-gate fixtures. `[INFERENCE]`

## 7. Polling and app behavior

The app polls task/progress reads every 2 seconds while any task is queued or running, every 10 seconds while idle, and the timeline every 30 seconds as a safety refresh. Admission, cancellation, and observed terminal transitions immediately invalidate task, gallery, and timeline queries. Whole-document editor saves remain optimistic and CAS-protected; worker completion never performs a public full-document save.

The gallery initially uses `GET /generations` and generation detail. Thumbnails are a later cheap local task, not a v1 schema column or Phase-A blocker. Gallery paging and document JSON byte size are measured in production-shaped fixtures; document paging or a variants-first route requires evidence.

### 7.1 Timeline document envelope and measured evolution

**(Amended: engineering-answers judgment)**

The one logical timeline document carries a strict `doc_format: 1` envelope while retaining one timeline CAS version, one load route and one save route. Unknown document formats fail closed. `[INFERENCE]` The format marker is a representation seam only; it does not authorize a second placement store, another save path, layered CAS objects, overlays or chunks in v1.

A parametric production-shaped generator varies shot/clip count, pool generations, registry entries, boundary overrides and undo depth. On both supported tiers it records document bytes, parse/serialize time and peak memory, save/merge p50/p95/p99, writer occupancy, undo memory, and CAS conflict/clobber outcomes under concurrent editor saves and registry merges. Registry pruning at save remains behind measurement: it may be enabled only if registry growth is the observed constraint and a test proves each removed entry is unreachable from the current document and retained undo/history. Media bytes are never deleted by this prune.

### 7.2 Performance envelope

**(Amended: engineering-answers judgment)**

The availability matrix names two supported reference tiers—`floor` and `comfortable`—by concrete benchmark-machine manifest. The following are provisional floor-tier p95 budgets, all `[INFERENCE]` until Phase A baselines promote or adjust them:

| Surface | Provisional floor-tier budget | Provisional comfortable-tier budget |
|---|---|---|
| launcher start → interactive UI | ≤3 s; capabilities appear only as their probes finish successfully | ≤3 s |
| admission → claim with idle worker | ≤1 worker-loop iteration, initially 1 s | ≤1 worker-loop iteration |
| active progress freshness | ≤3 s | ≤3 s |
| ordinary writer transaction / completion transaction | ≤50 ms / ≤250 ms | same ceiling; record separate baseline |
| sustained writer occupancy | `<20%` | `<20%` |
| editor save | ≤150 ms typical fixture; ≤1 s reference-ceiling fixture | same ceiling; record separate baseline |
| gallery page | 50 items from 10,000 generations in ≤200 ms | ≤200 ms |
| render admission → first progress | ≤10 s | ≤10 s |
| managed-MP4 first byte | ≤500 ms via Range | ≤500 ms |
| expired lease → reclaim | ≤2× configured lease duration | ≤2× configured lease duration |
| disk reserve | warn at 85% of configured cap; refuse before required output headroom is lost | same percentage/headroom rule |

Generation/render duration itself remains capability- and hardware-dependent. The benchmark corpus combines the document generator, small/medium/large project fixtures and the Phase-A journey; timings stay local and are surfaced by `doctor`. Release budgets are enforced only on controlled tier machines. The two tiers initially share user-visible ceilings rather than inventing unsupported “comfortable” speedups; their separate baselines may justify distinct targets later.

Backpressure has exactly three verbs: **refuse** with an exact remedy when correctness or resource feasibility is at stake (disk/VRAM/hard document or artifact limit); **degrade** only fidelity (preview/thumbnail work); **queue** when only time/capacity is at stake. No silent truncation or GPU thrash is permitted.

## 8. Phase A vertical-slice exit criteria

Phase A ships one production-shaped `wan_2_2_t2i` generation plus one `rendering.timeline_visualize` render through the contracts above. It must demonstrate:

1. local availability gating and a useful missing-model/node/ffmpeg setup response;
2. admission receipt replay and changed-payload conflict;
3. claim directly into a leased running attempt;
4. heartbeat progress and expiry after worker death;
5. fence rejection for an expired or superseded attempt;
6. multipart completion replay after a lost acknowledgment;
7. poisoned, truncated, hash-mismatched, and disk-failure output rejection with no partial rows;
8. cancellation of queued and running work;
9. atomic media + task + generation/variant publication;
10. concurrent editor save versus internal registry merge without document clobbering;
11. 2-second active polling visibility;
12. managed MP4 Range/ETag playback in the browser; and
13. operation with Supabase and outbound-provider networking blocked.

**(Amended: engineering-answers judgment)** Phase A is signed off by a declarative fault schedule and evidence table, not a happy-path recording. The real browser/editor journey is t2i → gallery → editor CAS placement → Remotion render → Range/ETag playback, with a concurrent save storm. It includes the §5 crash/IO/full-disk matrix, worker death and reclaim, `astrid serve` restart, cancel-during-publication, dropped acknowledgments, idempotency mismatch, hostile local-trust fixtures, setup interruption/repair, the floor-tier document/performance baseline, and OS-level blocking of Supabase/provider/task-execution networking. A bridge harness supplements but does not replace browser playback and document-save acceptance. Exact repetition counts and stop/go latency thresholds remain `[INFERENCE]` until the first baseline; any DB/tree disagreement, duplicate semantic completion, stale-fence acceptance or silent document clobber is an unconditional stop.

Join/travel payload and graph fixtures are not Phase-A gates. They move to Phase B with the handlers they validate. The old broad A–N/T1–T12 matrices are historical coverage inventories, not day-one release gates.

## 9. Later build scope

### Phase B — remaining local capabilities and orchestrator children

Enable retained capabilities only after their single local binding passes availability checks. Add join/travel/edit orchestrator behavior with leased parents, executor-only deterministic child admission, hard dependencies, crash replay, explicit parent completion, and their production-shaped fixtures. Add the trimmed custom-workflow YAML/snapshot path and generic VibeComfy handler.

**(Amended: engineering-answers judgment)** Orchestrator child identity and admission receipt semantics are attempt-independent: `reigh.orch:v1:<parent>:<role>:<index>` never includes attempt number, lease or fence. `derive_children` produces a deterministic identity/plan skeleton from the immutable parent spec; current fence data authorizes effects but is excluded from idempotency comparison. Phase-B exit requires a checked transition table, key lint, plan-purity test, and deterministic-scheduler interleavings covering lease expiry mid-fan-out, lost admission acknowledgment, crash between children, cancellation during replay, zombie/new-attempt races, and restart during parent settlement. The result must be one planned child per key and one parent terminal transition.

Wan2GP changes pass five gates: (1) hermetic rebase/patch application, (2) path/import/config contract tests, (3) dependency resolution on every supported platform, (4) unchanged conversion fixtures, and (5) a fixed-seed representative output-shape and semantic-diff corpus. Gates 1–4 reject mechanically; gate 5 requires human review outside demonstrated deterministic tolerances. Rollout drains WGP work, swaps the sole binding/build manifest, and retains one bounded prior build for pointer-and-restart rollback. Phase B includes an N→N+1→N rollback drill and verifies queue, output and manifest provenance integrity. `[INFERENCE]`

### Phase C — application cutover and release

Replace retained Supabase/edge/realtime/storage calls with bridge domain clients; ship focused document-native shot mode, always-copy media, setup/doctor, backup/restore, and bridge-only local supervision. Acceptance runs with Supabase and outbound-provider networking blocked, then legacy product code paths are retired. There is no importer, rollback window, cloud-data destruction phase, or operator dump in this journey.

**(Amended: engineering-answers judgment)** Phase C also proves SQLite + managed-tree + hash-manifest backup/restore round trip and runs the calibrated performance budgets on both controlled reference tiers.

## 10. Deferred and explicitly untouched

Deferred: remote workers, TLS/auth transport, SSE, queue summary, executor registry, `GET /variants`, thumbnail tasks, document paging, structural orchestration runs, hard-delete/media GC, link-in-place media, runtime workflow promotion, multiple bindings, and provider fallback.

Untouched: references, evidence, understanding, existing kernel hash-chained events, kernel ULIDs, the single-writer UoW, backup/restore primitives, and frozen timeline bridge routes. Do not use table-count assertions or dynamic-pack/plugin laws as a Reigh release gate; update concrete schema expectations when implementing migration v2.

Attempt quota, request size, lease duration, and expiry cadence are boring configurable code defaults, not frozen wire constants. Begin with conservative local values and adjust from measured WGP/render artifacts. `[INFERENCE]`

**(Amended: engineering-answers judgment)** Seven option-preserving invariants govern future proposals:

1. media authority crosses the wire as stable ULID/hash identity, never a filesystem path or storage URL;
2. admitted task specs remain immutable and receipts plus output/build provenance remain replayable;
3. every authoritative product mutation uses the one writer queue, while existing meaningful kernel/timeline event contracts remain intact—setup-journal transitions are operational installation state, and simple generation mutations do not gain a new event vocabulary;
4. each timeline retains one CAS version and one save/load contract, with `doc_format` as the representation seam;
5. backup/restore remains a tested SQLite + managed-tree + manifest pair;
6. kernel ULIDs, idempotency keys, leases and fences remain transport-neutral wire semantics, without building a non-loopback transport or test surface in v1; and
7. the per-capability conformance suite defines a compatible executor behind the one current binding.

Every proposed abstraction must name the invariant row it protects and the current file/API/test that would otherwise become expensive to change. No row means no abstraction. This rule does not justify plugin ABIs, alias tables, placement normalization, generic entity/SQLite layers, multi-binding selection, remote-worker scaffolding or new event machinery.

## 11. Source map

- Binding constitution: docs 15, 24, 25, and `grok/second-opinion-decisions.md`.
- Simplification judgments: `grok/simplicity-review.md` and doc 22 §1.
- Historical capability/payload evidence: doc 16.
- Historical DDL and completion detail: doc 17.
- Frozen bridge conventions and historical route design: docs 09 and 18.
- Historical worker transport inventory: doc 19.
- Supporting recommendations and gaps: docs 20, 21, 23, and 26.
- Engineering response comparison and adopted `[INFERENCE]` amendments: doc 28.
