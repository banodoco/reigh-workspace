> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Generation-path alignment — portfolio boundary report

Research date: 2026-09-10. This is a read-only planning report. No product files,
runtime state, databases, providers, worktrees, or tests were changed or run.
Evidence is from the current dirty checkouts and the planning packages; “planned”
means an intended future change, not implemented behavior.

## 1. Purpose and concrete user impact

The project aligns every supported Astrid generation route with the canonical
Runtime generation/variant domain. The minimum useful before/after is:

| Today (evidence-backed gap) | Intended after alignment |
|---|---|
| A generation can complete through the normal task/run/CAS/host path, but the host does not automatically create a project-owned generation or variants. Existing SDK wrappers only expose separate `create_generation`/`create_variant` commands (`Astrid/astrid/sdk/remote.py:652-681`; audit `.otto/runs/astrid-generation-path-audit-20260910/shared.md:11-18`). | A successful image/video/audio task yields a discoverable project-owned generation, ordered variants, managed media, source task/attempt and provider provenance through one Runtime-owned settlement boundary. |
| Generation convenience methods invoke without waiting by default (`Astrid/astrid/sdk/invocation.py:1689-1713`); the facade immediately reconstructs from a completed payload (`Astrid/astrid/sdk/generation.py:282-308`, `390-416`, `499-525`). Remote settled results can instead expose `result`/`outputs.artifacts`, so callers may see premature or non-reconstructable results (audit `.otto/runs/astrid-generation-path-audit-20260910/cloud.md:37-43`). | Sync calls wait/reconstruct from canonical settled data; async calls remain correct after the original caller exits. Returned media handles resolve through managed storage, not dead staging paths. |
| Runtime settlement atomically publishes staged objects and task completion, but its current declared settlement effect is only `project.update` (`runtime_protocol/store.py:1786-1820`, `1822-1862`). Separate domain create calls would leave a crash window. | Generation rows, variants, object associations, receipt/event result and task completion commit or recover together, with deterministic replay and no duplicate rows. |

The north star explicitly preserves prompts/reference order, model/provider/session
provenance, output order and explicit timeline editing while forbidding a second
queue/store/poller, backend registrar, automatic timeline insertion or provider
fallback (`.otto/runs/astrid-generation-path-alignment-20260910/northstar.md:3-7`).

## 2. Current status, source identity and custody

The assigned run is planning-complete and dormant: no implementation, execution
tests, execution worktrees, paid calls, review stages, merge, push or deployment
occurred (`.otto/runs/astrid-generation-path-alignment-20260910/status.md:3-17`).
The run’s authorization is planning only and expressly excludes live repair,
provider/GPU spend, and implementation (`.otto/runs/astrid-generation-path-alignment-20260910/agent_goal.md:3-15`).

Recorded source snapshot (2026-09-10 12:46 UTC) and current read-only check:

| Repository | Recorded/current identity | State and custody implication |
|---|---|---|
| Astrid | `<workspace>/Astrid`; `main`; `82d09bb91c8a4621695c1d8b6966652cad941ef4`; current HEAD unchanged | Substantially dirty with tracked host/SDK/generated-client/test changes and untracked files, including `docs/architecture/runtime-database-clean-break-plan.md` and `docs/design/`. The captured status and dirty-input basis are explicit (`.otto/runs/astrid-generation-path-alignment-20260910/source-state.json:2-10`); the generation run says not to silently replace them with HEAD (`agent_goal.md:7`). |
| Runtime | `<workspace>/banodoco-workspace-runtime-execution-20260909`; branch `codex/canonical-timeline-replacement-20260909`; `afccb430e2a983c968b6a8a96fd630ba3a6262fc`; current HEAD unchanged | Dirty in settlement/store/service/server/daemon, generated-client template, migration and tests. The source snapshot says this is evidence of implementation location, not permission to edit or execute on that feature branch (`.otto/runs/astrid-generation-path-alignment-20260910/source-state.json:7-22`). |
| Reigh | `<workspace>/reigh-app`; `main`; `3d3e088653c4b7ff00eca2ecfd9c23859ca0f9f7` | Clean, read-only context only. The project explicitly excludes GPU route migration/provisioning from this assignment (`agent_goal.md:9-13`). |

