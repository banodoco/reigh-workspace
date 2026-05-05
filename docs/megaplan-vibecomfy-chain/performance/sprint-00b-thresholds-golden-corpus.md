# Sprint 0B Performance Review: Thresholds and Golden Corpus

Date: 2026-05-06

## Executive Summary

Sprint 0B produced the route-keyed threshold, corpus, fixture, evidence, and documentation artifacts needed by later parity, harness, and canary sprints. The executable threshold source of truth is now `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` at version `0B-2026-05-05`, and the top-level migration docs name that YAML as the source later consumers must load.

Live paired WGP-vs-WGP calibration did not run during Sprint 0B. The sprint therefore completed on the planned route-keyed deferral path: every required route is represented in the WGP repeatability report with attempted command shape, calibration status, and next action, and every YAML route is marked `deferred_pending_sprint_0c_disk` until a later sprint needs measured WGP drift. This is not recorded as a RunPod-access failure: live RunPod lifecycle was separately verified by the agent on 2026-05-05 with pod `f9s5vqk15gux9d`.

## Sprint Identity

| Field | Value |
|---|---|
| Chain milestone | `sprint-00b-thresholds-golden-corpus` |
| Plan name | `sprint-0b-thresholds-and-20260505-2252` |
| Workspace branch | `megaplan/vibecomfy-migration-sprint-00b` |
| Worker branch | `megaplan/vibecomfy-sprint-00b-thresholds` |
| PR | Worker PR #23; top-level PR #3 |
| Megaplan state | executed; review pending |
| Execution progress | Execute completed; review pending |
| Profile | `all-codex` after recovery from stalled Hermes/Kimi critique path |
| Robustness | `standard` |

## Intended Scope

The sprint brief required:

- `migration-thresholds.yaml` with one row-granular threshold source of truth.
- WGP self-repeatability evidence.
- Route-keyed WGP golden corpus for Cohort A/B and representative Cohort E routes.
- Lightweight product-contract fixtures for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`.
- Live-validation documentation synchronized to the same threshold and route version.

The exit criterion was explicit: the threshold YAML must be committed and smoke-readable; WGP self-drift must either be below thresholds or affected routes must be marked WGP-only/pending; the corpus must be route-keyed; and active non-RayWorker routes must have owner-approved fixtures or explicit deferral rationale.

## Actual Outcome

Completed by execution:

- `reigh-worker/scripts/dual_run_compare/migration-thresholds.yaml` was created with `version: 0B-2026-05-05`, `schema_version: 1`, top-level `metric_keys`, metric `defaults`, all 14 Section 11 metric rows, the single approved calibration status enum, and 14 route entries.
- `reigh-worker/scripts/dual_run_compare/thresholds.py` and `check_thresholds.py` were added so later sprints can load and strictly validate the YAML.
- `reigh-worker/scripts/dual_run_compare/route_keys.py` was added with canonical direct, edit-dimensional, and Cohort E dimensional route keys, including the audited `wan_2_2_i2v_lightning_baseline_2_2_2 -> wan22_i2v` mapping.
- Route-keyed golden corpus manifests were added under `reigh-worker/scripts/dual_run_compare/golden/<route_key>/manifest.json` with seed fixture references where worker-matrix coverage is missing.
- Non-RayWorker preservation fixtures and `registry_snapshot.json` were added for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`.
- `reigh-worker/scripts/dual_run_compare/wgp_self_repeat.py` was added around the real live-test CLI contract and tested to avoid invalid flags.
- The Sprint 0B WGP repeatability evidence was committed as a route-keyed deferral report at `reigh-worker/scripts/dual_run_compare/reports/wgp-self-repeat-0b-2026-05-05-deferral.json` and `.md`.
- `docs/migration-vibecomfy-live-validation.md` and `docs/migration-vibecomfy.md` were updated to name YAML version `0B-2026-05-05` as the executable threshold source of truth.

## Verification

| Check | Result |
|---|---|
| Strict threshold validation | Passed: `python -m scripts.dual_run_compare.check_thresholds --strict` |
| Focused dual-run-compare tests | Passed: `pytest scripts/dual_run_compare/tests/` (25 tests) |
| Compile smoke | Passed: `python -m compileall -q scripts/dual_run_compare` |
| WGP report/YAML sync | Passed by route-keyed Python JSON/YAML validation in T7 |
| Docs source-of-truth grep | Passed in T8 for YAML version/path, report path, route-key module, and status references |
| Full worker test suite | Failed during collection with pre-existing environment issues |
| Representative full-suite blocker | `ModuleNotFoundError: No module named 'httpx'` in `tests/test_additional_coverage_modules.py` |

