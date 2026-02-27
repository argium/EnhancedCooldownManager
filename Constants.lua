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
    GROW_DIRECTION_DOWN = "down",
    GROW_DIRECTION_UP = "up",

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
    COLOR_WHITE_HEX = "FFFFFF",

    -- Module-specific constants and configuration
    POWERBAR_SHOW_MANABAR = { MAGE = true, WARLOCK = true, DRUID = true },
    RESOURCEBAR_SPIRIT_BOMB_SPELLID = 247454,
    RESOURCEBAR_ICICLES_SPELLID = 205473,
    SPELLID_VOID_FRAGMENTS = 1225789,  -- tracks progress towards void meta form (35 fragments)
    SPELLID_COLLAPSING_STAR = 1227702, -- when in void meta, tracks progress towards collapsing star (30 stacks)
    RESOURCEBAR_VENGEANCE_SOULS_MAX = 6,
    RESOURCEBAR_DEVOURER_NORMAL_MAX = 30,
    RESOURCEBAR_DEVOURER_META_MAX = 35,
    RESOURCEBAR_ICICLES_MAX = 5,
    SPELLID_MAELSTROM_WEAPON = 344179,
    RESOURCEBAR_RAGING_MAELSTROM_SPELLID = 384143,
    RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE = 5,
    RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED = 10,
    RESOURCEBAR_TYPE_VENGEANCE_SOULS = "souls",
    RESOURCEBAR_TYPE_DEVOURER_NORMAL = "devourerNormal",
    RESOURCEBAR_TYPE_DEVOURER_META = "devourerMeta",
    RESOURCEBAR_TYPE_ICICLES = "icicles",
    RESOURCEBAR_TYPE_MAELSTROM_WEAPON = "maelstromWeapon",

    RUNEBAR_MAX_RUNES = 6,
    RUNEBAR_CD_DIM_FACTOR = 0.5,
    BUFFBARS_DEFAULT_COLOR = { r = 228 / 255, g = 233 / 255, b = 235 / 255, a = 1 },
    BUFFBARS_ICON_TEXTURE_REGION_INDEX = 1,
    BUFFBARS_ICON_OVERLAY_REGION_INDEX = 3,
    BUFFBARS_TEXT_PADDING = 4,

    DEMONHUNTER_CLASS_ID = 12,
    DEMONHUNTER_VENGEANCE_SPEC_INDEX = 2,
    DEMONHUNTER_DEVOURER_SPEC_INDEX = 3,
    DEATHKNIGHT_BLOOD_SPEC_INDEX = 1,
    DEATHKNIGHT_FROST_SPEC_INDEX = 2,
    DEATHKNIGHT_UNHOLY_SPEC_INDEX = 3,
    SHAMAN_ELEMENTAL_SPEC_INDEX = 1,
    SHAMAN_ENHANCEMENT_SPEC_INDEX = 2,
    SHAMAN_RESTORATION_SPEC_INDEX = 3,
    MONK_BREWMASTER_SPEC_INDEX = 1,
    MONK_MISTWEAVER_SPEC_INDEX = 2,
    MONK_WINDWALKER_SPEC_INDEX = 3,
    MAGE_ARCANE_SPEC_INDEX = 1,
    MAGE_FROST_SPEC_INDEX = 3,
    DRUID_CAT_FORM_INDEX = 2,

    -- Trinket slots
    TRINKET_SLOT_1 = 13,
    TRINKET_SLOT_2 = 14,

    -- Consumable item IDs (priority-ordered: best first)
    COMBAT_POTIONS = {
        { itemID = 212265, quality = 3 }, -- Tempered Potion R3
        { itemID = 212264, quality = 2 }, -- Tempered Potion R2
        { itemID = 212263, quality = 1 }, -- Tempered Potion R1
    },
    HEALTH_POTIONS = {
        { itemID = 211880, quality = 3 }, -- Algari Healing Potion R3
        { itemID = 211879, quality = 2 }, -- Algari Healing Potion R2
        { itemID = 211878, quality = 1 }, -- Algari Healing Potion R1
        { itemID = 212244, quality = 3 }, -- Cavedweller's Delight R3
        { itemID = 212243, quality = 2 }, -- Cavedweller's Delight R2
        { itemID = 212242, quality = 1 }, -- Cavedweller's Delight R1
    },
    HEALTHSTONE_ITEM_ID = 5512,
    ITEM_ICONS_MAX = 5,

    -- Item icon defaults
    DEFAULT_ITEM_ICON_SIZE = 32,
    DEFAULT_ITEM_ICON_SPACING = 2,
    ITEM_ICON_BORDER_SCALE = 1.35,
    ITEM_ICON_LAYOUT_REMEASURE_DELAY = 0.1,
    ITEM_ICON_LAYOUT_REMEASURE_ATTEMPTS = 2,

    -- Schema migration
    CURRENT_SCHEMA_VERSION = 10,
    SV_NAME = "EnhancedCooldownManagerDB",
    ACTIVE_SV_KEY = "_ECM_DB",

    LIFECYCLE_SECOND_PASS_DELAY = 0.05,

    ME = "Solar"
}

local BLIZZARD_FRAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local CLASS = {
    DEATHKNIGHT = "DEATHKNIGHT",
    DEMONHUNTER = "DEMONHUNTER",
    DRUID = "DRUID",
    EVOKER = "EVOKER",
    HUNTER = "HUNTER",
    MAGE = "MAGE",
    MONK = "MONK",
    PALADIN = "PALADIN",
    PRIEST = "PRIEST",
    ROGUE = "ROGUE",
    SHAMAN = "SHAMAN",
    WARLOCK = "WARLOCK",
    WARRIOR = "WARRIOR",
}

local CLASS_COLORS = {
    [CLASS.DEATHKNIGHT] = "C41F3B",
    [CLASS.DEMONHUNTER] = "A330C9",
    [CLASS.DRUID]       = "FF7D0A",
    [CLASS.EVOKER]      = "33937F",
    [CLASS.HUNTER]      = "ABD473",
    [CLASS.MAGE]        = "69CCF0",
    [CLASS.MONK]        = "00FF96",
    [CLASS.PALADIN]     = "F58CBA",
    [CLASS.PRIEST]      = "FFFFFF",
    [CLASS.ROGUE]       = "FFF569",
    [CLASS.SHAMAN]      = "0070DE",
    [CLASS.WARLOCK]     = "9482C9",
    [CLASS.WARRIOR]     = "C79C6E",
}

--- Chat channel colors keyed by channel name.
local ChatChannelColors = {
    SAY          = "FFFFFF",
    YELL         = "FF3F40",
    WHISPER      = "FF7EFF",
    PARTY        = "AAABFE",
    PARTY_LEADER = "77C8FF",
    RAID         = "FF7F00",
    RAID_WARNING = "FF4809",
    INSTANCE     = "FF7D01",
    GUILD        = "3CE13F",
    OFFICER      = "40BC40",
    EMOTE        = "FF7E40",
    SYSTEM       = "FFFF00",
    QUEST        = "CC9933",
    LFG          = "FEC1C0",
    BATTLENET    = "00FAF6",
    GENERAL      = "FFC080",
    TRADE        = "FFC080",
    LOOT         = "00A956",
}

local order = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS }
constants.CHAIN_ORDER = order
constants.BLIZZARD_FRAMES = BLIZZARD_FRAMES
constants.CLASS = CLASS
constants.CLASS_COLORS = CLASS_COLORS

ECM.Constants = constants
