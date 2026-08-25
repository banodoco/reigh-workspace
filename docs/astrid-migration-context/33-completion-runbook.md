# 33 — Completion Runbook: from current state to shipped product

## Where we are right now

Phase A ✅ · Phase B ✅ · Phase C ◐ (~75%)
Three fixers running on box container `reigh-phase-a-exec`:
- save-persistence kernel fix (debugging WAL/live-writer bug)
- shot cutover (eliminating last supabase-js files querying old placement)
- onboarding screen ✅ done

Full context: docs/astrid-migration-context/ (31 docs). Build contract: doc 27. Forward map: doc 31.

## Step-by-step to done

### 1. Wait for fixers → oracle review each
When `fix-save.log` and `fix-shot.log` show completion: dispatch one independent stealth/ox-alpha reviewer per fixer output against its acceptance criteria. Fix loop until PASS.

### 2. Execute remaining reigh-app batches (from frozen tasklist)
Read `.oracle/tasklist.md` Batch sections B5–B8 for exact specs:
- **B5** Shot mode as view (3 tasks: document view, deep-copy duplicate, promote-primary pack command)
- **B6** Render/export UX (render admission via R1 render_export; runtime/UI cutover; MP4 playback via R9)
- **B7** Ops surfaces (backup/restore hooks calling bridge endpoints; onboarding/model-setup screens wired to doctor; typed error/recovery UX)
- **B8** Acceptance gates (grep script proving zero supabase-js imports; build green; OS-network-blocked journey test)

Each batch: implement → scoped vitest → commit → oracle review → fix loop until PASS.

### 3. Integration proof (cannot be skipped)

These require real hardware/software running — no code review substitutes:

| Proof | How | Pass condition |
|---|---|---|
| Real Wan2GP t2i generation through full pipeline | Admit via R1 → worker claims → WGP runs on GPU → atomic complete → gallery row appears | Generation visible within 3s of completion |
| Real VibeComfy workflow execution | CPU-mode subprocess with deterministic graph | Same |
| Model weight download end-to-end | Fresh machine or wiped ckpts dir → doctor setup → weights present → generation works | Setup journal shows installed(verified); capability advertised |
| Document size at scale | Generate fixture with 200 shots × 50 pooled generations × full registry | Save latency p95 ≤ 150ms typical / ≤ 1s at ceiling |

### 4. Merge + push

```
# Astrid (on box)
git checkout main && git merge --ff-only phase-b && git push origin main
git tag archive/phase-a 0b69557b && git push origin archive/phase-a

# reigh-app (on box)  
git checkout main && git merge --ff-only phase-c && git push origin main
```

Only after acceptance passes with Supabase networking blocked.

### 5. Retire Supabase
Delete parked branches, archive tags, remove old env vars, delete Supabase project.

## Known risks at this point

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Save-persistence root cause is deeper than expected | Medium | Blocks all Phase C | Already being debugged by dedicated fixer |
| ComfyUI won't start on CPU-only box | Low-medium | Forces stub binding instead of real subprocess | Test early in B-1 gate |
| Timeline document too large at scale | Medium | CAS saves slow down | Measure with production-shaped fixture before Phase C exit |
| Hidden Supabase deps surface during cutover | Medium | Extends C1 waves | Inventory already maps them; fix as found |
