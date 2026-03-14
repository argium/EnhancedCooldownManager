# LibSettingsBuilder-1.0

A builder for the World of Warcraft [Settings API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua). One call per control instead of the usual `RegisterProxySetting` → `CreateCheckbox` → `AddModifyPredicate` dance. Supports AceDB-style dot-paths, composite groups (font, border, positioning), table-driven registration, and custom canvas pages.

Two binding modes:
- **Path mode** — dot-delimited paths into a nested profile table (e.g. AceDB), resolved via a `PathAdapter`.
- **Handler mode** — explicit `get`/`set`/`key` callbacks for arbitrary storage.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## Installation

Include `LibSettingsBuilder.xml` in your addon's TOC or load-on-demand XML. Depends on LibStub.

```toc
Libs\LibStub\LibStub.lua
Libs\LibSettingsBuilder\LibSettingsBuilder.xml
```

## Quick Start

### Table-driven (recommended)

The fastest way to build a settings page. `RegisterFromTable` creates a subcategory, sorts entries by `order`, and maps each type to the right control.

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local SB = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore    = function() return MyAddonDB.profile end,
        getDefaults = function() return MyAddonDefaults.profile end,
    }),
    varPrefix = "MYADDON",
    onChanged = function(spec, value) MyAddon:Refresh() end,
})

SB.CreateRootCategory("My Addon")

SB.RegisterFromTable({
    name = "General",              -- creates a subcategory called "General"
    path = "general",              -- child paths are relative to this
    args = {
        enabled = {
            type  = "toggle",      -- alias for "checkbox"
            path  = "enabled",     -- resolves to "general.enabled"
            name  = "Enable",
            desc  = "Enable or disable the addon.",   -- alias for "tooltip"
            order = 1,
        },
        displayHeader = { type = "header", name = "Display", order = 10 },
        opacity = {
            type = "range",        -- alias for "slider"
            path = "opacity",
            name = "Opacity",
            min  = 0, max = 100, step = 1,
            order = 11,
        },
        font = { type = "fontOverride", order = 20 },           -- composite: checkbox + font picker + size slider
        border = { type = "border", path = "border", order = 30 }, -- composite: checkbox + thickness + color
    },
})

SB.RegisterCategories()
```

### Imperative API

For more control, call each function directly.

```lua
SB.CreateRootCategory("My Addon")
SB.CreateSubcategory("General")

SB.Checkbox({
    path    = "general.enabled",
    name    = "Enable",
    tooltip = "Enable or disable the addon.",
})

SB.Slider({
    path = "general.opacity",
    name = "Opacity",
    min  = 0, max = 100, step = 1,
})

SB.RegisterCategories()
```

### Handler mode (no AceDB)

Skip the `PathAdapter` and provide `get`/`set`/`key` directly.

```lua
local SB = LSB:New({
    varPrefix = "MYADDON",
    onChanged = function(spec, value) MyAddon:ApplySettings() end,
})

SB.CreateRootCategory("My Addon")
SB.CreateSubcategory("General")

SB.Checkbox({
    get     = function() return MyStore.enabled end,
    set     = function(v) MyStore.enabled = v end,
    key     = "enabled",
    default = true,
    name    = "Enable",
})

SB.RegisterCategories()
```

---

## Migrating from AceConfig / AceGUI

If you're coming from AceConfig-3.0 + AceGUI-3.0 + AceConfigDialog-3.0, here's what changes and what stays the same.

### What you're replacing

| AceConfig stack | LibSettingsBuilder |
|---|---|
| AceConfigDialog renders into a standalone AceGUI frame or Blizzard's old InterfaceOptions panel. | Renders directly into Blizzard's **Settings API** panel (the one players already use for game settings). |
| AceDB-3.0 for saved variables + profiles. | **Keep AceDB.** LSB reads/writes your existing AceDB profile through a `PathAdapter`. Nothing changes about how your data is stored. |
| `LibStub("AceConfig-3.0"):RegisterOptionsTable(name, optionsTable)` | `SB.RegisterFromTable(tbl)` — similar table structure, different field names. |
| `LibStub("AceConfigDialog-3.0"):AddToBlizOptions(name)` | `SB.RegisterCategories()` |

### Your SavedVariables don't change

LSB doesn't manage saved variables. It reads and writes through getter/setter functions you provide. If you're using AceDB, point the `PathAdapter` at your existing `db.profile` and `db.defaults.profile` — your saved variables file, your profile switching, and your defaults table all stay exactly as they are.

```lua
-- Your existing AceDB setup — no changes needed
self.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults, true)

