# Quick Start

## Documentation Index

- [README](../README.md)
- [Installation & Compatibility](INSTALLATION.md)
- [API Reference](API_REFERENCE.md)
- [Migration Guide](MIGRATION_GUIDE.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## Choose a setup style

- Use **table-driven registration** if you want the shortest path to a normal settings page.
- Use the **imperative API** if you want precise control over layout and call order.
- Use **handler mode** if your settings are not stored in a dot-path table.
- Use `input` rows when you need text or numeric entry without building a custom template.

## Table-driven setup

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
            desc = "Enable or disable the addon.",
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
        spellId = {
            type = "input",
            path = "spellIdText",
            name = "Spell ID",
            numeric = true,
            maxLetters = 10,
            debounce = 1,
            order = 3,
            resolveText = function(value)
                local id = tonumber(value)
                return id and C_Spell.GetSpellName(id) or nil
            end,
        },
    },
})

SB.RegisterCategories()
```

## Imperative setup

```lua
SB.CreateRootCategory("My Addon")
SB.CreateSubcategory("General")

SB.Checkbox({
    path = "general.enabled",
    name = "Enable",
    tooltip = "Enable or disable the addon.",
})

SB.Slider({
    path = "general.opacity",
    name = "Opacity",
    min = 0,
    max = 100,
    step = 1,
})

SB.Input({
    path = "general.spellIdText",
    name = "Spell ID",
    numeric = true,
    debounce = 1,
    resolveText = function(value)
        local id = tonumber(value)
        return id and C_Spell.GetSpellName(id) or nil
    end,
})

SB.RegisterCategories()
```

`RegisterFromTable(...)` can mix persisted controls and layout-only rows freely, so it is normal to combine `toggle`, `range`, `input`, `header`, `description`, `info`, `button`, and `canvas` entries on one page.

## Handler mode

```lua
local SB = LSB:New({
    varPrefix = "MYADDON",
    onChanged = function()
        MyAddon:ApplySettings()
    end,
})

SB.CreateRootCategory("My Addon")
SB.CreateSubcategory("General")

SB.Checkbox({
    get = function()
        return MyStore.enabled
    end,
    set = function(value)
        MyStore.enabled = value
    end,
    key = "enabled",
    default = true,
    name = "Enable",
})

SB.Input({
    get = function()
        return MyStore.searchText or ""
    end,
    set = function(value)
        MyStore.searchText = value
    end,
    key = "searchText",
    default = "",
    name = "Search",
})

SB.RegisterCategories()
```

## Good defaults for public addons

- Keep `varPrefix` short and unique.
- Point `getStore()` and `getDefaults()` at live tables.
- Keep `onChanged` fast; use it to refresh UI, not rebuild the world.
- Use composites for repeated patterns like borders, font overrides, and positioning.
- Prefer table-driven registration for large standard settings pages.
- Reach for `SB.Custom(...)` only when built-ins like `input` stop fitting.
