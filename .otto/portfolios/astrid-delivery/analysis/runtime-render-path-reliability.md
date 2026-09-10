> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Runtime/render-path reliability — boundary and sequencing report

Research date: 2026-09-10. This is a read-only planning report. No runtime,
database, service, branch, worktree, test, or product file was changed. “Present
in source” below is not the same as “implemented by this run” or “passing
evidence”.

## 1. Purpose and concrete before/after user impact

The project repairs the final path from an explicitly focused project/timeline to
an opened render while retaining Runtime ownership, immutable CAS, managed upload,
fenced settlement, launcher ownership, and the digest-addressed cache. The
before/after contract is:

| Before / observed failure | Intended after |
|---|---|
| Deep doctor hashes large CAS content while holding the serving SQLite mutex, making health and ordinary calls appear unavailable. | Cheap liveness/readiness remains responsive; unbounded integrity/CAS work is explicit offline work against a stopped realm or consistent snapshot. |
| A recovered realm can be manually started and answer direct requests, yet normal launcher discovery rejects it because ownership/discovery identity does not match. | One verified activation operation preserves the original and backup, fences any prior owner, starts through normal launcher ownership, and proves discovery plus normal client access before promotion is complete. |
| The user-facing resolver can be unavailable or can inherit an unrelated global project; “latest” then selects the wrong project’s render. | CLI, SDK, and UI resolve an explicit project and optional canonical timeline; latest is newest successful `rendering.render` only inside that scope. |
| A valid MP4 can be opened as an extensionless CAS object. Historical object metadata may say `video` even though task provenance has `minkhole-review-v13.mp4`. | Output port (`video`), managed object/digest, filename, and media type remain distinct. The verified object is atomically materialized under the real filename and only that path is passed to the OS opener. |
| Existing QuickTime state can be mistaken for proof that the requested render opened. | The result says “open requested” unless target-document evidence exists; an `open` request is not claimed to prove playback. |

The run’s North Star is one boring path: explicit scope → Runtime render task →
attempt-local staging → managed upload → fenced settlement → scoped resolution →
verified named materialization → exact opener path
([northstar.md](../handovers/render/northstar.md)).

## 2. Current status, source identity, and custody

The package is planning-only and marked ready for delivery authorization; no
implementation or tests were launched
([status.md](../handovers/render/status.md);
[agent_goal.md](../handovers/render/agent_goal.md)).
The tasklist is RRP-01 trace, then diagnostics and recovery (RRP-02/03), scoped
resolution and publication identity (RRP-04/05), materialization/open reporting
(RRP-06), and final end-to-end cleanup/regression (RRP-07)
([tasklist.md](../handovers/render/tasklist.md)).

Recorded Astrid source is `<workspace>/Astrid`,
branch `main`, setup HEAD
`82d09bb91c8a4621695c1d8b6966652cad941ef4`, captured 2026-09-10. It is heavily
dirty and the setup explicitly treats tracked and untracked work as user-owned
planning context (source-state.md (original source reference: `<workspace>/Astrid/.otto/runs/runtime-render-path-reliability-20260910/source-state.md:1-14`)).
The current checkout still has broad modifications, including
`generic_host.py`, `invocation.py`, `host_bootstrap.py`, `workspace_client.py`,
timeline/render files, and tests. Custody must be reconciled before delivery;
the RRP package itself created no isolated worktree.

The runtime implementation relevant to recovery is a different dirty checkout:
`<workspace>/banodoco-workspace-runtime-execution-20260909`,
branch `codex/canonical-timeline-replacement-20260909`, HEAD
`afccb430e2a983c968b6a8a96fd630ba3a6262fc`. Its dirty files include
`runtime_protocol/backup.py`, `service.py`, `daemon.py`, `server.py`, `store.py`,
`catalog.py` callers, generated clients, and migration tools. This is observed
source, not delivery custody; the clean-break report also requires rechecking
both identities before T1.

The Astrid tree already contains tracked `astrid/sdk/project_render.py` and
`tests/sdk/test_project_render.py` at the recorded HEAD. They implement much of
the desired shape, but are static source evidence only: no run evidence says
these tests passed, and RRP-01 must establish whether they are prior user work,
an incomplete repair, or the intended baseline.