-- Point LSB at the same tables AceConfig was reading
local SB = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore    = function() return self.db.profile end,
        getDefaults = function() return self.db.defaults.profile end,
    }),
    varPrefix = "MYADDON",
    onChanged = function() self:ApplySettings() end,
})
```

### Field name mapping

LSB's `RegisterFromTable` accepts AceConfig-style type aliases so you don't have to relearn everything:

| AceConfig field | LSB equivalent | Notes |
|---|---|---|
| `type = "toggle"` | `type = "toggle"` | Alias for `"checkbox"`. Works as-is. |
| `type = "range"` | `type = "range"` | Alias for `"slider"`. Works as-is. |
| `type = "select"` | `type = "select"` | Alias for `"dropdown"`. Works as-is. |
| `type = "execute"` | `type = "execute"` | Alias for `"button"`. Works as-is. |
| `type = "description"` | `type = "description"` | Alias for `"subheader"`. Works as-is. |
| `type = "color"` | `type = "color"` | Same name. |
| `type = "header"` | `type = "header"` | Same name. |
| `type = "group"` | No equivalent | Use separate `RegisterFromTable` calls or `CreateSubcategory`. |
| `type = "input"` | No equivalent | Use `type = "custom"` with your own template. |
| `type = "multiselect"` | No equivalent | Use `type = "toggleList"` with a `defs` array. |
| `desc` | `desc` | Alias for `tooltip`. Works as-is. |
| `order` | `order` | Same behavior. |
| `disabled` | `disabled` | Same behavior (function returning bool). |
| `hidden` | `hidden` | Same behavior (function returning bool). |
| `get` / `set` | `get` / `set` | Same concept — handler mode. Also need `key` for variable name generation. |
| `values` | `values` | Same — table or function returning `value -> label` map. |
| `min` / `max` / `step` | `min` / `max` / `step` | Same. |

### Side-by-side example

**AceConfig:**

```lua
local options = {
    name = "My Addon",
    type = "group",
    args = {
        enabled = {
            type = "toggle",
            name = "Enable",
            desc = "Enable the addon.",
            order = 1,
            get = function() return db.profile.enabled end,
            set = function(_, v) db.profile.enabled = v end,
        },
        opacity = {
            type = "range",
            name = "Opacity",
            min = 0, max = 100, step = 1,
            order = 2,
            get = function() return db.profile.opacity end,
            set = function(_, v) db.profile.opacity = v end,
        },
    },
}
LibStub("AceConfig-3.0"):RegisterOptionsTable("MyAddon", options)
LibStub("AceConfigDialog-3.0"):AddToBlizOptions("MyAddon")
```

**LibSettingsBuilder (path mode — no per-field get/set needed):**

```lua
local SB = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore    = function() return db.profile end,
        getDefaults = function() return db.defaults.profile end,
    }),
    varPrefix = "MYADDON",
    onChanged = function() MyAddon:Refresh() end,
})

SB.CreateRootCategory("My Addon")

SB.RegisterFromTable({
    name = "My Addon",
    rootCategory = true,
    args = {
        enabled = {
            type  = "toggle",
            path  = "enabled",
            name  = "Enable",
            desc  = "Enable the addon.",
            order = 1,
        },
        opacity = {
            type = "range",
            path = "opacity",
            name = "Opacity",
            min  = 0, max = 100, step = 1,
            order = 2,
        },
    },
})

