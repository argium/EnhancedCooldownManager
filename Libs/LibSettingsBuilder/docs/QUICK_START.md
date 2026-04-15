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

## Declarative root setup

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
                    desc = "Enable or disable the addon.",
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
})
```

Declarative pages can mix persisted controls and layout-only rows freely, so it is normal to combine `checkbox`, `slider`, `input`, `header`, `subheader`, `info`, `button`, `pageActions`, `list`, `sectionList`, and `canvas` entries on one page.

## Handler mode

```lua
local SB = LSB:New({
    varPrefix = "MYADDON",
    onChanged = function()
        MyAddon:ApplySettings()
    end,
})

SB.GetRoot("My Addon"):Register({
    sections = {
        {
            key = "general",
            name = "General",
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
})
```

## Good defaults for public addons

- Keep `varPrefix` short and unique.
- Point `getStore()` and `getDefaults()` at live tables.
- Keep `onChanged` fast; use it to refresh UI, not rebuild the world.
- Use composites for repeated patterns like borders, font overrides, and positioning.
- Prefer declarative root registration for large standard settings pages.
- Store registered page handles through `onRegistered(page)` and call `page:Refresh()` for async or transient redraws.
- Reach for `SB.Custom(...)` or `SB.EmbedCanvas(...)` only when built-ins like `input`, `list`, and `sectionList` stop fitting.
