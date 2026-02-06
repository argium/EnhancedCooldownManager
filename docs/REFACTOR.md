# Refactor Status and Architecture Notes

## Current Status (2026-02-03)

The addon is undergoing a significant refactor to introduce a mixin-based architecture that separates concerns and reduces code duplication.

### Completed Refactoring

#### ECMFrame Mixin (Mixins\ECMFrame.lua)
**Status:** Fully implemented

**Responsibilities:**
- Frame lifecycle (creation, hiding, showing)
- Layout management (positioning, anchoring, sizing)
- Border and background rendering
- Config access through `self.GlobalConfig` and `self.ModuleConfig`
- Chain anchoring logic via `GetNextChainAnchor`
- Throttling and debouncing for layout updates

**Key Design Decisions:**
- Uses direct field access (`self.GlobalConfig`, `self.ModuleConfig`) rather than getter methods for simplicity
- Layout caching in `_layoutCache` prevents redundant frame operations
- `UpdateLayout()` is the single entry point for all layout changes
- Supports two anchor modes: CHAIN (auto-stacking) and FREE (manual positioning)
- Debouncing via `ScheduleLayoutUpdate()` prevents excessive updates during rapid events
- Chain predecessor selection in `GetNextChainAnchor` does not require predecessor visibility; it uses enabled state, `ShouldShow()`, chain mode, and existing `InnerFrame`
- Global layout passes run chain modules in `C.CHAIN_ORDER` first to keep anchor resolution deterministic

#### BarFrame Mixin (Mixins\BarFrame.lua)
**Status:** Fully implemented

**Responsibilities:**
- StatusBar creation and management
- Value display (current/max with optional text overlay)
- Texture and color management
- Tick mark system with multiple positioning strategies:
  - Resource dividers (even spacing)
  - Value-based markers (e.g., ability cost thresholds)
- Font application

**Key Design Decisions:**
- `GetStatusBarValues()` is abstract - must be implemented by derived modules
- Tick pools are reusable to avoid creating/destroying textures
- Two tick layout methods: `LayoutResourceTicks` (evenly spaced) and `LayoutValueTicks` (positioned at specific values)
- `Refresh()` calls parent `ECMFrame.Refresh()` for base logic, then updates bar-specific elements

#### PowerBar (Bars\PowerBar.lua)
**Status:** Fully migrated to new architecture

**Implements:**
- `GetStatusBarValues()` - returns UnitPower, UnitPowerMax
- `ShouldShow()` - hides mana bars for non-caster DPS specs
- `UpdateTicks()` - positions class/spec-specific ability cost markers
- Mana percent display option

**Event Handling:**
- UNIT_POWER_UPDATE
- UNIT_DISPLAYPOWER
- Various class-specific events

#### ResourceBar (Bars\ResourceBar.lua)
**Status:** Fully migrated to new architecture

**Implements:**
- `GetStatusBarValues()` - handles combo points, chi, holy power, soul shards, essence
- Special handling for Demon Hunter soul fragments (vengeance/devourer specs)
- `ShouldShow()` - only shows when player has active discrete resource
- Resource tick dividers

**Event Handling:**
- UNIT_POWER_UPDATE
- Class/spec-specific events for soul fragments

#### RuneBar (Bars\RuneBar.lua)
**Status:** Mostly complete

**Implements:**
- Death Knight rune display
- Individual rune cooldowns
- Custom CreateFrame with 6 StatusBars (one per rune)

**Notes:**
- Doesn't fully fit the standard BarFrame pattern due to multiple StatusBars
- May need further refinement

### Partially Refactored

#### BuffBars (Bars\BuffBars.lua)
**Status:** Partially complete - uses ECMFrame but not BarFrame

**Current State:**
- Uses ECMFrame mixin for positioning and config access
- Wraps Blizzard's BuffBarCooldownViewer instead of creating its own bars
- Hooks Blizzard frames to apply custom styling
- Implements per-bar color customization with class/spec persistence

**Design Decisions:**
- Does NOT use BarFrame because it manages Blizzard-created child bars, not a single StatusBar
- Override `CreateFrame()` to return existing Blizzard viewer
- Override `UpdateLayout()` to position viewer and style all visible children
- BuffBars icon container is treated as deterministic (`child.Icon`); no cross-object fallback probing
- Color system supports:
  - Per-bar custom colors (stored per class/spec)
  - Default fallback color