The Astrid run’s recorded source state uses `/Astrid` while the surrounding audit
uses the same checkout through the case-insensitive `/astrid` path. Treat the Git
identity, not pathname spelling, as authoritative. Do not assume the dirty source
composition is reproducible from the recorded HEAD.

The runtime and Astrid sources have active concurrent repairs. In particular,
host registration has a previously observed HTTP 500 and no live-runtime proof is
available (`.otto/runs/astrid-generation-path-audit-20260910/summary.md:17-20`; generation
plan `.otto/runs/astrid-generation-path-alignment-20260910/plan.md:63-67`).
Existing 67 focused tests and three Codex tests are audit background only, not
candidate acceptance evidence (`plan.md:55-61`).

Custody conflict to surface to Astra: generation T1 calls for isolated custody after
authorization (`.otto/runs/astrid-generation-path-alignment-20260910/tasklist.md:7`),
whereas runtime-database-clean-break requires the existing `main` checkout, no new
branch/worktree, serial ownership and preservation of unrelated dirt
(`Astrid/.otto/runs/runtime-database-clean-break-20260910/tasklist.md:3-7`). This is
a run-level constraint difference, not permission to override either package. A
future coordinator must choose custody jointly before touching shared runtime or
Astrid files.

## 3. Scope boundaries, owned contracts and invariants

### Explicitly in scope

- Codex and standard fal image/video/audio, generic local image/video, OpenAI
  images, fal H3 and Foley, typed Wan2GP video, and explicitly generative Vibe
  workflows (`plan.md:11-18`).
- One versioned envelope: immutable admitted intent (project, modality, logical
  groups, permitted selectors/order, partial-success policy) plus winning-attempt
  provenance and verified output mappings (`plan.md:24-30`).
- Task-scoped identity: generation = task + declared group key; variant = generation
  + original declared output ordinal/key. Attempts/fences are provenance only
  (`oracle-D1.md:4-10`).
- Runtime resolution of selectors against verified managed outputs; provider
  normalization once at pack/host boundary; replay, failure, stale-fence and
  cancellation truth (`plan.md:26-32`).
- Foley manifest/host contract correction and normalized OpenAI/H3/Wan/Vibe output
  inventories, excluding manifests, diagnostics, references and incidental bundle
  members (`plan.md:13-18`, `oracle-D1.md:8-12`).

### Explicitly out of scope

- GPU migration/provisioning/warm-session work, RunPod as a generator, a second
  queue/store/poller, provider-job resumability that prevents duplicate paid work,
  historical backfill, live-realm repair/direct DB writes, automatic timeline
  placement, UI redesign, generic workflow framework or implicit provider fallback
  (`agent_goal.md:11-15`; `northstar.md:3-7`).
- Bare RunPod `provision`/`exec`/`pull` registration: it remains substrate and a
  downloaded file is not automatically a generation (`plan.md:17-20`; GPU audit
  `.otto/runs/astrid-generation-path-audit-20260910/gpu.md:17-21`).

### Owned contracts/invariants

The Runtime owns admission authority, task/project/attempt ownership, output
verification, generation/variant persistence, receipts/events and atomic fenced
completion. Child executors may declare intent and normalized output descriptors;
they may not choose arbitrary domain/object identities. No empty successful
generation is allowed; partial success must be opt-in and preserve original
ordinals. Failed/cancelled/stale/invalid publication creates no successful domain
rows (`oracle-D1.md:8-17`; `plan.md:45-53`).

The existing shared result-manifest contract is an input to this boundary, not a
second authority. It enriches file/directory metadata (`Astrid/astrid/core/_shared/result_manifest.py:89-135`),
requires concrete hash-verified file outputs for strict validation
(`Astrid/astrid/core/_shared/result_manifest.py:346-430`), and treats `manifest.json` as the exclusive
receipt when present (`Astrid/astrid/core/_shared/result_manifest.py:610-655`). Generation publication
must add explicit generation intent/role semantics without making path or manifest
membership itself a domain identity.

## 4. How it runs: entry points, flow, state and boundaries

The normal path is:

```text
typed SDK / CLI / producer
  → sdk.invoke admission (project + capability + task/run)
  → Runtime claim / lease / attempt / fence
  → GenericPackHost subprocess or Python executor
  → attempt-local output spool + manifest
  → host harvests named, verified outputs
  → Runtime upload/CAS publication
  → fenced settlement transaction
  → task.completed + attempt.settle receipt + generation/variant mappings
  → SDK list/show/variants or explicit timeline placement
```

