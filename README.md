# Enhanced Cooldown Manager by Argium

Enhanced Cooldown Manager creates a clean combat HUD around Blizzard's built-in cooldown manager that **looks and works great out of the box** and is **straightforward to customise.**

Made with ❤️, with little features you didn't know you needed and won't want to live without.

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

## Module support by class

Legend: 🟢 supported

| Class | Power Bar | Resource Bar |
| --- | --- | --- |
| <span style="color:#C41E3A;">Death Knight</span> | 🟢 | 🟢 Runes |
| <span style="color:#A330C9;">Demon Hunter</span> | 🟢 | 🟢 Vengeance (Soul Fragments) <br>🟢 Devourer (Void Fragments) |
| <span style="color:#FF7C0A;">Druid</span> | 🟢 Balance/Restoration (Mana) <br>🟢 Feral (Energy) <br>🟢 Guardian (Rage) | 🟢 Feral (Combo Points) |
| <span style="color:#33937F;">Evoker</span> | 🟢 Preservation (Mana) | 🟢 Essence |
| <span style="color:#AAD372;">Hunter</span> | 🟢 | |
| <span style="color:#3FC7EB;">Mage</span> | 🟢 | 🟢 Arcane (Charges), Frost (Icicles) |
| <span style="color:#00FF98;">Monk</span> | 🟢 Mistweaver (Mana) <br>🟢 Brewmaster (Energy)<br>🟢 Windwalker (Energy) | 🟢 Windwalker (Chi) |
| <span style="color:#F48CBA;">Paladin</span> | 🟢 Holy (Mana) | 🟢 Holy Power|
| <span style="color:#FFFFFF;">Priest</span> | 🟢 | |
| <span style="color:#FFF468;">Rogue</span> | 🟢 | 🟢 Combo points|
| <span style="color:#0070DD;">Shaman</span> | 🟢 | 🟢 Enhancement (Maelstrom Weap.) |
| <span style="color:#8788EE;">Warlock</span> | 🟢 | 🟢 Soul shards |
| <span style="color:#C69B6D;">Warrior</span> | 🟢 | |

## Troubleshooting

If you run into a problem, enable debug tracing with the command `/ecm debug on` and reload your UI. Include any output when reporting an issue.

## License

[GPL-3.0](LICENSE)
