local _,  ns = ...

local constants = {
    TRACE_LOG_MAX = 200,

    -- Internal module names
    POWERBAR = "PowerBar",
    RESOURCEBAR = "ResourceBar",
    RUNEBAR = "RuneBar",
    BUFFBARS = "BuffBars",

    -- Blizzard frame names
    VIEWER = "EssentialCooldownViewer",
    VIEWER_BUFFBAR = "BuffBarCooldownViewer",

    -- Default or fallback values for configuration
    DEFAULT_REFRESH_FREQUENCY = 0.066,
    DEFAULT_BAR_HEIGHT = 20,
    DEFAULT_BAR_WIDTH = 250,
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

    DEMONHUNTER_CLASS_ID = 12,
    DEMONHUNTER_VENGEANCE_SPEC_INDEX = 2,
    DEMONHUNTER_DEVOURER_SPEC_INDEX = 3,

    -- Configuration section names
    CONFIG_SECTION_GLOBAL = "global",

    ANCHORMODE_CHAIN = "chain",
    ANCHORMODE_FREE = "free",
}

local order = { constants.POWERBAR, constants.RESOURCEBAR, constants.RUNEBAR, constants.BUFFBARS }
constants.CHAIN_ORDER = order

ns.Constants = constants
