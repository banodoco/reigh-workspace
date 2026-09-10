> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# E2 handover: ephemeral derived-artifact lifecycle

Date: 2026-09-10. Research-only integration recommendation for the existing
planning package `Astrid/.otto/runs/ephemeral-derived-artifact-lifecycle-20260910`.
No implementation, database operation, test, launch, deletion, service action,
commit, or original-run mutation was performed.

## Recommendation

Keep Plan 2 (E2) as a distinct project with a distinct manager, but not as a
new storage/database authority. The E2 manager owns the lifecycle contract,
cross-project ledger, synthetic-producer evidence, and E2 acceptance. Existing
Runtime/DB ownership remains the sole writer for Runtime schema, CAS metadata,
leases, events, receipts, and settlement. Existing Astrid/UE integration
ownership remains the sole writer for GenericPackHost/result-manifest and
generated-client/host changes. V1 retains ownership of visualization output
semantics and its own acceptance.

The manager boundary is useful because E2 spans Runtime, host publication and
V1 migration. It must coordinate those authorities, not create a parallel
`review_artifacts` database, pack-local ledger, producer-specific table, or
second lease system.

## Scope to carry forward

The E2 North Star is the correct v1 simplification:

* Primary image/video/audio generation outputs are durable by default.
* Previews, crops, filmstrips, HTML, exact frames, copied offline media and
  similar derivatives are temporary by default.
* Output intent/provenance is immutable manifest/member data; expiry, leases,
  pins and promotion state are Runtime-owned mutable metadata.
* Identity is the verified manifest/CAS digest and source/member provenance;
  filesystem paths are disposable locators, never authority.
* Promotion creates normal project media with provenance without changing the
  derivative's digest/identity. Cleanup may remove only an expired, temporary,
  unpinned derivative with no active lease.

E2 must not silently classify existing primary media as temporary. Adoption is
digest-verified and identity-conflict-safe; missing source/recipe inputs return
an explicit unavailable result rather than substituting `latest`.

## Current package and oracle disposition

The package is `planning_only` / `READY_FOR_DELIVERY_SETUP_ONLY`; no stages have
run. Its source snapshot records dirty HEAD
`32910818874b4699281b7ab2b1bd000097ac1c8d` on
`recovery/runpod-s3-multipart-20260903`, and calls that dirty source
authoritative. That is stale custody information for portfolio execution, not
permission to write it. Current actual Astrid/Runtime source and the UE
`megado-unified-v3` P7 candidate must be recovered and explicitly identified.

The archived adopted oracle decision (RR-ORACLE-001) supports: orthogonal
durability/retention/pin/promotion; generic task/artifact events and receipts;
manifest/CAS rather than paths; optional parent linkage for stateless ranges
but required lineage for manifest-derived outputs; bounded overviews with
mandatory first/last/tail boundary cards plus adaptive interior; and removal of
speculative CLI examples. It also says to extend the existing visualizer and
not claim proposed lifecycle/overview/TTL APIs are already implemented.

Budget is shared centrally with V1: original maximum 3, one used by
RR-ORACLE-001, two remaining across V1 and E2. E2 setup used zero calls. Keep
one ledger; do not count E2 calls twice or confuse V1's capped Astra UX
invocations with oracle calls.

## Sequencing and gates

Use the portfolio's controlling order:

1. **UE-P7 checkpoint.** Recover the current `megado-unified-v3` handoff,
   manager, accepted session/publication receipts, remaining CPU closure rows,
   CR2/freeze state and exact multi-repo candidate. Continue P7 CPU closure;
   do not restart historical P0–P6 from the failed wrapper or old 22/1/22
   checkpoint.
2. **Current-main + relevant dirty integration.** Establish explicit custody
   for Astrid and Runtime, reconcile the dirty deltas, and compose only the
   UE/P7 changes relevant to the common host/session/publication boundary.
   Record one resulting source/contract identity. Unidentified dirty drift is
   a hold, not a valid baseline.
3. **Validated common baseline.** DB-T1→T3/foundation and GEN-T1/T2 must
   settle the canonical fresh schema, verifier, output envelope, publication
   mapping, generated-client revision and idempotency/error parity. The
   retained-session contract is consumed only after the UE S handoff plus
   consumer CPU proof. Runtime DB remains the writer for overlapping files.
4. **E2 dependent work.** After that baseline, E2-01 can freeze the shared
   output-intent/provenance contract with a synthetic producer. E2-02 then
   adds Runtime-owned mutable lifecycle metadata and generic mutations/events.
   E2-03 (adoption) and E2-04 (lease/pin/TTL/promotion/deletion) may be
   prepared in parallel but share schema/transaction safety and should use one
   serialized Runtime implementation turn. E2-05 follows E2-01/02.
5. **V1 migration gate.** E2-06 waits for V1-01–06 deterministic gates,
   real fixture/capture, and the declared V1 UX acceptance scope. It then
   migrates the existing visualizer's overview/detail members and proves the
   shared lifecycle journey end to end. E2 does not widen V1 into a new
   review product or block independent V1 work before this gate.

