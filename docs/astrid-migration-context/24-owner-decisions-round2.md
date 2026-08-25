# 24 — Owner Decisions Round 2 (realtime, shot abstraction, render, local compute)

Status: **RATIFIED 2026-08-21** — owner answers to doc 23 §7, plus follow-up considerations. Supersedes: doc 20 §19.10 (outbound providers — see Q3), doc 17's `shot_generation_items` (see Q1), doc 22 Phases 6–7 (already superseded by doc 23 §6.1 — fresh start).

## The decisions

| # | Question (doc 23 §7) | Owner decision | Impact |
|---|---|---|---|
| Q1 | Placement authority | **Document-native.** Shot groups, pools, timing, boundaries live in the **same timeline document** as the video editor (one structure, one editor, focused shot mode). | `shot_generation_items` removed from doc 17; placement RPC/trigger machinery deleted, not ported. Doc 18 R12 + doc 22 Phase 1 amended. **The document itself is stored in SQLite** — `timelines.document_json` + `asset_registry_json` JSON columns, CAS-versioned against the stream head (doc 04/05/09); "document-native" means un-normalized JSON rows in the existing SQLite `timelines` table, not a second store. |
| Q2 | Group duplicate | **Deep copy** — duplicate copies structure + media refs AND enqueues/copies the generated final-video assets. | Duplicate is fully independent; disk grows with each copy (content-addressed dedupe helps identical bytes only); duplicate's lineage (`derived_from`/`based_on`) must record the source group. Document command, not DB rows. |
| Q3 | Provider scope | **Everything runs on the machine.** Fully local compute for v1 — no outbound generation providers. | **Supersedes doc 20 §19.10** (keep Fal/Wavespeed in local API orchestrator). Capability families with no installed local model are hidden/disabled with a setup prompt. New P0: model acquisition (weights download/verify/update) + local availability matrix replaces the provider-secrets P0. |
| Q4 | Export path | **Render via Astrid, display in browser.** | Confirmed reigh-app already bundles Remotion (`remotion@4.0.434`, `@remotion/player`, `@remotion/web-renderer` in `reigh-app/package.json`) — browser-side render today. Astrid already has `rendering.render` / `rendering.timeline_visualize` capabilities ("renders timeline to video through Remotion with GPU-accelerated rendering", `Astrid/astrid/core/contracts/...` + `output_result_exemptions.json`). Target: render runs as an Astrid task on the same machine → MP4 into managed media → served via bridge Range/ETag → browser `<video>` displays it. One render pipeline, task-tracked progress (fits the 2s polling design), outputs in the managed tree. Caveats: local Remotion needs node/ffmpeg; editor document → Remotion composition mapping needs a compatibility layer (verify `timeline_visualize` covers the Reigh document shape); browser remotion preview path can remain secondary. |
| Q5 | Media policy | **Copy for now** — always managed copy; no link-in-place mode in v1. | Simplest; no broken-link failure mode. Opt-in link mode deferred. |
| Q6 | Freshness bar | **~2s is good enough; SSE deferred.** | Polling design ratified as-is (doc 23 §2). Escalation path unchanged (`GET /events?after_seq=` cursor first, SSE only after measured evidence). |

## Remaining considerations (owner asked: "anything else?")

Prioritized, beyond doc 23 §4's P0 list (local boot, task journey, media lifecycle, render/export — now simplified by Q3/Q4/Q5):

1. **P0 — Model acquisition UX (new, from Q3).** Fully-local means fresh machines need model weights (Wan etc.), ComfyUI/VibeComfy nodes, and verification. Needs: download/verify/update flow, "missing model → setup prompt" UX, disk-space preflight. This is the direct successor to the provider-secrets item.
2. **P0 — Thumbnails (existing gap, surfaced by gallery-scale question).** The design dropped `thumbnail_url` (doc 17); with fully-local compute, thumbnail generation becomes a cheap local task/capability. A 1,000-generation gallery needs it for UI sanity. Decide in Phase 1 scope.
3. **P1 — Document size bounds (new, from Q1).** Shot groups + poolGenerationIds grow the timeline document; canonical JSON bounds are 1 MiB in / 4 MiB out (doc 18 §2.2). A large project's document could approach this. Watch in Phase 2 vertical slice; defer paging/laziness unless measured.
4. **P1 — `shots`/`shot_items` pack disposition.** Astrid's shots pack v1 exists but is no longer the Reigh authority (doc 23 §3). Decide: keep dormant for future consumers, or note as unused. Don't mirror document groups into it.
5. **P1 — Append-service equivalence verification.** The append service source is not in the workspace (doc 06 gaps; doc 21 P0). Doc 23 asserts the bridge replaces its semantics — verify by behavior in Phase 0/2, not assume.
6. **P1 — Deep-copy disk policy.** Duplicating final videos doubles bytes; content-addressed dedupe only collapses identical bytes. Confirm per-project disk envelope in the soak/scale tests (doc 21 P1.11).
7. **P2 — Phase 0 evidence scope shift.** With fresh-start ratified, some deployed-reality evidence (4 missing migrations, slot DDL) is no longer migration-critical — but claim/completion *behavior* evidence still matters for porting semantics faithfully (worker claim fields, completion side effects). Keep, re-prioritize.

## Spec amendments triggered (pending execution)

- **doc 17**: remove `shot_generation_items` + placement commands/events; keep `generations`/`generation_variants` + primary index + atomic completion; add note that placement is document-native.
- **doc 18**: R11/R12 content reads change (shot groups served via timeline document; gallery stays relational); render route/task for export; drop shot-placement routes.
- **doc 22**: Phase 1 scope (no relational placement), Phase 2 vertical slice adds render + model acquisition, Phase 5 adds local render/export + model setup; capability matrix = local availability matrix (Q3).
- **doc 20**: §19.10 marked superseded by doc 24 Q3.
