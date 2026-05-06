# Sprint 11A Production Patch Boundary Decision

Date: 2026-05-06

Scope: Batch 4, T5 plus manual sense-check recovery. Decide whether Sprint 11A
has enough agent-gathered evidence to choose one production code patch boundary.

## Decision

`z_image_turbo` is the only route with enough live proof for canary promotion
consideration.

Sprint 11A does not justify broad VibeComfy production parity or selector
promotion for any other route. Every non-`z_image_turbo` app-used route remains
WGP-only or VibeComfy-unsupported until route-specific proof exists.

## Evidence Reviewed

- Endpoint inventory: `docs/megaplan-vibecomfy-chain/sprint-11a-vibecomfy-endpoint-inventory.md`
- Live proof attempts: `docs/megaplan-vibecomfy-chain/sprint-11a-live-proof-attempts.md`

Recovered live proof now exists for `z_image_turbo`:

- VibeComfy RunPod selected-template execution passed for selected template
  `image/z_image`.
- Reigh-shaped worker queue validation passed under `REIGH_BACKEND=vibecomfy`,
  selector namespace `production`, selector version `sprint-11a-canary`, worker
  contract version `1`, worker profile `default`, and route key
  `z_image_turbo`.
- WGP rollback rerun passed for the same route-specific case.

## Boundary Classification

| Candidate boundary | Decision | Reason |
| --- | --- | --- |
| Selector map / route key | candidate for `z_image_turbo` only | The route has selected-template, Reigh queue, and rollback proof. Promotion should stay canary-scoped and route-specific. |
| Section 3A support-report metadata | rejected | Travel/Section 3A rows still lack VibeComfy adapter parity and live Reigh-shaped proof. |
| Worker claim guard | no new patch required by this proof | Claim behavior was exercised through the queue proof; no separate guard defect was found for `z_image_turbo`. |
| Task-count selected-pool visibility | no new patch required by this proof | The live case proved execution/completion, not a need for aggregate count behavior changes. |
| Orchestrator pool / stale-worker behavior | rejected | No orchestrator route is promoted; travel/join/edit-video parents remain WGP-only or blocked. |
| Completion | no new patch required by this proof | The route completed and produced generation artifacts through the existing completion path. |
| Billing | no new patch required by this proof | No billing-specific defect was observed in this canary route proof. |
| Worker adapter behavior | patched in live harness/runtime support | Worker live proof required VibeComfy provisioning, Python 3.11/system Torch selection, and service-client preflight metadata fixes. |

## Required Next Gate

Before production promotion beyond canary consideration:

- Confirm the selector patch is exactly scoped to `z_image_turbo`.
- Keep WGP rollback available for the same route.
- Do not infer support for Qwen image, image-to-image, edit, upscale, video,
  travel, join, stitch, or other routes from this proof.
- Require the same selected-template plus Reigh-shaped queue proof for each
  additional route before promotion.

Sprint 11A's usable boundary is therefore narrow: `z_image_turbo` can move to
the next canary promotion decision; all other routes stay fail-closed.
