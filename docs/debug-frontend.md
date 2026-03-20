# Frontend Debugging

Frontend code lives in `./reigh-app/src/`. Logging is opt-in — nothing prints unless you set env flags.

---

## Enabling Logs

```bash
cd reigh-app

# Console only
VITE_DEBUG_LOGS=true npm run dev

# Console + persist to system_logs table
VITE_PERSIST_LOGS=true VITE_DEBUG_LOGS=true npm run dev
```

When persisted, logs appear in `system_logs` with `source_type = 'browser'` and can be queried:

```bash
python scripts/debug.py logs --latest              # Most recent browser session
python scripts/debug.py logs --latest --tag MyTag   # Filter by tag
```

---

## Logging API (`src/shared/lib/logger.ts`)

| Function | Behavior |
|----------|----------|
| `logError(tag, ...data)` | Always logs + persists, even without flags |
| `forceFlush()` | Immediately flush buffer — call before navigation |
| `useRenderLogger(tag, props?)` | Incrementing render counter to spot hot re-renders |

Use unique `[TagName]` prefixes: `console.log('[VideoLoadSpeedIssue] loadTime:', loadTime, 'ms')`.

Debug logs are dev-only (stripped in prod), so temporary instrumentation is safe.