SB.RegisterCategories()
```

The key difference: in path mode, you declare the path once and LSB generates the get/set for you from the `PathAdapter`. No more writing `function(info) return db.profile.X end` / `function(info, v) db.profile.X = v end` on every field.

### What LSB adds that AceConfig doesn't have

- **Composite builders** — `FontOverrideGroup`, `BorderGroup`, `PositioningGroup` create 3–5 related controls in one line.
- **Canvas layout pages** — `CreateCanvasLayout` for scroll lists, custom widgets, and anything that doesn't fit a vertical list.
- **Reactive modifiers** — `disabled` and `hidden` predicates re-evaluate automatically on every setting change. No manual refresh needed.
- **Editable slider values** — all sliders let users click the value label to type an exact number.
- **Native Settings panel** — your addon's settings appear in the same panel as Blizzard's game settings, not in a separate AceGUI window.

---

## Glossary

| Term | Meaning |
|---|---|
| **Category** | A top-level entry in the WoW Settings panel. Created via `Settings.RegisterVerticalLayoutCategory`. |
| **Subcategory** | A child entry nested under a category. Created via `Settings.RegisterVerticalLayoutSubcategory` or its canvas equivalent. |
| **Vertical layout** | Blizzard's list-based settings UI where controls are stacked automatically. |
| **Canvas layout** | A settings page backed by a custom frame that you design and anchor yourself. |
| **Proxy setting** | A `Settings.RegisterProxySetting` object with explicit getter/setter. All LibSettingsBuilder controls use proxy settings. |
| **Initializer** | The object returned by `Settings.CreateCheckbox`, `Settings.CreateSlider`, etc. Represents a single row in the vertical list. |
| **Setting** | The data object returned by `Settings.RegisterProxySetting`. Exposes `GetValue()` / `SetValue(value)`. |
| **Spec** | The configuration table passed to every control (`Checkbox`, `Slider`, etc.). Contains binding fields, `name`, modifiers, and optional transforms. |
| **Path** | A dot-delimited string (`"powerBar.border.color"`) addressing a value in the profile table. Resolved by a `PathAdapter`. |
| **Modifier** | A predicate function controlling visibility (`hidden`), enabled state (`disabled`), or parent-child nesting (`parent`). |
| **Composite builder** | A higher-level helper (`FontOverrideGroup`, `BorderGroup`, `PositioningGroup`, etc.) that creates multiple related controls in one call. |

---

## Factory: `lib:New(config)`

Creates a new builder instance. Returns the `SB` table containing all API functions documented below.

### Required Fields

| Field | Type | Description |
|---|---|---|
| `varPrefix` | `string` | Short prefix for unique variable names. A path `"general.enabled"` with prefix `"ECM"` becomes `"ECM_general_enabled"`. |
| `onChanged` | `function(spec, value)` | Called after every setter. `spec` is the full spec table for the control that changed. |

### Optional Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `pathAdapter` | `PathAdapter` | `nil` | Required when using path-based specs. See `lib.PathAdapter()` below. |
| `compositeDefaults` | `table` | `nil` | Keyed by composite function name (`"FontOverrideGroup"`, `"PositioningGroup"`). Values are default spec tables merged (lowest priority) into the composite's spec. See [Composite Defaults](#composite-defaults). |

---

## PathAdapter: `lib.PathAdapter(config)`

Creates an adapter that resolves dot-delimited paths into getter/setter/default bindings over a nested table (e.g. AceDB profiles).

### Required Fields

| Field | Type | Description |
|---|---|---|
| `getStore` | `function() -> table` | Returns the live storage table (e.g. `db.profile`). |
| `getDefaults` | `function() -> table` | Returns the defaults table (same shape as the store). |

### Optional Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `getNestedValue` | `function(tbl, path) -> any` | Built-in dot-path resolver | Reads a dot-delimited path from a table (`"general.enabled"` → `tbl.general.enabled`). The built-in default handles numeric path segments (`"colors.0"` → `tbl.colors[0]`). |
| `setNestedValue` | `function(tbl, path, value)` | Built-in dot-path setter | Writes a value at a dot-delimited path. Creates intermediate tables as needed. |

### Methods

| Method | Description |
|---|---|
| `adapter:resolve(path)` | Returns `{ get, set, default }` — a binding for the given path. |
| `adapter:read(path)` | Returns the current value at the path. |

---

## Category Management

### `SB.CreateRootCategory(name)`

Registers a top-level vertical-layout category. Sets it as the current target for subsequent controls.

Returns the category object.

### `SB.CreateSubcategory(name)`

Creates a vertical-layout subcategory under the root. Sets it as the current target.

Returns the subcategory object.

### `SB.CreateCanvasSubcategory(frame, name [, parentCategory])`

Creates a canvas-layout subcategory backed by your own frame. Does **not** change the current target for vertical-layout controls.

Returns the subcategory object.

### `SB.CreateCanvasLayout(name [, parentCategory])`

Creates a canvas subcategory with a built-in layout helper. Returns a `CanvasLayout` object that provides `AddHeader`, `AddDescription`, `AddSlider`, `AddColorSwatch`, `AddButton`, `AddScrollList`, and `AddSpacer` methods for building custom pages without manual frame anchoring.

See [Canvas Layout API](#canvas-layout-api) for details.

### `SB.RegisterCategories()`

Calls `Settings.RegisterAddOnCategory` on the root category. Call once after all categories and controls are defined.

### `SB.GetRootCategoryID()`

Returns the root category ID. Use with `Settings.OpenToCategory(id)` to open your settings programmatically.

### `SB.GetSubcategoryID(name)`

Returns the category ID for a named subcategory.

```lua
-- Open to a specific subcategory
local catID = SB.GetSubcategoryID("General") or SB.GetRootCategoryID()
Settings.OpenToCategory(catID)
```

---

## Proxy Controls

All controls support two binding modes:

- **Path mode:** provide `spec.path` — the builder resolves get/set/default via the `PathAdapter`.
- **Handler mode:** provide `spec.get`, `spec.set`, `spec.key`, and optionally `spec.default`.

A spec cannot mix both modes.

Each call:

1. Derives a unique variable name from `varPrefix` + (`spec.key` or `spec.path`).
2. Creates getter/setter functions from the resolved binding.
3. Calls `Settings.RegisterProxySetting` and the appropriate `Settings.Create*` factory.
4. Applies modifiers (parent, disabled, hidden) — reactive predicates re-evaluate on every setting change.

All controls return `initializer, setting`.

### Common Spec Fields

| Field | Type | Description |
|---|---|---|
| `path` | `string` | Dot-delimited path into the profile table. **Required in path mode.** |
| `get` | `function() -> any` | Getter for the current value. **Required in handler mode.** |
| `set` | `function(value)` | Setter for the value. **Required in handler mode.** |
| `key` | `string` | Unique key for variable name generation. **Required in handler mode.** |
| `default` | `any` | Default value. In path mode, auto-derived from the defaults table. |
| `name` | `string` | **Required.** Display name shown in the settings panel. |
| `tooltip` | `string` | Tooltip text. Also aliased as `desc` (for AceConfig compatibility). |
| `category` | `category` | Override the target category. Defaults to the current subcategory or root. |
| `onSet` | `function(value)` | Called after the value is written, before `onChanged`. |
| `getTransform` | `function(raw) -> display` | Transform the stored value before it reaches the UI. Useful for providing fallback defaults (e.g. `function(v) return v or 0 end`). |
| `setTransform` | `function(display) -> raw` | Transform the UI value before writing to the profile. Useful for clearing defaults (e.g. `function(v) return v > 0 and v or nil end`). |
| `parent` | `initializer` | Makes this control a visual child of another (indented, shown only when the parent predicate passes). |
| `parentCheck` | `function() -> bool` | Custom predicate for the parent relationship. Defaults to checking the parent's setting value. |
| `disabled` | `function() -> bool` | When returns `true`, the control is greyed out. **Reactive** — re-evaluated on every setting change. |
| `hidden` | `function() -> bool` | When returns `true`, the control is hidden. **Reactive** — re-evaluated on every setting change. |

### `SB.Checkbox(spec)`

Creates a boolean checkbox.

```lua
SB.Checkbox({
    path    = "powerBar.enabled",
    name    = "Enable power bar",
    tooltip = "Show the power bar beneath the player frame.",
})
```

### `SB.Slider(spec)`

Creates a numeric slider. All sliders get an editable value label — clicking the displayed value opens an edit box for direct numeric input.

| Additional Field | Type | Default | Description |
|---|---|---|---|
| `min` | `number` | — | Minimum value. |
| `max` | `number` | — | Maximum value. |
| `step` | `number` | `1` | Step increment. |
| `formatter` | `function(value) -> string` | Integer or 1-decimal | Custom label formatter. |

```lua
SB.Slider({
    path = "powerBar.height",
    name = "Height",
    min  = 5, max = 40, step = 1,
})
```

### `SB.Dropdown(spec)`

Creates a dropdown selector. The var type is inferred from the default (`Number` if default is a number, otherwise `String`).

| Additional Field | Type | Description |
|---|---|---|
| `values` | `table` or `function() -> table` | Map of `value -> label` pairs. Functions are evaluated each time the dropdown opens. |
| `scrollHeight` | `number` | When set, uses a scroll-enabled dropdown. Ideal for long lists (fonts, sounds, etc.). |

```lua
SB.Dropdown({
    path   = "powerBar.anchorMode",
    name   = "Position Mode",
    values = { attached = "Attached", free = "Free" },
})
```

### `SB.Color(spec)`

Creates a color swatch. Stores/reads `{r, g, b, a}` tables in the profile and converts to/from hex strings (AARRGGBB) for the proxy setting.

> **Note:** Blizzard's `Settings.CreateColorSwatch` does not support a `hasAlpha` parameter. Alpha channel selection is not available through the Settings API.

```lua
SB.Color({
    path = "powerBar.border.color",
    name = "Border color",
})
```

### `SB.Custom(spec)`

Creates a proxy setting backed by a custom XML frame template. The template's `Init` receives `initializer:GetData()` containing `{setting, name, tooltip}`.

| Additional Field | Type | Description |
|---|---|---|
| `template` | `string` | **Required.** Name of the XML template (must inherit `SettingsListElementTemplate`). |
| `varType` | `Settings.VarType` | Override the variable type. Defaults to `Settings.VarType.String`. |

```lua
SB.Custom({
    path     = "global.texture",
    name     = "Bar Texture",
    template = "MyAddon_TexturePickerTemplate",
})
```

### `SB.Control(spec)`

Unified dispatcher. Reads `spec.type` and forwards to `Checkbox`, `Slider`, `Dropdown`, `Color`, or `Custom`.

---

## Composite Builders

Higher-level helpers that create multiple related controls from a single call. All composites propagate `disabled`, `hidden`, and `parent` modifiers to their children.

### `SB.HeightOverrideSlider(sectionPath, spec?)`

Creates a slider for `sectionPath .. ".height"`. Value of `0` means "use the global default" and stores `nil`.

Returns `initializer, setting`.

### `SB.FontOverrideGroup(sectionPath, spec?)`

Creates a group of controls for per-module font overrides:

1. **Checkbox** at `sectionPath .. ".overrideFont"` — enables the override.
2. **Font dropdown** at `sectionPath .. ".font"` — disabled when override is off.
3. **Font size slider** at `sectionPath .. ".fontSize"` — disabled when override is off.

| Optional Field | Type | Description |
|---|---|---|
| `fontValues` | `function() -> table` | Choices for the font dropdown. |
| `fontFallback` | `function() -> string` | Fallback font name when no override is set. |
| `fontSizeFallback` | `function() -> number` | Fallback size when no override is set. |
| `fontTemplate` | `string` | Custom template name; when provided, uses `Custom` instead of `Dropdown`. |
| `enabledName` | `string` | Override label for the checkbox (default: `"Override font"`). |
| `fontName` / `sizeName` | `string` | Override labels for the font/size controls. |
| `sizeMin` / `sizeMax` / `sizeStep` | `number` | Slider bounds (defaults: 6–32, step 1). |

Returns `{ enabledInit, enabledSetting, fontInit, sizeInit }`.

### `SB.BorderGroup(borderPath, spec?)`

Creates a group for border settings:

1. **Checkbox** at `borderPath .. ".enabled"`.
2. **Slider** at `borderPath .. ".thickness"` — child of the checkbox (default 1–10).
3. **Color swatch** at `borderPath .. ".color"` — child of the checkbox.

| Optional Field | Type | Description |
|---|---|---|
| `enabledName` / `enabledTooltip` | `string` | Override labels (default: `"Show border"`). |
| `thicknessName` / `thicknessTooltip` | `string` | Override labels (default: `"Border width"`). |
| `thicknessMin` / `thicknessMax` / `thicknessStep` | `number` | Slider bounds (defaults: 1–10, step 1). |
| `colorName` / `colorTooltip` | `string` | Override labels (default: `"Border color"`). |

Returns `{ enabledInit, enabledSetting, thicknessInit, colorInit }`.

### `SB.ColorPickerList(basePath, defs, spec?)`

Creates a list of color swatches from an array of definitions.

```lua
SB.ColorPickerList("resourceBar.colors", {
    { key = "chi",         name = "Chi" },
    { key = "holyPower",   name = "Holy Power" },
    { key = "comboPoints", name = "Combo Points" },
})
```

Each `def` must have:

| Field | Type | Description |
|---|---|---|
| `key` | `string` or `number` | Appended to `basePath` to form the full path. |
| `name` | `string` | Display name. |
| `tooltip` | `string?` | Optional tooltip. |

Returns an array of `{ key, initializer, setting }`.

### `SB.CheckboxList(basePath, defs, spec?)`

Same as `ColorPickerList` but creates checkboxes instead of color swatches.

```lua
SB.CheckboxList("resourceBar.maxColorsEnabled", {
    { key = "holyPower",   name = "Holy Power" },
    { key = "comboPoints", name = "Combo Points" },
})
```

Returns an array of `{ key, initializer, setting }`.

### `SB.PositioningGroup(configPath, spec)`

Creates controls for bar positioning:

1. **Dropdown** at `configPath .. ".anchorMode"`.
2. **Width slider** at `configPath .. ".width"` — visible only in free mode.
3. **Offset X slider** at `configPath .. ".offsetX"` — visible only in free mode (omitted if `spec.includeOffsetX == false`).
4. **Offset Y slider** at `configPath .. ".offsetY"` — visible only in free mode.

| Required Field | Type | Description |
|---|---|---|
| `positionModes` | `table` | Value → label map for the anchor mode dropdown. |
| `isAnchorModeFree` | `function(cfg) -> bool` | Returns whether the current mode is "free" (shows offset/width controls). |

| Optional Field | Type | Description |
|---|---|---|
| `applyPositionMode` | `function(cfg, mode)` | Called when the mode changes. |
| `defaultBarWidth` | `number` | Default width value (default: 250). |
| `includeOffsetX` | `bool` | Set to `false` to omit the X offset slider. |
| `widthMin` / `widthMax` / `widthStep` | `number` | Width slider bounds (defaults: 100–600, step 1). |

Returns `{ modeInit, modeSetting, widthInit, offsetXInit, offsetYInit }`.

---

## Utility Helpers

### `SB.Header(text [, category])`

Inserts a section header. The first header on a page is automatically suppressed if its text matches the subcategory name (avoiding a redundant heading).

Returns `initializer` or `nil` (if suppressed).

### `SB.Subheader(spec)`

Inserts a sub-section heading using `GameFontNormal`. No control widget — used as a parent initializer to visually group controls underneath it.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | `string` | yes | Display text. |
| `category` | `category` | no | Override target category. |
| `parent` | `initializer` | no | Parent for nesting. |
| `hidden` | `function` | no | Visibility predicate. |
| `disabled` | `function` | no | Enabled state predicate. |

```lua
local colorLabel = SB.Subheader({ name = "Colors" })
SB.ColorPickerList("items.colors", COLOR_DEFS, { parent = colorLabel })
```

Returns `initializer`.

### `SB.InfoRow(spec)`

Inserts a read-only key/value row into the vertical list — useful for "About" pages.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | `string` | yes | Label (left side). |
| `value` | `string` | yes | Value (right side). |
| `category` | `category` | no | Override target category. |

```lua
SB.InfoRow({ name = "Version", value = "1.2.3" })
SB.InfoRow({ name = "Author",  value = "YourName" })
```

Returns `initializer`.

### `SB.EmbedCanvas(canvas, height, spec?)`

Embeds an arbitrary frame into the vertical list at the specified height.

```lua
local preview = CreateFrame("Frame")
preview:SetHeight(100)
SB.EmbedCanvas(preview, 100)
```

Returns `initializer`.

### `SB.Button(spec)`

Adds a button to the vertical list.

| Field | Type | Description |
|---|---|---|
| `name` | `string` | **Required.** Display name. |
| `buttonText` | `string` | Button label (defaults to `name`). |
| `onClick` | `function()` | **Required.** Click handler. |
| `tooltip` | `string` | Tooltip text. |
| `confirm` | `bool` or `string` | Shows a confirmation dialog before executing `onClick`. A string value overrides the dialog text. |

```lua
SB.Button({
    name       = "Reset to defaults",
    buttonText = "Reset",
    confirm    = "This will reset all settings. Are you sure?",
    onClick    = function() MyAddon:ResetProfile() end,
})
```

Returns `initializer`.

### `SB.RegisterSection(nsTable, key, section)`

Registers a section table into `nsTable.OptionsSections[key]`. Useful for modular option pages that register themselves into a shared namespace and are iterated at startup.

```lua
local MyOptions = {}
function MyOptions.RegisterSettings(SB)
    SB.RegisterFromTable({ name = "My Module", path = "myModule", args = { ... } })
