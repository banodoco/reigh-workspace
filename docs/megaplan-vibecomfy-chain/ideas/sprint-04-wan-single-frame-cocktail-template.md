# Sprint 4: Wan Single-Frame and Cocktail Template Work

## Overall Context

This sprint consumes Sprint 3.5's decision. It resolves Wan template risks but intentionally does not require full parent/child orchestration parity, which belongs to Sprint 8.

## Shared Operating Rules

- Author a new Wan 2.2 VACE cocktail template only if Sprint 3.5 proceeds.
- Keep affected Wan routes WGP-only when the template cannot satisfy thresholds.
- Do not claim full orchestration parity in this sprint.
- Preserve `wan_2_2_t2i` as a single-frame output contract when implemented.

## Sprint Goal

Resolve Wan single-frame and cocktail template risks without demanding full orchestration parity.

## Required Deliverables

- Wan 2.2 VACE cocktail template if Sprint 3.5 proceeds.
- Isolated child-route smokes.
- `wan_2_2_t2i` forced single-frame patch if not already landed.

## Exit Criteria

Cocktail compiles/runs under representative profiles; isolated child smokes pass where applicable; `wan_2_2_t2i` is green or WGP-only/pending. Full parent/child parity remains deferred to Sprint 8.