**Known Issues:**
- Blizzard frequently resets visibility settings when cooldowns update
- Requires aggressive re-application of visibility settings via hooks
- Edit mode reordering requires cache invalidation via `ResetStyledMarkers()`

**Future Work:**
- Consider extracting color management to a separate module
- Improve hook reliability
- Better handling of dynamic bar creation/destruction

### Not Yet Refactored

#### Mixins\PositionStrategy.lua
**Status:** Likely to be removed

**Reason:** The new ECMFrame mixin handles positioning directly with chain anchoring and free positioning. The PositionStrategy abstraction appears redundant.

## Architecture Patterns

### Mixin Hierarchy

```
ECMFrame (base)
├─> BarFrame (adds StatusBar management)
│   ├─> PowerBar (player power: mana, energy, rage, etc.)
│   ├─> ResourceBar (discrete resources: combo points, chi, etc.)
│   └─> RuneBar (death knight runes)
└─> BuffBars (wraps Blizzard viewer, doesn't use BarFrame)
```

### Method Override Pattern

Derived modules must call their immediate parent's implementation:

```lua
-- CORRECT
function PowerBar:Refresh(force)
    local result = BarFrame.Refresh(self, force)
    if not result then return false end

    -- PowerBar-specific refresh logic
    self:UpdateTicks(...)
    return true
end

-- WRONG - skipping BarFrame
function PowerBar:Refresh(force)
    local result = ECMFrame.Refresh(self, force)  -- SKIP
    -- ...
end
```

### Config Access Pattern

```lua
-- CORRECT
local height = self.ModuleConfig.height or self.GlobalConfig.barHeight

-- WRONG
local profile = ECM.db.profile
local height = profile.powerBar.height or profile.global.barHeight
```

### Layout vs Refresh Separation

**UpdateLayout()** handles:
- Positioning (SetPoint)
- Sizing (SetWidth, SetHeight)
- Border/background styling
- Anchor chain resolution
- Calls Refresh() at the end

**Refresh()** handles:
- StatusBar min/max/value
- StatusBar color and texture
- Text overlay content and visibility
- Tick positioning (values may change without layout changing)

This separation allows:
- Layout changes without recalculating values
- Value updates without repositioning frames
- Better performance through caching

## Trade-offs and Decisions

### Direct Field Access vs Getters
**Decision:** Use direct field access (`self.GlobalConfig`)
**Rationale:**
- Simpler, less boilerplate
- Config is read-only during normal operation
- Performance (no function call overhead)
**Trade-off:** Less encapsulation, but configs are simple tables

### Layout Caching
**Decision:** Cache layout parameters in `_layoutCache` and compare before applying
**Rationale:**
- SetPoint/ClearAllPoints are expensive
- Layout rarely changes compared to value updates
- Prevents visual flickering
**Trade-off:** More memory, more complex code, but significant performance gain

### Module Lifecycle From Config
**Decision:** Module `enabled` flags now map to actual module enable/disable, not only `ShouldShow()` visibility checks.
**Rationale:**
- Disabled modules unregister their ECMFrames from Layout event fanout.
- Removes unnecessary event handlers and refresh/layout work when a feature is disabled.
**Trade-off:** Slightly more lifecycle complexity (must support re-register on re-enable).

### Debouncing vs Throttling
**Decision:** Use debouncing for layout, throttling for refresh
**Rationale:**
- Layout changes should settle before applying (debounce)
- Value refreshes should update regularly but not spam (throttle)
**Trade-off:** Slight delay in layout response, but cleaner event handling

### BuffBars Hook Pattern
**Decision:** Hook Blizzard frames rather than recreating
**Rationale:**
- Blizzard handles buff tracking and cooldown math
- Avoids reimplementing complex aura logic
- Respects user's edit mode configuration
**Trade-off:** Hook reliability issues, requires defensive coding

## Future Considerations

1. **Extract color management** - BuffBars color system could be generalized for other modules
2. **Tick system refinement** - Consider separating tick layout from BarFrame into a dedicated helper
3. **Layout.lua integration** - Ensure Layout.lua properly coordinates all ECMFrames
   - Includes lifecycle registration and unregistration (`ECM.RegisterFrame` / `ECM.UnregisterFrame`) for modules that are toggled on/off at runtime.
4. **PositionStrategy removal** - Verify no dependencies before deleting
5. **Error handling** - Add more defensive nil checks in hooks
6. **Documentation** - Add inline examples for complex methods (e.g., GetNextChainAnchor)
