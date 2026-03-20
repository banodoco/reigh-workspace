# Reigh: System Structure

> **How to Use This Guide**
> - Start here to understand how the three repos fit together
> - Follow links to sub-docs in [docs/structure_detail/](docs/structure_detail/) for deep dives
> - Each repo also has its own README/STRUCTURE.md for repo-specific detail
> - Source of truth is always the code — this guide points you in the right direction

---

## System Overview

Reigh is a video generation platform. Users create tasks in the frontend, GPU workers process them, and the orchestrator manages scaling.

```
┌─────────────────────────────────────────────────────────┐
│                    Reigh-Collection                      │
├──────────────────┬──────────────────┬───────────────────┤
│     Reigh-App/       │  Reigh-Worker/   │  Reigh-Worker-    │
│                  │                  │  Orchestrator/    │
│  React/Vite UI   │  Python GPU      │  Python control   │
│  Supabase edge   │  worker on       │  plane on         │
│  functions       │  RunPod pods     │  Railway          │
└────────┬─────────┴────────┬─────────┴─────────┬─────────┘
         │                  │                   │
         └──────────────────┼───────────────────┘
                            │
                    ┌───────┴───────┐
                    │   Supabase    │
                    │  Postgres DB  │
                    │  Edge Funcs   │
                    │  Storage      │
                    │  Realtime     │
                    └───────────────┘
```

---

## Tech Stack

| Layer | Technology | Repo |
|-------|------------|------|
| **Frontend** | React + Vite + TypeScript | Reigh-App/ |
| **Styling** | TailwindCSS + shadcn-ui | Reigh-App/ |
| **Backend** | Supabase (Postgres + Edge Functions + Storage + Realtime) | Reigh-App/ (edge functions + migrations) |
| **GPU Workers** | Python + PyTorch + CUDA | Reigh-Worker/ |
| **Video Engine** | Wan2GP (vendored) | Reigh-Worker/Wan2GP/ |
| **Orchestration** | Python (GPU scaling + API task dispatch) | Reigh-Worker-Orchestrator/ |
| **GPU Hosting** | RunPod | Managed by Orchestrator + Arnold |
| **Orchestrator Hosting** | Railway | Reigh-Worker-Orchestrator/ |
| **External APIs** | fal.ai, Wavespeed (image editing) | Dispatched by Orchestrator |

---

## End-to-End Data Flow

```
User clicks Generate
  → Frontend builds payload                           Reigh-App/src/shared/lib/tasks/
  → Calls create-task edge function                   Reigh-App/supabase/functions/create-task/
  → Row inserted in tasks table (status: Queued)      Supabase Postgres
  → Worker polls claim-next-task                      Reigh-App/supabase/functions/claim-next-task/
  → Worker processes task on GPU                      Reigh-Worker/worker.py
  → Worker calls complete_task edge function           Reigh-App/supabase/functions/complete_task/
  → DB trigger creates generation row                 Supabase
  → Realtime broadcasts to UI                         Reigh-App/src/ (React Query subscription)
  → Video appears in gallery
```

**Pipelines** (e.g., video travel): Orchestrator creates parent task → spawns child segment tasks → each child follows the flow above → stitch task joins outputs.

**API tasks** (e.g., image editing): API Orchestrator claims task → dispatches to fal.ai/Wavespeed → writes result back.

---

## Repo Structure

### Reigh-App/ — Frontend + Edge Functions

The main application. React SPA + Supabase serverless backend.

| Path | Purpose |
|------|---------|
| `src/app/` | App bootstrap & routing |
| `src/pages/` | Top-level pages (Home, Shots, Art, Share) |
| `src/tools/` | Feature modules — each tool: `pages/`, `components/`, `hooks/`, `settings.ts` |
| `src/domains/` | Domain logic (billing, lora, media-lightbox, generation) |
| `src/features/` | Feature slices (tasks, shots, gallery, resources, projects, settings) |
| `src/shared/` | Cross-domain primitives, UI components, contracts |
| `src/integrations/` | Supabase client, auth, realtime, instrumentation |
| `supabase/functions/` | Edge Functions (task lifecycle, payments, AI) |
| `supabase/migrations/` | DB schema migrations |
| `scripts/debug.py` | Debug CLI for tasks, pipelines, logs, pods |

