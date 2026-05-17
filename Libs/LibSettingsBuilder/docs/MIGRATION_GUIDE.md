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
| `RegisterOptionsTable` | export declarative root/page/section specs |
| `AddToBlizOptions` | `LSB.New({ name = "My Addon", page = ..., sections = ... })` |
| one `get`/`set` per field | one `path` per field in path mode |
| `type = "input"` | `type = "input"` |
| custom refresh dance | reactive modifiers re-evaluate automatically |

## Path mode replaces repeated getters and setters

```lua
local lsb = LSB.New({
    name = "My Addon",
    store = db.profile,
    defaults = db.defaults.profile,
    onChanged = function()
        MyAddon:Refresh()
    end,
})
```

## Field name updates

When moving old option tables over:

- use `tooltip`, not AceConfig's `desc`,
- replace removed fields like `condition`, `parent`, and `parentCheck` with `disabled` / `hidden` predicates on rows or pages,
- prefer the current field names `formatter`, `scrollHeight`, and `debounce` even though the declarative loader still normalizes a few older aliases for compatibility.

## Canonical row types

Declarative pages use canonical row types only:

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

## Features you gain

- native Blizzard Settings integration,
- composite builders for common UI groups,
- first-class dynamic list rows for complex editors,
- built-in text input rows with optional debounced previews,
- page-owned refresh hooks for async/transient state,
- clickable slider value editing,
- deterministic dropdown ordering.

## Features you still build yourself

- specialized row templates,
- genuinely bespoke embedded frames.

If you only need text or numeric entry, use the built-in `input` type first. Reach for `type = "custom"` only when you need a genuinely different widget.

If you need an ordered list, grouped editor, or add/remove workflow, prefer `type = "list"` or `type = "sectionList"` before reaching for `type = "custom"` or `type = "canvas"`.

## Migrating AceConfig input fields

Simple AceConfig `input` fields usually map directly:

```lua
search = {
    type = "input",
    path = "searchText",
    name = "Search",
    order = 10,
}
```

If your old AceConfig input also computed helper text or validity hints, move that into `resolveText(...)` and optionally add `debounce` to avoid recomputing on every keystroke.
