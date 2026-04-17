# Troubleshooting

## Documentation Index

- [README](../README.md)
- [Quick Start](QUICK_START.md)
- [API Reference](API_REFERENCE.md)
- [Installation & Compatibility](INSTALLATION.md)
- [Migration Guide](MIGRATION_GUIDE.md)

## Controls do not save values

Check the path binding config first.

- `store` must point at the live writable table.
- `defaults` should point at the matching defaults table.
- In handler mode, verify both `get` and `set` are present.

## Path mode errors immediately

Common causes:

- you created `LSB.New({ ... })` with `page` or `sections` but no `name`,
- you created the builder without `store` / `defaults`,
- a spec mixes `path` with `get` / `set`,
- handler mode is missing `key` or `id`.

## Registration fails with deprecated or removed field errors

Common fixes:

- rename `desc` to `tooltip`,
- replace removed fields like `condition`, `parent`, and `parentCheck` with `disabled` / `hidden`,
- use `pageActions` for page-header buttons instead of attaching actions to a `header` row.

## Settings page exists but nothing appears in-game

Usually one of these:

- you created `LSB.New({ name = "My Addon", ... })` without a `page` or `sections` tree,
- your registered root page or section page ended up with no visible rows,
- a `hidden` predicate is always returning `true`,
- a `custom` template was never loaded from XML.

## A child control is always disabled or hidden

Check modifier predicates:

- `disabled = function() ... end`
- `hidden = function() ... end`

Remember these are reactive and will be re-evaluated after setting changes.

## Input preview does not refresh

Check these pieces:

- `resolveText(...)` must return a string or `nil`,
- `debounce` delays preview updates intentionally,

If you just need raw text entry with no secondary preview, omit `resolveText` entirely.

## Dropdown options look wrong

`values` can be a table or a function returning a table.

Recommendations:

- keep labels unique where possible,
- make sure returned values are stable,
- if the list is large, use `scrollHeight` for a scrollable dropdown.

Dropdown entries are ordered deterministically by label, then by value, to avoid random menu ordering between sessions.

## Custom template control never initializes

Built-in rows like `checkbox`, `slider`, `dropdown`, `color`, and `input` do not need extra XML.

`custom` controls do.

If a custom control appears blank or never receives its initializer data:

- verify the XML file defining the template is loaded from your TOC,
- verify the template name passed in `spec.template` matches the XML definition,
- verify the template inherits the correct Blizzard settings row template for your widget,
- verify no addon is replacing the Settings initialization pipeline.

## Slider value editing does not behave as expected

The library adds inline numeric editing to slider value labels.

If debugging slider behavior:

- verify the control is using Blizzard's standard slider template path,
- confirm no other addon is replacing the slider frame structure,
- test with other UI customizers disabled.

## Embedded canvas rows look off

`type = "canvas"` embeds the frame you provide. If spacing or clipping looks wrong:

- give the row an explicit `height`, or make sure the frame reports a stable height,
- prefer built-in rows, `list`, or `sectionList` when you want Blizzard-style settings layout instead of a bespoke frame,
- use `type = "custom"` for XML-backed row widgets rather than a full embedded canvas when you only need one custom control.

## Debugging spec mistakes

Set `LSB_DEBUG = true` during development to warn about unknown spec fields.

This helps catch typos like:

- `paht`
- `tooltipp`
- `valeus`