## 3. Scope, boundaries, owned contracts, and invariants

In scope is the existing Runtime/CAS/settlement and its launcher-facing recovery
seams; explicit project/timeline selection; one SDK/CLI/UI render-opening concept;
output identity propagation; verified digest/size materialization; truthful OS
open reporting; and the exact Minkhole-vs-Astrid-Intro regression. The plan names
the known artifact as project `Matrix — Into the Minkhole`, project ID
`7f362daea1f048969980ef23f0cd46e6`, run `e3aaf311c17b450198d1c2d6f1582887`,
digest `sha256:4774f5bb04cf4e25e6b514f372517e6b2ff05b7e1d20aa1014ffe6d28c53477c`,
filename `minkhole-review-v13.mp4`, 11,288,161 bytes
([plan.md](../handovers/render/plan.md)).

Keep: Runtime authority, immutable CAS, attempt staging, managed upload, fenced
settlement, explicit timeline scope, digest cache, launcher ownership, and
existing identity/fence/receipt mechanisms. Remove or defer: user-facing direct
DB/CAS fallback, a second render registry, manual-runtime adoption, online deep
audits, cache registries, historical migration/backfill, playback automation,
and generation/variant domain expansion
([plan.md](../handovers/render/plan.md)).

Owned invariants are C1/C2 non-blocking diagnostics and offline audit; C3
exclusive launcher-owned recovery; C4 exact project/timeline selection; C5
attempt-local → upload → fenced settlement; C6 separate port/object/filename/
media metadata; C7 verified SHA-256 and size before atomic publication; C8 exact
opener path and truthful status; C9 the decisive scoped regression; and C10 no
direct DB/CAS or manual-runtime supported fallback
([implementation-criteria.md](../handovers/render/implementation-criteria.md)).

## 4. How it runs: entry points, flow, state, failure, publication

### Recovery, readiness, and launcher boundary

Current runtime startup constructs `RuntimeService`, provisions owner/worker
credentials, starts HTTP, registers the realm, writes owner-lock state, publishes
discovery, then serves (`runtime_protocol/daemon.py:38-109`). Stop shuts down the
HTTP server, clears discovery only for its own instance, and closes the service
(`runtime_protocol/daemon.py:111-119`). `RuntimeService` currently opens a
strict-admission store, calls doctor during startup, begins a runtime session,
and marks itself verified (`runtime_protocol/service.py:219-249`). Its `doctor()`
holds `store._mutex`, and `health()` calls doctor synchronously
(`runtime_protocol/service.py:272-322`); this is the direct RRP-02 concern.

Backup restore already verifies an authenticated source, copies SQLite/CAS into a
fresh inactive candidate, writes an authenticated `activation-handoff.json`,
fsyncs, and atomically renames the candidate into place
(`runtime_protocol/backup.py:659-732`). `verify_restore_candidate()` is designed
to run immediately before activation/reuse and rejects altered or incomplete
candidates (`runtime_protocol/backup.py:450-500`). The missing RRP-03 seam is
coordination around this: prior-owner shutdown/conflict, catalog pointer switch,
fresh credentials/epoch, interruption recovery, normal launcher start, and
discovery verification.

`RealmCatalog.register()` and `select()` each read then write, but their lock does
not span the full read-modify-write (`runtime_protocol/catalog.py:61-125`).
`LiveDiscovery` is ephemeral and deliberately path/secret-free in its allowed
fields (`runtime_protocol/catalog.py:128-163`). Runtime server task admission
checks readiness inside the owner transaction, not in a racy client precheck
(`runtime_protocol/server.py:430-442`). RRP must consume the clean-break T4/T5
contract here rather than add a parallel adoption/discovery mechanism.

### Render opening and selection flow

The public CLI is `python3 -m astrid runs open [RUN_ID]`; it permits optional
`--project`, mutually exclusive `--timeline` or `--default-timeline`, and makes
exactly one `client.runs.open` call (`astrid/core/cli/domain_runs.py:29-38,116-123,182-206`).
The rendering skill documents the supported commands and says opening is macOS
only (`astrid/packs/rendering/skill/SKILL.md:195-224`). `RemoteRuns.open()` forwards
the selected arguments to `open_project_render()` (`astrid/sdk/remote.py:425-446`).

