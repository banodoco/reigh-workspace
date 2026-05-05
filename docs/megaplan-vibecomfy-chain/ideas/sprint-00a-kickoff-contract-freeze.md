# Sprint 0A: Kickoff and Contract Freeze

## Overall Context

This is the first milestone in the sequential VibeComfy migration chain from `docs/migration-vibecomfy.md`. The epic adds VibeComfy as a peer executor beside Wan2GP while preserving queue contracts, output shapes, latency expectations, memory-profile behavior, rollback, and active non-RayWorker generation routes. This sprint freezes the contract before adapter or template work starts.

## Shared Operating Rules

- Treat `reigh-worker/`, `reigh-worker-orchestrator/`, and `vibecomfy/` as independent nested Git repos; use `git -C <repo> ...` for repo-aware sweeps.
- Use `rg` for discovery. Start from `docs/migration-vibecomfy.md` and companion `docs/migration-vibecomfy-live-validation.md`.
- Do not migrate raw `task_type: "comfy"`; it is cleanup-gated only.
- Do not let missing selector keys imply Comfy in production; production default is WGP/no-claim until Sprint 6 proves selector behavior.
- Keep active non-RayWorker routes in scope for preservation checks: `video_enhance`, `image-upscale`, `animate_character`, `flux_klein_edit`.

## Sprint Goal

Close kickoff blockers and freeze the project generation contract before implementation sprints start.

## Required Deliverables

- Signed Section 12 pre-kickoff checklist.
- RayWorker-owned USED task inventory.
- Active non-RayWorker route inventory and owner/runtime decision for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`.
- Resolver safety test or fix for `turbo_mode: true`.
- Per-USED-RayWorker-task contract skeleton covering payload, timeout, polling cadence, output fields, product effects, billing, duplicate completion, and partial-orchestrator failure.

## Exit Criteria

No Sprint 1 implementation starts until `turbo_mode` is safe, every active non-RayWorker row has a named owner/runtime plus preserve-vs-move decision, and every USED RayWorker task has a baseline owner plus runnable/skipped/blocked status.

