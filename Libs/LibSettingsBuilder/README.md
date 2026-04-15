# LibSettingsBuilder-1.0

`LibSettingsBuilder` is a World of Warcraft Settings API builder for addon authors who want less boilerplate and more reuse.

It supports:

- path-based bindings for AceDB-style profile tables,
- handler-mode bindings for arbitrary storage,
- built-in text input rows with optional debounced preview resolution,
- first-class dynamic lists and sectioned editors,
- composite builders for common settings groups,
- canonical row types for headers, subheaders, info rows, buttons, canvases, and page actions,
- XML/template-backed custom controls when a built-in row is not enough,
- page-owned refresh hooks for out-of-band state changes,
- deterministic dropdown ordering,
- clickable slider value editing.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## At a glance

| Need | LibSettingsBuilder |
|---|---|
| Standard settings pages | `SB.GetRoot(name)` → `root:Register({ page = ..., sections = { ... } })` |
| Root-owned landing page | `page = { key = ..., rows = ... }` inside the root spec |
| Dynamic refresh | `onRegistered(page)` + `page:Refresh()` |
| Existing AceDB profiles | `PathAdapter(...)` |
| Custom storage | handler mode with `get` / `set` / `key` |
| Text entry / numeric ID fields | `SB.Input(...)` or `type = "input"` |
| Dynamic editors / ordered lists | `type = "list"` or `type = "sectionList"` |
| Reusable settings groups | border, font override, positioning composites |
| XML-backed bespoke widgets | `SB.Custom(...)` |
| Force visible rows to refresh | `page:Refresh()` |

## Quick start

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local SB = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore = function()
            return MyAddonDB.profile
        end,
        getDefaults = function()
            return MyAddonDefaults.profile
        end,
    }),
    varPrefix = "MYADDON",
    onChanged = function()
        MyAddon:Refresh()
    end,
})

local root = SB.GetRoot("My Addon")

root:Register({
    page = {
        key = "about",
        rows = {
            {
                type = "info",
                name = "Version",
                value = "1.0.0",
            },
        },
    },
    sections = {
        {
            key = "general",
            name = "General",
            path = "general",
            rows = {
                {
                    type = "checkbox",
                    path = "enabled",
                    name = "Enable",
                },
                {
                    type = "slider",
                    path = "opacity",
                    name = "Opacity",
                    min = 0,
                    max = 100,
                    step = 1,
                },
            },
        },
    },
})
```

## Canonical row types

Declarative pages accept canonical row types only.

| Type | Meaning |
|---|---|
| `checkbox` | Boolean proxy setting |
| `slider` | Numeric proxy setting |
| `dropdown` | Deterministic menu proxy setting |
| `input` | Built-in text input row with optional preview / debounce support |
| `color` | Color swatch proxy setting |
| `button` | Button row |
| `header` | Blizzard-style section header |
| `subheader` | Secondary text row |
| `info` | Left-label / right-value informational row |
| `canvas` | Embedded frame row for canvas content |
| `pageActions` | Right-aligned page-header action row |
| `list` | First-class dynamic flat list widget |
| `sectionList` | First-class dynamic grouped list widget |
| `custom` | Proxy setting backed by a custom XML template |
| `colorList` | Expands `defs` into multiple color swatches |
| `checkboxList` | Expands `defs` into multiple checkboxes |
| `border` | Composite group for border enable / width / color |
| `fontOverride` | Composite group for override toggle, font picker, and size slider |
| `heightOverride` | Composite slider with nil/zero transforms |

## Input rows

`input` is the newest built-in control type. It is intended for cases where you want a normal settings row layout, but need text entry instead of a dropdown or slider.

Supported `input` spec fields include the standard binding/modifier fields plus:

- `numeric = true` — sets the edit box to numeric-only mode.
- `maxLetters` — limits input length.
- `width` — overrides the edit box width (default `140`).
- `debounce` — delays preview refresh by N seconds.
- `resolveText(value, setting, frame)` — returns the preview text shown under the edit box.
- `watch = { ... }` — names/paths of sibling settings that should force the preview to refresh.
- `watchVariables = { ... }` — direct proxy-setting variable names to watch.
- `onTextChanged(text, setting, frame)` — optional hook fired after the new text is written.

Example:

```lua
spellId = {
    type = "input",
    name = "Spell ID",
    key = "draftSpellId",
    numeric = true,
    maxLetters = 10,
    debounce = 1,
    get = function()
        return draft.spellIdText
    end,
    set = function(value)
        draft.spellIdText = value or ""
    end,
    resolveText = function(value)
        local id = tonumber(value)
        return id and C_Spell.GetSpellName(id) or nil
    end,
}
```

## Implementation notes

The library has three main implementation paths:

- **Proxy controls** — `checkbox`, `slider`, `dropdown`, `color`, `input`, and `custom` all go through the same proxy-setting pipeline. That means path mode and handler mode work consistently across them.
- **Layout rows** — `header`, `subheader`, `info`, `button`, `canvas`, and `pageActions` are initializer/layout helpers rather than persisted settings.
- **Composite rows** — `border`, `fontOverride`, `heightOverride`, `colorList`, and `checkboxList` expand into multiple child controls.

The recommended author-facing registration model is declarative: get the singleton root once, export plain page/section spec tables, and call `root:Register(...)` with the assembled tree. Deprecated non-declarative page-construction APIs have been removed.

Use `pageActions` for right-aligned page buttons. Use `list` and `sectionList` for dynamic editors, and keep `canvas` / `custom` as escape hatches for truly bespoke frames. Canvas rows stay on the existing lifecycle path, so page switches continue to reuse the same proven frame handling.

`input` specifically is implemented as a built-in custom list row using `SettingsListElementTemplate`, with an `InputBoxTemplate` edit box anchored in the standard left-label / right-control layout. It does **not** need a separate XML template the way `custom` controls do.

Under the hood, an input row:

1. creates a normal proxy setting via `Settings.RegisterProxySetting`,
2. writes the current edit-box text back through that setting on `OnTextChanged`,
3. optionally debounces preview work through `C_Timer.NewTimer`,
4. refreshes the preview immediately when watched settings change via callback handles, and
5. reuses the same enabled / hidden / parent modifier system as the other built-in controls.

That keeps `input` aligned with the rest of the builder instead of turning it into a one-off control with different binding behavior.

## Documentation

- [Installation & Compatibility](docs/INSTALLATION.md)
- [Quick Start](docs/QUICK_START.md)
- [API Reference](docs/API_REFERENCE.md)
- [Migration Guide](docs/MIGRATION_GUIDE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Testing

Tests live in `Tests/` and use [busted](https://olivinelabs.com/busted/). Run from the **host addon root** (the directory containing `.busted`):

```sh
busted --run libsettingsbuilder
```

The `.busted` config defines the `libsettingsbuilder` task pointing at this library's test directory.

## Notes for library consumers

- Embed the library inside your addon's `Libs/` folder.
- Load `LibStub` before `LibSettingsBuilder`.
- Load `Libs\LibSettingsBuilder\embed.xml` rather than the individual library Lua files.
- Prefer a single `root:Register({ page = ..., sections = { ... } })` call and keep page handles only for later `page:Refresh()` calls.
- `page:Refresh()` is the intended way to refresh dynamic info rows, dropdown options, and dynamic list rows after profile mutations, async item loads, or other out-of-band changes.
- Slider value editing and scroll dropdown support are implemented through Settings UI integration hooks.

## License

LibSettingsBuilder is distributed under the terms of the GNU General Public License v3.0.
