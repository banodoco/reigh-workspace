# 06 — reigh-app: Data Usage & Contract Surface

**Summary.** `reigh-app/` is a **Vite + React 18 SPA** (not Next.js) backed by **Supabase** (`@supabase/supabase-js` ^2.49.4) plus one external service: a Python "append service" (`VITE_REIGH_APPEND_SERVICE_URL`) that is the *only* writer for video-editor timeline `config`/`asset_registry` mutations (CAS-enforced, backed by `timeline_events`). All data access is browser-side through a single lazily-created Supabase client with a cached-token fetch shim; there is **no server component** — auth is Discord OAuth (Supabase GoTrue) and every read/write relies on Postgres RLS. The app reads/writes ~30 tables via direct PostgREST (`.from()`), ~20 RPCs, 40 edge functions (12 called by the frontend), 2 realtime channels (5 tables), React Query polling (2–30 s intervals plus a realtime-health adaptive poller), and 6 storage buckets. **Key fact for a migration:** the timeline editor's durable state lives in `timelines.config`, `timeline_events`, `sync_bookmarks`, `timeline_checkpoints` — written only through the append service; a replacement backend must reproduce that append-service contract or bypass it (e.g. Astrid file store) at the `DataProvider` seam.

**Key facts.**
- Pure browser SPA; Supabase client singleton created at bootstrap (`src/integrations/supabase/bootstrap/createSupabaseClient.ts`); `db.schema='public'`; anon key + JWT; auth `autoRefreshToken/persistSession/detectSessionInUrl`; realtime heartbeat 30 s, max reconnect 10 s, `eventsPerSecond:10`.
- Access token is read **synchronously from localStorage** (`readAccessTokenFromStorage`, key `sb-<projectRef>-auth-token`) and injected into a replaced `PostgrestClient.fetch` to avoid `navigator.locks` contention (`createSupabaseClient.ts:28-66`).
- Route guard: `src/app/Layout.tsx` redirects unauthenticated users to `/home`; DEV-only sessionless "local mode" (`?localProject&localTimeline`) renders the whole shell with no backend calls (Astrid bridge path).
- Realtime channel `task-updates:<projectId>` (`src/shared/realtime/RealtimeConnection.ts`) subscribes `postgres_changes` on **tasks, generations, shot_generations, generation_variants, timelines**; `useAgentSession` adds a channel on **timeline_agent_sessions** (UPDATE, id filter).
- Polling: React Query `refetchInterval` drives task lists (3–5 s), payment verification (2 s for ≤30 s), source-image change detection (60 s), timeline JSON/registry (30 s), stale-variant check (15 s), plus `useSmartPolling` which polls up to 15 s only while realtime is unhealthy.
- Timeline writes for the travel/segment UI go through RPCs `batch_update_timeline_frames`, `reorder_normalized`, `delete_and_normalize`, `unposition_and_normalize`, `add_generation_to_shot`; the video editor writes through the **append service** (`POST /v1/timelines/:id/config-replaced`, `/app-bookmark`, `/app-divergence`) + `timeline_checkpoints`/`extension_*` tables directly.
- Storage buckets: `image_uploads` (public, media), `temporary` (private 500 MB), `training-data` (public), `lora_files` (public), `timeline-assets` (made public 2026-04), `render-outputs` (private, user-folder RLS).
- The **current** Supabase project lives in `reigh-app/supabase/` (config.toml, migrations, functions, tests). The top-level `supabase/` at the workspace root is **stale** (only an empty `functions/` dir; ~3 mo old) — do not use it.
- Tables written by *workers* via edge functions (`complete_task`, `claim-next-task`, `update-task-status`, …) are listed in §7 but are part of the same backend contract; a replacement must keep serving them to the worker fleet (or migrate workers too).

---

## 2. App architecture

### 2.1 Build & runtime
- Vite React SPA; entry `src/app/main.tsx` → `bootstrap.tsx` (`initializeAppEnvironment`, `renderApp`); router = `react-router-dom` v6 (`src/app/routes.tsx`). `railway.toml` + `Dockerfile` + `start:railway` (`npm run build && vite preview`) — no SSR, no server-rendered routes.
- State: TanStack Query v5 (`src/app/providers/queryClient.ts`), zustand for panes, React context for auth/settings.
- Env keys (names only; values redacted): `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_REIGH_APPEND_SERVICE_URL`, `VITE_STRIPE_PUBLISHABLE_KEY`, `VITE_API_TARGET_URL` (media URL base in dev), `VITE_APP_ENV`, `VITE_DEV_USER_EMAIL`, `VITE_DEV_USER_PASSWORD`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (server-side only), `DATABASE_URL` (server-side only).

### 2.2 Routes (`src/app/routes.tsx`)
| Route | Page | Auth needed |
|---|---|---|
| `/` | Home (`HomeWithAuthRedirect` → redirect to `/tools` if session) | public |
| `/home` | HomePage | public |
| `/payments/success`, `/payments/cancel` | Payment pages (Stripe return) | public (reads query params) |
| `/share/:shareId` | SharePage (public share of a shot/final video) | **public** |
| `/blog`, `/blog/:slug` | Blog | public |
| `/tools` | `DefaultToolRedirect` | protected (Layout) |
| `/tools/image-generation`, `/tools/travel-between-images`, `/tools/character-animate`, `/tools/join-clips`, `/tools/edit-images`, `/tools/edit-video`, `/tools/video-editor`, `/tools/training-data-helper`, `/shots`, `/art` | Tool pages inside `<Layout />` | protected (Layout) |
| `/tools/video-editor/harness` | Extension harness (DEV only) | protected |

`Layout.tsx` gates all `/tools/*` + `/shots` + `/art` behind `useAuth()` (`isAuthenticated`) with `<Navigate to="/home">`; DEV `isLocalModeSession` exemption (no backend).

### 2.3 Supabase client layer
- `src/integrations/supabase/client.ts` — `initializeSupabase()` at bootstrap; `getSupabaseClient()` throws if uninitialized. `getSupabaseClientResult()` non-throwing.
- `createSupabaseClient.ts` — client factory with **cached access token** fetch shim (see Key facts) and auth state listener that re-caches `session.access_token`.
- `src/integrations/supabase/functions/invokeSupabaseEdgeFunction.ts` — POST to `${SUPABASE_URL}/functions/v1/<name>` with `Authorization: Bearer <stored token>` + `apikey: anon`, 20 s default timeout, abort composition.
- `src/integrations/supabase/repositories/*` — typed data-access repository layer (generations, tasks, variants, resources, derived items, segment persistence).
- DB types: `src/integrations/supabase/types.ts` (generated, full) and `databasePublicTypes.ts` (client-facing subset).
- `fetchWithTimeout.ts` — global fetch shim; skips timeout for `/functions/v1/` and `/storage/v1/object/` URLs.

---

## 3. Per-feature data-access inventory

### 3.1 Projects & onboarding
| Action | Call | File |
|---|---|---|
| List/create projects | `projects.select('*').eq('user_id', user.id).order(created_at desc)`; `projects.insert({name, user_id})` | `src/shared/hooks/projects/useProjectCRUD.ts:90,98,146` |
| Update project | `projects.update(dbUpdates).eq('id', projectId).eq('user_id', user.id)` | `useProjectCRUD.ts:195` |
| Delete project | edge fn **`delete-project`** `{projectId}` → RPC `delete_project_with_extended_timeout` | `useProjectCRUD.ts:225`; `supabase/functions/delete-project/index.ts` |
| Project settings read | `projects.select('settings').eq('id', projectId)` | `src/shared/lib/projectSettingsInheritance.ts:69`; `toolSettingsScopes.ts:41` |
| Project resolution (aspect ratio) | `projects.select('aspect_ratio').eq('id', projectId)` | `src/shared/lib/taskCreation/resolution.ts:8` |
| Onboarding template | RPC `copy_onboarding_template {target_project_id, target_shot_id}`; shot lookup `shots.select('id').eq('project_id', …).eq('name','Getting Started')` | `src/features/projects/services/projectSetupRepository.ts:24,50`; `src/app/hooks/useOnboardingFlow.ts:39` |
| User record ensure | RPC `create_user_record_if_not_exists` | `projectSetupRepository.ts:83` |
| Project settings write | RPC `update_tool_settings_atomic {p_table_name, p_id, p_tool_id, p_settings}` (scopes: `users`/`projects`/`shots`) | `src/shared/settings/runtime/toolSettingsWriteService.ts:50` |

