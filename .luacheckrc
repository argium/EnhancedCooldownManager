std = "lua51"
max_line_length = false
exclude_files = {
    "libs/",
    "Tests/",
    ".luacheckrc"
}

ignore = {
    "212/self", -- unused argument 'self'
    "212/..."   -- unused variable length argument
}

globals = {
    "ECM",
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
    "C_AddOns", "C_CVar", "C_Item", "C_Spell", "C_SpellBook", "C_Timer", "C_UnitAuras",
    "CANCEL",
    "ColorPickerFrame",
    "CLOSE",
    "CreateDataProvider",
    "CreateFrame",
    "CurveConstants",
    "DevTool",
    "EditModeManagerFrame",
    "Enum",
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
    "Settings",
    "SETTINGS_DEFAULTS",
    "StaticPopup_Show",
    "UIParent",
    "UnitCanAssist", "UnitCanAttack", "UnitClass", "UnitExists", "UnitInVehicle", "UnitIsDead", "UnitName",
    "UnitPower", "UnitPowerMax", "UnitPowerPercent", "UnitPowerType",
    "YES",
}
