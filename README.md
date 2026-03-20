# reigh-workspace

Development workspace for the Reigh video generation platform. Clone this repo, then clone the three component repos into it to get a fully working environment.

## Setup

```bash
# 1. Clone the workspace
git clone https://github.com/banodoco/reigh-workspace.git
cd reigh-workspace

# 2. Clone the component repos
git clone https://github.com/peteromallet/reigh-app.git
git clone https://github.com/banodoco/reigh-worker.git
git clone https://github.com/peteromallet/reigh-worker-orchestrator.git
```

Your workspace should look like this:

```
reigh-workspace/
  reigh-app/                  Frontend (React/Vite) + Supabase edge functions
  reigh-worker/               GPU worker (Python, runs on RunPod)
  reigh-worker-orchestrator/  Worker scaling + API task dispatch (runs on Railway)
  structure.md                System-wide architecture overview
  debugging.md                Cross-repo debugging router
  docs/                       Detailed sub-documentation
```

## Repo Setup

Each repo has its own dependencies:

**reigh-app** (frontend):
```bash
cd reigh-app
cp .env.example .env          # Fill in Supabase credentials
npm install
npm run dev                   # http://localhost:2222
```

**reigh-worker** (GPU worker):
```bash
cd reigh-worker
cp .env.example .env          # Fill in Supabase + RunPod credentials
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python worker.py --debug
```

**reigh-worker-orchestrator** (control plane):
```bash
cd reigh-worker-orchestrator
cp env.example .env            # Fill in Supabase + RunPod + Railway credentials
pip install -r gpu_orchestrator/requirements.txt
pip install -r api_orchestrator/requirements.txt
python -m gpu_orchestrator.main status
```

## Key Docs

| Doc | Purpose |
|-----|---------|
| [structure.md](structure.md) | How the three repos fit together — architecture, data flow, database schema |
| [debugging.md](debugging.md) | When something breaks — decision table, debug tools, blast radius |
| [docs/](docs/) | Deep-dive sub-documentation for each system layer |

## Architecture

```
User → reigh-app (frontend)
         ↓ create-task edge function
       Supabase (DB + Edge Functions + Storage + Realtime)
         ↓ claim-next-task
       reigh-worker (GPU on RunPod)
         ↓ complete_task
       Supabase → Realtime → reigh-app (video appears)

       reigh-worker-orchestrator (Railway)
         monitors demand → scales workers up/down
         dispatches API tasks (fal.ai, Wavespeed)
```
