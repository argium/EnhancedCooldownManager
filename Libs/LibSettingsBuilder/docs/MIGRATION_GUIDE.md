# Migration Guide

## Documentation Index

- [README](../README.md)
- [Quick Start](QUICK_START.md)
- [API Reference](API_REFERENCE.md)
- [Installation & Compatibility](INSTALLATION.md)
- [Troubleshooting](TROUBLESHOOTING.md)

## Moving from AceConfig / AceGUI

`LibSettingsBuilder` keeps your storage model and changes your UI wiring.

### What stays the same

- Your AceDB profile structure
- Your defaults table
- Profile switching behavior
- The need to refresh your addon when settings change

### What changes

| AceConfig stack | LibSettingsBuilder |
|---|---|
| `RegisterOptionsTable` | `SB.RegisterFromTable` |
| `AddToBlizOptions` | `SB.RegisterCategories()` |
| one `get`/`set` per field | one `path` per field in path mode |
| custom refresh dance | reactive modifiers re-evaluate automatically |

## Path mode replaces repeated getters and setters

```lua
local SB = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore = function()
            return db.profile
        end,
        getDefaults = function()
            return db.defaults.profile
        end,
    }),
    varPrefix = "MYADDON",
    onChanged = function()
        MyAddon:Refresh()
    end,
})
```

## Useful aliases

`RegisterFromTable` accepts several AceConfig-style aliases:

- `toggle` → `checkbox`
- `range` → `slider`
- `select` → `dropdown`
- `execute` → `button`
- `description` → `subheader`
- `desc` → `tooltip`

## Features you gain

- native Blizzard Settings integration,
- composite builders for common UI groups,
- canvas layout helpers for complex pages,
- clickable slider value editing,
- deterministic dropdown ordering.

## Features you still build yourself

- custom input widgets,
- specialized row templates,
- bespoke canvas pages.

Use `SB.Custom(...)` or `CreateCanvasLayout(...)` when the standard controls stop fitting.
