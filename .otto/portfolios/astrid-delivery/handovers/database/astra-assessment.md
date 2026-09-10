> Frozen reference snapshot. Current state and receiving authority are governed by the package START-HERE and authority.md; preserve the existing live run. Paths below are source references, not missing package requirements.

# Astra planning assessment — adopted by user

User requested GPT-6 Astra medium judgment on the 10–15-day estimate versus a proposed 3–5-day consolidation. Native agent `01a08bc9-1ecb-7152-993f-1423bcf34bb0` (Faraday), configured `gpt-6-astra`, medium reasoning, completed a read-only source assessment. No tests or product edits were performed. User then instructed: “update the plan on that basis.” This authorizes the planning amendment, not execution.

Recommendation: retain the complete outcome through consolidation, provisionally 6–9 focused engineering days; 10–15 contingency for difficult recovery integration or consumer closure. A 3–5-day milestone omits complete snapshot/replacement guarantees and full compatibility/consumer closure. The original plan already required reuse, so reuse alone did not support halving the estimate.

Evidence below is relative to `<workspace>/banodoco-workspace-runtime-execution-20260909`, inspected dirty checkout at recorded HEAD `afccb430e2a983c968b6a8a96fd630ba3a6262fc`. Line references describe inspection-time source and must be reconciled at T1.

| Retain or fix | Source evidence | Task |
| --- | --- | --- |
| Retain shared admission/transaction locking and CAS-journal reconciliation | `runtime_protocol/service.py:189`; race fixture `tests/test_realm_admission_hardening.py:410` | T3 |
| Retain private WAL inspection, SQLite backup API and CAS copy under mutex | `runtime_protocol/store.py:262`, `runtime_protocol/backup.py:571`; WAL-only round trip `tests/test_realm_admission_hardening.py:223` | T2, T4 |
| Retain receipt rollback and stale-worker tests | `tests/test_runtime_domains.py:252`, `tests/test_runtime_reboot.py:184` | T3, T4 |
| Tighten exact schema and identity admission; refuse missing roots before lock directory creation | `runtime_protocol/store.py:2067` | T2 |
| Candidate currently renamed before verification; reverse that order | `runtime_protocol/backup.py:634` | T4 |
| Restore currently yields an inactive new realm; complete owner shutdown, switch, credentials and interruption recovery | `runtime_protocol/backup.py:659` | T4 |
| Serialize registration and selection read-modify-write | `runtime_protocol/catalog.py:108` | T5 |
| Adapt publication tests importing removed migration code | `tests/test_dirfd_publication.py:46` | T6 |
| Supplement operation/digest parity with actual typed-error behavior | `tests/test_client_parity.py:49` | T6 |

Avoid a manager framework, wholesale SQL movement and rebuilding existing safety tests. A thin boundary must still enforce admission. Epoch freshness must be relative to the superseded live owner, not only the restored snapshot.

This is user-requested planning advice, not an executable review stage, a delivery certification or a replacement for the configured oracle. Execution review/oracle counters remain unchanged. No criterion has been dropped; all C1–C8 retain their IDs and proof obligations. No existing executable approvals require invalidation because execution has not begun.
