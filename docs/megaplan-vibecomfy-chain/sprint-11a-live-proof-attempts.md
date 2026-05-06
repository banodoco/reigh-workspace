# Sprint 11A Live Route Proof Attempts

Date: 2026-05-06

Scope: Batch 3, T4 plus manual sense-check recovery. Route-specific live proof
for VibeComfy promotion, starting with `z_image_turbo`, the only current
`vibecomfy_supported` route from the endpoint inventory.

## Route Status

| route_key | task_type | selected_template_id | proposed backend | proof status | promotion status |
| --- | --- | --- | --- | --- | --- |
| `z_image_turbo` | `z_image_turbo` | `image/z_image` | `vibecomfy` | live RunPod selected-template pass, Reigh-shaped queue pass, WGP rollback pass | proven for canary consideration only; no broad production parity |

All other app-used VibeComfy-candidate routes from the inventory remain WGP-only
or VibeComfy-unsupported and unpromoted. Sprint 11A proves only the
`z_image_turbo` route path.

## Initial Execution Failures

### VibeComfy RunPod Selected-Template Proof

Command:

```bash
cd vibecomfy && python -m scripts.runpod_route_validate \
  --route-key z_image_turbo \
  --out-dir out/reigh_route_validation/z_image_turbo/sprint11a-batch3 \
  --timeout 1800 \
  --poll-interval 30
```

Initial result: failed before RunPod launch because the validator only read the
process environment and did not load the neighboring `reigh-worker/.env` file.

Recovery: patched `scripts/runpod_route_validate.py` to load env from
`vibecomfy/.env` and adjacent `reigh-worker/.env` without overriding exported
values. Added focused env-loader coverage.

### Reigh-Shaped Worker Queue Proof, VibeComfy Backend

Command:

```bash
cd reigh-worker && python -m scripts.live_test.main \
  --variant fresh \
  --backend vibecomfy \
  --selector-namespace production \
  --selector-version sprint-11a-canary \
  --worker-contract-version 1 \
  --worker-profile default \
  --route-key z_image_turbo
```

Initial result: failed during live Supabase lookup with a transient DNS/connect
error. Manual token probing later succeeded, so this was not a persistent
credential failure.

Subsequent recovery exposed real harness/runtime gaps:

- The fresh worker proof cloned only Reigh-Worker, not VibeComfy, so
  `REIGH_BACKEND=vibecomfy` failed preflight. The live harness now clones and
  installs VibeComfy and exports `VIBECOMFY_CWD`, `VIBECOMFY_PATH`, and
  `VIBECOMFY_PYTHON`.
- Worker preflight metadata tried to publish through the PAT-auth worker client.
  Runtime preflight metadata now uses the service client when the service key is
  present.
- VibeComfy requires Python 3.11. The live VibeComfy path no longer tries to use
  the worker Python 3.10 virtualenv.
- A separate isolated VibeComfy virtualenv pulled a Torch build incompatible
  with the RunPod image driver. The live VibeComfy path now uses the image's
  system Python 3.11/Torch stack.
- RunPod lifecycle pod creation printed SDK `raw_response` content that included
  secret-bearing env values. The SDK stdout is now suppressed during pod create.

### WGP Rollback Rerun

Command:

```bash
cd reigh-worker && python -m scripts.live_test.main \
  --variant fresh \
  --wgp-rollback \
  --selector-namespace production \
  --selector-version sprint-11a-canary \
  --worker-contract-version 1 \
  --worker-profile default \
  --route-key z_image_turbo
```

Initial result: blocked by the same transient live Supabase lookup failure.
Recovered after the live environment and worker harness issues above were fixed.

## Passing Evidence

### VibeComfy RunPod Selected-Template Proof

Retry command:

```bash
cd vibecomfy && PYENV_VERSION=3.11.11 python -m scripts.runpod_route_validate \
  --route-key z_image_turbo \
  --out-dir out/reigh_route_validation/z_image_turbo/sprint11a-manual-retry-20260506 \
  --timeout 1800 \
  --poll-interval 30
```

Result: pass.