The current resolver first uses explicit project or `current_project()`; resolves
timeline slug/id through project-scoped listing; filters successful
`rendering.render` runs; sorts by timestamp/id; checks run/task timeline
provenance; requires exactly one successful render task and exactly one named
`video` output; then matches the digest to project-owned objects
(`astrid/sdk/project_render.py:105-272`). It downloads bytes through the runtime
object surface, hashes them and checks expected size, selects task `output_name`
before a valid media filename, materializes under digest/filename, and calls
`open <exact-path>` (`astrid/sdk/project_render.py:273-308`). This is the intended
flow’s current source implementation, but it lacks proven execution evidence and
still returns `opened=True` after merely issuing the OS request.

Materialization currently uses `cache_root/<digest>/<basename>` and an atomic
temporary-file replace (`astrid/sdk/project_render.py:79-102`). Cache reuse checks
the digest but not an independently recorded size; the downloaded path validates
size before materialization. The implementation should make C7 explicit for both
fresh and reused cache entries, and validate media type rather than relying solely
on the `video` port.

### Generation/render output publication boundary

The render executor allocates `{out}/{output_name}` and declares `video` and
`provenance` output ports (`astrid/packs/rendering/executors/render/executor.yaml:19-27,180-205,252-269`).
The renderer writes a universal manifest whose `video` entry names the concrete
output path and whose manifest input records `output_name`
(`astrid/packs/rendering/executors/render/run.py:190-237`). The shared harvester
uses manifest `name`/`port` identity and never guesses from filename/suffix;
required media outputs must have a receipt (`astrid/core/_shared/result_manifest.py:610-660`).

The exact loss boundary is in the host/runtime handoff. `_typed_outputs()` keeps
port name, artifact type, digest, size, staged path, role, ordinal, and primary
flag, but not filename (`astrid/core/execution/generic_host.py:2044-2105`).
`_upload_outputs()` does pass `path.name` as `filename` to `upload_object()`, yet
the settlement-safe descriptor it returns omits filename
(`astrid/core/execution/generic_host.py:2286-2347`). `client.settle()` sends
those descriptors in one fenced settlement envelope
(`astrid/core/execution/generic_host.py:1077-1093`).

The runtime currently accepts only output fields `name`, `kind`, digest,
`media_type`, size, ordinal, role, primary, and duration; it normalizes the
output without filename (`runtime_protocol/service.py:2735-2866`). On publication,
it inserts `item["name"]` into `objects.original_name`, so the `video` port becomes
the generic object name `video` (`runtime_protocol/service.py:3085-3123`). The
runtime object read model does expose `filename` from `original_name`
(`runtime_protocol/service.py:2097-2141`), explaining the historical extensionless
object. RRP-05 should preserve actual filename separately and use producing task
provenance only as the bounded fallback for historical `original_name='video'`.

This is also the precise generation overlap. The generation report identifies the
same host `_upload_outputs`/settlement convergence as its explicit T3 surface and
requires managed output identity/provenance through settlement
([generation-path-alignment.md](generation-path-alignment.md)).
Generation must consume one settled descriptor contract and retain filename/media
identity, but RRP must not expand into generation/variant persistence. The
ephemeral-artifact dependency owns generic output-intent/lifecycle metadata, not a
second path or event authority ([tasklist.md](../handovers/ephemeral/tasklist.md)).

## 5. Touch map

