-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

-- Defaults for Enhanced Cooldown Manager

---@class ECM_Color RGBA color definition.
---@field r number Red channel (0-1).
---@field g number Green channel (0-1).
---@field b number Blue channel (0-1).
---@field a number Alpha channel (0-1).
---@field textureId number|nil Texture file ID for icon display.

---@class ECM_BarConfigBase Shared bar layout configuration.
---@field enabled boolean Whether the bar is enabled.
---@field offsetX number|nil Horizontal offset when free anchor.
---@field offsetY number|nil Vertical offset when free anchor.
---@field width number|nil Bar width override.
---@field height number|nil Bar height override.
---@field texture string|nil Bar texture override.
---@field showText boolean|nil Whether to show text.
---@field bgColor ECM_Color|nil Background color override.
---@field anchorMode ECM.Constants.ANCHORMODE_CHAIN|ECM.Constants.ANCHORMODE_FREE|nil Anchor mode for the bar.

---@class ECM_PowerBarConfig : ECM_BarConfigBase Power bar configuration.
---@field showManaAsPercent boolean Whether to show mana as a percent.
---@field colors table<ECM_ResourceType, ECM_Color> Resource colors.
---@field border ECM_BorderConfig Border configuration.
---@field ticks ECM_PowerBarTicksConfig Tick mark configuration.

---@class ECM_ResourceBarConfig : ECM_BarConfigBase Resource bar configuration.
---@field demonHunterSoulsMax number Maximum Demon Hunter souls.
---@field colors table<ECM_ResourceType, ECM_Color> Resource colors.
---@field border ECM_BorderConfig Border configuration.

---@class ECM_RuneBarConfig : ECM_BarConfigBase Rune bar configuration.
---@field max number Maximum rune count.
---@field color ECM_Color Rune bar color.

---@alias ECM_ResourceType number|string Resource type identifier.

---@class ECM_GlobalConfig Global configuration.
---@field hideWhenMounted boolean Whether to hide when mounted or in a vehicle.
---@field hideOutOfCombatInRestAreas boolean Whether to hide out of combat in rest areas.
---@field updateFrequency number Update frequency in seconds.
---@field barHeight number Default bar height.
---@field barBgColor ECM_Color Default bar background color.
---@field offsetY number Global vertical offset.
---@field texture string|nil Default bar texture.
---@field font string Font face.
---@field fontSize number Font size.
---@field fontOutline "NONE"|"OUTLINE"|"THICKOUTLINE"|"MONOCHROME" Font outline style.
---@field fontShadow boolean Whether font shadow is enabled.
---@field outOfCombatFade ECM_CombatFadeConfig Out of combat fade configuration.

---@class ECM_BorderConfig Border configuration.
---@field enabled boolean Whether border is enabled.
---@field thickness number Border thickness in pixels.
---@field color ECM_Color Border color.

---@class ECM_BarCacheEntry Cached bar metadata.
---@field spellName string|nil Spell name.
---@field lastSeen number Last seen timestamp.

---@class ECM_SpellColorsConfig Spell color configuration.
---@field byName table<number, table<number, table<string, table>>> Per-name colors by class/spec/spellName.
---@field byTexture table<number, table<number, table<number, table>>> Per-texture colors by class/spec/textureId.
---@field cache table<number, table<number, table<number, ECM_BarCacheEntry>>> Cached bar metadata by class/spec/index.
---@field defaultColor ECM_Color Default color for buff bars.

---@class ECM_BuffBarsConfig Buff bars configuration.
---@field anchor ECM.Constants.ANCHORMODE_CHAIN|ECM.Constants.ANCHORMODE_FREE|nil Anchor behavior for buff bars.
---@field width number|nil Buff bar width when free anchor.
---@field offsetY number|nil Vertical offset when free anchor.
---@field showIcon boolean|nil Whether to show buff icons.
---@field showSpellName boolean|nil Whether to show spell names.
---@field showDuration boolean|nil Whether to show durations.
---@field colors ECM_SpellColorsConfig Per-spell color settings.

---@class ECM_ItemIconsConfig Item icons configuration.
---@field enabled boolean Whether item icons are enabled.
---@field showTrinket1 boolean Whether to show trinket slot 1 (if on-use).
---@field showTrinket2 boolean Whether to show trinket slot 2 (if on-use).
---@field showCombatPotion boolean Whether to show combat potions.
---@field showHealthPotion boolean Whether to show health potions.
---@field showHealthstone boolean Whether to show healthstone.

---@class ECM_TickMark Tick mark definition.
---@field value number Tick mark value.
---@field color ECM_Color Tick mark color.
---@field width number Tick mark width.

---@class ECM_PowerBarTicksConfig Power bar tick configuration.
---@field mappings table<number, table<number, ECM_TickMark[]>> Mappings by class/spec.
---@field defaultColor ECM_Color Default tick color.
---@field defaultWidth number Default tick width.

---@class ECM_CombatFadeConfig Combat fade configuration.
---@field enabled boolean Whether combat fade is enabled.
---@field opacity number Target opacity percent.
---@field exceptIfTargetCanBeAttacked boolean Skip fade if target is attackable.
---@field exceptInInstance boolean Skip fade in instances.

---@class ECM_Profile Profile settings.
---@field schemaVersion number Saved variables schema version.
---@field debug boolean Whether debug logging is enabled.
---@field global ECM_GlobalConfig Global appearance settings.
---@field powerBar ECM_PowerBarConfig Power bar settings.
---@field resourceBar ECM_ResourceBarConfig Resource bar settings.
---@field runeBar ECM_RuneBarConfig Rune bar settings.
---@field buffBars ECM_BuffBarsConfig Buff bars configuration.
---@field itemIcons ECM_ItemIconsConfig Item icons configuration.

