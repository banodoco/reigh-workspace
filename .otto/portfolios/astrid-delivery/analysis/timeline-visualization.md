> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Timeline visualization fixes — sequencing and boundary research

Research date: 2026-09-10. This report is read-only research; no project run,
test, database, service, or implementation change was launched.

## 1. Purpose and concrete user impact

Plan 1 makes `timelines visualize --view filmstrip` a trustworthy Render Review
surface. The intended before/after is concrete:

| Before / failure mode | Intended after / user impact |
|---|---|
| A local path or “latest” can be mistaken for the requested render. | The review is pinned to `(project/timeline, render run, video digest, manifest/input identity)` and rejects wrong or stale bytes. |
| Authored duration can stop sampling before a rendered hold/tail. | Decoded video duration controls the review window; the tail reaches EOF and is explicitly unmapped unless pixel evidence proves blackness. |
| Prompts or unmarked transcript metadata can appear as captions. | Only allowlisted spoken metadata is shown; missing metadata is reported, never turned into inferred silence. |
| Page one/contact sheets can imply complete coverage or every fast cut. | A bounded full-duration overview exposes mandatory first/last/tail-transition evidence, selected coverage, and drill-down/index limits honestly. |
| Range, density, spatial resolution, and navigation can be conflated. | Each request value is independent and recorded; navigation pins the exact render and does not invent a parent for a stateless range. |
| Structure facts and rendered facts are answered from one surface. | Authored structure, rendered frames, and cross-view clock/identity mismatches remain distinct and inspectable. |

The authoritative North Star requires exact managed-render identity, decoded full
duration, spoken-only metadata, bounded overview, independent controls, honest
navigation, and reuse of current admission/manifests/CAS/host/cache paths
([northstar.md](../handovers/visualization/northstar.md);
[plan](../handovers/visualization/plan.md)).

## 2. Current status, custody, and evidence

The run package is `READY_FOR_DELIVERY_SETUP_ONLY`; no implementation, product
test, model UX run, deployment, merge, or publication has launched
([status](../handovers/visualization/status.md)). Its `run.yaml` remains
`mode: planning_only` with no review stages and two remaining calls in the
shared central oracle budget; this is authority/configuration, not product-pass
evidence ([run.yaml](../handovers/visualization/run.yaml)).

Source custody is the dirty `Astrid` checkout, branch `main`, HEAD
`82d09bb91c8a4621695c1d8b6966652cad941ef4`, matching `origin/main` at the
captured snapshot. The selected 31-path runtime/visualization delta is
reproducible from `source/selected-dirty.patch` (SHA-256
`e61029dd0375577175224df7de3389a407b79d4d2ea40d2da4f5e744f38c59d1`), but
unrelated tracked and untracked dirt remains in the checkout
([source-provenance](../handovers/visualization/source-provenance.md);
source-state (original source reference: `<workspace>/Astrid/.otto/runs/timeline-visualization-fixes-20260910/source-state.md:1-8`)).
Do not treat the selected patch as a clean integrated branch or as proof that
the changed behavior passed tests.

Observed current-tree facts, distinguished from planned work:

* The dirty delta adds decoded-frame probing and render alignment in
  `filmstrip_execution.py:19-89,119-143`, including digest verification before
  extraction (`:127-142`). This is present source behavior, but no run evidence
  says it has been executed.
* The dirty delta adds spoken-binding filtering, frozen occurrence identity, and
  frozen-text digest/size verification in `sdk/timeline_filmstrip.py:35-62,98-155`.
  Existing unit tests cover prompt/unmarked-transcript exclusion and selected
  occurrence identity (test_timeline_filmstrip.py (original source reference: `<workspace>/Astrid/tests/sdk/test_timeline_filmstrip.py:46-115`)),
  but setup status says tests have not run.
* Runtime-backed timeline selection is present in `select.py:223-318` and tests
  cover project/default/slug selection, archived-row exclusion, public-client
  readers, and malformed page rejection
  (test_timeline_visualize_select.py (original source reference: `<workspace>/Astrid/tests/core/timeline/test_timeline_visualize_select.py:54-155`)).
