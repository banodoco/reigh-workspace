# Sprint 09 Control Rail Travel Matrix Performance

Date: 2026-05-06

Plan: `sprint-9-control-rail-and-20260506-1802`

## Outcome

Sprint 09 execute completed all 12 tasks and produced the Section 3A route-key, selector, replay, and media-contract work. Sense-check found an important over-promotion risk: rows 7 and 8 were initially treated as VibeComfy-supported based on a ready template, but the Reigh travel child handler does not yet execute that template with first/last image inputs and production completion semantics. The sprint was corrected to keep all Section 3A rows WGP/blocked until adapter wiring and live Reigh-shaped proof exist.

## What Passed

- Section 3A route keys are mode-aware for WAN VACE and LTX control modes.
- Dry-run replay and matrix smoke pass for all 13 rows.
- Worker route support, fixture/docs sync, and explicit fail-closed behavior pass focused tests.
- App/cloud-chain selector snapshots preserve support state and missing-selector WGP fallback.
- VibeComfy baseline RunPod smoke produced `ready_template_empty_image_red ok` with one PNG output on pod `guuxsqjh57spu1`; the pod was terminated.

## What Did Not Pass

- Local cloud-chain Vitest commands remain blocked by missing local `vitest`.
- Worker broad pytest collection remains blocked by local missing runtime dependencies.
- Initial VibeComfy corpus matrix failed before execution because `runpod_corpus_matrix.py` still called retired `scripts/materialize_ready_templates.py`.
- The follow-up scoped LTX RunPod matrix did not reach green proof. The launched pod disappeared before completion/artifact capture, the local runner had no active TCP connection while waiting between polls, and manual SSH timed out. This leaves LTX template-family proof open.
- A scoped LTX RunPod matrix is still required after the VibeComfy runner patch to prove the underlying template family runs, but that is only template-runtime proof, not Reigh production parity.

## Fixes Made During Sense-Check

- VibeComfy `runpod_validate.py` and `runpod_corpus_matrix.py` now implement safe argparse help so `--help` cannot launch paid pods.
- VibeComfy corpus matrix accepts `--scope` and no longer fails when the retired ready-template materializer is absent.
- VibeComfy detached RunPod polling now fails after repeated SSH poll failures and still terminates the launched pod through the guard; the CLI wrapper forwards `vibecomfy runpod corpus-matrix --scope ...`.
- Section 3A rows 7/8 were downgraded from `ADAPT`/VibeComfy selector promotion to `BLOCKED`/WGP fallback until Reigh travel adapter wiring exists.

## Current Parity Position

Sprint 09 does not establish full feature parity with Wan2GP for travel rows. It establishes deterministic route/matrix behavior and prevents unsafe promotion. Real parity still requires a Reigh-shaped adapter that maps first image, last image, optional prefix video, prompt, seed, frame count, FPS, LoRA stack, output metadata, thumbnail behavior, and lifecycle completion through VibeComfy, followed by live RunPod proof against that exact path.
