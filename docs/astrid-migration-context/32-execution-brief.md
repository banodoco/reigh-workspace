# Reigh-on-Astrid: Full Execution Brief

## What this project is

Reigh is being rebuilt as a **local single-user video editor** running entirely on **Astrid's SQLite kernel** via a loopback HTTP bridge. No cloud, no login, no credits, no Supabase. One SQLite file holds all structured state; one SHA-256 media tree holds all bytes; one bridge process (`astrid serve` on port 17333) is the only door.

## What is DONE and PUSHED

### Phase A — kernel foundation
Branch: `origin/Astrid/oracle-run` @ `0b69557b`
- §5 amendment: bytes publish durably BEFORE `BEGIN IMMEDIATE`; receipt inside commit; only invisible byte orphans possible on crash
- Crash-point fault-injection matrix: 107 crashes / 7 classes / zero DB-tree disagreement
- Shots-pack v2: `generations` + `generation_variants` tables (one-primary partial index, unique media membership, soft delete)
- Capability registry: 19 flat `reigh.<normalized>` names, dead types rejected, child allowlist
- Fenced task routes: admission (Idempotency-Key), claim (leased running attempt), heartbeat, complete (multipart + fence), fail
- Local-trust gate: per-boot token (hmac.compare_digest), Host-vs-loopback check, custom header, 0700 dirs
- Lease-expiry sweeper at serve boot (~15s tick)
- Gallery reads (R12): paged cursor, primary-variant summary, head counts
- Media content route (R9): Range/ETag/304/416 streaming from managed tree

### Phase B — catalog population + bindings
Branch: `origin/Astrid/phase-b` @ `5c43235b`
- Capability fan-out: ~15 capabilities registered (qwen family, z_image, upscale, flux_klein, video_enhance, animate_character, inpaint, travel/join/edit orchestrators)
- Orchestrator coordinator: leased parents, attempt-independent child keys, deterministic replay, transition table + interleaving suite (zero duplicates proven)
- Wan2GP binding skeleton + five-gate upgrade pipeline (CUDA legs documented-skipped)
- Setup journal: sidecar JSONL at `<root>/.astrid/setup/journal.jsonl`, fsync'd appends, boot-time replay, state machine absent→downloading→verifying→installed/corrupt→repair
- Signed version-pinned distribution manifest; tier discovery; disk preflight
- Doctor deep re-hash + targeted repair; probe registrations (never CUDA)
- Boot manifest: dual-scope digest (registry + fixtures), fail-closed startup on drift, emitted by `_dispatch_serve`
- Conformance completion sweep: fixture per shipped capability

### Phase C (partial) — app cutover
Branch: `origin/reigh-app/phase-c` @ `408d38ae4`
- Cutover inventory: every supabase-js call site enumerated with disposition
- Shared bridge transport: timeout/envelope/token posture consumed by both editor provider and local client
- AstridLocalClient route modules replacing supabase-js for tasks/gallery/media/timeline
- Capability flags replacing instanceof gates on DataProvider
- Four cutover waves: tasks/polling, gallery/media onto R12/R13+R9, realtime→2s/10s/30s diff-poller, boot/auth to fixed local user via `/api/astrid/health` probe
- Document-native placement foundation: placementService.ts (CAS reload-retry ladder), shot_generations retired from realtime diff-poller/event processor/invalidation
- Journey placement visible: committed

## What is IN PROGRESS right now

Three stealth/ox-alpha fixers running on box container `reigh-phase-a-exec`:

1. **Save-persistence kernel bug** (Astrid, branch phase-b): only first HTTP save per boot persists. Root cause being debugged in the long-lived server's UnitOfWork commit path. This blocks ALL Phase C acceptance.
   - Log: `/opt/megaplan-cloud/workspace/reigh-phase-a-20260822/fix-save.log`
   - Brief: `/workspace/reigh-phase-a-20260822/briefs/fix-save.md`

2. **Shot cutover** (reigh-app, branch phase-c): eliminating last ~23 supabase-js files querying old `shot_generations`. Three commits already landed (TBI surfaces, segments pipeline, timeline core). Remaining: variant promotion cleanup, share enrichment completion, travel-between-images hooks.
   - Log: `/opt/megaplan-cloud/workspace/reigh-phase-a-20260822/fix-shot.log`

3. **Onboarding screen** (reigh-app): ✅ COMPLETE — `LocalSetupModal` shipped, 17 old files deleted, 20 new tests green.

## What REMAINS after the fixers land

1. **Oracle reviews** of the three fixer outputs (one independent pass each)
2. **C5 — Shot mode as view**: wire placement calls into actual UI rendering
3. **C6 — Render/export UX**: render-as-task button wired to capability registry
4. **C7 — Ops surfaces**: backup/restore hooks, doctor integration in settings
5. **C8 — Acceptance gates**: clean-install boot, Supabase networking OS-blocked, full journey green
6. **Merge** `phase-b` → `main` (Astrid) and `phase-c` → target branch (reigh-app)
7. **Push** both to origin
8. **Retire** Supabase project

## Key decisions (all ratified)

- Fresh start: NO data migration, no backward compatibility
- Fully local compute: no outbound generation providers
- Document-native placement: NO `shot_generation_items` table
- Render via Astrid Remotion → managed MP4
- Polling 2s/10s/30s, no SSE
- Copy-only media, no link mode
- Credits/auth/sharing/referrals/PATs: ALL CUT
- Flat `reigh.<normalized>` capability names, one binding per capability

## Key files

| File | Role |
|---|---|
| `.oracle/northstar.md` | Durable direction |
| `.oracle/agent_goal.md` | Frozen run contract |
| `docs/astrid-migration-context/27-build-spec.md` | THE build contract |
| `docs/astrid-migration-context/31-forward-map.md` | Phase B/C plan |
| `docs/astrid-migration-context/15-owner-decisions-defaults.md` | Ratified scope |
| `docs/astrid-migration-context/29-ground-truth-sensecheck.md` | Audit findings |

## Infrastructure

- Box: `root@159.69.51.216` (Hetzner, container `reigh-phase-a-exec`)
- Workspace: `/workspace/reigh-phase-a-20260822/`
- Model: stealth/ox-alpha via OpenRouter (key at `/root/.openrouter-key`)
- Launcher: `/root/.codex/skills/subagent-launcher/launch_hermes_agent.py`
