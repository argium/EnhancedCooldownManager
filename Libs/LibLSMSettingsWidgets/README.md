# LibLSMSettingsWidgets-1.0

LibSharedMedia picker widgets for LibSettingsBuilder. Provides pure-Lua `font` and `texture` declarative row types with live previews.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## Features

- Drop-in `type = "font"` and `type = "texture"` rows for LibSettingsBuilder declaratives.
- Live preview of the selected font or texture in the dropdown.
- Cached and sorted media name lists, auto-invalidated when new media is registered.
- Graceful fallback when media fetch fails.

## Quick start

```lua
local LSW = LibStub("LibLSMSettingsWidgets-1.0")
LSW.Register(LibStub("LibSettingsBuilder-1.0"))

rows = {
	{ type = "font", path = "font", name = "Font" },
	{ type = "texture", path = "texture", name = "Texture" },
}
```

When loaded after LibSettingsBuilder, the library registers these row types automatically. Calling `Register` is safe and idempotent for explicit setup.

## Testing

Tests live in `Tests/` and use [busted](https://olivinelabs.com/busted/). Run from the **host addon root** (the directory containing `.busted`):

```sh
busted --run liblsmsettingswidgets
```

## License

LibLSMSettingsWidgets is distributed under the terms of the GNU General Public License v3.0.