end
SB.RegisterSection(ns, "MyModule", MyOptions)
```

Returns the `section` table.

---

## Table-Driven Registration: `SB.RegisterFromTable(tbl)`

Walks a declarative table and calls the imperative API. Ideal for standard settings pages; complex pages (canvas layouts, dynamic content) should use the imperative API directly.

### Table Structure

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | `string` | yes | Subcategory name. A new subcategory is created automatically. |
| `path` | `string` | no | Path prefix. Child paths are resolved relative to this (`path = "powerBar"` + child `path = "enabled"` → `"powerBar.enabled"`). A child path containing a `.` is treated as absolute. |
| `rootCategory` | `bool` | no | When `true`, adds controls to the root category page instead of creating a subcategory. |
| `disabled` | `function() -> bool` | no | Inherited by all children that don't set their own. |
| `hidden` | `function() -> bool` | no | Inherited by all children that don't set their own. |
| `args` | `table` | no | Table of entries keyed by name. Each entry is processed in `order`. |

### Type Mapping

Standard types (AceConfig aliases in parentheses):

| Type | Alias | Maps to |
|---|---|---|
| `checkbox` | `toggle` | `SB.Checkbox` |
| `slider` | `range` | `SB.Slider` |
| `dropdown` | `select` | `SB.Dropdown` |
| `color` | — | `SB.Color` |
| `custom` | — | `SB.Custom` |
| `button` | `execute` | `SB.Button` |
| `header` | — | `SB.Header` |
| `subheader` | `description` | `SB.Subheader` |
| `info` | — | `SB.InfoRow` |
| `canvas` | — | `SB.EmbedCanvas` (requires `canvas` and `height` fields) |

Composite types:

| Type | Maps to |
|---|---|
| `positioning` | `SB.PositioningGroup` |
| `border` | `SB.BorderGroup` |
| `fontOverride` | `SB.FontOverrideGroup` |
| `heightOverride` | `SB.HeightOverrideSlider` |
| `colorList` | `SB.ColorPickerList` (requires `defs` field) |
| `toggleList` | `SB.CheckboxList` (requires `defs` field) |

### Entry Fields

Each entry in `args` supports:

| Field | Type | Description |
|---|---|---|
| `type` | `string` | **Required.** Control type (see mapping above). |
| `order` | `number` | Sort order (default 100). Lower values appear first. |
| `path` | `string` | Relative to group `path`, or absolute if it contains a `.`. |
| `name` | `string` | Display name. |
| `desc` | `string` | Alias for `tooltip`. |
| `parent` | `string` | Key name of another entry in the same `args` table. Resolved to its initializer automatically. |
| `parentCheck` | `string` or `function` | `"checked"` / `"notChecked"` shortcuts, or a custom predicate function. |
| `condition` | `function() -> bool` or `bool` | When set, the entry is skipped entirely if the condition is falsy. Unlike `hidden`, the control is never created. |
| `disabled` | `function` | Inherited from group if not set. |
| `hidden` | `function` | Inherited from group if not set. |
| `label` | `string` | For `colorList` and `toggleList` only — automatically creates a `Subheader` and parents the list items under it. |
| `defs` | `table` | For `colorList` and `toggleList` only — the array of `{key, name, tooltip}` definitions. |
| `canvas` | `frame` | For `canvas` type only — the frame to embed. |
| `height` | `number` | For `canvas` type only — the height of the embedded frame. |

Plus all standard spec fields for the control type (`min`, `max`, `step`, `values`, `template`, etc.).

### Example: Parent References and Shortcuts

```lua
SB.RegisterFromTable({
    name = "Rune Bar",
    path = "runeBar",
    disabled = isNotDeathKnight,     -- greyed out for non-DK classes
    args = {
        useSpecColor = {
            type = "checkbox",
            path = "useSpecColor",
            name = "Use specialization color",
            order = 1,
        },
        -- Shown only when useSpecColor is NOT checked
        runeColor = {
            type = "color",
            path = "color",
            name = "Rune color",
            parent = "useSpecColor",         -- references the entry key above
            parentCheck = "notChecked",      -- shortcut: visible when parent is unchecked
            order = 2,
        },
        -- Shown only when useSpecColor IS checked
        bloodColor = {
            type = "color",
            path = "colorBlood",
            name = "Blood color",
            parent = "useSpecColor",
            parentCheck = "checked",         -- shortcut: visible when parent is checked
            order = 3,
        },
    },
})
```

---

## Canvas Layout API

For settings pages that need full control over layout (scroll lists, custom widgets), `CreateCanvasLayout` provides a frame with layout helpers.

```lua
local layout = SB.CreateCanvasLayout("Spell Colors")
local frame  = layout.frame  -- the backing frame

