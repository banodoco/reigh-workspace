# VibeComfy Post-Chain Validation

Date: 2026-05-07

## Chain Status

`docs/megaplan-vibecomfy-chain/chain.yaml` is complete. All 18 milestones are
marked completed and the final Sprint 12B PR (#20) is merged.

## Live RunPod Proof

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
- Reigh App create-task route contract:
  `npm exec -- vitest run --config config/testing/vitest.edge.config.ts supabase/functions/_shared/selectedRoute.test.ts supabase/functions/create-task/routeContract.test.ts`
  - Result: `2 files, 14 tests passed`.

## App Endpoint Parity Ledger

Only `z_image_turbo` currently has live VibeComfy production-route proof.
Everything else remains WGP-only or explicit fail-close until it receives:

- selected-template mapping,
- production-shaped fixture,
- live RunPod template proof,
- Reigh-shaped queue proof,
- completion/billing/artifact parity proof,
- rollback proof.

| App-used endpoint family | Route key | Current VibeComfy state | Post-chain validation result |
| --- | --- | --- | --- |
| Text-to-image with `model: z-image` | `z_image_turbo` | `vibecomfy_supported` | Live RunPod pass; app/worker route contracts pass |
| Qwen image generation | `qwen_image`, `qwen_image_2512`, `qwen_image_style` | WGP-only | Fail-close/contract covered locally; no VibeComfy parity claim |
| WAN image generation | `wan_2_2_t2i` | WGP-only | Fail-close/contract covered locally; no VibeComfy parity claim |
| Z image image-to-image | `z_image_turbo_i2i` | WGP-only | Fail-close/contract covered locally; no VibeComfy parity claim |
| Magic edit / Qwen edit | `qwen_image_edit` | WGP-only | Fail-close/contract covered locally; no VibeComfy parity claim |
| Klein edit | `flux_klein_edit` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Inpaint / annotated edit | `image_inpaint`, `annotated_image_edit` | WGP-only | Fail-close/contract covered locally; no VibeComfy parity claim |
| Image upscale | `image-upscale` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Video enhance | `video_enhance` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Character animate | `animate_character` | unsupported | Explicit VibeComfy selection must fail closed; no parity claim |
| Travel Between Images parent/children | `travel_orchestrator`, dimensional `travel_segment`, `travel_stitch` | WGP-only / unsupported children | Parent selection blocked by child/control requirements; no parity claim |
| Join clips parent/children | `join_clips_orchestrator`, dimensional `join_clips_segment`, `join_final_stitch` | WGP-only / unsupported children | Parent selection blocked by child/control requirements; no parity claim |
| Edit video orchestrator | `edit_video_orchestrator` | WGP-only parent with blocked child/control routes | No VibeComfy parity claim |

## Bottom Line

The chain delivered the migration scaffolding and one production-supported
VibeComfy route. It does not yet provide complete feature parity with the prior
1.2GP/WGP surface. The correct production stance is:

- allow VibeComfy only for `z_image_turbo` after selector promotion,
- keep every other app-used endpoint on WGP or fail-closed,
- promote additional routes one at a time only after the full proof set above.
