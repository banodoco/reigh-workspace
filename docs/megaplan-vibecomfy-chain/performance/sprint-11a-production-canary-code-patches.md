# Sprint 11A Production Canary Code Patches Performance

Date: 2026-05-06

Status: recovered after initial fail-closed execution; `z_image_turbo` has live
proof for canary consideration. Broad feature parity is not proven.

## What Completed

- Produced the app-used endpoint inventory for create-task and AI-agent
  generation surfaces.
- Added route-specific live proof infrastructure for `z_image_turbo`.
- Recovered and passed VibeComfy RunPod selected-template proof for
  `image/z_image`.
- Recovered and passed Reigh-shaped worker queue proof with
  `REIGH_BACKEND=vibecomfy`, selector namespace `production`, selector version
  `sprint-11a-canary`, contract version `1`, profile `default`, and route key
  `z_image_turbo`.
- Recovered and passed WGP rollback proof for the same route-specific case.

## Evidence

- Endpoint inventory: `docs/megaplan-vibecomfy-chain/sprint-11a-vibecomfy-endpoint-inventory.md`
- Live proof: `docs/megaplan-vibecomfy-chain/sprint-11a-live-proof-attempts.md`
- Patch boundary: `docs/megaplan-vibecomfy-chain/sprint-11a-patch-boundary-decision.md`
- Learning log: `/Users/peteromalley/Documents/learnings/megaplan-vibecomfy-sprint-00a-2026-05-05.md`

## Issues Found And Fixed

- VibeComfy route validator did not load adjacent Reigh worker env files.
- Reigh fresh live harness did not provision VibeComfy for the VibeComfy backend.
- Worker preflight metadata used the PAT client when it needed the service
  client.
- VibeComfy integration initially crossed the wrong Python/Torch boundary for
  the RunPod image.
- RunPod lifecycle SDK output exposed secret-bearing raw pod create responses.
- Live harness progress was too silent during long paid remote phases.

## Residual Risk

- Only `z_image_turbo` is proven. No Qwen, image-to-image, edit, upscale, video,
  travel, join, stitch, or orchestrator route has VibeComfy parity proof.
- The live proof was recovered manually after initial execution. Future chain
  execution should keep pushing past transient provider/network failures and
  classify them separately from harness or product defects.
- Remote command output is still not safely streamed during long installs; phase
  logging reduces ambiguity but does not replace redacted command streaming.

## Next Action

Run Megaplan review with the recovered evidence, then continue the chain one
milestone at a time. Any selector promotion must stay route-specific to
`z_image_turbo` unless additional routes get equivalent proof.
