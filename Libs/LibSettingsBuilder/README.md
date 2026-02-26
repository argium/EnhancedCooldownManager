# LibSettingsBuilder-1.0

A path-based settings builder for the World of Warcraft [Settings API](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua). Wraps Blizzard's vertical-list settings system with proxy controls, composite groups, and utility helpers — eliminating the boilerplate of registering individual `Settings.RegisterProxySetting` / `Settings.CreateCheckbox` / `Settings.CreateSlider` / etc. calls for each setting.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## Installation

Include `LibSettingsBuilder.xml` in your addon's TOC or load-on-demand XML. It depends on LibStub.

```toc
Libs\LibStub\LibStub.lua
Libs\LibSettingsBuilder\LibSettingsBuilder.xml
```

## Quick Start

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local SB = LSB:New({
    getProfile     = function() return MyAddonDB.profile end,
    getDefaults    = function() return MyAddonDefaults.profile end,
    varPrefix      = "MYADDON",
    onChanged      = function(spec, value) MyAddon:ApplySettings() end,
    getNestedValue = function(tbl, path) return GetNestedValue(tbl, path) end,
    setNestedValue = function(tbl, path, value) SetNestedValue(tbl, path, value) end,
})

SB.CreateRootCategory("My Addon")
SB.CreateSubcategory("General")

SB.PathCheckbox({
    path    = "general.enabled",
    name    = "Enable",
    tooltip = "Enable or disable the addon.",
})

SB.PathSlider({
    path = "general.opacity",
    name = "Opacity",
    min  = 0, max = 100, step = 1,
})