Known full-suite failures are unchanged from prior batches: plain `pytest --tb=no -q --no-header` reports 83 collection errors, and `PYTHONPATH=. pytest --tb=no -q --no-header` reports 56 collection errors. Focused Sprint 0B validation passes.

## Performance Metrics

| Phase | Duration | Cost | Tokens | Result |
|---|---:|---:|---:|---|
| init | not recorded | n/a | n/a | completed before batch execution |
| plan | not recorded | n/a | n/a | finalized before batch execution |
| critique | not recorded | n/a | n/a | finalized before batch execution |
| revise | not recorded | n/a | n/a | finalized before batch execution |
| finalize | not recorded | n/a | n/a | `finalize.json` mapped 10 tasks plus user actions |
| execute | completed | n/a | executor artifacts | completed with focused validation passing |
| total | review pending | n/a | n/a | execution complete |

## Issues Encountered

### 1. Live RunPod Lifecycle Was Proven; Paired WGP Calibration Remains Deferred

The agent ran live RunPod verification on 2026-05-05 using `runpod-lifecycle/smoke_live.py`. Pod `f9s5vqk15gux9d` launched on an NVIDIA GeForce RTX 4090, reached SSH readiness, reported GPU visibility, passed storage health, appeared in `list_pods`, terminated, and had zero active matches after termination.

Impact: The sprint used the planned route-keyed deferral path for paired WGP-vs-WGP metric observations because the user corrected that WGP is already trusted and WGP-only proof text should not block the chain. Every required route is represented in the deferral report, and every route status is `deferred_pending_sprint_0c_disk` until a later sprint needs measured WGP drift to promote it.

### 2. Full Worker Pytest Remains Blocked By Environment-Level Collection Failures

Full-suite validation was rerun after the sprint changes, but collection still fails before executing tests. A representative failing module imports `httpx`, which is not installed in this environment.

Impact: Sprint 0B relies on strict threshold validation, focused dual-run-compare tests, report/YAML sync checks, and compile smoke for local confidence. The full-suite environment should be fixed separately before treating repo-wide pytest as a regression gate.

### 3. Nested Repo And Top-Level Doc Boundaries Still Need Careful Publishing

Most Sprint 0B artifacts live in the nested `reigh-worker` repository, while the live-validation, migration, and performance review docs live in the top-level workspace repository.

Impact: Publishing must include both the nested worker branch and the top-level workspace branch, or reviewers will see documentation without the executable artifacts or artifacts without the synchronized docs.

## Calibration Status

| Area | Status | Notes |
|---|---|---|
| Threshold YAML | Complete | `version: 0B-2026-05-05`; schema 1; top-level `metric_keys` and `defaults`; 14 metric rows; strict validation passes. |
| Route statuses | Deferred | All 14 routes are `deferred_pending_sprint_0c_disk`. |
| WGP self-repeatability | Deferred with artifact | JSON and Markdown report list every route, attempted command shape, blocker, and next action. |
| Golden corpus manifests | Complete | One manifest per YAML route, route-keyed by canonical route key. |
| Non-RayWorker fixtures | Complete as preservation fixtures | Four active non-RayWorker routes have committed fixtures and registry snapshot. |
| Live calibration next gate | Later consumer sprint | Run paired WGP only if fresh measured drift is required before clearing deferral statuses. |

## Completion Assessment

| Requirement | Status | Notes |
|---|---|---|
| Threshold YAML committed and smoke-readable | Complete | Strict check passes from `reigh-worker`. |
| WGP self-repeatability report | Complete on deferral path | Live paired calibration deferred by intent; machine-readable and Markdown evidence committed. |
| Route-keyed golden corpus | Complete | Manifests cover all 14 threshold YAML routes. |
| Cohort A/B and representative Cohort E coverage | Complete | Cohort E keys are dimensional and include audited model-family mapping. |
| Non-RayWorker preservation fixtures | Complete | Fixtures cover `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`. |
| Live-validation doc synchronized | Complete | Top-level docs name YAML version/path and report status. |
| Final verification suite | Complete for focused Sprint 0B scope | Focused validation passes; full suite remains blocked by pre-existing environment issues. |

Overall verdict: **Sprint 0B artifacts completed execute and are ready for Megaplan review; live WGP-vs-WGP metric calibration remains explicitly deferred until a later consumer sprint needs measured drift**.

## Required Next Action

1. Run Megaplan review for Sprint 0B and publish both repos.
2. In Sprint 0C or the first sprint that consumes fresh WGP drift, rerun paired WGP-vs-WGP calibration only if needed to clear `deferred_pending_sprint_0c_disk`.
3. Publish/review both the nested `reigh-worker` artifact branch and the top-level workspace documentation branch together.
