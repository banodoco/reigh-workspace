# Sprint 8: Orchestrated Route Propagation and Lifecycle Contract

## Overall Context

This sprint brings parent/child workflows onto the selector contract. It is the point where travel, join, and edit-video orchestration must reject mixed or unsupported backend combinations before creating partial work.

## Shared Operating Rules

- Parent backend selection is authoritative only when all required child routes are supported, tested, and not WGP-only.
- Child rows must carry route snapshot metadata: selected backend, selector version, parent route key, and support state.
- Preserve dependency arrays, idempotency, cancellation, duplicate completion handling, and repair paths.
- Fail closed before child creation when backend consistency cannot be guaranteed.

## Sprint Goal

Route parent/child workflows consistently through selected backend where Comfy support exists.

## Required Deliverables

- Propagation for travel/join/edit-video parent and child surfaces.
- Persisted child-row route snapshot.
- Dependency-array/idempotency/cancellation behavior for DB-created child rows.
- Parent/child backend-consistency guards.
- Lifecycle-contract tests.
- Repair/runbook hooks for partial children, uploaded-but-not-completed outputs, duplicate completion, mixed-backend child sets, and parent repair.

## Exit Criteria

Parent rejects Comfy if any required child route is WGP-only, unsupported, fallback, or untested; child rows created after parent claim carry enough metadata to avoid selector drift; lifecycle contract is green for every USED route intended for canary.

