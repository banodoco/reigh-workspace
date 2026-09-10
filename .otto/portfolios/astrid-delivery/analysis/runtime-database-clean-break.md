> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Runtime database clean break — boundary and sequencing report

Research date: 2026-09-10. This is a planning/research report; no product files,
databases, branches, worktrees, services, or tests were changed or launched.

## 1. Purpose and concrete user impact

The project proposes a clean break from the current migration-heavy runtime to
one runtime-owned SQLite authority. A fresh realm is explicitly created,
verified, durably published, and then registered; opening a missing or legacy
root does not create or upgrade it. A read-only verifier gates writable open,
mutation, and readiness. Snapshots include WAL-committed SQLite state and all
referenced CAS objects; recovery verifies a snapshot into a fresh root, retains
the damaged root, and fences the superseded owner.

The before/after user impact is concrete:

- Before: `RealmStore` can create directories during construction and call
  startup migration (`runtime_protocol/store.py:149-195,395-412,424-490` in the
  inspected runtime checkout); admission has `allow_migration` and a narrow
  identity-only legacy exception.
- After: one exact format/identity is accepted; corrupt, incomplete, or
  unsupported roots fail closed without source mutation. Fresh development
  provisioning is an explicit operator action.
- Before: backup restore ends as an inactive candidate and catalog registration
  uses separate read and write operations. After: verified replacement is a
  coordinated owner shutdown/catalog switch/fresh-credential-and-epoch
  operation, and catalog registration/selection serializes the complete
  read-modify-write.
- Before: runtime, CLI, Astrid bootstrap, and migration tools expose duplicate
  lifecycle paths. After: server, CLI, Astrid, and packs use one lifecycle
  boundary while retaining typed HTTP errors, generated-client behavior,
  receipts, CAS consistency, ownership, and fencing.

The architecture document calls this a clean break because existing realms and
backups become unsupported legacy artifacts, preserved separately rather than
upgraded (`Astrid/docs/architecture/runtime-database-clean-break-plan.md:7-19,
21-36`). It explicitly does not claim to identify the physical corruption
trigger (`Astrid/docs/architecture/runtime-database-clean-break-plan.md:163-168`).

## 2. Current status, source identity, and custody

The run is `SETUP_READY` and paused. Tasks T1–T7 are pending; no implementation,
execution tests, review, deployment, commit, or branch creation has occurred
(`Astrid/.otto/runs/runtime-database-clean-break-20260910/status.md:7-14`).
The selected full scope is C1–C8 with a provisional 6–9 focused-day estimate
and 10–15-day contingency; the proposed 3–5-day milestone is explicitly not
the selected contract (`Astrid/.otto/runs/runtime-database-clean-break-20260910/README.md:3-7`, `Astrid/.otto/runs/runtime-database-clean-break-20260910/plan.md:18-20`).

Recorded Astrid source:

- Repository/worktree: `<workspace>/Astrid`.
- Branch/HEAD at capture: `main` / `82d09bb91c8a4621695c1d8b6966652cad941ef4`.
- Captured tree was dirty, including modified Astrid callers/generated clients
  and an untracked architecture plan; no product files were staged or
  committed (`Astrid/.otto/runs/runtime-database-clean-break-20260910/source-state.md:1-5`; `Astrid/.otto/runs/runtime-database-clean-break-20260910/source-status.txt:1-90`).
- Current read-only check still reports `main` at that HEAD and the same broad
  dirty set, including `astrid/sdk/host_bootstrap.py`, `astrid/sdk/invocation.py`,
  `astrid/sdk/workspace_client.py`, `banodoco_workspace_client/generated.py`,
  and many timeline/generic-host tests. The dirty tree is user-owned planning
  input, not evidence of this project being implemented.

Recorded runtime source is a different checkout:

- `<workspace>/banodoco-workspace-runtime-execution-20260909`.
- Branch/HEAD: `codex/canonical-timeline-replacement-20260909` /
  `afccb430e2a983c968b6a8a96fd630ba3a6262fc`; it is dirty in
  `runtime_protocol/store.py`, `service.py`, `backup.py`, `catalog` callers,
  generated clients, migration tools, and an untracked hardening test.
- The run records this as an implementation location discovered by read-only
  exploration, not as authorized delivery custody
  (`Astrid/.otto/runs/runtime-database-clean-break-20260910/source-state.md:7-22`). The architecture plan itself is untracked in
  the Astrid checkout and has recorded SHA-256
  `9cce8e3310759a712031b0f2e2e637d39ffa5fdd1a2b6d34da564b49cb4be7ac`
  (`Astrid/.otto/runs/runtime-database-clean-break-20260910/source-state.md:3-5`). Recheck both identities at T1.

