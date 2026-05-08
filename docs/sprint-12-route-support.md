# Sprint 12 Route Support

This document is derived from `docs/sprint-12-route-inventory.md`,
`reigh-worker/source/task_handlers/tasks/template_routing.py`, app route
stamping in `reigh-app/supabase/functions/create-task/routeContract.ts`, and
non-RayWorker fixture metadata.

## Dual-Supported RayWorker Routes

| Route key | WGP | VibeComfy | Template | Evidence |
| --- | --- | --- | --- | --- |
| `z_image_turbo` | supported | supported | `image/z_image` | `SPRINT_2_SELECTOR_MAP`; Python route tests; app selected-route fixture |
| `z_image_turbo_i2i` | supported | supported | `image/z_image_img2img` | `SPRINT_2_SELECTOR_MAP`; Wan2GP img2img defaults; VibeComfy template tests |
| `qwen_image_2512` | supported | supported | `image/qwen_image_2512` | `SPRINT_2_SELECTOR_MAP`; app route metadata seed; VibeComfy live proof |
| `qwen_image` | supported | supported | `image/qwen_image_2512` | `SPRINT_2_SELECTOR_MAP`; app route metadata seed; VibeComfy live proof |
| `qwen_image_edit` | supported | supported | `edit/qwen_image_edit` | `SPRINT_2_SELECTOR_MAP`; app route metadata seed; VibeComfy live proof |
| `qwen_image_style` | supported | supported | `edit/qwen_image_edit` | `SPRINT_2_SELECTOR_MAP`; app route metadata seed; VibeComfy live proof |
| `image_inpaint` | supported | supported | `edit/qwen_image_edit` | `SPRINT_2_SELECTOR_MAP`; app route metadata seed; VibeComfy live proof |
| `annotated_image_edit` | supported | supported | `edit/qwen_image_edit` | `SPRINT_2_SELECTOR_MAP`; app route metadata seed; VibeComfy live proof |
| `wan_2_2_t2i` | supported | supported | `video/wanvideo_wrapper_22_14b_t2i` | `SPRINT_2_SELECTOR_MAP`; Wan2GP T2I defaults; VibeComfy template tests |
| Wan 2.2 VACE travel/join rows | supported | supported | `video/wanvideo_wrapper_22_14b_vace_cocktail` | `SECTION3A_ROUTE_SUPPORT_MAP`; Wan2GP VACE 3-phase defaults; WanVideoWrapper VACE nodes |

## VibeComfy-Only Routes

None. Sprint 12 does not close any route as VibeComfy-only; WGP remains intact.

## WGP-Only RayWorker Routes

`travel_orchestrator`, `join_clips_orchestrator`, `edit_video_orchestrator`,
`travel_stitch`, and `join_final_stitch` are WGP-only by current selector
evidence.

## Unsupported-Pending RayWorker Routes

`travel_segment`, `individual_travel_segment`, and `join_clips_segment` are
dimensional route families that remain `vibecomfy_unsupported` unless a specific
Section 3A row is promoted with implementation and proof. Wan 2.2 VACE
flow/canny/depth/raw plus join bridge are promoted through the VACE cocktail
template; LTX and Wan I2V rows remain unsupported-pending and retain their
individual `NEW` or `BLOCKED` fixture disposition plus blocker reason.

Unsupported-pending Section 3A examples include:

- Wan 2.2 I2V and Uni3C rows waiting on the relevant template/preprocessing path.
- LTX first/last rows waiting on travel child adapter wiring.
- LTX control rows waiting on proven control-capable templates and preprocessing.
- App-active direct routes `wan_2_2_i2v`, `image-upscale`, `image_upscale`,
  `video_enhance`, `animate_character`, and `flux_klein_edit` are explicit
  fail-closed VibeComfy rows until each has a real VibeComfy implementation or
  remains intentionally API-owned.

## Non-RayWorker API-Owned Routes

The following active routes are outside the RayWorker backend selector and keep
API-orchestrator ownership: `video_enhance`, `image-upscale`,
`image_upscale`, `animate_character`, `flux_klein_edit`, plus the other
API-orchestrator rows listed in `docs/sprint-12-route-inventory.md`.

## Route Promotion Checklist

Before any route moves to `dual_supported`:

1. Add or update `SPRINT_2_SELECTOR_MAP` in `reigh-worker/source/task_handlers/tasks/template_routing.py`.
2. For dimensional travel rows, add or update `SECTION3A_ROUTE_SUPPORT_MAP` with preserved blocker/disposition detail until resolved.
3. Mirror selector behavior in `reigh-app/supabase/functions/_shared/selectedRoute.ts` and app stamping in `reigh-app/supabase/functions/create-task/routeContract.ts`.
4. Update route snapshots in `reigh-app/supabase/functions/_shared/selectedRoute.fixtures.json` when app-visible output changes.
5. Run full Python route tests: `PYTHONPATH=reigh-worker pytest reigh-worker/tests/test_template_routing.py`.
6. Run non-RayWorker fixture/readiness tests if the route is API-orchestrator owned: `pytest reigh-worker/scripts/dual_run_compare/tests/test_non_rayworker_fixtures.py reigh-worker/scripts/canary_readiness/tests/test_non_rayworker.py`.
7. Run app route tests: `npm exec -- vitest run --config config/testing/vitest.edge.config.ts supabase/functions/_shared/selectedRoute.test.ts supabase/functions/create-task/routeContract.test.ts`.
8. Verify dashboard/alert surfaces for route totals, selected pool totals, route worker health, missing runtime evidence, smoke failure, and completion/billing failure where applicable.

No unsupported route is promoted by this document.