Admission and optional waiting are in `sdk/invocation.py:1689-1714` and
`1920-2037`; a `wait=True` call polls settled task data at `1967-1976`, but the
typed generation facade currently does not pass that option at its call sites
(`sdk/generation.py:282-305`, `390-413`, `499-522`).

The host’s convergence point is explicit. `_upload_outputs` requires canonical
`upload_object`, removes staging paths, records digest/media/size/ordinal/role and
returns settlement-safe object references (`Astrid/astrid/core/execution/generic_host.py:2286-2347`).
After execution it harvests the declared result manifest, rejects missing declared
media ports and empty required output (`Astrid/astrid/core/execution/generic_host.py:2921-2969`), stamps
admitted capability/source/dependency and process/network provenance, then calls
`client.settle` (`Astrid/astrid/core/execution/generic_host.py:2970-3029`).

Runtime `settle_attempt` validates attempt identity, epoch, fence, declared effect
and output shape, stages outputs, then invokes the store’s fenced settlement
(`banodoco-workspace-runtime-execution-20260909/runtime_protocol/service.py:2491-2563`).
The store currently validates/applies only `project.update`, and inside one
transaction applies the effect, publishes staged objects, marks task/run complete,
releases reservations, appends `task.completed`, and records the receipt
(`banodoco-workspace-runtime-execution-20260909/runtime_protocol/store.py:1786-1862`). D1’s planned extension belongs here:
generation/variant rows must be written before task completion within this same
transaction, using internal primitives rather than independently committing public
create wrappers.

Persistent state is therefore existing Runtime SQLite domain tables, command
idempotency/receipts, task/run/attempt/fence rows, immutable CAS/managed objects,
and attempt staging. Outputs are durable managed objects; the settled result carries
canonical mappings and provenance. Timeline tracks/events remain separate and are
mutated only by an explicit existing timeline operation (`plan.md:20`, C9).

Failure/recovery boundary: bytes may be staged before the transaction, but ownership,
fence, output publication, domain rows and completion must be all-or-nothing. An
identical committed replay returns the original receipt; changed payload conflicts.
Provider requests may repeat after host interruption; eliminating that external paid
work duplication is deliberately excluded (`oracle-D1.md:13-17`; `plan.md:63-67`).

## 5. Touch map and overlap

