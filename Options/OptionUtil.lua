-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local LSB = LibStub("LibSettingsBuilder-1.0")
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

local function ApplyPositionModeToBar(cfg, mode)
    cfg.anchorMode = mode
end

local function IsAnchorModeFree(cfg)
    return cfg and cfg.anchorMode == ECM.Constants.ANCHORMODE_FREE
end

local function SetModuleEnabled(moduleName, enabled)
    local module = mod[moduleName] or ECM[moduleName]
    if not module then return end

    if enabled and not module:IsEnabled() then
        module:Enable()
    elseif not enabled and module:IsEnabled() then
        module:Disable()
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

--- Opens the Blizzard ColorPickerFrame with the given color.
--- Calls onChange with the selected {r, g, b, a} table on both accept and cancel.
---@param currentColor {r:number, g:number, b:number, a:number|nil}
---@param hasOpacity boolean
---@param onChange fun(color: {r:number, g:number, b:number, a:number})
local function OpenColorPicker(currentColor, hasOpacity, onChange)
    ColorPickerFrame:SetupColorPickerAndShow({
        r = currentColor.r, g = currentColor.g, b = currentColor.b,
        opacity = currentColor.a,
        hasOpacity = hasOpacity,
        swatchFunc = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
            onChange({ r = r, g = g, b = b, a = a })
        end,
        cancelFunc = function(prev)
            onChange({ r = prev.r, g = prev.g, b = prev.b, a = hasOpacity and prev.opacity or 1 })
        end,
    })
end

--- Returns a closure that checks if the module at configPath is disabled.
---@param configPath string e.g. "powerBar"
---@return fun(): boolean
local function GetIsDisabledDelegate(configPath)
    local enabledPath = configPath .. ".enabled"
    return function()
        return not GetNestedValue(mod.db.profile, enabledPath)
    end
end

ECM.OptionUtil = {
    GetNestedValue = GetNestedValue,
    IsAnchorModeFree = IsAnchorModeFree,
    SetModuleEnabled = SetModuleEnabled,
    GetCurrentClassSpec = GetCurrentClassSpec,
    OpenColorPicker = OpenColorPicker,
    GetIsDisabledDelegate = GetIsDisabledDelegate,
}

--------------------------------------------------------------------------------
-- SettingsBuilder instance
--------------------------------------------------------------------------------

ECM.SettingsBuilder = LSB:New({
    getProfile = function() return mod.db and mod.db.profile end,
    getDefaults = function() return mod.db and mod.db.defaults and mod.db.defaults.profile end,
    getNestedValue = GetNestedValue,
    setNestedValue = SetNestedValue,
    varPrefix = "ECM",
    onChanged = function(spec)
        if spec.layout ~= false then
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    compositeDefaults = {
        FontOverrideGroup = {
            fontValues = LSMW.GetFontValues,
            fontFallback = function()
                local profile = mod.db and mod.db.profile
                return profile and GetNestedValue(profile, "global.font") or "Expressway"
            end,
            fontSizeFallback = function()
                local profile = mod.db and mod.db.profile
                return profile and GetNestedValue(profile, "global.fontSize") or 11
            end,
            fontTemplate = LSMW.FONT_PICKER_TEMPLATE,
        },
        PositioningGroup = {
            positionModes = {
                [ECM.Constants.ANCHORMODE_CHAIN] = "Locked to Cooldown Manager",
                [ECM.Constants.ANCHORMODE_FREE] = "Movable via Edit Mode",
            },
            isAnchorModeFree = IsAnchorModeFree,
            applyPositionMode = ApplyPositionModeToBar,
        },
    },
})