| Exact repository/file/symbol | Intended change | Consumer | Overlap; confidence |
|---|---|---|---|
| Astrid `astrid/sdk/project_render.py:105-308` (`open_project_render`) | One scoped resolver/materializer/open operation; enforce project/timeline provenance, digest+size, filename/media type, and truthful open status. | SDK `RemoteRuns`, CLI, future UI | **Explicit RRP-04–06.** RRP-owned, but shared semantics with timeline filmstrip resolver/cache. |
| Astrid `astrid/sdk/project_render.py:42-102` (`_output_name`, `_materialize`) | Preserve task output filename; secure basename; verify cache reuse by digest and size; atomically publish named file. | `open_project_render` | **Explicit RRP-05/06.** Do not generalize into a second cache registry. |
| Astrid `astrid/sdk/remote.py:425-446` (`RemoteRuns.open`) | Keep one facade call and explicit arguments. | CLI/client users | **Explicit RRP-04.** Same SDK file as generation public family, semantic only. |
| Astrid `astrid/core/cli/domain_runs.py:116-206` | Keep parser-backed `runs open` project/timeline contract and one SDK call. | Product CLI | **Explicit RRP-04.** Same family is stable; serialize if changing flags/help. |
| Astrid `astrid/core/execution/generic_host.py:2044-2105,2286-2347,3020-3029` | Carry filename and media identity as distinct settlement fields while retaining named manifest/port, digest, size, role, ordinal. | All hosted render/generation tasks | **Explicit RRP-05; explicit generation T3 overlap.** Same file and semantic collision; one owner/integration gate. |
| Astrid `astrid/core/_shared/result_manifest.py:610-760` | Preserve strict receipt/port identity; add only minimum filename/output-intent field required by settled publication. | Generic host and all producers | **Inferred shared contract.** Coordinate with lifecycle E2-01; no lifecycle implementation. |
| Astrid `astrid/packs/rendering/executors/render/run.py:190-237`, `executor.yaml:19-27,252-269` | Ensure manifest’s concrete `output_name` survives host harvest without conflating it with `video` port. | Canonical render executor | **Explicit RRP-05.** Same publication semantics as generation producers, local files mostly disjoint. |
| Runtime `runtime_protocol/service.py:2491-2563,2735-2866,3085-3123` | Accept/validate/persist filename as distinct output metadata; retain staged/CAS/fenced transaction behavior. | Host settlement, task/run readers | **Explicit RRP-05; DB T3/T6 protocol overlap.** Runtime source ownership belongs to clean-break/runtime contract owner. |
| Runtime `runtime_protocol/backup.py:450-500,659-732` | Reuse verified candidate and add coordinated activation/recovery around it. | Runtime operator/launcher | **Explicit RRP-03; clean-break T4.** Same runtime files/transaction boundary; serialize. |
| Runtime `runtime_protocol/catalog.py:61-163`, `daemon.py:38-119` | Full catalog RMW and admitted-owner discovery/readiness publication; launcher-owned activation. | Local launcher/bootstrap | **Explicit RRP-03; clean-break T5.** Same files and semantic dependency. |
| Runtime `runtime_protocol/service.py:272-322` | Split cheap health/readiness from deep doctor/CAS verification. | Health/doctor callers | **Explicit RRP-02; clean-break T3/C1.** Same service mutex/admission semantics. |
| Astrid `tests/sdk/test_project_render.py:1-225` | Expand exact Minkhole/Intro, output filename, digest/size, media type, cache reuse, opener status tests. | SDK/CLI CI | **Explicit RRP-04–07.** Existing tests are source definitions, not passing evidence. |
| Runtime tests around `backup`, `catalog`, `daemon`, `service` | Add owner conflict, interruption, restart, stale discovery, readiness and replacement proofs. | Runtime CI | **Explicit RRP-02/03.** Must use disposable realms/catalogs and clean-break fixtures. |

## 6. Dependencies, parallelism, and serialization

The RRP task dependency is RRP-01 → RRP-02/03/04/05 → RRP-06 → RRP-07
([tasklist.md](../handovers/render/tasklist.md)).
RRP-01 is read-only and can run alongside other projects’ source maps. After it
freezes exact ownership, diagnostics (RRP-02), activation (RRP-03), resolver
(RRP-04), and filename trace (RRP-05) can proceed in parallel only with explicit
file owners.

Must serialize or gate:

1. **Runtime clean-break T3 before settlement edits.** RRP-05 depends on the
   settled admission/receipt/CAS contract. Do not change runtime service/store
   settlement fields against the dirty runtime checkout while clean-break T3/T6
   is still reconciling lifecycle ownership.
2. **Clean-break T4/T5 before RRP-03 integration.** T4 owns verified replacement,
   owner shutdown, fresh credential/epoch and interruption recovery; T5 owns
   catalog full-RMW and admitted-owner readiness/discovery. RRP-03 is a consumer
   of those contracts, not an alternate activation path.
3. **Host publication identity is a single-owner seam.** Generation’s host T3,
   timeline visualization’s host/cache receipt work, and RRP-05 all intersect
   `_typed_outputs`, `_upload_outputs`, settlement, and generated clients. Same-file
   collisions and semantic schema conflicts require one coordinated change and
   one regenerated client surface.
