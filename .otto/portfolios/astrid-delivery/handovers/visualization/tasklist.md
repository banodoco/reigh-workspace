> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Plan 1 tasklist

| ID | Outcome / dependency | Route | Acceptance evidence |
|---|---|---|---|
| V1-01 | Freeze parser-backed CLI and remove unsupported examples (`Astrid/astrid/packs/timeline/cli.py:645-710`) | normal | every documented command parses |
| V1-02 | Extend render-pinned decoded clock/tail/identity (`sdk/timeline_filmstrip.py:197-269`; `filmstrip_execution.py:19-89,119-143`) | normal; after V1-01 | wrong digest, stale render, tail/final-frame evidence |
| V1-03 | Full-duration bounded overview and coverage (`filmstrip_cards.py:71-113,200-285`) | normal; after V1-02 | hundreds-of-cuts, first/last/tail, page/coverage evidence |
| V1-04 | Independent range/density/resolution/navigation (`filmstrip_options.py:30-72`) | normal; after V1-03 | real-flag detail evidence; no fabricated parent |
| V1-05 | Spoken-only metadata independent of shot presence (`sdk/timeline_filmstrip.py:54-62,141-155`) | normal; after V1-02 | prompt/transcript exclusion and no-shot spoken evidence |
| V1-06 | Existing host/CAS manifest identity and disposable-cache documentation | normal; after V1-02 | cache rehydration and structure/render distinction |
| UX-01 | Baseline: fresh Luna actors attempt authored-structure, rendered-filmstrip and cross-view briefs on the local synthetic fixture | normal; after V1-06 | frozen images viewed, traces, artifacts, manifest IDs; deterministic gates |
| UX-02 | Astra UX round 1 assesses friction and evidence from baseline traces; no actor narrative grading | normal; after UX-01 | one capped Astra invocation; findings cite frozen evidence |
| UX-03 | Luna high implements only precise demonstrated UX fixes; Sol only if a hard kernel remains after decomposition | normal, escalate only with justification; after UX-02 | affected deterministic gates and UX evidence improve |
| UX-04 | Astra UX round 2 verifies affected UX; Luna high applies the second precise fix pass; final fresh Luna actors run the held-out fast-cut/unknown-interval task | normal; after UX-03 | one capped Astra invocation; second-pass delta plus final held-out evidence; missing image capture is undetermined |
