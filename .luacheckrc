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

globals = {
    "LSB_DEBUG",
    "LibLSMSettingsWidgets_FontPickerMixin",
    "LibLSMSettingsWidgets_TexturePickerMixin",
    "SlashCmdList",
    "hash_SlashCmdList",
    "StaticPopupDialogs",
    "UISpecialFrames"
}

read_globals = {
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
    "C_AddOns", "C_CVar", "C_EditMode", "C_Item", "C_Spell", "C_SpellBook", "C_Timer", "C_UnitAuras",
    "CANCEL",
    "ColorPickerFrame",
    "CLOSE",
    "CreateColorFromHexString",
    "CreateDataProvider",
    "CreateFrame",
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
    "InCombatLockdown", "IsControlKeyDown", "IsDelveInProgress", "IsInInstance", "IsMounted", "IsResting",
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
    "UnitCanAssist", "UnitCanAttack", "UnitClass", "UnitExists", "UnitInVehicle", "UnitOnTaxi", "UnitIsDead", "UnitName",
    "UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitPowerType",
    "YES",
    "MinimalSliderWithSteppersMixin",
}
