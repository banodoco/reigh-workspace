# Sprint 07 Performance Review: Orchestrator Image, Pools, and Artifacts

Date: 2026-05-06
Plan: `sprint-7-orchestrator-image-20260506-1219`
Result: Done after one review rework.

## Shipped

- `reigh-app` PR: https://github.com/banodoco/reigh-app/pull/11
- `reigh-worker` PR: https://github.com/banodoco/reigh-worker/pull/28
- `reigh-worker-orchestrator` PR: https://github.com/banodoco/reigh-worker-orchestrator/pull/2

Sprint 07 added the selected-route contract across app, worker, and orchestrator; route-aware task counts and claim rejection; worker preflight/readiness, warm-cache, resource-pressure, and telemetry labels; route-aware orchestrator pool sizing, stale-worker draining, startup propagation, and rollback fixture coverage; and artifact path/TTL/debug-retention metadata.

## Verification

- Focused edge route/storage/claim/count tests passed.
- `reigh-worker/tests/test_template_routing.py` passed: 34 tests.
- Focused worker artifact/resource/preflight/health/routing/LoRA tests passed.
- Focused orchestrator route/stale/capacity/startup/rollback tests passed: 57 tests.
- Full orchestrator suite passed.
- Temporary Sprint 07 invariant script verified route stamping, claim-gate SQL ordering, selected-pool demand, startup preflight-ready gating, artifact cleanup, stale capacity handling, and telemetry labels; the script was deleted after use.

Known unrelated failures reproduced in broad suites:

- Edge broad suite: `complete_task` default context, `timeline-import`, and `ai-timeline-agent` command availability.
- Worker broad suite: debug storage command tests, media video namespace/API tests, preview harness tests, and runtime boundary fake `Popen` test.

## Issues And Recovery

- Execute succeeded but the phase callback failed because claimed files were in nested repos. Recovery required publishing nested PRs, then rerunning execute.
- Review caught a real Sprint-adjacent test failure: `tests/test_template_routing.py` installed an `httpx` stub without `Response`, while `edge_helpers.py` evaluated `httpx.Response` at import time. Rework added postponed annotations in `edge_helpers.py`; the focused test passed.
- The recovery execute reran expensive validation instead of only replaying the successful callback. That inflated total plan cost to about `$560.79`.

## Residual Risk

- Top-level PR cannot contain the nested implementation; reviewers must use the three nested PRs above.
- The chain should keep treating nested publication as mandatory before advancement.
- Megaplan recovery should be improved so callback-only recovery does not re-enter expensive execute work when all batches are already complete.