Custody is a material sequencing issue. The database run's user amendment
requires the existing main checkout, no new branches or implementation
worktrees, preservation of unrelated dirt, and serial ownership of overlapping
files (`Astrid/.otto/runs/runtime-database-clean-break-20260910/agent_goal.md:10-13`; `Astrid/.otto/runs/runtime-database-clean-break-20260910/tasklist.md:6-7`). The generation-path run
instead says T1 selects isolated custody after authorization and does not do a
Reigh migration (`.otto/runs/astrid-generation-path-alignment-20260910/tasklist.md:7-8`).
That is a direct policy conflict for shared runtime files, not merely a merge
conflict. The database project should be canonical owner of runtime source and
runtime lifecycle files. Generation may isolate Astrid-only adapter work only
after the runtime contract is frozen, then integrate it into the main checkout
through an explicit source/diff reconciliation gate; it must not edit the dirty
runtime checkout concurrently.

## 3. In-scope, out-of-scope, owned contracts, invariants

In scope is the owning runtime repository and its CLI/server lifecycle,
canonical schema/identity, verifier, admission/transaction fence, receipts and
CAS publication, WAL-aware snapshot, replacement recovery, catalog registration
and readiness, generated clients, Astrid bootstrap/callers/packs, tests, and
operator guidance (`Astrid/.otto/runs/runtime-database-clean-break-20260910/agent_goal.md:13`). T1 must first close this inventory.

Out of scope: physical corruption forensics; salvage or migration of old realms;
compatibility bridges; generalized storage infrastructure; new cloud/GPU
infrastructure; operating against real development/production data
(`Astrid/.otto/runs/runtime-database-clean-break-20260910/agent_goal.md:15-19`). Existing roots/backups remain preservation inputs,
never fixtures or upgrade targets.

Owned invariants are the North Star: one canonical SQLite format and verifier;
`closed → verifying → ready → failed`; only ready permits mutation/readiness;
one lock for admission and transaction entry; atomic receipts/domain writes;
CAS publication rollback; immutable verified snapshots; fresh replacement
credentials/epochs; serialized catalog RMW; truthful liveness/readiness; and
typed HTTP/generated-client parity (`Astrid/.otto/runs/runtime-database-clean-break-20260910/northstar.md:1-7`; `Astrid/.otto/runs/runtime-database-clean-break-20260910/implementation-criteria.md:5-12`).

## 4. How it runs and where state crosses boundaries

### Startup and serving

The current runtime entry points are `python -m runtime_protocol.cli start`
(`runtime_protocol/cli.py:17-38,136-156`) and the local operator wrapper's
`banodoco-local up/connect/restart/doctor/backup/restore/recovery`
(`banodoco_local/cli.py:51-103,230-291`). `RuntimeDaemon.start()` constructs
`RuntimeService`, provisions owner and worker credentials, creates the HTTP
server, registers the realm in the support catalog, writes owner-lock state,
then publishes discovery (`runtime_protocol/daemon.py:38-67,83-109`).

`RuntimeService.__init__` currently constructs `RealmStore(strict_admission=True)`,
ensures a realm, runs doctor, starts a runtime session/epoch, and then recovers
CAS journals (`runtime_protocol/service.py:219-249`). Mutations are wrapped by
`_verified_mutation`/`_durable_mutation`, taking the store mutex, checking
admission, entering a transaction, and reconciling CAS publication journals
after rollback/commit (`runtime_protocol/service.py:189-216`). Receipts are
allocated and written inside the active transaction (`runtime_protocol/store.py:1411-1430`).

The current health path calls `doctor()` under the same store mutex
(`runtime_protocol/service.py:272-281,320-329`). This is precisely the RRP
diagnostics concern: unbounded CAS hashing must move to an explicit offline
audit or consistent snapshot; cheap liveness/readiness must not starve normal
requests. This is an integration dependency, not permission to redesign the
database verifier outside C2.

### Verification, storage, and publication

`RealmStore.inspect_realm()` copies SQLite and sidecars to a private temporary
directory, checks source component identity, and runs inspection without
opening the original database (`runtime_protocol/store.py:261-320`). The
current `_open()` creates CAS/staging directories, enables WAL/foreign keys,
and calls `_migrate()` (`<workspace>/banodoco-workspace-runtime-execution-20260909/runtime_protocol/store.py:395-412`), all of which T2 must reconcile
with explicit fresh creation and exact canonical format.