### 3.2 Shots & the shot timeline (travel-between-images)
Reads:
- Shots list: `shots.select('*').eq('project_id').order('position asc')`; counts via `generations` head-counts (`useShotsQueries.ts:35,144-155`).
- **Timeline read (the main one)**: `shot_generations.select('id, generation_id, timeline_frame, metadata, generation:generations!shot_generations_generation_id_generations_id_fk(id, location, thumbnail_url, type, created_at, starred, name, based_on, params, primary_variant_id, primary_variant:generation_variants!generations_primary_variant_id_fkey(location, thumbnail_url))').eq('shot_id', …).order('timeline_frame asc')` — `src/shared/hooks/shots/useShotImages.ts:60-75`.
- Live timeline (segments view): `shot_generations.select('id, generation_id, timeline_frame').eq('shot_id').gte('timeline_frame', 0)` — `src/shared/hooks/segments/segmentOutputsQueries.ts:66`.
- Segment metadata: `shot_generations.select('metadata').eq('id', …)` (many call sites: `usePairMetadata.ts`, `useSegmentMutations.ts`, `useShotGenerationMetadata.ts`, `timelineTrailingEndpointPersistence.ts`, `useFrameCountUpdater.ts`).
- Shot stats: `shot_statistics.select('shot_id, video_count, final_video_count').eq('project_id', …)` + `shots.select('id, settings')` — `src/shared/hooks/projects/useProjectVideoCountsCache.ts:50`.
- Shot settings: `shots.select('settings').eq('id', …)` (`useShotVideoSettings.ts:30`); aspect ratio: `shots.select('aspect_ratio, settings')` (`useVideoRegenerateMode.ts:185`, `externalImageDrop.ts:93`).

Writes:
- Create shot: RPC `insert_shot_at_position {p_project_id, p_shot_name, p_position}`; then `shots.update({aspect_ratio})` (`useShotsCrud.ts:118,134`).
- Duplicate shot: RPC `duplicate_shot {original_shot_id, project_id}`; with videos: `duplicate_shot_with_videos {original_shot_id, project_id}`; re-fetch `shots.select().eq('id', …)`.
- Rename/position: `shots.update({name})` (`useShotUpdates.ts:53`); `shots.update({position}).eq('id').eq('project_id')` batch (`useShotsCrud.ts:290`).
- Delete shot: `shots.delete().eq('id', shotId)` (`useShotsCrud.ts:30`).
- Add generation to shot: RPC `add_generation_to_shot {p_shot_id, p_generation_id, p_with_position:true}`; fallback direct `shot_generations.insert({shot_id, generation_id, timeline_frame})` (`addImageToShotHelpers.ts:28,48,85`).
- Create shot with generations: RPC `create_shot_with_generations {p_project_id, p_shot_name, p_generation_ids}` (`useShotCreation.ts:29`).
- Timeline drag/move: RPC `batch_update_timeline_frames {p_updates:[{shot_generation_id, timeline_frame, metadata}]}` (`src/shared/lib/timelineFrameBatchPersist.ts:149`); single update `shot_generations.update({timeline_frame}).eq('id').eq('shot_id')` (`timelineMutationService.ts:67`); `shot_generations.update({timeline_frame:null})` to unposition (`useShotGenerationMutations.ts:147`); per-row `update({timeline_frame}).eq('shot_id').eq('generation_id')` (`useShotGenerationMutations.ts:262`); RPC `update_single_timeline_frame` exists in types but the batch RPC is the hot path.
- Reorder: RPC `reorder_normalized {p_shot_id, p_new_order: string[]}`; delete slot: `delete_and_normalize {p_shot_id, p_shot_generation_id}`; unposition: `unposition_and_normalize` (`useTimelineCore.ts:199,248,267`).
- Segment metadata writes: `shot_generations.update({metadata}).eq('id', …)` — `useSegmentMutations.ts:98,231,274`, `useTimelineCore.enhancedPromptOperations.ts:63`, `useTimelineCore.pairOperations.ts:68,132`, `useShotGenerationMetadata.ts:99`, `useSegmentPromptMetadata.ts:107,166`, `timelineTrailingEndpointPersistence.ts:73`, `useFrameCountUpdater.ts:177`, `generateVideoService.ts:191`.
- Segment deletion (child generations): read `generations.select('id, type, parent_generation_id, location, params, primary_variant_id, pair_shot_generation_id')`, siblings by `parent_generation_id`, then `generations.delete().in('id', ids)` (`segmentDeletionService.ts:25-89`, `useSegmentDeletion.ts:31-73`).
- Demote orphaned variants: RPC `demote_orphaned_video_variants {p_shot_id}` (`useDemoteOrphanedVariants.ts:44`).
- Ensure parent generation: RPC `ensure_shot_parent_generation {p_shot_id, p_project_id}` (`src/shared/lib/tasks/shotParentGeneration.ts:31`).
- Shot pair prompts (worker): edge fn `update-shot-pair-prompts {shot_id, task_id?, enhanced_prompts[]}` writes `shot_generations.metadata.enhanced_prompt`.

### 3.3 Generations, variants & the gallery
| Action | Call | File |
|---|---|---|
| Gallery read (variants) | `generation_variants.select(id, generation_id, …).eq('project_id').order(created_at desc)` + exact head count | `src/shared/hooks/projects/useProjectGenerations.ts:175,210` |
| Gallery read (generations) | `generations.select(id, location, …).eq('project_id')` + head count; `not('location','is',null)` filters | `useProjectGenerations.ts:300,322` |
| Single generation | `generations.select('*').eq('id').maybeSingle()` | `src/integrations/supabase/repositories/generationRepository.ts:14,39` |
| Create generation + original variant (external upload) | `generations.insert({location, thumbnail_url, type, project_id, params})` then `generation_variants.insert({generation_id, location, thumbnail_url, is_primary:true, variant_type:'original', name:'Original', params})` | `generationMutationsRepository.ts:136-160`; also `EditImagesPage.tsx:90`, `EditVideoPage.tsx:138`, `createGenerationFromFile.ts:157` |
| Star / unstar | `generations.update({starred}).eq('id').eq('project_id')` | `generationMutationsRepository.ts:177` |
| Delete generation / variant | `generations.delete().eq('id').eq('project_id')`; `generation_variants.delete().eq('id').eq('generation_id').neq('variant_type','original')` | `generationMutationsRepository.ts:193,209` |
| Variants list | `generation_variants.select('*').eq('generation_id').order(created_at desc)` | `src/shared/hooks/variants/useVariants.ts:82` |
| Make primary | `generation_variants.update({is_primary:true}).eq('id')` (trigger un-sets old primary) | `useVariants.ts:146,215` |
| Variant viewed | `generation_variants.update({viewed_at}).eq('id').is('viewed_at', null)`; mark-all by `generation_id` | `useMarkVariantViewed.ts:143,179` |
| Variant star | `generation_variants.update({starred}).eq('id')` | `useToggleVariantStar.ts:27` |
| Delete variant | `generation_variants.delete().eq('id')` | `useVariants.ts:258` |
| Derived items (media lightbox) | `generations.select(...).eq('based_on', src)` + `generation_variants.select(...).eq('generation_id').in('variant_type', EDIT_VARIANT_TYPES).eq('is_primary', false)`; counts via `calculateDerivedCountsSafe` | `src/integrations/supabase/repositories/derivedItemsRepository.ts:69-89` |
| Make-main variant | `generation_variants.insert({generation_id, location, …})` then `generations.update({location, thumbnail_url})` | `useMakeMainVariant.ts:83,107` |
| Duplicate as new generation | RPC `duplicate_as_new_generation {p_shot_id, p_generation_id, p_project_id}` | `useDuplicateAsNewGeneration.ts:38` |
| Trim save | read `generation_variants.select('params').eq('id')`; insert trimmed variant; update `generations.update({location, thumbnail_url})` | `useTrimSave.ts:136,168,191` |
| Reposition (image transform) | insert `generations` + `generation_variants` (new primary) | `useRepositionVariantSave.ts:177-216` |
| Local media (pending upload) | `local_media_handles.insert({user_id, project_id, …})`; then `generations.insert({location:null, …})`; materialize: `generations.update(patch)` + `generation_variants.insert` | `createGenerationFromFile.ts:114-160`, `materializeLocalGeneration.ts:84-110` |
| Thumbnail update | `generations.update({thumbnail_url}).eq('id')` | `videoThumbnailGenerator.ts:101` |
| Task→generation lookup | `generations.select('*').eq('location', task.outputLocation).eq('project_id')`; fallback `.filter('tasks','cs', JSON.stringify([task.id]))` | `useImageGeneration.ts:38-61`, `useVideoGenerations.ts:83-106` |

