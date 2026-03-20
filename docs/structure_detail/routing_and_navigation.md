# Routing & Navigation

**Purpose**: Document non-obvious routing patterns, URL-state synchronization, and context availability.
**Source of Truth**: `src/app/routes.tsx`, `src/app/App.tsx`, `src/app/Layout.tsx`

## Route nesting

```
/ or /home          HomePage (no Layout, no auth)
/share/:shareId     SharePage (no Layout, no auth)
/payments/*         PaymentSuccess/Cancel (no Layout, no auth)

<Layout>            Auth guard + header + panes + Outlet
  /tools/:toolName  Tool pages (main content area)
  /shots            ShotsPage
  /art              ArtPage
```

Logged-in users hitting `/` redirect to `/tools/travel-between-images`. Unauthenticated users inside `Layout` redirect to `/home`.

## Context provider hierarchy (App.tsx)

All providers wrap the **entire** router. Order matters for dependency:

| Layer (outer -> inner) | What it provides |
|---|---|
| `QueryClientProvider` | React Query |
| `AuthProvider` | Session / user |
| `UserSettingsProvider` | Persisted UI settings |
| `ProjectProvider` | `selectedProjectId`, `setSelectedProjectId` |
| `RealtimeProvider` | Supabase realtime channels |
| `ShotsProvider` | `useShots()` data, scoped to selected project |
| `GenerationTaskProvider` | Active generation tasks |
| `IncomingTasksProvider` | Incoming task notifications |
| `PanesProvider` | Pane open/locked/width state |
| `LastAffectedShotProvider` | Last-modified shot ID (for highlight) |
| `CurrentShotProvider` | `currentShotId` / `setCurrentShotId` |
| `ToolPageHeaderProvider` | Injected header content per tool page |

Since all contexts are above the router, every route (including non-Layout routes) can access them. Layout adds the visual chrome (header, panes, footer) but not the data contexts.

## Shot selection via URL hash

Shot identity is encoded in the **hash fragment**, not a route param or query string:

```
/tools/travel-between-images#<shot-uuid>
```

Three hooks coordinate this:

| Hook | File | Responsibility |
|---|---|---|
| `useShotNavigation` | `src/shared/hooks/useShotNavigation.ts` | Imperative navigation API: `navigateToShot`, `navigateToNextShot`, etc. |
| `useUrlSync` | `src/tools/travel-between-images/hooks/useUrlSync.ts` | Keeps hash in sync with `currentShotId`. Clears selection when hash is removed. |
| `useHashDeepLink` | `src/tools/travel-between-images/hooks/useHashDeepLink.ts` | Handles cold-start deep links: validates UUID, resolves project from shot, grace period while loading. |

**Flow**: `useShotNavigation.navigateToShot()` sets `currentShotId` in context **and** calls `navigate('/tools/travel-between-images#<id>')`. `useUrlSync` then keeps the two in sync on subsequent changes. `useHashDeepLink` handles the reverse: user lands on a URL with a hash and no project loaded yet.

## Navigation state (`location.state`)

| State key | Type | Purpose |
|---|---|---|
| `fromShotClick` | `boolean` | Distinguishes intentional shot navigation from browser back. When `false` + no hash, `useUrlSync` clears selection (back-to-list). |
| `shotData` | `Shot` | Optimistic shot data for newly created shots (avoids "not found" flash before cache syncs). |
| `isNewlyCreated` | `boolean` | Extends grace period in `useHashDeepLink` so new shots aren't redirected away. |
| `openSettings` | `boolean` | Triggers settings modal open from any route (checked in `Layout`). |
| `openSegmentSlot` | `string` | Deep-links to a specific segment slot in shot editor. |

## `useShotNavigation` behavior

- **`navigateToShot`**: Sets context, navigates with hash, scrolls to top, closes mobile panes. Passes `{ fromShotClick: true, shotData }` in state.
- **`navigateToNextShot` / `navigateToPreviousShot`**: Always use `replace: true` (no history entry per shot when cycling).
- **`navigateToShotEditor`**: Clears `currentShotId`, navigates without hash.
- **Mobile**: Dispatches `mobilePaneOpen` event with `side: null` to close open panes.
- **Scroll**: Uses `requestAnimationFrame` + configurable delay. Also dispatches `app:scrollToTop` custom event for mobile split-view scroll container.

## Layout shot cleanup

`Layout.tsx` clears `currentShotId` when navigating **away from** `/tools/travel-between-images` (but not when navigating **to** it). This prevents stale shot state when switching tools.

## Key invariants

1. **Hash is truth for shot selection** -- `currentShotId` context and URL hash must agree. `useUrlSync` enforces this.
2. **`fromShotClick` prevents accidental deselection** -- Without it, `useUrlSync` would clear the shot on any navigation that happens to lack a hash momentarily.
3. **`replace: true` for prev/next** -- Cycling shots must not pollute browser history.
4. **Deep links resolve project** -- `useHashDeepLink` fetches `project_id` from the shot row when no project is selected, so direct URLs work.
5. **All data contexts wrap the router** -- No context is Layout-only; even unauthenticated pages can read (empty) context.
6. **One query-param exception** -- Onboarding uses `?shot=<id>` (not hash) for the Getting Started redirect. This is a one-off in `Layout.tsx`.
