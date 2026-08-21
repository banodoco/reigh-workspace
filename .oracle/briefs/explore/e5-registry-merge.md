# Explore E5: timeline registry-merge semantics (the subtlest seam)

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

Doc 27 requires: task completion performs an "internal asset-registry merge against the current timeline head" so a completed generation becomes visible in the editor document WITHOUT clobbering concurrent editor saves (editor holds whole-document CAS via `expected_version`). Today `TimelineRepository` (astrid/packs/timeline/repository.py) has whole-replace save (:246–248/:315–328) — no partial merge. Task: read the timeline save/load/CAS internals and the bridge save route; then specify concretely what an internal merge command should be: which event kind (existing `timeline.saved`? new registered kind? is a new kind legal per registry freeze?), what it mutates (asset_registry_json only? document_json too?), how it interacts with `config_version`/head advance, and how a concurrent editor save during completion resolves (last-write-wins on head? conflict?). Identify the minimal design that preserves one-CAS-version semantics and cannot silently lose an editor edit.

Report ranked findings (<300 words) with file:line evidence and ONE recommended merge design.
