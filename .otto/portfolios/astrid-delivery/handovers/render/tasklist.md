> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Tasklist

| ID | Outcome and dependency | Route | Acceptance evidence |
|---|---|---|---|
| RRP-01 | Trace deep-doctor locking, launcher activation ownership, render resolver callers, and filename propagation; identify exact mutation surfaces. | normal | Source/line map and bounded conclusions for both named uncertainties. |
| RRP-02 | Split cheap serving diagnostics from explicit offline deep audit. Depends on RRP-01. | normal | C1–C2 tests: ordinary requests remain responsive; offline audit detects corruption. |
| RRP-03 | Add one verified launcher-owned recovery activation path. Depends on RRP-01. | normal | C3 tests for conflict, interruption, restart, discovery, and normal CLI access. |
| RRP-04 | Consolidate explicit project/timeline render resolution across SDK/CLI/UI and remove user-facing DB/CAS fallback. Depends on RRP-01. | normal | C4, C10 focused tests, including wrong-global-project fixture. |
| RRP-05 | Preserve filename separately across publication; add bounded task-provenance fallback for historical objects. Depends on RRP-01. | normal | C5–C6 publication and historical-object tests. |
| RRP-06 | Harden verified atomic materialization and truthful OS-open reporting. Depends on RRP-04/RRP-05. | normal | C7–C8 digest, size, filename, cache-reuse, and opener-path tests. |
| RRP-07 | Run the decisive Minkhole end-to-end regression and broad affected suite; remove superseded fallback code/docs. Depends on RRP-02–RRP-06. | normal | C9 exact run/digest/path proof; affected suite green; deletion inventory. |

No task is currently classified XHARD. If RRP-01 exposes an irreducible cross-package
transaction/ownership decision, pause only affected work and send that concrete
decision to the configured oracle rather than escalating implementation by default.
