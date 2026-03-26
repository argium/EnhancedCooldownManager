# LibConsole-1.0

Lightweight slash command registration library for World of Warcraft addons.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## Features

- Register and unregister slash commands at runtime.
- Case-insensitive command matching.
- Input validation on all public API calls.

## Quick start

```lua
local LibConsole = LibStub("LibConsole-1.0")

LibConsole:RegisterCommand("myaddon", function(input, editBox)
    print("You typed: " .. input)
end)
```

## Testing

Tests live in `Tests/` and use [busted](https://olivinelabs.com/busted/). Run from the **host addon root** (the directory containing `.busted`):

```sh
busted --run libconsole
```

## License

LibConsole is distributed under the terms of the GNU General Public License v3.0.