local header = layout:AddHeader("Spell Colors")
header._defaultsButton:SetText("Defaults")
header._defaultsButton:SetScript("OnClick", resetAll)

layout:AddSpacer(4)

local desc = layout:AddDescription("Assign colors to individual spells.", "GameFontHighlight")
desc._text:SetWordWrap(true)

local row, swatch = layout:AddColorSwatch("Default color")
swatch:SetScript("OnClick", openPicker)

local row2, slider, valueText = layout:AddSlider("Size", 10, 50, 1)
slider:SetScript("OnValueChanged", onSliderChanged)

local row3, button = layout:AddButton("Add Entry", "Add")
button:SetScript("OnClick", addEntry)

local scrollBox, scrollBar, view = layout:AddScrollList(ROW_HEIGHT)
view:SetElementInitializer("MyRowTemplate", initRow)
scrollBox:SetDataProvider(dataProvider)
```

### Methods

| Method | Returns | Description |
|---|---|---|
| `AddHeader(text)` | `row` | Settings-style header with `row._title` and `row._defaultsButton`. |
| `AddSpacer(height)` | — | Advances the Y position without creating a frame. |
| `AddDescription(text, fontObject?)` | `row` | Text label with `row._text` (FontString). |
| `AddColorSwatch(label)` | `row, swatch` | Label + color swatch button. |
| `AddSlider(label, min, max, step?)` | `row, slider, valueText` | Label + slider + value FontString. |
| `AddButton(label, buttonText)` | `row, button` | Label + button. |
| `AddScrollList(elementExtent)` | `scrollBox, scrollBar, view` | Full-height scroll list that fills remaining space. Call last. |

---

## Modifier System

All controls and composites support modifier fields in their spec tables. Applied automatically via Blizzard's initializer API.

| Modifier | Blizzard API | Behaviour |
|---|---|---|
| `parent` + `parentCheck` | `SetParentInitializer` | Makes the control a visual child (indented). Shown only when the predicate returns `true`. Default predicate checks the parent's setting value. |
| `disabled` | `AddModifyPredicate` | Greyed out when `disabled()` returns `true`. |
| `hidden` | `AddShownPredicate` | Hidden when `hidden()` returns `true`. |

---

## Composite Defaults

The `compositeDefaults` config field lets you set addon-wide defaults for composite builders. Each composite merges these defaults (lowest priority) under its spec before processing.

```lua
local SB = LSB:New({
    varPrefix = "MYADDON",
    onChanged = function() end,
    compositeDefaults = {
        FontOverrideGroup = {
            fontValues       = GetFontValues,
            fontFallback     = function() return "Friz Quadrata TT" end,
            fontSizeFallback = function() return 12 end,
            fontTemplate     = "MyFontPickerTemplate",
        },
        PositioningGroup = {
            positionModes    = { [1] = "Automatic", [2] = "Free" },
            isAnchorModeFree = function(cfg) return cfg and cfg.anchorMode == 2 end,
        },
    },
})
```

Per-call spec values always override defaults.

---

## Editable Slider Values

LibSettingsBuilder hooks `SettingsSliderControlMixin:Init` globally (once per library version) to make all slider value labels clickable. Clicking the displayed value opens an inline edit box for direct numeric input. Input is clamped to min/max and snapped to the step value.

---

## Full Example

### Imperative API

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local SB = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore    = function() return MyAddonDB.profile end,
        getDefaults = function() return MyAddonDefaults.profile end,
    }),
    varPrefix = "MYADDON",
    onChanged = function() MyAddon:Refresh() end,
    compositeDefaults = {
        PositioningGroup = {
            positionModes    = { attached = "Attached", free = "Free" },
            isAnchorModeFree = function(cfg) return cfg and cfg.anchorMode == "free" end,
        },
    },
})

SB.CreateRootCategory("My Addon")

-- About page on the root category
SB.InfoRow({ name = "Version", value = "1.0.0" })
SB.InfoRow({ name = "Author",  value = "YourName" })

-- Power Bar subcategory
SB.CreateSubcategory("Power Bar")

SB.HeightOverrideSlider("powerBar")

SB.Header("Display")
SB.Slider({
    path = "powerBar.opacity",
    name = "Opacity",
    min = 0, max = 100, step = 1,
    formatter = function(v) return v .. "%" end,
})

SB.Header("Border")
SB.BorderGroup("powerBar.border")

SB.Header("Font")
SB.FontOverrideGroup("powerBar")

SB.Header("Positioning")
SB.PositioningGroup("powerBar")

SB.RegisterCategories()
```

