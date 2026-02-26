-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local POSITION_MODE_TEXT = {
    [ECM.Constants.ANCHORMODE_CHAIN] = "Automatic",
    [ECM.Constants.ANCHORMODE_FREE] = "Manual",
}

local function ApplyPositionModeToBar(cfg, mode)
    if mode == ECM.Constants.ANCHORMODE_FREE then
        if cfg.width == nil then
            cfg.width = ECM.Constants.DEFAULT_BAR_WIDTH
        end
    end

    cfg.anchorMode = mode
end

local function IsAnchorModeFree(cfg)
    return cfg and cfg.anchorMode == ECM.Constants.ANCHORMODE_FREE
end

local function SetModuleEnabled(moduleName, enabled)
    local module = mod[moduleName] or ECM[moduleName]
    if not module then
        return
    end

    if enabled then
        if not module:IsEnabled() then
            if module.Enable then
                module:Enable()
            else
                mod:EnableModule(moduleName)
            end
        end
    else
        if module:IsEnabled() then
            if module.Disable then
                module:Disable()
            elseif mod.DisableModule then
                mod:DisableModule(moduleName)
            end
        end
    end
end

--- Normalize a path key by converting numeric strings to numbers, leaving other strings unchanged.
---@param key string The path key to normalize
---@return number|string The normalized key
local function NormalizePathKey(key)
    local numberKey = tonumber(key)
    if numberKey then
        return numberKey
    end
    return key
end

--- Gets the nested value from table using dot-separated path
---@param tbl table The table to get the value from
---@param path string The dot-separated path to the value
---@return any The value at the specified path, or nil if any part of the path is invalid
local function GetNestedValue(tbl, path)
    local current = tbl
    for resource in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[NormalizePathKey(resource)]
    end
    return current
end

--- Splits a dot-separated path into its individual components.
---@param path string The dot-separated path to split
---@return table An array of path components
local function SplitPath(path)
    local resources = {}
    for resource in path:gmatch("[^.]+") do
        table.insert(resources, resource)
    end
    return resources
end

--- Sets a nested value in a table using a dot-separated path, creating intermediate tables as needed.
---@param tbl table The table to set the value in
---@param path string The dot-separated path to the value
---@param value any The value to set at the specified path
local function SetNestedValue(tbl, path, value)
    local resources = SplitPath(path)
    local current = tbl
    for i = 1, #resources - 1 do
        local key = NormalizePathKey(resources[i])
        if current[key] == nil then
            current[key] = {}
        end
        current = current[key]
    end
    current[NormalizePathKey(resources[#resources])] = value
end

--- Gets the current player's class and specialization information.
---@return number classID
---@return number specIndex
---@return string localisedClassName
---@return string specName
---@return string className
local function GetCurrentClassSpec()
    local localisedClassName, className, classID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specName
    if specIndex then
        _, specName = GetSpecializationInfo(specIndex)
    end
    return classID, specIndex, localisedClassName or "Unknown", specName or "None", className
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

ECM.OptionUtil = {
    GetNestedValue = GetNestedValue,
    SetNestedValue = SetNestedValue,
    ApplyPositionModeToBar = ApplyPositionModeToBar,
    IsAnchorModeFree = IsAnchorModeFree,
    SetModuleEnabled = SetModuleEnabled,
    GetCurrentClassSpec = GetCurrentClassSpec,
    POSITION_MODE_TEXT = POSITION_MODE_TEXT,
}

--------------------------------------------------------------------------------
-- SettingsBuilder instance (backed by LibSettingsBuilder)
--------------------------------------------------------------------------------

local LSB = LibStub("LibSettingsBuilder-1.0")
local LSMW = LibStub("LibLSMSettingsWidgets-1.0", true)

local SB = LSB:New({
    getProfile = function() return mod.db and mod.db.profile end,
    getDefaults = function() return mod.db and mod.db.defaults and mod.db.defaults.profile end,
    varPrefix = "ECM",
    onChanged = function(spec, value)
        if spec.layout ~= false then
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    getNestedValue = function(tbl, path)
        return GetNestedValue(tbl, path)
    end,
    setNestedValue = function(tbl, path, value)
        return SetNestedValue(tbl, path, value)
    end,
})

local _libModuleEnabledCheckbox = SB.ModuleEnabledCheckbox
SB.ModuleEnabledCheckbox = function(moduleName, spec)
    local merged = {}
    if spec then for k, v in pairs(spec) do merged[k] = v end end
    merged.setModuleEnabled = merged.setModuleEnabled or function(name, enabled)
        return SetModuleEnabled(name, enabled)
    end
    return _libModuleEnabledCheckbox(moduleName, merged)
end

local _libFontOverrideGroup = SB.FontOverrideGroup
SB.FontOverrideGroup = function(sectionPath, spec)
    local merged = {}
    if spec then for k, v in pairs(spec) do merged[k] = v end end
    merged.fontValues = merged.fontValues or (LSMW and LSMW.GetFontValues)
    merged.fontFallback = merged.fontFallback or function()
        local profile = mod.db and mod.db.profile
        return profile and GetNestedValue(profile, "global.font") or "Expressway"
    end
    merged.fontSizeFallback = merged.fontSizeFallback or function()
        local profile = mod.db and mod.db.profile
        return profile and GetNestedValue(profile, "global.fontSize") or 11
    end
    merged.fontTemplate = merged.fontTemplate or (LSMW and LSMW.FONT_PICKER_TEMPLATE)
    return _libFontOverrideGroup(sectionPath, merged)
end

local _libPositioningGroup = SB.PositioningGroup
SB.PositioningGroup = function(configPath, spec)
    local merged = {}
    if spec then for k, v in pairs(spec) do merged[k] = v end end
    merged.positionModes = merged.positionModes or POSITION_MODE_TEXT
    merged.isAnchorModeFree = merged.isAnchorModeFree or function(cfg)
        return IsAnchorModeFree(cfg)
    end
    merged.applyPositionMode = merged.applyPositionMode or function(cfg, mode)
        return ApplyPositionModeToBar(cfg, mode)
    end
    merged.defaultBarWidth = merged.defaultBarWidth or ECM.Constants.DEFAULT_BAR_WIDTH
    return _libPositioningGroup(configPath, merged)
end

ECM.SettingsBuilder = SB

ECM.SharedMediaOptions = LSMW and {
    GetFontValues = LSMW.GetFontValues,
    GetStatusbarValues = LSMW.GetStatusbarValues,
    FONT_PICKER_TEMPLATE = LSMW.FONT_PICKER_TEMPLATE,
    TEXTURE_PICKER_TEMPLATE = LSMW.TEXTURE_PICKER_TEMPLATE,
} or {
    GetFontValues = function() return {} end,
    GetStatusbarValues = function() return {} end,
}
