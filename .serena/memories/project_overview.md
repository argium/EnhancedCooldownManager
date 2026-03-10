# Enhanced Cooldown Manager - Project Overview

## Purpose
A World of Warcraft retail addon that creates a clean combat HUD around Blizzard's built-in Cooldown Manager. Provides inline resource bars (power, class resources, runes, aura/buff bars) and item icon cooldowns anchored to the native UI.

## Tech Stack
- **Language**: Lua 5.1 (WoW embedded runtime)
- **Libraries**: AceAddon-3.0, AceEvent-3.0, AceConsole-3.0, AceDB-3.0, LibSharedMedia-3.0, LibSerialize, LibDeflate, LibEQOL, LibSettingsBuilder
- **Testing**: Busted (Lua test framework)
- **Linting**: luacheck
- **License**: GNU GPLv3, Author: Argium

## Codebase Structure
```
ECM_Constants.lua      -- All constants (MANDATORY location)
ECM_Defaults.lua       -- Default configuration values
ECM.lua                -- Main addon entry point (AceAddon)
Helpers/               -- Shared utilities and mixins (ModuleMixin, FrameMixin, BarMixin, etc.)
Modules/               -- Feature modules (PowerBar, ResourceBar, RuneBar, BuffBars, ItemIcons)
UI/                    -- Settings/options panels
Libs/                  -- Third-party libraries (do not edit)
Tests/                 -- Busted test suite with stubs/ for WoW API mocks
Media/                 -- Fonts, textures
```

## Architecture
- AceAddon-3.0 based with AceDB-3.0 for saved variables
- Modules use `ModuleMixin` for config: `self:GetGlobalConfig()`, `self:GetModuleConfig()`
- `FrameMixin` for frame lifecycle; `BarMixin` for bar rendering
- Loose coupling via events for inter-module communication
- Private methods/fields prefixed with underscore (_)
- Global table `ECM` for cross-file constants and mixins
- Load order: Constants -> Defaults -> Helpers -> ECM.lua -> Modules -> UI

## Secret Values (WoW Taint System)
- `UnitPowerMax`, `UnitPower`, `UnitPowerPercent`, `C_UnitAuras.GetUnitAuraBySpellID` return secret values
- Cannot compare, test, or use as table keys
- Use `CurveConstants.ScaleTo100` for adjusted values
- NEVER nil check or wrap `issecretvalue()` / `issecrettable()` built-ins
