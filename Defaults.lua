-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

---@class ECM_Color RGBA color definition.
---@field r number Red channel (0-1).
---@field g number Green channel (0-1).
---@field b number Blue channel (0-1).
---@field a number Alpha channel (0-1).

---@class ECM_EditModePosition Saved position for one Edit Mode layout.
---@field point string Anchor point (e.g. "CENTER", "TOPLEFT").
---@field x number X offset from anchor.
---@field y number Y offset from anchor.

---@alias ns.Constants.ANCHORMODE_CHAIN "chain"
---@alias ns.Constants.ANCHORMODE_DETACHED "detached"
---@alias ns.Constants.ANCHORMODE_FREE "free"

---@class ECM_BarConfigBase Shared bar layout configuration.
---@field enabled boolean Whether the bar is enabled.
---@field editModePositions table<string, ECM_EditModePosition>|nil Per-layout positions saved via Edit Mode.
---@field width number|nil Bar width override.
---@field height number|nil Bar height override.
---@field texture string|nil Bar texture override.
---@field overrideFont boolean|nil Whether this bar overrides global font settings.
---@field font string|nil Font face override for bar text.
---@field fontSize number|nil Font size override for bar text.
---@field showText boolean|nil Whether to show text.
---@field bgColor ECM_Color|nil Background color override.
---@field anchorMode ns.Constants.ANCHORMODE_CHAIN|ns.Constants.ANCHORMODE_DETACHED|ns.Constants.ANCHORMODE_FREE|nil Anchor mode for the bar.

---@class ECM_PowerBarConfig : ECM_BarConfigBase Power bar configuration.
---@field showManaAsPercent boolean Whether to show mana as a percent.
---@field colors table<ECM_ResourceType, ECM_Color> Resource colors.
---@field border ECM_BorderConfig Border configuration.
---@field ticks ECM_PowerBarTicksConfig Tick mark configuration.

---@class ECM_ResourceBarConfig : ECM_BarConfigBase Resource bar configuration.
---@field colors table<ECM_ResourceType, ECM_Color> Resource colors.
---@field maxColors table<ECM_ResourceType, ECM_Color> Colors used when a resource is at its maximum value.
---@field maxColorsEnabled table<ECM_ResourceType, boolean> Whether the max-value color override is enabled per type.
---@field border ECM_BorderConfig Border configuration.

---@class ECM_RuneBarConfig : ECM_BarConfigBase Rune bar configuration.
---@field useSpecColor boolean Whether to use class/spec colors instead of custom color.
---@field color ECM_Color Rune bar color.
---@field colorBlood ECM_Color Blood rune color.
---@field colorFrost ECM_Color Frost rune color.
---@field colorUnholy ECM_Color Unholy rune color.

---@alias ECM_ResourceType number|string Resource type identifier.

---@class ECM_GlobalConfig Global configuration.
---@field debug boolean Whether debug logging is enabled.
---@field hideWhenMounted boolean Whether to hide when mounted or in a vehicle.
---@field hideOutOfCombatInRestAreas boolean Whether to hide out of combat in rest areas.
---@field updateFrequency number Update frequency in seconds.
---@field barHeight number Default bar height.
---@field barBgColor ECM_Color Default bar background color.
---@field offsetY number Global vertical offset.
---@field moduleSpacing number Vertical gap between chained modules.
---@field moduleGrowDirection "down"|"up"|nil Vertical grow direction for chained modules.
---@field texture string|nil Default bar texture.
---@field font string Font face.
---@field fontSize number Font size.
---@field fontOutline "NONE"|"OUTLINE"|"THICKOUTLINE"|"MONOCHROME" Font outline style.
---@field fontShadow boolean Whether font shadow is enabled.
---@field outOfCombatFade ECM_CombatFadeConfig Out of combat fade configuration.
---@field detachedAnchorPositions table<string, ECM_EditModePosition>|nil Per-layout positions for the detached anchor frame.
---@field detachedBarWidth number|nil Shared width for all detached bars.
---@field detachedModuleSpacing number|nil Vertical gap between detached modules.
---@field detachedGrowDirection "down"|"up"|nil Vertical grow direction for detached modules.

