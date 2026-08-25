# Reigh + Astrid: one authority, one bridge

> **CURRENT JOURNEY PLAN. (Amended: Grok review — judged ADOPT/MODIFY; Amended: engineering-answers judgment.)** The ratified constitution is docs 15, 24, 25, and `grok/second-opinion-decisions.md`. `27-build-spec.md` is the sole working build contract; doc 28 records the engineering-answer judgment that amends this journey; older detailed specs are historical evidence.

## 1. Judgment on Grok's ten items

**(Amended: Grok review — judged ADOPT/MODIFY.)** Verdicts are binding for this plan but do not silently override the ratified constitution.

| # | Verdict | Judgment |
|---|---|---|
| 1 | **ADOPT** | Fresh start already excludes importer and rollback authority, so removing live-production archaeology as journey work refines rather than changes the ratified decision. Phase A begins with a local availability matrix and a short code-based completion-effects note; doc 11 v10 scripts and doc 13 §§8–11 remain historical evidence, with no operator dumps, exporter, audit JSONL, or 14-day rollback in this plan. |
| 2 | **ADOPT** | On one host, crash-safe completion needs a leased attempt, expiry, heartbeat progress, terminal fencing, and an atomic commit—not separate claimed/start/staged states. The protocol becomes claim directly to leased `running`, heartbeat, multipart complete, and fail; the child-admission hard gate and the heartbeat-versus-terminal mutex remain load-bearing. |
| 3 | **ADOPT** | This reaffirms the already-ratified current doc 26 posture rather than replacing it: flat `reigh.<normalized>` IDs, one binding, snapshots plus `ready_templates`, trimmed YAML, no runtime plugins, and dead-type rejection. The surviving rules are consolidated in doc 27 so doc 26 no longer competes as a build spec. |
| 4 | **ADOPT** | A local product benefits more from one coherent contract than from repeatedly reconciling consultation artifacts. Doc 27 is now the sole working build spec; docs 16–19 and 20/21/26 are clearly labeled historical, while this document carries only the A/B/C journey. |
| 5 | **ADOPT** | Gallery correctness requires two relational tables, one-primary, media pinning, soft delete, and task-completion atomicity. It does not require a per-generation hash-chained stream or receipt for every star toggle, so `record_completion` lives inside task completion and the remaining mutations are small writer-serialized pack commands. |
| 6 | **MODIFY** | Adopt the smaller executor surface: idempotency keys only on R1 and complete/fail, no keys on claim or heartbeat, five new-route error categories, and minimal fence extras. Preserve the already-frozen timeline/CAS error vocabulary and an explicit child-admission boundary instead of renaming stable contracts or obscuring the executor-only security gate. |
| 7 | **ADOPT** | Fully local compute makes the API-orchestrator Fal/Wavespeed path dead code, while lease heartbeat already supplies attempt liveness. V1 runs one worker process beside `astrid serve`; executor heartbeat and queue summary are deferred, and local logs plus supervision replace fleet observability. |
| 8 | **ADOPT** | Kernel ULIDs are sufficient for tasks and dependencies, eliminating the UUID/ULID map and logical-ID cache. Child families remain executor-only and fenced; legacy contract blocks unread by handlers are dropped `[INFERENCE]`, while load-bearing `orchestrator_details` remains. |
| 9 | **ADOPT** | Day-one evidence should prove the architecture, not every future handler. Phase A covers one production-shaped `wan_2_2_t2i` path plus missing-model, replay, fence, crash/expiry, poisoned-output, and cancel; join/travel graphs move to Phase B with their implementations. |
| 10 | **ADOPT** | Render uses R1/R2 and common task cancellation; variants remain embedded in generation detail, the shots pack stays dormant, and references/evidence remain untouched. Table-count gates, frozen size constants, Phase-A thumbnails, and speculative document paging are removed; boring code defaults and measurement replace premature design. |

## 2. End state

**(Amended: Grok review — judged ADOPT.)**

```text
Reigh browser/editor
  │ HTTP: domain admission/reads, timeline CAS, media
  ▼
astrid serve on loopback
  │ every mutation through one writer queue
  ├── Astrid SQLite: sole structured authority
  └── SHA-256 managed media tree: authoritative bytes
  ▲
  │ claim / heartbeat / multipart complete / fail
one same-host local worker
  ├── WGP
  ├── VibeComfy
  └── Astrid Remotion render
```

