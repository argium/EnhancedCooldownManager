# Lifecycle Update Orchestration Plan (ECM)

## Purpose
Define a single update orchestration path for all ECM bar modules:

- `PowerBar`
- `ResourceBar`
- `RuneBar`
- `BuffBars`

This design replaces scattered event-driven layout/value calls with one coalesced lifecycle flow.

## Goals

1. **Readiness gating**
   - Do not update until frame/module state is safe.
2. **Deferred second-pass update**
   - Allow one follow-up pass after Blizzard/UI late mutations.
3. **Event-hook coalescing**
   - Collapse update storms into one dispatch cycle per frame/module.
4. **Single update entrypoint**
   - All module-triggered updates must go through `RequestUpdate(...)`.

## Non-Goals

- No new user-facing settings.
- No new standalone `Lifecycle.lua`.
- No ownership changes across `ModuleMixin`, `BarFrame`, `Bars/*`, and `Layout.lua`.

## File Ownership

### `Modules/ModuleMixin.lua`
Owns lifecycle orchestration internals and exposes:

- `RequestUpdate(reason, opts)`
- `IsReady()`

All other orchestration helpers are private.

### `Modules/Layout.lua`
Remains owner of:

- Global event intake (mount/vehicle/rest/combat/zone/cvar/spec)
- Global hide/fade logic
- Frame registration (`RegisterFrame` / `UnregisterFrame`)

It should no longer directly call `UpdateLayout()`. It dispatches via:

`frame:RequestUpdate(C.LIFECYCLE_REASON_LAYOUT, { forceLayout = true })`

## Constants (`Constants.lua`)

Add:

- `LIFECYCLE_REASON_LAYOUT`
- `LIFECYCLE_REASON_VALUE`
- `LIFECYCLE_REASON_VIEWER`
- `LIFECYCLE_REASON_EDITMODE`
- `LIFECYCLE_REASON_PROFILE`
- `LIFECYCLE_SECOND_PASS_DELAY = 0`
- `LIFECYCLE_READINESS_RETRY_DELAY = 0.05`
- `LIFECYCLE_MAX_READINESS_RETRIES = 10`

## Public Lifecycle API

### `RequestUpdate(reason, opts)`
Only orchestration entrypoint from module event handlers/hooks.

Behavior:

- Record `reason` in pending reason set.
- If `opts.forceLayout`, also record `LIFECYCLE_REASON_LAYOUT`.
- If `opts.secondPass`, request one deferred follow-up pass.
- Queue exactly one immediate dispatcher tick if not already queued.

### `IsReady()`
Readiness gate before lifecycle dispatch executes.

Base readiness checks:

- Module enabled
- `InnerFrame` exists
- `GlobalConfig` exists
- `ModuleConfig` exists

Module-specific overrides are allowed (notably `BuffBars`).

## Internal State (`ModuleMixin` per-instance)

- `_pendingReasons` (set/map)
- `_dispatchPending` (boolean)
- `_secondPassPending` (boolean)
- `_readinessRetryCount` (number)

## Internal Dispatch Flow (Private)

1. `RequestUpdate(...)` records reasons and schedules a dispatch tick.
2. Dispatcher checks `IsReady()`.
3. If not ready:
   - Retry after `LIFECYCLE_READINESS_RETRY_DELAY`.
   - Stop after `LIFECYCLE_MAX_READINESS_RETRIES`.
4. If ready:
   - Layout reasons (`LAYOUT`, `VIEWER`, `EDITMODE`, `PROFILE`) call `UpdateLayout()`.
   - Value-only reason (`VALUE`) calls throttled value path (`ThrottledRefresh()`).
5. If second-pass requested and not already pending:
   - Schedule one deferred pass using `LIFECYCLE_SECOND_PASS_DELAY`.
   - Deferred pass re-enters via `RequestUpdate(...)`.

## Readiness Rules by Bar Type

### PowerBar / ResourceBar / RuneBar
Use base `IsReady()` + required frame parts:

- `InnerFrame.StatusBar` exists
- Additional expected subframes exist where required (`TicksFrame`, etc.)