* Public CLI and SDK preflight are present: `_cmd_visualize` normalizes format
  arguments and waits for the admitted task
  (`astrid/packs/timeline/cli.py:301-341`), while `_validate_timeline_visualize_inputs`
  rejects caller-supplied authority, path output, incompatible view controls,
  and malformed filmstrip values (`astrid/sdk/invocation.py:450-528`).
* The checked-in card planner still samples interval/cut/clip/shot cards with a
  2,000-card limit (`filmstrip_cards.py:35-154`); no dirty delta changes this
  file or `filmstrip_options.py`. Therefore the planned adaptive bounded
  overview and explicit independent spatial-resolution contract remain
  unproven/likely outstanding.

The future UX fixture is explicitly only a specification: no five-minute actual
video, dual authored/rendered fixture, hidden ground truth, Astrid Sisypy
adapter, actor, or image capture exists
([test-project](../handovers/visualization/test-project.md)).

## 3. Scope, boundaries, owned contracts, invariants

In scope: parser-backed filmstrip CLI; managed render selection and freshness;
render digest and frozen manifest identity; decoded frame count/tail; spoken-only
metadata; bounded overview/coverage; independent range/density/resolution;
manifest/CAS entrypoint locators; generic host publication; disposable cache
rehydration documentation; and the bounded authored/rendered/cross-view UX loop
([plan](../handovers/visualization/plan.md)).

Out of scope: a new storage/lifecycle framework, review-specific events or
database, ASR/provider calls on viewer open, accepting arbitrary caller paths,
fabricating mutation receipts, rewriting authored timeline files, cloud/GPU
execution, deployment/publication, and Plan 2 lifecycle migration. Plan 2's
E2-06 exclusively integrates a completed Plan 1 visualizer after Plan 2's
generic lifecycle work ([pointer](../handovers/visualization/lifecycle-pointer.md)).

Owned invariants:

1. Render authority is exact run/task/video/manifest identity; path and filename
   are locators only. `prepare_filmstrip` rejects caller `rendered_video`, checks
   successful render capability/state, project ownership, and exactly one video
   output (`sdk/timeline_filmstrip.py:197-265`).
2. Latest is a scoped freshness query, not global newest: current timeline
   config versions and frozen script heads/hashes are compared before selection
   (`sdk/timeline_filmstrip.py:243-255`). Explicit old-run inspection bypasses
   this latest-freshness check but retains frozen identity.
3. Frozen clips/scripts/tracks are annotations, not permission to infer shot
   identity from filenames/current documents. Explicit admitted occurrence IDs
   win; ambiguous legacy timing joins retain candidates rather than overwrite
   ownership (`sdk/timeline_filmstrip.py:98-140`).
4. Spoken metadata is an allowlist (`voiceover_script`, or transcript explicitly
   marked `spoken`); prompt and unmarked transcript bindings are excluded
   (`sdk/timeline_filmstrip.py:54-62,141-155`). Script segments are not word
   alignment; no script is not silence.
5. Rendered frame clock and authored clock remain separate. Current alignment
   records rendered/authored frame counts (`filmstrip_execution.py:47-64`), but
   the tail must not be called black without pixel evidence: current code's
   `asset: black_frame`/`__rendered_tail_black__` (`:64-83`) is a material
   acceptance gap, not an accepted invariant.
6. Viewer cache is digest-scoped, project-namespaced, extracted through a hidden
   sibling staging directory, verified member-by-member, and atomically
   published (`sdk/invocation.py:1170-1183,1200-1305`). Runtime objects remain
   durable authority; cache paths never establish identity.

## 4. How it runs

The public entrypoint is `python3 -m astrid timelines visualize ...`; CLI
`_cmd_visualize` constructs one SDK input map and calls
`rendering.timeline_visualize` synchronously with `wait=True`
(`astrid/packs/timeline/cli.py:301-341`). The SDK preflight validates parser
grammar and ownership, then for filmstrip calls `prepare_filmstrip`
(`astrid/sdk/invocation.py:450-528`).