Full detail: [Reigh-App/README.md](./Reigh-App/README.md)

### Reigh-Worker/ — GPU Worker

Queue-based video generation system built on Wan2GP.

| Path | Purpose |
|------|---------|
| `worker.py` | Main entry — polls DB, claims tasks, routes to handlers |
| `source/core/` | Infrastructure: DB operations, logging, typed parameters |
| `source/media/` | Media processing: ffmpeg, crossfade, color matching, structure guidance |
| `source/models/` | Model integration: WanOrchestrator, ComfyUI, LoRA |
| `source/task_handlers/` | Task orchestration: travel, join/stitch, editing, routing |
| `source/utils/` | Shared utilities: resolution, prompts, masks, downloads |
| `Wan2GP/` | Upstream video generation engine (vendored, DO NOT MODIFY) |
| `debug/` | Debug CLI (`python -m debug`) |
| `scripts/` | Standalone utilities (GPU diag, test tasks, worker matrix) |

Data flow: `DB → worker.py → TaskRegistry → HeadlessTaskQueue → WanOrchestrator → wgp.py → Files`

Full detail: [Reigh-Worker/STRUCTURE.md](./Reigh-Worker/STRUCTURE.md)

### Reigh-Worker-Orchestrator/ — Control Plane

Manages GPU workers on RunPod and dispatches API-based tasks.

| Path | Purpose |
|------|---------|
| `gpu_orchestrator/` | Spawns, monitors, and terminates RunPod pods based on task demand |
| `api_orchestrator/` | Handles API-based tasks (fal.ai, Wavespeed, image processing) |
| `scripts/debug.py` | Debug CLI (tasks, workers, health, railway, infra, runpod) |
| `scripts/dashboard.py` | Real-time status dashboard |
| `scripts/spawn_gpu.py` | Manual GPU pod creation |
| `scripts/shutdown_all_workers.py` | Emergency: kill all workers |

Full detail: [Reigh-Worker-Orchestrator/README.md](./Reigh-Worker-Orchestrator/README.md)

---

## Shared Database (Supabase)

All three repos talk to the same Supabase instance. Key tables:

| Table | Purpose | Written by |
|-------|---------|-----------|
| `tasks` | Task queue (status, params, output) | Frontend (create), Edge Functions (lifecycle), Worker (claim/complete) |
| `workers` | Active worker registry + heartbeat | Worker, Orchestrator |
| `system_logs` | Unified log sink (48h retention) | All components |
| `generations` | Gallery items (images/videos) | DB trigger on task completion |
| `shots` / `shot_generations` | Timeline organization | Frontend |
| `projects` | User projects | Frontend |
| `users` | User profiles + settings | Frontend, Auth |

Schema lives in `Reigh-App/supabase/migrations/`. Deploy with `npx supabase db push --linked` (never `db reset --linked`).

---

## Edge Functions (API Layer)

All edge functions live in `Reigh-App/supabase/functions/`. They are the API boundary between all components and the database.

**Task pipeline functions** (called by Worker + Orchestrator):

| Function | Caller | Purpose |
|----------|--------|---------|
| `create-task` | Frontend | Insert task row |
| `claim-next-task` | Worker | Claim a Queued task |
| `update-task-status` | Worker | Status transitions + cascading failure |
| `complete_task` | Worker | Mark Complete, trigger generation |
| `task-counts` | Orchestrator | Queue depth for scaling decisions |
| `update-worker-model` | Worker | Register current model |

Deploy: `npx supabase functions deploy <name> --project-ref wczysqzxlwdndgxitrvc`

Full reference: [docs/structure_detail/edge_functions.md](./docs/structure_detail/edge_functions.md)

