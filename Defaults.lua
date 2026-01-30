-- Defaults for Enhanced Cooldown Manager

local ADDON_NAME, ns = ...

---@class ECM_Color
---@field a number
---@field r number
---@field g number
---@field b number

---@class ECM_BarConfigBase
---@field enabled boolean
---@field offsetX number|nil
---@field offsetY number|nil
---@field width number|nil
---@field height number|nil
---@field texture string|nil
---@field showText boolean|nil
---@field bgColor number[]|nil
---@field anchorMode "chain"|"independent"|nil

---@class ECM_PowerBarConfig : ECM_BarConfigBase
---@field showManaAsPercent boolean
---@field colors table<ECM_ResourceType, number[]>
---@field border ECM_BorderConfig
---@field ticks ECM_PowerBarTicksConfig

---@class ECM_ResourceBarConfig : ECM_BarConfigBase
---@field demonHunterSoulsMax number
---@field colors table<ECM_ResourceType, number[]>
---@field border ECM_BorderConfig

---@class ECM_RuneBarConfig : ECM_BarConfigBase
---@field max number
---@field color number[]

---@alias ECM_ResourceType number|string

---@class ECM_GlobalConfig
---@field barHeight number
---@field barBgColor number[]
---@field texture string|nil
---@field font string
---@field fontSize number
---@field fontOutline "NONE"|"OUTLINE"|"THICKOUTLINE"|"MONOCHROME"
---@field fontShadow boolean

---@class ECM_BorderConfig
---@field enabled boolean
---@field thickness number
---@field color ECM_Color

---@class ECM_BarCacheEntry
---@field spellName string|nil
---@field lastSeen number

---@class ECM_BuffBarColorsConfig Buff bar color configuration
---@field perBar table<number, table<number, table<number, number[]>>> Per-bar RGB colors by class/spec/index
---@field cache table<number, table<number, table<number, ECM_BarCacheEntry>>> Cached bar metadata by class/spec/index
---@field defaultColor number[] Default RGB color for buff bars
---@field selectedPalette string|nil Name of the currently selected palette

---@class ECM_BuffBarsConfig Buff bars configuration
---@field anchor "chain"|"independent"|nil Anchor behavior for buff bars
---@field width number|nil Buff bar width when independent
---@field offsetY number|nil Vertical offset when independent
---@field showIcon boolean|nil Whether to show buff icons
---@field showSpellName boolean|nil Whether to show spell names
---@field showDuration boolean|nil Whether to show durations
---@field colors ECM_BuffBarColorsConfig Per-bar color settings

---@class ECM_TickMark
---@field value number
---@field color number[]
---@field width number

---@class ECM_PowerBarTicksConfig
---@field mappings table<number, table<number, ECM_TickMark[]>>
---@field defaultColor ECM_Color
---@field defaultWidth number

---@class ECM_CombatFadeConfig
---@field enabled boolean
---@field opacity number
---@field exceptIfTargetCanBeAttacked boolean
---@field exceptInInstance boolean

---@class ECM_Profile Profile settings
---@field hideWhenMounted boolean
---@field hideOutOfCombatInRestAreas boolean
---@field updateFrequency number
---@field schemaVersion number
---@field debug boolean
---@field offsetY number
---@field combatFade ECM_CombatFadeConfig
---@field global ECM_GlobalConfig
---@field powerBar ECM_PowerBarConfig
---@field resourceBar ECM_ResourceBarConfig
---@field runeBar ECM_RuneBarConfig
---@field buffBars ECM_BuffBarsConfig Buff bars configuration

local DEFAULT_BORDER_THICKNESS = 4
local DEFAULT_BORDER_COLOR = { r = 0.15, g = 0.15, b = 0.15, a = 0.5 }
local DEMONHUNTER_MAX_SOULS = 6
local DEMONHUNTER_CLASS_ID = 12
local DEVOURER_SPEC_INDEX = 3
local DEVOURER_SPEC_ID

if type(GetSpecializationInfoForClassID) == "function" then
    DEVOURER_SPEC_ID = select(1, GetSpecializationInfoForClassID(DEMONHUNTER_CLASS_ID, DEVOURER_SPEC_INDEX))
end