`prepare_filmstrip` reads the workspace runtime through the client: project,
timeline list, successful project runs/tasks, frozen authority envelope, current
timeline/script heads for latest, and project-owned media rows
(`astrid/sdk/timeline_filmstrip.py:207-265`). It builds a frozen snapshot from
the admitted envelope, including rational FPS, normalized clips/tracks,
occurrences, verified text objects, and optional admitted speech annotations
(`sdk/timeline_filmstrip.py:65-194`). SDK then injects a private JSON authority
and digest/object-id input into the task request; public callers cannot supply
that authority (`astrid/sdk/invocation.py:1496-1511,1762-1781`).

The generic pack host claims the task, materializes the managed video, and
invokes `filmstrip_execution.execute_filmstrip` at
`astrid/packs/rendering/executors/timeline_visualize/run.py:1658-1664`. The
executor verifies file digest against both authority and snapshot, probes
decoded video frame count with `ffprobe`, aligns the copied snapshot to the
render clock, computes audio analysis from a digest/settings cache, and builds
cards/contact sheets/HTML/Markdown/JSON (`filmstrip_execution.py:19-59,119-175`;
`filmstrip_cards.py:163-285`).

Outputs are a nested `filmstrip-view/manifest.json`, self-contained
`filmstrip-bundle.zip`, and host-level `manifest.json` receipt. The nested
manifest covers every pack member and entrypoints; the host receipt publishes
the bundle as the primary result (`filmstrip_execution.py:174-240`). Generic
host harvest/upload/settlement then publishes typed managed objects; no
review-specific event is required (`generic_host.py:2286-2349,2935-3024`).

On successful synchronous SDK return, `_materialize_filmstrip_outputs` reads the
bundle by managed digest, validates ZIP safety, manifest membership, hashes,
sizes, frame index, media/audio sidecar locators, then atomically replaces the
project cache root (`astrid/sdk/invocation.py:1186-1305`). Failure removes only
the temporary staging directory; an already published cache remains usable
until the final replacement point (`:1286-1309`).

Failure boundaries are intentionally fail-closed: no managed admission for a
path-only video, wrong digest, stale latest render, foreign object, invalid
manifest, unsafe ZIP path, missing member, malformed card range, or unsupported
sampling input. The current executor catches audio-analysis errors and emits an
explicit `analysis_error` sidecar while retaining frame usability
(`filmstrip_execution.py:143-167`); this is not permission to invent waveform
or speech evidence.

## 5. Touch map

| Exact file / symbol | Intended change | Consumer | Overlap / status |
|---|---|---|---|
| `astrid/packs/timeline/cli.py:645-711`, `_cmd_visualize:301-341` | Freeze parser-backed grammar; remove/document unsupported examples; keep current real flags | Public CLI | Same CLI surface as runtime render reliability RRP-04; semantic overlap, likely same-file coordination. |
| `astrid/sdk/timeline_filmstrip.py:54-62,65-194,197-270` | Exact render selection, stale/latest checks, frozen identity, spoken-only projection | SDK preflight and executor | Plan 1-owned; render-path project also has scoped resolver concerns, but its task is opening renders, not filmstrip annotations. |
| `filmstrip_execution.py:19-89,119-240` | Decoded duration, tail labeling, digest gate, audio/cache, result receipts | Generic pack host | Plan 1-owned; Plan 2 later consumes its result members/lifecycle metadata. |
| `filmstrip_cards.py:35-154,200-285` | Bounded full-duration overview, mandatory boundaries, honest coverage, adaptive sampling | Executor and offline viewer | Explicit Plan 1 scope; currently no dirty change. |
| `filmstrip_options.py:30-78` | Independent range/density/resolution values and parser constraints | SDK and executor | Explicit Plan 1 scope; currently no dirty change; CLI parser must be settled first. |
| `inspector_navigation.py:19-76,79-170` | Render-scoped targets, exact frame/range commands, distinct audio/track lanes | HTML/JSON viewer | Semantic dependency on coverage and duration; no new event/storage contract. |
| `astrid/sdk/invocation.py:450-710` | Preflight ownership/selector validation and runtime authority injection | SDK task admission | Same-file semantic overlap with runtime-database/render-path projects; serialize changes to shared admission helpers. |
| `astrid/sdk/invocation.py:1170-1309,1989-1995` | Digest cache rehydration and published output paths | SDK result surface | Plan 1 cache contract; Plan 2 E2-06 later migrates lifecycle, not current implementation. |
| `astrid/core/execution/generic_host.py:2286-2349,2935-3024` | Reuse typed output harvest/upload/settlement; no review event | Runtime host | Shared semantic boundary with runtime database clean break T3/T6 and render reliability RRP-05/06; avoid parallel rewrites. |
| `astrid/core/timeline/expand_shots.py`, `banodoco_schema.py`, `sdk/shot_grouping.py` | Admit explicit occurrence identity into render snapshot | Render admission and filmstrip labels | Plan 1/render bridge dependency; source patch includes these paths. |
| `tests/sdk/test_timeline_filmstrip.py:46-155` | Identity, stale, spoken metadata, occurrence tests | CI | Existing focused evidence definitions; no setup execution. |
| `tests/packs/rendering/test_timeline_filmstrip_cards.py:18-132` | Sampling/frame/card behavior | CI | Existing interval/cut tests; missing decoded-tail/overview/resolution acceptance. |
| `tests/sdk/test_timeline_filmstrip_invocation.py:12-157` | Admission/cache/ZIP safety | CI | Existing focused tests; no setup execution. |
| Future fixture under `tests/fixtures` plus Sisypy adapter | Five-minute dual-view video, hidden truth, frozen images/traces | UX loop | Explicitly missing; cannot be inferred from current PNG/storyboard fixtures. |

