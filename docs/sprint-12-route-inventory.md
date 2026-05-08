# Sprint 12 Route Inventory

Source of truth for batch T1. This is an audit artifact, not a promotion list:
routes are only marked `dual_supported` when the selector map currently proves
VibeComfy support while WGP remains bootable.

## Evidence Sources

- Worker selector aliases and `SPRINT_2_SELECTOR_MAP`: `reigh-worker/source/task_handlers/tasks/template_routing.py`
- Section 3A support map with disposition and blockers: `reigh-worker/source/task_handlers/tasks/template_routing.py` and `reigh-worker/scripts/dual_run_compare/fixtures/section3a_matrix.fixture`
- App route stamping and snapshots: `reigh-app/supabase/functions/_shared/selectedRoute.ts`, `reigh-app/supabase/functions/create-task/routeContract.ts`, and `reigh-app/supabase/functions/_shared/selectedRoute.fixtures.json`
- Non-RayWorker fixture registry: `reigh-worker/scripts/dual_run_compare/fixtures/non_rayworker/registry_snapshot.json`

## Classification Rules

- `dual_supported`: RayWorker route is `vibecomfy_supported`; WGP remains available as the alternate backend.
- `wgp_only`: RayWorker route is explicitly WGP-only in the selector map.
- `vibecomfy_unsupported`: RayWorker route is known but not promoted to VibeComfy.
- `non_rayworker_api_owned`: Active API-orchestrator route owned outside the RayWorker selector.
- `cleanup_backlog`: Route registry row is not an active RayWorker or active API-orchestrator route for Sprint 12 closure.

## Direct RayWorker Selector Surface

The rows below reconcile `DIRECT_ROUTE_ALIASES` and `SPRINT_2_SELECTOR_MAP`.

| Route key | Classification | Support state | Template | Notes |
| --- | --- | --- | --- | --- |
| `z_image_turbo` | `dual_supported` | `vibecomfy_supported` | `image/z_image` | Direct aliases: `z_image`, `z_image_turbo`. Default resolution `1024x1024`. |
| `z_image_turbo_i2i` | `wgp_only` | `vibecomfy_supported` | `image/z_image_img2img` | Direct alias: `z_image_turbo_i2i`. |
| `qwen_image_2512` | `dual_supported` | `vibecomfy_supported` | `image/qwen_image_2512` | Direct alias: `qwen_image_2512`. |
| `qwen_image` | `dual_supported` | `vibecomfy_supported` | `image/qwen_image_2512` | Direct alias: `qwen_image`. |
| `qwen_image_edit` | `dual_supported` | `vibecomfy_supported` | `edit/qwen_image_edit` | Direct alias: `qwen_image_edit`. |
| `qwen_image_style` | `dual_supported` | `vibecomfy_supported` | `edit/qwen_image_edit` | Direct alias: `qwen_image_style`. |
| `image_inpaint` | `dual_supported` | `vibecomfy_supported` | `edit/qwen_image_edit` | Direct alias: `image_inpaint`. |
| `annotated_image_edit` | `dual_supported` | `vibecomfy_supported` | `edit/qwen_image_edit` | Direct alias: `annotated_image_edit`. |
| `travel_orchestrator` | `wgp_only` | `wgp_only` |  | Parent route; app requirements include travel child, stitch control, and nested join parent. |
| `join_clips_orchestrator` | `wgp_only` | `wgp_only` |  | Parent route; app requirements include join child and final stitch control. |
| `edit_video_orchestrator` | `wgp_only` | `wgp_only` |  | Parent route; app requirements include join child and final stitch control. |
| `travel_segment` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | Dimensional child route family; see Section 3A rows below. |
| `individual_travel_segment` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | Dimensional child route family. |
| `join_clips_segment` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | Dimensional child route family. |
| `travel_stitch` | `wgp_only` | `wgp_only` |  | Control route. |
| `join_final_stitch` | `wgp_only` | `wgp_only` |  | Control route. |
| `wan_2_2_t2i` | `wgp_only` | `vibecomfy_supported` | `video/wanvideo_wrapper_22_14b_t2i` | Direct aliases: `optimised_t2i`, `wan_2_2_t2i`. |
| `wan_2_2_i2v` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | App-active travel turbo route. Blocked until an explicit VibeComfy I2V route/template and worker dispatch proof exist. |
| `image-upscale` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | App-active non-RayWorker API route; not ported to VibeComfy. |
| `image_upscale` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | Legacy underscore variant for image upscale; not ported to VibeComfy. |
| `video_enhance` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | App-active non-RayWorker API route; not ported to VibeComfy. |
| `animate_character` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | App-active non-RayWorker API route; not ported to VibeComfy. |
| `flux_klein_edit` | `vibecomfy_unsupported` | `vibecomfy_unsupported` |  | App-active non-RayWorker API route; not ported to VibeComfy. |

## Section 3A Dimensional Route Surface

The rows below preserve `SECTION3A_ROUTE_SUPPORT_MAP` disposition and blocker
metadata without extending the runtime support-state enum.

