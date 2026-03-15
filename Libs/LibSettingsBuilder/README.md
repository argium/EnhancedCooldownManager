# LibSettingsBuilder-1.0

`LibSettingsBuilder` is a World of Warcraft Settings API builder for addon authors who want less boilerplate and more reuse.

It supports:

- path-based bindings for AceDB-style profile tables,
- handler-mode bindings for arbitrary storage,
- composite builders for common settings groups,
- canvas layout helpers for more complex pages,
- deterministic dropdown ordering,
- clickable slider value editing.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## At a glance

| Need | LibSettingsBuilder |
|---|---|
| Standard settings pages | `RegisterFromTable(...)` |
| Fine-grained control | imperative `SB.Checkbox(...)`, `SB.Slider(...)`, etc. |
| Existing AceDB profiles | `PathAdapter(...)` |
| Custom storage | handler mode with `get` / `set` / `key` |
| Reusable settings groups | border, font override, positioning composites |
| Custom settings pages | `CreateCanvasLayout(...)` |

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

## Documentation

- [Installation & Compatibility](docs/INSTALLATION.md)
- [Quick Start](docs/QUICK_START.md)
- [API Reference](docs/API_REFERENCE.md)
- [Migration Guide](docs/MIGRATION_GUIDE.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)

## Notes for library consumers

- Embed the library inside your addon's `Libs/` folder.
- Load `LibStub` before `LibSettingsBuilder`.
- Canvas layout spacing can be tuned globally or per layout.
- Slider value editing and scroll dropdown support are implemented through Settings UI integration hooks.

## License

LibSettingsBuilder is distributed under the terms of the GNU General Public License v3.0.
