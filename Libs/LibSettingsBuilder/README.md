# LibSettingsBuilder-1.0

`LibSettingsBuilder` is a World of Warcraft Settings API builder for addon authors who want less boilerplate and more reuse.

It supports:

- path-based bindings for AceDB-style profile tables,
- handler-mode bindings for arbitrary storage,
- built-in text input rows with optional debounced preview resolution,
- first-class dynamic collections for scrollable or sectioned list editors,
- composite builders for common settings groups,
- layout-only rows such as headers, subheaders, info rows, buttons, and embedded canvases,
- XML/template-backed custom controls when a built-in row is not enough,
- category refresh hooks for out-of-band state changes,
- deterministic dropdown ordering,
- clickable slider value editing.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## At a glance

| Need | LibSettingsBuilder |
|---|---|
| Standard settings pages | `RegisterFromTable(...)` |
| Fine-grained control | imperative `SB.Checkbox(...)`, `SB.Slider(...)`, `SB.Input(...)`, etc. |
| Existing AceDB profiles | `PathAdapter(...)` |
| Custom storage | handler mode with `get` / `set` / `key` |
| Text entry / numeric ID fields | `SB.Input(...)` or `type = "input"` |
| Dynamic editors / ordered lists | `SB.Collection(...)` or `type = "collection"` |
| Reusable settings groups | border, font override, positioning composites |
| XML-backed bespoke widgets | `SB.Custom(...)` |
| Force visible rows to refresh | `SB.RefreshCategory(...)` |

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

SB.CreateRootCategory("My Addon")

SB.RegisterFromTable({
    name = "General",
    path = "general",
    args = {
        enabled = {
            type = "toggle",
            path = "enabled",
            name = "Enable",
            order = 1,
        },
        opacity = {
            type = "range",
            path = "opacity",
            name = "Opacity",
            min = 0,
            max = 100,
            step = 1,
            order = 2,
        },
    },
})

SB.RegisterCategories()
```

## Supported `RegisterFromTable` types

The table API understands both AceConfig-style aliases and library-specific row types.

| Type | Meaning |
|---|---|
| `toggle` | Alias for a checkbox proxy setting |
| `range` | Alias for a slider proxy setting |
| `select` | Alias for a dropdown proxy setting |
| `input` | Built-in text input row with optional preview / debounce support |
| `color` | Color swatch proxy setting |
| `execute` | Alias for a button row |
| `header` | Blizzard-style section header |
| `description` | Alias for a subheader row |
| `info` | Left-label / right-value informational row |
| `canvas` | Embedded frame row for canvas content |
| `collection` | First-class dynamic list/section widget |
| `custom` | Proxy setting backed by a custom XML template |
| `colorList` | Expands `defs` into multiple color swatches |
| `toggleList` | Expands `defs` into multiple checkboxes |
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
- **Layout rows** — `header`, `subheader`, `info`, `button`, `canvas`, and `collection` are initializer/layout helpers rather than persisted settings.
- **Composite rows** — `border`, `fontOverride`, `heightOverride`, `colorList`, and `toggleList` expand into multiple child controls.

`header` supports optional `actions = { ... }` for right-aligned page or section buttons, and `collection` covers the common "custom canvas page" cases without making authors drop into a second authoring API. Use `canvas` and `custom` as escape hatches, not the default path.

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
- Prefer one `RegisterFromTable(...)` DSL for both simple rows and complex editors.
- `SB.RefreshCategory(...)` is the intended way to refresh dynamic info rows, dropdown options, and collections after profile mutations, async item loads, or other out-of-band changes.
- Slider value editing and scroll dropdown support are implemented through Settings UI integration hooks.

## License

LibSettingsBuilder is distributed under the terms of the GNU General Public License v3.0.
