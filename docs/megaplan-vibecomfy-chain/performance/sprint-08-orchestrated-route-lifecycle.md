# Sprint 08 Performance Review: Orchestrated Route Lifecycle

Date: 2026-05-06
Plan: `sprint-8-orchestrated-route-20260506-1506`
Result: Done after timeout recovery.

## Shipped

- `reigh-app` PR: https://github.com/banodoco/reigh-app/pull/12
- `reigh-worker` PR: https://github.com/banodoco/reigh-worker/pull/29

Sprint 08 propagated route contracts through task creation and parent/child orchestration surfaces. Parent routes now fail closed when child routes cannot safely follow the selected backend, child rows carry route snapshots, existing-child idempotency paths validate backend/version/profile/parent-route identity, and debug/repair output exposes route-drift signals.

## Verification

- Megaplan review passed: 14/14 success criteria.
- Execute completed: 12/12 tasks, 11/11 batches.
- Focused app task-creation tests passed: 2 files / 10 tests.
- Focused create-task edge tests passed: 2 files / 18 tests.
- Scoped route/children edge tests passed during Sprint 08 execution.
- Focused worker route lifecycle tests passed: `tests/test_template_routing.py` and `tests/test_travel_orchestrator_terminal_gating.py`, 2 files / 69 tests.
- Temporary mixed-backend route-drift reproduction script produced explicit repair-required output, then was deleted.

Known unrelated or environment failures during broad validation:

- Broad edge tests still fail in known unrelated areas: `complete_task`, `timeline-import`, and `ai-timeline-agent`.
- Broad app Vitest runs timed out or failed in unrelated existing UI tests.
- Late app reruns reported missing local `vitest` from `node_modules/.bin` after focused app/edge commands had already passed.
- Broad worker collection hit local Python dependency gaps such as missing `torch`/`httpx` under the available interpreter.

## Issues And Recovery

- The first execute run was healthy and continued writing batches, but `megaplan auto` killed it at the hard two-hour phase timeout. At that point Sprint 08 had 9/12 tasks done and 8/11 batches complete.
- `megaplan resume` recovered and continued from existing receipts through batch 11, but while active, `status` still reported top-level state `failed`. After resume completed, the plan state became `executed`.
- Harness fix pushed in `megaplan` PR branch `fix/nested-repo-chain-execute-recovery`: active resume now restores a runnable phase state during resume, and auto timeout no longer kills a phase that is still producing output or liveness artifacts.
- Top-level chain state still needed manual attention because `chain_state.json` had recorded Sprint 08 as failed before the resumed plan reached `done`.

## Residual Risk

- The top-level PR cannot contain nested implementation details; reviewers must inspect the two nested PRs above.
- Broad-suite failures remain noisy and should not be treated as Sprint 08 regressions without focused reproduction.
- Chain state recovery after a timeout-resumed plan should become fully automatic so future milestones do not require manual chain-state reconciliation.