## 6. Dependencies, parallel chunks, serialization

Task-level order in the authoritative list is V1-01 → V1-02 → V1-03 → V1-04,
with V1-05 after V1-02 and V1-06 after V1-02; UX-01 waits for V1-06 and all
UX rounds follow the baseline/fix/replay sequence
([tasklist](../handovers/visualization/tasklist.md)).
That order is sensible for semantic reasons, not merely file collisions:

* V1-01 must settle valid public names before card actions/resolution commands
  are generated.
* V1-02 establishes the render clock, digest, and occurrence identity consumed
  by overview cards, spoken projection, and cross-view navigation.
* V1-03 can then define bounded coverage against the actual decoded duration.
  V1-04 must record range/density/resolution without changing V1-03's identity
  or coverage semantics.
* V1-05 is mostly parallel after V1-02 if it changes only speech allowlists and
  tests; it must serialize with V1-02 where both edit `timeline_filmstrip.py`.
* V1-06 is documentation/receipt/cache proof and can parallelize with V1-03/04
  once authority shape is stable, but its result envelope must not race host
  receipt changes.

Safe parallel chunks after V1-02's contract is frozen: (a) adaptive card
selection plus card tests; (b) option normalization plus parser tests; (c)
spoken metadata tests/projection; (d) cache/publication documentation and
receipt tests. Same-file collisions exist in `sdk/invocation.py`,
`timeline_filmstrip.py`, `cli.py`, and `filmstrip_execution.py`; use one serial
owner per file even where work is semantically parallel.

Integration prerequisites: cleanly reconcile the selected dirty patch against
HEAD; settle tail status (`unmapped` vs proven black); settle whether resolution
is a true request value or only a bounded presentation setting; then run the
focused deterministic suite. Only after those gates should the missing UX
fixture/adapter be authored and baseline actors launched. Plan 2 E2-06 waits
for Plan 1 acceptance and must not be merged into this run's control root.

Cross-project overlaps:

* Runtime database clean break T3/T6 consolidates host admission/receipts and
  generated clients. Plan 1 should consume that boundary and avoid adding a
  filmstrip event family; shared host/invocation edits require an integration
  gate.
* Runtime render path RRP-04–RRP-06 also touches explicit project/timeline
  render resolution, materialization, and output identity. The projects can
  research in parallel, but resolver/materializer ownership must be assigned
  before implementation; do not let “open render” fallback logic reintroduce
  path authority into filmstrip.
* Ephemeral lifecycle E2-01–E2-05 can implement against a synthetic producer;
  E2-06 is downstream only and must consume Plan 1's settled manifest/member
  contract ([dependency tasklist](../handovers/ephemeral/tasklist.md)).

## 7. Validation and acceptance gates

Blocking deterministic gates, before UX claims:

1. Every documented command parses against current CLI/help; no unsupported
   `review render`, `timeline view`, `--preset`, or `--resolution` promise.
2. Render A remains selected after B and timeline/script edits; wrong digest,
   foreign ownership, stale latest, and path-only inputs fail.
