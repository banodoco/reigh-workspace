# Sprint 0B: Thresholds and Golden Corpus

## Overall Context

This follows Sprint 0A's contract freeze and creates the comparison oracles consumed by every later parity, harness, and canary sprint. The epic cannot rely on subjective media review; later sprints need route-keyed baselines and a single threshold source of truth.

## Shared Operating Rules

- Preserve queue contracts, output shapes, memory-profile behavior, latency expectations, and rollback.
- Use route keys, not friendly names, for baselines and cutover evidence.
- Keep active non-RayWorker routes covered as preservation fixtures even when they stay outside RayWorker.
- Keep `docs/migration-vibecomfy-live-validation.md` synchronized with threshold and route versions.

## Sprint Goal

Produce executable comparison oracles and WGP golden corpora for later migration sprints.

## Required Deliverables

- `migration-thresholds.yaml`.
- WGP self-repeatability report.
- Route-keyed WGP golden corpus for Cohort A/B and representative Cohort E routes.
- Lightweight product-contract fixtures for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`.
- Live-validation document updated to the same route/threshold version.

## Exit Criteria

Threshold YAML is committed and read by a smoke script; WGP self-drift is below thresholds or affected routes are marked WGP-only/pending; corpus is route-keyed; non-RayWorker active routes have owner-approved fixtures or explicit deferral rationale.

