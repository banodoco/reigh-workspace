# GPU Worker Debugging

Workers run on RunPod pods. Code lives in `./reigh-worker/`.

---

## Finding Pods

```bash
# From reigh-app/
python scripts/debug.py pod list           # All pods with SSH commands
python scripts/debug.py pod ssh <pod_id>   # SSH command for a specific pod

# From reigh-worker-orchestrator/
python scripts/ssh_to_worker.py            # Interactive SSH into a worker
```

---

## Reading Worker Logs

```bash
# Tail live output
ssh root@<HOST> -p <PORT> "tail -f /tmp/worker_test.log"

# Search for errors
ssh root@<HOST> -p <PORT> "grep -i 'error\|exception\|traceback' /tmp/worker_test.log | tail -30"

# Search for a specific task
ssh root@<HOST> -p <PORT> "grep '<task_id>' /tmp/worker_test.log | tail -20"

# Key markers to grep for
# UPLOAD_INTERMEDIATE, complete_task, generate_vace.*returned, FINAL_STITCH, Failed
ssh root@<HOST> -p <PORT> "grep -E 'UPLOAD_INTERMEDIATE|complete_task|FINAL_STITCH|Failed' /tmp/worker_test.log | tail -20"
```

---

## Starting / Restarting a Worker

```bash
ssh root@<HOST> -p <PORT>

# Kill existing workers
kill -9 $(pgrep -f 'python.*worker') 2>/dev/null

# Pull latest and start
cd /workspace/reigh-worker
git pull
source venv/bin/activate
nohup python -u worker.py \
  --reigh-access-token <PAT_TOKEN> \
  --debug --wgp-profile 4 \
  > /tmp/worker_test.log 2>&1 &

# Verify (init takes ~3-4 min for CUDA/model imports)
ps aux | grep 'python.*worker' | grep -v grep
```

Or use `debug.py pod worker <pod_id>` (from reigh-app/) to print the full setup commands.

---

## First-Time Pod Setup

If `/workspace/reigh-worker` doesn't exist:

```bash
cd /workspace
git clone https://github.com/banodoco/reigh-worker.git
cd reigh-worker
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Pods are provisioned by **Arnold** (`../Arnold/`) via RunPod API. The **Orchestrator** handles auto-scaling in production.

---

## Worker Auth Modes

| Mode | Flag / Env Var | When |
|------|---------------|------|
| **PAT** (recommended for testing) | `--reigh-access-token <token>` | Manual testing |
| **Service role key** | `SUPABASE_SERVICE_ROLE_KEY` env var | Cloud workers |
| **Anon key** | `SUPABASE_ANON_KEY` env var | Fallback |

**PAT gotcha**: PAT goes in `Authorization: Bearer` header, NOT in `apikey` header. Edge functions accepting PATs need `verify_jwt = false` in `supabase/config.toml`.

---

## System Checks (on pod via SSH)

| Check | Command |
|-------|---------|
| GPU status | `nvidia-smi` |
| Worker process | `ps aux \| grep python` |
| Disk space | `df -h /workspace` |
| Git state | `git -C /workspace/reigh-worker log --oneline -3` |
| Guardian heartbeat | `tail -20 /tmp/guardian_*.log` |
| Full GPU diagnostics | `bash /workspace/reigh-worker/scripts/gpu_diag.sh` |

---

## Queuing Test Tasks

### Duplicate an existing task

Use a new `run_id` to avoid stale children counting against completion:

```sql
INSERT INTO tasks (id, task_type, status, project_id, params, created_at)
SELECT gen_random_uuid(), task_type, 'Queued', project_id,
       jsonb_set(
         jsonb_set(params, '{orchestrator_details,run_id}',
           to_jsonb(to_char(NOW(), 'YYYYMMDDHH24MI') || 'test')),
         '{orchestrator_details,orchestrator_task_id}',
         to_jsonb('test_' || left(gen_random_uuid()::text, 8))
       ),
       NOW()
FROM tasks WHERE id = '<source_task_id>';
```

Or use `scripts/create_test_task.py` in either reigh-worker or reigh-worker-orchestrator.

### Cancel interfering tasks

```sql
UPDATE tasks SET status = 'Cancelled'
WHERE status IN ('In Progress', 'Queued')
  AND id != '<target_task_id>';
```

### Check cloud_enabled

Workers can only claim tasks from users with cloud processing enabled:

```sql
SELECT u.settings->'ui'->'generationMethods'->'inCloud' as cloud_enabled
FROM tasks t JOIN projects p ON p.id = t.project_id JOIN users u ON u.id = p.user_id
WHERE t.id = '<task_id>';
```

---

## Fix & Retry Loop

1. Edit `./reigh-worker/` locally → `git push`
2. SSH to pod: `cd /workspace/reigh-worker && git pull`
3. Kill and restart worker (see above)
4. Wait ~3-4 min for init
5. Queue a test task
6. Watch logs → on error, repeat

---

## Monitoring Queries

```sql
-- Task status
SELECT id, status, worker_id, EXTRACT(EPOCH FROM (NOW() - created_at))::int as age_secs
FROM tasks WHERE id = '<task_id>';

-- System logs for a task
SELECT timestamp, source_type, log_level, LEFT(message, 200)
FROM system_logs WHERE task_id = '<task_id>' ORDER BY timestamp;

-- Error logs only
SELECT timestamp, log_level, message, metadata::text
FROM system_logs WHERE task_id = '<task_id>' AND log_level IN ('WARNING', 'ERROR')
ORDER BY timestamp;

-- Worker heartbeat
SELECT id, status, current_model, last_heartbeat, NOW() - last_heartbeat as stale_for
FROM workers ORDER BY last_heartbeat DESC LIMIT 3;
```
