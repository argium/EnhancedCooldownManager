# Installation & Compatibility

## Documentation Index

- [README](../README.md) — overview and quick links
- [Quick Start](QUICK_START.md) — common setup patterns
- [API Reference](API_REFERENCE.md) — builder, controls, composites, page registration, canvas helpers
- [Migration Guide](MIGRATION_GUIDE.md) — moving from AceConfig/AceGUI
- [Troubleshooting](TROUBLESHOOTING.md) — common issues and fixes

## Requirements

- World of Warcraft retail with the Blizzard Settings API
- `LibStub`
- A saved-variable store of your choice
  - AceDB works well, but is optional

## Embed the library

Include the library in your addon's TOC or load-on-demand manifest.

```toc
Libs\LibStub\LibStub.lua
Libs\LibSettingsBuilder\embed.xml
```

Recommended pattern for addon authors:

1. Ship the library inside your addon's `Libs/` folder.
2. Load `LibStub` before `LibSettingsBuilder`.
3. Load `Libs\LibSettingsBuilder\embed.xml` so the library's internal source files keep their required order.
4. Treat the library as embedded, not as a standalone dependency players must install separately.

## Versioning notes

`LibSettingsBuilder` is distributed through `LibStub`, so the newest loaded minor version wins.

That means:

- multiple addons can safely embed the library,
- consumers should not hardcode internals,
- public behavior should be documented and stable across minor bumps.

## Runtime assumptions

The library integrates with Blizzard's Settings UI and installs a few global hooks to support:

- custom list rows,
- scrollable dropdowns,
- clickable slider value editing.

When you use `input` rows with `debounce` / `resolveText`, the library also uses callback handles and `C_Timer.NewTimer` to keep previews in sync.

Those hooks are part of the library's behavior and should be considered when debugging conflicts with heavily customized Settings UI code.

## Built-in controls vs custom templates

Most library features are available with no extra XML:

- proxy controls like `checkbox`, `slider`, `dropdown`, `color`, and `input`,
- layout rows like `header`, `subheader`, `info`, `button`, `pageActions`, and `canvas`,
- composite builders like `border`, `fontOverride`, and `heightOverride`.

`input` is a built-in row type implemented entirely in Lua on top of `SettingsListElementTemplate` plus a runtime-created `InputBoxTemplate` edit box.

Only `type = "custom"` rows require you to supply your own template. In that case:

1. define the template in XML,
2. load that XML from your TOC before calling `LSB.New({ ... })`, and
3. pass the template name through `spec.template`.

## Canvas layout compatibility

Canvas layout spacing defaults are still available for older `CreateCanvasLayout(...)` pages. New `canvas` rows stay on the current lifecycle path, so canvas content continues to reuse the existing frame handling without special-case rewrites.

- per-library via `LSBDeprecated.SetCanvasLayoutDefaults(overrides)`
- per-layout via `LSBDeprecated.ConfigureCanvasLayout(layout, overrides)`

See [API Reference](API_REFERENCE.md) for examples.
