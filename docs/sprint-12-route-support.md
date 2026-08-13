# Sprint 12 Route Support

This document is derived from `docs/sprint-12-route-inventory.md`,
`reigh-worker/source/task_handlers/tasks/template_routing.py`, app route
stamping in `reigh-app/supabase/functions/create-task/resolvers/shared/routeKeys.ts`,
and non-RayWorker fixture metadata.

## Dual-Supported RayWorker Routes

| Route key | WGP/API | VibeComfy | Template | Evidence |
| --- | --- | --- | --- | --- |
| `z_image_turbo` | supported | supported | `image/z_image` | Live RunPod worker proof; route tests |
| `z_image_turbo_i2i` | supported | supported | `image/z_image_img2img` | Live RunPod worker proof; route tests |
| `qwen_image_2512` | supported | supported | `image/qwen_image_2512` | Live RunPod worker proof; route tests |
| `qwen_image` | supported | supported | `image/qwen_image_2512` | Live RunPod worker proof; production selector seed |
| `qwen_image_edit` | supported | supported | `edit/qwen_image_edit` | Live RunPod worker proof |
| `qwen_image_style` | supported | supported | `edit/qwen_image_edit` | Live RunPod worker proof |
| `image_inpaint` | supported | supported | `edit/qwen_image_edit` | Live RunPod worker proof with masked composite |
| `annotated_image_edit` | supported | supported | `edit/qwen_image_edit` | Live RunPod worker proof with masked composite |
| `wan_2_2_t2i` | supported | supported | `video/wanvideo_wrapper_22_14b_t2i` | Live RunPod worker proof |
| `wan_2_2_i2v` | supported | supported | `video/wanvideo_wrapper_22_14b_i2v_kijai` | Live RunPod worker proof: `reigh-worker/scripts/live_test/runs/20260508T113336Z/report.md` |
| Wan 2.2 VACE travel/join rows | supported | supported | `video/wanvideo_wrapper_22_14b_vace_cocktail` | Live RunPod worker proof for promoted VACE rows |
| LTX 2.3 first/last no-control (`ltx2`) | supported | supported | `video/ltx2_3_lightricks_first_last_parity` | Local contract (`ltx-first-last-two-stage`) passed; lens/contract tests pass; route tests pass; adapter scratchpad uses named inputs via `workflow.set_input(...)`; RunPod live validation pending (orchestrator-owned, T13 not yet executed) |
| LTX 2.3 distilled first/last no-control (`ltx2_distilled`) | supported | supported | `video/ltx2_3_lightricks_first_last_parity` | Same as `ltx2` no-control row above; shared parity template; RunPod live validation pending |

## Live-Proven App-Active Direct Routes

These app-active direct routes have VibeComfy selector rows, worker scratchpad
writers, app route snapshots, local regression coverage, and live RunPod
generation proof through the Reigh worker.

| Route key | VibeComfy template | Evidence | Current caveat |
| --- | --- | --- | --- |
| `animate_character` | `video/wan22_animate_native_first_stage` | Live RunPod worker proof: `reigh-worker/scripts/live_test/runs/20260508T174952Z/report.md`, task `f61d68f5-37d7-49c4-8bda-ac55ff0ce3c5`, output `Wanimate_00001_.mp4` | Native WanAnimate first-stage route. `num_frames` is now bound into the template and app resolver; full long-form quality grading remains separate from completion proof. |
| `image-upscale`, `image_upscale` | `image/basic_image_upscale` | Live RunPod worker proof: `reigh-worker/scripts/live_test/runs/20260508T084407Z/report.md` | Contract parity only; currently Lanczos scaling, not model-quality external upscaler parity. |
| `video_enhance` | `video/basic_video_enhance` | Live RunPod worker proof: `reigh-worker/scripts/live_test/runs/20260508T090727Z/report.md` | Public baseline route. Frame interpolation/model-quality enhancement still needs a non-gated asset path. |
| `flux_klein_edit` | `edit/flux2_klein_4b_image_edit_distilled` | Live RunPod worker proof: `reigh-worker/scripts/live_test/runs/20260508T085430Z/report.md` | 4B expanded template path only; 9B Klein edit parity remains unresolved. |

## WGP-Only RayWorker Routes

`travel_orchestrator`, `join_clips_orchestrator`, `edit_video_orchestrator`,
`travel_stitch`, and `join_final_stitch` are WGP-only by current selector
evidence.

## Unsupported-Pending Dimensional Rows

`travel_segment`, `individual_travel_segment`, and `join_clips_segment` are
dimensional route families that remain `vibecomfy_unsupported` unless a specific
Section 3A row is promoted with implementation and proof. Wan 2.2 VACE
flow/canny/depth/raw plus join bridge are promoted through the VACE cocktail
template. LTX 2.3 no-control first/last (`ltx2` and `ltx2_distilled`) is now
routed to `video/ltx2_3_lightricks_first_last_parity` (local contract passed,
code-wired, adapter uses named inputs); RunPod live validation is pending.
LTX IC-LoRA control rows (`pose/depth/canny/cameraman`) remain on
`video/ltx2_3_first_last_frame_travel_iclora_control` and raw-video guide on
`video/ltx2_3_runexx_first_last_raw_video_guide`. Remaining Wan I2V dimensional
rows require separate proof.

## Route Promotion Checklist

Before any route moves from code-wired to production-promoted:

1. Add or update `SPRINT_2_SELECTOR_MAP` in the worker.
2. Mirror selector behavior in app route snapshots.
3. Add worker scratchpad tests for app payload names and required media inputs.
4. Run VibeComfy template validation and worker/app route tests.
5. Run live RunPod generation through the Reigh worker, not just raw VibeComfy.
6. Verify output media, completion handler behavior, billing/variant effects,
   and rollback behavior.
7. Update this document and the post-chain validation log with exact report paths.
