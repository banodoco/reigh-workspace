# Sprint 3.5: Wan 2.2 VACE Feasibility Dry Run

## Overall Context

This short sprint is a decision gate before full Wan template work. It tests whether the two-stage HIGH-to-LOW sampler hypothesis can reproduce WGP closely enough for Wan-family travel/join routes.

## Shared Operating Rules

- Use Section 11 video thresholds as the PROCEED/FALL-BACK gate.
- Keep failure scoped: if this falls back, Wan-family VACE travel/join routes become WGP-only while non-Wan migration work continues.
- Use existing VibeComfy template/runtime authoring conventions and cite local/upstream evidence.

## Sprint Goal

Test the two-stage HIGH-to-LOW sampler hypothesis before full Wan template implementation.

## Required Deliverables

- Minimal dry-run workflow/template.
- One 49-frame comparison.
- `dry-run-report.md` with explicit PROCEED or FALL-BACK decision.

## Exit Criteria

PROCEED iff Section 11 video thresholds pass; otherwise mark Wan-family VACE travel/join routes WGP-only while the rest of the migration continues.