### Table-Driven API

The same Power Bar page as a table:

```lua
SB.CreateRootCategory("My Addon")

-- About info on the root page
SB.RegisterFromTable({
    name = "My Addon",
    rootCategory = true,
    args = {
        version = { type = "info", name = "Version", value = "1.0.0", order = 1 },
        author  = { type = "info", name = "Author",  value = "YourName", order = 2 },
    },
})

SB.RegisterFromTable({
    name = "Power Bar",
    path = "powerBar",
    args = {
        height      = { type = "heightOverride", order = 1 },
        dispHeader  = { type = "header", name = "Display", order = 10 },
        opacity     = { type = "range", path = "opacity", name = "Opacity",
                        min = 0, max = 100, step = 1,
                        formatter = function(v) return v .. "%" end, order = 11 },
        bdrHeader   = { type = "header", name = "Border", order = 20 },
        border      = { type = "border", path = "border", order = 21 },
        fontHeader  = { type = "header", name = "Font", order = 30 },
        font        = { type = "fontOverride", order = 31 },
        posHeader   = { type = "header", name = "Positioning", order = 40 },
        positioning = { type = "positioning", order = 41 },
    },
})

SB.RegisterCategories()
```

---

## Debug Mode

Set `LSB_DEBUG = true` before creating controls to enable spec field validation. Warns on unrecognized spec fields — catching typos like `typee`, `paht`, or `vale` that would otherwise be silently ignored.

