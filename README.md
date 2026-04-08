# Enhanced Cooldown Manager by Argium

Enhanced Cooldown Manager creates a clean combat HUD around Blizzard's built-in cooldown manager that **looks and works great out of the box** and is **straightforward to customise.** It adds a mana/power bar and resource bar, extra icons for potions, and supports per-spell color and customisation for aura bars. Modular design allow each part to be attached to the CDM or detached and freely placed.

Made with ❤️, with little features you won't want to live without.

##  Features

### ⚔️ Inline Resources

Adds essential combat bars directly below Blizzard's cooldown manager.

- `Power Bar` for mana, rage, energy, focus, and runic power
- `Resource Bar` for class resources
- `Rune Bar` for Death Knight rune tracking
- `Aura Bars` with unified style and color control

![](docs/images/inline-resources.gif)

### 🎨 Aura Bars

Automatically position aura bars and style them to match. Change their colors for different spells so you can see their remaining duration at a glance.

![](docs/images/aura-bars.gif)

### 🙈 Smart Visibility and Fade Rules

Reduce screen clutter automatically based on gameplay context:

- Hide while mounted or in a vehicle
- Hide in rest areas
- Fade when out of combat
- Optionally stay visible in instances (raids, M+, PVP)
- Optionally stay visible when you have an attackable target

![](docs/images/fade.gif)

### 🟥 Death Knight Runes

Track each rune independently as it recharges inline with other resources and cooldowns.

![](docs/images/dk-runes.gif)

### 🧪 Add Icons for Trinkets, Potions, and Healthstones

Extend the utility cooldown bar with essential combat icons to save you a glance at the action bar.

- Equipped trinket cooldowns
- Health potion cooldown
- Combat potion cooldown
- Healthstone cooldown

### 📌 Automatic positioning or free movement

Use the layout mode that fits your setup.

- Auto-position directly under Blizzard's Cooldown Manager
- Detach modules and move them independently
- Mix and match layouts depending on preference

## Installation

1. Download and extract this addon into `World of Warcraft/_retail_/Interface/AddOns`.
2. Reload your UI or restart the game.

## Configuration

- Use `/ecm` in game to open options.
- You can also open it from the AddOn compartment menu near the minimap.

## License

[GPL-3.0](LICENSE)
