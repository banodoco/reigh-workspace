# Sprint 11B: Production Canary Runbook and Dashboard Updates

## Overall Context

This is the operations/documentation slice of Sprint 11 production canary. It tracks dashboard, alert, runbook, and evidence updates while canary proceeds by route cohort.

## Shared Operating Rules

- Promote by route cohort, not by broad backend switch.
- Cohort A holds 48 hours before B; B holds before E.
- Shadow checks must avoid completion, billing, upload, and user-visible side effects.
- Emergency rollback is a selector flip back to WGP.
- Do not include code patches here; those belong to Sprint 11A.

## Sprint Goal

Keep canary runbooks, dashboards, alerts, and evidence current without paying premium implementation-profile cost.

## Required Deliverables

- Canary runbook updates.
- Cohort dashboard updates.
- Shadow/dual-run report links or summaries.
- Rollback PR references and emergency selector-flip procedure.
- Smoke/alert watch notes for `video_enhance`, `image-upscale`, `animate_character`, and `flux_klein_edit`.

## Exit Criteria

Runbooks and dashboards match the current cohort state; emergency rollback instructions are current; active non-RayWorker routes remain green or canary is paused; no code patches are mixed into this milestone.

