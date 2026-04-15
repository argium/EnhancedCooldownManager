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

## Registration tree

### `SB.GetRoot(name)`

Returns the singleton root handle, creating and registering the addon root category on the first call.

Required on first call:

- `name`

Notes:

- later calls return the same root handle,
- passing a different name after creation raises an error,
- new consumer code should call this once and reuse the returned handle.

### `root:Register(spec)`

Registers a declarative tree rooted at the singleton root handle.

Supported fields:

- `spec.page` — optional root-owned landing page definition
- `spec.sections` — optional array of section definitions

Root page definition fields:

- `key`
- `rows`
- `name` (optional; defaults to the root name)
- `onShow`
- `onHide`
- `onRegistered(page)`
- `order`

Section definition fields:

- `key`
- `name`
- `path` (defaults to `key`)
- `display = "auto"` or `"nested"`
- `order`
- either `rows` for the single-page shorthand, or `pages` for multi-page sections
- `pageKey`, `pageName`, `pageOrder` for the single-page shorthand
- `onShow`, `onHide`, `onRegistered(page)`, `disabled`, `hidden` for the single-page shorthand page

Page definition fields inside `pages`:

- `key`
- `name` (required for nested/multi-page pages unless you want the section name as the default)
- `path`
- `rows`
- `onShow`
- `onHide`
- `onRegistered(page)`
- `disabled`
- `hidden`
- `order`

Notes:

- single-page sections flatten to a single leaf by default,
- multi-page sections create a visible section node automatically,
- `onRegistered(page)` is the intended hook for storing a registered page handle when you need later `page:Refresh()` calls.

Declarative root registration is the only supported page-construction API.

### Lookup and page operations

- `root:GetSection(key)`
- `root:GetPage(key)`
- `root:HasCategory(category)`
- `section:GetPage(key)`
- `page:GetID()`
- `page:Refresh()`

## Controls

All controls support either:

- **path mode** with `spec.path`, or
- **handler mode** with `spec.get`, `spec.set`, and `spec.key`.

Common spec fields:

- `name`
- `tooltip`
- `default`
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

### `SB.List(spec)`

Creates a first-class dynamic flat list row backed by the normal settings list.

Required fields:

- `height`

Flat-list fields:

- `variant = "swatch"` or `variant = "editor"`
- `items(frame)` → item list

### `SB.SectionList(spec)`

Creates a first-class grouped dynamic list row backed by the normal settings list.

Sectioned-list fields:

- `sections(frame)` → section list

Supported list variants:

- `swatch` — label/icon plus color swatch rows
- `editor` — label plus one or more slider fields, optional swatch, and remove button
- section items use the built-in action-row layout (`up`, `down`, `move`, `delete`)
- section trailers support `type = "modeInput"` for toggle + input + preview + submit rows
  Mode-input trailer display fields may be static values or functions that are re-evaluated during in-place row refreshes.

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
- `SB.PageActions(spec)`

`SB.Button` supports `confirm = true` or a custom confirm string. Confirm dialogs are registered per button to avoid cross-button collisions.
`SB.PageActions` renders right-aligned page-header action buttons.
`SB.InfoRow` accepts function-backed `value` for dynamic text.
## Declarative page rows

Supported canonical row types:

- `checkbox`
- `slider`
- `dropdown`
- `input`
- `color`
- `custom`
- `button`
- `header`
- `subheader`
- `info`
- `canvas`
- `pageActions`
- `list`
- `sectionList`

Supported composite types:

- `border`
- `fontOverride`
- `heightOverride`
- `colorList`
- `checkboxList`

Declarative pages are normally supplied through `root:Register({ page = ..., sections = { ... } })`, either as a root page definition or through section `rows` / `pages` definitions.

## Implementation model

The library has three main families of row builders:

- **proxy controls** — persisted values backed by `Settings.RegisterProxySetting` (`checkbox`, `slider`, `dropdown`, `color`, `input`, `custom`),
- **layout rows** — structural/display rows without stored values (`header`, `subheader`, `info`, `button`, `canvas`, `pageActions`),
- **composites** — helpers that emit multiple child rows (`border`, `fontOverride`, `heightOverride`, `colorList`, `checkboxList`).

`input` is implemented as a built-in custom list row on `SettingsListElementTemplate`. It creates an `InputBoxTemplate` edit box at runtime, subscribes to watched proxy settings through callback handles, and optionally debounces preview refreshes. That gives it built-in-row behavior without requiring a separate XML template.
`canvas` rows stay on the current lifecycle path. Keep using `SB.EmbedCanvas(...)` for bespoke frames when a built-in row is not enough.

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