### 3.4 Tasks
Reads (direct PostgREST, not the edge functions):
- `tasks.select('*').eq('id').eq('project_id')` (`taskRepository.ts:11`, `useTasks.ts:83`); `.eq('id').maybeSingle()` (`taskDataService.ts:18`).
- Pending tasks: `tasks.select('id, task_type, params, status, created_at, updated_at, project_id').eq('project_id').in('status',['Queued','In Progress'])` — 5 s poll (`usePendingGenerationTasks.ts:96`), 3 s poll (`usePendingSegmentTasks.ts:83`, `useActiveTaskClips.ts:128`).
- Paginated task log: `tasks.select('*',{count:'exact'}).is('params->orchestrator_task_id_ref', null).in('task_type', visible)` + filter page (`paginatedTaskRepository.ts:49,77`, `taskLogPipeline.ts:217`).
- Status counts: head-counts on `tasks` by status (Queued/In Progress/Failed…) via `useTaskStatusCounts.ts:181-207`.
- Subtasks for cancel: `tasks.select('id, params').eq('project_id').in('status',['Queued'])`; orchestrator child lookup by `orchestrator_task_id_ref` in params (`useTaskCancellation.ts:27-104`).
- Task type config: `task_types.select('id,name,content_type,tool_type,display_name,category,is_visible,supports_progress').eq('is_active', true)` (`useTaskType.ts:18,49`).
- Task error: `tasks.select('error_message, task_type').eq('id')` (`useTaskErrorDisplay.ts:37`).
- Credits per task: `credits_ledger.select('task_id, amount, created_at').in('task_id').eq('type','spend')` (`taskLogPipeline.ts:15`).
- Final-video section controller: `tasks.select('id, status, params').in('task_type', ['join_clips_orchestrator','travel_stitch']).eq('project_id')` — 3 s poll (`useFinalVideoSectionController.ts:206,226`).

Writes:
- **Create task**: POST edge fn **`create-task`** `{family, project_id, input, idempotency_key, materialized_inputs?}` (direct fetch to `/functions/v1/create-task`, 15 s timeout, 2 attempts, idempotent) — `src/shared/lib/taskCreation/createTask.ts:194`. Before it, local generations are uploaded to storage (`materializeLocalGeneration`).
- **Cancel task**: edge fn **`update-task-status`** `{task_id, status:'Cancelled', …}` (+ cascading subtask cancel, orchestrator billing handling) — `useTaskCancellation.ts:9`, `useTaskPlaceholder.ts:86`.
- Task status is otherwise written **only by workers** via edge functions (`complete_task`, `update-task-status`, `claim-next-task`).

### 3.5 Resources & presets
- Public presets: `resources.select('*').eq('type', type).eq('is_public', true)` paged (`useResources.ts:167`).
- Owned resources: `.eq('user_id', user.id).eq('type', type)` (`useResources.ts:224`).
- Create/update/delete resource: `resources.insert(...).select().single()`; `resources.update({metadata, is_public}).eq('id').eq('user_id')`; `resources.delete().eq('id').eq('user_id')` (`useResources.ts:279-420`).
- Featured motion presets: `resources.select('*').in('id', featuredPresetIds)` (`useMotionPresets.ts:30`, `useMotionControlPresetState.ts:106`).
- Preset by id: `resources.select('*').eq('id').maybeSingle()` (`presetResourcesRepository.ts:25`, `VideoTravelDetails.tsx:92`).
- Reference resource ↔ generation migration: `resources.update({generation_id, metadata})` + `generations.insert/delete` (`useGenerationBackfillMigration.ts:104-146`, `referenceDomainService.ts:230-260`).

### 3.6 Users, settings, tokens
- User profile: `users.select('username').eq('id')` (`useGlobalHeaderAuth.ts:10`); `users.select('username').eq('id').single()` (`ReferralModal.tsx:51`); `users.select('name').eq('id').single()` (`useLoraFormState.ts:101`).
- User settings JSON: `users.select('settings').eq('id').single()` — `UserSettingsContext.tsx:58`, `useUserUIState.ts:317`, `toolSettingsScopes.ts:32`, `useProjectGenerationModesCache.ts:39`.
- Onboarding flag: `users.select('onboarding_completed').eq('id')`; `users.update({onboarding_completed:true})` (`useOnboarding.ts:23,62`).
- Legacy api_keys JSON: `users.select('api_keys').eq('id')`; `users.upsert({id, api_keys}, {onConflict:'id'})` (`useApiKeys.ts:21-45`).
- API tokens (PAT): `user_api_tokens.select('*').eq('user_id').order(created_at desc)`; edge fns **`generate-pat`** `{label}` and **`revoke-pat`** `{tokenId}` (`useApiTokens.ts:31,56,74`).
- External API keys: RPC `save_external_api_key {p_service, p_key_value, p_metadata}` / `delete_external_api_key {p_service}`; read `external_api_keys.select('id, service, metadata, created_at, updated_at').eq('user_id').eq('service')` (`src/shared/services/externalApiKeys/repository.ts:20-60`).
- Referral stats: `referral_stats.select('total_visits, successful_referrals').eq('username', …)` / `.eq('id', …)` (`useGlobalHeaderAuth.ts:87`, `ReferralModal.tsx:74`).
- Referral tracking RPCs: `track_referral_visit {p_referrer_username, p_visitor_fingerprint, p_session_id}` (`useReferralTracking.ts:76`); `create_referral_from_session {p_session_id, p_fingerprint}` (`useAuthReferralFinalize.ts:52`).

### 3.7 Sharing (public)
- Create share: read generation (`generations` or `shot_final_videos` by id+shot_id), task, shot + `shot_generations` timeline (images array), creator `users` row; insert `shared_generations {share_slug, task_id?, generation_id, creator_id, creator_username/name/avatar_url, cached_generation_data, cached_task_data, shot_id}` with slug retry on unique violation — `src/shared/hooks/useShareGeneration.ts:111-286`.
- Existing slug: `shared_generations.select('share_slug').eq('generation_id').eq('creator_id')`.
- Public view (`/share/:shareId`): RPC `get_shared_shot_data {share_slug_param}` → `{shot_id, shot_name, generation, images, settings, creator_id, view_count, creator_username/name/avatar_url}`; fire-and-forget RPC `increment_share_view_count {share_slug_param}` — `src/pages/share/hooks/useSharePageData.ts:63-81`.
- Copy from share: RPC `copy_shot_from_share {share_slug_param, target_project_id}` (`useShareActions.ts:92`).

