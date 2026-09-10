> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Agent goal

## Mode and authorization

Planning-only Megado setup. The user authorized a self-contained planning package in
this repository's `.otto/runs/` directory and explicitly did not request a planning
branch. No implementation, worktree, tests, Runtime/database mutation, deployment,
or executable review is authorized by this setup.

Run configuration: [run.yaml](run.yaml). Direction: [northstar.md](northstar.md).

## Objective

Produce an implementation-ready 90:10 plan that prevents recurrence of the observed
Runtime/render-path failure while retaining the existing Runtime, CAS, managed
upload, fenced settlement, launcher ownership, and digest-addressed render cache.

The first useful outcome is a normal supported command that, despite an unrelated
global current-project value, resolves the latest successful render in the explicitly
focused project/timeline, verifies and materializes the managed object with its real
`.mp4` filename, and asks the OS to open exactly that path.

## Required scope

- Keep health and ordinary doctor responsive; move deep integrity/CAS work offline.
- Activate a verified recovered realm through normal launcher ownership/discovery.
- Consolidate CLI, SDK, and UI render opening around explicit project/timeline scope.
- Preserve output port, object identity, filename, and media type as distinct fields.
- Materialize managed objects by verified digest/size before opening them.
- Add the exact Minkhole-vs-Astrid-Intro regression and focused negative tests.

## Non-goals

- Rebuild the recovered realm merely to rename its directory.
- Add a second render registry, compatibility shims, or legacy paths.
- Add online audit workers, dashboards, cache registries, or playback automation.
- Fold generation/variant domain expansion into this repair.
- Claim OS playback from merely issuing an `open` request.

## Source

- Repository: `<workspace>/Astrid`
- Branch: `main`
- Setup HEAD: `82d09bb91c8a4621695c1d8b6966652cad941ef4`
- The working tree is heavily dirty; existing tracked and untracked work is user-owned
  and authoritative planning context. See source-state.md (original source reference: `source-state.md`).

## Stop condition

Planning completes when the package has a coherent implementation order, explicit
dependencies, testable criteria, estimates, known uncertainty, and no unresolved
product-direction decision. Delivery is a separate authorized run.
