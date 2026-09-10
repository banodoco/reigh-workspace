# Integration & E2E plan

## Minimum useful outcome

Assemble the accepted UE, database, generation, visualization, render and
ephemeral results into one explicitly identified cross-repository candidate;
exercise that candidate through the ordinary disposable setup/start/discovery
path and one connected CPU/local workflow; then coordinate normal final merges
and prove remote `main` trees equal the tested composition. Return exact source,
dependency, test and evidence identities to the orchestrator.

This is a receiver plan. It does not reimplement any project's behavior or
turn the workspace host into an aggregate source repository.

## Inputs and custody

INT-01 starts after the accepted P7 continuation checkpoint, but read-only
discovery may begin earlier. The active UE manager supplies the exact candidate,
preserved dirty inputs, accepted session/publication contracts, P7 CPU evidence,
remaining physical proof, review counters and resource balance. Historical UE
files and published snapshots are inputs to reconcile, not acceptance.

Use the canonical [repository custody and push strategy](../../repositories.md)
for the remote inventory, ownership boundaries and promotion rules, and
[fixture readiness](../../fixture-readiness.md) for the V1-owned prerequisite.
Known preservation pins (not final acceptance) remain in
[source-publication.md](../../source-publication.md). Before INT-02, the active
UE handoff must supply exact remote, root, branch, commit SHA and tree SHA,
including preserved dirty-input decisions, for every consumed repository. Do
not select an older VibeComfy handover ref or the workspace recovery branch by
implication. The workspace host (`banodoco/reigh-workspace`, the invoking
workspace root) stores control documents only and is not an additional source
row or aggregate checkout.

## Exact cross-repository manifest

Integration maintains one candidate manifest (an execution evidence artifact,
not a product service). It must have one row for every repository actually in
the UE closure, at minimum Astrid, Banodoco Workspace Runtime, Reigh app, Reigh
worker and VibeComfy; add any UE-named repository only when the handoff proves it
is in scope. Each row records:

`repository name`, `remote URL`, `repository root`, `tested branch/ref`,
`tested commit SHA`, `tested tree SHA`, preserved input refs and dirty/untracked
include/exclude decisions, dependency refs/versions, generated-client
producer contract identity plus generator/schema/version and consumer file
identity, expected tests on target `main`, tests run on the candidate, expected
target-main SHA/tree before promotion, and (only after INT-04) observed final
remote-main SHA/tree plus equivalence evidence. Include evidence
links/timestamps.

The manifest must also state the cross-repository dependency edges (Runtime
protocol/schema → generated client → Astrid host/SDK; UE session/host contract →
consumers; generation/publication → E2 lifecycle and render opening; V1 fixture
→ UX/E2 final integration), exact test commands and result identities. For the
generated client, identify the Runtime producer schema/contract and generator,
the generated file in Runtime and the vendored/consumer file in Astrid, their
commit/tree/blob or content digest, and the parity test. A blank,
guessed or aggregate workspace value is a missing field, not a PASS. Generated
clients are regenerated through the producer contract when required and checked
for parity; they are never hand-merged as an unexplained artifact.

## Sequence

1. **INT-01 — prepare.** After the continuation checkpoint, consume source and
   contract manifests, inventory supported setup/test/evidence entry points, and
   define the final journey and manifest fields. Record the V1 fixture-ready
   deliverable early so the final manager cannot discover it missing at the end.
2. **INT-02 — assemble.** Wait for all six required project results to reach
   code-ready upstream gates and for E2-06 to consume completed V1. Consume the
   upstream reviews that are prerequisites to those handoffs; do not wait for a
   final review whose evidence is produced by INT-03. Integrate code-ready
   accepted inputs continuously; inspect only changed dependencies and
   conflicts; reconcile final target-main drift. INT-02 does not require
   evidence that INT-03 is supposed to produce.
3. **INT-03 — exercise.** Once relevant changes settle, use a fresh disposable
   development realm and clean environment pinned to the candidate. Follow
   documented installation/start/discovery/authentication. Run one connected
   CPU/local journey: project selection; deterministic synthetic generation and
   publication after caller exit; canonical result retrieval; explicit timeline
   placement; authored synthetic render; correct named managed render while a
   newer render exists elsewhere; actual authored/filmstrip inspection; pinned
   A-after-B identity; and disposable derivative rehydration, pin/lease/expiry
   and promotion while durable/shared bytes survive. Reuse V1's required UX
   sequence and RRP's decisive regression; do not invent a third UX critique.
   Coordinate any original UE final GPU/live proof through UE's manager only
   when ready and authorized: the applicable B06-T04 final real-GPU journey and
   B06-T05 live interrupt/reclaim proof, with UE's original owning review before
   INT-04. The aggregate historical-plus-new GPU cap remains USD 6, one pod at a
   time, with the existing attempt/time/storage limits; do not duplicate a proof
   that still matches the candidate.
4. **INT-04 — merge and verify.** Only after all relevant checks and owning
   reviews pass, coordinate ordinary dependency-order merges/pushes. There is no
   atomic multi-repository merge. Freeze expected target-main heads, fetch final
   remote identities, compare final trees to the tested composition, and run a
   small supported-entry-point identity smoke on those main revisions. Stop the
   affected promotion on branch drift; after squash/rebase, prove tree and
   dependency equivalence or rerun affected checks. Return the manifest and
   evidence to the orchestrator for META-5/META-6.

## Boundaries and stop conditions

No deploy, old-data migration, production cutover, destructive realm cleanup,
new paid spend, force-push, protection bypass, partial “complete” merge, or
unapproved budget expansion. Stop only the affected promotion on conflict or
drift. Missing credentials, capture, fixture, required review, exact UE handoff,
or physical/GPU evidence remains explicit outstanding evidence. A clean setup
or synthetic workflow cannot waive those requirements.

Conditional estimate: 2–4 focused engineering days for the thin receiver after
an accepted continuation checkpoint, excluding fixture/product implementation,
owning reviews and any live/GPU wait. The practical uncertainty is exact UE
source/contract recovery, cross-repository drift, generated-client parity and
fixture/capture availability. Agent elapsed time and manager count do not alter
the portfolio's budgets.