### 3.8 Training data helper
- `training_data_batches` CRUD (select/insert/update/delete) — `useTrainingDataBatches.ts:19-94`.
- `training_data` CRUD: select all (by batch), insert `{user_id, batch_id, original_filename, storage_location, duration, metadata}`, select `duration`, delete; storage upload to `training-data` bucket, `storage.remove()` on delete, `createSignedUrl(loc, 3600)` for playback — `useTrainingData.ts:18-104`, `useTrainingDataUpload.ts:55-100`, `useVideoUrlCache.ts:35`, `removeTrainingVideoFromStorage` (`useTrainingData.ts:110`).
- `training_data_segments` CRUD (insert/update/delete, `start_time`/`end_time` rounded) — `useTrainingData.ts:59-95`.

### 3.9 Video editor (extension platform + timeline)
Reads:
- Timelines list: `timelines.select('*').eq('project_id').order(updated_at desc)`; insert `{name, project_id}`; update `{name, updated_at}`; delete — `useReighTimelinesList.ts:16-80`.
- **Timeline state (the durable doc)**: `timelines.select('config, config_version').eq('id').maybeSingle()` (`SupabaseDataProvider.loadTimeline`); asset registry `timelines.select('asset_registry')` (`loadAssetRegistry`); keep-both snapshot `timelines.select('config, config_version, asset_registry')`.
- **Event log head**: `timeline_events.select('version, hash, event_id').eq('timeline_id').order('version desc').limit(1).maybeSingle()` (`loadDbHead`).
- Sync bookmarks: `sync_bookmarks.select(...).eq('timeline_id').eq('spoke','app')`; local bookmarks in **IndexedDB** (`syncLedgerIndexedDb.ts`).
- Checkpoints: `timeline_checkpoints` insert/select/delete (auto-cleanup: keep 30 non-manual, 24 h retention) — `SupabaseDataProvider.saveCheckpoint/loadCheckpoints`.
- Extension persistence: `extension_install_state` (sentinel row `extension_id='__reigh_snapshot__'`, metadata), `extension_settings` (per-extension rows), `extension_proposals` (insert/delete/upsert), all scoped `user_id + timeline_id` — `SupabaseDataProvider.ts:355-600`.
- Effects catalog: `effects` CRUD `.eq('user_id')` (`useReighEffectsCatalog.ts:17-66`).
- Generation asset resolution: `generations.select('*').eq('id')` via repository, storage `getPublicUrl`/`createSignedUrl` (signed URL TTL 1 h), `parseSupabaseStorageUrl` handles `/storage/v1/object/(public|sign)/<bucket>/<path>` — `generationAssetResolver.ts`.
- Agent sessions: `timeline_agent_sessions` select by id (read), **insert** `{timeline_id, user_id, status:'waiting_user', turns:[], model:'groq', proposal_policy}` (useCreateSession), realtime UPDATE subscription; edge fn **`ai-timeline-agent`** `{session_id, user_message?, selected_clips?, proposal_policy?}` — `useAgentSession.ts:254-323`.
- Stale variants: `generations.select('id, primary_variant_id, primary_variant:...')` 15 s poll (`useStaleVariants.ts`, `staleVariantRepository.ts`).
- Timeline JSON poll: `loadTimelineJsonFromProvider` + `loadAssetRegistry` with `refetchInterval: 30_000` (`useTimelineQueries.ts:14-23`).

Writes (beyond the tables above):
- **saveTimeline / syncTimeline → append service** (NOT direct PostgREST):
  - `POST {appendBase}/v1/timelines/{id}/config-replaced` body `{config, asset_registry?, expected_version, actor:{type:'human', id:userId}, source:'editor_save'}`; 409 → `TimelineVersionConflictError`; response `{config_version, db_head:{version,hash,event_id}}`.
  - `POST .../app-bookmark` `{db_head}` → `{bookmark}`.
  - `POST .../app-divergence` `{config, asset_registry, db_head, source:'editor_sync', artifact_pointer:{kind:'indexeddb', id, created_at}}`.
  - Bearer = user JWT (`getUserJwt`); base from `VITE_REIGH_APPEND_SERVICE_URL`; throws at construction if unset — `SupabaseDataProvider.ts:166-172,649-838`.
- `timelines` materialized row is written by the append service (which also appends `timeline_events` and updates `sync_bookmarks`); realtime on `timelines` then broadcasts to clients. Edge functions use the same service via `_shared/reighAppendService.ts` (`appendTimelineConfigViaService`, `createTimelineViaService` at `/v1/timelines/create-with-config`).
- Asset registry upsert: RPC `upsert_asset_registry_entry {p_timeline_id, p_asset_id, p_entry}` (also used by `complete_task` for worker-produced assets) — `SupabaseDataProvider.registerAsset:1088`; `complete_task/handler.ts`.
- Asset upload: `storage.from('timeline-assets').upload(userId/timelineId/<ts>-<name>, file)` + `registerAsset` — `SupabaseDataProvider.uploadAsset`.
- Asset URL: `storage.from('timeline-assets').getPublicUrl(path)` (`resolveAssetUrl`).

### 3.10 Realtime & polling summary
- **RealtimeConnection** (`src/shared/realtime/RealtimeConnection.ts`): one channel per project `task-updates:<projectId>`; events:
  - `tasks`: INSERT, UPDATE (filter `project_id=eq.<projectId>`)
  - `generations`: INSERT, UPDATE, DELETE (filter project_id)
  - `shot_generations`: INSERT, UPDATE, DELETE (no filter)
  - `generation_variants`: INSERT, UPDATE, DELETE (no filter)
  - `timelines`: INSERT, UPDATE, DELETE (filter project_id)
  - Events feed `DataFreshnessManager` → smart polling.
- `useAgentSession`: channel `timeline-agent-session:<sessionId>:<rand>` on `timeline_agent_sessions` UPDATE (filter `id=eq.<sessionId>`).
- Polling loops: payment verification 2 s (max 30 s) — `usePaymentVerification.ts:13`; pending generation tasks 5 s; pending segment tasks 3 s; active task clips 5 s; final-video controller 3 s; source-image changes 60 s; stale variants 15 s; timeline JSON/registry 30 s; `useSmartPolling` fallback (5 s min → 15 s max, 30 s freshness, mobile ×2) when realtime down; `IncomingTasksContext` staleness sweep; debug polling (task-count head queries) in `debugPolling.ts`.
- Optimistic updates: timeline drag writes are optimistic with `batch_update_timeline_frames` RPC + timeout diagnostics re-read (`timelineFrameBatchPersist.ts`); settings writes are debounced/queued (`toolSettingsWriteService.ts`).

### 3.11 Logging
- Client logs: RPC `func_insert_logs_batch {logs}` (batched) — `src/shared/lib/logger.ts:178`. Server logs: `system_logs` table written by edge functions.

---

## 4. Auth model

