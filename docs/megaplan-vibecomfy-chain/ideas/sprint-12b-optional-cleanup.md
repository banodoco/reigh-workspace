# Sprint 12B: Optional Cleanup Sprint or Post-Canary PRs

## Overall Context

This is optional cleanup after the migration is safe, or before Sprint 0 only if all affected baselines are regenerated. It is explicitly not a migration prerequisite.

## Shared Operating Rules

- One PR per cleanup category.
- UNUSED status is not deletion proof by itself; run the Section 8A deletion gate.
- If cleanup lands mid-migration, rerun affected baselines and resolver tests before comparison or canary.
- Defer cleanup when it risks invalidating frozen baselines.

## Sprint Goal

Perform cleanup-only work without changing migration correctness assumptions.

## Required Deliverables

- Turbo-mode scaffolding cleanup after contract safety.
- UNUSED-handler deletion only after Section 8A deletion gate.
- Pyproject dedupe.
- AMBIGUOUS rows proven dead.
- Optional Supabase cleanup migration.
- DB/admin/debug/direct-emitter proof for handler deletions.

## Exit Criteria

Cleanup lands before Sprint 0 with regenerated baselines or after Sprint 11; if it lands mid-migration, affected baselines and resolver tests rerun before comparison/canary.

