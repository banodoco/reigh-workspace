# Per-Pair Data Persistence

> Source of truth for per-pair prompts, settings, and overrides in travel-between-images.

---

## Data Model

All per-pair data lives on the **start image** of each pair, in `shot_generations.metadata`:

```
Timeline:  [Image A] ----pair 0---- [Image B] ----pair 1---- [Image C]
Storage:      ↑                         ↑
         metadata for pair 0      metadata for pair 1
```

| Field | Purpose | Used By |
|-------|---------|---------|
| `pair_prompt` | User's custom prompt | Overall generation + regen |
| `pair_negative_prompt` | User's negative prompt | Overall generation + regen |
| `enhanced_prompt` | AI-generated prompt (VLM) | Fallback for generation; "restore to AI" target |
| `user_overrides` | Technical regen settings (LoRAs, motion, phase) | **Regen only** (backend can't apply per-segment to overall gen) |

---

## Prompt Priority Chain

Generation and display resolve prompts in **different** order:

| Priority | Generation (sent to backend) | Display (shown in form) |
|----------|------------------------------|-------------------------|
| 1st | `pair_prompt` | `enhanced_prompt` |
| 2nd | `enhanced_prompt` | `pair_prompt` |
| 3rd | shot-level `base_prompt` | shot-level `base_prompt` |

**Why different?** The form shows the AI prompt so users see the VLM description as a starting point. When they edit, it saves to `pair_prompt`, which then takes priority for generation. The AI version is preserved for "restore to AI version".

- Generation: `generateVideoService.ts` extracts `pair_prompt` / `enhanced_prompt` per pair; backend merges with priority above
- Display: `SegmentSettingsModal.tsx`, `MediaLightboxRefactored.tsx` show `enhanced_prompt || pair_prompt || defaultPrompt`

---

## Key Invariants

### Pair Indexing

N positioned images = **N-1 pairs**. Pair index `i` = transition from image `i` to image `i+1`. Data stored on `shot_generations[i].metadata`. The last image has no outgoing pair.

### Video-to-Pair Tethering

Videos are tethered to pairs via `start_image_generation_id` in the video's params — **not** stored `segment_index`.

1. Extract `start_image_generation_id` from video params
2. Find that ID in current `shot_generations` array
3. Use that position as the segment index

**Why?** Stored `segment_index` goes stale after deletions/reorderings. Tethering to the actual image ID is semantically correct (the video IS the transition from that image) and auto-corrects when the timeline changes. If the start image is deleted, falls back to stored `segment_index`.

### Filtering + Ordering Must Match Everywhere

Any code mapping pair index to shot_generation row must use identical filtering and ordering:

| Rule | Reason |
|------|--------|
| Exclude unpositioned items (`timeline_frame < 0`) | Sentinel value for unpositioned media |
| Exclude videos (by `generation.type` / file extension) | Videos are not travel pairs |
| Sort by `timeline_frame ASC`, tie-break `id ASC` | Prevents pair index shuffle |

**Code paths that must agree:** `generateVideoService.ts`, `update-shot-pair-prompts`, timeline pair UI, MediaLightbox regen lookup, `ChildGenerationsView`.

---

## Snapshot vs Source of Truth

| Data | Location | Trust |
|------|----------|-------|
| Per-pair prompts | `shot_generations.metadata.pair_prompt` | **Source of truth** |
| AI prompts | `shot_generations.metadata.enhanced_prompt` | **Source of truth (AI fallback)** — never delete on user edit |
| Per-pair regen settings | `shot_generations.metadata.user_overrides` | **Source of truth (regen only)** |
| `generations.params` | `generations` table | Snapshot — can be stale vs current timeline |
| `tasks.params` | `tasks` table | Snapshot — useful for debugging "what was sent" |

---

## Reset / Restore Semantics

Three distinct actions:

| Action | Effect | Resulting prompt |
|--------|--------|-----------------|
| Clear field | `pair_prompt = ""` (treated as absent) | Falls back to `enhanced_prompt` / shot default |
| Restore to AI | Delete `pair_prompt` | Falls back to `enhanced_prompt` |
| Restore to defaults | Delete `pair_prompt` AND `enhanced_prompt` | Falls back to shot-level `base_prompt` |

**Note:** "Reset to variant defaults" in the regen form only clears `user_overrides`, not prompts. The system currently has no "explicit blank prompt override" — empty strings fall through to the next priority level.

---

## Enhanced Prompts (VLM)

1. User clicks "Enhance prompts" → VLM analyzes each pair's images
2. Edge function `update-shot-pair-prompts` saves to `enhanced_prompt` on each start image
3. User edits → saved to `pair_prompt` (`enhanced_prompt` preserved)
4. "Restore to AI version" → deletes `pair_prompt`, falls back to `enhanced_prompt`

---

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Prompt ignored in overall gen | Saved to `user_overrides.base_prompt` instead of `pair_prompt` | Save to `pair_prompt` field directly |
| Enhanced prompt lost after edit | Code deleting `enhanced_prompt` | Only set `pair_prompt`; never delete `enhanced_prompt` on edit |
| Video shows wrong pair's data | Stale `segment_index` in params | Derive segment from `start_image_generation_id` |
| Video in wrong gallery slot | `child_order` mismatch | `ChildGenerationsView` derives slot from `start_image_generation_id` |
| Settings not persisting | Wrong `shot_generation` ID | Verify `pairData.startImage.id` matches the correct row |
| Lightbox vs Timeline disagree | Different save paths | Both must save to `shot_generations.metadata` |

---

## Key Files

| File | Purpose |
|------|---------|
| `src/tools/travel-between-images/components/Timeline/SegmentSettingsModal.tsx` | Timeline pair editing UI |
| `src/shared/components/MediaLightbox/MediaLightboxRefactored.tsx` | Lightbox regenerate tab |
| `src/shared/hooks/useSegmentSettings.ts` | Fetch/merge/persist segment settings |
| `src/shared/components/segmentSettingsUtils.ts` | Interfaces, utilities, presets |
| `src/tools/travel-between-images/components/ShotEditor/services/generateVideoService.ts` | Overall generation — extracts per-pair prompts |
| `src/tools/travel-between-images/components/VideoGallery/components/ChildGenerationsView.tsx` | Video gallery slots via `start_image_generation_id` |
| `supabase/functions/update-shot-pair-prompts/index.ts` | Edge function for VLM prompt enhancement |
