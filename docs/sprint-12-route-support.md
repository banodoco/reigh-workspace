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
| Wan 2.2 VACE travel/join rows | supported | supported | `video/wanvideo_wrapper_22_14b_vace_cocktail` | Live RunPod worker proof for promoted VACE rows |

## Code-Wired, Pending Live Proof

These app-active routes now have VibeComfy selector rows and worker scratchpad
writers, but still require live RunPod generation proof before production canary
promotion.

| Route key | VibeComfy template | Current caveat |
| --- | --- | --- |
| `wan_2_2_i2v` | `video/wanvideo_wrapper_22_14b_i2v_kijai` | Kijai A14B I2V template locally validates; needs live worker generation |
| `animate_character` | `video/wanvideo_wrapper_22_wan_animate_preprocess_kijai` | Kijai WanAnimate preprocessing template locally validates; needs live worker generation |
| `image-upscale`, `image_upscale` | `image/basic_image_upscale` | Contract parity only; currently Lanczos scaling, not model-quality external upscaler parity |
| `video_enhance` | `video/basic_video_enhance` | GIMM-VFI/interpolation/upscale candidate; needs live proof and artifact parity |
| `flux_klein_edit` | `edit/flux2_klein_4b_image_edit_distilled` | 4B expanded template path only; 9B Klein edit parity remains unresolved |

## WGP-Only RayWorker Routes

`travel_orchestrator`, `join_clips_orchestrator`, `edit_video_orchestrator`,
`travel_stitch`, and `join_final_stitch` are WGP-only by current selector
evidence.

## Unsupported-Pending Dimensional Rows

`travel_segment`, `individual_travel_segment`, and `join_clips_segment` are
dimensional route families that remain `vibecomfy_unsupported` unless a specific
Section 3A row is promoted with implementation and proof. Wan 2.2 VACE
flow/canny/depth/raw plus join bridge are promoted through the VACE cocktail
template; LTX and remaining Wan I2V dimensional rows require separate proof.

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
