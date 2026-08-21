# Custody baseline — megado run (2026-08-22)

Captured before any worktree creation. Protected local work must survive untouched.

| Repo | Base ref (oracle-run source) | Branch at capture | Uncommitted changes | Remote |
|---|---|---|---|---|
| reigh-workspace (orchestration home) | `f17dc11cee0a131133449581cb6ea0dff5f4e054` | `docs/vibecomfy-post-chain-qwen-proof` (ahead 14 of origin) | `.gitattributes`, `.sc05/` untracked | github.com/peteromallette/… (docs branch pushed separately by owner) |
| Astrid | `dd1bbe3a872eb4adfaa644c7a377e9ab32bad160` | `main` | **43 files (protected WIP — do not touch)** | github.com/peteromallet/Astrid.git |
| reigh-app | `6c02bd3ba56d9a2f5a7dcb55ffbe4a7a581a3b04` | `timeline-patches` | 27 files (protected) | github.com/banodoco/reigh-app.git |
| reigh-worker | `68b701497c4b9363c9d0ab74be1acc0066d71575` | `main` | 0 (clean) | github.com/banodoco/reigh-worker.git |
| reigh-worker-orchestrator | `5f58f30d6ac35a9fce81497680ecdb9ef30b9386` | `fix/stale-task-reset-long-running-types` | 9 files | banodoco/reigh-worker-orchestrator.git |

## Worktrees created (all branch `oracle-run`)
- `/Users/peteromalley/Documents/reigh-workspace-oracle` ← workspace @ f17dc11 (orchestration home; holds `.oracle/` + full plan corpus under `docs/astrid-migration-context/`)
- `/Users/peteromalley/Documents/Astrid-oracle` ← Astrid @ dd1bbe3a (execution target: kernel, packs, bridge, registry, tests)
- `/Users/peteromalley/Documents/reigh-worker-oracle` ← reigh-worker @ 68b70149 (Phase B target; unused in Phase-A batches unless a slice task requires it)
- reigh-app: worktree DEFERRED to Phase C (no Phase-A batches touch it)

## Rules
- Never commit in the base checkouts; all mutation happens in the oracle worktrees above.
- The Astrid main checkout's 43 dirty files are the owner's WIP — read-only for this run.
- Sync policy (from agent_goal): at Phase-6 completion, push each touched `oracle-run` branch to its `origin`. No merges to main.
