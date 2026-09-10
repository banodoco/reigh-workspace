> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Implementation criteria

- **C1 — Responsive serving:** health and ordinary doctor do not perform unbounded
  database/CAS hashing or hold the serving SQLite mutex for deep audit work.
- **C2 — Offline audit:** deep integrity/CAS verification runs explicitly against a
  stopped realm or consistent snapshot and cannot starve normal Runtime requests.
- **C3 — Exclusive ownership:** recovery activation stops/conflicts with any prior
  owner and finishes with a Runtime accepted by normal launcher discovery.
- **C4 — Explicit selection:** render resolution receives project ID and optional
  timeline ID explicitly; it never widens scope through unrelated global selection.
- **C5 — Atomic publication:** attempt-local output becomes a managed object only via
  upload and fenced Runtime settlement.
- **C6 — Distinct metadata:** output port, object reference/digest, actual filename,
  and media type survive publication as distinct values.
- **C7 — Verified materialization:** only a downloaded object with matching SHA-256
  and byte size is atomically exposed at the named digest-cache path.
- **C8 — Truthful opening:** the opener receives that exact materialized `.mp4` path;
  product output distinguishes “open requested” from proven playback.
- **C9 — Decisive regression:** with Astrid Intro globally selected and Minkhole
  focused, the supported entry point selects the known Minkhole run/digest and never
  opens the Intro object or raw CAS path.
- **C10 — Simplification:** direct DB/CAS user-facing fallbacks and transparent
  adoption of manually launched runtimes are absent from the supported flow.
