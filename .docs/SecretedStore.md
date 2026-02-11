# SecretedStore + Layout Discovery Refactor (Implemented)

## Implementation Summary

This change is fully implemented and now enforces the new ownership model:

1. `Layout.lua` owns scan orchestration and discovery persistence.
2. `BuffBars.lua` only collects discovery tuples.
3. `BuffBarColors.lua` owns color policy/storage and color-key migration.
4. `SecretedStore.lua` is generic infrastructure and intentionally reads/writes active profile state.

## New/Changed Files

- `Modules/SecretedStore.lua` (new)
- `Modules/Layout.lua`
- `Modules/BuffBarColors.lua`
- `Bars/BuffBars.lua`
- `Options/BuffBarsOptions.lua`
- `Constants.lua`
- `EnhancedCooldownManager.lua`
- `EnhancedCooldownManager.toc`
- `CLAUDE.md`
- `docs/SecretedStore.md`
- `docs/REFACTOR.md`

## API Changes

### New: `SecretedStore` (generic module)

Added in `Modules/SecretedStore.lua`:

- `RegisterProfileCallbacks(db)`
- `OnProfileChanged()`
- `GetProfileRoot()`
- `GetPath(pathSegments, createMissing)`
- `SetPath(pathSegments, value)`
- `IsSecretValue(v)`
- `IsSecretTable(v)`
- `CanAccessValue(v)`
- `CanAccessTable(v)`
- `NormalizeString(raw, opts)`
- `NormalizeNumber(raw, opts)`
- `NormalizeRecord(record, fieldSpecs)`
- `HasIndexedMapsChanged(oldA, newA, oldB, newB, comparer)`

Notes:
- This is an intentional exception to bar-module config rules.
- Profile callbacks are self-registered once from addon init.

### New in Layout/ECM

Added in `Modules/Layout.lua`:

- `ECM.RegisterScanner(name, scannerFn, opts)`
- `ECM.UnregisterScanner(name)`
- `ECM.RefreshBuffBarDiscovery(reason)`
- `ECM.GetBuffBarDiscoveryCache()`
- `ECM.GetBuffBarDiscoverySecondaryKeyMap()`

Scanner constant added in `Constants.lua`:

- `SCANNER_BUFFBARS_DISCOVERY = "BuffBarsDiscovery"`

### Changed in BuffBars

In `Bars/BuffBars.lua`:

- Removed: `RefreshBarCache()`
- Added: `CollectScanEntries()` returning ordered `{ spellName, textureFileID }[]`
- Secret-value checks now use `SecretedStore.IsSecretValue(...)`
- Edit mode exit calls `ECM.RefreshBuffBarDiscovery("edit_mode_exit")` before immediate restyle

### Changed in BuffBarColors

In `Modules/BuffBarColors.lua`:

Removed stale discovery APIs:
- `GetBarCache()`
- `GetBarTextureMap()`
- `RefreshMaps(...)`

Added reconciliation API:
- `ResolveDiscoveryColors(classID, specID, oldCache, oldTextureMap, nextCache, nextTextureMap)`

Current BuffBarColors scope:
- `perSpell` color storage
- default color get/set
- color key policy (`GetColorKey`)
- migration from numeric secondary keys to resolved spell-name keys

### Changed in Options

In `Options/BuffBarsOptions.lua`:

- Discovery read path changed to:
  - `ECM.GetBuffBarDiscoveryCache()`
  - `ECM.GetBuffBarDiscoverySecondaryKeyMap()`
- "Refresh Spell List" now calls:
  - `ECM.RefreshBuffBarDiscovery("options_refresh")`

## Wiring/Load Order

### `EnhancedCooldownManager.toc`

Added:
- `Modules\SecretedStore.lua`

### `EnhancedCooldownManager.lua`

In `OnInitialize`:
- `ns.SecretedStore.RegisterProfileCallbacks(self.db)`

## Naming Cleanup

Terminology normalized to **SecondaryKeyMap**.

Renamed:
- `GetBuffBarDiscoveryAltKeyMap` -> `GetBuffBarDiscoverySecondaryKeyMap`

Applied across code and docs.

## Storage Shape (unchanged)

No schema migration required. Storage remains:

- `buffBars.colors.perSpell[classID][specID][colorKey] = ECM_Color`
- `buffBars.colors.cache[classID][specID][index] = { spellName, lastSeen }`
- `buffBars.colors.textureMap[classID][specID][index] = secondaryKey`

## Removed Stale Architecture

Removed stale references and behavior for:

- BuffBarColors discovery-cache ownership.
- BuffBars calling BuffBarColors discovery refresh APIs.
- AltKeyMap terminology.
- Old docs implying `BuffBarColors.Init(cfg)` lifecycle ownership.

## Validation Completed

1. Syntax checks passed:
- `luac -p Constants.lua Modules/SecretedStore.lua Modules/Layout.lua Modules/BuffBarColors.lua Bars/BuffBars.lua Options/BuffBarsOptions.lua EnhancedCooldownManager.lua`
- `luac -p Modules/Layout.lua Options/BuffBarsOptions.lua`

2. Stale-reference sweeps:
- No references to removed APIs (`RefreshMaps`, `GetBarCache`, `GetBarTextureMap`, `RefreshBarCache`).
- No `AltKeyMap` references remain.

3. Diff hygiene:
- `git diff --check` clean.
