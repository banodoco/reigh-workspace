# Sprint 06 Performance Review: Production Selector Claim Contract

Date: 2026-05-06

## Executive Summary

Sprint 06 completed and passed Megaplan review after one review-driven rework pass. The sprint added the production route selector/claim contract across `reigh-app` and `reigh-worker`: route selector and capability tables, task snapshot and claim-decision fields, backend-aware claim and count RPCs, create-task route materialization, worker claim payloads, pre-execution fail-closed guards, and child route snapshot propagation.

Nested implementation PRs were published separately before the top-level chain was allowed to complete:

- `reigh-app`: https://github.com/banodoco/reigh-app/pull/10
- `reigh-worker`: https://github.com/banodoco/reigh-worker/pull/27
- Top-level workspace PR: https://github.com/banodoco/reigh-workspace/pull/11

## Sprint Identity

| Field | Value |
|---|---|
| Chain milestone | `sprint-06-production-selector-claim-contract` |
| Plan name | `sprint-6-production-selector-20260506-1051` |
| Workspace branch | `megaplan/vibecomfy-migration-sprint-06` |
| Profile | `all-codex` |
| Robustness | `standard` |
| Megaplan state | `done` |
| Execution progress | 11/11 tasks, 7/7 batches |
| Review | Approved after rework |
| Cost | `$144.223201` total recorded by Megaplan |

## Verification

| Check | Result |
|---|---|
| Edge focused modules | Passed: `npm run test:edge:unit -- supabase/functions/claim-next-task supabase/functions/create-task supabase/functions/task-counts` (7 files, 59 tests) |
| RLS coverage | Passed: `node scripts/quality/check-supabase-rls.mjs` |
| Worker routing/claim/child tests | Passed: `PYTHONPATH=. pytest tests/test_template_routing.py` (31 tests) |
| Review criteria | All must criteria passed in final `review.json` |
| Supabase DB lint | Not run successfully; local Postgres was unavailable at `127.0.0.1:54322` |
| Full edge suite | Still has unrelated `ai-timeline-agent/tools/timeline.test.ts` title-card expectation failure |
| Full worker suite | Still blocked by local dependency/import setup collection failures |

## Issues Encountered

### 1. Planning Needed Three Iterations

Gate correctly forced two revisions before execution. The important caught issues were SQL-side WGP capability for missing selectors and active task-count parity after selector rollback. This was a productive planning loop, not wasted churn: the final plan explicitly separated live selector rows, capability rows, task snapshots, and claim-time fields.

### 2. Review Caught Two Must-Level Contract Bugs

The first execution pass completed but review blocked approval because:

- successful claim responses/logs exposed create-time `selected_backend` as if it were the live claim decision after rollback;
- malformed or unsupported escaped worker claim decisions logged and stopped locally, but left an already-claimed task stuck instead of clearing it.

The rework fixed both. Claim responses now separate live claim fields from `task_*` snapshot fields, and the worker guard now marks malformed/unsupported claim decisions failed before execution, falling back to retry requeue if the fail update is unavailable.

### 3. Nested Publication Guard Worked

The chain stopped twice after execute because claimed files lived in nested repos. This was correct. The fix was to publish the nested `reigh-app` and `reigh-worker` branches/PRs, then resume the chain. The existing callback-failure recovery restored the plan from terminal `failed` to the correct resume state.

### 4. Transient GitHub 504 Exposed Harness Fragility

After the plan reached `done`, `gh pr view 11 --json state` returned an HTTP 504 from GitHub GraphQL. The milestone state had already been updated to `done`, but the command failure stopped the wrapper.

Harness fix: Megaplan now retries transient `gh pr view` 5xx/timeout failures before failing the chain.

Validation:

```bash
PYENV_VERSION=3.11.11 python -m pytest tests/test_chain.py::test_pr_state_retries_transient_gh_failures tests/test_chain.py::test_pr_state_retries_graphql_timeout_until_attempts_exhausted tests/test_chain.py::test_pr_state_does_not_retry_non_transient_gh_failures tests/test_chain.py::test_enable_auto_merge_falls_back_when_repo_disallows_auto_merge tests/test_chain.py::test_run_chain_advances_when_pr_already_merged -q
```

Result: 5 passed.

## Completion Assessment

Overall verdict: **Complete and approved.** Sprint 06 established the production selector and claim contract needed by later orchestrator, lifecycle, and canary sprints. Remaining risk is mostly integration sequencing: the nested PRs are stacked on earlier migration branches, and production rollout still depends on later Sprint 07+ orchestrator/pool work.
