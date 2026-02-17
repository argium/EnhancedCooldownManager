ECM = ECM or {} -- this file is probably loaded before everything else so this initializes the global table.

local constants = {
    ADDON_NAME = "Enhanced Cooldown Manager",
    ADDON_ICON_TEXTURE = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\icon",
    ADDON_ABRV = "ECM",

    DEBUG_COLOR = "F17934",

    -- Internal module names
    POWERBAR = "PowerBar",
    RESOURCEBAR = "ResourceBar",
    RUNEBAR = "RuneBar",
    BUFFBARS = "BuffBars",
    ITEMICONS = "ItemIcons",

    -- Configuration
    CONFIG_SECTION_GLOBAL = "global",
    ANCHORMODE_CHAIN = "chain",
    ANCHORMODE_FREE = "free",

    -- Default or fallback values for configuration
    DEFAULT_FONT = "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf",
    DEFAULT_REFRESH_FREQUENCY = 0.066,
    DEFAULT_BAR_HEIGHT = 20,
    DEFAULT_BAR_WIDTH = 250,
    DEFAULT_FREE_ANCHOR_OFFSET_Y = -300,
    DEFAULT_BG_COLOR = { r = 0.08, g = 0.08, b = 0.08, a = 0.65 },
    DEFAULT_STATUSBAR_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    DEFAULT_BORDER_THICKNESS = 4,
    DEFAULT_BORDER_COLOR = { r = 0.15, g = 0.15, b = 0.15, a = 0.5 },
    DEFAULT_POWERBAR_TICK_COLOR = { r = 1, g = 1, b = 1, a = 0.8 },
    FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8X8",

    -- Color constants
    COLOR_BLACK = { r = 0, g = 0, b = 0, a = 1 },
    COLOR_WHITE = { r = 1, g = 1, b = 1, a = 1 },

    -- Module-specific constants and configuration
    POWERBAR_SHOW_MANABAR = { MAGE = true, WARLOCK = true, DRUID = true },
    RESOURCEBAR_SPIRIT_BOMB_SPELLID = 247454,
    RESOURCEBAR_VOID_FRAGMENTS_SPELLID = 1225789,  -- tracks progress towards void meta form (35 fragments)
    RESOURCEBAR_COLLAPSING_STAR_SPELLID = 1227702, -- when in void meta, tracks progress towards collapsing star (30 stacks)
    RESOURCEBAR_VENGEANCE_SOULS_MAX = 6,
    RESOURCEBAR_DEVOURER_NORMAL_MAX = 30,
    RESOURCEBAR_DEVOURER_META_MAX = 35,
    RESOURCEBAR_MAELSTROM_WEAPON_SPELLID = 344179,
    RESOURCEBAR_RAGING_MAELSTROM_SPELLID = 384143,
    RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE = 5,
    RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED = 10,

    RUNEBAR_MAX_RUNES = 6,
    RUNEBAR_CD_DIM_FACTOR = 0.5,
    BUFFBARS_DEFAULT_COLOR = { r = 228 / 255, g = 233 / 255, b = 235 / 255, a = 1 },
    BUFFBARS_ICON_TEXTURE_REGION_INDEX = 1,
    BUFFBARS_ICON_OVERLAY_REGION_INDEX = 3,
    BUFFBARS_TEXT_PADDING = 4,

    DEMONHUNTER_CLASS_ID = 12,
    DEMONHUNTER_VENGEANCE_SPEC_INDEX = 2,
    DEMONHUNTER_DEVOURER_SPEC_INDEX = 3,
    SHAMAN_ENHANCEMENT_SPEC_INDEX = 2,
    MONK_BREWMASTER_SPEC_INDEX = 1,
    MAGE_ARCANE_SPEC_INDEX = 1,
    DRUID_CAT_FORM_INDEX = 2,

    -- Trinket slots
    TRINKET_SLOT_1 = 13,
    TRINKET_SLOT_2 = 14,

    -- Consumable item IDs (priority-ordered: best first)
    COMBAT_POTIONS = { 212265, 212264, 212263 }, -- Tempered Potion R3, R2, R1
    HEALTH_POTIONS = { 211880, 211879, 211878,   -- Algari Healing Potion R3, R2, R1
        212244, 212243, 212242 },                -- Cavedweller's Delight R3, R2, R1
    HEALTHSTONE_ITEM_ID = 5512,
    ITEM_ICONS_MAX = 5,

    -- Item icon defaults
    DEFAULT_ITEM_ICON_SIZE = 32,
    DEFAULT_ITEM_ICON_SPACING = 2,
    ITEM_ICON_BORDER_SCALE = 1.35,

    -- Guardrail for measured utility icon spacing (as a factor of icon width)
    -- TODO: this has to go. it's gross.
    ITEM_ICON_MAX_SPACING_FACTOR = 0.6,
    ITEM_ICON_LAYOUT_REMEASURE_DELAY = 0.1,
    ITEM_ICON_LAYOUT_REMEASURE_ATTEMPTS = 2,

    -- Schema migration
    CURRENT_SCHEMA_VERSION = 8,
    SV_NAME = "EnhancedCooldownManagerDB",
    ACTIVE_SV_KEY = "_ECM_DB",

    LIFECYCLE_SECOND_PASS_DELAY = 0.05,

    ME = "Solar"
}

