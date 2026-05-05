# Sprint 12: Dual-Executor Hardening

## Overall Context

This sprint closes the migration as a dual-executor platform, not as WGP retirement. It turns canary results into steady-state ownership, docs, and tests.

## Shared Operating Rules

- WGP runtime code, tests, and startup paths remain intact.
- Supported RayWorker routes can select either backend where validated.
- Active non-RayWorker routes keep documented owners and regression checks.
- Cleanup-only deletion is not needed for migration closure.

## Sprint Goal

Close the epic as a dual-executor platform with explicit ownership for every active generation route.

## Required Deliverables

- Dual-executor runbook.
- WGP-only/Comfy-only/dual-supported route docs.
- Non-RayWorker active-route ownership docs.
- Staging flip tests.
- Final dashboard/alert review.
- Steady-state ownership matrix.
- Cleanup backlog moved to Sprint 12B or separate PRs.

## Exit Criteria

Both executors boot from the same image; supported RayWorker routes can select either backend; WGP remains intact; `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit` have owners and regression checks; cleanup-only deletion is not required for closure.

