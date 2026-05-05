# Sprint 6: Production Selector and Claim Contract

## Overall Context

This sprint turns local selector ideas into production claim behavior before orchestrated routes depend on them. It is the control-plane foundation for rollback and canary.

## Shared Operating Rules

- Production missing selector key means WGP/no-claim, never implicit Comfy.
- Workers must not claim routes they cannot execute.
- Selector version and selected backend must be visible in logs or task metadata.
- Child rows created later must be able to snapshot route selection.

## Sprint Goal

Make selector and claim behavior concrete for production.

## Required Deliverables

- Selector schema/namespace.
- Route-key serialization, including direct variants where needed.
- Index/RPC/query behavior.
- Cache TTL and rollback SLO.
- Malformed/unauthorized/stale-entry tests.
- Claim-time backend eligibility or pre-execution requeue/fail-closed guard.
- Selector-version logging.
- Child-route snapshot field contract for later parent-created rows.

## Exit Criteria

Missing production route key means WGP/no-claim; mismatched workers cannot claim or execute selected routes; selector unreachable behavior and rollback SLO are tested; selected backend/selector version can be pinned for child rows created after parent claim.

