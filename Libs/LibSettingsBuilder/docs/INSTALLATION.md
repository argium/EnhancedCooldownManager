# Installation & Compatibility

## Documentation Index

- [README](../README.md) — overview and quick links
- [Quick Start](QUICK_START.md) — common setup patterns
- [API Reference](API_REFERENCE.md) — builder, controls, composites, canvas helpers
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
Libs\LibSettingsBuilder\LibSettingsBuilder.lua
```

Recommended pattern for addon authors:

1. Ship the library inside your addon's `Libs/` folder.
2. Load `LibStub` before `LibSettingsBuilder`.
3. Treat the library as embedded, not as a standalone dependency players must install separately.

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

Those hooks are part of the library's behavior and should be considered when debugging conflicts with heavily customized Settings UI code.

## Canvas layout compatibility

Canvas layout spacing defaults are modeled after Blizzard's retail Settings panel measurements and can be adjusted when needed:

- per-library via `SB.SetCanvasLayoutDefaults(overrides)`
- per-layout via `SB.ConfigureCanvasLayout(layout, overrides)`

See [API Reference](API_REFERENCE.md) for examples.
