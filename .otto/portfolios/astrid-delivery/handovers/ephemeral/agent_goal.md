> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Delivery setup goal

This is a planning-only Megado project package for [Plan 2](plan.md). It is ready for a later delivery run, but no implementation, worktree, tests, deployment, or review stages are launched by setup.

Scope: shared output intent/provenance, runtime-owned mutable lifecycle metadata, generic events/receipts/idempotency, safe adoption of existing CAS/durable outputs and caches, lease/pin/TTL/promotion/deletion correctness, extension-author guidance, synthetic second producer, and migration/E2E integration with completed Plan 1. It is independently implementable against a synthetic producer; its final Plan 1 migration depends on Plan 1's completed visualization scope.

Source: dirty working tree at HEAD `32910818874b4699281b7ab2b1bd000097ac1c8d`, branch `recovery/runpod-s3-multipart-20260903`; dirty source is authoritative. Provenance and accepted decisions: archived prior run (original source reference: `../archive/render-review-plan-20260910/`), Astra decision (original source reference: `../archive/render-review-plan-20260910/oracle-response.md`).
