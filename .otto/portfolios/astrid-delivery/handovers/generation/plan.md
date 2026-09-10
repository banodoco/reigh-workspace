> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Generation path alignment plan

## Minimum useful outcome

A successful generation is discoverable as a project-owned generation with ordered output variants, each resolving to stored media and its producing task/attempt/provider provenance. This works through synchronous convenience calls and asynchronous invocation after the caller exits. Existing failure/cancellation and explicit timeline behavior remains truthful. The runtime, not the provider adapter or caller, owns durable publication.

## Scope and consolidation

Reuse existing tasks/runs/events, managed objects, generation/variant tables and commands, GenericPackHost, backend polling and timeline APIs. Add one narrow generation settlement envelope with admitted intent and verified output mappings; do not create a new job service or register every arbitrary artifact as a generation. Preserve the existing generation grouping semantics; explicit ordered grouping must represent multiple prompts/jobs without inventing alternative schemas per backend.

| Route | Required alignment |
|---|---|
| Codex; fal image/video/audio; generic local image/video | Shared publication, complete normalized provenance and correct facade result handling |
| OpenAI images; fal H3 | Normalize generated output inventory, grouping and metadata while excluding prompts, references and manifests |
| fal Foley | Fix declared prompt/output-directory contract and register generated audio/provenance |
| Wan2GP | Normalize typed video outputs into shared publication contract |
| vibecomfy.run | Publish only when the caller/producer declares generation intent at admission with known output semantics; preserve non-generative arbitrary workflow behavior |
| RunPod provision/exec/pull | Remain substrate; no blanket generation registration for downloaded files |

Timeline placement is explicit: verify generated managed media can be placed through existing APIs when requested. Do not create tracks merely on generation success.

## Architecture decision D1

**Settled by oracle D1:** [oracle-D1.md](oracle-D1.md). Publish generations and variants within the existing fenced Runtime settlement transaction. Reuse internal validation/persistence primitives shared with existing commands; do not call independently committing public API wrappers. The generation envelope is orthogonal to existing `project.update`, not a new generalized effect framework.

One versioned envelope separates immutable admitted intent (project, logical groups, modality, permitted output selectors/order and partial-success policy) from winning-attempt provenance and output mappings. Runtime resolves selectors against verified managed outputs; child code cannot choose arbitrary domain/object identities. Provider normalization occurs once at the pack/host boundary.

Generation identity is task ID + declared group key; variant identity is generation ID + original declared output ordinal/key. Attempts/fences are provenance, never persistent identity. Multiple prompts/jobs have explicit groups; no grouping by file enumeration. Vibe workflows need explicit generative admission; bare RunPod remains substrate.

Partial success is opt-in at admission. Preserve original output ordinals, publish successful deliverables only, record missing/failed optional members, and never create an empty successful generation. Missing required output, zero successful required groups, invalid ownership/publication, stale fence, failed or cancelled task creates no generation rows. Domain writes and task completion roll back together on publication errors. Exact committed replay returns the original receipt; changed replay conflicts.

Reuse `task.completed` and `attempt.settle` with canonical generation/variant/object mappings in the settled result. Dedicated generation-domain events are not required absent an actual consumer. Existing durable task recovery and fenced replay recover interruption; no new poller or continuation service.

## Execution sequence

1. T1: Reconcile source identities and implement the narrow publication contract with existing output/grouping semantics. Resolve any conflicting concurrent host/runtime changes before dependent edits.
2. T2: Implement atomic runtime generation/variant publication and receipts/events through existing fenced completion. Integration fixtures prove recovery and exclusion of stale/failed attempts.
3. One contract review after T2 catches incorrect authority/transaction assumptions before provider adapters depend on them.
4. T3: Wire GenericPackHost and typed facade to canonical settled results. No caller-side publication side effects; support caller disappearance.
5. T4/T5: Align cloud/Codex and GPU/local adapters, in parallel only after their shared interface is stable and file ownership is disjoint.
6. T6: Integrated failure-path and retained-path acceptance, one broad affected suite on final source, then configured final review. Live proof remains conditional on explicit provider budget/target authorization; unavailable live evidence is reported outstanding, never PASS.

## Implementation criteria

- **C1 — Authority:** task/project/attempt and every published object are validated against admitted generation intent and the winning attempt's verified result inventory; no cross-project or arbitrary-object attachment.
- **C2 — Durable completion:** generation(s), ordered variants, media associations and task completion have one atomic/recoverable runtime boundary. Caller exit and runtime restart cannot leave a completed generation task permanently unregistered. No new queue/store/poller.
- **C3 — Replay:** identical completion retries preserve identities/receipts without duplicate generations or variants; conflicting replay payloads reject. Multiple outputs and prompt/job grouping remain deterministic.
- **C4 — Failure truth:** stale fences, cancellation, rejected uploads and failed tasks do not create successful generation rows. Explicit successful/partial output policy is honored without treating partial failure as full success.
- **C5 — Provenance:** declared output variants include modality, prompt/reference ordering where available, actual model/backend, provider request/session identifier where supplied, source task and managed media. Manifests/reference assets are not mistaken for deliverables; unavailable values remain explicitly absent.
- **C6 — SDK:** sync facade waits appropriately and reconstructs from canonical settled data; async invocation completes publication without caller participation. Results expose usable managed-media references and preserve promised file access through managed materialization, not dead staging paths.
- **C7 — Route coverage:** every row in the scope table has explicit adapter/contract evidence; Foley's input/output mismatch is fixed; generic workflow/substrate behavior is not misclassified. Codex authentication/network/output access works through host policy without bypasses.
- **C8 — Compatibility/data:** existing generation commands and non-generation completion remain supported; existing records are preserved; protocol/generated clients evolve together; no live-realm mutation or migration is implicit.
- **C9 — Consumer usability:** list/show/variants retrieves the generated result and producing-task event/receipt chain; explicit timeline placement resolves managed media successfully and ordinary generation alone creates no timeline changes.

## Validation approach (future work, not executed)

Use one parameterized adapter-fixture matrix and a disposable runtime with small injected provider fixtures to demonstrate sync/async generation, two prompts with multiple outputs, reference/manifests exclusion, partial failure policy, original caller exit, retry and conflicting payload, interruption around transaction boundaries, restart, cancellation during upload, stale attempt, project/object mismatch and non-generation control cases. Inspect actual runtime queries/events/receipts rather than matching implementation helper calls. Combine shared integration proof with small adapter contract tests; do not duplicate lifecycle suites per backend.

Live smoke classes: canonical Codex image, standard fal generation, OpenAI image, H3/Foley specialized paths, and available local/Wan/Vibe route through supported host. Select smallest valid requests and one generated item each where semantics allow. No paid call or GPU provisioning now. If live proof cannot be authorized or made available during delivery, report exactly which acceptance evidence is missing and do not claim all-path completion.

Prior 67 focused tests and 3 Codex tests are audit background, not future candidate evidence. No planning-time execution tests.

## Estimates and uncertainties

5–8 focused engineer-days total; shared foundation 3–5 is included. Normal-route tasks with precise briefs are sufficient initially. Provider-job resumability (avoiding duplicate external compute) is excluded; database publication must still be unique for the winning attempt.

Known uncertainties: active dirty host/runtime repairs; authoritative eventual execution composition; current host registration HTTP500; Codex policy currently advertises fal destinations; heterogeneous manifest/grouping details; provider credentials and disposable GPU availability. T1 owns source/contract uncertainty, T3 result-shape uncertainty, T4 Codex/provider specifics, T5 generic workflow declarations, T6 live evidence. These do not authorize new infrastructure or the separate GPU migration.
