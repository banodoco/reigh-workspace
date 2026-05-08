# VibeComfy Post-Chain Validation

Date: 2026-05-07

## Chain Status

`docs/megaplan-vibecomfy-chain/chain.yaml` is complete. All 18 milestones are
marked completed and the final Sprint 12B PR (#20) is merged.

## Live RunPod Proof

### Direct VibeComfy Template Proof

Validated route: `z_image_turbo`

- Command:
  `PYENV_VERSION=3.11.11 python -m scripts.runpod_route_validate --route-key z_image_turbo --out-dir out/reigh_route_validation/z_image_turbo/post-chain-watchdog-fix-20260507 --timeout 1800 --poll-interval 30`
- Pod: `8oxw2matooidlz`
- GPU: NVIDIA GeForce RTX 4090
- Selected template: `image/z_image`
- Status: pass
- Outputs: 1 PNG, `1024x1024`, 747,988 bytes
- Artifact report:
  `vibecomfy/out/runpod_artifacts/20260507T020859Z/report.md`
- Watchdog: `completed`, warnings=0
- Pod cleanup: terminated by the runner

Earlier same-day proof also passed on pod `7qnb85xm1m87wf`, but it exposed a
false watchdog crash warning. That VibeComfy reporting bug was fixed and merged
in VibeComfy PR #6, then the clean proof above was rerun.

### Reigh Queue Proof

Validated route: `z_image_turbo`

- Command:
  `PYENV_VERSION=3.11.11 python -m scripts.live_test.main --variant fresh --backend vibecomfy --ref megaplan/vibecomfy-sprint-09-control-rail-travel-matrix --vibecomfy-ref main --route-key z_image_turbo`
- Pod: `e5zu2z42gvwkgl`
- Report:
  `reigh-worker/scripts/live_test/runs/20260507T040824Z/report.md`
- Status: `1/1 passed`
- Task: `56d92eae-4a66-4b5a-9ecc-110cb3bbeab4`
- Generation: `62605462-afbe-421c-9e41-ed0109a3b36b`
- Output: PNG from the production-shaped Reigh worker queue path.
- Pod cleanup: terminated by the runner.

### Reigh Queue Proof: Qwen Ready Templates

Validated routes: `qwen_image_2512`, `qwen_image_edit`, `qwen_image_style`,
`image_inpaint`, `annotated_image_edit`

- Command:
  `PYENV_VERSION=3.11.11 python -m scripts.live_test.main --variant fresh --backend vibecomfy --ref megaplan/vibecomfy-sprint-09-control-rail-travel-matrix --vibecomfy-ref main --case qwen_image_2512 --case qwen_image_edit --case qwen_image_style --case image_inpaint --case annotated_image_edit`
- Pod: `v7ozyfck7hqhbb`
- Report:
  `reigh-worker/scripts/live_test/runs/20260507T065745Z/report.md`
- Status: `5/5 passed`
- Selected templates:
  - `qwen_image_2512` -> `image/qwen_image_2512`
  - `qwen_image_edit`, `qwen_image_style`, `image_inpaint`,
    `annotated_image_edit` -> `edit/qwen_image_edit`
- Outputs:
  - `qwen_image_2512`: task `21845d07-f3c8-40ef-bfe8-54832e8dfb96`,
    generation `face33ec-5c7f-4911-b420-3d57d76e4b19`, PNG output.
  - `qwen_image_edit`: task `220ee446-3222-4197-936a-efccc1493cc3`,
    generation `8eb0e64a-4910-4c6c-b865-bce46a4bcac5`, PNG output.
  - `qwen_image_style`: task `367f7671-ced1-4b41-aec6-6e470c0b002a`,
    generation `2c5feb25-4bd8-4340-972e-929898ca61df`, PNG output.
  - `image_inpaint`: task `84a474a4-f6d5-42b1-a355-fc78796a5c7d`,
    generation `deae6051-d231-4055-b42d-d1dd95e10df2`, PNG output.
  - `annotated_image_edit`: task `35f55290-a8d9-4687-ad05-24a42326fef2`,
    generation `91c981c4-79db-49ae-b371-b919884e2f28`, PNG output.
- Production-path details: the worker generated per-task VibeComfy scratchpads,
  materialized image inputs into each run workspace, created masked composites
  for inpaint/annotated edit, waited for worker preflight readiness before
  inserting tasks, and uploaded outputs through the normal task completion path.

### Reigh Queue Proof: Promoted Qwen Base Route And VACE Variants

Validated on reused RunPod pod `uem4ds6heuwu83` after the post-chain parity
fixes. These runs used the Reigh worker live-test harness against the production
Supabase project and the VibeComfy branch
`megaplan/production-parity-templates`.

- Combined smoke/memory proof:
  `reigh-worker/scripts/live_test/runs/20260507T220856Z/report.md`,
  `3/3 passed` for `z_image_turbo_i2i`, `wan_2_2_t2i`, and
  `individual_travel_segment` VACE raw.
- Direct image/Qwen proof:
  `reigh-worker/scripts/live_test/runs/20260507T223010Z/report.md`,
  `6/6 passed` for `qwen_image_2512`, `qwen_image_edit`,
  `qwen_image_style`, `image_inpaint`, `annotated_image_edit`, and
  `z_image_turbo`.
- Promoted base Qwen route:
  `reigh-worker/scripts/live_test/runs/20260507T232825Z/report.md`,
  `qwen_image_t2i` passed through route key `qwen_image`, task
  `9f15c9ed-59a4-4b99-a311-0b5ba654fbfc`, generation
  `7fafb706-2876-43d9-80aa-e464539a6fc0`, output
  `Qwen-Image-2512_00001_.png`.
- Individual VACE guidance modes after memory tuning:
  `reigh-worker/scripts/live_test/runs/20260507T235320Z/report.md`,
  `3/3 passed` for `individual_travel_segment_wan22_vace_flow`,
  `individual_travel_segment_wan22_vace_canny`, and
  `individual_travel_segment_wan22_vace_depth`.
- Travel-segment VACE video-source modes:
  `reigh-worker/scripts/live_test/runs/20260508T003727Z/report.md`,
  `4/4 passed` for `travel_segment_wan22_vace_raw_video_source`,
  `travel_segment_wan22_vace_flow_video_source`,
  `travel_segment_wan22_vace_canny_video_source`, and
  `travel_segment_wan22_vace_depth_video_source`.
- Join-clips VACE bridge segment:
  `reigh-worker/scripts/live_test/runs/20260508T013338Z/report.md`,
  `1/1 passed` for `join_clips_segment_wan22_vace` through route key
  `join_clips_segment__model-wan22_vace__guidance-vace__continuity-join_bridge__profile-default`.
  Task `3aecdcbb-0321-4084-81c5-073acf8c235f`, generation
  `44fac44b-7018-406d-8d02-065271e06b09`, output
  `Wan-2-2-VACE_00001.mp4`, duration `675.255s`.

Travel-segment proof rows:

| Case | Task | Generation | Output |
| --- | --- | --- | --- |
| `travel_segment_wan22_vace_raw_video_source` | `b6e9b912-aea4-4533-932f-b90a351a0aed` | `487a4126-5b7e-49ae-89ae-21c884ed2e76` | `seg00_output_005215_11c41a.mp4` |
| `travel_segment_wan22_vace_flow_video_source` | `7acae1fa-34c3-44c0-955b-4690385829db` | `9ee22401-c9a2-4595-958f-394fc3e9b320` | `seg00_output_010136_aeec74.mp4` |
| `travel_segment_wan22_vace_canny_video_source` | `78d4d45c-523e-4f68-9a2a-69fecd4af230` | `e75e1292-bb9a-4005-8d48-c68227117e4e` | `seg00_output_011049_8ee2a6.mp4` |
| `travel_segment_wan22_vace_depth_video_source` | `e9c27fc7-9ecb-483b-9763-37bdf2e4e32f` | `5c92b409-b1a6-4367-ab0e-c5273c2870d5` | `seg00_output_012048_5997ac.mp4` |

Production selector seed:

- App migration
  `supabase/migrations/20260508003000_seed_vibecomfy_vace_mode_and_qwen_routes.sql`
  was applied to the linked production Supabase database with
  `npx supabase db push --linked`.
- The migration promotes the validated `qwen_image`, individual VACE
  flow/canny/depth, and travel-segment VACE raw/flow/canny/depth video-source
  route keys to production `vibecomfy` selectors with matching backend
  capabilities.

### WGP Rollback And Baseline Proof

The WGP path was exercised on fresh RunPod pods with production-shaped live
tasks so rollback/control behavior remains proven while VibeComfy is only
enabled for the supported route.

- `z_image_turbo` WGP rollback:
  `reigh-worker/scripts/live_test/runs/20260507T042813Z/report.md`,
  pod `gbc7258uext5yj`, `1/1 passed`, task
  `296a0eae-8201-4021-8a2b-4ca4a192bc98`, generation
  `fb362e35-5694-4d31-9c54-5bb1af3fc31a`.
- Main WGP matrix:
  `reigh-worker/scripts/live_test/runs/20260507T024729Z/report.md`,
  pod `v46wbqkjnlbpwg`, `7/9 passed`; the two travel parent false negatives
  were fixed by adding the parent route contract and repolling child outputs.
- Focused travel parent repoll:
  `travel_orchestrator_wan2_1seg` task
  `367cbf14-e993-40ab-bb09-969bd9bb68db`, generation
  `98b9f1a6-868a-4d98-987d-a48388725c49`, child output MP4 under task
  `b6addd18-fcd7-4ffe-a4a8-41e35739bd14`; `travel_orchestrator_ltx` task
  `fd23b18b-aabf-4d6d-ad2c-af3b48722b87`, generation
  `a23ac486-d26d-43ee-bacc-edc0bc3f814e`, child output MP4 under task
  `324c03cc-ee9c-4718-9a0c-f4595c1baa2a`.
- Missing direct WGP route coverage:
  `reigh-worker/scripts/live_test/runs/20260507T050214Z/report.md`,
  pod `wqt0lar8iiyna2`, `3/3 passed` for `wan_2_2_t2i`,
  `image_inpaint`, and `annotated_image_edit`.
- Expanded WGP direct/orchestrator coverage:
  `reigh-worker/scripts/live_test/runs/20260507T055221Z/report.md`,
  pod `xhgccre7prd1sj`, `5/7 passed`; `qwen_image_edit`, `image_inpaint`,
  `annotated_image_edit`, `z_image_turbo_i2i`, and `travel_stitch` all
  completed with real outputs. The two join/edit failures exposed an actual
  `max_safe_blend` worker bug, which was fixed and rerun.
- Join/edit rerun after the worker fix:
  `reigh-worker/scripts/live_test/runs/20260507T062420Z/report.md`,
  pod `3u5zwyqmx167fl`, `2/2 passed`; `join_clips_orchestrator` task
  `1e8f67e8-4396-4502-add2-a6fcda931342`, generation
  `d18b8244-9017-4957-8fe1-ef6a3b7f7861`, output MP4; and
  `edit_video_orchestrator` task `ae0e7523-8d9f-463f-8e2d-191de393ccdd`,
  generation `494b8dd2-188d-4461-a8f2-a317d1e30707`, output MP4.

## Local Contract Validation

- VibeComfy route/router tests:
  `PYENV_VERSION=3.11.11 python -m pytest tests/test_runpod_route_validate.py tests/test_router.py tests/test_runpod_matrix.py -q`
  - Result: `41 passed`.
- VibeComfy watchdog/report tests:
  `PYENV_VERSION=3.11.11 python -m pytest tests/test_watchdog.py tests/test_runpod_runner.py -q`
  - Result: `33 passed`.
- Reigh Worker selected-template routing:
  `PYENV_VERSION=3.11.11 python -m pytest tests/test_template_routing.py -q`
  - Result: `79 passed, 1 warning`.
- Reigh Worker live harness, Qwen cleanup, and join regression slice:
  `PYENV_VERSION=3.11.11 python -m pytest tests/test_join_orchestrator_and_registry.py scripts/live_test/tests/test_primitives.py tests/test_qwen_model_selection.py tests/runtime/test_worker_preflight.py tests/test_template_routing.py -q`
  - Result: `166 passed, 2 warnings`.
- Reigh Worker Qwen VibeComfy promotion slice:
  `PYENV_VERSION=3.11.11 python -m pytest scripts/live_test/tests/test_primitives.py tests/test_vibecomfy_adapter.py tests/test_template_routing.py tests/test_vibecomfy_backend_selection.py -q`
  - Result: `157 passed, 2 warnings`.
- Reigh Worker VACE/Qwen parity slice after video-source additions:
  `PYENV_VERSION=3.11.11 python -m pytest scripts/live_test/tests/test_primitives.py tests/test_template_routing.py tests/test_vibecomfy_adapter.py -q`
  - Result: `180 passed, 2 warnings`.
- Reigh Worker join VACE dispatch and live-matrix regression slice:
  `PYENV_VERSION=3.11.11 python -m pytest tests/test_vibecomfy_backend_selection.py scripts/live_test/tests/test_primitives.py tests/test_template_routing.py tests/test_vibecomfy_adapter.py -q`
  - Result: `204 passed, 2 warnings`.
- Reigh Worker live launcher cleanup regression:
  `PYENV_VERSION=3.11.11 python -m pytest scripts/live_test/tests/test_primitives.py -q`
  - Result: `84 passed, 1 warning`.
- Reigh Worker app-active unported route fail-close contract:
  `PYENV_VERSION=3.11.11 python -m pytest tests/test_template_routing.py tests/test_vibecomfy_backend_selection.py -q`
  - Result: `108 passed, 2 warnings`.
- Reigh App create-task route contract:
  `npm exec -- vitest run --config config/testing/vitest.edge.config.ts supabase/functions/_shared/selectedRoute.test.ts supabase/functions/create-task/routeContract.test.ts`
  - Result: `2 files, 14 tests passed`.
- Reigh App VibeComfy production route seed and claim namespace slice:
  `npm run test:edge:unit -- --run supabase/functions/create-task/vibecomfyProductionRouteSeed.test.ts supabase/functions/create-task/section3aRouteMetadata.test.ts supabase/functions/claim-next-task/index.test.ts`
  - Result: `3 files, 12 tests passed`.
- Reigh App route metadata consistency after promoting `qwen_image`:
  `npm run test:edge:unit -- --run supabase/functions/create-task/resolvers/shared/routeKeys.test.ts supabase/functions/create-task/vibecomfyProductionRouteSeed.test.ts supabase/functions/create-task/section3aRouteMetadata.test.ts supabase/functions/claim-next-task/index.test.ts`
  - Result: `4 files, 24 tests passed`.
- Reigh App app-active unported route fail-close contract:
  `npm run test:edge:unit -- --run supabase/functions/create-task/resolvers/shared/routeKeys.test.ts supabase/functions/create-task/vibecomfyProductionRouteSeed.test.ts supabase/functions/create-task/section3aRouteMetadata.test.ts supabase/functions/claim-next-task/index.test.ts`
  - Result: `4 files, 30 tests passed`.
- Reigh App turbo travel guard:
  `npm run test:edge:unit -- --run supabase/functions/create-task/resolvers/__tests__/placement.test.ts supabase/functions/create-task/resolvers/shared/routeKeys.test.ts supabase/functions/create-task/vibecomfyProductionRouteSeed.test.ts supabase/functions/create-task/section3aRouteMetadata.test.ts supabase/functions/claim-next-task/index.test.ts`
  - Result: `5 files, 44 tests passed`.
- Reigh App AI timeline agent route-family alias guard:
  `npm run test:edge:unit -- --run supabase/functions/ai-timeline-agent/tools/generation.test.ts supabase/functions/ai-timeline-agent/tools/create-task.test.ts supabase/functions/create-task/resolvers/__tests__/placement.test.ts supabase/functions/create-task/resolvers/shared/routeKeys.test.ts`
  - Result: `4 files, 59 tests passed`.
  - Covers both hyphenated agent task types and snake_case resolver-family
    aliases so legacy `create_generation_task` calls cannot degrade into
    default image generation before they reach the route selector.
- Reigh Worker non-RayWorker active-route preservation/readiness:
  `PYENV_VERSION=3.11.11 python -m pytest scripts/dual_run_compare/tests/test_non_rayworker_fixtures.py scripts/canary_readiness/tests/test_non_rayworker.py -q`
  - Result: `9 passed`.
- VibeComfy full focused suite after WanVideo and model-asset fixes:
  `PYENV_VERSION=3.11.11 python -m pytest -q`
  - Result: `425 passed, 4 skipped, 5 deselected`.

## App Endpoint Parity Ledger

Only the rows with live proof below should be selected for production
VibeComfy. Everything else remains WGP-only or explicit fail-close until it
receives:

- selected-template mapping,
- production-shaped fixture,
- live RunPod template proof,
- Reigh-shaped queue proof,
- completion/billing/artifact parity proof,
- rollback proof.

| App-used endpoint family | Route key | Current VibeComfy state | Post-chain validation result |
| --- | --- | --- | --- |
| Text-to-image with `model: z-image` | `z_image_turbo` | `vibecomfy_supported` | Live RunPod pass; app/worker route contracts pass |
| Qwen image generation | `qwen_image`, `qwen_image_2512`, `qwen_image_style` | `vibecomfy_supported` for validated Qwen template routes | Live RunPod worker pass; production selector seed deployed for `qwen_image` aliasing to `image/qwen_image_2512` |
| WAN image generation | `wan_2_2_t2i` | `vibecomfy_supported` | Live RunPod worker pass; production selector seed deployed for `video/wanvideo_wrapper_22_14b_t2i` |
| Z image image-to-image | `z_image_turbo_i2i` | `vibecomfy_supported` | Live RunPod worker pass; production selector seed deployed for `image/z_image_img2img` |
| Magic edit / Qwen edit | `qwen_image_edit` | `vibecomfy_supported` | Live RunPod worker pass via `edit/qwen_image_edit` |
| Klein edit | `flux_klein_edit` | `vibecomfy_unsupported` | Explicit app/worker VibeComfy selection fails closed; non-RayWorker preservation/readiness fixtures pass |
| Inpaint / annotated edit | `image_inpaint`, `annotated_image_edit` | `vibecomfy_supported` | Live RunPod worker pass via masked/annotated composite into `edit/qwen_image_edit` |
| Image upscale | `image-upscale`, `image_upscale` | `vibecomfy_unsupported` | Explicit app/worker VibeComfy selection fails closed; non-RayWorker preservation/readiness fixtures pass |
| Video enhance | `video_enhance` | `vibecomfy_unsupported` | Explicit app/worker VibeComfy selection fails closed; non-RayWorker preservation/readiness fixtures pass |
| Character animate | `animate_character` | `vibecomfy_unsupported` | Explicit app/worker VibeComfy selection fails closed; non-RayWorker preservation/readiness fixtures pass |
| Travel Between Images parent/children | `travel_orchestrator`, dimensional `travel_segment`, `travel_stitch` | VibeComfy-supported for VACE raw/flow/canny/depth `travel_segment` video-source route keys; parent/stitch remain WGP-only | Live worker proof for all four production-shaped VACE video-source child route keys; production selector seed deployed for those child routes |
| Individual travel segment | `individual_travel_segment` VACE raw/flow/canny/depth first/last route keys | VibeComfy-supported for validated VACE route keys | Live worker proof for raw plus flow/canny/depth; production selector seed deployed for flow/canny/depth, raw was already in the existing selector path |
| Join clips parent/children | `join_clips_orchestrator`, dimensional `join_clips_segment`, `join_final_stitch` | VibeComfy-supported for the Wan 2.2 VACE `join_clips_segment` join-bridge route key; parent/final stitch remain WGP-only | Live worker proof for direct VACE join-bridge child route after fixing worker dispatch; live WGP orchestrator proof remains the parent/final-stitch baseline |
| Edit video orchestrator | `edit_video_orchestrator` | WGP-only parent with blocked child/control routes | Live WGP orchestrator proof after join bug fix; no VibeComfy parity claim |

AI timeline agent generation tools are included in this app-active surface.
The canonical `create_task` tool emits hyphenated task types such as
`image-to-video` and `image-upscale`; the legacy `create_generation_task`
helper also accepts snake_case resolver-family aliases such as
`travel_between_images`, `image_upscale`, `video_enhance`, and
`character_animate`. The alias guard above proves both forms reach the same
registered create-task resolvers and therefore the same route selector/fail-
closed contracts.

## Bottom Line

The chain plus post-chain repair delivered production-supported VibeComfy routes
for `z_image_turbo`, Qwen ready-template image/edit routes, promoted
`qwen_image`, Qwen inpaint/annotated edit routes, individual VACE
travel-segment modes, VACE `travel_segment` video-source modes, and the VACE
`join_clips_segment` join-bridge child route. It does not yet provide complete
feature parity with the prior 1.2GP/WGP surface. The
correct production stance is:

- allow VibeComfy only for routes with live worker proof listed above,
- keep every other app-used endpoint on WGP or fail-closed,
- promote additional routes one at a time only after the full proof set above.

Direct `wan_2_2_i2v` remains intentionally unpromoted. The app previously could
emit it through `turbo_mode: true`, but the Ray worker dispatch catalog does not
own that task type and VibeComfy does not yet have a Wan 2.2 14B Lightning I2V
template equivalent. The app now keeps turbo travel requests on the owned
`travel_orchestrator` route until direct I2V has a real runtime owner, selector
seed, and live proof.
