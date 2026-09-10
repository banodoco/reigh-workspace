> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Plan 2 tasklist

| ID | Outcome / dependency | Route | Acceptance evidence |
|---|---|---|---|
| E2-01 | Shared output-intent/provenance contract via capability/result manifests (`docs/contracts/capability-artifact-contract.md`; `result_manifest.py:574-660`) | normal | synthetic producer emits digest/role/coverage/recipe |
| E2-02 | Runtime-owned lifecycle metadata, generic events, receipts and idempotency | normal; after E2-01 | retry returns original publication; no review event family |
| E2-03 | Safe adoption of existing CAS/durable outputs and caches | normal; after E2-02 | digest dedupe, no broad deletion, conflicting identity rejected |
| E2-04 | Lease/pin/TTL/promotion/deletion correctness | normal; after E2-02 | only unpinned expired derivatives delete; durable output survives |
| E2-05 | Extension-author guidance and second-producer fixture | normal; after E2-01/E2-02 | no producer-specific table/event family |
| E2-06 | Integrate completed Plan 1 and verify end-to-end | normal; after E2-03/E2-04 and Plan 1 | Plan 1 members migrate with provenance/lifecycle evidence |
