# Sprint 2: Adapter Seam and Local Selector Skeleton

## Overall Context

This sprint creates the first worker-side VibeComfy seam. It depends on Sprint 1 profile behavior and deliberately proves local route selection before production selector/claim work arrives in Sprint 6.

## Shared Operating Rules

- Keep `reigh-worker/` external Supabase queue contracts unchanged.
- Backend-neutral resolved tasks must exist before WGP-specific queue conversion.
- Unsupported Comfy routes fail closed and remain WGP-only.
- Do not require Wan VACE cocktail or full orchestrated parity here.

## Sprint Goal

Add the worker VibeComfy adapter and early route/selector abstraction.

## Required Deliverables

- `template_routing.py`.
- Executor/adapter seam.
- Backend-neutral resolved-task object.
- Local `REIGH_BACKEND` and static/local selector map.
- Route support states.
- Direct smokes for `z_image_turbo` and `qwen_image_2512`.
- One LTX-only or template-independent child smoke.
- Minimal backend/template/profile/error telemetry.
- Include `wan_2_2_t2i` only if its single-frame patch lands here.

## Exit Criteria

Feature-flagged Comfy path works for included direct routes without entering `_convert_to_wgp_task`; child smoke avoids Wan VACE cocktail; unsupported Comfy routes fail closed; local route derivation is test-covered.

