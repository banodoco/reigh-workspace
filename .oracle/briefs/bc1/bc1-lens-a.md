# BC1 review — lens A: CORRECTNESS vs the build contract

You are an independent reviewer (lens A of BC1). Working directory: /Users/peteromalley/Documents/reigh-workspace-oracle. READ-ONLY.

## Read
`.oracle/northstar.md`, `.oracle/agent_goal.md` (done criteria 1–7, validation commands), `.oracle/plan.md` (STABLE v3 + deltas), `.oracle/tasklist-draft.md` (the batches under review), and the binding contract `docs/astrid-migration-context/27-build-spec.md` (+ 29-ground-truth-sensecheck.md corrections).

## Your lens: CORRECTNESS
Does the tasklist + plan fully and faithfully implement doc 27's contract for Phase A? Check: every §4/§5/§6 requirement has a covering task; the atomic-completion ordering (pre-transaction CAS publish, receipt inside commit) is correctly specified in T1/T7/T13; the capability registry/allowlist/dead-type rejection matches doc 27 §3; child-admission gate and local-trust gate are complete (nothing missing: token, Host, custom header, 0700, node-allowlist?); done criteria 1–7 each map to ≥1 batch acceptance; validation commands correct (note: tests live at repo-root `tests/`).

## Verdict format
Start with exactly `CONVERGE` (agree; list minor notes) or `DIVERGE` (list specific blocking issues, each with evidence and the fix). ≤400 words. No hedging.