- Pod: `yhicnabayrc5t7`, terminated after run.
- Artifact directory: `vibecomfy/out/runpod_artifacts/20260506T212136Z`.
- Manifest status: `pass`, exit code `0`, outputs `1`, failures `0`.
- Output file: `output/z-image_00001_.png`.
- Output dimensions: `1024x1024`.
- Output bytes: `747988`.
- Route result: `route_key=z_image_turbo`, `task_type=z_image_turbo`,
  `selected_template_id=image/z_image`, `status=ok`, `seconds=55`.
- Note: the watchdog diagnosis reported `crashed`, but the route result,
  stop reason, exit code, and downloaded output show successful completion.

### Reigh-Shaped Worker Queue Proof, VibeComfy Backend

Retry command:

```bash
cd reigh-worker && PYENV_VERSION=3.11.11 python -m scripts.live_test.main \
  --variant fresh \
  --ref megaplan/vibecomfy-sprint-09-control-rail-travel-matrix \
  --vibecomfy-ref megaplan/vibecomfy-sprint-04-wan-single-frame \
  --backend vibecomfy \
  --selector-namespace production \
  --selector-version sprint-11a-canary \
  --worker-contract-version 1 \
  --worker-profile default \
  --route-key z_image_turbo
```

Result: pass.

- Report directory: `reigh-worker/scripts/live_test/runs/20260506T223318Z`.
- Pod: `io794j07eysuqn`, terminated after run.
- Passed cases: `1/1`.
- Task id: `f82463f9-b7f6-4733-88d4-0a44d6b61d2d`.
- Final task status: `Complete`.
- Generation id: `ded1a5b3-af7f-4a16-a82e-f5fadf09813f`.
- Output:
  `https://wczysqzxlwdndgxitrvc.supabase.co/storage/v1/object/public/image_uploads/702a2ebf-569e-4f7d-a7df-78e7c1847000/tasks/f82463f9-b7f6-4733-88d4-0a44d6b61d2d/z-image_00001_.png`
- Duration: `224.555` seconds.
- Worker logs include `[PREFLIGHT] status=passed backend=vibecomfy failed=none`.

### WGP Rollback Rerun

Retry command:

```bash
cd reigh-worker && PYENV_VERSION=3.11.11 python -m scripts.live_test.main \
  --variant fresh \
  --ref megaplan/vibecomfy-sprint-09-control-rail-travel-matrix \
  --wgp-rollback \
  --selector-namespace production \
  --selector-version sprint-11a-canary \
  --worker-contract-version 1 \
  --worker-profile default \
  --route-key z_image_turbo
```

Result: pass.

- Report directory: `reigh-worker/scripts/live_test/runs/20260506T225131Z`.
- Pod: `cqlfzn81c2foqv`, terminated after run.
- Passed cases: `1/1`.
- Task id: `b12c36b8-7f2c-4608-aa79-b5b38f2f60f7`.
- Final task status: `Complete`.
- Generation id: `532ba8cb-6253-4726-b284-c49f88680f02`.
- Output:
  `https://wczysqzxlwdndgxitrvc.supabase.co/storage/v1/object/public/image_uploads/702a2ebf-569e-4f7d-a7df-78e7c1847000/tasks/b12c36b8-7f2c-4608-aa79-b5b38f2f60f7/b12c36b8-7f2c-4608-aa79-b5b38f2f60f7_2026-05-06-23h05m13s_seed1732_A%20compact%20red%20cube%20on%20a%20clean%20white%20tabletop%20product-photo%20lighting.png`
- Worker logs include `[PREFLIGHT] status=passed backend=wgp failed=none`,
  `WGP imported OK`, and a completed `Z Image Turbo` task.

## T4 Conclusion

`z_image_turbo` now has all three required live proofs:

- VibeComfy selected-template RunPod execution.
- Reigh-shaped worker queue execution with `REIGH_BACKEND=vibecomfy`.
- WGP rollback execution for the same route-specific case.

This evidence is route-specific. It does not prove parity for Qwen image,
image-to-image, edit, upscale, video, travel, join, stitch, or other app-used
routes. Those remain unpromoted until each route has equivalent selected-template
and Reigh-shaped proof.
