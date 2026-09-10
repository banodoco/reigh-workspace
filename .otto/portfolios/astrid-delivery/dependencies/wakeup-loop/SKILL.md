---
name: wakeup-loop
description: >
  Keep the current assistant turn alive while waiting. Use when the user wants
  this exact chat/thread to continue after a delay or after a local process
  exits. This is not a background scheduler and does not launch a new agent.
allowed-tools: Bash(*wakeup_loop.sh*), Bash(ps *), Bash(pgrep *), Bash(kill *), Hub, Read
---

# Wake-up Loop

Same-thread waiting helper. The turn stays alive because the assistant AWAITS
the wait: launch it, block until it completes, then continue in this same
chat. Never launch a wait and end the turn — that drops the thread.

## Use This For

- "Sleep for 10 minutes, then continue here."
- "Follow this process and tell me when it exits."
- "Keep this thread alive until X finishes."

## Do Not Use This For

- Background launchd/cron scheduling.
- Restarting a dead chat/API thread.
- Launching fresh Codex or Claude sessions.

## How It Works

1. **Launch the wait** — `scripts/wakeup_loop.sh` with `--sleep N` or `--pid`.
   It prints progress lines and a completion marker when done.
2. **Await it in-thread.** If the harness kept the call foreground, that tool
   call itself holds the turn open. If the harness backgrounded it and
   returned a job handle (omp auto-backgrounds long bash calls), block on
   that job and re-issue until it settles:

   ```text
   hub wait --ids <job-id> [timeoutMs >= remaining]
   ```

   A wait returns on the FIRST of: the job settling, an incoming message, a
   steering interrupt, or the window elapsing — NOT when all jobs finish.
   Any early return: re-issue. Keep re-issuing until the wait completes.
3. **Continue only when the wait completes.** The settle snapshot auto-delivers,
   then make a concrete decision: continue the work (start another wait if more
   waiting is useful) or stop because the task is complete or blocked on the
   user.

## Commands

Sleep and continue this same turn:

```bash
scripts/wakeup_loop.sh \
  --sleep 600 \
  --poll 30 \
  --label "10-minute wait" \
  --message "Restart the work now and summarize what changed while waiting."
```

**The 3600s cap:** every bash call — foreground or backgrounded — hard-terminates
at 3600s. The sleep value must stay under that with overhead headroom.

**Safe single sleep cap: 3540s (59 min)** — leaves ~55s for script setup and
logging. `--sleep 3600` fails: sleep + overhead overshoots the deadline and the
process is killed just short of done. Never exceed 3540s in one launch.

Long waits (> ~59 min) are **chained**: one sub-hour segment per launch. Each
wake is a new bash call, so each segment gets a fresh 3600s ceiling:

```bash
scripts/wakeup_loop.sh \
  --sleep 3540 \
  --poll 60 \
  --label "1h wake (leg 1): 59min" \
  --message "One hour has elapsed; continue in this same chat/thread."
# await completion (re-issue on early return), then launch leg 2 (60s):
scripts/wakeup_loop.sh \
  --sleep 60 \
  --poll 30 \
  --label "1h wake (leg 2): +1min" \
  --message "One hour has elapsed; continue in this same chat/thread."
```

Each launch's result auto-delivers on settle; keep the turn alive by awaiting
each one before launching the next.

Recurring checks (the script loops internally; you still await the launch):

```bash
scripts/wakeup_loop.sh \
  --sleep 600 \
  --poll 30 \
  --repeat forever \
  --label "recurring check" \
  --message "Check status, decide whether more waiting makes sense, and stop the loop if the work is done."
```

Follow a process:

```bash
scripts/wakeup_loop.sh \
  --pid 12345 \
  --poll 5 \
  --label "build" \
  --message "The build process ended; inspect the result and continue."
```

Await the launch the same way; when it completes, the process has exited —
inspect the result and continue here.

## Flags

| flag | meaning |
|---|---|
| `--sleep SECONDS` | wait for a fixed number of seconds |
| `--pid PID` | wait until a local process exits |
| `--poll SECONDS` | progress interval, default `5` |
| `--label TEXT` | label printed in progress lines |
| `--message TEXT` | message printed when the wait finishes |
| `--repeat N` | repeat a `--sleep` wait N times |
| `--repeat forever` | repeat a `--sleep` wait until interrupted |

Pass exactly one of `--sleep` or `--pid`.
`--repeat` is only supported with `--sleep`.

At completion the helper prints:

```text
wake-up complete; continue this same chat/thread now
decide whether to start another wait or stop because the work is done
```

If `--message` is provided, it prints that text immediately after the
completion marker so the assistant knows what to do next. After each wake-up,
the assistant should make a concrete decision: either continue the work and
start another wait if more waiting is useful, or stop if the task is complete
or blocked on the user.