The browser admits by frontend `family`; the bridge resolves a flat capability with one installed local binding. The worker claims directly into a leased running attempt, reports progress through heartbeat, and atomically completes bytes, task/output state, and optional generation/variant state. Shot placement remains in the timeline document, and render is an ordinary Astrid task whose managed MP4 is played through the media route.

## 3. Guiding rules

**(Amended: Grok review — judged ADOPT/MODIFY.)**

- One SQLite database, one managed media tree, one bridge listener, and one writer queue.
- Fresh start: no importer, exporter, replay layer, rollback authority, operator production dump, or legacy-data release phase.
- Fully local compute; unavailable models/nodes/Remotion prerequisites produce setup guidance, never cloud fallback.
- Flat capability names, one binding per capability, no aliases, no wildcards, no runtime plugins.
- Kernel ULIDs are task identity. `family` is the frontend key; capability IDs remain behind admission.
- Leased orchestrator parents heartbeat and exclusively admit allowlisted children with deterministic keys and hard dependencies.
- Generations/variants are rows; placement is the CAS-versioned timeline document. Workers never save the editor document.
- Always-copy media, server-computed SHA-256, atomic completion, and Range/ETag delivery.
- Poll at 2 seconds active, 10 seconds idle, and 30 seconds for timelines. No SSE.
- Preserve existing kernel events/ULIDs/single-writer mechanics and frozen timeline bridge errors; simplify only the new Reigh task surface.

**(Amended: engineering-answers judgment)**

- Completion durably publishes verified CAS objects before `BEGIN IMMEDIATE`; the receipt-bearing COMMIT is the only irreversible product-state point, and only invisible byte orphans are permissible after a crash.
- The launcher supplies a boot-scoped local request capability; Host/custom-header checks, restrictive data permissions, path/parser limits, and a reviewed Comfy node allowlist harden loopback without accounts or tenancy.
- Model acquisition is journaled outside product SQLite and is the sole setup-only outbound-network exception; generation and render never use an outbound fallback.
- The timeline remains one logical document/version/save route; `doc_format` is a representation seam, and registry pruning or chunking requires measurements.
- Capability changes use the checked taxonomy and per-capability fixtures in doc 27 §3.6; no plugin ABI, binding selector, or extra version field is implied.
- Performance is measured on named floor/comfortable tiers; writer occupancy and `refuse/degrade/queue` are explicit release policy.

## 4. Phase A — vertical slice: local t2i plus render

**(Amended: Grok review — judged ADOPT/MODIFY.)**

### Goal

Prove the complete local architecture with the smallest production-shaped path before broad capability or UI cutover work.

### Work

1. Produce a code-based completion-effects note describing what the current completion path writes; do not inspect or dump live production as journey work.
2. Produce a local availability matrix for the pinned Wan build, models, nodes, VibeComfy/ComfyUI, Node/ffmpeg/Remotion, and disk preflight.
3. Add only `generations` and `generation_variants` with the retained DDL invariants; implement `record_completion` inside task completion without generation streams.
4. Implement the minimal R1/R2/claim/heartbeat/multipart-complete/fail/cancel/media/generation-read contract from doc 27 and the internal lease-expiry loop.
5. Run one worker process beside `astrid serve`; remove all Phase-A dependency on Supabase, provider APIs, API orchestrator, queue summary, or executor registry.
6. Carry one real `wan_2_2_t2i` request from editor admission to managed output and gallery row.
7. Admit `render_export` through R1, execute `rendering.timeline_visualize`, observe through R2, and play the managed MP4 in the browser.
8. Wire 2-second active polling and immediate invalidation on admission, cancellation, and terminal observation.

**(Amended: engineering-answers judgment)**

