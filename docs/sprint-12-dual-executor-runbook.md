# Sprint 12 Dual-Executor Runbook

Sprint 12 closes the migration as dual-executor steady state. WGP remains a
supported runtime and rollback target; VibeComfy is selectable only for routes
whose selector and tests prove support.

## Boot Modes

Both executors boot from the orchestrator startup template and image. The
backend is selected by route contract exports, not by deleting the WGP path.

| Mode | Required exports | Notes |
| --- | --- | --- |
| WGP | `REIGH_BACKEND=wgp`, `REIGH_WORKER_PROFILE`, `REIGH_WORKER_POOL`, `REIGH_SELECTOR_NAMESPACE`, `REIGH_SELECTOR_VERSION`, `REIGH_WORKER_CONTRACT_VERSION`, `REIGH_WORKER_RUN_ID` | Preserves WGP checkout, submodule startup checks, and rollback behavior. |
| VibeComfy | Same exports with `REIGH_BACKEND=vibecomfy` | `VIBECOMFY_MEMORY_PROFILE` is exported only when `REIGH_WORKER_PROFILE` is numeric. |

The startup test suite guards that WGP and VibeComfy renders share the same
template markers and route contract exports.

## Selector Contract

Selector namespace and version identify the active route decision set:

- `REIGH_SELECTOR_NAMESPACE` or `ROUTE_SELECTOR_NAMESPACE`: deployment scope such as `production`, `staging`, or `canary`.
- `REIGH_SELECTOR_VERSION` or `ROUTE_SELECTOR_VERSION`: flip version for the selected pool.
- `REIGH_WORKER_CONTRACT_VERSION`: worker route contract schema version. Sprint 12 uses version `1`.
- `REIGH_WORKER_RUN_ID`: optional run identifier for evidence, rollback, and dashboard correlation.

Profile and pool names must match the selected backend:

- WGP production/staging examples: `worker_backend=wgp`, `worker_profile=1`, `worker_pool=gpu-wgp-production` or `gpu-wgp-staging`.
- VibeComfy examples: `worker_backend=vibecomfy`, `worker_profile=3`, `worker_pool=gpu-vibecomfy-production` or `gpu-vibecomfy-staging`.
- Profile `default` and `1` remain compatible for legacy WGP accounting. Other profiles must match exactly.

Selected pool totals count only workers and tasks matching backend, profile,
selector namespace, selector version, and worker contract version.

## Route Decision Rules

- `dual_supported`: route may select WGP or VibeComfy. Current Sprint 12 route: `z_image_turbo`.
- `wgp_only`: route stays on WGP even when VibeComfy exists.
- `vibecomfy_unsupported`: explicit VibeComfy selection fails closed and does not silently fall back to WGP.
- `non_rayworker_api_owned`: API-orchestrator route with documented owner, handler, completion, billing, dashboard, and alert coverage.
- `cleanup_backlog`: cleanup-only deletion candidate for Sprint 12B or a separate PR; deletion is not required for Sprint 12 closure.

Before promoting a route, update the worker selector map, Section 3A support map
when dimensional, app route stamping, snapshots, Python route tests, TypeScript
route tests, and dashboard/alert evidence.

## Staging Flip Procedure

1. Confirm the route is documented as `dual_supported` in `docs/sprint-12-route-support.md`.
2. Start or verify workers for the current selector contract and record selected pool totals.
3. Queue canary tasks for the supported route with route snapshot fields stamped by the app or worker parent contract.
4. Start replacement workers with the target backend/profile/pool/selector contract.
5. Flip `REIGH_BACKEND`, `REIGH_WORKER_PROFILE`, `REIGH_WORKER_POOL`, `REIGH_SELECTOR_NAMESPACE`, `REIGH_SELECTOR_VERSION`, `REIGH_WORKER_CONTRACT_VERSION`, and `REIGH_WORKER_RUN_ID` together.
6. Watch selected pool totals. Only matching backend/profile/selector workers should count as new capacity.
7. Let route-stale workers with active tasks drain. They must not receive new-route capacity credit.
8. Terminate idle route-stale workers through the worker capacity phase.
9. Confirm dashboard panels for selected pool totals, route totals, route worker health, claim suppression, quota, preflight, warm cache, and non-RayWorker health.
10. Keep readiness red if real staging/live observations are unavailable.

Run the same procedure for `wgp -> vibecomfy` and `vibecomfy -> wgp`.

## Rollback

Rollback means flipping the selector contract back to the previous WGP or
VibeComfy backend/profile/pool/version while preserving in-flight work:

1. Restore the previous selector exports as a single contract.
2. Start replacement workers for the restored contract.
3. Confirm old target workers are now route-stale and excluded from selected pool totals.
4. Drain active route-stale workers; terminate idle route-stale workers.
5. Verify WGP startup/submodule checks still run when the restored backend is WGP.
6. Record dashboard and alert state, including stale route workers and missing runtime evidence.

Do not delete WGP runtime code, startup checks, tests, or rollback paths as part
of Sprint 12 closure.
