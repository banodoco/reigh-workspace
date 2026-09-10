> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Source and dependency provenance

Captured read-only from the local workspace on 2026-09-10.

## Project source

- Repository: `https://github.com/peteromallet/Astrid.git`
- Local source inspected: nested checkout `Astrid/`
- Remote `origin/main`: `82d09bb91c8a4621695c1d8b6966652cad941ef4`
- Selected source ref/SHA: `main` / `82d09bb91c8a4621695c1d8b6966652cad941ef4`
- Working tree: dirty. The selected timeline files below are intentionally included; unrelated dirt is excluded.
- Worktree inventory showed several other branches/worktrees, including prunable historical entries. None is selected custody.

## Reproducible selected dirty source

`source/selected-dirty.patch` is a binary-capable `git diff` from the selected commit over this targeted runtime/visualization closure (31 paths):

```text
astrid/core/execution/generic_host.py
astrid/core/timeline/banodoco_schema.py
astrid/core/timeline/expand_shots.py
astrid/packs/rendering/executors/render/STAGE.md
astrid/packs/rendering/executors/timeline_visualize/STAGE.md
astrid/packs/rendering/executors/timeline_visualize/filmstrip_execution.py
astrid/packs/rendering/executors/timeline_visualize/layout.py
astrid/packs/rendering/executors/timeline_visualize/run.py
astrid/packs/rendering/executors/timeline_visualize/select.py
astrid/packs/timeline/cli.py
astrid/sdk/host_bootstrap.py
astrid/sdk/invocation.py
astrid/sdk/shot_grouping.py
astrid/sdk/timeline_filmstrip.py
astrid/sdk/workspace_client.py
banodoco_workspace_client/contract_metadata.py
banodoco_workspace_client/generated.py
tests/core/timeline/test_expand_shots.py
tests/core/timeline/test_timeline_visualize_select.py
tests/packs/rendering/test_managed_timeline_render.py
tests/sdk/test_host_bootstrap_source_identity.py
tests/sdk/test_timeline_filmstrip.py
tests/sdk/test_timeline_filmstrip_invocation.py
tests/stage1/test_host_bootstrap_manifest_luna.py
tests/stage1/test_invocation_runtime_cutover.py
tests/stage1/test_pack_host_interpreter_identity.py
tests/stage1/test_sdk_explicit_boundary_luna.py
tests/stage1/test_vendored_workspace_client_parity_luna.py
tests/test_generic_host.py
tests/test_shot_grouping.py
tests/v10/test_domain_cli_projects_timelines.py
```

Patch SHA-256: `e61029dd0375577175224df7de3389a407b79d4d2ea40d2da4f5e744f38c59d1`. Current working-tree file digests are in `source/selected-dirty-manifest.sha256`.

The canonical Plan 1 source document was untracked in the source checkout. Its SHA-256 is `e0a4621be5b2c89ffafb2cad18aed8d2455957acb16df4264facc718cf16b754`; the portable copy is `references/timeline-visualization-fixes-plan.md`. No MP4, cache, render output, credential, or whole dirty repo is included.

Excluded unrelated tracked dirt includes auth/OMP/runtime changes, broad test changes, generated assessment files, `workflow_scenarios_master.json`, and the pyproject script rename. Excluded untracked dirt includes `HEAD`, `.DS_Store`, auth/version files, assessment reports, and unrelated tests. The original source checkout remains dirty; the patch is a reproduction aid, not a claim that the full dirty tree is captured.

## Megado skills

- Megado URL: `https://github.com/peteromallet/poms-skills.git`
- Inspected remote `main` / SHA: `f1296034386486d65cf19876d5e5ebfb0547e7cf`
- Required files: `megado/SKILL.md` and `megado-handover/SKILL.md`; direct-read fallback is documented in `START-HERE.md`.
- The local poms-skills checkout has unrelated untracked skill directories; no such dirt is part of this handover.

## Astrid skill/runtime evidence

At the selected Astrid source SHA, the inspected core skill/runtime files were:

- `astrid/packs/_core/skill/SKILL.md` — SHA-256 `40df71540247ce49a84622462aaf6c9f4b0659f924c9579ec518c106e78a9ce3`
- `astrid/packs/_core/skill/references/capabilities.md` — SHA-256 `d9a05ccaa5f77372d43d84e470b99f37a357bbc2c19df592ea4f0e908f77d347`
- `astrid/skills/registry.py` — SHA-256 `102771fff5914772205e6ffe47ccc678748cdfa938a34670591ec126506fc717`
- `astrid/skills/harnesses/base.py` — SHA-256 `b32019faaa44c44eabfd93b79cb8f19a9a36b9497bed5cf87b75dc37ed669905`

These are source references, not proof of a configured native agent capability on the receiving machine. The receiver must report missing capabilities explicitly.

## Sisypy

- Declared dependency in Astrid `pyproject.toml`: `sisypy @ git+https://github.com/peteromallet/sisypy.git@dfb3fa3`
- Remote `main` at inspected time: `dfb3fa3e71e4130df081d1d15d62f57f6e8ebb87`
- Existing editable Sisypy checkout (local sibling path intentionally omitted), same commit but dirty in `sisypy/assessor.py`, `sisypy/runner.py`, and `sisypy/schema.py`; those modifications are excluded.
- The source census found no Astrid-specific `AgenticProjectAdapter`, no agentic scenario suite under `Astrid/tests`, and no existing five-minute UX fixture. Existing Sisypy scenario/evidence guidance and Astrid timeline fixtures are available as references only.

## Banodoco schema/client closure

- Astrid's `pyproject.toml` pins the optional development schema dependency to `https://github.com/banodoco/ArtAgents.git@242f9c4306bf3b501222cb041a9eb246ef47bc85#subdirectory=packages/timeline-schema/python`.
- The pinned commit was declared in source, but it was not independently confirmed as a current remote branch/tag ref during this read-only census; the receiving machine must verify that the exact commit is fetchable before installing. Do not silently substitute another schema revision.
- `banodoco_workspace_client` is vendored in Astrid and is included at the selected source commit. Baseline file SHA-256 values are: `__init__.py` `0952dea0031787ef558ab35fb7f57d66be5de0be652f3bced40f9e215dde39bc`, `contract_metadata.py` `ae223b08aae260212a38ab8d06f50cc053e8b197ec8450e76db46cc3e83642c8`, and `generated.py` `de535ff4c501c8f0ad10f0a6a1b9d1a6fa6e2bc14870974eea9a42738e1679da9`.
- The selected dirty client changes are included because the timeline invocation/host closure uses timeout and request-correlation fields. Verify the clean pinned baseline before applying the timeline patch.
- No external `banodoco-workspace-runtime-execution-20260909` checkout is required for Plan 1 portability; it is not a declared Astrid dependency and no unverified runtime checkout is shipped. If a future delivery path needs a live workspace-runtime service, record its exact URL/SHA and access as a separate prerequisite rather than treating this package as self-contained.

## Environment observed (not pinned as product proof)

Python `3.11.11`; FFmpeg `7.1.1` at `/opt/homebrew/bin/ffmpeg`; Sisypy was installed editable locally. These are prerequisites to check, not a completed delivery environment. No GPU, cloud, model, or credential check was launched.
