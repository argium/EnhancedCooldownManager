# EnhancedCooldownManager — Project Overview

## Purpose
EnhancedCooldownManager (ECM) is a World of Warcraft addon that provides standalone, customizable resource bars anchored to Blizzard’s Cooldown Manager viewers.

## What it does
- Adds multiple bars (Power, Resource, Rune) and restyles Blizzard’s Buff Bar viewer.
- Supports flexible anchoring: bars can anchor to the viewer, chain from each other, or be positioned independently.
- Exposes configuration in-game via slash command `/ecm`.

## Key constraints / game rules
- Many UI operations are restricted in combat (e.g., ReloadUI is blocked). Code commonly checks `InCombatLockdown()`.
- “Secret values” may appear in combat/instances; comparisons/concatenation/type conversion can be restricted. Use `issecretvalue(v)` / `canaccessvalue(v)` and `SafeGetDebugValue()` for debug output when needed.

## Tech stack
- Language: Lua (WoW addon environment)
- Framework/libs: Ace3 (AceAddon, AceEvent, AceConsole, AceDB, AceConfig, AceGUI, etc.)
- Media: LibSharedMedia-3.0
- Serialization/import/export: LibSerialize, LibDeflate
- Misc UI helpers: LibEQOL

## Storage
- SavedVariables: `EnhancedCooldownManagerDB`
- Runtime config convention: `EnhancedCooldownManager.db.profile` (module subsections under the profile)
