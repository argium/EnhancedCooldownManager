# API Reference

## Documentation Index

- [README](../README.md)
- [Quick Start](QUICK_START.md)
- [Installation & Compatibility](INSTALLATION.md)
- [Migration Guide](MIGRATION_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## Factory

### `LSB:New(config)`

Required fields:

- `varPrefix`
- `onChanged(spec, value)`

Optional fields:

- `pathAdapter`
- `compositeDefaults`

Returns a builder instance referred to as `SB` in the examples below.

## Path adapters

### `LSB.PathAdapter(config)`

Required:

- `getStore()`
- `getDefaults()`

Optional:

- `getNestedValue(tbl, path)`
- `setNestedValue(tbl, path, value)`

Methods:

- `adapter:resolve(path)` → `{ get, set, default }`
- `adapter:read(path)` → current value

The built-in path helpers support numeric segments like `colors.0`.

## Category helpers

- `SB.CreateRootCategory(name)`
- `SB.CreateSubcategory(name)`
- `SB.CreateCanvasSubcategory(frame, name[, parentCategory])`
- `SB.CreateCanvasLayout(name[, parentCategory])`
- `SB.RegisterCategories()`
- `SB.GetRootCategoryID()`
- `SB.GetSubcategoryID(name)`

## Controls

All controls support either:

- **path mode** with `spec.path`, or
- **handler mode** with `spec.get`, `spec.set`, and `spec.key`.

Common spec fields:

- `name`
- `tooltip`
- `default`
- `category`
- `disabled`
- `hidden`
- `parent`
- `parentCheck`
- `getTransform`
- `setTransform`
- `onSet`
- `layout`

### `SB.Checkbox(spec)`

Creates a boolean checkbox.

### `SB.Slider(spec)`

Additional fields:

- `min`
- `max`
- `step`
- `formatter`

Slider values are editable inline through the displayed value label.

### `SB.Dropdown(spec)`

Additional fields:

- `values`
- `scrollHeight`

Dropdown values are emitted in deterministic order to keep menus stable between sessions.

### `SB.Color(spec)`

Reads and writes `{ r, g, b, a }` tables through a hex proxy value.

### `SB.Input(spec)`

Creates a text input row using the standard settings-row layout.

Additional fields:

- `numeric`
- `maxLetters`
- `width`
- `debounce`
- `resolveText(value, setting, frame)`
- `watch`
- `watchVariables`
- `onTextChanged(text, setting, frame)`

Notes:

- the edit box writes through the same proxy-setting pipeline as the other built-in controls,
- `resolveText` enables an optional preview line below the edit box,
- `debounce` delays preview recomputation through `C_Timer.NewTimer`,
- `watch` accepts sibling spec identifiers and resolves them to this builder's proxy-setting variables,
- `watchVariables` accepts already-resolved proxy-setting variable names.

### `SB.Custom(spec)`

Additional fields:

- `template`
- `varType`

Notes:

- use this for XML-backed widgets that are not covered by the built-in controls,
- the template must already be loaded by the time you register settings,
- unlike `input`, `custom` does not create its frame structure in Lua.

### `SB.Control(spec)`

Dispatches to the correct control factory using `spec.type`.

## Composite builders

- `SB.HeightOverrideSlider(sectionPath[, spec])`
- `SB.FontOverrideGroup(sectionPath[, spec])`
- `SB.BorderGroup(borderPath[, spec])`
- `SB.ColorPickerList(basePath, defs[, spec])`
- `SB.CheckboxList(basePath, defs[, spec])`

## Utility helpers

- `SB.Header(text[, category])`
- `SB.Subheader(spec)`
- `SB.InfoRow(spec)`
- `SB.EmbedCanvas(canvas, height[, spec])`
- `SB.Button(spec)`
- `SB.RegisterSection(nsTable, key, section)`

`SB.Button` supports `confirm = true` or a custom confirm string. Confirm dialogs are registered per button to avoid cross-button collisions.

## Table-driven registration

### `SB.RegisterFromTable(tbl)`

Supported standard types:

- `checkbox` / `toggle`
- `slider` / `range`
- `dropdown` / `select`
- `input`
- `color`
- `custom`
- `button` / `execute`
- `header`
- `subheader` / `description`
- `info`
- `canvas`

Supported composite types:

- `border`
- `fontOverride`
- `heightOverride`
- `colorList`
- `toggleList`

## Implementation model

The library has three main families of row builders:

- **proxy controls** — persisted values backed by `Settings.RegisterProxySetting` (`checkbox`, `slider`, `dropdown`, `color`, `input`, `custom`),
- **layout rows** — structural/display rows without stored values (`header`, `subheader`, `info`, `button`, `canvas`),
- **composites** — helpers that emit multiple child rows (`border`, `fontOverride`, `heightOverride`, `colorList`, `toggleList`).

`input` is implemented as a built-in custom list row on `SettingsListElementTemplate`. It creates an `InputBoxTemplate` edit box at runtime, subscribes to watched proxy settings through callback handles, and optionally debounces preview refreshes. That gives it built-in-row behavior without requiring a separate XML template.

## Canvas layout helpers

`CreateCanvasLayout` returns a layout object with these methods:

- `AddHeader(text)`
- `AddSpacer(height)`
- `AddDescription(text[, fontObject])`
- `AddColorSwatch(label)`
- `AddSlider(label, min, max[, step])`
- `AddButton(label, buttonText)`
- `AddScrollList(elementExtent)`

### Canvas layout configuration

Library defaults live on `LSB.CanvasLayoutDefaults` and can be adjusted globally or per layout.

#### `SB.SetCanvasLayoutDefaults(overrides)`

Merges overrides into the shared defaults table.

#### `SB.ConfigureCanvasLayout(layout, overrides)`

Clones the shared defaults and applies overrides only to the supplied layout.

Useful fields include:

- `elementHeight`
- `headerHeight`
- `labelX`
- `controlCenterX`
- `buttonCenterX`
- `buttonWidth`
- `sliderWidth`
- `swatchCenterX`
- `verifiedPatch`

Example:

```lua
local layout = SB.CreateCanvasLayout("Spell Colors")
SB.ConfigureCanvasLayout(layout, {
    elementHeight = 30,
    labelX = 42,
    buttonWidth = 220,
})
```

## Debugging

Set `LSB_DEBUG = true` to warn about unknown spec fields while developing new settings definitions.