### BuffBars
Override `IsReady()` to additionally require:

- `_G["EssentialCooldownViewer"_BUFFBAR]` exists
- Viewer supports `GetChildren` or `GetItemFrames`
- Current attach state is valid for child enumeration and layout

## Migration Plan by Module

### `Bars/PowerBar.lua`

- `OnUnitPowerUpdate` should call `RequestUpdate(LIFECYCLE_REASON_VALUE)`.
- Remove direct event-path calls to `ThrottledRefresh()`.

### `Bars/ResourceBar.lua`

- Replace direct `"ThrottledRefresh"` event mapping with explicit handlers.
- Handlers call `RequestUpdate(LIFECYCLE_REASON_VALUE)`.

### `Bars/RuneBar.lua`

- `RUNE_POWER_UPDATE` routes to `RequestUpdate(LIFECYCLE_REASON_VALUE)`.
- `OnUpdate` also routes to `RequestUpdate(LIFECYCLE_REASON_VALUE)`.
- Keep rune calculation/rendering in `Refresh()`.

### `Bars/BuffBars.lua`

Replace direct scheduling/layout triggers with `RequestUpdate(...)`:

- Child `SetPoint` hook
- Child `OnShow` / `OnHide` hooks
- Viewer `OnShow` / `OnSizeChanged`
- Edit mode entry/exit hooks
- `UNIT_AURA`

Second-pass stabilization should be requested through `RequestUpdate(..., { secondPass = true })`, not ad-hoc timers.

### `Modules/Layout.lua`

Replace direct fanout:

- `ModuleMixin:UpdateLayout()`

With dispatch:

- `ModuleMixin:RequestUpdate(C.LIFECYCLE_REASON_LAYOUT, { forceLayout = true })`

## Removed / Folded Behavior

### Remove

- `ModuleMixin:ScheduleLayoutUpdate()`
- Module-level direct event/hook calls to `ThrottledRefresh()`
- Module-local deferred update timers used for stabilization (`C_Timer.After(0, ...)`)

### Fold into lifecycle internals

- Layout scheduling/coalescing
- Value scheduling/coalescing
- Readiness retry/backoff
- Deferred second-pass behavior

## Invariants

1. Layout mutation only occurs in `UpdateLayout()`.
2. Value mutation only occurs in `Refresh()`.
3. Event handlers/hooks do not directly mutate layout/value.
4. Module-triggered updates enter through `RequestUpdate(...)`.

## Test and Validation Checklist

1. **Startup**
   - `/reload` with each bar enabled.
   - Verify no nil errors and stable initial draw.
2. **Event storms**
   - Rapid power/rune/aura changes.
   - Verify coalescing (no layout thrash).
3. **BuffBars stabilization**
   - Rapid aura adds/removes.
   - Verify final anchors and styling are correct after second pass.
4. **Edit mode**
   - Enter/exit repeatedly.
   - Verify no stacked/duplicated anchors.
5. **Global events**
   - mount/vehicle/rest/zone/spec/cvar transitions.
   - Verify all bars refresh via lifecycle dispatch.
6. **Rune behavior**
   - DK rune reorder/recharge under combat load.
   - Verify no flicker/stale order.

## Acceptance Criteria

- All bar modules use `RequestUpdate(...)` for event/hook-triggered updates.
- `IsReady()` gates all dispatch execution.
- `ScheduleLayoutUpdate()` is removed.
- Deferred second-pass is centralized and deduplicated.
- `Layout.lua` dispatches lifecycle requests instead of running direct layout updates.
- All four bar modules are migrated: `PowerBar`, `ResourceBar`, `RuneBar`, `BuffBars`.

## Recommended Rollout Sequence

1. Add lifecycle constants.
2. Add lifecycle internals in `ModuleMixin`.
3. Migrate `PowerBar`, `ResourceBar`, `RuneBar`.
4. Migrate `BuffBars` with readiness override.
5. Update `Layout.lua` dispatch integration.
6. Remove obsolete scheduling/deferred code.
7. Execute validation checklist.