| Exact repository/file/symbol | Intended change | Consumer | Overlap / scope confidence |
|---|---|---|---|
| Runtime `runtime_protocol/store.py:_validate_settlement_effect`, `_apply_settlement_effect`, `_settle_attempt` (`1786-1862`) | Add narrow generation settlement validation/publication to the existing fenced transaction; preserve project-update and non-generation effects, receipts/events and replay. | All Astrid producers through `settle_attempt`. | **Explicit T2.** Same-file semantic collision with clean-break T3/T6 lifecycle consolidation; must serialize after source custody. |
| Runtime `runtime_protocol/service.py:settle_attempt` (`2491-2563`) | Accept/version envelope, validate admitted intent and normalized mappings, stage outputs and pass a typed publication payload to store. | GenericPackHost and generated clients. | **Explicit T1/T2.** Same-file/protocol collision with clean-break server/service changes. |
| Runtime `runtime_protocol/store.py` generation/variant primitives and `service.py` public create commands (audit `shared.md:21-27`) | Reuse internal validation/persistence logic; do not call independently committing public wrappers. | Existing generation commands plus settlement publisher. | **Explicit D1.** Semantic dependency on clean-break canonical DB authority; no schema rewrite implied. |
| Runtime `generators/python_client_template.py`, generated Python client; Astrid vendored `banodoco_workspace_client/generated.py` and `contract_metadata.py` | Evolve wire schema together for envelope/settled mappings; regenerate once after contract settles. | Astrid `WorkspaceClient`, host, CLI, server consumers. | **Explicit T1/T6.** Same-file collision with clean-break T6 generated-client work; serialize contract generation. |
| Astrid `astrid/core/execution/generic_host.py:_upload_outputs`, settlement path (`2286-2347`, `2921-3029`) | Build/admit generation descriptors from typed manifests; attach only verified outputs; forward canonical settlement; no caller-side create calls. | Every hosted generation route, including cloud/Codex/local/GPU. | **Explicit T3.** Same-file collision with render V1-06 and RRP-05 publication identity; host owner must coordinate. |
| Astrid `astrid/sdk/invocation.py:invoke`, `_wait_for_kernel_task` (`1689-1714`, `1962-1976`) | Carry generation intent at admission and make async settlement independent of caller; align wait/readback. | SDK, CLI, typed facade, producers. | **Explicit T1/T3.** Semantic overlap with clean-break T6 caller routing; same-file likely. |
| Astrid `astrid/sdk/generation.py:GenerationFacade` (`150-158`, `282-308`, `390-416`, `499-525`) and `sdk/results.py:_reconstruct_generation_result` (`202-235`) | Pass appropriate wait/reconstruct canonical settled result; expose stable managed-media/generation handles. | Typed image/video/audio users. | **Explicit T3.** No direct overlap with timeline UI work except explicit placement readback. |
| Astrid `astrid/sdk/remote.py:RemoteGenerations` (`652-681`) and `sdk/workspace_client.py` (`592-669`, `715-716`) | Preserve public list/show/variants and create command compatibility while adding settled mappings. | SDK/CLI/runtime queries. | **Explicit C8/C9.** Generated-client collision with clean-break T6; do not duplicate domain API. |
| Astrid `astrid/core/_shared/result_manifest.py` (`346-430`, `610-655`) | Reuse strict output inventory; add only the minimum intent/role metadata needed by generation publication. | Generic host and all manifest-producing packs. | **Inferred shared-contract touch.** Semantic dependency on lifecycle E2-01; avoid broad lifecycle implementation here. |
| Astrid `packs/generation/executors/generate_image/run.py:635-708`, `generate_video/run.py:675-744`, `generate_audio/run.py:524-565` manifests and result construction | Normalize modality, model/mode/execution, prompt/reference order, request/session ID and deliverable output descriptors. | Standard cloud/fal/local/Codex routes. | **Explicit T4/T5/shared.** Route adapters may parallelize only after T3 descriptor contract. |
| Astrid `packs/generation/executors/generate_image_openai/run.py:_build_openai_manifest` (`250-307`, `375-400`) | Map jobs/groups and actual image outputs; exclude manifest/reference/support members; retain partial manifest semantics. | OpenAI image producer. | **Explicit T4.** No runtime file collision with H3/Foley; semantic contract dependency on T3. |
| Astrid `packs/fal/executors/h3_video/run.py:_write_run_manifest` (`170-210`) and `executor.yaml` (`79-91`) | Convert run bundle to one declared generated-video group, preserving exact prompt, ordered refs, request/cost metadata without registering bundle members. | H3 producer. | **Explicit T4.** Adapter-local after shared contract. |
| Astrid `packs/fal/executors/fal_foley/run.py` (`54-78`) and `executor.yaml` (`15-52`) | Declare required prompt; reconcile file-vs-directory `{out}` contract; emit generated audio descriptor/provenance. | Foley producer/GenericPackHost. | **Explicit T4.** Same semantic boundary as host harvest; likely independent file ownership. |
| Astrid `packs/wan2gp/executors/generate_video/run.py` (`75-125`) | Normalize ordered generated videos, model/portable digest/engine metadata into shared publisher input. | Wan2GP typed route. | **Explicit T5.** Adapter-local after T3; GPU plan remains separate. |
| Astrid `packs/vibecomfy/executors/run/run.py` (`33-88`) and `executor.yaml` (`23-40`, `78-90`) | Require explicit generative admission/output semantics; preserve arbitrary non-generative workflow behavior and manifest inventory. | VibeComfy producer. | **Explicit T5.** Semantic dependency on lifecycle E2-01; do not classify all outputs as generation. |
| Astrid timeline APIs / rendering paths | Verify explicit placement of managed generated media only when requested. | Timeline SDK/CLI and existing render consumers. | **Explicit C9; mostly out of scope.** Timeline V1 and RRP deliberately retain separate render/timeline contracts. |

## 6. Task-level dependencies, parallelism and serialization

### Must serialize