| Row | Route key | Classification | Disposition | Blocker |
| --- | --- | --- | --- | --- |
| 1 | `travel_segment__model-wan22_i2v__guidance-none__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `NEW` | Requires the NEW Wan 2.2 VACE cocktail template before Wan-family travel rows can be promoted. |
| 2 | `travel_segment__model-wan22_vace__guidance-vace_flow__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 2a | `travel_segment__model-wan22_vace__guidance-vace_flow__continuity-video_source__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 3 | `travel_segment__model-wan22_vace__guidance-vace_canny__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 3a | `travel_segment__model-wan22_vace__guidance-vace_canny__continuity-video_source__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 4 | `travel_segment__model-wan22_vace__guidance-vace_depth__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 4a | `travel_segment__model-wan22_vace__guidance-vace_depth__continuity-video_source__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 5 | `travel_segment__model-wan22_vace__guidance-vace_raw__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6 | `travel_segment__model-wan22_vace__guidance-uni3c__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `NEW` | Requires the NEW Wan 2.2 VACE cocktail template and Uni3C patch before promotion. |
| 6a | `travel_segment__model-wan22_vace__guidance-vace__continuity-video_source__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6b | `travel_segment__model-wan22_vace__guidance-vace_raw__continuity-video_source__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6c | `individual_travel_segment__model-wan22_vace__guidance-vace__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6d | `individual_travel_segment__model-wan22_vace__guidance-vace_flow__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6e | `individual_travel_segment__model-wan22_vace__guidance-vace_canny__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6f | `individual_travel_segment__model-wan22_vace__guidance-vace_depth__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6g | `individual_travel_segment__model-wan22_vace__guidance-vace_raw__continuity-first_last__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 6h | `join_clips_segment__model-wan22_vace__guidance-vace__continuity-join_bridge__profile-default` | `vibecomfy_supported` | `NEW` | Promoted via `video/wanvideo_wrapper_22_14b_vace_cocktail`. |
| 7 | `travel_segment__model-ltx2__guidance-none__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The LTX first/last ready template is not yet wired through the Reigh travel child adapter with first/last image inputs and completion semantics. |
| 8 | `travel_segment__model-ltx2_distilled__guidance-none__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The LTX first/last ready template is not yet wired through the Reigh travel child adapter with first/last image inputs and completion semantics. |
| 9 | `travel_segment__model-ltx2_distilled__guidance-ltx_control_video__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The pinned LTX first/last template is not yet proven control-capable for a full-length control guide. |
| 10 | `travel_segment__model-ltx2_distilled__guidance-ltx_control_pose__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The pinned LTX first/last template is not yet proven control-capable for pose-preprocessed full-length guides. |
| 11 | `travel_segment__model-ltx2_distilled__guidance-ltx_control_depth__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The pinned LTX first/last template is not yet proven control-capable for depth-preprocessed full-length guides. |
| 12 | `travel_segment__model-ltx2_distilled__guidance-ltx_control_canny__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The pinned LTX first/last template is not yet proven control-capable for Canny-preprocessed full-length guides. |
| 13 | `travel_segment__model-ltx2_distilled__guidance-ltx_control_cameraman__continuity-first_last__profile-default` | `vibecomfy_unsupported` | `BLOCKED` | The pinned LTX first/last template is not yet proven control-capable for cameraman full-length guides. |

## App Route Snapshot Surface

`selectedRoute.ts` mirrors direct aliases and `SPRINT_2_SELECTOR_MAP`, derives
dimensional route keys for `travel_segment`, `individual_travel_segment`, and
`join_clips_segment`, and stamps tasks through `create-task/routeContract.ts`.
The app fixture snapshot currently covers:

| Fixture | Route key | Classification | Backend |
| --- | --- | --- | --- |
| vibecomfy z-image direct route | `z_image_turbo` | `dual_supported` | `vibecomfy` |
| wgp join child dimensional route | `join_clips_segment__model-wan22_vace__guidance-vace__continuity-join_bridge__profile-default` | `vibecomfy_supported` | `wgp` |
| legacy unknown route defaults | `legacy_custom_task` | `vibecomfy_unsupported` | `wgp` |

Section 3A blocker detail is preserved in the worker map and fixture matrix
above; app route snapshots currently preserve route key, backend, support state,
template id, profile, selector, run id, and worker contract version.

## Non-RayWorker Fixture Registry

| Route key | Classification | Runtime | Handler | Report policy |
| --- | --- | --- | --- | --- |
| `annotated_image_edit` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/image.py::handle_annotated_image_edit` | `wgp_only` |
| `animate_character` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/wavespeed.py::handle_animate_character` | `red_or_green_required` |
| `banodoco_render_timeline` | `cleanup_backlog` | `banodoco_worker_pool` | `handlers/banodoco.py::handle_banodoco_render_timeline` | `fallback` |
| `banodoco_timeline_generate` | `cleanup_backlog` | `banodoco_worker_pool` | `handlers/banodoco.py::handle_banodoco_timeline_generate` | `fallback` |
| `flux_klein_edit` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_flux_klein_edit` | `red_or_green_required` |
| `image-upscale` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_image_upscale` | `red_or_green_required` |
| `image_inpaint` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/image.py::handle_image_inpaint` | `wgp_only` |
| `qwen_image` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_qwen_image` | `wgp_only` |
| `qwen_image_2512` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_qwen_image` | `wgp_only` |
| `qwen_image_edit` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/wavespeed.py::handle_qwen_image_edit` | `wgp_only` |
| `qwen_image_style` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/wavespeed.py::handle_qwen_image_style` | `wgp_only` |
| `video_enhance` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_video_enhance` | `red_or_green_required` |
| `wan_2_2_i2v` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/wavespeed.py::handle_wan_2_2_i2v` | `pending_until_shared_oracle_evidence` |
| `wan_2_2_t2i` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/wavespeed.py::handle_wan_2_2_t2i` | `wgp_only` |
| `z_image_turbo` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_qwen_image` | `red_or_green_required` |
| `z_image_turbo_i2i` | `non_rayworker_api_owned` | `api_orchestrator` | `handlers/fal.py::handle_z_image_turbo_i2i` | `pending_until_shared_oracle_evidence` |
