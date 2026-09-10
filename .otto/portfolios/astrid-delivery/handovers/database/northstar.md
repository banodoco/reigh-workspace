> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# North Star

Astrid uses one runtime-owned database authority: a canonical SQLite format, one read-only verifier and one guarded lifecycle boundary. Domain constraints, atomic receipts, CAS consistency, exclusive ownership, durable WAL-aware snapshots, serialized registration and fresh-instance fencing remain intact. Corruption fails closed and recovery replaces a root from verified material while retaining the damaged original.

Remove compatibility and duplicate lifecycle code. Avoid startup migrations, repair-on-open, implicit creation, dual writes, generalized storage frameworks and pack-owned database access. Preserve typed HTTP errors and generated client behavior.

Adopted from `docs/architecture/runtime-database-clean-break-plan.md`, SHA-256 `9cce8e3310759a712031b0f2e2e637d39ffa5fdd1a2b6d34da564b49cb4be7ac`, on 2026-09-10. This direction does not authorize operating on existing data.