local powerBarTickMappings = {}
if DEVOURER_SPEC_ID then
    powerBarTickMappings[DEMONHUNTER_CLASS_ID] = {
        [DEVOURER_SPEC_ID] = {
            { value = 90, color = { 2 / 3, 2 / 3, 2 / 3, 0.8 } },
            { value = 100 },
        },
    }
end

local defaults = {
    profile = {
        debug = false,
        hideWhenMounted = true,
        hideOutOfCombatInRestAreas = false,
        updateFrequency = 0.04,
        schemaVersion = 4,
        offsetY = 4,
        combatFade = {
            enabled = false,
            opacity = 60,
            exceptIfTargetCanBeAttacked = true,
            exceptInInstance = true,
        },
        global = {
            barHeight = 22,
            barBgColor = { 0.08, 0.08, 0.08, 0.75 },
            texture = "Solid",
            font = "Expressway",
            fontSize = 11,
            fontOutline = "OUTLINE",
            fontShadow = false,
        },
        powerBar = {
            enabled           = true,
            -- width             = nil,
            -- height            = nil,
            -- offsetX           = -350,
            -- offsetY           = 200,
            -- texture           = nil,
            -- bgColor           = nil,
            anchorMode        = "chain",
            -- anchorMode        = "independent",
            showText          = true,
            ticks             = {
                mappings = powerBarTickMappings, -- [classID][specID] = { { value = 50, color = {r,g,b,a}, width = 1 }, ... }
                defaultColor = { 1, 1, 1, 0.8 },
                defaultWidth = 1,
            },
            showManaAsPercent = true,
            border            = {
                enabled = false,
                thickness = DEFAULT_BORDER_THICKNESS,
                color = DEFAULT_BORDER_COLOR,
            },
            colors            = {
                [Enum.PowerType.Mana] = { 0.00, 0.00, 1.00 },
                [Enum.PowerType.Rage] = { 1.00, 0.00, 0.00 },
                [Enum.PowerType.Focus] = { 1.00, 0.57, 0.31 },
                [Enum.PowerType.Energy] = { 0.85, 0.65, 0.13 },
                [Enum.PowerType.RunicPower] = { 0.00, 0.82, 1.00 },
                [Enum.PowerType.LunarPower] = { 0.30, 0.52, 0.90 },
                [Enum.PowerType.Fury] = { 0.79, 0.26, 0.99 },
                [Enum.PowerType.Maelstrom] = { 0.00, 0.50, 1.00 },
                [Enum.PowerType.ArcaneCharges] = { 0.20, 0.60, 1.00 },
            },
        },
        resourceBar = {
            enabled             = true,
            -- width               = nil,
            -- height              = nil,
            -- offsetX             = nil,
            -- offsetY             = nil,
            -- texture             = nil,
            -- bgColor             = nil,
            anchorMode          = "chain",
            demonHunterSoulsMax = DEMONHUNTER_MAX_SOULS,
            border              = {
                enabled = false,
                thickness = DEFAULT_BORDER_THICKNESS,
                color = DEFAULT_BORDER_COLOR,
            },
            colors              = {
                souls = { 0.259, 0.6, 0.91 },
                devourerNormal = { 0.447, 0.412, 0.651 },
                devourerMeta = { 0.275, 0.169, 1.0 },
                [Enum.PowerType.ComboPoints] = { 0.75, 0.15, 0.15 },
                [Enum.PowerType.Chi] = { 0.00, 1.00, 0.59 },
                [Enum.PowerType.HolyPower] = { 0.8863, 0.8235, 0.2392 },
                [Enum.PowerType.SoulShards] = { 0.58, 0.51, 0.79 },
                [Enum.PowerType.Essence] = { 0.20, 0.58, 0.50 }
            },
        },
        runeBar = {
            enabled    = true,
            -- width      = nil,
            -- height     = nil,
            -- offsetX    = nil,
            -- offsetY    = nil,
            -- texture    = nil,
            -- bgColor    = nil,
            anchorMode = "chain",
            max        = 6,
            color      = { 0.87, 0.10, 0.22 }, -- DK class colour red
        },
        buffBars = {
            anchorMode = "chain",
            width = 300,
            offsetY = 0,
            showIcon = false,
            showSpellName = true,
            showDuration = true,
            colors = {
                perBar = {},
                cache = {},
                defaultColor = { 228 / 255, 233 / 255, 235 / 255 },
                selectedPalette = nil,
            },
        },
    },
}

-- Export defaults for Options module to access
ns.defaults = defaults
