Ensure this document and /docs are kept up to date after refactoring and API changes.

## Design

MANDATORY: **ALL constants** are to be stored in Constants.lua.

The profile is split into GLOBAL and a SECTION specific to the module (typically matching the file name, in camel case).  See [Defaults.lua](Defaults.lua)

The intention is to use mixins as a kind of class hierarchy:
 ECMFrame -> BarFrame -> PowerBar|ResourceBar|RuneBar
 ECMFrame -> BuffBars
 ECMFrame -> ItemIcons

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
| GlobalConfig  | table\|nil        | Current global config section reference. Access via `self.GlobalConfig`. Rebound on profile changes via `SetConfig`. |
| ModuleConfig  | table\|nil        | Current module config section reference. Access via `self.ModuleConfig`. Rebound on profile changes via `SetConfig`. |
| Name          | string            | Name of the frame. |
| GetNextChainAnchor | fun(self: ECMFrame, frameName: string\|nil): Frame, boolean | Gets the next valid anchor in the chain. |
| ShouldShow    | fun(self: ECMFrame): boolean | Determines whether the frame should be shown at this moment. |
| CreateFrame   | fun(self: ECMFrame): Frame | Creates the inner frame. |
| SetHidden     | fun(self: ECMFrame, hide: boolean) | Sets whether the frame is hidden. |
| SetConfig     | fun(self: ECMFrame, config: table) | Sets GlobalConfig and ModuleConfig from config root. |
| CalculateLayoutParams | fun(self: ECMFrame): table | Calculates layout params (mode, anchor, offsets, size). Override for custom positioning. |
| ApplyFramePosition | fun(self: ECMFrame, frame: Frame): table\|nil | Applies positioning to a frame. Handles ShouldShow check and returns params or nil if hidden. |
| UpdateLayout  | fun(self: ECMFrame): boolean | Updates the visual layout of the frame. |
| Refresh       | fun(self: ECMFrame, force: boolean\|nil): boolean | Handles refresh logic, returns true if should continue. |
| ScheduleDebounced | fun(self: ECMFrame, flagName: string, callback: function) | Schedules a debounced callback. |
| ThrottledRefresh | fun(self: ECMFrame): boolean | Rate-limited refresh. |
| ScheduleLayoutUpdate | fun(self: ECMFrame) | Schedules a throttled layout update. |
| AddMixin      | fun(target: table, name: string) | Adds ECMFrame methods and initializes state on target. |

ECMFrame should work with _any_ frame the addon needs to position or hide.
For chain anchoring, predecessor visibility (`InnerFrame:IsVisible()`) must not be required; rely on module enabled state, `ShouldShow()`, chain mode, and existing `InnerFrame`.

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
- BuffBars icon handling is deterministic: use `child.Icon` only (no `IconFrame`/`IconButton` fallback probing, no dynamic atlas/region discovery loops).
- BuffBars provides scan data via `CollectScanEntries()` (array of `{ spellName, textureFileID }`)
  and does not own cache persistence/orchestration.
- Color lookups in `ApplyCooldownBarStyle` use `BuffBarColors.GetColorKey()` and
  `BuffBarColors.GetSpellColor()`.

[Modules\BuffBarColors.lua](Modules\BuffBarColors.lua) owns:
- Per-spell color storage (`perSpell` in config, keyed by class/spec)
- Buff bar color key policy (`spellName` primary, `textureFileID` fallback key)
- Color-key migration from secondary numeric keys to resolved spell-name keys
- Default color get/set
- All color query/mutation methods called by Options UI directly.

[Modules\SecretedStore.lua](Modules\SecretedStore.lua) owns:
- Generic secret-safe normalization helpers (string/number/record).
- Secret API wrappers (`IsSecretValue`, `IsSecretTable`, `CanAccessValue`, `CanAccessTable`).
- Generic indexed-map change detection helper.
- Profile callback registration (`OnProfileChanged`, `OnProfileCopied`, `OnProfileReset`) and
  active profile rebinding.