SB.RegisterCategories()
```

## Glossary

| Term | Meaning |
|---|---|
| **Category** | A top-level entry in the WoW Settings panel. Created via `Settings.RegisterVerticalLayoutCategory`. |
| **Subcategory** | A child entry nested under a category. Created via `Settings.RegisterVerticalLayoutSubcategory` or its canvas equivalent. |
| **Vertical layout** | Blizzard's list-based settings presentation where controls are stacked automatically. Contrast with **canvas layout**, where you provide your own frame. |
| **Canvas layout** | A settings page backed by a custom frame that you design and anchor yourself. |
| **Proxy setting** | A `Settings.RegisterProxySetting` object with explicit getter/setter functions, as opposed to an addon setting that reads/writes a saved-variable key directly. All LibSettingsBuilder controls use proxy settings. |
| **Initializer** | The object returned by `Settings.CreateCheckbox`, `Settings.CreateSlider`, etc. Represents a single row in the vertical list. Supports modifiers like `SetParentInitializer`, `AddModifyPredicate`, and `AddShownPredicate`. |
| **Setting** | The data object returned by `Settings.RegisterProxySetting`. Holds the current value and exposes `GetValue()` / `SetValue(value)`. |
| **Spec** | The configuration table passed to every path-based control (`PathCheckbox`, `PathSlider`, etc.). Contains the `path`, `name`, modifiers, and optional transforms. |
| **Path** | A dot-delimited string (`"powerBar.border.color"`) addressing a value in the nested profile table. LibSettingsBuilder resolves it via the `getNestedValue`/`setNestedValue` callbacks. |
| **Modifier** | A predicate function attached to an initializer that controls visibility (`AddShownPredicate`), enabled state (`AddModifyPredicate`), or parent-child nesting (`SetParentInitializer`). |
| **Page-enabled setting** | A setting (typically from `ModuleEnabledCheckbox`) that automatically greys out all other controls on the same page when disabled. |
| **Composite builder** | A higher-level helper (`FontOverrideGroup`, `BorderGroup`, `PositioningGroup`, etc.) that creates multiple related controls in one call. |

## Factory: `lib:New(config)`

Creates a new builder instance. All fields are **required**.

| Field | Type | Description |
|---|---|---|
| `getProfile` | `function() -> table` | Returns the current profile table (the live saved-variables table that settings read from and write to). |
| `getDefaults` | `function() -> table` | Returns the defaults table (same shape as the profile; used to derive default values for each control). |
| `varPrefix` | `string` | Short prefix used to generate unique variable names for [`Settings.RegisterProxySetting`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua). A path `"general.enabled"` with prefix `"ECM"` becomes variable `"ECM_general_enabled"`. |
| `onChanged` | `function(spec, value)` | Called after every setter. Use this to trigger layout refreshes, event broadcasts, etc. |
| `getNestedValue` | `function(tbl, path) -> any` | Reads a dot-delimited path from a table (e.g. `"general.enabled"` → `tbl.general.enabled`). |
| `setNestedValue` | `function(tbl, path, value)` | Writes a value at a dot-delimited path. |

Returns the `SB` table containing all API functions documented below.

---

## Category Management

These functions wrap Blizzard's [`Settings.RegisterVerticalLayoutCategory`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua), [`Settings.RegisterVerticalLayoutSubcategory`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua), and related registration calls.

### `SB.CreateRootCategory(name)`

Registers a top-level vertical-layout category. Sets it as the current target for subsequent controls. Resets subcategory state and page-enabled tracking.

Returns the category object.

### `SB.UseRootCategory()`

Switches the current target back to the root category (for adding controls to the root page after creating subcategories).

### `SB.CreateSubcategory(name)`

Creates a vertical-layout subcategory under the root. Sets it as the current target. Resets the page-enabled setting for the new page.

Returns the subcategory object.

### `SB.CreateCanvasSubcategory(frame, name [, parentCategory])`

Creates a canvas-layout subcategory (your own frame). Wraps [`Settings.RegisterCanvasLayoutSubcategory`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua). Does **not** change the current target.

### `SB.RegisterCategories()`

Calls [`Settings.RegisterAddOnCategory`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) on the root category. Call this once after all categories and controls are set up.

### `SB.GetCategoryID()`

Returns `category:GetID()` for the root category. Use with [`Settings.OpenToCategory`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) to open the settings panel programmatically.

---

## Path-Based Proxy Controls

All path-based controls share a common **spec** table. Each call:

1. Derives a unique variable name from `varPrefix` + `spec.path`.
2. Creates getter/setter functions that read/write via `getNestedValue`/`setNestedValue` on the profile.
3. Reads the default value from the defaults table.
4. Calls [`Settings.RegisterProxySetting`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) and the appropriate `Settings.Create*` factory.
5. Applies modifiers (parent, disabled, hidden, page-enabled).

All controls return `initializer, setting`.

### Common Spec Fields

| Field | Type | Description |
|---|---|---|
| `path` | `string` | **Required.** Dot-delimited path into the profile table (e.g. `"powerBar.height"`). |
| `name` | `string` | **Required.** Display name shown in the settings panel. |
| `tooltip` | `string` | Tooltip text for the control. |
| `category` | `category` | Override the target category. Defaults to the current subcategory or root. |
| `onSet` | `function(value)` | Called after the value is written, before `onChanged`. |
| `getTransform` | `function(raw) -> display` | Transform the stored value before it reaches the UI. |
| `setTransform` | `function(display) -> raw` | Transform the UI value before writing to the profile. |
| `parent` | `initializer` | Makes this control a child of another (uses [`initializer:SetParentInitializer`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua)). The child is shown indented and only when the parent predicate is truthy. |
| `parentCheck` | `function() -> bool` | Custom predicate for the parent relationship. Defaults to checking the parent's setting value. |
| `disabled` | `function() -> bool` | When returns `true`, the control is greyed out (via `AddModifyPredicate`). |
| `hidden` | `function() -> bool` | When returns `true`, the control is hidden (via `AddShownPredicate`). |

### `SB.PathCheckbox(spec)`

Creates a boolean checkbox. Wraps `Settings.RegisterProxySetting` with `Settings.VarType.Boolean` + [`Settings.CreateCheckbox`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua).

```lua
SB.PathCheckbox({
    path    = "powerBar.enabled",
    name    = "Enable power bar",
    tooltip = "Show the power bar beneath the player frame.",
})
```

### `SB.PathSlider(spec)`

Creates a numeric slider. Wraps `Settings.RegisterProxySetting` with `Settings.VarType.Number` + [`Settings.CreateSlider`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua).

All sliders get an editable value label — clicking the value text opens an edit box for direct numeric input.

| Additional Field | Type | Default | Description |
|---|---|---|---|
| `min` | `number` | — | Minimum slider value. |
| `max` | `number` | — | Maximum slider value. |
| `step` | `number` | `1` | Step increment. |
| `formatter` | `function(value) -> string` | Integer or 1-decimal | Custom label formatter passed to `SetLabelFormatter`. |

```lua
SB.PathSlider({
    path = "powerBar.height",
    name = "Height",
    min  = 5, max = 40, step = 1,
    getTransform = function(v) return v or 20 end,
})
```

### `SB.PathDropdown(spec)`

Creates a dropdown selector. Wraps `Settings.RegisterProxySetting` + [`Settings.CreateDropdown`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua). The var type is inferred from the default (`Settings.VarType.Number` if default is a number, otherwise `Settings.VarType.String`).

| Additional Field | Type | Description |
|---|---|---|
| `values` | `table` or `function() -> table` | Map of `value -> label` pairs. Functions are evaluated each time the dropdown opens. |

```lua
SB.PathDropdown({
    path   = "powerBar.anchorMode",
    name   = "Position Mode",
    values = { attached = "Attached", free = "Free" },
})
```

### `SB.PathColor(spec)`

Creates a color swatch. Stores/reads `{r, g, b, a}` tables in the profile and converts to/from hex strings (AARRGGBB) for the proxy setting. Wraps `Settings.CreateColorSwatch`.

```lua
SB.PathColor({
    path = "powerBar.border.color",
    name = "Border color",
})
```

### `SB.PathCustom(spec)`

Creates a proxy setting backed by a custom XML frame template. The template's `Init` receives `initializer:GetData()` containing `{setting, name, tooltip}`.

| Additional Field | Type | Description |
|---|---|---|
| `template` | `string` | **Required.** Name of the XML template (must inherit `SettingsListElementTemplate`). |

```lua
SB.PathCustom({
    path     = "powerBar.texture",
    name     = "Texture",
    template = "MyAddon_TexturePickerTemplate",
})
```

### `SB.PathControl(spec)`

Unified dispatcher. Reads `spec.type` and forwards to the matching factory:

- `"checkbox"` → `PathCheckbox`
- `"slider"` → `PathSlider`
- `"dropdown"` → `PathDropdown`
- `"color"` → `PathColor`
- `"custom"` → `PathCustom`

```lua
SB.PathControl({
    type    = "checkbox",
    path    = "resourceBar.showText",
    name    = "Show text",
    tooltip = "Display the current value on the bar.",
})
```

---

## Composite Builders

Higher-level helpers that create multiple related controls from a single call.

### `SB.ModuleEnabledCheckbox(moduleName, spec)`

Creates a checkbox that acts as the **page-level enable toggle**. After this call, all subsequent controls on the same page automatically get a modify predicate that greys them out when the module is disabled.

| Additional Field | Type | Description |
|---|---|---|
| `setModuleEnabled` | `function(name, enabled)` | **Required.** Called when the toggle changes. |

```lua
SB.ModuleEnabledCheckbox("PowerBar", {
    path             = "powerBar.enabled",
    name             = "Enable power bar",
    setModuleEnabled = function(name, enabled) MyAddon:SetModuleEnabled(name, enabled) end,
})
```

### `SB.SetPageEnabledSetting(setting)`

Manually sets the page-level enabled setting (if you need to wire it up without `ModuleEnabledCheckbox`).

### `SB.HeightOverrideSlider(sectionPath, spec?)`

Convenience slider for `sectionPath .. ".height"`. Value of `0` (the default) means "use the global default"; stores `nil` when set to 0.

### `SB.FontOverrideGroup(sectionPath, spec?)`

Creates a group of controls for per-module font overrides:

1. **Checkbox** at `sectionPath .. ".overrideFont"` — enables the override.
2. **Font dropdown** (or custom template) at `sectionPath .. ".font"` — child of the checkbox.
3. **Font size slider** at `sectionPath .. ".fontSize"` — child of the checkbox.

| Optional Spec Field | Type | Description |
|---|---|---|
| `fontValues` | `function() -> table` | Choices for the font dropdown. |
| `fontFallback` | `function() -> string` | Fallback font name when no override is set. |
| `fontSizeFallback` | `function() -> number` | Fallback size when no override is set. |
| `fontTemplate` | `string` | Custom template name; when provided, uses `PathCustom` instead of `PathDropdown`. |
| `enabledName` | `string` | Override label for the checkbox (default: `"Override font"`). |
| `fontName` / `sizeName` | `string` | Override labels for the font/size controls. |
| `sizeMin` / `sizeMax` / `sizeStep` | `number` | Slider bounds (defaults: 6–32, step 1). |

Returns `{ enabledInit, enabledSetting, fontInit, sizeInit }`.

### `SB.BorderGroup(borderPath, spec?)`

Creates a group for border settings:

1. **Checkbox** at `borderPath .. ".enabled"`.
2. **Slider** at `borderPath .. ".thickness"` (default 1–10).
3. **Color swatch** at `borderPath .. ".color"`.

Returns `{ enabledInit, enabledSetting, thicknessInit, colorInit }`.

### `SB.ColorPickerList(basePath, defs, spec?)`

Creates a list of color swatches from an array of definitions.

```lua
SB.ColorPickerList("resourceBar.colors", {
    { key = "chi",        name = "Chi" },
    { key = "holyPower",  name = "Holy Power" },
    { key = "comboPoints", name = "Combo Points" },
})
```

Each `def` in the array must have:

| Field | Type | Description |
|---|---|---|
| `key` | `string` or `number` | Appended to `basePath` to form the full path. |
| `name` | `string` | Display name. |
| `tooltip` | `string?` | Optional tooltip. |
| `hasAlpha` | `bool?` | Whether the color picker includes alpha. |

Returns an array of `{ key, initializer, setting }`.

### `SB.PositioningGroup(configPath, spec)`

Creates controls for bar positioning:

1. **Dropdown** at `configPath .. ".anchorMode"`.
2. **Width slider** at `configPath .. ".width"` — visible only in free mode.
3. **Offset X slider** at `configPath .. ".offsetX"` — visible only in free mode (omitted if `spec.includeOffsetX == false`).
4. **Offset Y slider** at `configPath .. ".offsetY"` — visible only in free mode.

| Required Spec Field | Type | Description |
|---|---|---|
| `positionModes` | `table` | Value → label map for the anchor mode dropdown. |
| `isAnchorModeFree` | `function(cfg) -> bool` | Returns whether the current mode is "free" (shows offset/width controls). |

| Optional Spec Field | Type | Description |
|---|---|---|
| `applyPositionMode` | `function(cfg, mode)` | Called when the mode changes. |
| `defaultBarWidth` | `number` | Default width value (default: 250). |
| `includeOffsetX` | `bool` | Set to `false` to omit the X offset slider. |

Returns `{ modeInit, modeSetting, widthInit, offsetXInit, offsetYInit }`.

---

## Utility Helpers

### `SB.Header(text [, category])`

Inserts a section header into the vertical list. Wraps `CreateSettingsListSectionHeaderInitializer`.

**Automatic deduplication:** the first header on a page is suppressed if its text matches the subcategory name (avoiding a redundant heading). Headers with the text `"Display"` are always suppressed.

```lua
SB.Header("Colors")
```

### `SB.Label(spec)`

Inserts a smaller, lighter sub-section heading into the vertical list. Uses `GameFontHighlightSmall` (white, small) rather than the bold yellow `GameFontNormal` used by `SB.Header`. Matches the style used by Blizzard's Accessibility → Colors page for headings like "Item Quality".

Unlike `SB.Header`, no automatic deduplication is applied. Supports `parent`, `hidden`, and `disabled` modifiers via `applyModifiers`. Can be used as a parent initializer to nest controls underneath it.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | yes | Display text for the label |
| `category` | category | no | Override the target layout category |
| `parent` | initializer | no | Parent initializer for nesting |
| `hidden` | function | no | Predicate controlling visibility |
| `disabled` | function | no | Predicate controlling enabled state |

```lua
local colorLabel = SB.Label({ name = "Item Quality" })
SB.ColorPickerList("items.colors", COLOR_DEFS, { parent = colorLabel })
```

### `SB.EmbedCanvas(canvas, height, spec?)`

Embeds an arbitrary frame (canvas) into the vertical list at the specified height. Uses the `LibSettingsBuilder_EmbedCanvasTemplate` XML template.

```lua
local preview = CreateFrame("Frame")
preview:SetHeight(100)
SB.EmbedCanvas(preview, 100)
```

### `SB.Button(spec)`

Adds a button to the vertical list. Wraps `CreateSettingsButtonInitializer`.

| Field | Type | Description |
|---|---|---|
| `name` | `string` | **Required.** Display name. |
| `buttonText` | `string` | Button label (defaults to `name`). |
| `onClick` | `function()` | **Required.** Click handler. |
| `tooltip` | `string` | Tooltip text. |
| `confirm` | `bool` or `string` | When truthy, shows a `StaticPopup` confirmation dialog before executing `onClick`. A string value overrides the dialog text. |

```lua
SB.Button({
    name       = "Reset to defaults",
    buttonText = "Reset",
    tooltip    = "Reset all settings to their default values.",
    confirm    = "This will reset all settings. Are you sure?",
    onClick    = function() MyAddon:ResetProfile() end,
})
```

### `SB.RegisterSection(nsTable, key, section)`

Registers a section table into `nsTable.OptionsSections[key]`. Useful for modular option pages that register themselves into a shared namespace.

```lua
local MyOptions = {}
function MyOptions.RegisterSettings(SB)
    SB.CreateSubcategory("My Module")
    SB.ModuleEnabledCheckbox("MyModule", { path = "myModule.enabled", name = "Enable" })
