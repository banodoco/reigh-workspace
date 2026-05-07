# Sprint 12 Dual-Executor Ownership

Sprint 12 closes as dual-executor steady state, not WGP retirement. WGP runtime
code, tests, startup paths, and rollback behavior remain owned and live.

## Approval Basis

The active chain directive on 2026-05-07 accepts Peter O'Malley as interim
owner for unresolved non-RayWorker ownership through review date 2026-06-07.
Approval source: `current chain directive, 2026-05-07`.

## Direct RayWorker Matrix

| Route key | Runtime | Support | Owner | Regression check | Dashboard/alert surface | Cleanup disposition |
| --- | --- | --- | --- | --- | --- | --- |
| `z_image_turbo` | RayWorker WGP + VibeComfy | `dual_supported` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py`; app `selectedRoute.test.ts` | selected pool totals, route totals, route worker health, canary runtime alerts | Keep; not cleanup |
| `z_image_turbo_i2i` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `qwen_image_2512` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `qwen_image` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `qwen_image_edit` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `qwen_image_style` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `image_inpaint` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `annotated_image_edit` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `reigh-worker/tests/test_template_routing.py` | route totals and WGP route health | Keep WGP path |
| `travel_orchestrator` | RayWorker WGP | `wgp_only` | RayWorker platform owner | parent/child route contract tests in `test_template_routing.py` | parent route totals and claim suppression alerts | Keep WGP path |
| `join_clips_orchestrator` | RayWorker WGP | `wgp_only` | RayWorker platform owner | parent/child route contract tests in `test_template_routing.py` | parent route totals and claim suppression alerts | Keep WGP path |
| `edit_video_orchestrator` | RayWorker WGP | `wgp_only` | RayWorker platform owner | parent/child route contract tests in `test_template_routing.py` | parent route totals and claim suppression alerts | Keep WGP path |
| `travel_segment` | RayWorker WGP child family | `vibecomfy_unsupported` | RayWorker platform owner | Section 3A matrix tests in `test_template_routing.py` | child route totals and missing runtime evidence alert when promoted | Keep WGP path |
| `individual_travel_segment` | RayWorker WGP child family | `vibecomfy_unsupported` | RayWorker platform owner | dimensional route tests in `test_template_routing.py` | child route totals and missing runtime evidence alert when promoted | Keep WGP path |
| `join_clips_segment` | RayWorker WGP child family | `vibecomfy_unsupported` | RayWorker platform owner | dimensional route tests in `test_template_routing.py`; app route fixture | child route totals and missing runtime evidence alert when promoted | Keep WGP path |
| `travel_stitch` | RayWorker WGP control | `wgp_only` | RayWorker platform owner | parent-derived control row tests in `test_template_routing.py` | control route totals | Keep WGP path |
| `join_final_stitch` | RayWorker WGP control | `wgp_only` | RayWorker platform owner | parent-derived control row tests in `test_template_routing.py` | control route totals | Keep WGP path |
| `wan_2_2_t2i` | RayWorker WGP | `wgp_only` | RayWorker platform owner | `test_wan_2_2_t2i_remains_wgp_only_even_when_vibecomfy_is_explicit` | route totals and WGP route health | Keep WGP path |

## Section 3A Dimensional Matrix

All Section 3A rows remain RayWorker WGP-owned until a route-specific VibeComfy
implementation lands. The runtime support state remains `vibecomfy_unsupported`;
`NEW` and `BLOCKED` are fixture dispositions, not runtime enum values.

| Route key | Owner | Regression check | Dashboard/alert surface | Cleanup disposition |
| --- | --- | --- | --- | --- |
| `travel_segment__model-wan22_i2v__guidance-none__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and `test_section3a_matrix_route_support_is_explicit_and_deterministic` | missing runtime evidence if promoted; route totals | Keep WGP route; promotion blocker documented |
| `travel_segment__model-wan22_vace__guidance-vace_flow__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and route support report test | missing runtime evidence if promoted; route totals | Keep WGP route; promotion blocker documented |
| `travel_segment__model-wan22_vace__guidance-vace_canny__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and route support report test | missing runtime evidence if promoted; route totals | Keep WGP route; promotion blocker documented |
| `travel_segment__model-wan22_vace__guidance-vace_depth__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and route support report test | missing runtime evidence if promoted; route totals | Keep WGP route; promotion blocker documented |
| `travel_segment__model-wan22_vace__guidance-vace_raw__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and route support report test | missing runtime evidence if promoted; route totals | Keep WGP route; promotion blocker documented |
| `travel_segment__model-wan22_vace__guidance-uni3c__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and route support report test | missing runtime evidence if promoted; route totals | Keep WGP route; promotion blocker documented |
| `travel_segment__model-ltx2__guidance-none__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; adapter blocker documented |
| `travel_segment__model-ltx2_distilled__guidance-none__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; adapter blocker documented |
| `travel_segment__model-ltx2_distilled__guidance-ltx_control_video__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; control blocker documented |
| `travel_segment__model-ltx2_distilled__guidance-ltx_control_pose__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; control blocker documented |
| `travel_segment__model-ltx2_distilled__guidance-ltx_control_depth__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; control blocker documented |
| `travel_segment__model-ltx2_distilled__guidance-ltx_control_canny__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; control blocker documented |
| `travel_segment__model-ltx2_distilled__guidance-ltx_control_cameraman__continuity-first_last__profile-default` | RayWorker platform owner | Section 3A matrix fixture and fail-closed tests | missing runtime evidence if promoted; route totals | Keep WGP route; control blocker documented |

## Required Non-RayWorker Routes

| Route key | Runtime | Owner | Review date | Approval source | Regression check | Dashboard/alert surface | Cleanup disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `video_enhance` | `api_orchestrator` via `handlers/fal.py::handle_video_enhance` | Peter O'Malley, accepted interim product owner | 2026-06-07 | current chain directive, 2026-05-07 | `test_non_rayworker_fixture_json_and_snapshot_are_complete`; `test_non_rayworker_gate_requires_recent_live_observations_for_all_four_routes` | `non_rayworker_route_health`; `canary_non_rayworker_route_smoke_failure`; completion/billing failure alerts | Preserve |
| `image-upscale` | `api_orchestrator` via `handlers/fal.py::handle_image_upscale` | Peter O'Malley, accepted interim product owner | 2026-06-07 | current chain directive, 2026-05-07 | fixture alias mismatch test; non-RayWorker readiness gate | `non_rayworker_route_health`; smoke failure; completion/billing failure alerts | Preserve |
| `animate_character` | `api_orchestrator` via `handlers/wavespeed.py::handle_animate_character` | Peter O'Malley, accepted interim product owner | 2026-06-07 | current chain directive, 2026-05-07 | non-RayWorker fixture and readiness gate tests | `non_rayworker_route_health`; smoke failure; completion/billing failure alerts | Preserve |
| `flux_klein_edit` | `api_orchestrator` via `handlers/fal.py::handle_flux_klein_edit` | Peter O'Malley, accepted interim product owner | 2026-06-07 | current chain directive, 2026-05-07 | non-RayWorker fixture and readiness gate tests | `non_rayworker_route_health`; smoke failure; completion/billing failure alerts | Preserve |

