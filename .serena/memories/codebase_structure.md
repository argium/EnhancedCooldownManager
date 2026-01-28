# Codebase Structure

## Top-level entrypoints
- `EnhancedCooldownManager.toc`: addon manifest; defines load order and embedded libraries.
- `EnhancedCooldownManager.lua`: main addon object initialization (AceAddon) and high-level UI flows (dialogs, chat command handling, etc.).
- `Defaults.lua`: default profile/config setup (must load before main addon file).

## Major folders
- `Bars/`
  - Implements the actual bar modules (e.g., PowerBar, ResourceBar, RuneBar, BuffBars).
- `Mixins/`
  - Shared mixins used by bar frames/modules.
  - Notably includes BarFrame/layout/appearance helpers and module lifecycle utilities.
- `Modules/`
  - Cross-cutting addon modules (e.g., ViewerHook, ImportExport, Utilities, TraceLog).
  - `ViewerHook.lua` coordinates Blizzard viewer frames, layout updates, and hide/show/fade behavior.
- `UI/`
  - Options/config UI and bug reporting UI.
  - `UI/Widgets/` contains custom widgets used by options UI.
- `Libs/`
  - Embedded third-party libraries (Ace3, LibSharedMedia-3.0, LibSerialize, LibDeflate, LibEQOL, etc.).
- `Media/`
  - Fonts and addon media assets.

## Load order notes (from .toc)
- Ace3/other libs load first.
- Core modules/utilities load before `Defaults.lua` and `EnhancedCooldownManager.lua`.
- Mixins load before bar modules.
- Bar modules and finally `Modules/ViewerHook.lua`.
