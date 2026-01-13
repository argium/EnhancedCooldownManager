# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Enhanced Cooldown Manager (ECM) is a World of Warcraft addon that displays customizable resource bars anchored to Blizzard's Cooldown Manager viewer UI frames. It provides visual feedback for player power resources (mana, rage, energy, etc.) and segmented resources (DK runes, DH souls, Paladin Holy Power, Warrior Whirlwind stacks).

## Development

- **No build step** - Changes are live-reloaded in WoW via `/reload`
- **Lua 5.1** - WoW standard
- **Framework:** Ace3 (AceAddon-3.0, AceEvent-3.0, AceConsole-3.0, AceDB-3.0)
- **Slash commands:** `/ecm on|off|toggle|debug`
- **API docs:** https://www.townlong-yak.com/framexml/beta/Blizzard_APIDocumentation

## Architecture

### File Structure
- `EnhancedCooldownManager.lua` – Ace3 addon bootstrap, defaults, config type definitions, slash commands
- `Utilities.lua` – Shared helpers: `ns.Util.*` (PixelSnap, GetBgColor, GetBarHeight, GetTexture, GetFontPath, ApplyBarAppearance, ApplyBarLayout, ApplyFont, GetViewerAnchor, GetPreferredAnchor)
- `PowerBars.lua` – AceModule for primary resource bar (mana/rage/energy/runic power/etc.)
- `SegmentBar.lua` – AceModule for fragmented resources (DK runes, DH souls, Paladin Holy Power, Fury Warrior Whirlwind stacks)
- `BuffBars.lua` – AceModule that styles Blizzard's BuffBarCooldownViewer children (does NOT create frames)
- `ViewerHook.lua` – Central event handler for mount/spec changes; triggers layout updates across modules

### Bar Anchor Chain
Bars stack vertically below `EssentialCooldownViewer`:
```
EssentialCooldownViewer (Blizzard icons)
    ↓ PowerBar (if visible)
    ↓ SegmentBar (if visible)
    ↓ BuffBarCooldownViewer (Blizzard, restyled by BuffBars)
```
Use `Util.GetPreferredAnchor(addon, excludeModule)` to find the bottom-most visible ECM bar.

### Common Module Interface
All bar modules expose:
| Method | Description |
|--------|-------------|
| `:GetFrame()` | Lazy-creates and returns the module's frame |
| `:GetFrameIfShown()` | Returns frame only if currently visible (for anchor chaining) |
| `:SetExternallyHidden(bool)` | Hides frame externally (e.g., mounted); does NOT unregister events |
| `:UpdateLayout()` | Positions/sizes/styles the frame, then calls `:Refresh()` |
| `:Refresh()` | Updates values only (colors, text, progress) |
| `:Enable()` / `:Disable()` | Registers/unregisters power/aura events |

### Configuration
- All settings in `EnhancedCooldownManager.db.profile`
- Module-specific: `profile.powerBar`, `profile.segmentBar`, `profile.dynamicBars`
- Global defaults: `profile.global.{barHeight, texture, font, fontSize, barBgColor}`
- Colors: `profile.powerTypeColors.colors[PowerType]`, `.special.deathKnight.runes[specID]`

## Critical: Secret Value Handling

Many values returned from Blizzard APIs (spell IDs, spell names, aura data, UI text) are "secret values" with severe restrictions:
- **CANNOT** compare them (`==`, `~=`, `<`, `>`) - this will error
- **CANNOT** use in string concatenation or with `tonumber()`/`tostring()`
- **CANNOT** use `pcall` to bypass these restrictions
- **CAN** pass by reference to functions that accept them

When working with potentially secret values:
1. Never compare the value directly
2. Use `issecretvalue(v)` to check if a value is secret
3. Use `canaccessvalue(v)` to check if you can safely use the value
4. Pass to `SafeGetDebugValue()` for debug output

**Forbidden APIs** (due to secret restrictions):
- `C_UnitAuras.GetPlayerAuraBySpellID(spellID)`
- `C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)`

Use APIs that rely on `auraInstanceId` instead.

**Secret values include:**
- Spell IDs from `GetSpellID()`
- Spell names from `fontString:GetText()` on buff/aura bars
- Aura data from various C_UnitAuras functions

## WoW Text Formatting

Use escape sequences to format text in chat, tooltips, and UI strings:

| Sequence | Description |
|----------|-------------|
| `\|cAARRGGBB` | Set text color (AA=alpha, RR=red, GG=green, BB=blue in hex) |
| `\|r` | Reset to default color |

**Example:**
```lua
"|cff00ff00Green text|r normal text"  -- ff=full alpha, 00=red, ff=green, 00=blue
"|cffff0000Red|r and |cff0088ffBlue|r"
```

Common colors: `ff00ff00` (green), `ffff0000` (red), `ffffff00` (yellow), `ffaaaaaa` (grey).

## Engineering Guidelines

- Implement EXACTLY and ONLY what is requested
- Do not reach into another module's internals
- Prefer `assert()`/`error()` with clear messages for internal invariants
- For Blizzard/third-party frames where methods may not exist, prefer `pcall` over `type(...)` checks
- Do not add `type(x) == "function"` guards except for future-update functions (`issecretvalue`, `canaccessvalue`, etc.)
- Remove unused code; minimize duplication via shared helpers
- **Do NOT use upvalue caching** (e.g., `local math_floor = math.floor`) - use standard Lua/WoW globals directly

## Serena MCP Tools (Lua Plugin)

Serena provides semantic code navigation and editing for this Lua codebase. Prefer these tools over raw text search/replace when working with symbols.

### Code Navigation
| Tool | Use Case |
|------|----------|
| `get_symbols_overview` | First step to understand a file - lists all functions, methods, variables |
| `find_symbol` | Search by name pattern (e.g., `PowerBars:Refresh`), optionally include source body |
| `find_referencing_symbols` | Find all callers/usages of a symbol |
| `search_for_pattern` | Regex search with context lines, flexible file filtering |

### Code Editing
| Tool | Use Case |
|------|----------|
| `replace_symbol_body` | Replace entire function/method definition |
| `insert_before_symbol` / `insert_after_symbol` | Add new code adjacent to existing symbols |
| `rename_symbol` | Rename across entire codebase |
| `replace_content` | Regex-based find/replace within files (for partial edits) |

### Lua Symbol Types Recognized
Variables, Objects, Functions, Methods, Strings, Arrays - with nesting depth support for class methods.

### Best Practices
- Use `get_symbols_overview` before reading full files
- Use `find_symbol` with `include_body=true` only when you need the source
- Use `find_referencing_symbols` before renaming/changing signatures
- Prefer `replace_symbol_body` over text-based edits for whole functions
- Use `replace_content` with regex for surgical line-level changes