---@class ECM_BorderConfig Border configuration.
---@field enabled boolean Whether border is enabled.
---@field thickness number Border thickness in pixels.
---@field color ECM_Color Border color.

---@class ECM_BarCacheEntry Cached bar metadata.
---@field spellName string|nil Spell name.
---@field lastSeen number Last seen timestamp.

---@class ECM_SpellColorsConfig Spell color configuration.
---@field byName table<number, table<number, table<string, table>>> Per-name colors by class/spec/spellName.
---@field bySpellID table<number, table<number, table<number, table>>> Per-spellID colors by class/spec/spellID.
---@field byCooldownID table<number, table<number, table<number, table>>> Per-cooldownID colors by class/spec/cooldownID.
---@field byTexture table<number, table<number, table<number, table>>> Per-texture colors by class/spec/textureId.
---@field cache table<number, table<number, table<number, ECM_BarCacheEntry>>> Cached bar metadata by class/spec/index.
---@field defaultColor ECM_Color Default color when no per-spell override applies.

---@class ECM_BuffBarsConfig Buff bars configuration.
---@field enabled boolean Whether buff bars are enabled.
---@field anchorMode ns.Constants.ANCHORMODE_CHAIN|ns.Constants.ANCHORMODE_DETACHED|ns.Constants.ANCHORMODE_FREE|nil Anchor behavior for buff bars.
---@field verticalSpacing number|nil Vertical gap between buff bars (pixels).
---@field showIcon boolean|nil Whether to show buff icons.
---@field showSpellName boolean|nil Whether to show spell names.
---@field showDuration boolean|nil Whether to show durations.
---@field overrideFont boolean|nil Whether aura bars override global font settings.
---@field font string|nil Font face override for aura bar text.
---@field fontSize number|nil Font size override for aura bar text.
---@field colors ECM_SpellColorsConfig Per-spell color settings.

---@class ECM_ExternalBarsConfig External cooldown bars configuration.
---@field enabled boolean Whether external cooldown bars are enabled.
---@field hideOriginalIcons boolean Whether Blizzard's original external cooldown icons are hidden.
---@field anchorMode ns.Constants.ANCHORMODE_CHAIN|ns.Constants.ANCHORMODE_DETACHED|ns.Constants.ANCHORMODE_FREE|nil Anchor behavior for external cooldown bars.
---@field editModePositions table<string, ECM_EditModePosition>|nil Per-layout positions saved via Edit Mode.
---@field width number|nil Bar width override.
---@field height number|nil Bar height override.
---@field verticalSpacing number|nil Vertical gap between bars (pixels).
---@field showIcon boolean|nil Whether to show external cooldown icons.
---@field showSpellName boolean|nil Whether to show spell names.
---@field showDuration boolean|nil Whether to show durations.
---@field overrideFont boolean|nil Whether external cooldown bars override global font settings.
---@field font string|nil Font face override for bar text.
---@field fontSize number|nil Font size override for bar text.
---@field colors ECM_SpellColorsConfig Per-spell color settings.

---@class ECM_ExtraIconEntry
---@field stackKey string|nil Built-in stack key resolved via `BUILTIN_STACKS`.
---@field kind string|nil Entry kind for custom or racial rows.
---@field ids table|nil Entry spell/item priority list.
---@field slotId number|nil Slot ID for equip-slot entries.
---@field disabled boolean|nil When true, the entry stays in settings but is skipped at runtime.

---@class ECM_ExtraIconsConfig Extra icons configuration.
---@field enabled boolean Whether extra icons are enabled.
---@field showStackCount boolean Whether to show item stack counts.
---@field showCharges boolean Whether to show spell charges.
---@field viewers table<string, ECM_ExtraIconEntry[]> Per-viewer ordered icon lists.

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
---@field exceptIfTargetCanBeHelped boolean Skip fade if target is assistable.
---@field exceptInInstance boolean Skip fade in instances.

