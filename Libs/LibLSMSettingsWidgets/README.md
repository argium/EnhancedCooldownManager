# LibLSMSettingsWidgets-1.0

LibSharedMedia picker widgets for the WoW Settings API. Provides font and texture picker templates with live previews.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## Features

- Drop-in font and texture picker templates for `Settings.CreateControlTextContainer`.
- Live preview of the selected font or texture in the dropdown.
- Cached and sorted media name lists, auto-invalidated when new media is registered.
- Graceful fallback when media fetch fails.

## Quick start

```lua
local LSW = LibStub("LibLSMSettingsWidgets-1.0")

-- Use the template name when creating a Settings dropdown:
-- LSW.FONT_PICKER_TEMPLATE
-- LSW.TEXTURE_PICKER_TEMPLATE
```

## Testing

Tests live in `Tests/` and use [busted](https://olivinelabs.com/busted/). Run from the **host addon root** (the directory containing `.busted`):

```sh
busted --run liblsmsettingswidgets
```

## License

LibLSMSettingsWidgets is distributed under the terms of the GNU General Public License v3.0.