3. Actual decoded duration reaches final frame. Any excess tail is marked
   unmapped unless a test records pixel evidence for blackness; the current
   `__rendered_tail_black__` label alone cannot pass.
4. Prompt/unmarked transcript exclusion, shotless spoken metadata, frozen text
   digest, and no-inferred-silence behavior pass.
5. Hundreds-of-cuts fixture produces bounded full-duration overview, mandatory
   first/last/tail-transition cards, explicit selected coverage, and valid
   range/detail commands. It must not claim every boundary was sampled.
6. Range, density, and spatial resolution appear as separate request/result
   fields; stateless ranges have no fabricated parent; structure and render
   clocks/identities stay distinct.
7. Bundle/cache extraction verifies all members and atomically publishes only
   after digest/size/path checks; deletion/retry leaves prior usable cache on
   failed verification.

Existing tests are useful definitions, not passing evidence: card tests cover
fractional FPS, cut neighbors, filters, bounds, static caption limits, and
repeated occurrences (test_timeline_filmstrip_cards.py (original source reference: `<workspace>/Astrid/tests/packs/rendering/test_timeline_filmstrip_cards.py:18-132`));
SDK tests cover identity/spoken/stale cases and cache/ZIP safety
(test_timeline_filmstrip_invocation.py (original source reference: `<workspace>/Astrid/tests/sdk/test_timeline_filmstrip_invocation.py:12-157`)).
Still required are real ffprobe tail fixtures, pixel-verified transition logic,
bounded/adaptive coverage tests, independent-resolution tests, and the complete
five-minute actual-video UX fixture.

UX gates are evidence gates, not narrative grades: fresh Luna baseline actors;
one capped Astra friction assessment over frozen traces/images; precise Luna fix
pass; fresh replay; one capped Astra verification; precise second fix; final
fresh held-out fast-cut/unknown-interval check. Missing image viewing/capture is
`undetermined`, never pass
([test-project](../handovers/visualization/test-project.md)).

## 8. Recommendations to Astra and unresolved checks

1. Treat the current dirty patch as partial implementation context only. Require
   a clean custody reconciliation and focused tests before estimating delivery.
2. Make the tail decision explicit: rename current synthetic black-tail marker
   to an unmapped rendered region, or add a deterministic pixel-evidence check
   with a recorded threshold/method. Do not inherit the current label by prose.
3. Resolve the overview contract before UX work: define card budget, mandatory
   first/last/tail cards, interior adaptive policy, and machine-readable selected
   coverage. Keep exhaustive boundaries as index/drill-down data.
4. Decide whether spatial resolution is an executor input, a presentation-only
   option, or intentionally deferred. Parser, option normalization, manifest,
   and cache identity must agree; no speculative `--resolution` documentation.
5. Assign ownership for shared `sdk/invocation.py` and generic-host changes with
   runtime-database and runtime-render projects. Semantic dependencies are more
   dangerous than same-file conflicts: a later resolver/materializer patch can
   silently undermine exact filmstrip identity.
6. Author the fixture before claiming UX readiness: actual decodable video,
   two render byte versions, dual authored structure, shotless spoken segment,
   prompt/transcript traps, visible tail, rapid cuts, hidden truth, and confirmed
   image capture. Existing PNG/storyboard fixtures are not substitutes.
7. Keep Plan 2 separate. Its lifecycle contract may constrain eventual result
   metadata, but E2-06 is downstream and must not widen Plan 1 scope.

Specific pre-execution checks: rehash selected patch and manifest; compare
`docs/design/timeline-visualization-fixes-plan.md` against the portable copy;
inspect current parser help; identify all callers of `_materialize_filmstrip_outputs`
and `execute_filmstrip`; confirm generated-client page-pair behavior; and verify
the receiving environment's Python/FFmpeg/Sisypy/native-agent capabilities.

### Conclusion

Plan 1 has a coherent boundary and a useful partial dirty implementation, but
it is not product-complete or evidenced. Sequence parser/identity/clock first,
then overview/options/caption work, then cache/host integration, and only then
the bounded UX loop. The tail-black labeling, adaptive overview, independent
resolution, and missing real fixture are the principal blockers.
