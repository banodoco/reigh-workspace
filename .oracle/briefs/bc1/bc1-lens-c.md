# BC1 review — lens C: GROUND TRUTH vs the actual code

You are an independent reviewer (lens C of BC1). Working directory: /Users/peteromalley/Documents/reigh-workspace-oracle. READ-ONLY.

## Read
`.oracle/agent_goal.md`, `.oracle/plan.md` (v3+deltas), `.oracle/tasklist-draft.md`, then VERIFY against the actual code in `/Users/peteromalley/Documents/Astrid-oracle/`.

## Your lens: GROUND TRUTH
Spot-check the plan/tasklist's code claims — would each batch actually work as described? Verify at minimum: (1) T1's file/line claims (materialize_prepared:1794–1800, _insert:2156–2164, publish_prepared_media:938–949, tasks.py complete:3517/receipt gate:3628–3638) — open the files; (2) T2's six frozen-20 assertion sites (m4_gate.py, test_registry.py, test_m6_gate.py, test_reference_lifecycle.py, test_m8_installed_contract.py) — do those counts/lines exist?; (3) T6's claim that expire_overdue:2358 has zero production callers and compose_standard_bridge (packs/__init__.py:199/234) is the right sweeper site; (4) T7's staging_path reuse (media_import.staging_path) and the blender_render_server.py Content-Length precedent (:298–305); (5) T9's parse_request:188–192 hook point and _ALLOWED_HEADERS:252–263; (6) the test layout claim (repo-root tests/, tests/v10/test_crash_atomicity.py pattern, tests/integrations/reigh/ with tmp_bridge_root:100/repository_server:219). Flag any claim that is wrong, stale, or would break implementation.

## Verdict format
Start with exactly `CONVERGE` (claims check out; minor notes) or `DIVERGE` (list wrong claims with file:line evidence and the correction). ≤400 words.
