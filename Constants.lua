local _,  ns = ...

local constants = {
    TRACE_LOG_MAX = 200,

    -- Internal module names
    POWERBAR = "PowerBar",
    RESOURCEBAR = "ResourceBar",
    RUNEBAR = "RuneBar",
    BUFFBARS = "BuffBars",
    ITEMICONS = "ItemIcons",

    -- Blizzard frame names
    VIEWER = "EssentialCooldownViewer",
    VIEWER_BUFFBAR = "BuffBarCooldownViewer",
    VIEWER_UTILITY = "UtilityCooldownViewer",
    ADDON_ICON_TEXTURE = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\icon",

    -- Default or fallback values for configuration
    DEFAULT_REFRESH_FREQUENCY = 0.066,
    DEFAULT_BAR_HEIGHT = 20,
    DEFAULT_BAR_WIDTH = 250,
    DEFAULT_FREE_ANCHOR_OFFSET_Y = -300,
    DEFAULT_BG_COLOR = { r = 0.08, g = 0.08, b = 0.08, a = 0.65 },
    DEFAULT_STATUSBAR_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar",
    FALLBACK_TEXTURE = "Interface\\Buttons\\WHITE8X8",

    -- Color constants
    COLOR_BLACK = { r = 0, g = 0, b = 0, a = 1 },
    COLOR_WHITE = { r = 1, g = 1, b = 1, a = 1 },

    -- Module-specific constants and configuration
    POWERBAR_SHOW_MANABAR = { MAGE = true, WARLOCK = true, DRUID = true },
    RESOURCEBAR_SPIRIT_BOMB_SPELLID = 247454,
    RESOURCEBAR_VOID_FRAGMENTS_SPELLID = 1225789, -- tracks progress towards void meta form (35 fragments)
    RESOURCEBAR_COLLAPSING_STAR_SPELLID = 1227702, -- when in void meta, tracks progress towards collapsing star (30 stacks)
    RESOURCEBAR_VENGEANCE_SOULS_MAX = 6 ,
    RUNEBAR_MAX_RUNES = 6,
    BUFFBARS_DEFAULT_COLOR = { r = 0.9, g = 0.9, b = 0.9, a = 1 },
    BUFFBARS_ICON_TEXTURE_REGION_INDEX = 1,  -- TODO: this and the following line might need to go.
    BUFFBARS_ICON_OVERLAY_REGION_INDEX = 3,
    BUFFBARS_TEXT_PADDING = 4,
    GROUP_INSTANCE_TYPES = { party = true, raid = true, arena = true, pvp = true, delve = true }, -- keyed by IsInInstance()[2]

    DEMONHUNTER_CLASS_ID = 12,
    DEMONHUNTER_VENGEANCE_SPEC_INDEX = 2,
    DEMONHUNTER_DEVOURER_SPEC_INDEX = 3,

    -- Trinket slots
    TRINKET_SLOT_1 = 13,
    TRINKET_SLOT_2 = 14,

    -- Consumable item IDs (priority-ordered: best first)
    COMBAT_POTIONS = { 212265, 212264, 212263 },           -- Tempered Potion R3, R2, R1
    HEALTH_POTIONS = { 211880, 211879, 211878,             -- Algari Healing Potion R3, R2, R1
                       212244, 212243, 212242 },            -- Cavedweller's Delight R3, R2, R1
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

    -- Configuration section names
    CONFIG_SECTION_GLOBAL = "global",

    ANCHORMODE_CHAIN = "chain",
    ANCHORMODE_FREE = "free",
}

local BLIZZARD_FRAMES = {
    constants.VIEWER,
    constants.VIEWER_UTILITY,
    "BuffIconCooldownViewer",
    constants.VIEWER_BUFFBAR,
}

local order = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS }
constants.CHAIN_ORDER = order
constants.BLIZZARD_FRAMES = BLIZZARD_FRAMES

ns.Constants = constants
