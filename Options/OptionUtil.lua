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
    if not module then return end

    if enabled and not module:IsEnabled() then
        if module.Enable then
            module:Enable()
        else
            mod:EnableModule(moduleName)
        end
    elseif not enabled and module:IsEnabled() then
        if module.Disable then
            module:Disable()
        elseif mod.DisableModule then
            mod:DisableModule(moduleName)
        end
    end
end

--- Normalize a path key by converting numeric strings to numbers, leaving other strings unchanged.
---@param key string The path key to normalize
---@return number|string The normalized key
local function NormalizePathKey(key)
    return tonumber(key) or key
end

--- Gets the nested value from table using dot-separated path
---@param tbl table The table to get the value from
---@param path string The dot-separated path to the value
---@return any The value at the specified path, or nil if any part of the path is invalid
local function GetNestedValue(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[NormalizePathKey(segment)]
    end
    return current
end

--- Sets a nested value in a table using a dot-separated path, creating intermediate tables as needed.
---@param tbl table The table to set the value in
---@param path string The dot-separated path to the value
---@param value any The value to set at the specified path
local function SetNestedValue(tbl, path, value)
    local segments = {}
    for segment in path:gmatch("[^.]+") do
        segments[#segments + 1] = segment
    end
    local current = tbl
    for i = 1, #segments - 1 do
        local key = NormalizePathKey(segments[i])
        if current[key] == nil then
            current[key] = {}
        end
        current = current[key]
    end
    current[NormalizePathKey(segments[#segments])] = value
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