end
SB.RegisterSection(ns, "MyModule", MyOptions)
```

---

## Modifier System

All path-based controls and composites support the following modifier fields in their spec tables. These are applied automatically via Blizzard's initializer API.

| Modifier | Blizzard API Used | Behaviour |
|---|---|---|
| `parent` + `parentCheck` | `initializer:SetParentInitializer(parent, predicate)` | Makes the control a visual child (indented). Shown only when the predicate returns `true`. Default predicate checks the parent's setting value. |
| `disabled` | `initializer:AddModifyPredicate(fn)` | Greyed out when `disabled()` returns `true`. |
| `hidden` | `initializer:AddShownPredicate(fn)` | Hidden when `hidden()` returns `true`. |
| Page-enabled | `initializer:AddModifyPredicate(fn)` | Automatically applied to all controls when a `ModuleEnabledCheckbox` exists on the page. Greyed out when the module is disabled. |

---

## Editable Slider Values

LibSettingsBuilder hooks `SettingsSliderControlMixin:Init` globally (once per library version) to make all slider value labels clickable. Clicking the displayed value opens an inline edit box where users can type an exact number. The input is clamped to the slider's min/max range and snapped to the step value.

---

## Full Example

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local SB = LSB:New({
    getProfile     = function() return MyAddonDB.profile end,
    getDefaults    = function() return MyAddonDefaults.profile end,
    varPrefix      = "MYADDON",
    onChanged      = function() MyAddon:Refresh() end,
    getNestedValue = function(tbl, path) return GetNestedValue(tbl, path) end,
    setNestedValue = function(tbl, path, value) SetNestedValue(tbl, path, value) end,
})

SB.CreateRootCategory("My Addon")

-- Root page
SB.UseRootCategory()
SB.PathCheckbox({ path = "general.welcomeMessage", name = "Show welcome message" })

-- Power Bar subcategory
SB.CreateSubcategory("Power Bar")

SB.ModuleEnabledCheckbox("PowerBar", {
    path             = "powerBar.enabled",
    name             = "Enable power bar",
    setModuleEnabled = function(name, enabled) MyAddon:ToggleModule(name, enabled) end,
})

SB.HeightOverrideSlider("powerBar")

SB.Header("Display")
SB.PathSlider({
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
SB.PositioningGroup("powerBar", {
    positionModes    = { attached = "Attached", free = "Free" },
    isAnchorModeFree = function(cfg) return cfg and cfg.anchorMode == "free" end,
})

-- Profile subcategory
SB.CreateSubcategory("Profiles")
SB.Button({
    name    = "Reset Profile",
    confirm = "This will reset your profile to defaults. Continue?",
    onClick = function() MyAddon:ResetProfile() end,
})

SB.RegisterCategories()
```

