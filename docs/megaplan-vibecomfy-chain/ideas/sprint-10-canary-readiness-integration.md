# Sprint 10: Canary Readiness Integration

## Overall Context

This sprint integrates the evidence and operations surface needed for a go/no-go decision. It follows selector, pool, artifact, lifecycle, and travel-matrix work.

## Shared Operating Rules

- Canary does not begin until direct-route parity, selector/claim behavior, orchestrator pools, artifact lifecycle, and orchestrated-route parity have test or live-validation evidence.
- Evidence should be easy to inspect, not scattered across ad hoc logs.
- Active non-RayWorker route smoke evidence remains required.
- Rollback must be exercised before production promotion.

## Sprint Goal

Integrate evidence packages, dashboards, alerts, and rollback runbooks.

## Required Deliverables

- Live-validation evidence package.
- Dashboards.
- Section 11 alert rules.
- Draft rollback PRs.
- In-flight rollback exercise.
- Active non-RayWorker smoke evidence for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`.

## Exit Criteria

Soak covers mixed pools, concurrent claims, selector flip with in-flight work, worker kill/restart, cold/warm cache, and disk-near-full behavior; active non-RayWorker routes remain healthy through shared app/completion/billing paths.