9. Implement the pre-transaction durable CAS publication order and labeled crash/IO/full-disk/retry/dedupe invariant checker from doc 27 §5.
10. Add the separate setup journal/state machine, signed artifact manifest, resumable verified install, doctor repair, and setup interruption fixtures from doc 27 §6.1.
11. Add the local-trust gate and hostile-page/path/archive/parser/node fixtures from doc 27 §4.7.
12. Stamp `doc_format: 1`; run the production-shaped document generator/save storm and collect the first floor-tier performance and writer-occupancy baseline. Registry prune remains disabled unless this evidence justifies it.
13. Land the minimal typed capability registry/change taxonomy and Phase-A capability conformance fixtures; record boot/build manifest provenance on completion.

### Exit criteria

The slice passes local success plus missing-model/node/ffmpeg, admission replay, changed-payload conflict, complete lost-ack replay, fence rejection, crash/lease expiry/reclaim, poisoned/truncated output, disk failure, queued/running cancel (including cancel-during-publication), `astrid serve` restart, concurrent editor-save versus registry-merge, local-trust attacks, setup interruption/repair, and browser MP4 playback. The evidence table comes from a declarative fault schedule on the real t2i→gallery→timeline→render→Range journey; a bridge harness does not replace editor/browser acceptance. Every atomicity failure yields a full result or no authoritative result, DB→tree totality holds after recovery/retry, and no stale fence or silent document clobber is accepted. Supabase and task-execution/provider networking are blocked at the OS level. **(Amended: engineering-answers judgment)**

## 5. Phase B — remaining local capabilities and orchestrator children

**(Amended: Grok review — judged ADOPT.)**

### Goal

Expand only after the Phase-A protocol and completion boundary are trustworthy.

### Work

- Enable retained capabilities from doc 27 only when their single WGP or VibeComfy binding passes the local availability probe.
- Port the remaining pure family resolvers and payload builders without a task-types table or alias layer.
- Implement leased-running join/travel/edit parents, executor-only fenced child admission, deterministic child keys, hard dependencies, crash replay, and explicit parent complete/fail.
- Use kernel ULIDs returned by admission for all child and dependency references.
- Drop unread route-control contract blocks `[INFERENCE]`; retain handler-read `orchestrator_details` and only demonstrably used fallbacks.
- Add join/travel production-shaped fixtures with the handlers they cover.
- Add trimmed custom-workflow YAML, immutable snapshots, in-repo `ready_templates`, and one generic VibeComfy handler.
- Gate Wan2GP changes through hermetic rebase, path/import/config contracts, supported-platform resolution, conversion fixtures, and fixed-seed output-shape/semantic comparison; drain-and-swap one binding and run the bounded N→N+1→N rollback drill. **(Amended: engineering-answers judgment)**
- Make orchestration identity attempt-independent and plan derivation pure; check in the transition table, key lint, purity test, and deterministic-scheduler adversarial interleavings from doc 27 §9. **(Amended: engineering-answers judgment)**
- Land each remaining capability with its representative conformance fixture and boot/build-manifest provenance. **(Amended: engineering-answers judgment)**

### Exit criteria

Every advertised capability executes locally with one binding and truthful setup gating. Orchestrator crash/replay cannot duplicate children across attempt changes, browser callers cannot admit child-only families, parent leases recover, hard dependencies order work, and every scheduler interleaving yields one child per deterministic key plus one parent terminal transition. Wan rollback preserves queue/output/provenance integrity, and no handler uses a Supabase or outbound-provider path. **(Amended: engineering-answers judgment)**

## 6. Phase C — application cutover and release

**(Amended: Grok review — judged ADOPT.)**

### Goal

Make the supported product bridge-only and retire legacy runtime paths.

### Work

- Replace retained PostgREST, RPC, storage, realtime, and edge-function calls with domain clients.
- Ship the focused document-native shot view with one document, save path, and undo history.
- Ship always-copy import/output media, local setup/doctor, launcher supervision, backup/restore, and render playback.
- Keep gallery reads bounded; measure document size and gallery delivery before considering paging or a variants route.
- Remove account/billing/sharing/training/agent-session, provider, cloud fleet, Supabase, importer, and rollback UI/code paths.
- Run clean-install and upgrade acceptance with Supabase/provider networking blocked.
- Prove the SQLite + managed-tree + hash-manifest backup/restore round trip and run calibrated p95/writer-occupancy budgets on both controlled hardware tiers. **(Amended: engineering-answers judgment)**

### Exit criteria