```lua
LSB_DEBUG = true  -- Enable during development
```

Zero cost in production (the check is behind a global flag).

---

## Blizzard API Reference

The following Blizzard APIs are wrapped or used internally:

- [`Settings.RegisterVerticalLayoutCategory(name)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — registers a top-level category.
- [`Settings.RegisterVerticalLayoutSubcategory(parent, name)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — registers a subcategory.
- [`Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — registers a canvas subcategory.
- [`Settings.RegisterAddOnCategory(category)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — makes the category visible in Settings.
- [`Settings.RegisterProxySetting(category, variable, varType, name, default, getter, setter)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a setting backed by custom get/set.
- [`Settings.CreateCheckbox(category, setting, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a checkbox control.
- [`Settings.CreateSlider(category, setting, options, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a slider control.
- [`Settings.CreateDropdown(category, setting, optionsGenerator, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a dropdown control.
- [`Settings.CreateColorSwatch(category, setting, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a color picker.
- [`Settings.CreateSliderOptions(min, max, step)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates slider range options.
- [`Settings.OpenToCategory(categoryID)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — opens Settings to a specific category.
- `initializer:SetParentInitializer(parent, predicate)` — parent-child control relationships.
- `initializer:AddModifyPredicate(fn)` — conditionally disables a control.
- `initializer:AddShownPredicate(fn)` — conditionally hides a control.
- `CreateSettingsListSectionHeaderInitializer(text)` — creates a section header row.
- `CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearch)` — creates a button row.

## License

LibSettingsBuilder is distributed under the terms of the GNU General Public License v3.0.
