# Enhanced Cooldown Manager

WoW addon: customizable resource bars anchored to Blizzard's Cooldown Manager viewers.

## Guidelines

- No upvalue caching (e.g., `local math_floor = math.floor`)
- Config: `EnhancedCooldownManager.db.profile` with module subsections
- Follow WoW UI performance best practices. Avoid unnecessary updates, use frame pooling, and minimize CPU/memory usage.

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