## Blizzard API Reference

The following Blizzard APIs are wrapped or used internally:

- [`Settings.RegisterVerticalLayoutCategory(name)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — registers a top-level category with automatic vertical layout.
- [`Settings.RegisterVerticalLayoutSubcategory(parent, name)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — registers a subcategory under a parent.
- [`Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — registers a canvas (custom frame) subcategory.
- [`Settings.RegisterAddOnCategory(category)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — makes the category visible in the settings UI.
- [`Settings.RegisterProxySetting(category, variable, varType, name, default, getter, setter)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a setting backed by custom get/set functions.
- [`Settings.CreateCheckbox(category, setting, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a checkbox control.
- [`Settings.CreateSlider(category, setting, options, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a slider control.
- [`Settings.CreateDropdown(category, setting, optionsGenerator, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a dropdown control.
- [`Settings.CreateColorSwatch(category, setting, tooltip)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates a color picker control.
- [`Settings.CreateSliderOptions(min, max, step)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — creates slider range options.
- [`Settings.OpenToCategory(categoryID, scrollToElementName?)`](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua) — opens the settings UI to a specific category.
- `initializer:SetParentInitializer(parent, predicate)` — establishes parent-child control relationships.
- `initializer:AddModifyPredicate(fn)` — conditionally disables a control.
- `initializer:AddShownPredicate(fn)` — conditionally hides a control.
- `CreateSettingsListSectionHeaderInitializer(text)` — creates a section header row.
- `CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearch)` — creates a button row.

## License

LibSettingsBuilder is distributed under the terms of the GNU General Public License v3.0.
