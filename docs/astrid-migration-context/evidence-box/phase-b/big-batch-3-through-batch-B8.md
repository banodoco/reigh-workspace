# Cumulative Review 3 — B7 Wan gates + B8 setup journal/acquisition (narrowed)

## Verdict: PASS

Scope: new seam only (B7 gates, B8 model_setup) + integration regressions. Prior coverage (B1–B4) not re-audited.

### 1. Journal / boot ordering / state machine — OK
- Replay-before-database-path confirmed at the real boot site: `astrid/core/packs/__init__.py:325` calls `_replay_setup_journal(root)` before `derive_database_path(root)` (:326).
- `SetupJournal.replay()` (journal.py:221-290): fsync'd JSONL append with monotonic seq seeded from replay; folds absent→downloading→verifying→staged→installed plus corrupt/repairing. Torn final line ignored (crash mid-append); unparsable record inside the durable prefix marks the log `corrupt`, never trusted as truth — doctor rebuilds from filesystem reality.
- `resolve_boot_state()` (:293-371): staged+bytes → hash-verify then atomic rename (hash mismatch → `corrupt/staged_hash_mismatch`); staged/verifying without bytes → resume from actual `.part` length (filesystem wins over recorded offset); `installed` fast path is stat-only (deep re-hash is doctor's job). Matches the documented spec.

### 2. Signed manifests actually verify — OK
HMAC-SHA256 over canonical JSON, `hmac.compare_digest`; `parse_manifest` fails closed on schema mismatch, malformed fields, and signature mismatch. Verified live: valid manifest accepted; tampered `size` and forged signature both rejected ("manifest signature mismatch … refusing to trust it"). Tier discovery (`discover_environment`) derives OS/arch/RAM/disk only — explicitly never CUDA presence.

### 3. Probe truthfulness on CPU-only box — OK (live-checked)
`resolve_probe` live results: wgp_runtime/vibecomfy_runtime/remotion_ready → True (vendored fixture trees present); `wgp_weights:<model>`/`vc_weights:<template>` → False with exact missing artifact + "run 'astrid doctor setup'"; unknown/malformed names → None. Probes gate on installable artifacts ONLY (capabilities.py:571-575 comment enforced in code); zero CUDA-presence gating anywhere in the probe path. B7 `wgp_gates.py`: CPU-feasible legs mechanical, CUDA legs reported `skipped` with explicit reasons (`blocked(CUDA)`, stop-condition note).

### 4. Integration flip + 422 payload — OK
- Zero-code-change flip proven by `tests/v10/test_setup_probes.py::test_completing_setup_flips_probe_without_code_changes`; probes read one place (`read_stamp`, write=False replay + stat), so installing via setup flips advertisement with no code change.
- 422 carries prerequisites: `check_available` raises `CapabilityUnavailable("missing_prerequisites: <artifacts>; run 'astrid doctor setup'")` (capabilities.py:980-986), mapped to `BridgeCapabilityUnavailableError` (HTTP 422, code `capability_unavailable`) at both admission sites (bridge_service.py:594, :726).

### Suite evidence
`python3 -m pytest tests/v10 -k "setup or model or manifest or probe" -q` → **75 passed**, 0 failed.

No issues found.
