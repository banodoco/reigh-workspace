# Sprint 11A: Production Canary Code Patches

## Overall Context

This is the code-change slice of Sprint 11 production canary. RayWorker routes are promoted sequentially by selector, and any code changes during canary need extra care because there may be no comfortable rollback iteration once users are involved.

## Shared Operating Rules

- Promote by route cohort, not by broad backend switch.
- Cohort A holds 48 hours before B; B holds before E.
- Emergency rollback is a selector flip back to WGP; WGP remains selectable.
- Code patches must be narrow, reversible, and tied to live canary evidence.
- Do not mix runbook/dashboard-only edits into this milestone; those belong to Sprint 11B.

## Sprint Goal

Handle necessary mid-canary code patches without widening production risk.

## Required Deliverables

- Selector or worker/orchestrator code patches required by canary evidence.
- Focused regression tests for each patch.
- Updated rollback notes for any changed behavior.
- Evidence that active non-RayWorker routes remain green when shared app/completion/billing surfaces are touched.

## Exit Criteria

Each code patch has a concrete canary trigger, test evidence, and rollback path; no runbook-only dashboard work is mixed into the code milestone; WGP remains selectable for every affected route.

