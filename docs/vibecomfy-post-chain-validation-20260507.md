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
- Reigh App create-task route contract:
  `npm exec -- vitest run --config config/testing/vitest.edge.config.ts supabase/functions/_shared/selectedRoute.test.ts supabase/functions/create-task/routeContract.test.ts`
  - Result: `2 files, 14 tests passed`.

## App Endpoint Parity Ledger

Only `z_image_turbo` and the Qwen ready-template group currently have live
VibeComfy production-route proof. Everything else remains WGP-only or explicit
fail-close until it receives:

- selected-template mapping,
- production-shaped fixture,
- live RunPod template proof,
- Reigh-shaped queue proof,
- completion/billing/artifact parity proof,
- rollback proof.

| App-used endpoint family | Route key | Current VibeComfy state | Post-chain validation result |
| --- | --- | --- | --- |
| Text-to-image with `model: z-image` | `z_image_turbo` | `vibecomfy_supported` | Live RunPod pass; app/worker route contracts pass |
| Qwen image generation | `qwen_image`, `qwen_image_2512`, `qwen_image_style` | `qwen_image` WGP-only; `qwen_image_2512` and `qwen_image_style` VibeComfy-supported | `qwen_image_2512` and `qwen_image_style` live RunPod worker pass; plain `qwen_image` has no VibeComfy template and must not alias to 2512 |
| WAN image generation | `wan_2_2_t2i` | WGP-only | Live WGP pass; no VibeComfy parity claim |
| Z image image-to-image | `z_image_turbo_i2i` | WGP-only | Live WGP pass; no VibeComfy parity claim |
| Magic edit / Qwen edit | `qwen_image_edit` | `vibecomfy_supported` | Live RunPod worker pass via `edit/qwen_image_edit` |
| Klein edit | `flux_klein_edit` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Inpaint / annotated edit | `image_inpaint`, `annotated_image_edit` | `vibecomfy_supported` | Live RunPod worker pass via masked/annotated composite into `edit/qwen_image_edit` |
| Image upscale | `image-upscale` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Video enhance | `video_enhance` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Character animate | `animate_character` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Travel Between Images parent/children | `travel_orchestrator`, dimensional `travel_segment`, `travel_stitch` | WGP-only / unsupported children | Live WGP parent/child and stitch proof; no VibeComfy parity claim |
| Join clips parent/children | `join_clips_orchestrator`, dimensional `join_clips_segment`, `join_final_stitch` | WGP-only / unsupported children | Live WGP orchestrator proof after join bug fix; no VibeComfy parity claim |
| Edit video orchestrator | `edit_video_orchestrator` | WGP-only parent with blocked child/control routes | Live WGP orchestrator proof after join bug fix; no VibeComfy parity claim |

## Bottom Line

The chain delivered the migration scaffolding plus production-supported
VibeComfy routes for `z_image_turbo`, `qwen_image_2512`,
`qwen_image_edit`, `qwen_image_style`, `image_inpaint`, and
`annotated_image_edit`. It does not yet provide complete feature parity with
the prior 1.2GP/WGP surface. The correct production stance is:

- allow VibeComfy only for routes with live worker proof listed above,
- keep every other app-used endpoint on WGP or fail-closed,
- promote additional routes one at a time only after the full proof set above.
