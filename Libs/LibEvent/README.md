# LibEvent-1.0

Embeddable WoW event system for addon modules. Wraps the frame-based event API behind a clean `RegisterEvent` / `UnregisterEvent` / `Fire` interface that can be mixed into any table.

Distributed via [LibStub](https://www.wowace.com/projects/libstub).

## Features

- Embed into any table to give it event registration capabilities.
- Zero-allocation dispatch loop — no snapshot copies per fire.
- Idempotent embedding — safe to re-embed on library upgrades.
- Per-event callback stats via `GetEventStats` / `ResetEventStats`.

## Quick start

```lua
local LibEvent = LibStub("LibEvent-1.0")

local myModule = {}
LibEvent:Embed(myModule)

myModule:RegisterEvent("PLAYER_LOGIN", function(self, event)
    print("Logged in!")
end)
```

## API

| Method | Description |
|---|---|
| `Embed(target)` | Mixes event methods into `target`. |
| `RegisterEvent(event, callback)` | Register a function callback for a WoW event. |
| `UnregisterEvent(event, callback)` | Remove a specific callback. |
| `UnregisterAllEvents()` | Remove all callbacks and unregister the hidden frame. |
| `Fire(event, ...)` | Manually fire an event on the target. |
| `GetEventStats()` | Returns a table of event → fire-count. |
| `ResetEventStats()` | Clears all accumulated stats. |

## Testing

Tests live in `Tests/` and use [busted](https://olivinelabs.com/busted/). Run from the **host addon root** (the directory containing `.busted`):

```sh
busted --run libevent
```

## License

LibEvent is distributed under the terms of the GNU General Public License v3.0.
