# Enhanced Cooldown Manager ⚔️

> Customizable resource bars anchored to Blizzard's Cooldown Manager viewers for World of Warcraft.

Looks and works great out of the box with a UX-oriented design. Enhance your gameplay visibility with sleek, customizable resource tracking.

## ✨ Key Features

### 📊 Resource Tracking
- **Power Bar** — Primary resources (mana, rage, energy, focus, runic power, lunar power) with optional text overlay and customizable tick marks
- **Resource Bar** — Special resources like combo points, chi, holy power, soul shards, and essence
- **Rune Bar** — Death Knight specific bar showing individual rune recharge progress independently
- **Buff Bars** — Enhanced display alongside cooldowns including trinkets, health/combat potions, and healthstones

### 🎨 Customization
- **Custom Styling** — Choose from multiple color palettes (Rainbow, Warm, Cool, Pastel, Muted) or set custom colors per buff bar
- **Texture Options** — Full LibSharedMedia-3.0 support for statusbar textures
- **Font Control** — Customizable fonts, sizes, and outlines
- **Borders** — Optional borders with adjustable thickness and color

### 🔧 Flexible Positioning
Two movement modes for ultimate control:
- **Chain Mode** — Bars automatically position under the Cooldown Manager in a neat stack
- **Independent Mode** — Detach and move bar modules independently for custom layouts

### 👁️ Smart Visibility
- **Mount & Vehicle Hide** — Automatically hide bars when mounted or in a vehicle
- **Rest Area Hide** — Option to hide bars when out of combat in rest areas
- **Combat Fade** — Fade bars out of combat for less screen clutter
  - Except in instances (dungeons/raids)
  - Except when target can be attacked

## 🆕 What's New

### Architecture Improvements (v0.5.0-beta4)
The latest refactor introduces a clean, modular architecture with reusable mixins:

- **BarFrame Mixin** — Unified frame creation, layout, and appearance handling for all bar modules
- **ModuleLifecycle Mixin** — Consistent enable/disable, event registration, and throttled refresh patterns
- **TickRenderer Mixin** — Efficient tick pooling and positioning for resource segmentation
- **Consolidated Anchoring** — Streamlined logic for both chain and independent positioning modes

These improvements make the addon more maintainable and performant while preserving all existing functionality.

## 📦 Installation

1. Download the latest release
2. Extract to `World of Warcraft/_retail_/Interface/AddOns/`
3. Reload UI (`/reload`) or restart WoW

## ⚙️ Configuration

Type `/ecm` in-game to open the options panel and customize:
- Enable/disable individual bars
- Choose positioning modes
- Adjust colors, textures, and fonts
- Configure visibility rules
- Set up tick marks for specific class/spec combinations

## 🎮 Supported Resources

- **Mana, Rage, Energy, Focus, Runic Power, Lunar Power** (Power Bar)
- **Combo Points, Chi, Holy Power, Soul Shards, Essence** (Resource Bar)
- **Demon Hunter Souls** with independent refresh tracking (Resource Bar)
- **Death Knight Runes** with independent recharge progress (Rune Bar)

---

👤 **Author:** Solär  
📄 **License:** [GPL-3.0](LICENSE)  
🔗 **Repository:** [github.com/argium/EnhancedCooldownManager](https://github.com/argium/EnhancedCooldownManager)
