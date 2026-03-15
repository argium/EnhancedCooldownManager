# Troubleshooting

## Documentation Index

- [README](../README.md)
- [Quick Start](QUICK_START.md)
- [API Reference](API_REFERENCE.md)
- [Installation & Compatibility](INSTALLATION.md)
- [Migration Guide](MIGRATION_GUIDE.md)

## Controls do not save values

Check the `PathAdapter` first.

- `getStore()` must return the live writable table.
- `getDefaults()` should return the matching defaults table.
- In handler mode, verify both `get` and `set` are present.

## Path mode errors immediately

Common causes:

- you created the builder without `pathAdapter`,
- a spec mixes `path` with `get` / `set`,
- handler mode is missing `key`.

## Settings page exists but nothing appears in-game

Usually one of these:

- you forgot `SB.RegisterCategories()`,
- you created a subcategory but never added controls to it,
- a `hidden` predicate is always returning `true`.

## A child control is always disabled or hidden

Check modifier predicates:

- `disabled = function() ... end`
- `hidden = function() ... end`
- `parent` + `parentCheck`

Remember these are reactive and will be re-evaluated after setting changes.

## Dropdown options look wrong

`values` can be a table or a function returning a table.

Recommendations:

- keep labels unique where possible,
- make sure returned values are stable,
- if the list is large, use `scrollHeight` for a scrollable dropdown.

Dropdown entries are ordered deterministically by label, then by value, to avoid random menu ordering between sessions.

## Slider value editing does not behave as expected

The library adds inline numeric editing to slider value labels.

If debugging slider behavior:

- verify the control is using Blizzard's standard slider template path,
- confirm no other addon is replacing the slider frame structure,
- test with other UI customizers disabled.

## Canvas pages look slightly off after a WoW patch

Canvas layout spacing is configurable.

Use:

```lua
SB.SetCanvasLayoutDefaults({ elementHeight = 28 })
```

or per layout:

```lua
local layout = SB.CreateCanvasLayout("My Page")
SB.ConfigureCanvasLayout(layout, { labelX = 40 })
```

If Blizzard adjusts Settings panel spacing in a major patch, this is the intended escape hatch.

## Debugging spec mistakes

Set `LSB_DEBUG = true` during development to warn about unknown spec fields.

This helps catch typos like:

- `paht`
- `tooltipp`
- `valeus`
