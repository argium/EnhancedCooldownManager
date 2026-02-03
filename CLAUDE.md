## Design

MANDATORY: **ALL constants** are to be stored in Constants.lua.

The profile is split into GLOBAL and a SECTION specific to the module (typically matching the file name, in camel case).  See [Defaults.lua](Defaults.lua)

The intention is to use mixins as a kind of class hierarchy:
 ECMFrame -> BarFrame -> PowerBar|ResourceBar|RuneBar
 ECMFrame -> BuffBars

[ECMFrame](Mixins\ECMFrame.lua) owns:
- The "inner" Blizzard Frame
- Layout including positioning, anchor, border, background
- Refresh throttling
- Hiding

| Field         | Type            | Description |
|--------------|------------------|-------------|
| _configKey    | string\|nil       | Config section key (derived from Name). |
| _layoutCache  | table\|nil        | Cached layout state for change detection. |
| IsHidden      | boolean\|nil      | Whether the frame is currently hidden. |
| IsECMFrame    | boolean           | True to identify this as an ECMFrame mixin instance. |
| InnerFrame    | Frame\|nil        | Inner WoW frame owned by this mixin. |
| GlobalConfig  | table\|nil        | Direct reference to the global config section. Access via `self.GlobalConfig`. |
| ModuleConfig  | table\|nil        | Direct reference to this module's config section. Access via `self.ModuleConfig`. |
| Name          | string            | Name of the frame. |
| GetNextChainAnchor | fun(self: ECMFrame, frameName: string\|nil): Frame, boolean | Gets the next valid anchor in the chain. |
| ShouldShow    | fun(self: ECMFrame): boolean | Determines whether the frame should be shown at this moment. |
| CreateFrame   | fun(self: ECMFrame): Frame | Creates the inner frame. |
| SetHidden     | fun(self: ECMFrame, hide: boolean) | Sets whether the frame is hidden. |
| SetConfig     | fun(self: ECMFrame, config: table) | Sets GlobalConfig and ModuleConfig from config root. |
| UpdateLayout  | fun(self: ECMFrame): boolean | Updates the visual layout of the frame. |
| Refresh       | fun(self: ECMFrame, force: boolean\|nil): boolean | Handles refresh logic, returns true if should continue. |
| ScheduleDebounced | fun(self: ECMFrame, flagName: string, callback: function) | Schedules a debounced callback. |
| ThrottledRefresh | fun(self: ECMFrame): boolean | Rate-limited refresh. |
| ScheduleLayoutUpdate | fun(self: ECMFrame) | Schedules a throttled layout update. |
| AddMixin      | fun(target: table, name: string) | Adds ECMFrame methods and initializes state on target. |

ECMFrame should work with _any_ frame the addon needs to position or hide.

[BarFrame](Mixins\BarFrame.lua) owns:
- StatusBar (values, color, texture)
- Appearance (texture, colors)
- Text overlay
- Tick marks (creation, positioning, styling)

| Field/Method  | Type            | Description |
|--------------|------------------|-------------|
| GetStatusBarValues | fun(self: BarFrame): number\|nil, number\|nil, number\|nil, boolean | Gets current, max, displayValue, isFraction. Must be implemented by derived classes. |
| GetStatusBarColor | fun(self: BarFrame): ECM_Color | Gets the color for the status bar. Override for custom logic. |
| EnsureTicks   | fun(self: BarFrame, count: number, parentFrame: Frame, poolKey: string\|nil) | Ensures tick pool has required ticks. |
| HideAllTicks  | fun(self: BarFrame, poolKey: string\|nil) | Hides all ticks in the pool. |
| LayoutResourceTicks | fun(self: BarFrame, maxResources: number, color: ECM_Color\|nil, tickWidth: number\|nil, poolKey: string\|nil) | Positions ticks as resource dividers. |
| LayoutValueTicks | fun(self: BarFrame, statusBar: StatusBar, ticks: table, maxValue: number, defaultColor: ECM_Color, defaultWidth: number, poolKey: string\|nil) | Positions ticks at specific values. |
| CreateFrame   | fun(self: BarFrame): Frame | Creates frame with StatusBar, TicksFrame, and TextFrame. |
| Refresh       | fun(self: BarFrame, force: boolean\|nil): boolean | Refreshes bar values, text, texture, and color. |
| AddMixin      | fun(module: table, name: string) | Adds BarFrame methods and calls ECMFrame.AddMixin. |

