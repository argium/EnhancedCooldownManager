# Enhanced Cooldown Manager - Current Project Overview

## Purpose
EnhancedCooldownManager is a WoW retail addon that extends Blizzard's built-in Cooldown Manager with chained resource bars, aura/buff bars, and configurable extra icon viewers anchored to the native HUD.

## Current Top-Level Structure
- `Constants.lua`: authoritative constants, module identifiers, schema version, shared lookup tables.
- `Defaults.lua`: default profile data, including `extraIcons.viewers` defaults and power-bar tick mappings.
- `ECM.lua`: AceAddon entry point, profile lifecycle, slash commands, high-level integration.
- `Runtime.lua`: central event/layout dispatcher, fade/hidden enforcement, deferred layout scheduling, module enable/disable.
- `Migration.lua`: frozen saved-variable migrations; current schema version is `12`.
- `SpellColors.lua`: class/spec-scoped buff-bar color store plus runtime-discovered keys exposed to the UI.
- `Modules/`: `PowerBar`, `ResourceBar`, `RuneBar`, `BuffBars`, `ExtraIcons`.
- `UI/`: options sections registered via `ns.OptionsSections[key].RegisterSettings(SB)`.
- `Tests/`: busted suite covering runtime, migrations, modules, and options UI.

## Architecture Notes
- `Runtime.lua` is the single layout pipeline. It handles WoW events, coalesced layout requests, delayed layout updates, global hidden/alpha state, Blizzard frame enforcement, and module iteration.
- `Constants.CHAIN_ORDER` is `PowerBar -> ResourceBar -> RuneBar -> BuffBars`. `Constants.MODULE_ORDER` adds `ExtraIcons`.
- `ExtraIcons` is updated once before chained modules because its main viewer can widen the effective anchor footprint used by downstream width-sensitive layouts.
- Options UIs are now largely driven by `LibSettingsBuilder`'s table/DSL API instead of bespoke settings frame code.
- Buff-bar spell colors are no longer just a simple per-bar cache; they are keyed stores merged with runtime-discovered entries so the UI can operate without reaching into `BuffBars` internals.

## Persistence / Migration Highlights
- Schema changes through V12 include spell-color store normalization and the `itemIcons` -> `extraIcons.viewers` migration.
- Edit-mode position migration seeds per-layout positions from the old single-position model.
- Migration snapshots are intentionally frozen and should not depend on live production helpers.