`integrity_report()` performs SQLite quick check, foreign-key checks, table and
column shape checks, identity cardinality, CAS reachability/hash checks, event
chain checks, and optional catalog/activation checks
(`<workspace>/banodoco-workspace-runtime-execution-20260909/runtime_protocol/store.py:2023-2056,2056-2156`). These are valuable retained mechanisms;
`allow_migration`, migration ledger handling, repair-on-open behavior, and
identity-only exceptions are the planned deletion/strictening surface.

`create_backup()` takes the owner mutex, uses SQLite backup, copies referenced
CAS objects, writes authenticated manifests, fsyncs, atomically renames the
candidate, and verifies the published result (`runtime_protocol/backup.py:552-637`).
`restore_backup()` verifies the source, materializes a new candidate, inspects
it, writes an activation handoff, and atomically publishes an inactive root
(`<workspace>/banodoco-workspace-runtime-execution-20260909/runtime_protocol/backup.py:659-732`). It does not yet constitute the complete planned
replacement boundary: owner shutdown, active catalog switch, credential renewal,
fresh epoch relative to the superseded owner, and interruption recovery remain
T4/T5 work.

### Catalog, discovery, and consumers

`RealmCatalog.register()` and `.select()` each call `read()` then atomic write,
but the lock does not span the full read-modify-write (`runtime_protocol/catalog.py:61-125`).
`LiveDiscovery` is intentionally ephemeral and path/secret-free
(`<workspace>/banodoco-workspace-runtime-execution-20260909/runtime_protocol/catalog.py:128-163`); discovery must advertise only an admitted runtime,
never become database authority. Astrid's generated/typed client exposes
health, doctor, create-backup, and restore-backup (`Astrid/astrid/sdk/workspace_client.py:171-274`),
while the gateway dispatches backup operations through that client
(`Astrid/astrid/core/gateway/dispatch.py:103-190`).

Persistent state includes `realm.sqlite3` plus WAL/journal sidecars, CAS under
`cas/sha256`, staging/publication journals, owner lock, support catalog,
discovery, credentials, runtime session/epoch, and activation handoff. Outputs
are typed HTTP responses/receipts, verified backup directories, fresh inactive
roots, catalog/discovery records, and operator-readable next actions. A failure
must leave source roots and backups untouched, avoid accepted partial
publication, revoke readiness, and provide a recoverable state; publication is
not complete until verification and ownership/discovery gates pass.

## 5. Touch map

| Repository/file/symbol | Intended change | Consumer | Overlap; scope confidence |
|---|---|---|---|
| Runtime `runtime_protocol/store.py:149-195,261-361,395-490,2023-2160` (`RealmStore`) | Canonical fresh schema/identity, read-only verifier, no implicit create/migration, missing-root refusal before lock-directory creation | `RuntimeService`, backup, daemon | DB T2 explicit; same runtime files are off-limits to generation/RRP concurrently |
| Runtime `runtime_protocol/service.py:189-249,272-329` (`RuntimeService`) | Thin enforced lifecycle/admission boundary; retain receipts/CAS reconciliation; separate cheap health from deep audit as needed | HTTP server, CLI, Astrid client | DB T3 explicit; RRP RRP-02 semantic overlap in health/audit |
| Runtime `runtime_protocol/backup.py:346-390,552-637,659-732` | Reuse backup/restore; verify candidate before publication; complete replacement handoff and interruption recovery | operator CLI/service, launcher | DB T4 explicit; RRP-03 recovery activation depends on this contract |
| Runtime `runtime_protocol/catalog.py:61-163` (`RealmCatalog`, `LiveDiscovery`) | Serialize registration/selection RMW; ensure admitted-owner/readiness publication | daemon/local launcher, Astrid bootstrap | DB T5 explicit; RRP-03 launcher integration consumes it |
| Runtime `runtime_protocol/daemon.py:38-119` | Ensure start/stop/catalog/discovery/credentials honor canonical admission and fresh epoch | local launcher, pack host | DB T4/T5 contract; RRP-03 process ownership integration |
| Runtime `runtime_protocol/cli.py:17-156`, `banodoco_local/cli.py:51-103,230-291` | Explicit create/restore/recovery guidance; remove migration/compatibility commands and aliases | operators | DB T6 explicit; RRP tests normal CLI access |
| Runtime `tools/astrid_migrate/*`, `tests/test_receipt_migration.py` | Delete migration tools/bindings and adapt safety tests without deleting safety coverage | test/operator surface | DB T6 explicit; `tests/test_dirfd_publication.py:46` needs adaptation |
| Astrid `astrid/sdk/host_bootstrap.py:474-506` | Remove `legacy_empty_inventory` fallback once canonical readiness/source identity is settled | GenericPackHost | DB T6 explicit; timeline and generation both modify adjacent bootstrap closure |
| Astrid `astrid/sdk/workspace_client.py:171-274`, vendored generated client/metadata | Regenerate once after typed lifecycle contract settles; preserve HTTP/error parity | all Astrid callers/packs | DB T6 explicit; exact files overlap timeline and generation |
| Astrid gateway/bootstrap callers and pack entry points | Route all lifecycle operations through runtime; no pack-owned DB access | Astrid CLI, packs | DB T6 explicit; consumer closure also touched by generation/RRP |
| Runtime tests `test_realm_admission_hardening.py`, `test_runtime_reboot.py`, `test_dirfd_publication.py`, `test_client_parity.py` | Retain/adapt fixtures for C1–C7, including WAL, receipts, stale workers, publication races, typed errors | acceptance evidence | DB T2–T7 explicit; some existing fixtures currently import migration code |

