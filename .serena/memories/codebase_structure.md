# Codebase Structure

## Files
- `EnhancedCooldownManager.lua` - Addon bootstrap, defaults, slash commands
- `Utilities.lua` - Shared helpers (`ns.Util.*`)
- `Options.lua` - AceConfig options panel
- `Modules/PowerBar.lua` - Primary resource bar (mana/rage/energy)
- `Modules/SegmentBar.lua` - Segmented resources (runes, Holy Power)
- `Modules/BuffBars.lua` - Styles Blizzard's BuffBarCooldownViewer
- `Modules/ViewerHook.lua` - Mount/spec change handler

## Bar Anchor Chain
```
EssentialCooldownViewer → PowerBar → SegmentBar → BuffBarCooldownViewer
```
Use `Util.GetPreferredAnchor(addon, excludeModule)` for bottom-most visible bar.

## Module Interface
`:GetFrame()`, `:GetFrameIfShown()`, `:SetExternallyHidden(bool)`, `:UpdateLayout()`, `:Refresh()`, `:Enable()/:Disable()`

## Config
All in `EnhancedCooldownManager.db.profile` with module-specific subsections.
