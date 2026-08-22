# Oracle Review — track-R (capability registry + admission/lifecycle + trust perimeter)

Reviewed: `dd1bbe3a..track-R` (9 files, +4207/−12). Tests: `python3 -m pytest tests/integrations/reigh -x -q` → **244 passed** (72.7s).

## Verdict: ISSUES (1 minor, non-blocking)

### Issue 1 (minor): fd leak in multipart parser on oversize-file rejection
- **Evidence:** `astrid/core/integrations/reigh/multipart.py`, `stage_file_until` (lines ~234–287): when `spill()` raises `MultipartTooLarge` (file exceeds `file_cap`), `fail()` unlinks the staged path but nothing calls `os.close(handle_fd)` — the truncated-body path closes explicitly, the oversize path does not. Reproduced: 200 abusive requests → `/proc/self/fd` count 6 → 206 (one leaked fd per request). Staged bytes are cleaned up correctly; only the descriptor leaks.
- **Impact:** unbounded abusive `complete` requests can exhaust fds and take down the serve process. Mitigated by the trust gate (attacker needs the per-boot token), hence minor.
- **Fix:** close the handle on the failure path, e.g. track `handle_fd` and wrap the stream loop:
  ```python
  try:
      while True:
          ...
  except BaseException:
      os.close(handle_fd)
      raise
  os.close(handle_fd)
  ```
  (or pass a file object and use a context manager).

## Acceptance checklist — all verified against source, not just tests

1. **Registry** (`capabilities.py`): 19 flat `reigh.*` IDs + `rendering.timeline_visualize`; frozen slotted entries; import-time `_validate_registry` enforces known bindings/families/probes, child-only ⊆ allowlist, every family covered. `DEAD_TYPES` incl. `wan_lora_training` → `CapabilityUnavailable` (422), never aliased. Child allowlist has the specified 5 IDs.
2. **R1 admission**: `_require_idempotency_key` (required, ≤200 printable ASCII); kernel receipt gate yields 201 new / 200 replay (`existing` stable-id lookup keeps the same task id so the receipt hash matches) / 409 `idempotency_mismatch` via `ReceiptMismatchError` mapping. Tested as trio.
3. **Child hard gate**: `admit_child` requires the full executor envelope; browser path (`admit`) raises `ChildAdmissionForbidden` for child-only entries; deterministic key `reigh.orch:v1:{parent}:{role}:{index}` enforced; live parent fence verified (status running, attempt owned by executor_id+lease_id+status_version, lease unexpired). Forged/stale/nondeterministic-key/non-child cases all rejected (tests present).
4. **Trust gate**: placed in `parse_request` **after** `super().parse_request()`; Host vs bound loopback literal via `hmac.compare_digest`; per-boot token (`secrets.token_urlsafe(32)`) compared with `hmac.compare_digest`, delivered out-of-band at `<root>/.astrid/request-token` mode 0600 under a 0700 managed root; OPTIONS exempt; GET/HEAD host-checked only; reject answers typed 403 and drops connection. Hostile fixtures green (spoofed/missing host, wrong/missing token, CORS-less POST).
5. **Claim/heartbeat/cancel/read**: claim is per-project head, ordered `(priority DESC, available_at ASC, id ASC)`, capability-filtered, hard-dependency-aware, keyless empty 204; heartbeat extends lease via kernel service and merges progress through a raw fenced `UPDATE ... WHERE id=? AND lease_id=? AND status IN ('claimed','running')` — no event/receipt appended; cancel requires a fence for running tasks, terminal cancel idempotent; reads bounded (limit≤200, summary fields frozen).
6. **Complete/fail**: parser rejects chunked TE, missing/invalid length, caps body/file/field/header-block before or during streaming, unlinks staged bytes on every failure (verified by repro above too); manifest part must be JSON; server-side sha256 + size verification before import; staging media identity pinned to digest (`uploads/{digest}`) so lost-ack replay is exactly-once; wrong fence → 409 `conflict` with bounded `_attempt_wire_shape` extras and zero authoritative rows; `fail` validates `{code,message,retryable}` (message ≤4000 chars) and budget exhaustion honored (`max_attempts=3` from admission). Abuse cases fail closed.

## Anti-pattern scan
No second authority (task bridge injected once at composition root; absent bridge → typed 500 fail-closed), no silent fallbacks, no middleware layering beyond the single parse_request gate, no speculative plugins. Heartbeat/cancel reuse kernel services rather than duplicating transitions.

## Recommendation
Merge-blocking: no. Land the fd-close fix (Issue 1) as a follow-up commit; it is three lines and closes the only observed resource leak.