## 6. Dependencies, parallelism, and serialization

The safe dependency chain is T1 → T2 → T3 → (T4 and T5 in parallel where file
ownership permits) → T6 → T7. The foundation review follows T3 and gates T4/T5;
the final review follows T7 (`Astrid/.otto/runs/runtime-database-clean-break-20260910/tasklist.md:9-19`; `Astrid/.otto/runs/runtime-database-clean-break-20260910/run.yaml:15-31`).

T1 is read-only and can run alongside other projects' read-only source maps. It
must resolve which main runtime source is authoritative, inventory current dirty
changes, map every C1–C8 proof to retained code/fixture/gap, and freeze the
format contract before edits. T2 is the schema/verifier foundation. T3 can
consolidate admission/transaction/receipt/CAS mechanisms after T2. T4 and T5
can then split by file ownership: T4 owns backup/replacement and owner/epoch
handoff; T5 owns catalog full-RMW and readiness/discovery semantics. They must
serialize if they touch daemon/service lifecycle code or shared recovery tests.

T6 must wait for T4/T5 because generated clients and Astrid callers should be
regenerated exactly once against the settled contract. T7 is the only place for
the complete corruption/concurrency/crash/HTTP matrix and broad affected suite.
No real realm, corrupt root, or production backup is a fixture.

### Explicit project overlaps

- Generation path alignment shares Astrid `generic_host.py`, `host_bootstrap.py`,
  `invocation.py`, `workspace_client.py`, vendored generated clients, and
  related tests (its recorded source map/status is
  `.otto/runs/astrid-generation-path-alignment-20260910/source-state.json:5-17`).
  Its T1/T2 runtime settlement work must not edit DB-owned runtime files; its
  T3 consumer work waits for the canonical lifecycle/client contract. This is
  both a same-file collision and a semantic dependency.
- Timeline visualization V1-01–V1-06 is intentionally self-contained and its
  selected dirty closure includes `astrid/packs/timeline/cli.py`, timeline
  visualization modules, `generic_host.py`, `host_bootstrap.py`, `invocation.py`,
  `timeline_filmstrip.py`, `workspace_client.py`, generated clients, and tests
  (`Astrid/.otto/runs/timeline-visualization-fixes-20260910/source-provenance.md:14-50`).
  Its status says Plan 2/lifecycle migration is separate and owns later E2-06
  (`Astrid/.otto/runs/timeline-visualization-fixes-20260910/status.md:3-7`; `Astrid/.otto/runs/timeline-visualization-fixes-20260910/references/plan2-migration-pointer.md:1-5`).
  V1 can proceed as a visualization-only consumer, but bootstrap/client edits
  and final integration must reconcile with DB T6.
- RRP-03 explicitly proposes one launcher-owned recovery activation path that
  verifies a candidate, preserves original/backup, stops or rejects a prior
  owner, updates catalog/launcher state, starts normal Runtime, and verifies
  discovery (`Astrid/.otto/runs/runtime-render-path-reliability-20260910/plan.md:70-79`).
  This overlaps DB T4/T5 semantically even if RRP edits launcher files and DB
  edits runtime files.
- The ephemeral derived-artifact project is a dependency pointer, not a fifth
  implementation assignment. E2-01–E2-05 can use a synthetic producer; E2-06
  waits for completed Plan 1 visualization and owns its later lifecycle
  migration (`Astrid/.otto/runs/ephemeral-derived-artifact-lifecycle-20260910/tasklist.md:3-10`,
  `Astrid/.otto/runs/ephemeral-derived-artifact-lifecycle-20260910/status.md:3-6`). It should not redefine DB realm lifecycle or readiness.

