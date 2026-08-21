# Explore E7: test-suite geography and integration-test conventions

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

The planner found tests live at repo-root `tests/` (not `astrid/tests/` — agent_goal's validation command has a typo). Task: (1) confirm the full layout: `tests/v10/` (kernel, incl. test_crash_atomicity.py pattern with `UnitOfWork(on_statement=)` + child `os._exit`), `tests/integrations/reigh/` (HTTP bridge tests, in-process daemon servers on port 0, `compose_standard_bridge` injection) — list the key fixture/conftest files an implementer must reuse for new route tests, a journey harness, and a fault-injection matrix. (2) Confirm no CI config references `astrid/tests`. (3) How do existing tests create fresh DBs (tmp roots?) and boot the bridge in-process? (4) pytest conventions: markers, -x usage, expected runtime. (5) Anything in pyproject/tox/CI that constrains adding `tests/integrations/reigh/test_journey_phase_a.py` + `tests/v10/test_phase_a_fault_matrix.py`.

Report ranked findings (<300 words) with file:line evidence; end with the corrected validation commands for agent_goal.
