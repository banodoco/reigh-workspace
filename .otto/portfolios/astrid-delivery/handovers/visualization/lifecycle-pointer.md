> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Plan 2 pointer — not part of this run

Plan 2 is the separate ephemeral-derived-artifact-lifecycle project. Its canonical plan is `docs/design/ephemeral-derived-artifact-lifecycle-plan.md` and its control root is `.otto/runs/ephemeral-derived-artifact-lifecycle-20260910/`.

Plan 2 owns E2-06, the eventual migration/integration of a completed Plan 1 visualizer into the shared lifecycle. Do not copy its `run.yaml` into this package or merge the two active configurations. Plan 1 must first pass its own visualization acceptance; Plan 2 remains independently implementable against a synthetic producer until that dependency.

This package records only the pointer and boundary. A receiving machine that needs Plan 2 must obtain its separately authorized handover or source checkout.
