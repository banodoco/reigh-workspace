# Sprint 1: VibeComfy Memory-Profile MVP

## Overall Context

This is the first implementation sprint after kickoff readiness. Memory-profile parity is load-bearing because production relies on Wan2GP profiles for GPU fit, OOM avoidance, latency, and cost predictability.

## Shared Operating Rules

- Treat Wan2GP profiles 1-5 as externally visible behavior.
- Preserve process-default and per-task override semantics.
- Prefer VibeComfy-native config/session APIs where available; avoid worker-only string patching.
- Keep WGP defaults intact if profile mapping is not operationally proven.

## Sprint Goal

Implement five-tier VibeComfy memory-profile parity.

## Required Deliverables

- `MemoryProfile` abstraction in `vibecomfy/`.
- Round-trip tests into embedded and managed-server config/argv.
- Representative template profile smokes.
- Process-default plus per-run override tests.

## Exit Criteria

Profiles 1-5 round-trip; profiles 1 and 3 have VRAM/wall-clock data; any profile change requiring session restart is documented.

