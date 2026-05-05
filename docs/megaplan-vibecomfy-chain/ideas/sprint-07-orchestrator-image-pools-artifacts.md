# Sprint 7: Orchestrator Image, Pools, and Artifact Contract

## Overall Context

This sprint makes deployment, pool health, and artifacts canary-ready after the selector contract exists. It spans `reigh-worker-orchestrator/` and `reigh-worker/`.

## Shared Operating Rules

- WGP and VibeComfy remain coinstalled in the worker image.
- Stale workers must not claim newer selected routes.
- Artifact paths, debug retention, redaction, LoRA cache limits, sweeps, and quota alerts must be testable.
- Telemetry must be visible through the chosen transport, not only local logs.

## Sprint Goal

Make orchestrator image, pools, health checks, and artifact lifecycle canary-ready.

## Required Deliverables

- WGP/Comfy startup examples.
- Backend/profile flags.
- Health probes.
- Model/custom-node/template preflight.
- Warm-cache strategy.
- Disk-near-full behavior.
- Drain/kill/restart policy.
- Pool sizing and rollback reserve.
- Artifact path/prefix/TTL/debug retention/redaction/LoRA cache/orphan sweep/quota alert contract.
- Telemetry transport for backend/template/profile/run id.

## Exit Criteria

WGP and Comfy pools launch from the same image; stale workers cannot claim newer routes; artifact cleanup and debug retention are testable; labels are visible in the chosen telemetry transport; staged rollback exercise passes.

