> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Runtime render path: 90:10 simplification plan

## Decision

The storage architecture is sound. The failure crossed too many weak integration and
operational boundaries:

`recovery activation → runtime discovery → scoped selection → output identity → materialization → OS open`

Keep Runtime/CAS/settlement. Remove alternate routes around them. There should be one
supported opening flow, one launcher-owned Runtime, and one explicit offline deep
audit path.

## Incident and root causes

1. Deep doctor hashed roughly 841 MB of CAS while holding the daemon's single SQLite
   mutex, making health and ordinary requests appear unavailable.
2. A recovered realm was started manually and responded directly, but normal launcher
   discovery rejected it because ownership/discovery identity did not match.
3. The unavailable supported resolver led to direct database and raw-CAS inspection.
4. Global current-project state pointed to Astrid Intro while the intended focus was
   Matrix — Into the Minkhole. “Latest” was resolved inside the wrong scope.
5. An extensionless CAS object was passed to QuickTime. The underlying H.264/AAC MP4
   was valid, but the user-facing path had neither the correct name nor extension.
6. An existing QuickTime window was mistaken for proof that the requested document
   opened.
7. Historical objects have generic names such as `video`, while producing task
   provenance still contains real names such as `minkhole-review-v13.mp4`. The exact
   historical flattening boundary remains the main implementation uncertainty.

The decisive known Minkhole artifact is:

- Project: `Matrix — Into the Minkhole`
- Project ID: `7f362daea1f048969980ef23f0cd46e6`
- Run: `e3aaf311c17b450198d1c2d6f1582887`
- Digest: `sha256:4774f5bb04cf4e25e6b514f372517e6b2ff05b7e1d20aa1014ffe6d28c53477c`
- Filename: `minkhole-review-v13.mp4`
- Size: `11,288,161` bytes
- Media: valid 1920×1080 H.264/AAC MP4, about 29.589 seconds

## Canonical model

Durable Runtime storage is immutable, internal CAS. User-facing materialization is:

`~/Library/Caches/Astrid/renders/<full-digest>/<filename>.mp4`

The canonical flow is:

```text
explicit project/timeline
  → Runtime render task
  → attempt-local staging
  → managed upload
  → fenced settlement
  → resolve settled output in the same scope
  → verify and atomically materialize named .mp4
  → pass exactly that path to the OS opener
```

The recovery directory and raw CAS layout are never user-facing render locations.

## Workstream 1 — make diagnostics non-blocking

- Separate cheap liveness/configuration checks from deep realm/CAS verification.
- Run deep verification only against a stopped realm or consistent snapshot.
- Ensure hashing occurs without monopolizing the serving SQLite mutex.
- Prove concurrent health, project reads, and a representative normal write remain
  responsive while the deep-audit path is exercised safely.

## Workstream 2 — complete recovery activation

- Provide one small operator operation that verifies a candidate, preserves original
  and backup, stops or rejects a prior owner, updates existing launcher/catalog state,
  starts the normal Runtime, and verifies discovery.
- Test owner conflict, interruption before/after activation, restart, stale discovery,
  and normal CLI access.
- Preserve the current recovered realm; rebuilding it is not justified. Promotion is
  complete only after normal discovery and successful expected-artifact retrieval.

## Workstream 3 — consolidate render opening

- Use one SDK operation conceptually equivalent to
  `open_render(project_id, timeline_id=None)`.
- UI supplies focused IDs. CLI resolves selected context once and passes explicit IDs.
- “Latest” means newest successful `rendering.render` in exactly that scope.
- Missing/conflicting timeline provenance fails clearly instead of widening search.
- CLI, SDK, and UI share the same resolver/materializer; delete user-facing direct
  database and raw-CAS fallback routes.

## Workstream 4 — preserve output identity

- Trace manifest → host harvest → upload → stored object → settled output.
- Preserve independently: port `video`, managed object reference, actual filename,
  and media type.
- For historical objects named only `video`, use producing task `output_name` as the
  bounded provenance fallback. Do not build a migration framework or broad backfill.

## Workstream 5 — verify materialization and opening

- Accept only a managed object reference, never a storage path.
- Download to a temporary file inside the digest directory, verify digest and size,
  and atomically publish the actual filename.
- Reuse cache only after equivalent verification.
- Return and pass the exact path to the opener. Report “open requested” unless stronger
  target-document evidence exists.

## Decisive end-to-end test

1. Global current project is Astrid Intro.
2. Focused context is Minkhole and its canonical timeline.
3. Both an unrelated newer Intro render and the successful Minkhole run exist.
4. Historical Minkhole object metadata says `original_name='video'` while task
   provenance says `minkhole-review-v13.mp4`.
5. Invoke the normal supported open entry point.
6. Assert run `e3aaf311c17b450198d1c2d6f1582887` and the known Minkhole digest.
7. Assert verified materialization at
   `~/Library/Caches/Astrid/renders/4774f5bb04cf4e25e6b514f372517e6b2ff05b7e1d20aa1014ffe6d28c53477c/minkhole-review-v13.mp4`.
8. Assert the opener receives exactly that path, never Intro or raw CAS.

Focused negative tests cover conflicting scope, absent scoped provenance, digest or
size mismatch, invalid filename, owner conflict, and interrupted recovery activation.

## Simplicity boundary

Keep: Runtime authority, immutable CAS, attempt staging, managed upload, fenced
settlement, explicit timeline scope, verified digest cache, launcher ownership.

Remove/defer: direct DB/CAS fallbacks, transparent manual-runtime adoption, online
deep audits, background audit services, dashboards, cache registries, historical
backfill machinery, permanent playback automation, and generation/variant expansion.

## Estimate and uncertainty

Estimated focused engineering effort: **5–8 days**, assuming existing launcher and
materialization seams can be reused. Likely split: diagnostics 1–1.5 days, recovery
activation 1–2 days, scoped opening/metadata 2–3 days, integrated regression and
cleanup 1–1.5 days. Agent elapsed time may be shorter through parallel investigation
and implementation, but executable integration remains the pacing constraint.

Main uncertainty: the precise boundary that flattened historical filenames and how
much of recovery activation lives in the Runtime package outside this checkout. A
bounded read-only trace should settle both before source mutation; neither warrants a
new subsystem.