BarFrame should work with any bar-style frame the addon is responsible for drawing and updating.

[Bars\*](Bars\*.lua) owns:
- Event registration and handlers
- Concrete implementations of GetStatusBarValues
- Custom ShouldShow logic
- Class/spec-specific behavior (ticks, colors, visibility rules)

These responsibilities can change over time so update this document if so however responsibilities should not cross mixins by reaching into the internals of another. Always use public interfaces. Internal fields are prefixed by an underscore.

### Method Call Chains

When a derived class calls a parent mixin method, it must call the immediate parent:
- `PowerBar:Refresh` calls `BarFrame.Refresh(self)` which calls `ECMFrame.Refresh(self)`
- `PowerBar:ShouldShow` calls `BarFrame.ShouldShow(self)` which calls `ECMFrame.ShouldShow(self)`
- `BuffBars:UpdateLayout` calls `ECMFrame` methods directly (BuffBars does not use BarFrame)

### Layout Update Flow

1. Events trigger `module:ScheduleLayoutUpdate()` (debounced)
2. `ScheduleLayoutUpdate` calls `UpdateLayout()` after throttle delay
3. `UpdateLayout()` determines positioning, size, border, background
4. `UpdateLayout()` calls `Refresh()` at the end to update values
5. `Refresh()` updates status bar values, text, colors, and ticks

MANDATORY: Modules that derive from ECMFrame, must use the config fields and never `ECM.db` or `ECM.db.profile` directly. NEVER create an intermediate table for profile/config.
- `self.GlobalConfig` for the `global` config block
- `self.ModuleConfig` for the module's specific block

MANDATORY: Modules should call methods in the immediate parent's mixin, if present. For example, `PowerBar:Refresh` must call `BarFrame.Refresh(self)` and never `ECMFrame.Refresh(self)`

MANDATORY: Any and all layout updates MUST be triggered from a call to `UpdateLayout()`. No cheeky workarounds, no funny business. MUST. Any change that modifies the layout outside of this function will be rejected.

MANDATORY: Any and all value-related updates should be triggered from a call to `Refresh()`.

MANDATORY: Files should have section headings to organize code. Use these headings in order as applicable (skip sections that don't apply):
- "Helpers" (or "Helper Methods" for non-static helpers)
- "Options UI" (for modules with options)
- "ECMFrame Overrides" or "BarFrame Overrides" or "ECMFrame/BarFrame Overrides" (depending on what you're overriding)
- "Event Handlers" or "Event Handling"
- "Module Lifecycle"

Not all files will have all sections. For example, mixins don't have event handlers.

[Modules\Layout.lua](Modules\Layout.lua) owns
- Registering events that affect every ECMFrame such as hiding when the player mounts.
- Tells ECMFrames when to show/hide themselves, or when to refresh in response to global events.
- Managing both ECMFrames and Blizzard cooldown viewer frames.
- Global hidden state based on mount, rest area, and CVar conditions.

## Secret Values

Do not perform any operations except nil checking (including reads) on the following secret values except for passing them into other built-in functions:
- UnitPowerMax
- UnitPower
- UnitPowerPercent
- C_UnitAuras.GetUnitAuraBySpellID

Most functions have a CurveConstant parameter that will return an adjusted value. eg.
```lua
UnitPowerPercent("player", resource, false, CurveConstants.ScaleTo100)
```
