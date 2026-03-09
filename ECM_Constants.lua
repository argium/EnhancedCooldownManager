-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

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

    -- Module name to config key mapping
    -- Configuration
    CONFIG_SECTION_GLOBAL = "global",
    ANCHORMODE_CHAIN = "chain",
    ANCHORMODE_FREE = "free",
    GROW_DIRECTION_DOWN = "down",
    GROW_DIRECTION_UP = "up",

    -- Default or fallback values for configuration
    DEFAULT_FONT = "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf",
    DEFAULT_REFRESH_FREQUENCY = 0.066,
    WATCHDOG_INTERVAL = 0.5,
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
    SPELLID_VOID_FRAGMENTS = 1225789, -- tracks progress towards void meta form (35 fragments)
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
        { itemID = 245898, quality = 2 }, -- https://www.wowhead.com/item=245898/fleeting-lights-potential
        { itemID = 245897, quality = 1 }, -- https://www.wowhead.com/item=245897/fleeting-lights-potential
        { itemID = 241308, quality = 2 }, -- https://www.wowhead.com/item=241308/lights-potential
        { itemID = 241309, quality = 1 }, -- https://www.wowhead.com/item=241309/lights-potential
    },
    HEALTH_POTIONS = {
        { itemID = 241305, quality = 2 }, -- Silvermoon Health Potion R2 https://www.wowhead.com/item=241305/silvermoon-health-potion
        { itemID = 241304, quality = 1 }, -- Silvermoon Health Potion R1 https://www.wowhead.com/item=241304/silvermoon-health-potion
        { itemID = 258138, quality = 1 }, -- Potent Healing Potion https://www.wowhead.com/item=258138/potent-healing-potion
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

    -- Debug serialization limits
    TOSTRING_MAX_DEPTH = 3,
    TOSTRING_MAX_ITEMS = 25,

    -- Font fallback
    DEFAULT_FONT_SIZE = 11,

    -- Layout event delays
    LAYOUT_ENTERING_WORLD_DELAY = 0.4,
    LAYOUT_COMBAT_END_DELAY = 0.1,
    LAYOUT_ZONE_CHANGE_DELAY = 0.1,

    -- Opacity
    OPACITY_MAX_PERCENT = 100,

    -- Popup dialog
    POPUP_PREFERRED_INDEX = 3,

    -- Import/Export
    EXPORT_PREFIX = "EnhancedCooldownManager",
    EXPORT_VERSION = 1,

    -- UI Options
    SPELL_COLORS_DESC_TEXT = "Customize colors for individual spells. Colors are saved per class and specialization.",
    SPELL_COLORS_SUBCAT = "Spell Colors",
    SCROLL_ROW_HEIGHT_COMPACT = 26,
    TICK_MARKS_DESC_TEXT = "Customize tick marks for the power bar. Marks are saved per class and specialization.",
    SCROLL_ROW_HEIGHT_WITH_CONTROLS = 34,

    -- Dialog frame
    DIALOG_FRAME_WIDTH = 480,
    DIALOG_FRAME_HEIGHT = 360,
    DIALOG_FRAME_WIDTH_SMALL = 400,
    DIALOG_FRAME_HEIGHT_SMALL = 160,
    DIALOG_BACKDROP = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
}

local BLIZZARD_FRAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local CLASS_COLORS = {
    DEATHKNIGHT = "C41F3B",
    DEMONHUNTER = "A330C9",
    DRUID = "FF7D0A",
    EVOKER = "33937F",
    HUNTER = "ABD473",
    MAGE = "69CCF0",
    MONK = "00FF96",
    PALADIN = "F58CBA",
    PRIEST = "FFFFFF",
    ROGUE = "FFF569",
    SHAMAN = "0070DE",
    WARLOCK = "9482C9",
    WARRIOR = "C79C6E",
}

local order = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS }
constants.CHAIN_ORDER = order
constants.BLIZZARD_FRAMES = BLIZZARD_FRAMES
constants.CLASS_COLORS = CLASS_COLORS

ECM.Constants = constants