E2-01's contract design should be a joint input to DB-T1 and GEN-T1, not a
third schema proposal. E2-02's publication semantics must align with GEN-T2
and host settlement. E2-06 is the only E2 task that is downstream of V1;
E2-01–05 remain independently implementable against the synthetic producer.

## Concrete acceptance gates

* **E2-01 contract PASS:** synthetic producer emits source/task/run identity,
  manifest/member digest, role, coverage, frozen recipe/inputs, durability,
  regeneration capability and immutable provenance through existing capability
  and result-manifest ports.
* **E2-02 lifecycle PASS:** mutable lifecycle metadata is Runtime-owned;
  idempotent retry returns the original publication; changed payload under the
  same key conflicts; generic task/run/artifact events and command receipts
  carry the mutation; no review event ledger exists.
* **E2-03 adoption PASS:** existing CAS/durable output and cache adoption is
  byte/digest verified, deduplicates shared bytes, rejects conflicting
  identity, and never performs broad deletion.
* **E2-04 retention PASS:** an unpinned active lease prevents deletion;
  pin/unpin and promotion are auditable Runtime mutations; only unpinned,
  expired temporary derivatives are deleted; durable primary output survives.
  Rehydration uses recorded digest + recipe only.
* **E2-05 producer PASS:** a second independent producer uses the same
  contract and lifecycle with no producer-specific table, event family, or
  authored-media row for derivatives.
* **E2-06/V1 PASS:** selected render identity is preserved; overview/detail
  members, cache rehydration, stale-render rejection, pin/GC/promotion and
  missing-input/unavailable behavior are evidenced on the V1 fixture.

## Actual contract touch points (and limits)

* Capability semantics already exist in
  `Astrid/docs/contracts/capability-artifact-contract.md:13-54,72,182-205`.
  `artifact_type` is an extensible semantic type and is used-if-present; E2
  should add output intent/provenance to this waist/result-manifest contract.
* Universal manifests require `schema_version`, `kind`, `inputs`, `outputs`,
  `created`, and `warnings` (`Astrid/astrid/core/_shared/result_manifest.py:29-32`).
  Harvest uses `{out}/manifest.json` as the receipt and does not infer identity
  from names/suffixes (`:610-660`).
* Host `_typed_outputs` verifies declared port, contained staged path, SHA-256,
  byte count, role and `is_primary` (`Astrid/astrid/core/execution/generic_host.py:2044-2105`).
  `_upload_outputs` publishes immutable CAS objects (`:2286-2347`), then
  `run_task` harvests, uploads and calls fenced settlement (`:2924-3029`).
  Attempt-root cleanup at `:3049-3053` is command-end scratch cleanup, not an
  artifact TTL/GC implementation.
* Host leases are task-attempt controls: heartbeat and settle carry
  `attempt_id`, lease token, fence and runtime epoch with deterministic
  idempotency keys (`generic_host.py:1041-1093`). Artifact leases/pins must be
  distinct lifecycle references, while settlement must fail closed if either
  Runtime lease or the UE admission/session fence is stale.
* Runtime currently has digest-keyed `objects`, project-scoped
  `project_objects`, `runs`, `tasks`, `events`, `attempts` and `reservations`
  (`banodoco-workspace-runtime-execution-20260909/runtime_protocol/migrations/001_initial.sql:11-44`,
  `store.py:44-83`). There is no generic lifecycle metadata table, no
  `task_outputs` table in this checkout, and no TTL/pin/promotion/GC operation.
  E2 must target the actual selected baseline, not assume a `task_outputs` API.
* `service.py:2047-2129` ingests CAS bytes with digest dedupe and project
  association. `claim_next` (`:2428-2488`) creates the attempt lease/fence;
  `settle_attempt` (`:2491-2564`) validates epoch/fence, stages outputs and
  delegates atomic settlement. `store.py:1822-1862` updates task/run/attempt,
  publishes objects and appends `task.completed` in one transaction.
* Generic event and receipt primitives are `store.py:1363-1379` (hash-chained
  run events) and `:1411-1432` (command idempotency, transaction/project
  sequence and event IDs). Reuse these; add a domain event only if E2 proves
  a unique lifecycle semantic.
* V1's `prepare_filmstrip` rejects caller paths, selects a managed successful
  render, verifies project ownership of the video digest and snapshots frozen
  authority (`Astrid/astrid/sdk/timeline_filmstrip.py:197-270`). This is the
  correct E2-06 authority seam; its cache is a rehydration, not identity.

## Custody and return condition

Before delivery, the orchestrator must record the current UE P7 source and
receipts, selected Astrid/Runtime baseline, E2 manager, exact write sets and
the single shared oracle ledger. If the runtime cannot atomically settle
manifest identity and mutable lifecycle metadata, stop at that explicit
contract gap: preserve existing durable bytes and return an unavailable/error
result. Do not delete, reclassify, migrate or silently adopt existing outputs.

This report is intentionally only a handover recommendation. The candidate's
stale dirty snapshot (`3291081…`) is evidence to reconcile, not current
custody. The `.otto` report location is the requested control folder; any
`.auto` relocation remains an orchestrator/user-path decision.