4. **RRP-04 before RRP-06.** Materialization/open must receive the final scoped
   resolver output and final filename identity; otherwise it can accidentally
   reintroduce global/current-project or path authority.
5. **RRP-07 last.** Run the decisive Minkhole regression only after diagnostics,
   launcher activation, settlement metadata, resolver, and materializer contracts
   are integrated. Do not use an existing QuickTime window as acceptance evidence.

Safe parallel chunks after contracts freeze are (a) resolver negative tests and
CLI plumbing, (b) host/manifest filename trace with generation owners, (c)
disposable runtime recovery/catalog fixtures, and (d) documentation/deletion
census. “Parallel” here means disjoint files or read-only investigation; shared
runtime service, generic host, generated clients, and recovery tests remain
serialized.

## 7. Validation and acceptance gates

No executable acceptance evidence exists in this planning package. Required gates:

| Gate | Required proof |
|---|---|
| RRP-02 / C1–C2 | Health, ordinary doctor, project read, and representative write remain responsive while deep CAS verification runs only offline/stopped/snapshot; corruption is detected without source mutation. |
| RRP-03 / C3 | Candidate verification, original/backup retention, prior-owner conflict/shutdown, fresh credential and runtime epoch, restart, interrupted activation recovery, normal launcher discovery, and normal CLI access all pass on disposable roots/catalogs. |
| RRP-04 / C4/C10 | With Astrid Intro globally selected and Minkhole explicitly focused, latest selects only the focused project/timeline; missing/conflicting provenance, foreign project/run, absent timeline, and unsupported fallback fail typed and before download/open. |
| RRP-05 / C5–C6 | Manifest `video` port, managed object/digest, actual output filename, media type, size, role/ordinal, and provenance survive staging → upload → settled task/object read. Historical `original_name='video'` resolves boundedly from task `output_name`; no migration/backfill. |
| RRP-06 / C7–C8 | Downloaded bytes match digest and size; invalid filename/media type is rejected; cache reuse is independently verified; temporary publication is atomic; opener receives exactly digest-cache `.../minkhole-review-v13.mp4`; result reports request, not playback. |
| RRP-07 / C9 | Exact run/digest/size/path for the known Minkhole artifact, never Intro or raw CAS; affected suite green; fallback/deletion census documented. |

The current test file already exercises latest successful selection, cross-project
rejection, ambiguous video outputs, tampered download, explicit project override,
current-project absence, default timeline provenance, and selector conflicts
(`tests/sdk/test_project_render.py:54-225`). These are useful evidence definitions
but have not been run by this setup. They do not yet prove the real Minkhole
identity, historical `video` filename fallback, media-type validation, cache-size
reuse, or truthful “open requested” status.

## 8. Recommendations to Astra and remaining uncertainties

Recommend Astra make the clean-break runtime owner canonical for T4/T5 and treat
RRP-03 as a thin launcher integration. It should not accept a manually running
realm merely because direct HTTP works; promotion requires ownership, catalog,
readiness, discovery, fresh epoch/credentials, and normal launcher access.

For publication, assign one owner for the host/result-manifest/generated-client
contract. Preserve the existing strict receipt and fenced settlement; add only a
distinct filename field (and, if needed, explicit output intent) rather than
making `name='video'` carry both port identity and filename. Generation consumes
the same contract, while RRP remains limited to render opening and materialization.

Before delivery, check: (1) exact authoritative runtime checkout and dirty-diff
custody; (2) whether runtime API can return filename/media type for historical and
new objects without a migration; (3) whether `output_name` is always present in
the admitted task spec or requires a bounded fallback rule; (4) whether the
launcher has an existing activation/recovery seam outside this checkout; (5)
whether health/readiness can be separated without weakening admission; and (6)
whether the generic host’s current dirty modifications are generation/timeline
work that must be preserved before RRP publication edits.

The principal sequencing conclusion is: finish/freeze clean-break T3, then
serialize T4/T5 runtime activation/readiness contracts before RRP-03; coordinate
one host/output metadata change with generation T3 and generated-client work;
implement scoped resolver/materializer only after that contract; and reserve the
Minkhole/Intro test for the final integrated gate.
