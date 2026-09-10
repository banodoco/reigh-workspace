> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Plan 2 implementation criteria

- C1: durable primary outputs and temporary derivatives have explicit output intent and immutable source/member provenance.
- C2: lifecycle metadata is runtime-owned and mutable; paths never establish identity.
- C3: leases/pins/expiry/promotion/deletion preserve durable references and exact regeneration inputs.
- C4: generic task/run/artifact events, receipts and idempotency are reused; no parallel review event ledger.
- C5: two producers use the same contract without producer-specific tables or authored-media rows for derivatives.
- C6: completed Plan 1 visualizer migrates and passes shared lifecycle evidence end to end.
