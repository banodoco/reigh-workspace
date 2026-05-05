# Sprint 9: Control-Rail and Travel-Matrix Parity

## Overall Context

This sprint completes Cohort E parity for canary-intended routes after lifecycle propagation exists. It validates the control rails, continuity sub-cases, and media semantics around Comfy outputs.

## Shared Operating Rules

- Every non-FALL-BACK row of Section 3A's travel matrix must pass through the current dispatcher.
- LTX control rows cannot rely on an unproven first/last-only seam.
- Native post-processing must preserve frame count, FPS, audio, thumbnail, and output contracts.
- Persisted-row compatibility replay is required before promotion.

## Sprint Goal

Complete control-rail and travel-matrix parity for promoted Cohort E routes.

## Required Deliverables

- Canny/Depth/Pose/Flow preprocessing.
- ffmpeg/ffprobe frame-count/FPS/audio/thumb semantics checks around Comfy outputs.
- Full Section 3A matrix smoke report.
- LTX control rows verified against a real control-capable template or marked NEW/BLOCKED/WGP-only.
- Continuity smokes.
- Persisted-row compatibility replay.

## Exit Criteria

Every non-FALL-BACK matrix row passes through current dispatcher; native media post-processing preserves contracts; LTX rows 9-13 no longer depend on an unproven seam; replay is green or route is WGP-only.

