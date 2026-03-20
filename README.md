# reigh-workspace

Development workspace for the Reigh video generation platform. Clone this repo, then clone the three component repos into it to get a fully working environment.

## Setup

```bash
# 1. Clone the workspace
git clone https://github.com/banodoco/reigh-workspace.git
cd reigh-workspace

# 2. Clone the component repos
git clone https://github.com/peteromallet/Reigh-App.git
git clone https://github.com/banodoco/Reigh-Worker.git
git clone https://github.com/peteromallet/Reigh-Worker-Orchestrator.git
```

Your workspace should look like this:

```
reigh-workspace/
  Reigh-App/                  Frontend (React/Vite) + Supabase edge functions
  Reigh-Worker/               GPU worker (Python, runs on RunPod)
  Reigh-Worker-Orchestrator/  Worker scaling + API task dispatch (runs on Railway)
  structure.md                System-wide architecture overview
  debugging.md                Cross-repo debugging router
  docs/                       Detailed sub-documentation
```

## Repo Setup

Each repo has its own dependencies:

**Reigh-App** (frontend):
```bash
cd Reigh-App
cp .env.example .env          # Fill in Supabase credentials
npm install
npm run dev                   # http://localhost:2222
```

**Reigh-Worker** (GPU worker):
```bash
cd Reigh-Worker
cp .env.example .env          # Fill in Supabase + RunPod credentials
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python worker.py --debug
```

**Reigh-Worker-Orchestrator** (control plane):
```bash
cd Reigh-Worker-Orchestrator
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
User → Reigh-App (frontend)
         ↓ create-task edge function
       Supabase (DB + Edge Functions + Storage + Realtime)
         ↓ claim-next-task
       Reigh-Worker (GPU on RunPod)
         ↓ complete_task
       Supabase → Realtime → Reigh-App (video appears)

       Reigh-Worker-Orchestrator (Railway)
         monitors demand → scales workers up/down
         dispatches API tasks (fal.ai, Wavespeed)
```