- **Provider: Supabase GoTrue; sign-in = Discord OAuth only.** `supabase.auth.signInWithOAuth({provider:'discord', options:{redirectTo: window.location.origin}})` — `src/pages/Home/hooks/useDiscordSignIn.ts:59`. Password sign-in exists **only for dev auto-login** (`VITE_DEV_USER_EMAIL/PASSWORD`, `signInWithPassword`) — `src/integrations/supabase/support/dev/autoLogin.ts:35`.
- Session restore: `useOAuthHashSessionRestore` parses the OAuth `#access_token` fragment, calls `auth.setSession(...)`, clears the hash, flags `oauthInProgress` in localStorage; `useStandaloneAuthRedirect` + `useHomeAuthSubscription` redirect to `/tools` on SIGNED_IN; referral finalize on OAuth return (`create_referral_from_session`).
- Session storage: localStorage `sb-<ref>-auth-token`; `persistSession:true, autoRefreshToken:true, detectSessionInUrl:true`. Token read synchronously for all data calls via `readAccessTokenFromStorage()` (bypasses `navigator.locks`).
- **Identity in queries: `user.id`** (`auth.getUser()` / session user) drives `.eq('user_id', …)`, `.eq('id', user.id)` filters, project ownership, and RLS. No roles/groups beyond Supabase auth; admin = service-role key server-side only.
- Protected routes: `Layout` redirect to `/home` (see §2.2); `AuthGate` blocks render until `isLoading` false; `requireSession`/`requireUserFromSession` throw `Not authenticated` for repo-layer calls.
- Sign-out: `supabase().auth.signOut()` (`SettingsModal.tsx:142`).
- Public (no auth) surfaces: `/`, `/home`, `/blog*`, `/payments/*`, `/share/:shareId` (share RPCs are anon-allowed), marketing pages.
- Edge functions accept **JWT (user), service-role key, and PAT** (personal access token via `user_api_tokens`) depending on the function; PAT used by workers (`claim-next-task`, `update-task-status`, …). Auth manager (`AuthStateManager`) centralizes `onAuthStateChange` (debounced 150 ms in `AuthContext`).

---

## 5. Billing UI data needs

- **Balance**: `users.select('credits').eq('id', user.id).single()` → `{balance, currency:'USD'}`; React Query key `creditQueryKeys.balance`, stale 5 min — `src/shared/hooks/billing/useCredits.ts:56-73`.
- **Ledger (non-spend)**: `credits_ledger.select('*',{count:'exact',head:true}).eq('user_id').neq('type','spend')` + paged `.select('*')…range(offset, offset+limit-1)`; entry shape `{id, user_id, type: 'manual'|'stripe'|'spend'|'refund'|'auto_topup', amount, description?, task_id?, metadata?, created_at}` — `useCredits.ts:82-99`; spend rows per task in task log (`taskLogPipeline.ts:15`).
- **Purchase**: edge fn **`stripe-checkout`** `{amount, autoTopupEnabled?, autoTopupAmount?, autoTopupThreshold?}` → `{checkoutUrl?}`; redirect to Stripe; return URL is `/payments/success?session_id=…&amount=…` — `useCredits.ts:212`.
- **Payment verification**: `/payments/success` polls query-invalidation of balance+ledger every 2 s for ≤30 s (`usePaymentVerification.ts`).
- **Auto top-up prefs**: `users.select('auto_topup_enabled, auto_topup_amount, auto_topup_threshold, auto_topup_last_triggered, auto_topup_setup_completed').eq('id')` (amounts in cents; **Stripe IDs never exposed client-side** — column privileges revoked) — `useAutoTopup.ts:49-58`.
- **Update auto top-up**: edge fn **`setup-auto-topup`** `{autoTopupEnabled, autoTopupAmount, autoTopupThreshold}` (dollars→cents server-side).
- **Welcome bonus**: edge fn **`grant-credits`** `{userId, amount, description?, isWelcomeBonus}` (welcome bonus = fixed $5; admin grants require service role).
- Backing server-side machinery (no direct UI calls): `stripe-webhook` (Stripe → `credits_ledger` insert + `users.credits` update), `complete-auto-topup-setup`, `trigger-auto-topup`, `process-auto-topup` (service-role), credit-protection triggers, `user_credit_balance` view.
- Credits display surfaces: `CreditsManagement` (Settings modal; `AddCreditsSection`, `TransactionsTable`, `TaskLogPanel`), GlobalHeader credits pill.

---

## 6. Timeline data shape

Two distinct "timelines":

### 6.1 Shot timeline (travel-between-images / segments) — relational
Model: `shots` (row) → `shot_generations` (positioned slot rows: `id, shot_id, generation_id, timeline_frame (int≥0, nullable), metadata jsonb, position, updated_at`) → `generations` (media rows: `location, thumbnail_url, type, params, starred, based_on, is_child, parent_generation_id, child_order, pair_shot_generation_id, primary_variant_id, tasks jsonb, shot_data jsonb`) → `generation_variants` (edit variants; `is_primary` determines display URL). Views used: `shot_final_videos`, `shot_statistics`, `shot_generations_with_computed_position`.
- The timeline view consumes `useTimelineImages` (positioned images sorted by `timeline_frame`), `useUnpositionedImages`, `fetchLiveTimeline` (segments ≥ frame 0), pair metadata for travel segments (`metadata.pair_*`, `metadata.enhanced_prompt`).
- Mutations are normalized by RPCs (`add_generation_to_shot` with `p_with_position`, `reorder_normalized`, `delete_and_normalize`, `unposition_and_normalize`, `batch_update_timeline_frames`, `demote_orphaned_video_variants`, `duplicate_shot*`, `create_shot_with_generations`) rather than raw position math.
- URLs in `location`/`thumbnail_url` are public storage URLs (`image_uploads` bucket) or absolute HTTPS.

### 6.2 Video editor timeline — JSON document (append-log backed)
Shape (shared vendor schema `reigh-app/vendor/timeline-schema/typescript/src/schemas.ts`; also `src/tools/video-editor/types/index.ts`):
```
TimelineConfig { theme?, clips: TimelineClip[], tracks?: TrackDefinition[],
                 pinnedShotGroups?: PinnedShotGroup[], theme_overrides?,
                 generation_defaults?, output?: {resolution, fps, file, background?, background_scale?} }
TimelineClip  { source_uuid?, clipType?, asset?, from?, to?, speed?, hold?, volume?,
                x/y/width/height?, crop*, opacity?, text?, entrance?, exit?,
                continuous?, transition?, effects?, params?, generation?, app?, pool_id?, clip_order? }
TrackDefinition { id, kind:'visual'|'audio', label, scale?, fit?, opacity?, volume?, muted?, blendMode?, app? }
AssetRegistry  { assets: { [assetKey]: AssetEntry } }
AssetEntry     { file?, url?, etag?, content_sha256?, url_expires_at?, type?, duration?,
                 resolution?, fps?, generationId?, variantId?, thumbnailUrl? }
```
- Persisted in `timelines.config` (jsonb) + `timelines.config_version` (int, CAS) + `timelines.asset_registry` (jsonb), with `timeline_events` (append log: `version, hash, event_id, timeline_id`) as the source of truth head; `sync_bookmarks` (spoke `'app'`/`'local'`, hub/spoke version+hash+event_id) reconcile browser (IndexedDB) vs DB; `timeline_checkpoints` (config snapshots, `trigger_type` manual|auto, 30-row/24 h retention); `extension_install_state` / `extension_settings` / `extension_proposals` (per user+timeline extension state).
- Timeline **load** reads `timelines` + `timeline_events` head directly via PostgREST; timeline **save** goes through the append service (CAS `expected_version`; 409 → conflict; response carries new `config_version` + `db_head`). This is the single most important contract for a replacement backend.

---

## 7. Edge-function inventory (`reigh-app/supabase/functions/*`)

All functions: Deno, `serve()`, JSON responses, auth via `_shared/auth.ts` (JWT / service-role / PAT), shared helpers in `_shared/` (edgeHandler, requestGuards, taskActorPolicy, rateLimit, billing, systemLogger, reighAppendService). Tables listed are the ones each function touches.

