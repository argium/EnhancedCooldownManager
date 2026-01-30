# Enhanced Cooldown Manager

WoW addon: customizable resource bars anchored to Blizzard's Cooldown Manager viewers.

## Guidelines

- No upvalue caching (e.g., `local math_floor = math.floor`)
- Config: `EnhancedCooldownManager.db.profile` with module subsections
- Follow WoW UI performance best practices. Avoid unnecessary updates, use frame pooling, and minimize CPU/memory usage.

## Config Structure

Profile config key sections:

- `global`: Shared bar appearance (height, font, texture, background color)
- `powerBar`, `resourceBar`, `runeBar`: Per-bar config with `anchorMode`, `colors`, `border`
- `buffBars`: Buff bar config including nested `colors` table:
  - `buffBars.colors.perBar[classID][specID][barIndex]` = `{r, g, b}`
  - `buffBars.colors.cache[classID][specID][barIndex]` = cached spell metadata
  - `buffBars.colors.defaultColor` = default RGB
  - `buffBars.colors.selectedPalette` = palette name or nil
- `powerBarTicks`: Per-class/spec tick mark mappings
- `schemaVersion`: Current schema version (3)

## Migrations

Migrations run in `ECM:RunMigrations()` gated by `schemaVersion`. Always increment schema version when restructuring saved variables.

## Architecture

Blizzard frames: `EssentialCooldownViewer`, `UtilityCooldownViewer`, `BuffIconCooldownViewer`, `BuffBarCooldownViewer`
Bar stack: `EssentialCooldownViewer` → `PowerBar` → `ResourceBar` → `RuneBar` → `BuffBarCooldownViewer`

## Utilities

`Util.Log()` for debug logging, `Util.PixelSnap()` for pixel-perfect positioning. Layout/appearance helpers have moved to BarFrame.

## Secret Values

In combat/instances, many Blizzard API returns are restricted. Cannot compare, convert type, or concatenate.

- `issecretvalue(v)` / `canaccessvalue(v)` to check
- `SafeGetDebugValue()` for debug output
- Avoid `C_UnitAuras` APIs using spellId; use `auraInstanceId` instead except for:
   - Devourer demon hunter buffs
