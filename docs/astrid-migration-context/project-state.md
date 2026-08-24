# Reigh-on-Astrid: Project State

## What this is

Reigh rebuilt as a local single-user video editor running entirely on Astrid's SQLite kernel via a loopback bridge. No cloud, no login, no credits, no Supabase.

## Branches

### banodoco/Astrid
| Branch | SHA | State |
|---|---|---|
| `main` | `4cf58bec` | Pre-migration baseline |
| `oracle-run` | `0b69557b` | Phase A ✅ (kernel §5 amendment, crash matrix, trust gate) |
| `phase-b` | `5c43235b` | **Phase B ✅** — contains oracle-run. Capability fan-out (~15 caps), orchestrator children, Wan2GP binding + five gates, setup journal + doctor, conformance completion, boot manifest |
| `track-K/S/R` | merged | Phase-A parallel tracks (merged into oracle-run) |

### banodoco/reigh-app
| Branch | SHA | State |
|---|---|---|
| `timeline-patches` | `6c02bd3b` | Pre-cutover app baseline |
| `phase-c` | `408d38ae4` | **Phase C ◐** — 14 commits ahead: cutover inventory ✅, bridge transport + clients ✅, four cutover waves ✅, journey placement visible ✅ |

### banodoco/reigh-worker
| Branch | SHA | State |
|---|---|---|
| `main` | `68b70149` | Clean — worker port starts after Phase C app cutover |

### peteromallet/reigh-workspace
| Branch | SHA | State |
|---|---|---|
| `oracle-run` | `14ce958` | Plan corpus (docs 01–31) + evidence box |

## Work completed

- Kernel §5 amendment: bytes publish before BEGIN IMMEDIATE; proven by 107-crash fault matrix (zero DB/tree disagreement)
- Shots-pack v2 schema: generations/generation_variants (one-primary index, unique media membership)
- Capability registry: 19 flat reigh.* names, dead types rejected, child allowlist
- Fenced task routes: admission/claim/heartbeat/cancel/complete/fail with receipts + fences
- Local-trust gate: per-boot token, Host check, custom header, 0700 dirs
- Lease-expiry sweeper at serve boot
- Gallery reads (R12) + media content route (R9 Range/ETag)
- Orchestrator coordinator: leased parents, attempt-independent keys, transition table, interleaving suite
- Wan2GP binding skeleton + five-gate upgrade pipeline + rollback drill
- Setup journal state machine + doctor repair
- Boot manifest: dual-scope digest, fail-closed startup
- App cutover: cutover inventory, bridge transport + AstridLocalClient, capability flags replacing instanceof gates, four cutover waves, document-native placement foundation, shot_generations retirement from realtime

## Work remaining

| Item | Scope | Depends on |
|---|---|---|
| Shot mode as view | Shot groups/pools/boundaries read from timeline document; promote-primary via pack commands; deep-copy duplicate | C4 placement foundation (done), B2 client (done) |
| Render/export UX | Render-as-task button wired to capability registry; progress via polling; MP4 playback via R9 | B2 routes (done), render capability in registry (done) |
| Ops surfaces | Backup/restore hooks calling bridge endpoints; onboarding/model-setup screens wired to doctor; typed error/recovery UX | Bridge backup endpoints (may need adding) |
| Acceptance gates | Grep script proving zero supabase-js imports in covered modules; clean-install boot; Supabase networking OS-blocked; full covered journey green | All above |

## End state

Open browser → localhost:5173 → Reigh loads instantly. Browse projects stored locally in SQLite. Generate images/videos using Wan2GP or VibeComfy on your GPU. Results appear in gallery within 2 seconds. Edit timelines with CAS-safe saves. Export MP4s rendered by Remotion. No internet required. No login. No Supabase. No credits.