The browser talks only to `astrid serve`; supported generation, orchestration, editing, cancellation, gallery, media, render, backup, and restore journeys work from an empty local authority. No supported startup or workflow needs a Supabase/provider credential, endpoint, data export, rollback window, or second structured store.

## 7. Out of scope for v1

**(Amended: Grok review — judged ADOPT.)**

Remote/RunPod workers; authenticated/TLS transport; SSE/WebSockets; multiple bindings or admission-time binding selection; runtime plugins or promotion service; legacy aliases; structural whole-graph orchestration; queue summary; executor registry/heartbeat; project-wide variants route; thumbnails; document paging; link-in-place media; hard delete/media GC; cloud providers; auth/tenancy/billing/sharing; production importer/exporter/replay/archive/rollback authority.

References, evidence, understanding, existing kernel events, backup/restore, and frozen timeline bridge routes are not migration targets and remain untouched.

## 8. Delivery risks

**(Amended: Grok review — judged ADOPT/MODIFY.)**

| Risk | Mitigation |
|---|---|
| Atomic completion leaks partial state | One prepared-byte phase plus one `BEGIN IMMEDIATE`; replay and fault injection block Phase B. |
| Internal registry visibility clobbers an editor save | Registry-only evented merge against the current timeline head; never public full-document worker save. |
| Heartbeat races terminal settlement | One worker-side mutex, terminal-stop rule, lease/fence tests, and server expiry. |
| Orchestrator crash duplicates children | Deterministic child keys, live parent fence gate, kernel ULIDs, hard dependencies, and replay tests. |
| A fresh machine lacks models/nodes/render tools or disk | Boot availability manifest, verified acquisition/setup, disk preflight, hidden capabilities, actionable `capability_unavailable`. |
| Wan/Comfy workflow drift changes output | Pin workflow digest/model hash on tasks and record process build/node facts in the boot manifest. |
| Timeline JSON or gallery delivery grows poorly | Measure representative projects; add projection/paging only after observed limits. |
| Simplified errors hide diagnosis | Keep five public new-route categories and detailed local structured logs; preserve frozen timeline/CAS errors. |

**(Amended: engineering-answers judgment)** The first mitigation above means durable install-if-absent CAS publication **before** `BEGIN IMMEDIATE`, then an O(stat)-only receipt-bearing transaction; the Phase-A crash matrix checks DB→tree totality and reports but does not collect CAS orphans. Additional adopted risk controls are:

| Risk | Mitigation |
|---|---|
| Loopback is reached by a hostile page/process | Per-boot request capability, strict Host/custom-header/CORS gate, 0700/0600 posture, path/parser bounds and Comfy node allowlist. |
| Setup is interrupted or advertises corrupt artifacts | Separate resumable setup journal, signed hash/size/license manifest, atomic install and doctor repair; acquisition only in setup mode. |
| Document/registry growth occupies the writer | `doc_format`, production-shaped generator, p95/p99 and occupancy measurement; prune only after reference-safety proof. |
| Arbitrary performance guesses become promises | Treat doc 27 §7.2 budgets as `[INFERENCE]` until floor-tier baseline; publish calibrated `refuse/degrade/queue` behavior. |
| Future-proofing recreates cut machinery | Apply doc 27 §10's seven invariants and “name the row”; preserve existing events but add no universal event or remote-transport test surface. |

Production-schema drift, archive loss, provider-secret handling, fleet scaling, and rollback leakage are not active delivery risks because those futures are cut from the supported journey.

## 9. First actions

**(Amended: Grok review — judged ADOPT.)**

1. Land the local availability matrix and code-based completion-effects note.
2. Implement the separate setup journal/doctor and the local-trust gate. **(Amended: engineering-answers judgment)**
3. Implement the two-table pack migration plus pre-transaction CAS publication and the atomic receipt-bearing UoW. **(Amended: engineering-answers judgment)**
4. Land `doc_format`, the document/performance baseline, writer-occupancy instrumentation, and the Phase-A capability fixtures. **(Amended: engineering-answers judgment)**
5. Prove the adversarial Phase-A `wan_2_2_t2i` and render journey through doc 27's minimal protocol and crash matrix. **(Amended: engineering-answers judgment)**
