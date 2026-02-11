# SecretedStore + Discovery Architecture

## Summary
This refactor splits buff bar responsibilities into three clear layers:

1. `Layout.lua` owns scan orchestration and discovery-cache persistence.
2. `BuffBarColors.lua` owns color policy and color-key migration.
3. `SecretedStore.lua` provides generic secret-safe/profile helpers only.

This keeps domain logic out of generic utilities and keeps discovery state close to scan orchestration.

## Ownership

### `Modules/SecretedStore.lua`
Owns generic reusable helpers:
- Profile callback registration and active-profile rebinding.
- Generic nested profile path access (`GetPath`, `SetPath`).
- Secret API wrappers (`IsSecretValue`, `IsSecretTable`, `CanAccessValue`, `CanAccessTable`).
- Generic normalizers (`NormalizeString`, `NormalizeNumber`, `NormalizeRecord`).
- Generic indexed-map change detection (`HasIndexedMapsChanged`).

`SecretedStore` is an intentional exception to ECMFrame module config rules: it reads/writes
`ECM.db.profile` directly so it always tracks the active profile.

### `Modules/Layout.lua`
Owns discovery orchestration and persistence:
- Scanner registration (`ECM.RegisterScanner`, `ECM.UnregisterScanner`).
- Buff-bar discovery scanner (`BuffBarsDiscovery`).
- Discovery cache writes to profile storage (`buffBars.colors.cache`, `buffBars.colors.textureMap`).
- Public read APIs:
  - `ECM.GetBuffBarDiscoveryCache()`
  - `ECM.GetBuffBarDiscoverySecondaryKeyMap()`
  - `ECM.RefreshBuffBarDiscovery(reason)`

### `Bars/BuffBars.lua`
Owns scan data collection only:
- `CollectScanEntries()` returns ordered tuples `{ spellName, textureFileID }`.
- Does not own cache persistence.

### `Modules/BuffBarColors.lua`
Owns color behavior only:
- Per-class/spec per-key color CRUD.
- Default color get/set.
- Color-key selection (`GetColorKey`).
- Reconciliation/migration from secondary numeric keys to spell-name keys:
  - `ResolveDiscoveryColors(classID, specID, oldCache, oldTextureMap, nextCache, nextTextureMap)`

## Data Flow

1. Layout pass runs scanner(s).
2. BuffBars scanner calls `BuffBars:CollectScanEntries()`.
3. Layout normalizes entries (via `SecretedStore.NormalizeRecord`) and builds next discovery maps.
4. Layout calls `BuffBarColors.ResolveDiscoveryColors(...)` to resolve/migrate color keys.
5. Layout writes next discovery maps to profile.
6. Options reads discovery maps from Layout APIs and colors from `BuffBarColors`.

## Storage Shape (unchanged)
No schema migration required. Existing shape is preserved:

- `buffBars.colors.perSpell[classID][specID][colorKey] = ECM_Color`
- `buffBars.colors.cache[classID][specID][index] = { spellName, lastSeen }`
- `buffBars.colors.textureMap[classID][specID][index] = textureFileID`

## Public Interfaces

### `SecretedStore`
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

### `Layout` / `ECM`
- `RegisterScanner(name, scannerFn, opts)`
- `UnregisterScanner(name)`
- `RefreshBuffBarDiscovery(reason)`
- `GetBuffBarDiscoveryCache()`
- `GetBuffBarDiscoverySecondaryKeyMap()`

### `BuffBars`
- `CollectScanEntries()`

### `BuffBarColors`
- `GetColorKey(spellName, textureFileID)`
- `LookupSpellColor(colorKey)`
- `GetSpellColor(colorKey)`
- `GetDefaultColor()`
- `SetDefaultColor(r, g, b)`
- `SetSpellColor(colorKey, r, g, b)`
- `ResetSpellColor(colorKey)`
- `HasCustomSpellColor(colorKey)`
- `GetPerSpellColors()`
- `ResolveDiscoveryColors(classID, specID, oldCache, oldTextureMap, nextCache, nextTextureMap)`

## Notes

- Scanning is triggered from layout passes, not from `BuffBars:UpdateLayout()`.
- Options "Refresh Spell List" triggers `ECM.RefreshBuffBarDiscovery("options_refresh")`.
- Secret APIs are always feature-gated through `SecretedStore` wrappers.