1. **Source custody and T1 contract before all implementation.** Reconcile dirty
   Astrid/runtime changes, branch/worktree policy, exact runtime owner and generated
   client source. Do not begin T2 against the recorded runtime branch while the
   clean-break run’s custody is unresolved.
2. **T1 → T2.** Envelope shape, group/ordinal identity, partial policy, selector
   authority and protocol/client types must be fixed before runtime store/service
   writes. The publication-contract review follows T2 and gates T3
   (`plan.md:34-41`; `tasklist.md:7-10`).
3. **Runtime T2 → T3.** Host and SDK must consume the stable settled-result shape;
   otherwise they risk encoding caller-side publication or a second result schema.
4. **T3 → T4/T5 adapter implementation.** Both adapter branches depend on the
   shared host descriptor and managed-result contract. T4 and T5 can then run in
   parallel only with disjoint file ownership (`tasklist.md:10-14`).
5. **Generated-client regeneration after protocol settles.** Clean-break T6 also
   regenerates clients; one coordinated regeneration is required, not two branches
   overwriting generated files.
6. **T4 + T5 → T6.** Integrated failure paths, broad suite and any authorized live
   smoke require both retained adapter groups. Final review is after T6 only.

### Safe parallel chunks

- During T1, read-only source reconciliation can proceed in parallel with a route
  inventory (OpenAI/H3/Foley/Wan/Vibe) and a test/evidence matrix; neither edits
  shared files.
- After T3’s shared contract is accepted, T4’s cloud/Codex/OpenAI/H3/Foley adapter
  work and T5’s Wan/local/Vibe adapter work are safe parallel chunks if the host,
  result-manifest and generated-client files remain owned by T3/T1/T2 owners.
- T4’s Foley contract correction and OpenAI/H3 metadata normalization are
  independent adapter-local work; T5’s Wan2GP and explicit Vibe declarations are
  similarly independent. Their tests can be authored in parallel but integrated
  against one disposable runtime fixture matrix.
- Timeline visualization V1-01–V1-06 is planned as self-contained and can proceed
  independently (`Astrid/.otto/runs/timeline-visualization-fixes-20260910/status.md:3-9`).
  Generation’s explicit timeline-placement check should consume existing APIs, not
  block or modify V1’s filmstrip implementation.
- Runtime-render RRP-01 read-only tracing and generation T1 can run in parallel.
  RRP-02/RRP-03 diagnostic/recovery work is operationally separate, but any edits to
  GenericPackHost publication identity or Runtime launcher/service must be merged
  by coordinated ownership before T6.

### Cross-project semantic gates

- **Runtime database clean break:** its plan routes Astrid/server/packs through one
  lifecycle boundary and removes compatibility/migration paths
  (`Astrid/.otto/runs/runtime-database-clean-break-20260910/plan.md:9-16`).
  Generation must target that canonical boundary and preserve C1–C8 safety, not
  introduce a generation-specific DB path. Its T3 foundation gate is a prerequisite
  for any runtime settlement change if both runs touch the same source composition.
- **Ephemeral-derived-artifact lifecycle (adjacent dependency, not a fifth
  implementation assignment):** E2-01 defines output intent/provenance over the
  existing capability/result-manifest contract; E2-02 owns lifecycle metadata,
  events, receipts and idempotency (`Astrid/.otto/runs/ephemeral-derived-artifact-lifecycle-20260910/tasklist.md:3-10`).
  Generation should publish primary outputs with compatible role/provenance fields,
  but must not implement leases/TTL/promotion/deletion or a second event ledger.
  E2-06 waits for the completed visualization plan and owns its migration; it is not
  a prerequisite for generation’s shared publication contract.
- **Runtime render path reliability:** its north star keeps Runtime/CAS/settlement,
  explicit scope and verified materialization while removing user-facing DB/CAS
  fallbacks (`Astrid/.otto/runs/runtime-render-path-reliability-20260910/northstar.md:3-10`).
  Generation must preserve filename/media identity through settlement so RRP can
  resolve managed output, but must not expand into RRP’s launcher/recovery/opening
  work. RRP’s plan explicitly defers generation/variant expansion
  (`Astrid/.otto/runs/runtime-render-path-reliability-20260910/plan.md:123-130`).

## 7. Validation and acceptance gates

No acceptance evidence exists yet beyond static source/audit observations. The
planned evidence should be gathered against a disposable Runtime fixture, not the
live/corrupt realm, and should inspect queries/events/receipts rather than helper
calls (`plan.md:55-61`). The efficient matrix is:

| Gate | Required proof |
|---|---|
| T1/C1/C8 contract | Image/video/audio and multi-prompt descriptors; deterministic group/ordinal identity; unauthorized project/object mapping rejected; protocol and generated client agree; exact source identities recorded. |
| T2/C1–C4/C8 publication | Atomic task + object + generation/variant publication; crash before/after boundary; rollback on rejected upload; stale fence/cancel/failure produce no success rows; exact replay returns original receipt and changed replay conflicts; existing project.update and non-generation effects remain intact. |
| Publication-contract review | One intermediate review after T2, limited to authority, transaction, replay, failure and compatibility criteria (`run.yaml` review stage and `status.md:15-17`). |
| T3/C2/C5/C6/C9 facade/host | Sync waits; caller-exited async settles; list/show/variants expose managed media and task receipt/event chain; output paths remain usable after staging cleanup; explicit timeline placement works; ordinary generation creates no timeline change; non-generation control remains unchanged. |
| T4/T5/C5–C8 route contracts | Deliverable-only output mapping, multiple prompt/job groups, references/manifests excluded, partial policy explicit, provenance complete where available; Foley prompt/output contract fixed; Codex host policy/auth/network path verified without bypass; Wan/Vibe/RunPod classification preserved. |
| T6/C1–C9 integrated | One final source identity, parameterized adapter matrix, broad affected suite once, focused corrections, query/event/receipt evidence and exact limitations. Live smokes are conditional on explicit target/provider cap; unavailable live evidence is outstanding, never PASS. |

The planned live classes are Codex image, standard fal generation, OpenAI image,
H3/Foley and available local/Wan/Vibe, using the smallest valid requests. No paid
call or GPU provisioning is authorized in this planning phase (`plan.md:55-61`).
Provider request resumability is not an acceptance gate; unique Runtime publication
for the winning attempt is.

## 8. Recommendations to Astra and pre-execution checks

1. Sequence by contract, not by whole project: custody/read-only T1 → Runtime
   publication T2 → publication-contract review → host/SDK T3 → parallel adapter
   T4/T5 → integrated T6/final review. A blocker should pause only dependents.
2. Resolve the clean-break custody contradiction explicitly. If the database run’s
   existing-main/no-worktree rule remains authoritative, generation’s “isolated
   custody” must be reinterpreted as an isolated execution protocol over the shared
   main checkout with serialized file ownership—not silently create a worktree.
3. Assign one owner for Runtime settlement/store/service and one for generated
   protocol clients across generation and clean-break. The same owner should record
   a source/diff manifest before and after T2/T6.
4. Assign GenericPackHost and `result_manifest.py` ownership to T3 while V1/RRP
   owners coordinate any publication-identity edits. Do not let T4/T5 alter shared
   host semantics while adapter work is in flight.
5. Before execution, check whether the dirty host/runtime repairs already change
   settlement payloads, generated clients, or output roles; compare current hashes
   with `source-state.json` and re-baseline the plan if changed.
6. Confirm the actual runtime owner/main source and repair the observed host
   registration HTTP 500 only through its separate authorized work. Do not use a
   live corrupt realm for generation tests.
7. Confirm lifecycle E2-01’s final output-intent vocabulary before widening manifest
   fields. Generation should provide primary-output intent and source/member
   provenance; lifecycle owns retention, lease and deletion semantics.
8. Before any live smoke, obtain explicit disposable target, provider credentials,
   cost/resource cap, and network policy evidence. If any is unavailable, report the
   route as unverified rather than converting fixture PASS into all-path PASS.
9. Keep timeline placement and render opening as consumer checks only. Do not create
   tracks on generation success, add raw-CAS fallbacks, or fold RRP/V1 implementation
   into this run.

## Conclusion

Generation-path alignment is a shared Runtime settlement/host contract followed by
two disjoint adapter waves. The critical sequencing gate is T2’s atomic publication
contract; the critical portfolio risk is concurrent dirty Runtime/Astrid ownership,
especially the clean-break run’s existing-main/no-worktree mandate. Lifecycle,
timeline visualization and render-opening projects should consume the resulting
managed-output/provenance contract at explicit boundaries, not duplicate it.
