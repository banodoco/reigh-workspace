#!/usr/bin/env bash
# Same-thread wake-up helper: keep the current tool call alive by sleeping
# or following a process, then return so the agent can continue this chat.

set -euo pipefail

MODE=""
SECONDS_TO_SLEEP=""
PID_TO_FOLLOW=""
POLL=5
LABEL="wakeup-loop"
MESSAGE=""
REPEAT=1

usage() {
  cat <<'USAGE'
Usage:
  wakeup_loop.sh --sleep SECONDS [--poll SECONDS] [--label TEXT] [--message TEXT] [--repeat N|forever]
  wakeup_loop.sh --pid PID [--poll SECONDS] [--label TEXT] [--message TEXT]

This does not launch a new agent. It keeps the current tool call alive so the
current assistant turn can continue in the same chat after the timer/process
finishes.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sleep)
      MODE="sleep"
      SECONDS_TO_SLEEP="$2"
      shift 2
      ;;
    --pid)
      MODE="pid"
      PID_TO_FOLLOW="$2"
      shift 2
      ;;
    --poll)
      POLL="$2"
      shift 2
      ;;
    --label)
      LABEL="$2"
      shift 2
      ;;
    --message)
      MESSAGE="$2"
      shift 2
      ;;
    --repeat)
      REPEAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

if [[ -z "$MODE" ]]; then
  echo "one of --sleep or --pid is required" >&2
  usage >&2
  exit 2
fi
if ! is_uint "$POLL" || [[ "$POLL" -eq 0 ]]; then
  echo "--poll must be a positive integer" >&2
  exit 2
fi
if [[ "$MODE" == "pid" && "$REPEAT" != "1" ]]; then
  echo "--repeat is only supported with --sleep" >&2
  exit 2
fi
if [[ "$REPEAT" != "forever" ]] && { ! is_uint "$REPEAT" || [[ "$REPEAT" -eq 0 ]]; }; then
  echo "--repeat must be a positive integer or 'forever'" >&2
  exit 2
fi

run_sleep_once() {
  local iteration="$1"
  local start="$2"
  while :; do
    local now elapsed remaining
    now="$(date +%s)"
    elapsed=$((now - start))
    if [[ "$elapsed" -ge "$SECONDS_TO_SLEEP" ]]; then
      break
    fi
    remaining=$((SECONDS_TO_SLEEP - elapsed))
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: iteration=${iteration} sleeping elapsed=${elapsed}s remaining=${remaining}s"
    if [[ "$remaining" -lt "$POLL" ]]; then
      sleep "$remaining"
    else
      sleep "$POLL"
    fi
  done
}

print_wake_message() {
  local waited="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: done waited=${waited}s"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: wake-up complete; continue this same chat/thread now"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: decide whether to start another wait or stop because the work is done"
  if [[ -n "$MESSAGE" ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: message: ${MESSAGE}"
  fi
}

overall_start="$(date +%s)"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: start mode=${MODE} repeat=${REPEAT}"

case "$MODE" in
  sleep)
    if ! is_uint "$SECONDS_TO_SLEEP"; then
      echo "--sleep must be a non-negative integer" >&2
      exit 2
    fi
    iteration=1
    while :; do
      iteration_start="$(date +%s)"
      run_sleep_once "$iteration" "$iteration_start"
      iteration_end="$(date +%s)"
      print_wake_message "$((iteration_end - iteration_start))"
      if [[ "$REPEAT" != "forever" && "$iteration" -ge "$REPEAT" ]]; then
        break
      fi
      iteration=$((iteration + 1))
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: restarting wait iteration=${iteration}"
    done
    ;;
  pid)
    if ! is_uint "$PID_TO_FOLLOW"; then
      echo "--pid must be a positive integer" >&2
      exit 2
    fi
    if ! kill -0 "$PID_TO_FOLLOW" 2>/dev/null; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: pid ${PID_TO_FOLLOW} is not running"
      exit 0
    fi
    start="$(date +%s)"
    while kill -0 "$PID_TO_FOLLOW" 2>/dev/null; do
      now="$(date +%s)"
      elapsed=$((now - start))
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: pid ${PID_TO_FOLLOW} still running elapsed=${elapsed}s"
      sleep "$POLL"
    done
    end="$(date +%s)"
    print_wake_message "$((end - start))"
    ;;
esac

overall_end="$(date +%s)"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${LABEL}: finished total_waited=$((overall_end - overall_start))s"
