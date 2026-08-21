# Explore E6: lease-expiry liveness (where expire_overdue runs today)

Read `.oracle/northstar.md` and `.oracle/agent_goal.md` first. Work in `/Users/peteromalley/Documents/Astrid-oracle`.

Doc 27 requires a serve-side maintenance loop calling `TaskRepository.expire_overdue` (tasks.py:2358) — nothing currently schedules it. Task: verify precisely how expiry is observed today: does `claim` sweep expired attempts as part of selection, or only `expire_overdue`? Read claim's full selection path (:1745+) for any lazy-expiry behavior. Then determine the minimal correct wiring for Phase A: a background thread in `astrid serve` submitting through the writer queue vs on-claim lazy sweeps — what does the kernel already support, what are the races to avoid (expiry vs heartbeat serialization on the writer FIFO), and where would the loop live at serve boot (`compose_standard_bridge`?). Also confirm lease default (300s) and what happens to child tasks when an orchestrator-style parent lease expires mid-fan-out (relevant later, but note it).

Report ranked findings (<300 words) with file:line evidence and ONE recommended wiring.
