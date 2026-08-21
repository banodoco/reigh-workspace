# Explore N1: receipt × event-less completion (sharpest open risk before T7)

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

Context: Phase-A completion UoWs contain exactly one event append (`timeline.registry_merged`), which satisfies `ReceiptService.record`'s demand for positive `first_project_seq` (astrid/core/receipts/service.py:362-364). Open question: is a completion WITHOUT a timeline merge legal in Phase A (e.g. a task whose output policy creates no registry visibility — a generation that lands in the gallery but is not placed), and if so, does the receipt path break?

Investigate: (1) read receipts/service.py fully — what exactly requires `first_project_seq > 0`; is there any existing zero-event receipt form or alternative? (2) read the completion UoW construction (tasks.py:3517+, T3's record_completion design in doc 27 §2.3) — under what conditions does a Phase-A completion skip the registry merge (no default timeline? output_policy without placement? generation with no timeline visibility)? (3) decide: is a zero-event receipt variant needed, or should Phase A REQUIRE every completion to merge registry visibility into the default timeline (making the one-append guarantee structural)? Weigh simplicity (constitution: no ceremony without a current consumer) against correctness.

Report ranked findings (<300 words) with file:line evidence; end with ONE recommendation.
