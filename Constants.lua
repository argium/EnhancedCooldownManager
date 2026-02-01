local _,  ns = ...

local constants = {
    PowerBar = "PowerBar",
    ResourceBar = "ResourceBar",
    RuneBar = "RuneBar",
    VIEWER = "EssentialCooldownViewer",

    DEFAULT_REFRESH_FREQUENCY = 0.066,
    DEFAULT_BAR_HEIGHT = 20,
    DEFAULT_BAR_WIDTH = 250,
    DEFAULT_BG_COLOR = { r = 0.08, g = 0.08, b = 0.08, a = 0.65 },
    DEFAULT_STATUSBAR_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar",

    COLOR_WHITE = { r = 1, g = 1, b = 1, a = 1 },

    SHOW_MANABAR_FOR_DPS_CLASSES = { MAGE = true, WARLOCK = true, DRUID = true },

    CONFIG_SECTION_GLOBAL = "global",
}

local order = { constants.PowerBar, constants.ResourceBar, constants.RuneBar }
constants.CHAIN_ORDER = order

ns.Constants = constants
