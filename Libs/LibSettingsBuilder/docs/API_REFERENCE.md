# API Reference

## Documentation Index

- [README](../README.md)
- [Quick Start](QUICK_START.md)
- [Installation & Compatibility](INSTALLATION.md)
- [Migration Guide](MIGRATION_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## Current public surface

`LibSettingsBuilder` is centered on declarative registration through `LSB.New({ ... })`.

Documented surface:

- `LSB.New(config)`
- `LSB:RegisterRowType(name, descriptor)`
- `lsb:GetSection(sectionKey)`
- `lsb:GetRootPage()`
- `lsb:GetPage(sectionKey, pageKey)`
- `lsb:HasCategory(category)`
- `page:GetId()`
- `page:Refresh()`
- `config.page` and `config.sections`
- `config.defaultsConfirmation`
- raw row tables in `rows = { ... }`
- page defaults fields: `onDefault`, `onDefaultEnabled`, `hideDefaults`, and `defaultsConfirmText`

The runtime returned by `LSB.New(...)` is intentionally narrow. Row helper constructors are not available on `lsb` instances, and deprecated transition namespaces like `LSBDeprecated` are not part of the documented public API.

The declarative loader still normalizes a small compatibility subset of older field names:

- `button.value` → `buttonText`
- `info.values` → newline-joined `value` plus `multiline = true`

Removed fields such as `desc`, `condition`, `parent`, and `parentCheck` error at registration time.

## Factory

### `LSB.New(config)`

Required fields:

- `onChanged(ctx, value)`

Conditionally required fields:

- `name` — required when registering `page` or `sections`

Optional fields:

- `store` — table or function returning the live store used by path-bound rows
- `defaults` — table or function returning default values for path-bound rows
- `defaultsConfirmation` — table of localized strings for page Defaults confirmations; required when page defaults are enabled by path-bound defaultable rows or `onDefault`
- `getNestedValue`
- `setNestedValue`
- `page`
- `sections`

Returns an `lsb` runtime instance bound to one category tree.

`defaultsConfirmation` fields:

- `text` — confirmation prompt; `%s`, when present, is replaced with the lowercase page name
- `button1` — accept button text
- `button2` — decline button text

### `LSB:RegisterRowType(name, descriptor)`

Registers a reusable Lua-backed proxy row type. The descriptor must provide `applyFrame(frame, data, initializer)` and may provide `resetFrame(frame)`, `extent`, `varType`, and `defaultValue`.

Registered rows render on Blizzard's `SettingsListElementTemplate`; no XML template is required.

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
- `onDefault`
- `onDefaultEnabled`
- `hideDefaults`
- `defaultsConfirmText`
- `disabled`
- `hidden`
- `order`
- `path`

Section definition fields:

- `key`
- `name`
- `path` (defaults to `key`)
- `order`
- `pages`

Page definition fields inside `pages`:

- `key`
- `name` (optional; in a multi-page section, omitting it makes that page use the visible section category)
- `path`
- `rows`
- `onShow`
- `onHide`
- `onDefault`
- `onDefaultEnabled`
- `hideDefaults`
- `defaultsConfirmText`
- `disabled`
- `hidden`
- `order`
- `useSectionCategory` (optional explicit form of the omitted-`name` multi-page behavior)

Notes:

- single-page sections flatten to a single leaf by default,
- multi-page sections create a visible section node automatically,
- one multi-page section page can live directly on that section node; named pages are registered below it.
- page `path` prefixes child `path` fields that do not already contain dots,
- page-level `disabled` and `hidden` values propagate to child rows unless a row overrides them.

Declarative root registration is the only supported page-construction API.

### Page defaults behavior

LibSettingsBuilder can override Blizzard's category **Defaults** button for a visible page.

The button is active when the page has resettable path-bound rows or provides `onDefault`. Pages with resettable path-bound rows reset those rows to values from `config.defaults`; pages with `onDefault` run that callback instead.

Page defaults fields:

- `onDefault(ctx)` — custom reset callback for the page. When present, it replaces generic path-bound setting resets for that page.
- `onDefaultEnabled(ctx)` — optional predicate for enabling the Defaults button. When omitted, the button is enabled.
- `hideDefaults = true` — hides the category Defaults button while the page is visible. Use this for informational pages or pages where reset behavior does not apply.
- `defaultsConfirmText` — page-specific confirmation prompt. If omitted, `config.defaultsConfirmation.text` is used. `%s`, when present, is replaced with the lowercase page name; prompts without `%s` are shown verbatim.

`config.defaultsConfirmation` is required for pages that expose Defaults behavior through resettable path-bound rows or `onDefault`. Its `button1` and `button2` labels are shared by all page defaults confirmations for that runtime.

### Lookup and page operations

- `lsb:GetSection(key)` — registered section metadata or `nil`
- `lsb:GetRootPage()` — root page handle or `nil`
- `lsb:GetPage(sectionKey, pageKey)` — section page handle or `nil`
- `lsb:HasCategory(category)` — whether the category belongs to this runtime
- `page:GetId()` — Blizzard Settings category ID
- `page:Refresh()` — refreshes visible rows and registered dynamic content

Page handles are plain runtime lookup objects, not mutable builders.

## Declarative rows

Persisted rows support either:

- **path mode** with `spec.path`, or
- **handler mode** with `spec.get`, `spec.set`, and `spec.key` or `spec.id`.

Common spec fields:

- `id`
- `name`
- `tooltip`
- `default`
- `disabled`
- `hidden`
- `getTransform`
- `setTransform`
- `onSet`

Use `tooltip`, not `desc`.

### `checkbox` row

Creates a boolean checkbox.

### `slider` row

Additional fields:

- `min`
- `max`
- `step`
- `formatter`

Slider values are editable inline through the displayed value label.

### `dropdown` row

Additional fields:

- `values`
- `scrollHeight`
- `varType`

Dropdown values are emitted in deterministic order to keep menus stable between sessions.

### `color` row

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

### `button` row

Additional fields:

- `buttonText`
- `confirm`
- `onClick`

Notes:

- `onClick` is required,
- `confirm = true` uses the default `"Are you sure?"` prompt,
- `confirm = "..."` uses your custom confirm text,
- `value` is still normalized to `buttonText` for compatibility.

### `header` row

Use for a Blizzard-style section header.

Required fields:

- `name`

Notes:

- page header buttons belong in a separate `pageActions` row, not on the `header` row.

### `subheader` row

Use for smaller secondary section text.

Required fields:

- `name`

### `info` row

Displays left-label / right-value informational text.

Additional fields:

- `value`
- `values`
- `wide`
- `multiline`
- `height`

Notes:

- `value` may be a static value or a function,
- `name` may also be a function for dynamic labels,
- `wide = true` hides the left label and lets the value span the row,
- `values = { ... }` is normalized to a newline-joined `value` and sets `multiline = true`.

### `canvas` row

Embeds a prebuilt frame into the settings page.

Additional fields:

- `canvas`
- `height`

Notes:

- `canvas` is required,
- `height` defaults to `canvas:GetHeight()`.

### `pageActions` row

Renders right-aligned page-header action buttons.

Additional fields:

- `actions`
- `height`

Action fields:

- `name`
- `text`
- `width`
- `height`
- `enabled`
- `hidden`
- `tooltip`
- `onClick`

Notes:

- `actions` is required,
- `enabled`, `hidden`, and `tooltip` may be static values or functions evaluated during refreshes.

### `list` row

Creates a first-class dynamic flat list row backed by the normal settings list.

Required fields:

- `height`
- `items(frame)`

Flat-list fields:

- `variant = "swatch"` or `variant = "editor"`
- `rowHeight`
- `insetLeft`
- `insetTop`
- `insetBottom`

Notes:

- the row's `variant` becomes the default preset for returned items,
- `swatch` rows support label/icon/swatch style entries,
- `editor` rows support label + slider field(s), optional swatch, and a remove button.

### `sectionList` row

Creates a first-class grouped dynamic list row backed by the normal settings list.

Required fields:

- `height`
- `sections(frame)` → section list

Section-level fields commonly used by the built-in renderer:

- `key`
- `name`
- `title`
- `items`
- `emptyText`
- `headerHeight`
- `emptyHeight`
- `rowHeight`
- `footer`
- `footerHeight`
- `spacingAfter`

Supported list variants:

- `swatch` — label/icon plus color swatch rows
- `editor` — label plus one or more slider fields, optional swatch, and remove button
- section items use the built-in action-row layout (`up`, `down`, `move`, `delete`)
- section action buttons may use text, `iconTexture`, or `buttonTextures = { normal, pushed?, disabled?, highlight?, highlightAlpha?, disabledAlpha? }`
- section trailers support `type = "modeInput"` for toggle + input + preview + submit rows
- mode-input trailers may set `modeHidden = true` for item-only add rows that should not show a type toggle
  Mode-input trailer display fields may be static values or functions that are re-evaluated during in-place row refreshes.

## Composite row types

These row kinds expand into multiple child rows during registration.

### `heightOverride`

Fields:

- `path`
- `name`
- `tooltip`
- `min`
- `max`
- `step`

Notes:

- stores `nil` when the slider is set to `0`,
- reads `nil` back as `0`.

### `fontOverride`

Fields:

- `path`
- `enabledName`
- `enabledTooltip`
- `fontName`
- `fontTooltip`
- `fontValues`
- `fontFallback`
- `sizeName`
- `sizeTooltip`
- `sizeMin`
- `sizeMax`
- `sizeStep`
- `fontSizeFallback`

Notes:

- expands to an override checkbox, a font selector, and a size slider.
- uses a registered `type = "font"` row when available; otherwise uses a built-in `dropdown` selector.
- `fontValues` may provide the fallback dropdown values as a table or function; when omitted, the fallback dropdown lists the current `fontFallback()` value when available.

### `border`

Fields:

- `path`
- `enabledName`
- `enabledTooltip`
- `thicknessName`
- `thicknessTooltip`
- `thicknessMin`
- `thicknessMax`
- `thicknessStep`
- `colorName`
- `colorTooltip`

Notes:

- expands to an enable checkbox, a width slider, and a color swatch.

### `colorList` / `checkboxList`

Required fields:

- `defs`

Fields:

- `path`
- `defs = { { key, name, tooltip? }, ... }`
- `label`

Notes:

- `defs` is required for both composite row types,
- `label`, when present, inserts a subheader above the generated child rows.

## Declarative page rows

Supported canonical row types:

- `checkbox`
- `slider`
- `dropdown`
- `input`
- `color`
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

The public API is declarative and intentionally narrow. Internally, the library is structured as a thin translation pipeline:

- **Schema** normalizes and validates raw row tables.
- **Registry** materializes root pages, sections, page handles, refresh behavior, lifecycle callbacks, store/default bindings, callback contexts, and composite child rows.
- **Builders** translate prepared row specs into simple primitive operations. Builders do not receive the runtime object or call Registry.
- **Interop** is the only layer that calls Blizzard Settings/UI APIs, creates frames, installs hooks, or renders registered row widgets.

Row builders still fall into the same public families:

- **proxy controls** — persisted values backed by proxy settings (`checkbox`, `slider`, `dropdown`, `color`, `input`, and registered row types),
- **layout rows** — structural/display rows without stored values (`header`, `subheader`, `info`, `button`, `canvas`, `pageActions`),
- **composites** — declarative specs expanded by Registry into multiple child rows (`border`, `fontOverride`, `heightOverride`, `colorList`, `checkboxList`).

`input` is implemented as a built-in custom list row on `SettingsListElementTemplate`. It creates an `InputBoxTemplate` edit box at runtime, subscribes to watched proxy settings through callback handles, and optionally debounces preview refreshes. That gives it built-in-row behavior without requiring a separate XML template.
`canvas` rows stay on the current lifecycle path. The documented public canvas API is the `canvas` row type; older canvas-layout helpers live under internal implementation details and are not part of the public surface documented here.