---@class ECM_Profile Profile settings.
---@field schemaVersion number Saved variables schema version.
---@field global ECM_GlobalConfig Global appearance settings.
---@field powerBar ECM_PowerBarConfig Power bar settings.
---@field resourceBar ECM_ResourceBarConfig Resource bar settings.
---@field runeBar ECM_RuneBarConfig Rune bar settings.
---@field buffBars ECM_BuffBarsConfig Buff bars configuration.
---@field externalBars ECM_ExternalBarsConfig External cooldown bars configuration.
---@field extraIcons ECM_ExtraIconsConfig Extra icons configuration.

local C = ns.Constants

-- Defines default tick marks for specific specialisations
local powerBarTickMappings = {}
powerBarTickMappings[C.DEMONHUNTER_CLASS_ID] = {
    [C.DEMONHUNTER_DEVOURER_SPEC_INDEX] = {
        { value = 90, color = { r = 2 / 3, g = 2 / 3, b = 2 / 3, a = 0.8 } },
        { value = 100 },
    },
}

local defaults = {
    profile = {
        schemaVersion = C.CURRENT_SCHEMA_VERSION,
        global = {
            debug = false,
            debugToChat = false,
            releasePopupSeenVersion = "",
            hideWhenMounted = true,
            hideOutOfCombatInRestAreas = false,
            updateFrequency = 0.04,
            barHeight = 22,
            barBgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.75 },
            offsetY = 4,
            moduleSpacing = 0,
            moduleGrowDirection = C.GROW_DIRECTION_DOWN,
            texture = "Solid",
            font = "Expressway",
            fontSize = 11,
            fontOutline = "OUTLINE",
            fontShadow = false,
            outOfCombatFade = {
                enabled = false,
                opacity = 60,
                exceptIfTargetCanBeAttacked = true,
                exceptIfTargetCanBeHelped = false,
                exceptInInstance = true,
            },
            detachedAnchorPositions = {},
            detachedBarWidth = 300,
            detachedModuleSpacing = 0,
            detachedGrowDirection = C.GROW_DIRECTION_DOWN,
        },
        powerBar = {
            enabled = true,
            anchorMode = C.ANCHORMODE_CHAIN,
            width = 300,
            editModePositions = {},
            showText = true,
            overrideFont = false,
            ticks = {
                mappings = powerBarTickMappings, -- [classID][specID] = { { value = 50, color = {r,g,b,a}, width = 1 }, ... }
                defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
                defaultWidth = 1,
            },
            showManaAsPercent = true,
            border = {
                enabled = false,
                thickness = C.DEFAULT_BORDER_THICKNESS,
                color = C.DEFAULT_BORDER_COLOR,
            },
            colors = {
                [Enum.PowerType.Mana] = { r = 0.00, g = 0.00, b = 1.00, a = 1 },
                [Enum.PowerType.Rage] = { r = 1.00, g = 0.00, b = 0.00, a = 1 },
                [Enum.PowerType.Focus] = { r = 1.00, g = 0.57, b = 0.31, a = 1 },
                [Enum.PowerType.Energy] = { r = 0.85, g = 0.65, b = 0.13, a = 1 },
                [Enum.PowerType.RunicPower] = { r = 0.00, g = 0.82, b = 1.00, a = 1 },
                [Enum.PowerType.LunarPower] = { r = 0.30, g = 0.52, b = 0.90, a = 1 },
                [Enum.PowerType.Maelstrom] = { r = 0.00, g = 0.439, b = 0.871, a = 1 },
                [Enum.PowerType.Insanity] = { r = 0.40, g = 0.00, b = 0.80, a = 1 },
                [Enum.PowerType.Fury] = { r = 0.788, g = 0.259, b = 0.992, a = 1 },
            },
        },
        resourceBar = {
            enabled = true,
            showText = false,
            overrideFont = false,
            anchorMode = C.ANCHORMODE_CHAIN,
            width = 300,
            editModePositions = {},
            border = {
                enabled = false,
                thickness = C.DEFAULT_BORDER_THICKNESS,
                color = C.DEFAULT_BORDER_COLOR,
            },
            colors = {
                [C.RESOURCEBAR_TYPE_VENGEANCE_SOULS] = { r = 0.259, g = 0.6, b = 0.91, a = 1 },
                [C.RESOURCEBAR_TYPE_DEVOURER_NORMAL] = { r = 0.416, g = 0.435, b = 0.910, a = 1 },
                [C.RESOURCEBAR_TYPE_DEVOURER_META] = { r = 0.494, g = 0.549, b = 1.000, a = 1 },
                [C.RESOURCEBAR_TYPE_ICICLES] = { r = 0.72, g = 0.9, b = 1.0, a = 1 },
                [Enum.PowerType.ArcaneCharges] = { r = 102 / 255, g = 195 / 255, b = 250 / 255, a = 1 },
                [Enum.PowerType.Chi] = { r = 0.00, g = 1.00, b = 0.59, a = 1 },
                [Enum.PowerType.ComboPoints] = { r = 1.00, g = 0.96, b = 0.41, a = 1 },
                [Enum.PowerType.Essence] = { r = 0.20, g = 0.58, b = 0.50, a = 1 },
                [Enum.PowerType.HolyPower] = { r = 0.8863, g = 0.8235, b = 0.2392, a = 1 },
                [C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON] = { r = 0.043, g = 0.631, b = 0.890, a = 1 },
                [Enum.PowerType.SoulShards] = { r = 0.58, g = 0.51, b = 0.79, a = 1 },
            },
            -- Remember to enable the resource type in Constants too.
            maxColorsEnabled = {
                [C.RESOURCEBAR_TYPE_ICICLES] = true,
                [C.RESOURCEBAR_TYPE_DEVOURER_NORMAL] = true,
                [C.RESOURCEBAR_TYPE_DEVOURER_META] = true,
            },
            maxColors = {
                [C.RESOURCEBAR_TYPE_ICICLES] = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
                [C.RESOURCEBAR_TYPE_DEVOURER_NORMAL] = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
                [C.RESOURCEBAR_TYPE_DEVOURER_META] = { r = 0.8, g = 0.8, b = 0.8, a = 1 },
            },
        },
        runeBar = {
            enabled = true,
            anchorMode = C.ANCHORMODE_CHAIN,
            width = 300,
            editModePositions = {},
            overrideFont = false,
            useSpecColor = true,
            color = { r = 0.87, g = 0.10, b = 0.22, a = 1 },
            colorBlood = { r = 0.87, g = 0.10, b = 0.22, a = 1 },
            colorFrost = { r = 0.33, g = 0.69, b = 0.87, a = 1 },
            colorUnholy = { r = 0.00, g = 0.61, b = 0.00, a = 1 },
        },
        buffBars = {
            enabled = true,
            anchorMode = C.ANCHORMODE_CHAIN,
            editModePositions = {},
            verticalSpacing = 0,
            showIcon = false,
            showSpellName = true,
            showDuration = true,
            overrideFont = false,
            colors = {
                byName = {},
                bySpellID = {},
                byCooldownID = {},
                byTexture = {},
                cache = {},
                defaultColor = { r = 228 / 255, g = 233 / 255, b = 235 / 255, a = 1 },
            },
        },
        externalBars = {
            enabled = false,
            hideOriginalIcons = false,
            anchorMode = C.ANCHORMODE_CHAIN,
            editModePositions = {},
            width = C.DEFAULT_BAR_WIDTH,
            height = 0,
            verticalSpacing = 0,
            showIcon = true,
            showSpellName = true,
            showDuration = true,
            overrideFont = false,
            colors = {
                byName = {},
                bySpellID = {},
                byCooldownID = {},
                byTexture = {},
                cache = {},
                defaultColor = { r = 0.40, g = 0.78, b = 0.95, a = 1 },
            },
        },
        extraIcons = {
            enabled = true,
            showStackCount = true,
            showCharges = true,
            viewers = {
                utility = {
                    { stackKey = "trinket1" },
                    { stackKey = "trinket2" },
                    { stackKey = "combatPotions" },
                    { stackKey = "healthPotions" },
                    { stackKey = "healthstones" },
                },
                main = {},
            },
        },
    },
}

-- Export defaults for Options module to access
ns.defaults = defaults
