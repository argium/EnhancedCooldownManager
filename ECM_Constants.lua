-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

ECM = ECM or {} -- this file is probably loaded before everything else so this initializes the global table.

local constants = {
    -- Addon metadata
    ADDON_ICON_TEXTURE = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\icon",
    ADDON_METADATA_VERSION_KEY = "Version",
    DEBUG_COLOR = "F17934",
    RELEASE_POPUP_VERSION = "v0.7.0",
    VERSION_TAG_BETA = "beta",

    -- Module identifiers
    BUFFBARS = "BuffBars",
    ITEMICONS = "ItemIcons",
    POWERBAR = "PowerBar",
    RESOURCEBAR = "ResourceBar",
    RUNEBAR = "RuneBar",

    -- Shared configuration values
    ANCHORMODE_CHAIN = "chain",
    ANCHORMODE_DETACHED = "detached",
    ANCHORMODE_FREE = "free",
    CONFIG_SECTION_GLOBAL = "global",
    EDIT_MODE_DEFAULT_POINT = "CENTER",
    GROW_DIRECTION_DOWN = "down",
    GROW_DIRECTION_UP = "up",

    -- Shared visuals and defaults
    COLOR_BLACK = { r = 0, g = 0, b = 0, a = 1 },
    COLOR_WHITE = { r = 1, g = 1, b = 1, a = 1 },
    COLOR_WHITE_HEX = "FFFFFF",
    DEFAULT_BAR_HEIGHT = 20,
    DEFAULT_BAR_WIDTH = 250,
    DEFAULT_BG_COLOR = { r = 0.08, g = 0.08, b = 0.08, a = 0.65 },
    DEFAULT_BORDER_COLOR = { r = 0.15, g = 0.15, b = 0.15, a = 0.5 },
    DEFAULT_BORDER_THICKNESS = 4,
    DEFAULT_FONT = "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf",
    DEFAULT_FONT_SIZE = 11,
    DEFAULT_POWERBAR_TICK_COLOR = { r = 1, g = 1, b = 1, a = 0.8 },
    DEFAULT_REFRESH_FREQUENCY = 0.066,
    DEFAULT_STATUSBAR_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8X8",

    -- Power bar
    POWERBAR_SHOW_MANABAR = { MAGE = true, WARLOCK = true, DRUID = true },

    -- Resource bar identifiers
    RESOURCEBAR_TYPE_DEVOURER_META = "devourerMeta",
    RESOURCEBAR_TYPE_DEVOURER_NORMAL = "devourerNormal",
    RESOURCEBAR_TYPE_ICICLES = "icicles",
    RESOURCEBAR_TYPE_MAELSTROM_WEAPON = "maelstromWeapon",
    RESOURCEBAR_TYPE_VENGEANCE_SOULS = "souls",

    -- Resource bar spell IDs
    RESOURCEBAR_ICICLES_SPELLID = 205473,
    RESOURCEBAR_RAGING_MAELSTROM_SPELLID = 384143,
    RESOURCEBAR_SPIRIT_BOMB_SPELLID = 247454,

    -- Resource bar limits
    RESOURCEBAR_COLLAPSING_STAR_MAX = 30,
    RESOURCEBAR_DEVOURER_SOUL_FRAGMENTS_MAX = 50,
    RESOURCEBAR_ICICLES_MAX = 5,
    RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE = 5,
    RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED = 10,
    RESOURCEBAR_VENGEANCE_SOULS_MAX = 6,

    -- Resource bar related spell IDs
    SPELLID_COLLAPSING_STAR = 1227702, -- when in void meta, tracks progress towards collapsing star (30 stacks)
    SPELLID_MAELSTROM_WEAPON = 344179,
    SPELLID_DEVOURER_SOUL_FRAGMENTS = 1225789, -- tracks progress towards void meta form (50 soul fragments)
    SPELLID_SOUL_GLUTTEN = 1247534, -- reduces the number of souls needed for void meta by 15
    SPELLID_VOID_META = 1217607, -- void meta

    -- Buff bars
    BUFFBARS_DEFAULT_COLOR = { r = 228 / 255, g = 233 / 255, b = 235 / 255, a = 1 },
    BUFFBARS_ICON_TEXTURE_REGION_INDEX = 1,
    BUFFBARS_ICON_OVERLAY_REGION_INDEX = 3,
    BUFFBARS_TEXT_PADDING = 4,

    -- Rune bar
    RUNEBAR_CD_DIM_FACTOR = 0.5,
    RUNEBAR_MAX_RUNES = 6,

    -- Class and specialization identifiers
    DEATHKNIGHT_FROST_SPEC_INDEX = 2,
    DEATHKNIGHT_UNHOLY_SPEC_INDEX = 3,
    DEMONHUNTER_CLASS_ID = 12,
    DEMONHUNTER_DEVOURER_SPEC_INDEX = 3,
    DEMONHUNTER_VENGEANCE_SPEC_INDEX = 2,
    DRUID_CAT_FORM_INDEX = 2,
    MAGE_ARCANE_SPEC_INDEX = 1,
    MAGE_FROST_SPEC_INDEX = 3,
    MONK_BREWMASTER_SPEC_INDEX = 1,
    MONK_MISTWEAVER_SPEC_INDEX = 2,
    MONK_WINDWALKER_SPEC_INDEX = 3,
    SHAMAN_ELEMENTAL_SPEC_INDEX = 1,
    SHAMAN_ENHANCEMENT_SPEC_INDEX = 2,
    SHAMAN_RESTORATION_SPEC_INDEX = 3,

    -- Item icons
    DEFAULT_ITEM_ICON_SIZE = 32,
    ITEM_ICON_BORDER_SCALE = 1.35,
    ITEM_ICONS_MAX = 5,

    -- Consumables and equipment slots
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
    TRINKET_SLOT_1 = 13,
    TRINKET_SLOT_2 = 14,

    -- Saved variables and migration
    ACTIVE_SV_KEY = "_ECM_DB",
    CURRENT_SCHEMA_VERSION = 11,
    SV_NAME = "EnhancedCooldownManagerDB",

    -- Import and export
    EXPORT_PREFIX = "EnhancedCooldownManager",
    EXPORT_VERSION = 1,

    -- Runtime timing and debug limits
    LAYOUT_COMBAT_END_DELAY = 0.1,
    LAYOUT_ENTERING_WORLD_DELAY = 0.4,
    LAYOUT_ZONE_CHANGE_DELAY = 0.1,
    LIFECYCLE_SECOND_PASS_DELAY = 0.05,
    TOSTRING_MAX_DEPTH = 3,
    TOSTRING_MAX_ITEMS = 25,
    WATCHDOG_INTERVAL = 0.5,

    -- Dialogs and popups
    DIALOG_BACKDROP = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    },
    DIALOG_FRAME_HEIGHT = 360,
    DIALOG_FRAME_HEIGHT_SMALL = 160,
    DIALOG_FRAME_WIDTH = 480,
    DIALOG_FRAME_WIDTH_SMALL = 400,
    POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI",
    POPUP_PREFERRED_INDEX = 3,
    WHATS_NEW_BUTTON_BOTTOM_OFFSET = 16,
    WHATS_NEW_BUTTON_HEIGHT = 24,
    WHATS_NEW_BUTTON_SPACING = 8,
    WHATS_NEW_BODY_SPACING = 12,
    WHATS_NEW_CLOSE_BUTTON_WIDTH = 120,
    WHATS_NEW_FRAME_HEIGHT = 480,
    WHATS_NEW_FRAME_NAME = "ECMWhatsNewFrame",
    WHATS_NEW_FRAME_OFFSET_Y = 20,
    WHATS_NEW_FRAME_PADDING = 18,
    WHATS_NEW_FRAME_WIDTH = 520,
    WHATS_NEW_HEADER_COLOR = "FFD100",
    WHATS_NEW_LIST_BULLET = "\194\183",
    WHATS_NEW_SETTINGS_BUTTON_WIDTH = 140,
    WHATS_NEW_SUBTITLE_SPACING = 8,

    -- UI dimension constants
    POSITION_MODE_EXPLAINER_HEIGHT = 150,
    SCROLL_ROW_HEIGHT_COMPACT = 26,
    SCROLL_ROW_HEIGHT_WITH_CONTROLS = 34,
    SPELL_COLORS_SCROLL_BOTTOM_OFFSET_WITH_SECRET_NAMES = 80,
    SPELL_COLORS_SECRET_NAMES_BUTTON_BOTTOM_OFFSET = 8,
    SPELL_COLORS_SECRET_NAMES_DESC_BOTTOM_OFFSET = 42,
    SPELL_COLORS_SECRET_NAMES_DESC_HEIGHT = 40,

    VALUE_SLIDER_TIERS = {
        { ceiling = 200,    step = 1 },
        { ceiling = 1000,   step = 5 },
        { ceiling = 5000,   step = 25 },
        { ceiling = 10000,  step = 50 },
        { ceiling = 50000,  step = 250 },
        { ceiling = 100000, step = 500 },
        { ceiling = 500000, step = 2500 },
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

-- Resource types that support a separate color when at maximum value.
-- Code-level gate; user toggle is stored in the profile (maxColorsEnabled).
local resourceBarMaxColorTypes = {
    [constants.RESOURCEBAR_TYPE_ICICLES] = true,
    [constants.RESOURCEBAR_TYPE_DEVOURER_META] = true,
    [constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL] = true,
}

local resourceBarCastableMaxColorSpells = {
    [constants.RESOURCEBAR_TYPE_DEVOURER_META] = constants.SPELLID_COLLAPSING_STAR,
    [constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL] = constants.SPELLID_VOID_META,
}

--- Authoritative mapping from module name to its profile config key.
local moduleConfigKeys = {
    [constants.POWERBAR] = "powerBar",
    [constants.RESOURCEBAR] = "resourceBar",
    [constants.RUNEBAR] = "runeBar",
    [constants.BUFFBARS] = "buffBars",
    [constants.ITEMICONS] = "itemIcons",
}

--- Returns the profile config key for a module name.
--- Uses the authoritative lookup; falls back to lowercasing the first character.
function constants.ConfigKeyForModule(name)
    return moduleConfigKeys[name] or (name:sub(1, 1):lower() .. name:sub(2))
end

local chainOrder = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS }
constants.CHAIN_ORDER = chainOrder
constants.MODULE_ORDER = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS, constants.ITEMICONS }
constants.MODULE_CONFIG_KEYS = moduleConfigKeys
constants.BLIZZARD_FRAMES = BLIZZARD_FRAMES
constants.RESOURCEBAR_CASTABLE_MAX_COLOR_SPELLS = resourceBarCastableMaxColorSpells
constants.CLASS_COLORS = CLASS_COLORS
constants.RESOURCEBAR_MAX_COLOR_TYPES = resourceBarMaxColorTypes

ECM.Constants = constants