### 7.1 Frontend-called (the browser contract)
| Function | Input | Output | Tables touched | Caller |
|---|---|---|---|---|
| `create-task` | `{family, project_id, input, idempotency_key?, materialized_inputs?[]}` | `{task_id} | {task_ids[], status:'Task queued', deduplicated?}` (idempotent; 400/403/429/500) | `tasks` (insert, dedup lookup), `projects` (ownership/aspect), `rate_limits` | `createTask.ts:194` (direct fetch) |
| `ai-prompt` | `{task, prompt, ...}` (`enhance_segment_prompt` etc.) | enhanced prompt text | none (Fireworks/OpenAI LLM) | `submitSegmentTask.ts:326` |
| `ai-voice-prompt` | JSON `{textInstructions, task:'transcribe_and_write', context, example, existingValue}` or multipart `audio` | rewritten prompt text | none (Groq STT + LLM) | `useAIInputTextPopover.ts:63`, `useVoiceRecording.ts:140` |
| `ai-timeline-agent` | `{session_id, user_message?, selected_clips?, proposal_policy?}` | agent turn result (turns appended, proposals or mutations) | `timeline_agent_sessions` (read/update), `timelines`/`timeline_events` via append service + tools, `tasks` (via `banodoco_render_timeline` enqueue), `effects`? | `useAgentSession.ts:380` |
| `ai-generate-effect` | `{prompt, name?, category?('entrance'|'exit'|'continuous'), ...}` | `{effect: {id, code, ...}}` | `effects` (insert) | `EffectCreatorPanel.tsx:303` |
| `ai-generate-sequence` | `{prompt, ...}` | `{drafts: [{clipType, hold, params}]}` (+ classifier) | none (Anthropic) | `sequenceGenerationService.ts:82` |
| `ai-generate-sequence-component` | `{prompt, existingComponent?...}` | generated React component TSX + manifest | none | `sequenceGenerationService.ts:265` |
| `trim-video` | `{video_url, start_time, end_time, project_id, user_id, generation_id?, variant_id?, test_mode?}` | `{video_url, duration, format}` | storage `image_uploads` (upload), `generation_variants` (update when ids given) | `useTrimSave.ts:97` |
| `huggingface-upload` | multipart: `loraStoragePaths`/`loraStoragePath`, `loraDetails`, `sampleVideos`, `repoName`, `isPrivate` | `{success, repoId?, repoUrl?, loraUrl?, highNoiseUrl?, lowNoiseUrl?, videoUrls?}` | storage `temporary` (read + cleanup) | `huggingFaceUploadRepository.ts:39` |
| `stripe-checkout` | `{amount, autoTopupEnabled?, autoTopupAmount?, autoTopupThreshold?}` | `{checkoutUrl?}` | `users` (read; Stripe session metadata), `rate_limits` | `useCredits.ts:212` |
| `setup-auto-topup` | `{autoTopupEnabled, autoTopupAmount, autoTopupThreshold}` | `{success}` | `users` (auto_topup_* columns) | `useAutoTopup.ts:83` |
| `grant-credits` | `{userId, amount?, description?, isWelcomeBonus?}` | transaction details | `users` (credits), `credits_ledger` (insert) | `useCredits.ts:213` (admin/welcome) |
| `delete-project` | `{projectId}` | `{success}` | RPC `delete_project_with_extended_timeout` (cascade), `rate_limits` | `useProjectCRUD.ts:225` |
| `update-task-status` | `{task_id, status, output_location?, error_details?, reset_generation_started_at?, clear_worker?, attempts?}` | status update result | `tasks` (status transition + cascades), `credits_ledger`/billing on cancel (orchestrator), `workers` | `useTaskCancellation.ts:9`, `useTaskPlaceholder.ts:86` |
| `generate-pat` | `{label?}` | `{token}` (32-char) | `user_api_tokens` (insert) | `useApiTokens.ts:56` |
| `revoke-pat` | `{tokenId}` | `{success}` | `user_api_tokens` (delete) | `useApiTokens.ts:74` |

### 7.2 Worker/orchestrator-facing (must keep serving the worker fleet)
| Function | Input → Output | Tables |
|---|---|---|
| `claim-next-task` | `{worker_id?, run_type?('gpu'|'api'|'banodoco-worker'), worker_pool?, task_types?, same_model_only?, max_task_wait_minutes?, debug?}` → 200 task data / 204 | `tasks` (atomic claim), `workers` (register/heartbeat) |
| `complete_task` | `{task_id, output_location, ...}` → completion result | `tasks` (status/result), `generations` (create), `generation_variants`, `shot_generations` (placement), `timelines`/`timeline_events` via append service (`upsert_asset_registry_entry`, media clip add), `credits_ledger` (cost), storage `image_uploads` |
| `update-task-status` | see §7.1 | `tasks`, `workers`, billing on cancel |
| `calculate-task-cost` | `{task_id}` → `{cost, ...}` | `tasks`, `task_types`, `projects`, `credits_ledger` |
| `get-task-status` (POST) / `task-status` (GET `?task_id=`) | → `{status, ...}` | `tasks` |
| `tasks-list` | `{projectId, status?[]}` → `tasks[]` | `tasks`, `projects` (ownership) |
| `task-counts` | `{run_type?, debug?}` → queue/capacity stats | `tasks`, `workers`, `task_types` |
| `get-task-output` | `{task_id}` → output location(s) | `tasks` |
| `get-orchestrator-children` | `{orchestrator_task_id}` → `{tasks:[{id, task_type, status, params, output_location}]}` | `tasks` |
| `get-predecessor-output` | `{task_id, parent_generation_id?, child_order?}` → `{predecessors:[{predecessor_id, output_location, status}]}` | `tasks`, `generations` |
| `get-completed-segments` | `{run_id, project_id?}` → `[{segment_index, output_location}]` | `tasks` |
| `generate-upload-url` | `{task_id, filename, content_type, generate_thumbnail_url?}` → `{upload_url, storage_path, token, expires_at, thumbnail_*}` | storage `image_uploads` (signed upload), `tasks` |
| `generate-thumbnail` | `{generation_id, main_image_url, user_id}` → `{thumbnailUrl}` | storage `image_uploads`, `generations` |
| `update-worker-model` | `{worker_id, current_model}` → worker row | `workers` |
| `apply-image-transform` | `{generation_id?, source_image_url?, source_variant_id?, user_id?, create_as_generation?, make_primary?, variant_name?, tool_type?, transform?}` | `generations`, `generation_variants`, storage `image_uploads` |
| `update-shot-pair-prompts` | `{shot_id, task_id?, enhanced_prompts[]}` → `{updated: n}` | `shot_generations` (metadata.enhanced_prompt) |
| `huggingface-upload` | see §7.1 (also used from worker tooling) | storage `temporary` |
| `timeline-import` | `{timeline_id, project_id, config, asset_registry?, expected_version?, force?}` → `{ok, config_version}` | `timelines`/`timeline_events` via append service (`create-with-config` / `config-replaced`) |

### 7.3 Cron / ops / Stripe (service-role)
| Function | Trigger | Input → Output | Tables |
|---|---|---|---|
| `stripe-webhook` | Stripe events | Stripe event JSON → `{received:true}` | `users` (credits, stripe ids), `credits_ledger` (insert) |
| `complete-auto-topup-setup` | after checkout | `{sessionId, expectedUserId?}` | `users` (stripe_customer_id, stripe_payment_method_id, auto_topup_setup_completed) |
| `trigger-auto-topup` | cron/DB trigger | `{userId?}` | `users` (scan eligible) |
| `process-auto-topup` | cron | `{userId}` | `users`, `credits_ledger`, Stripe payment intents |
| `discord-daily-stats` | cron | — | RPC `func_daily_task_stats` (tasks/task_types), Discord webhook |
| `route-contract-sentinel` | pg_cron 1 min | — | `tasks`, `workers` (health), paging webhook |
| `broadcast-realtime` | ops | `{channel, event, payload}` | realtime broadcast |
| `reigh-data-fetch` | external CLI/tools | `{project_id?, shot_id?, task_id?, timeline_id?}` → joined project/shots/shot_generations/generations/tasks/timelines payload | `projects`, `shots`, `shot_generations`, `generations`, `generation_variants`, `tasks`, `timelines` |
| `complete_task` | legacy alias | see §7.2 | `tasks` |

