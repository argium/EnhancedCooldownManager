# Quick Start

## Documentation Index

- [README](../README.md)
- [Installation & Compatibility](INSTALLATION.md)
- [API Reference](API_REFERENCE.md)
- [Migration Guide](MIGRATION_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## Choose a setup style

- Use **declarative root registration** for standard settings pages.
- Use **handler mode** if your settings are not stored in a dot-path table.
- Use `input` rows when you need text or numeric entry without building a custom template.
- Use `list` or `sectionList` rows when you need ordered lists, grouped editors, or add/remove workflows without dropping into a bespoke frame API.

## Declarative setup

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local lsb = LSB.New({
    name = "My Addon",
    store = MyAddonDB.profile,
    defaults = MyAddonDefaults.profile,
    onChanged = function(ctx)
        MyAddon:Refresh()
    end,
    sections = {
        {
            key = "general",
            name = "General",
            path = "general",
            pages = {
                {
                    key = "main",
                    rows = {
                        {
                            type = "checkbox",
                            path = "enabled",
                            name = "Enable",
                            tooltip = "Enable or disable the addon.",
                        },
                        {
                            type = "slider",
                            path = "opacity",
                            name = "Opacity",
                            min = 0,
                            max = 100,
                            step = 1,
                        },
                        {
                            type = "input",
                            path = "spellIdText",
                            name = "Spell ID",
                            numeric = true,
                            maxLetters = 10,
                            debounce = 1,
                            resolveText = function(value)
                                local id = tonumber(value)
                                return id and C_Spell.GetSpellName(id) or nil
                            end,
                        },
                    },
                },
            },
        },
    },
})
```

`name` and `onChanged` are required when you register a root page or section tree. `store` enables path mode; use handler mode when your values do not live in a dot-path table.

Declarative pages can mix persisted controls and layout-only rows freely, so it is normal to combine `checkbox`, `slider`, `input`, `header`, `subheader`, `info`, `button`, `pageActions`, `list`, `sectionList`, and `canvas` entries on one page.

## Handler mode

```lua
local lsb = LSB.New({
    name = "My Addon",
    onChanged = function(ctx)
        MyAddon:ApplySettings()
    end,
    sections = {
        {
            key = "general",
            name = "General",
            pages = {
                {
                    key = "main",
                    rows = {
                        {
                            type = "checkbox",
                            get = function()
                                return MyStore.enabled
                            end,
                            set = function(value)
                                MyStore.enabled = value
                            end,
                            key = "enabled",
                            default = true,
                            name = "Enable",
                        },
                        {
                            type = "input",
                            get = function()
                                return MyStore.searchText or ""
                            end,
                            set = function(value)
                                MyStore.searchText = value
                            end,
                            key = "searchText",
                            default = "",
                            name = "Search",
                        },
                    },
                },
            },
        },
    },
})
```

Handler rows require `get`, `set`, and a stable `key` (or `id`).

## Good defaults for public addons

- Pick a stable `name`; the library derives its internal variable prefix from that.
- Point `store` and `defaults` at live tables.
- Keep `onChanged` fast; use it to refresh UI, not rebuild the world.
- Use composites for repeated patterns like borders, font overrides, and height overrides.
- Prefer declarative root registration for large standard settings pages.
- Look up registered page handles with `lsb:GetRootPage()` or `lsb:GetPage(...)`, then call `page:Refresh()` for async or transient redraws.
- Reach for `type = "custom"` or `type = "canvas"` only when built-ins like `input`, `list`, and `sectionList` stop fitting.