- Direct `ECM.db.profile` access as an intentional infrastructure exception (non-bar module).

These responsibilities can change over time so update this document if so however responsibilities should not cross mixins by reaching into the internals of another. Always use public interfaces. Internal fields are prefixed by an underscore.

[Modules\ItemIcons.lua](Modules\ItemIcons.lua) owns:
- Displaying equipped trinkets with on-use effects as icons
- Displaying combat consumables (combat potions, health potions, healthstones) from bags
- Priority-based consumable selection (best quality per type)
- Positioning relative to UtilityCooldownViewer (right side)
- Applying/restoring temporary midpoint-preserving X offset on UtilityCooldownViewer when ItemIcons are shown/hidden
- Pausing ItemIcons layout while Blizzard Edit Mode is active, then resuming after edit mode closes
- Cooldown sweep display using CooldownFrameTemplate
- Icon creation and pooling

ItemIcons uses ECMFrame directly (does not use BarFrame) since it displays icons, not bars.

### Method Call Chains

When a derived class calls a parent mixin method, it must call the immediate parent:
- `PowerBar:Refresh` calls `BarFrame.Refresh(self)` which calls `ECMFrame.Refresh(self)`
- `PowerBar:ShouldShow` calls `BarFrame.ShouldShow(self)` which calls `ECMFrame.ShouldShow(self)`
- `BuffBars:UpdateLayout` calls `ECMFrame` methods directly (BuffBars does not use BarFrame)
- `ItemIcons:ShouldShow` calls `ECMFrame.ShouldShow(self)` directly (ItemIcons does not use BarFrame)

### Layout Update Flow

1. Events trigger `module:ScheduleLayoutUpdate()` (debounced)
2. `ScheduleLayoutUpdate` calls `UpdateLayout()` after throttle delay
3. `UpdateLayout()` calls `CalculateLayoutParams()` for positioning parameters
4. `UpdateLayout()` applies positioning, size, border, background
5. `UpdateLayout()` calls `Refresh()` at the end to update values
6. `Refresh()` updates status bar values, text, colors, and ticks

MANDATORY: Modules that derive from ECMFrame, must use the config fields and never `ECM.db` or `ECM.db.profile` directly. NEVER create an intermediate table for profile/config.
- `self.GlobalConfig` for the `global` config block
- `self.ModuleConfig` for the module's specific block
- Module `enabled` config should drive module lifecycle (enable/disable), not just visibility, so disabled modules are unregistered from Layout.

MANDATORY: Modules should call methods in the immediate parent's mixin, if present. For example, `PowerBar:Refresh` must call `BarFrame.Refresh(self)` and never `ECMFrame.Refresh(self)`

MANDATORY: Any and all layout updates MUST be triggered from a call to `UpdateLayout()`. No cheeky workarounds, no funny business. MUST. Any change that modifies the layout outside of this function will be rejected.

MANDATORY: Any and all value-related updates should be triggered from a call to `Refresh()`.

MANDATORY: Use WoW's built-in `strtrim(...)` for string trimming. Do not use `:trim()` or custom trim helpers.