The `_shared/` folder is not a deployable function (shared modules). `reigh-app/supabase/config.toml` defines deployed function config; `deno.lock` pins Deno deps.

---

## 8. CONTRACT SURFACE — every read/write path a replacement backend must serve

A replacement (e.g. Astrid SQLite + file store) must expose equivalents of the following. "App" = browser client; "worker" = GPU worker fleet / orchestrator.

### A. Auth & session
1. Discord OAuth sign-in with redirect back to origin and hash-token session restore; email/password dev-only login.
2. Session persistence + refresh; synchronous access-token read (localStorage `sb-<ref>-auth-token`) usable as `Authorization: Bearer <token>` on every data call.
3. `getUser()` / `getSession()` identity with stable `user.id` string, used as the RLS identity for all table access.
4. Sign-out; auth-state-change subscription (events SIGNED_IN/SIGNED_OUT/INITIAL_SESSION/token refresh).
5. Public (anon) paths: share-page RPCs (`get_shared_shot_data`, `increment_share_view_count`) and storage public reads.
6. PAT model for workers: `user_api_tokens` create (edge `generate-pat`), list, revoke; PAT accepted on worker-facing functions.

### B. Table reads (PostgREST-equivalent `from().select()` semantics + RLS-by-user)
7. `users` — by id: `credits`, `settings`, `username`, `name`, `avatar_url`, `onboarding_completed`, `api_keys`, `auto_topup_*` columns; `users.upsert({id, api_keys})`.
8. `projects` — list by user (ordered created_at desc), by id (`settings`, `aspect_ratio`), insert/update (owned), delete cascade (edge `delete-project`).
9. `shots` — list by project (order position), by id (`settings`, `aspect_ratio`, `project_id`), insert/update (name/aspect_ratio/settings/position batch), delete.
10. `shot_generations` — full timeline read with joined `generations` + `primary_variant` (exact select in §3.2), metadata read/update by id, `timeline_frame` read (positioned/unpositioned), frame writes (single + batch), delete.
11. `generations` — by id (`*`), by location+project, `based_on` (derived), `parent_generation_id`+`child_order` (children), `tasks`-contains filter (`filter('tasks','cs',…)`), count heads; inserts (external upload, local materialization, edit tools), updates (`location`, `thumbnail_url`, `params`, `starred`, `primary_variant_id`), deletes (project-scoped, cascade to variants).
12. `generation_variants` — list by generation/project, `is_primary` lookup, params read, inserts (original/edit/trim/reposition), updates (`is_primary`, `viewed_at`, `starred`), delete (project-scoped, non-original).
13. `tasks` — by id (with project scope), pending by project+status (Queued/In Progress), paginated project log with `params->orchestrator_task_id_ref is null` filter + task_type filter, status counts (head counts), subtasks (Queued, project), error_message read; **create via edge `create-task`**, **cancel via edge `update-task-status`**.
14. `task_types` — active config list (`is_active`, display fields, `supports_progress`, billing fields).
15. `resources` — public by type (paged), owned by type, by id (`metadata`), featured by ids, insert/update/delete owned; reference→generation migration updates.
16. `credits_ledger` — non-spend entries paged + exact count by user; spend rows by task_id.
17. `users`+`referral_stats` — referral stats read by username/id; `shared_generations` (slug lookup, insert with creator cache, uniqueness retry).
18. `shot_final_videos` — by shot+project, by id+shot_id (share data).
19. `shot_statistics` — per-shot video counts by project.
20. `external_api_keys` — owned rows (service, metadata, created_at); RPCs `save_external_api_key`/`delete_external_api_key`.
21. `user_api_tokens` — owned list ordered desc.
22. `training_data`, `training_data_batches`, `training_data_segments` — full CRUD, ordered desc, batch-scoped videos, duration read.
23. `effects` — user-scoped CRUD (catalog for video editor).
24. `timeline_agent_sessions` — read by id (user-owned), insert (create session), UPDATE realtime subscription; agent turns managed by edge `ai-timeline-agent`.
25. `timelines` — list by project (order updated_at desc), insert, rename, delete; `config`+`config_version`+`asset_registry` read by id.
26. `timeline_events` — head read (`version, hash, event_id` order desc limit 1).
27. `sync_bookmarks` — app-spoke bookmark read by timeline.
28. `timeline_checkpoints` — list by timeline (order created_at desc), insert, delete (retention/limit pruning).
29. `extension_install_state`, `extension_settings`, `extension_proposals` — user+timeline scoped select/upsert/delete (sentinel row pattern for snapshot).
30. `local_media_handles` — insert (pending materialization flow).
31. `system_logs` — write via RPC `func_insert_logs_batch`; read by ops tooling.
32. Views: `shot_final_videos`, `shot_statistics`, `shot_generations_with_computed_position`, `referral_stats`, `user_credit_balance`, `normalized_task_status`, `orchestrator_status`, `task_queue_analysis`, `task_types_with_billing`, `active_workers_health`, `worker_performance`, `v_recent_errors`, `v_worker_log_activity`, `recent_task_activity`.

### C. RPC-equivalent write/read operations (exact names + args)
33. `add_generation_to_shot {p_shot_id, p_generation_id, p_with_position}` (idempotent slot creation).
34. `batch_update_timeline_frames {p_updates:[{shot_generation_id, timeline_frame, metadata}]}` → rows (timeline drag hot path; must be atomic, fast, and return the applied rows).
35. `reorder_normalized {p_shot_id, p_new_order[]}`; `delete_and_normalize {p_shot_id, p_shot_generation_id}`; `unposition_and_normalize {p_shot_id, p_shot_generation_id}`.
36. `insert_shot_at_position {p_project_id, p_shot_name, p_position}` → `{shot_id}`; `duplicate_shot {original_shot_id, project_id}` → shot id; `duplicate_shot_with_videos {original_shot_id, project_id}` → Json.
37. `create_shot_with_generations {p_project_id, p_shot_name, p_generation_ids}` → shot.
38. `duplicate_as_new_generation {p_shot_id, p_generation_id, p_project_id}` → new generation id.
39. `demote_orphaned_video_variants {p_shot_id}` → count.
40. `ensure_shot_parent_generation {p_shot_id, p_project_id}` → generation id.
41. `copy_onboarding_template {target_project_id, target_shot_id}`; `create_user_record_if_not_exists` (no args).
42. `get_shared_shot_data {share_slug_param}` → `{shot_id, shot_name, generation, images, settings, creator_id, view_count, creator_*}`; `increment_share_view_count {share_slug_param}`; `copy_shot_from_share {share_slug_param, target_project_id}`.
43. `track_referral_visit {p_referrer_username, p_visitor_fingerprint, p_session_id}`; `create_referral_from_session {p_session_id, p_fingerprint}`.
44. `update_tool_settings_atomic {p_table_name, p_id, p_tool_id, p_settings}` (users/projects/shots scopes; atomic merge).
45. `save_external_api_key {p_service, p_key_value, p_metadata}` / `delete_external_api_key {p_service}` (encrypted at rest).
46. `func_insert_logs_batch {logs}` (client log shipping).
47. `upsert_asset_registry_entry {p_timeline_id, p_asset_id, p_entry}` (editor + worker completion).
48. Worker RPCs used by edge functions: `claim_next_task_*` / `func_claim_available_task`, `complete_task_with_timing {p_output_location, p_task_id}`, `func_update_task_status`, `func_mark_task_complete`, `func_update_worker_heartbeat`, `auto_register_worker`, `delete_project_with_extended_timeout {p_project_id}`, `func_daily_task_stats`, `check_rate_limit`/`cleanup_old_rate_limits`, `get_external_api_key_decrypted`.

