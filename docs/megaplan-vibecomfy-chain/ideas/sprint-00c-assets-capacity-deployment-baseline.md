# Sprint 0C: Assets, Capacity, and Deployment Baseline

## Overall Context

This readiness sprint separates infrastructure and asset capacity from behavioral baselines. It must finish before VibeComfy runtime work depends on dual-stack pods and template inventory.

## Shared Operating Rules

- Coordinate `reigh-worker-orchestrator/` and `vibecomfy/` changes as separate workstreams.
- Keep WGP-only deployment defaults available.
- Use VibeComfy's existing RunPod/cloud validation machinery where possible instead of duplicating pod lifecycle logic in the worker.
- Record exact model, template, custom-node, and disk assumptions used by later sprints.

## Sprint Goal

Freeze infra and asset assumptions for dual-stack validation.

## Required Deliverables

- Asset/model/hash manifest.
- Live `ready_templates` inventory.
- Custom-node lock audit.
- Owner/date to change RunPod disk from current 50 GB to 200 GB.
- First dual-stack pod boot/disk/startup measurement.

## Exit Criteria

200 GB change is landed or explicitly PENDING; disk usage is measured; if first boot exceeds 180 GB, raise to 250 GB before Sprint 1.