MANDATORY: Files should have section headings to organize code. Use these headings in order as applicable (skip sections that don't apply):
- "Helpers" (or "Helper Methods" for non-static helpers)
- "Options UI" (for modules with options)
- "ECMFrame Overrides" or "BarFrame Overrides" or "ECMFrame/BarFrame Overrides" (depending on what you're overriding)
- "Event Handlers" or "Event Handling"
- "Module Lifecycle"

Not all files will have all sections. For example, mixins don't have event handlers.

[Modules\Layout.lua](Modules\Layout.lua) owns
- Registering events that affect every ECMFrame such as hiding when the player mounts or enters a vehicle.
- Tells ECMFrames when to show/hide themselves, or when to refresh in response to global events.
- Managing both ECMFrames and Blizzard cooldown viewer frames.
- Global hidden state based on mount/vehicle, rest area, and CVar conditions.
- Registering and unregistering ECMFrames via `ECM.RegisterFrame(frame)` / `ECM.UnregisterFrame(frame)` so module-level enable/disable can fully opt frames in/out.
- Running deterministic layout passes: chain modules in `C.CHAIN_ORDER` first, then remaining modules.
- Owning scanner orchestration (`ECM.RegisterScanner` / `ECM.UnregisterScanner`) for non-layout
  discovery flows.
- Owning BuffBars discovery cache/secondary-key map refresh via scanner and exposing read APIs:
  `ECM.GetBuffBarDiscoveryCache()`, `ECM.GetBuffBarDiscoverySecondaryKeyMap()`,
  `ECM.RefreshBuffBarDiscovery(reason)`.

[Modules\Migration.lua](Modules\Migration.lua) owns:
- Versioned SavedVariable namespacing for rollback-safe schema upgrades within a single SV (`EnhancedCooldownManagerDB`).
- Per-version AceDB data is stored in `EnhancedCooldownManagerDB._versions[schemaVersion]`. The top-level `profiles`/`profileKeys` are legacy data (never touched by new code), so old addon versions still work. AceDB uses a temporary global (`_ECM_DB`) that references the current version's sub-table — writes flow through to the persisted SV automatically.
- `Migration.PrepareDatabase()` sets up the versioned store. Must be called **before** `AceDB:New()`. It seeds the current version's slot by copying from the best prior version in `_versions`, or from the legacy top-level data for pre-versioning builds.
- Running incremental schema migrations (V2 → V7) via `Migration.Run(profile)`.
- Rollback between any two versioned builds works seamlessly — each version's data is isolated in its own `_versions` sub-table. The legacy top-level data is never modified, so pre-versioning builds also work.
- The TOC never changes for schema bumps. Just increment `C.CURRENT_SCHEMA_VERSION` and add a new migration step in `Migration.Run`.

# Secret Values

Do not perform any operations except nil checking (including reads) on the following secret values except for passing them into other built-in functions:
- UnitPowerMax
- UnitPower
- UnitPowerPercent
- C_UnitAuras.GetUnitAuraBySpellID

Most functions have a CurveConstant parameter that will return an adjusted value. eg.
```lua
UnitPowerPercent("player", resource, false, CurveConstants.ScaleTo100)
```

## Restrictions

**The full list of technical restrictions for tainted code is as follows.**

- When an operation that is not allowed is performed, the result will be an immediate Lua error.
- Tainted code is allowed to store secret values in variables, upvalues, or as values in tables.
- Tainted code is allowed to pass secret values to Lua functions.
  - For C functions, an API must be explicitly marked up as accepting secrets from tainted callers.
- Tainted code is allowed to concatenate secret values that are strings or numbers.
  - Tainted code is additionally allowed to call APIs such as string.concat, string.format, and string.join with secret values.
- Tainted code is not allowed to perform arithmetic on secret values.
- Tainted code is not allowed to compare or perform boolean tests on secret values.
- Tainted code is not allowed to use the length operator (#) on secret values.
- Tainted code is not allowed to store secret values as keys in tables.
- Tainted code is not allowed to perform indexed access or assignment (secret["foo"] = 1) on secret values.
- Tainted code is not allowed to call secret values as-if they were functions.
- Querying the type of a secret value type(secret) returns its real type (ie. "string", "number", etc.).

### Secret tables

**For Lua tables, a few additional restrictions apply.**

- A table can be flagged such that indexed access of it will always yield a secret value.
- A table can be flagged as inaccessible to tainted code; any attempt to index, assign, measure, or iterate over such a table will trigger an immediate Lua error ("attempted to index a forbidden table").
- When untainted code stores a secret value as a table key, the table itself is irrevocably marked with both of the aforementioned flags.

**A few additional APIs exist to handle table secrecy.**

- canaccesstable(table) returns true if the calling function would not error if attempting to access the table.
