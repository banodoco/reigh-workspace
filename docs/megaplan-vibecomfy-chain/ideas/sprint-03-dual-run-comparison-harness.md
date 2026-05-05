# Sprint 3: Dual-Run Comparison Harness

## Overall Context

This sprint turns Sprint 0B thresholds and Sprint 2 routed tasks into executable comparison evidence. It should catch queue, billing, product-effect, and media drift before any production selector exists.

## Shared Operating Rules

- Shadow artifacts must have no user-visible, billing, completion, or upload side effects unless explicitly isolated.
- Compare media, queue contract, product effects, billing/refund/idempotency, latency, VRAM, OOM, and error class.
- Non-RayWorker active routes must stay healthy through shared app/completion/billing paths.
- Routes not yet implemented are pending/fallback/WGP-only, not silently green.

## Sprint Goal

Build the dual-run harness and executable product/billing oracle for landed routes.

## Required Deliverables

- `scripts/dual_run_compare.py`.
- Reports for media similarity, queue contract, product effects, billing/refund/idempotency, latency, VRAM, OOM, and error class.
- No-side-effect shadow artifact isolation.
- Regression checks for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit` through their current owners.

## Exit Criteria

Harness is green for Sprint 2 routes or marks them RED; not-yet-routed RayWorker rows are pending/fallback/WGP-only; product/billing checks are executable; active non-RayWorker routes are not broken by shared app/completion/billing changes.

