# Integration & E2E tasklist — dormant until receiver activation

The Integration-owned thin checklist/manifest runner uses this run's
`worker_normal` route. Product fixes and repository implementations route to the
owning project's declared worker. Integration does not create implementation
tasks or review verdicts. Original project task IDs and owning reviews remain
authoritative.

| ID | Outcome and scope | Dependencies | Acceptance evidence |
|---|---|---|---|
| INT-01 | Prepare the receiver after the accepted UE continuation checkpoint. Perform readonly discovery of setup/start/discovery/auth/test/evidence entry points; consume source and contract identities; define the final journey and exact manifest fields. Track an explicit **V1 fixture-ready** prerequisite (real decodable media, checksummed A/B identities, hidden truth separation and capture/viewing capability) feeding UX-01; V1 owns its implementation. | UE P7 CPU closure and continuation checkpoint; readonly discovery may precede it | Source/contract inventory; candidate manifest schema; fixture-ready status and owner; no product mutation |
| INT-02 | Assemble one code-ready candidate from all six required project results and upstream gates. Consume E2-06 only after completed V1; reconcile changed dependencies, conflicts and target-main drift; do not perform final proof here. Final reviews that require INT-03 evidence remain downstream of the campaign. | INT-01; UE, DB, GEN, V1, RRP and E2 code-ready results; E2-06; upstream gates needed for assembly | One pre-merge cross-repository manifest with remotes, roots, refs, branch, commit/tree SHAs, dirty decisions, dependencies, generated-client identity, expected target-main heads and candidate tests; accepted candidate composition |
| INT-03 | Exercise one practical disposable CPU/local setup and connected supported workflow on the settled candidate. Collect candidate-specific evidence. Coordinate any still-required original UE GPU/live acceptance through UE's existing manager and budget; if matching proof already exists, consume it rather than duplicate it. | INT-02; relevant changes settled; fixture-ready; credentials/capture and UE authorization where applicable | Commands and versions; startup/discovery identity; synthetic caller-exit/publication/retrieval; explicit timeline/render/opening; V1 authored/filmstrip and RRP regression; disposable E2 retention/pin/lease/expiry/promotion proof; applicable UE B06-T04/B06-T05 proof or explicit missing evidence; original owning review for any coordinated proof |
| INT-04 | Coordinate normal dependency-order merges/pushes after required checks and owning reviews; verify final remote-main identities and supported-entry-point identity smoke; hand off META-5/META-6 evidence. | INT-03; all required original criteria/reviews; no unresolved drift | Expected-vs-observed remote SHA/tree equality per repo; final dependency/generated-client parity; final smoke results; links to PRs/commits/evidence; no partial completion claim |

## Routing and review rule

No integration review stages are declared. `run.yaml` sets `oracle.max_calls: 0`:
this means no independent oracle calls or standing review panel for this thin
receiver. Consequential decisions, contested findings and exceptions route to
the owning project's existing oracle or the portfolio meta oracle under its
remaining existing budget; this receiver cannot waive a gate or create budget.
Upstream reviews must pass before INT-02 consumes a code-ready result. Reviews
whose required evidence is produced by INT-03 must pass after that campaign and
before INT-04. The portfolio orchestrator retains META-5 acceptance authority.

## Manifest completeness gate

At INT-02's candidate handoff, reject a manifest that lacks any selected repository's remote,
root, branch/ref, tested SHA/tree, dependency edges, generated-client identity,
expected-main tests, candidate tests or expected target-main SHA/tree. At
INT-04, additionally require the observed final remote-main SHA/tree and
equivalence evidence. The workspace host path is recorded as control context
only and never as an aggregate source row.
