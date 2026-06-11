# LibSettingsBuilder-1.0

`LibSettingsBuilder` turns plain Lua tables into World of Warcraft Settings pages.

It exists so addons can describe settings once, bind rows to saved values, and avoid repeating Blizzard Settings API boilerplate for every checkbox, slider, dropdown, and section.

Load it through `Libs\LibSettingsBuilder\embed.xml` after `LibStub`.

## Direct Saved Variables

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

MyAddonDB = MyAddonDB or {
    enabled = true,
    scale = 75,
}

local defaults = {
    enabled = true,
    scale = 75,
}

LSB.New({
    name = "My Addon",
    store = MyAddonDB,
    defaults = defaults,
    defaultsConfirmation = {
        text = "Reset %s to defaults?",
        button1 = "Reset",
        button2 = "Don't reset",
    },
    onChanged = function()
        MyAddon:Refresh()
    end,
    page = {
        key = "main",
        rows = {
            {
                type = "checkbox",
                path = "enabled",
                name = "Enable",
            },
            {
                type = "slider",
                path = "scale",
                name = "Scale",
                min = 0,
                max = 100,
                step = 1,
            },
        },
    },
})
```

Pages with path-bound rows can use Blizzard's category **Defaults** button when `defaults` and `defaultsConfirmation` are configured. The confirmation `text` may include `%s`, which is replaced with the lowercase page name.

```lua
page = {
    key = "main",
    defaultsConfirmText = "Reset ALL settings on this page? This cannot be undone.",
    onDefaultEnabled = function()
        return MyAddon:CanResetMainPage()
    end,
    rows = {
        -- path-bound rows reset to values from defaults
    },
}
```

Page definitions may also provide `onDefault` for custom reset logic, or `hideDefaults = true` to hide the category Defaults button on pages where reset behavior does not apply.

## AceDB Profile

```lua
local LSB = LibStub("LibSettingsBuilder-1.0")

local defaults = {
    profile = {
        enabled = true,
        scale = 75,
    },
}

MyAddon.db = LibStub("AceDB-3.0"):New("MyAddonDB", defaults, true)

LSB.New({
    name = "My Addon",
    store = function()
        return MyAddon.db.profile
    end,
    defaults = defaults.profile,
    defaultsConfirmation = {
        text = "Reset %s to defaults?",
        button1 = "Reset",
        button2 = "Don't reset",
    },
    onChanged = function()
        MyAddon:Refresh()
    end,
    page = {
        key = "main",
        rows = {
            {
                type = "checkbox",
                path = "enabled",
                name = "Enable",
            },
            {
                type = "slider",
                path = "scale",
                name = "Scale",
                min = 0,
                max = 100,
                step = 1,
            },
        },
    },
})
```

## License

LibSettingsBuilder is distributed under the terms of the GNU General Public License v3.0.
