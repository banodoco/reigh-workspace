# Latest product-main publication — September 10, 2026

User explicitly authorized publishing the latest intended local Astrid and Banodoco Runtime source to main. Both normal pushes were independently verified remotely. Active preparation checkouts, their HEADs/indexes and dirty work were preserved; no deployment, real-data migration or GPU job was launched.

| Repository | Verified main | Tree | Composition |
|---|---|---|---|
| peteromallet/Astrid | `b33b1593fa7b89c6600a3b14fc7b8a5641b494ad` | `d204aab1a2396ec90da9017933d4d0397371600e` | Earlier `cd461097` plus SDK/CLI update `517f3d191e3970d2a207f3175c10ca8742c4bb1f`, then host/assets snapshot |
| banodoco/banodoco-workspace-runtime | `c38590a07f1ca3ec9d28cb018fddd7760f9be6ce` | `950a3575e5f306e4e17f03e9aef9bea467d99882` | Parent main `8ca859088b0d877306b967a7f59fa4c212fdce7f`, reconciled feature source `afccb430e2a983c968b6a8a96fd630ba3a6262fc` plus selected dirty source and bounded integration fixes |

## Astrid

First update adds seven paths: `astrid/core/gateway/dispatch.py`, SDK `autobootstrap.py`, `client.py`, `pagination.py`, Stage 1 cold-launch and cursor tests, and the v10 domain CLI surface test. Affected selection passed 340 tests; SDK passed 81 and domain CLI selection 204 (overlapping selections, not an additive unique-test count).

Second snapshot cutoff was `2026-09-10T18:44:20Z`: `astrid/core/execution/generic_host.py`, `tests/test_generic_host.py` and `astrid/core/rendering/assets.py`. Its 78 direct host/assets tests and local backlog smoke passed. Those three inputs still matched at the pre-push check. Later edits outside this frozen snapshot are not implicitly included.

Known limitation: the broad Stage 1 capability-census test fails at 83/86 on the already-published parent as well. The agent reproduced that baseline failure separately; this publication does not claim an entirely green Stage 1 suite or waive any affected project's required acceptance. The destination manager must triage it against its actual criteria/candidate, not repeat the full suite for reassurance.

## Runtime

The isolated composition includes current feature behavior and intended admission, bootstrap, boundary, backup/store/server/client/migration edits plus two untracked product tests. Integration validation required bounded corrections to reboot mutex ownership, SQLite backup sidecar handling and read-only/immutable backup semantic verification. Reboot tests were corrected to use complete protocol requests and retain actual stale-lease/epoch rejection assertions, with malformed-request cases separate; assertions were not weakened to manufacture a pass.

The final affected matrix passed **122 tests** in 28.12 seconds: admission/boundary/bootstrap, backup/migration, reboot fencing, Runtime E2E, continuations/timeline publication, generated-client parity and contract/schema/TypeScript-generator checks. Live bootstrap, live migration/operator, production credential, Stage 1 reboot and tiny-acceptance campaigns were not run. This is source-publication proof, not final physical GPU or end-to-end portfolio acceptance.

The active Runtime feature checkout remains at its original HEAD and dirty preimage. The bounded publication corrections exist in the new main candidate, not as silent edits to that live checkout. Fetch and compare; do not reset or double-apply its dirty patch.

## Cross-repository identity and exclusions

The preparer compared published objects: both generated Python clients have Git blob `47df59cbac4b62ae6fbb389c7bd609f3cded6912`. Protocol, schema digest, component-manifest digest and operations metadata match; Astrid additionally carries historical vendoring provenance. This static identity check does not replace destination setup or the GPU candidate's post-merge integration tests.

Excluded assessment/eval/private/control material, unrelated documentation, caches/build outputs/egg-info, credentials and unrelated repositories. Runtime's historical convergence control note was not added to main. Detailed local publication receipts are in the preparation workspace's `.otto/reports/portfolio-sequencing-20260910/`; this portable summary contains the required fetch/proof boundaries without private machine paths.

On the different receiving Mac, preserve its existing GPU owner's complete source first, then merge freshly fetched main into isolated continuation branches at the verified checkpoint under [GPU takeover](gpu-project-takeover.md). Refresh remote heads at integration time and record any advance from these pins. Run validation at the [resource-aware waypoints](operations.md), accounting for 8 GB RAM, CPU load and constrained storage.
