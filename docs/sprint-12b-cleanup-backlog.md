# Sprint 12B Cleanup Backlog

Cleanup-only deletion is not required for Sprint 12 closure. Sprint 12 closes as
dual-executor steady state with WGP intact.

## Backlog Candidates

| Candidate | Current classification | Reason it is not Sprint 12 closure work |
| --- | --- | --- |
| `banodoco_render_timeline` registry row | `cleanup_backlog` | Worker-pool fallback path needs separate owner and active-row review before any deletion or move. |
| `banodoco_timeline_generate` registry row | `cleanup_backlog` | Worker-pool fallback path needs separate owner and active-row review before any deletion or move. |
| Stale Sprint 11B dashboard/watch-note wording | cleanup metadata | May be edited when contradictory, but deletion of historical context is not needed for closure. |
| Any unused WGP-only startup/runtime path | not approved for deletion | WGP runtime code, tests, startup paths, submodule checks, and rollback behavior must remain intact. |

## Deletion Gates

Any cleanup PR must independently prove:

1. Active DB rows: query production and staging task rows for the candidate task type or route key; deletion requires no active, queued, running, retryable, or resumable rows.
2. Emitter search: search app, edge functions, orchestrator, worker, scripts, fixtures, and migrations for task emitters, handler refs, route aliases, and dashboard/alert references.
3. Owner sign-off: record the owning team or named owner, approval date, and rollback expectation.
4. Regression coverage: add or update tests that fail if a still-active route is removed from dispatch, completion, billing, readiness, dashboard, or route-selection surfaces.
5. Rollback plan: document how to restore the route or fixture if live rows or callers are found after merge.

## Explicit Non-Goals

- Do not delete WGP runtime code for Sprint 12.
- Do not remove WGP tests, startup template paths, or rollback behavior.
- Do not treat cleanup deletion as a Sprint 12 exit criterion.