--- @enum SUBSYSTEM
local SYS = {
    Core = "Core",
    Migration = "Migration",
    Layout = "Layout",
    Styling = "Styling",
    SpellColors = "SpellColors",
}

local BLIZZARD_FRAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

--- Class info keyed by class ID. Each entry has name and hex color (without alpha prefix).
local CLASS_BY_ID = {
    [1]  = { name = "WARRIOR",      color = "C79C6E" },
    [2]  = { name = "PALADIN",      color = "F58CBA" },
    [3]  = { name = "HUNTER",       color = "ABD473" },
    [4]  = { name = "ROGUE",        color = "FFF569" },
    [5]  = { name = "PRIEST",       color = "FFFFFF" },
    [6]  = { name = "DEATHKNIGHT",  color = "C41F3B" },
    [7]  = { name = "SHAMAN",       color = "0070DE" },
    [8]  = { name = "MAGE",         color = "69CCF0" },
    [9]  = { name = "WARLOCK",      color = "9482C9" },
    [10] = { name = "MONK",         color = "00FF96" },
    [11] = { name = "DRUID",        color = "FF7D0A" },
    [12] = { name = "DEMONHUNTER",  color = "A330C9" },
    [13] = { name = "EVOKER",       color = "33937F" },
}

--- Chat channel colors keyed by channel name.
local CHAT_CHANNELS = {
    SAY          = { color = "FFFFFF" },
    YELL         = { color = "FF3F40" },
    WHISPER      = { color = "FF7EFF" },
    PARTY        = { color = "AAABFE" },
    PARTY_LEADER = { color = "77C8FF" },
    RAID         = { color = "FF7F00" },
    RAID_WARNING = { color = "FF4809" },
    INSTANCE     = { color = "FF7D01" },
    GUILD        = { color = "3CE13F" },
    OFFICER      = { color = "40BC40" },
    EMOTE        = { color = "FF7E40" },
    SYSTEM       = { color = "FFFF00" },
    QUEST        = { color = "CC9933" },
    LFG          = { color = "FEC1C0" },
    BATTLENET    = { color = "00FAF6" },
    GENERAL      = { color = "FFC080" },
    TRADE        = { color = "FFC080" },
    LOOT         = { color = "00A956" },
}

local order = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS }
constants.CHAIN_ORDER = order
constants.BLIZZARD_FRAMES = BLIZZARD_FRAMES
constants.CLASS_BY_ID = CLASS_BY_ID
constants.CHAT_CHANNELS = CHAT_CHANNELS
constants.SYS = SYS

ECM.Constants = constants
