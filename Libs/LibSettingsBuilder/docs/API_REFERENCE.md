# API Reference

## Documentation Index

- [README](../README.md)
- [Quick Start](QUICK_START.md)
- [Installation & Compatibility](INSTALLATION.md)
- [Migration Guide](MIGRATION_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## v2 Freeze

Phases 1 and 2 freeze the intended v2 public surface and make raw declarative rows the canonical registration schema.

Target v2 surface:

- `LSB.New(config)`
- `lsb:GetSection(sectionKey)`
- `lsb:GetRootPage()`
- `lsb:GetPage(sectionKey, pageKey)`
- `lsb:HasCategory(category)`
- `page:GetId()`
- `page:Refresh()`
- raw row tables at registration boundaries
- deprecated compatibility namespace: `LSBDeprecated`

Builder-level row helper constructors are no longer part of the public `lsb` instance surface. Use raw row tables through `LSB.New({ ... })`.

### `LSBDeprecated`

Phase 1 establishes `LSBDeprecated` as the compatibility namespace for APIs that will move off the main `LSB` table in a later phase.

Currently exposed there:

- `LSBDeprecated.CreateCanvasLayout(...)`
- `LSBDeprecated.SetCanvasLayoutDefaults(...)`
- `LSBDeprecated.ConfigureCanvasLayout(...)`
- `LSBDeprecated.CreateColorSwatch(...)`
- `LSBDeprecated.CreateHeaderTitle(...)`
- `LSBDeprecated.CreateSubheaderTitle(...)`
- `LSBDeprecated.CanvasLayout`

## Factory

### `LSB.New(config)`

Required fields:

- `name`
- `onChanged(ctx, value)`

Optional fields:

- `store`
- `defaults`
- `page`
- `sections`

Returns an `lsb` runtime instance bound to one category tree.

## Registration tree

`LSB.New(config)` accepts and registers the full declarative tree.

Supported fields:

- `config.page` — optional root-owned landing page definition
- `config.sections` — optional array of section definitions

Root page definition fields:

- `key`
- `rows`
- `name` (optional; defaults to the root name)
- `onShow`
- `onHide`
- `order`

Section definition fields:

- `key`
- `name`
- `path` (defaults to `key`)
- `order`
- `pages`

Page definition fields inside `pages`:

- `key`
- `name` (required for nested/multi-page pages unless you want the section name as the default)
- `path`
- `rows`
- `onShow`
- `onHide`
- `disabled`
- `hidden`
- `order`

Notes:

- single-page sections flatten to a single leaf by default,
- multi-page sections create a visible section node automatically.

Declarative root registration is the only supported page-construction API.

### Lookup and page operations

- `lsb:GetSection(key)`
- `lsb:GetRootPage()`
- `lsb:GetPage(sectionKey, pageKey)`
- `lsb:HasCategory(category)`
- `page:GetId()`
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
- `getTransform`
- `setTransform`
- `onSet`
- `layout`

### `checkbox` row

Creates a boolean checkbox.

### `slider` row

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

### `input` row

Creates a text input row using the standard settings-row layout.

Additional fields:

- `numeric`
- `maxLetters`
- `width`
- `debounce`
- `resolveText(value, setting, frame)`
- `onTextChanged(text, setting, frame)`

Notes:

- the edit box writes through the same proxy-setting pipeline as the other built-in controls,
- `resolveText` enables an optional preview line below the edit box,
- `debounce` delays preview recomputation through `C_Timer.NewTimer`.

### `custom` row

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
- `checkboxList`

## Utility helpers

- `SB.Header(text[, category])`
- `SB.Subheader(spec)`
- `SB.InfoRow(spec)`
- `canvas`
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

Declarative pages are normally supplied through `LSB.New({ page = ..., sections = { ... } })`, either as a root page definition or through section `rows` / `pages` definitions.

## Implementation model

The library has three main families of row builders:

- **proxy controls** — persisted values backed by `Settings.RegisterProxySetting` (`checkbox`, `slider`, `dropdown`, `color`, `input`, `custom`),
- **layout rows** — structural/display rows without stored values (`header`, `subheader`, `info`, `button`, `canvas`, `pageActions`),
- **composites** — helpers that emit multiple child rows (`border`, `fontOverride`, `heightOverride`, `colorList`, `checkboxList`).

`input` is implemented as a built-in custom list row on `SettingsListElementTemplate`. It creates an `InputBoxTemplate` edit box at runtime, subscribes to watched proxy settings through callback handles, and optionally debounces preview refreshes. That gives it built-in-row behavior without requiring a separate XML template.
`canvas` rows stay on the current lifecycle path. Keep using `type = "canvas"` rows for bespoke frames when a built-in row is not enough.

#### `LSBDeprecated.SetCanvasLayoutDefaults(overrides)`

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