-- Defines default tick marks for specific specialisations
local powerBarTickMappings = {}
powerBarTickMappings[ECM.Constants.DEMONHUNTER_CLASS_ID] = {
    [ECM.Constants.DEMONHUNTER_DEVOURER_SPEC_INDEX] = {
        { value = 90, color = { r = 2 / 3, g = 2 / 3, b = 2 / 3, a = 0.8 } },
        { value = 100 },
    },
}

local defaults = {
    profile = {
        debug = false,
        schemaVersion = ECM.Constants.CURRENT_SCHEMA_VERSION,
        global = {
            hideWhenMounted = true,
            hideOutOfCombatInRestAreas = false,
            updateFrequency = 0.04,
            barHeight = 22,
            barBgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.75 },
            offsetY = 4,
            texture = "Solid",
            font = "Expressway",
            fontSize = 11,
            fontOutline = "OUTLINE",
            fontShadow = false,
            outOfCombatFade = {
                enabled = false,
                opacity = 60,
                exceptIfTargetCanBeAttacked = true,
                exceptInInstance = true,
            },
        },
        powerBar = {
            enabled           = true,
            anchorMode        = ECM.Constants.ANCHORMODE_CHAIN,
            width             = 300,
            -- height            = nil,
            -- offsetX           = nil,
            offsetY           = -275,
            -- texture           = nil,
            -- bgColor           = nil,
            showText          = true,
            ticks             = {
                mappings = powerBarTickMappings, -- [classID][specID] = { { value = 50, color = {r,g,b,a}, width = 1 }, ... }
                defaultColor = ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR,
                defaultWidth = 1,
            },
            showManaAsPercent = true,
            border            = {
                enabled = false,
                thickness = ECM.Constants.DEFAULT_BORDER_THICKNESS,
                color = ECM.Constants.DEFAULT_BORDER_COLOR,
            },
            colors            = {
                [Enum.PowerType.Mana] = { r = 0.00, g = 0.00, b = 1.00, a = 1 },
                [Enum.PowerType.Rage] = { r = 1.00, g = 0.00, b = 0.00, a = 1 },
                [Enum.PowerType.Focus] = { r = 1.00, g = 0.57, b = 0.31, a = 1 },
                [Enum.PowerType.Energy] = { r = 0.85, g = 0.65, b = 0.13, a = 1 },
                [Enum.PowerType.RunicPower] = { r = 0.00, g = 0.82, b = 1.00, a = 1 },
                [Enum.PowerType.LunarPower] = { r = 0.30, g = 0.52, b = 0.90, a = 1 },
                [Enum.PowerType.Fury] = { r = 0.788, g = 0.259, b = 0.992, a = 1 },
            },
        },
        resourceBar = {
            enabled             = true,
            showText            = false,
            anchorMode          = ECM.Constants.ANCHORMODE_CHAIN,
            width               = 300,
            -- height              = nil,
            -- offsetX             = nil,
            offsetY             = -300,
            -- texture             = nil,
            -- bgColor             = nil,
            border              = {
                enabled = false,
                thickness = ECM.Constants.DEFAULT_BORDER_THICKNESS,
                color = ECM.Constants.DEFAULT_BORDER_COLOR,
            },
            colors              = {
                souls = { r = 0.259, g = 0.6, b = 0.91, a = 1 },
                devourerNormal = { r = 0.216, g = 0.153, b = 0.447, a = 1 },
                devourerMeta = { r = 0.275, g = 0.169, b = 1.0, a = 1 },
                [Enum.PowerType.ArcaneCharges] = { r = 102 / 255, g = 195 / 255, b = 250 / 255, a = 1 },
                [Enum.PowerType.Chi] = { r = 0.00, g = 1.00, b = 0.59, a = 1 },
                [Enum.PowerType.ComboPoints] = { r = 1.00, g = 0.96, b = 0.41, a = 1 },
                [Enum.PowerType.Essence] = { r = 0.20, g = 0.58, b = 0.50, a = 1 },
                [Enum.PowerType.HolyPower] = { r = 0.95, g = 0.90, b = 0.60, a = 1 },
                [Enum.PowerType.Maelstrom] = { r = 0.0, g = 0.439, b = 0.871, a = 1 },
                [Enum.PowerType.SoulShards] = { r = 0.50, g = 0.32, b = 0.55, a = 1 },
            },
        },
        runeBar = {
            enabled    = true,
            anchorMode = ECM.Constants.ANCHORMODE_CHAIN,
            width      = 300,
            -- height     = nil,
            -- offsetX    = nil,
            offsetY    = -325,
            -- texture    = nil,
            -- bgColor    = nil,
            color      = { r = 0.87, g = 0.10, b = 0.22, a = 1 }, -- DK class colour red
        },
        buffBars = {
            enabled = true,
            anchorMode = ECM.Constants.ANCHORMODE_CHAIN,
            width = 300,
            offsetY = -350,
            showIcon = false,
            showSpellName = true,
            showDuration = true,
            colors = {
                byName = {},
                bySpellID = {},
                byCooldownID = {},
                byTexture = {},
                cache = {},
                defaultColor = { r = 228 / 255, g = 233 / 255, b = 235 / 255, a = 1 },
            },
        },
        itemIcons = {
            enabled = true,
            showTrinket1 = true,
            showTrinket2 = true,
            showCombatPotion = true,
            showHealthPotion = true,
            showHealthstone = true,
        },
    },
}

-- Export defaults for Options module to access
ECM.defaults = defaults