### D. Realtime
49. Postgres-changes equivalent push for `tasks` (INSERT/UPDATE, project filter), `generations` (INSERT/UPDATE/DELETE, project filter), `shot_generations` (INSERT/UPDATE/DELETE), `generation_variants` (INSERT/UPDATE/DELETE), `timelines` (INSERT/UPDATE/DELETE, project filter) — a replacement must be able to *emit* change events when rows change (or the app falls back to polling at up to 15 s).
50. Per-session channel for `timeline_agent_sessions` UPDATE by id.
51. Realtime must be observable as healthy/unhealthy (DataFreshnessManager drives polling fallback).

### E. Edge-function endpoints (HTTP POST /functions/v1/<name>, Bearer JWT/PAT)
52. `create-task` — family-based task creation with idempotency (see §7.1).
53. `ai-prompt`, `ai-voice-prompt`, `ai-timeline-agent`, `ai-generate-effect`, `ai-generate-sequence`, `ai-generate-sequence-component` — LLM-backed prompt/effect/sequence/agent generation (external LLM APIs; only `ai-timeline-agent` persists to DB).
54. `trim-video` — server-side video trim (Replicate) + storage upload.
55. `huggingface-upload` — LoRA/sample-video publish to HuggingFace from storage.
56. `stripe-checkout`, `setup-auto-topup`, `grant-credits` — purchase & credit grant (Stripe checkout URL; ledger insert server-side).
57. `delete-project`, `update-task-status` (cancel path), `generate-pat`, `revoke-pat` — account/task mutations.
58. Worker endpoints: `claim-next-task`, `complete_task`, `calculate-task-cost`, `get-task-status`/`task-status`, `tasks-list`, `task-counts`, `get-task-output`, `get-orchestrator-children`, `get-predecessor-output`, `get-completed-segments`, `generate-upload-url`, `generate-thumbnail`, `update-worker-model`, `apply-image-transform`, `update-shot-pair-prompts`, `timeline-import`.
59. Service-role/cron endpoints: `stripe-webhook`, `complete-auto-topup-setup`, `trigger-auto-topup`, `process-auto-topup`, `discord-daily-stats`, `route-contract-sentinel`, `broadcast-realtime`, `reigh-data-fetch`.

### F. Storage (buckets + object semantics)
60. `image_uploads` (public read): upload via SDK `storage.from('image_uploads').upload(path, file)` (XHR with progress/stall detection, 60 s timeout, retries), signed upload URLs for workers (`generate-upload-url`), public URL readback (`getPublicUrl`), path conventions `{userId}/uploads/<file>`, `{userId}/thumbnails/<file>`, `{userId}/tasks/{taskId}/<file>`.
61. `temporary` (private, 500 MB limit): upload `{userId}/{uuid}-{name}` for edge-driven uploads; server reads + deletes after processing.
62. `timeline-assets` (public read; write policy user-folder): upload `{userId}/{timelineId}/{ts}-{name}`; `getPublicUrl` resolution; asset registry entries reference these paths or absolute URLs.
63. `training-data` (public): upload, signed URLs (1 h), remove.
64. `lora_files`, `render-outputs` (render-outputs private, user-folder RLS; editor builds signed URLs).
65. Public storage URL parsing: `/storage/v1/object/(public|sign)/<bucket>/<path>` → mint/refresh signed URLs (1 h TTL) for private objects (`generationAssetResolver.ts`).

### G. External services & integration seams
66. **Append service** (`VITE_REIGH_APPEND_SERVICE_URL`): `POST /v1/timelines/{id}/config-replaced` (CAS `expected_version`, 409 on conflict, response `{config_version, db_head}`), `POST /v1/timelines/{id}/app-bookmark`, `POST /v1/timelines/{id}/app-divergence`; internal token auth for edge functions; must materialize `timelines` + append `timeline_events` + update `sync_bookmarks`. **The migration's biggest single external seam** — replacing it with Astrid file-based timelines means re-implementing or bypassing this at the `DataProvider` interface (`SupabaseDataProvider` ↔ `AstridBridgeDataProvider`).
67. Orchestrator render enqueue: `POST <orchestratorBaseUrl>/functions/v1/enqueue-task` with `banodoco_render_timeline` payload + Bearer JWT (`src/tools/video-editor/lib/renderRouter.ts:703-775`).
68. IndexedDB local persistence: `syncLedgerIndexedDb` (sync bookmarks, keep-both divergence artifacts) — client-side only, but part of the sync protocol.
69. Stripe (server-side): checkout sessions, webhook verification, payment-intent auto-top-up; publishable key `VITE_STRIPE_PUBLISHABLE_KEY` for Stripe.js on the frontend.
70. Dev/local mode: `VITE_API_TARGET_URL` for media URL rebasing; sessionless editor reads timelines via the Astrid bridge instead of Supabase (the pre-existing migration path for this exact work).

---

## Gaps / unverified
- **Live DB schema vs generated types**: table/column ground truth was taken from `src/integrations/supabase/types.ts` (generated, appears current) and `reigh-app/supabase/migrations/`; not verified against a live Postgres (read-only constraint). A few tables referenced by newer code (e.g. `dev_tasks`, `settings`, `onboarding_config`, `rate_limits`, `timeline_update_log`, `shot_data_audit`, `referrals`, `referral_sessions`) have no direct frontend call sites found — likely ops/trigger-only.
- **`timeline_events` / `sync_bookmarks` writer details** (exact append-service SQL semantics, hash algorithm, event payload shape) live in the Python append service, which is **not in this workspace** — only its HTTP contract (§G.66) is verifiable from `SupabaseDataProvider.ts`, `_shared/reighAppendService.ts`, and tests.
- **`get_shared_shot_data` RPC output**: frontend consumes `{shot_id, shot_name, generation, images, settings, creator_id, view_count, creator_*}` (`useSharePageData.ts`), but the RPC body itself is in migrations (not re-read in full); `images` shape (url/thumbnail_url/timeline_frame) inferred from the share-creation cache path.
- **Which worker version calls which worker edge functions**: the worker/orchestrator repos (`reigh-worker/`, `reigh-worker-orchestrator/`) were out of scope; worker-facing contracts in §7.2/§8.E were read from the edge functions' own doc comments and are the *server* contract, but actual worker call patterns (frequencies, payloads) were not cross-checked there.
- **Exact RLS policies** for each table (row-level security granting the anon/JWT access the client depends on) were not enumerated; only inferred from migration filenames (e.g. `20250113000001_add_users_table_rls.sql`) and client behavior. A replacement backend must reproduce these ownership filters (`.eq('user_id', user.id)` etc.) server-side.
- **`useProjectGenerations` full select list** (gallery) elided mid-read; count + primary join shape captured, exact column list may include more fields.
- **Realtime broadcast usage**: `broadcast-realtime` edge function exists and `IncomingTasksContext` consumes an `incomingTasks` event stream — the exact broadcast channel/event name used by workers was not found in this repo (likely worker-side).
- **`db/seed.ts`** (`npm run db:seed`) referenced in package.json but no `db/` directory exists in the checkout — presumed legacy script.
- **Stripe prices/currency** and the `credits_ledger` type enum values beyond `manual|stripe|spend|refund|auto_topup` were read from client types only; the DB enum may have more members.