### Canonical owner for RRP-03

DB T4/T5 must own the runtime truth: candidate verification, inactive-root
materialization, old-owner shutdown/fencing contract, catalog atomicity,
credential renewal, runtime epoch freshness, and readiness/discovery admission.
RRP-03 should own launcher-facing orchestration only: invoking that runtime
operation, supervising the normal launcher, rejecting manually started
non-owned processes, and proving normal discovery plus CLI access. It must call
the DB-owned API rather than duplicate restore, catalog RMW, credential, or
epoch logic. Sequence RRP-01 read-only tracing in parallel; defer RRP-03
implementation and end-to-end activation tests until DB T3 foundation and the
T4/T5 interface are accepted. This avoids two competing recovery authorities.

## 7. Validation and acceptance gates

No acceptance criterion has been tested during setup (`Astrid/.otto/runs/runtime-database-clean-break-20260910/implementation-criteria.md:1-3`).
Future evidence must use disposable roots/catalogs and exact integrated source
identity. Required gates are:

1. C1/C2: explicit fresh creation; wrong/missing schema or identity rejection;
   missing root refusal before lock directory; read-only verifier with SQLite,
   FK/relational, CAS, catalog, and WAL/journal evidence; no source mutation.
2. C3: owner contention and admission races; same lock through transaction
   commit; atomic domain+receipt rollback; CAS publication recovery; readiness
   revoked after observed integrity/ownership failure.
3. C4/C5: WAL-only committed state round trip; bad/missing CAS rejection;
   verify-before-publish; immutable snapshots; interrupted materialization,
   owner shutdown, catalog switch, fresh credential/epoch, stale-worker
   rejection, retained damaged root, and recoverable interruption states.
4. C6: concurrent-process registration/select without lost updates; readiness
   only for an admitted owner; liveness distinct from readiness.
5. C7/C8: representative runtime/CLI/Astrid/pack domain success plus typed
   errors; generated client parity; migration/compatibility removal census;
   explicit fresh-realm operator docs and preservation inventory.

The foundation review must certify C1–C3 after T3. Final review certifies C1–C8
after T7 (`Astrid/.otto/runs/runtime-database-clean-break-20260910/run.yaml:15-31`). Existing test definitions, including the
untracked hardening tests listed in `source-status.txt:37-52`, are evidence of
coverage intent only, not passing results. RRP's C1/C2 offline-audit tests and
C3 activation tests should be linked to these DB proofs, not reimplement them.

## 8. Recommendations to Astra and checks before execution

1. Make the DB project the canonical runtime-owner and custody authority.
   Before launch, reconcile the recorded runtime feature checkout with the
   user's existing-main/no-worktree instruction; do not silently switch or
   cherry-pick dirty work.
2. Require T1 to produce a file-level closure and deletion map that distinguishes
   migration compatibility from safety-bearing WAL, CAS, receipt, ownership,
   and fencing code. Reconfirm the architecture-plan hash and both repository
   HEADs.
3. Freeze the runtime lifecycle API after T3. Let RRP-03 consume it at the
   launcher boundary; do not allow a second replacement/catalog/readiness
   implementation. The specific contract must say who stops the old owner,
   who issues fresh credentials/epochs, and which interruption states are
   recoverable.
4. Sequence shared Astrid files (`host_bootstrap.py`, `workspace_client.py`,
   generated clients, `generic_host.py`, `invocation.py`) by explicit ownership.
   Timeline V1, generation T3, and DB T6 must record source hashes/diffs at each
   handoff. Regenerate clients once, after the contract settles.
5. Resolve the RRP concern that `health()` currently performs doctor work under
   the store mutex before deciding whether to move deep hashing offline. Keep
   read-only verification semantics intact while proving cheap serving remains
   responsive.
6. Confirm the exact launcher/catalog support root, credential files, discovery
   records, and process-birth identity on the delivery host. Confirm that tests
   can inject a reboot/launcher executor without touching real roots.
7. Treat all current dirty files and captured tests as inspection inputs only.
   No “setup ready” or existing focused tests may be converted into a PASS until
   the final candidate is integrated and the declared fixture matrix actually
   emits evidence.

Conclusion: the project is a substantial runtime boundary consolidation, not a
fresh-schema-only task. T1–T3 establish one verifier/admission/transaction
authority; T4/T5 own replacement and catalog/readiness truth; T6 closes Astrid
consumers; T7 supplies integrated proof. RRP-03 should be a launcher consumer of
that contract, and generation/timeline changes must be serialized around the
shared Astrid client/bootstrap closure.
