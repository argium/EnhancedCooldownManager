# Movable PowerBar and SegmentBar Feature

## Status: COMPLETED

Implementation completed on 2026-01-21. All code changes merged, ready for testing.

## Feature Summary

Added `autoPosition` toggle to both PowerBar and SegmentBar. When disabled, bars integrate with **LibEQOLEditMode-1.0** for free positioning via Blizzard's Edit Mode UI with an in-frame width slider.

## Files Modified

### Library Added
- `Libs/LibEQOL/` - Copied from SenseiClassResourceBar/Libs/LibEQOL/

### Core Files
1. **EnhancedCooldownManager.toc** - Added `Libs\LibEQOL\LibEQOL.xml` loading
2. **EnhancedCooldownManager.lua** - Added config defaults:
   - `powerBar.autoPosition = true`
   - `powerBar.barWidth = 300`
   - `segmentBar.autoPosition = true`
   - `segmentBar.barWidth = 300`
   - `editModeLayouts.powerBar = {}`
   - `editModeLayouts.segmentBar = {}`

3. **Utilities.lua** - Modified `GetPreferredAnchor()` to exclude bars with `autoPosition=false` from anchor chain

4. **Modules/PowerBar.lua** - Added:
   - `local LEM = LibStub("LibEQOLEditMode-1.0", true)`
   - `RegisterWithEditMode()` function
   - `UnregisterFromEditMode()` function
   - `GetCurrentLayoutName()` function
   - Modified `UpdateLayout()` to handle manual positioning

5. **Modules/SegmentBar.lua** - Same pattern as PowerBar

6. **Options.lua** - Added `positioningSettings` group to both PowerBarOptionsTable and SegmentBarOptionsTable with:
   - Description text explaining the feature
   - `autoPosition` toggle
   - `barWidth` range slider (hidden when autoPosition=true)

## Anchor Chain Behavior

| PowerBar | SegmentBar | BuffBars anchors to |
|----------|------------|---------------------|
| auto=true | auto=true | SegmentBar |
| auto=true | auto=false | PowerBar |
| auto=false | auto=true | SegmentBar (to viewer) |
| auto=false | auto=false | Viewer |

## Per-Layout Storage

Positions saved per EditMode layout in:
```lua
profile.editModeLayouts.powerBar[layoutName] = { x, y, width }
profile.editModeLayouts.segmentBar[layoutName] = { x, y, width }
```

## Testing Checklist (Not Yet Verified)

1. [ ] Default unchanged: autoPosition=true by default, bars anchor normally
2. [ ] Toggle off: Disabling autoPosition allows EditMode positioning
3. [ ] EditMode panel: Selecting bar shows width slider in EditMode
4. [ ] Drag positioning: Bar can be dragged in EditMode
5. [ ] Layout switching: Position persists per EditMode layout
6. [ ] Anchor chain: BuffBars anchors correctly based on autoPosition state
7. [ ] Reload persistence: Positions survive /reload

## Key Implementation Details

- LibEQOL uses `LEM.SettingType.Slider` (not `type = "slider"`)
- Frame registration happens in `RegisterWithEditMode()` only when `autoPosition=false`
- `_editModeRegistered` flag prevents duplicate registration
- `UnregisterFromEditMode()` clears the flag (LibEQOL has no explicit unregister)
- EditMode name labels: "ECM: Power Bar" and "ECM: Segment Bar"