---

## Core Concepts

### Task System
Async queue for AI workloads. Client creates task → edge function inserts row → worker polls and claims → processes → edge function completes. See [docs/structure_detail/task_worker_lifecycle.md](./docs/structure_detail/task_worker_lifecycle.md) and [docs/structure_detail/unified_task_creation.md](./docs/structure_detail/unified_task_creation.md).

### Settings Resolution
Priority: **shot → project → user → defaults**. See [docs/structure_detail/settings_system.md](./docs/structure_detail/settings_system.md).

### Tools (Frontend)
Tools live in `Reigh-App/src/tools/{tool-name}/` following a consistent structure. See [docs/structure_detail/adding_new_tool.md](./docs/structure_detail/adding_new_tool.md).

### Shots & Generations
- **Generations** = gallery items (images/videos produced by AI tasks)
- **Shots** = containers that organize generations into a timeline
- **`shot_generations`** = join table with position + metadata

### Realtime
Smart polling + Supabase realtime subscriptions. Connected = no polling; disconnected = 15s fallback. See [docs/structure_detail/realtime_system.md](./docs/structure_detail/realtime_system.md).

---

## Sub-Documentation Index

### Cross-Repo (system-wide)

| Topic | File |
|-------|------|
| **Debugging** | [debugging.md](./debugging.md) |
| **Task System** | [task_worker_lifecycle.md](./docs/structure_detail/task_worker_lifecycle.md) |
| **Task Creation** | [unified_task_creation.md](./docs/structure_detail/unified_task_creation.md) |
| **Edge Functions** | [edge_functions.md](./docs/structure_detail/edge_functions.md) |
| **Database & Storage** | [db_and_storage.md](./docs/structure_detail/db_and_storage.md) |
| **Deployment** | [deployment_and_migration_guide.md](./docs/structure_detail/deployment_and_migration_guide.md) |
| **Storage & Uploads** | [storage_uploads.md](./docs/structure_detail/storage_uploads.md) |

### Frontend (Reigh-App/)

| Topic | File |
|-------|------|
| **Frontend Architecture** | [frontend_architecture.md](./docs/structure_detail/frontend_architecture.md) |
| **Settings System** | [settings_system.md](./docs/structure_detail/settings_system.md) |
| **Data Fetching** | [data_fetching.md](./docs/structure_detail/data_fetching.md) |
| **Per-Pair Data** | [per_pair_data_persistence.md](./docs/structure_detail/per_pair_data_persistence.md) |
| **Realtime System** | [realtime_system.md](./docs/structure_detail/realtime_system.md) |
| **Performance** | [performance_system.md](./docs/structure_detail/performance_system.md) |
| **Image Loading** | [image_loading_system.md](./docs/structure_detail/image_loading_system.md) |
| **Shared Utilities** | [shared_utilities.md](./docs/structure_detail/shared_utilities.md) |
| **Adding Tools** | [adding_new_tool.md](./docs/structure_detail/adding_new_tool.md) |
| **Design Standards** | [design_motion_guidelines.md](./docs/structure_detail/design_motion_guidelines.md) |
| **Error Handling** | [error_handling.md](./docs/structure_detail/error_handling.md) |
| **Refactoring** | [refactoring_patterns.md](./docs/structure_detail/refactoring_patterns.md) |
| **Authentication** | [auth_system.md](./docs/structure_detail/auth_system.md) |
| **Routing & Navigation** | [routing_and_navigation.md](./docs/structure_detail/routing_and_navigation.md) |
| **Payments** | [auto_topup_system.md](./docs/structure_detail/auto_topup_system.md) |
| **Referrals** | [referral_system.md](./docs/structure_detail/referral_system.md) |
| **Video Travel Tool** | [tool_video_travel.md](./docs/structure_detail/tool_video_travel.md) |
| **Code Quality** | [code_quality_audit.md](./Reigh-App/docs/code_quality_audit.md) |
