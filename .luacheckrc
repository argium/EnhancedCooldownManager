std = "lua51"
max_line_length = false
exclude_files = {
    "Libs/AceAddon-3.0/",
    "Libs/AceDB-3.0/",
    "Libs/AceEvent-3.0/",
    "Libs/CallbackHandler-1.0/",
    "Libs/LibDeflate/",
    "Libs/LibEditMode/",
    "Libs/LibSerialize/",
    "Libs/LibSharedMedia-3.0/",
    "Libs/LibStub/",
    ".luacheckrc"
}

ignore = {
    "212/self", -- unused argument 'self'
    "212/..."   -- unused variable length argument
}

files = {
    ["**/Tests/**"] = {
        std = "+busted",
        read_globals = {
            assert = { other_fields = true },
            mock = { other_fields = true },
            spy = { other_fields = true },
            stub = { other_fields = true }
        }
    }
}

globals = {
    "LSB_DEBUG",
    "LibLSMSettingsWidgets_FontPickerMixin",
    "LibLSMSettingsWidgets_TexturePickerMixin",
    "SlashCmdList",
    "hash_SlashCmdList",
    "StaticPopupDialogs",
    "UISpecialFrames"
}

read_globals = {'C_PlayerInfo','DEFAULT_CHAT_FRAME', 'MenuUtil', 'GameTooltip', 'GameTooltip_Hide', 'WorldFrame', 'GameTooltip_OnLoad', 'GetScreenWidth', 'GetScreenHeight', 'HideUIPanel', 'ChatFontNormal', 'GameFontNormalSmall', 'GameFontHighlightSmall', 'EnumUtil', 'TooltipDataProcessor', 'C_EventUtils', 'ItemRefTooltip', 'ShowUIPanel', 'GetPlayerInfoByGUID', 'C_FriendList', 'NUM_CHAT_WINDOWS', 'COMBATLOG', 'WHO_LIST_FORMAT', 'WHO_LIST_GUILD_FORMAT', 'ERR_FRIEND_ONLINE_SS', 'GetNumGroupMembers', 'IsInRaid', 'C_RestrictedActions',
    "bit",
    "ceil", "floor",
    "mod",
    "max",
    "table", "tinsert", "wipe", "copy", "tContains",
    "string", "tostringall", "strtrim", "strmatch", "strsplit",
    "pcall", "xpcall", "geterrorhandler",
    "date", "time", "GetTime",

    -- Externals
    "AddonCompartmentFrame",
    "C_AddOns", "C_CVar", "C_EditMode", "C_Item", "C_PartyInfo", "C_PvP", "C_Spell", "C_SpellBook", "C_Timer", "C_UnitAuras",
    "CANCEL",
    "CreateAtlasMarkup",
    "ColorPickerFrame",
    "CLOSE",
    "CreateColorFromHexString",
    "CreateDataProvider",
    "CreateFrame",
    "CreateTextureMarkup",
    "CreateScrollBoxListLinearView",
    "CreateSettingsButtonInitializer",
    "CreateSettingsListSectionHeaderInitializer",
    "CurveConstants",
    "DevTool",
    "EditModeManagerFrame",
    "Enum",
    "GameFontHighlight",
    "GameFontNormal",
    "GetInventoryItemCooldown", "GetInventoryItemID", "GetInventoryItemTexture", "GetRuneCooldown",
    "GetShapeshiftForm", "GetSpecialization", "GetSpecializationInfo", "GetSpecializationRole",
    "hooksecurefunc",
    "InCombatLockdown", "IsControlKeyDown", "IsInInstance", "IsMounted", "IsResting",
    "issecrettable", "issecretvalue",
    "LibStub",
    "NO",
    "OKAY",
    "ReloadUI",
    "ScrollUtil",
    "Settings",
    "SettingsDropdownControlMixin",
    "SettingsListElementMixin",
    "SettingsPanel",
    "SettingsSliderControlMixin",
    "SETTINGS_DEFAULTS",
    "StaticPopup_Show",
    "UIParent",
    "UnitCanAssist", "UnitCanAttack", "UnitClass", "UnitExists", "UnitIsPlayer", "UnitName",  "UnitInVehicle", "UnitOnTaxi", "UnitIsDead", "UnitName", "UnitRace",
    "UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitPowerType",
    "YES",
    "MinimalSliderWithSteppersMixin",
}
