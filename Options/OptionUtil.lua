-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Gets a module config value for options with a fallback default.
---@param self ECM_ItemIconsModule
---@param key string
---@param defaultValue boolean
---@return boolean
local function GetOptionValue(self, key, defaultValue)
    local moduleConfig = self:GetModuleConfig()
    if moduleConfig and moduleConfig[key] ~= nil then
        return moduleConfig[key]
    end

    return defaultValue
end

--- Returns true when non-enable options should be disabled.
---@param self ECM_ItemIconsModule
---@return boolean
local function IsOptionsDisabled(self)
    return not GetOptionValue(self, "enabled", true)
end

local POSITION_MODE_TEXT = {
    [ECM.Constants.ANCHORMODE_CHAIN] = "Position Automatically",
    [ECM.Constants.ANCHORMODE_FREE] = "Free Positioning",
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
--- This allows config paths to use either numeric indices or string keys interchangeably.
--- @param key string The path key to normalize
--- @return number|string The normalized key, as a number if it was a numeric string, or unchanged if not
local function NormalizePathKey(key)
    local numberKey = tonumber(key)
    if numberKey then
        return numberKey
    end
    return key
end

--- Gets the nested value from table using dot-separated path
--- @param tbl table The table to get the value from
--- @param path string The dot-separated path to the value (e.g., "powerBar.width")
--- @return any The value at the specified path, or nil if any part of the path is invalid
local function GetNestedValue(tbl, path)
    local current = tbl
    for resource in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[NormalizePathKey(resource)]
    end
    return current
end

--- Splits a dot-separated path into its individual components.
--- For example, "powerBar.width" would be split into {"powerBar", "width"}.
--- @param path string The dot-separated path to split
--- @return table An array of path components
local function SplitPath(path)
    local resources = {}
    for resource in path:gmatch("[^.]+") do
        table.insert(resources, resource)
    end
    return resources
end

--- Sets a nested value in a table using a dot-separated path, creating intermediate tables as needed.
--- For example, setting the path "powerBar.width" to 200 would create the tables if they don't exist and set powerBar.width = 200.
--- @param tbl table The table to set the value in
--- @param path string The dot-separated path to the value (e.g., "powerBar.width")
--- @param value any The value to set at the specified path
--- @return nil
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

--- Checks if value differs from default
--- @param path string The dot-separated config path to check (e.g., "powerBar.width")
--- @return boolean True if the current value differs from the default value, false otherwise
local function IsValueChanged(path)
    local profile = mod.db and mod.db.profile
    local defaults = mod.db and mod.db.defaults and mod.db.defaults.profile
    if not profile or not defaults then return false end

    local currentVal = GetNestedValue(profile, path)
    local defaultVal = GetNestedValue(defaults, path)

    return not ECM_DeepEquals(currentVal, defaultVal)
end

--- Resets the value at the specified config path to its default value.
--- @param path string The dot-separated config path to reset (e.g., "powerBar.width")
--- @return nil
local function ResetToDefault(path)
    local profile = mod.db and mod.db.profile
    local defaults = mod.db and mod.db.defaults and mod.db.defaults.profile
    if not profile or not defaults then return end

    local defaultVal = GetNestedValue(defaults, path)
    SetNestedValue(profile, path, ECM_CloneValue(defaultVal))
end

--- Generates a reset handler function for a specific config path, which resets that path to its default value and optionally calls a refresh function.
--- @param path string The dot-separated config path to reset (e.g., "powerBar.width")
--- @param refreshFunc function|nil An optional function to call after resetting the value, for refreshing the UI or performing additional updates
--- @return function A function that, when called, will reset the specified config path to its default value and call the refresh function if provided
local function MakeResetHandler(path, refreshFunc)
    return function()
        ResetToDefault(path)
        if refreshFunc then refreshFunc() end
        ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
    end
end

--- Gets the current player's class and specialization information.
--- @return number classID The player's class ID (e.g., 1 for Warrior, 2 for Paladin, etc.)
--- @return number specIndex The player's current specialization index (1-based), or nil if not applicable
--- @return string localisedClassName The player's localized class name (e.g., "Warrior", "Paladin", etc.)
--- @return string specName The player's current specialization name (e.g., "Arms", "Fury", etc.), or "None" if not applicable
local function GetCurrentClassSpec()
    local localisedClassName, className, classID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specName
    if specIndex then
        _, specName = GetSpecializationInfo(specIndex)
    end
    return classID, specIndex, localisedClassName or "Unknown", specName or "None"
end

--- Generates positioning settings for a bar (width, offsetX, offsetY with reset buttons).
--- @param configPath string The config path (e.g., "powerBar", "buffBars")
--- @param options table Options: { includeOffsets = true, widthLabel = "Width", widthDesc = "..." }
--- @return table args table for positioning settings
local function MakePositioningSettingsArgs(configPath, options)
    options = options or {}
    local includeOffsets = options.includeOffsets ~= false  -- Default true
    local widthLabel = options.widthLabel or "Width"
    local widthDesc = options.widthDesc or "Width when free positioning is enabled."
    local offsetXDesc = options.offsetXDesc or "\nHorizontal offset when free positioning is enabled."
    local offsetYDesc = options.offsetYDesc or "\nVertical offset when free positioning is enabled."

    local db = mod.db
    local args = {
        widthDesc = {
            type = "description",
            name = widthDesc,
            order = 3,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
        },
        width = {
            type = "range",
            name = widthLabel,
            order = 4,
            width = "double",
            min = 100,
            max = 600,
            step = 10,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg.width or ECM.Constants.DEFAULT_BAR_WIDTH
            end,
            set = function(_, val)
                local cfg = GetNestedValue(db.profile, configPath)
                cfg.width = val
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        },
        widthReset = {
            type = "execute",
            name = "X",
            order = 5,
            width = 0.3,
            hidden = function()
                return not IsAnchorModeFree(GetNestedValue(db.profile, configPath))
                    or not IsValueChanged(configPath .. ".width")
            end,
            func = MakeResetHandler(configPath .. ".width"),
        },
    }

    if includeOffsets then
        args.offsetXDesc = {
            type = "description",
            name = offsetXDesc,
            order = 6,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
        }
        args.offsetX = {
            type = "range",
            name = "Offset X",
            order = 7,
            width = "double",
            min = -800,
            max = 800,
            step = 1,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg.offsetX or 0
            end,
            set = function(_, val)
                local cfg = GetNestedValue(db.profile, configPath)
                cfg.offsetX = val ~= 0 and val or nil
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        }
        args.offsetXReset = {
            type = "execute",
            name = "X",
            order = 8,
            width = 0.3,
            hidden = function()
                return not IsAnchorModeFree(GetNestedValue(db.profile, configPath))
                    or not IsValueChanged(configPath .. ".offsetX")
            end,
            func = MakeResetHandler(configPath .. ".offsetX"),
        }
        args.offsetYDesc = {
            type = "description",
            name = offsetYDesc,
            order = 9,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
        }
        args.offsetY = {
            type = "range",
            name = "Offset Y",
            order = 10,
            width = "double",
            min = -800,
            max = 800,
            step = 1,
            hidden = function() return not IsAnchorModeFree(GetNestedValue(db.profile, configPath)) end,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg.offsetY or 0
            end,
            set = function(_, val)
                local cfg = GetNestedValue(db.profile, configPath)
                cfg.offsetY = val ~= 0 and val or nil
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        }
        args.offsetYReset = {
            type = "execute",
            name = "X",
            order = 11,
            width = 0.3,
            hidden = function()
                return not IsAnchorModeFree(GetNestedValue(db.profile, configPath))
                    or not IsValueChanged(configPath .. ".offsetY")
            end,
            func = MakeResetHandler(configPath .. ".offsetY"),
        }
    end

    return args
end

--- Generates a full positioning group (mode selector + width/offset settings).
--- @param configPath string The config path (e.g., "powerBar", "buffBars")
--- @param order number The order of the group in the options panel
--- @param options table|nil Options forwarded to MakePositioningSettingsArgs plus optional modeDesc
--- @return table AceConfig group table
local function MakePositioningGroup(configPath, order, options)
    options = options or {}
    local db = mod.db

    local args = {
        modeDesc = options.modeDesc and {
            type = "description",
            name = options.modeDesc,
            order = 0.5,
        } or nil,
        modeSelector = {
            type = "select",
            name = "",
            order = 1,
            width = "full",
            dialogControl = "ECM_PositionModeSelector",
            values = POSITION_MODE_TEXT,
            get = function()
                local cfg = GetNestedValue(db.profile, configPath)
                return cfg and cfg.anchorMode or ECM.Constants.ANCHORMODE_CHAIN
            end,
            set = function(_, val)
                ApplyPositionModeToBar(GetNestedValue(db.profile, configPath), val)
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
            end,
        },
    }

    local settingsArgs = MakePositioningSettingsArgs(configPath, options)
    for k, v in pairs(settingsArgs) do
        args[k] = v
    end

    return {
        type = "group",
        name = "Positioning",
        inline = true,
        order = order,
        args = args,
    }
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

ECM.OptionUtil = {
    IsOptionsDisabled = IsOptionsDisabled,
    GetOptionValue = GetOptionValue,
    GetNestedValue = GetNestedValue,
    IsValueChanged = IsValueChanged,
    MakeResetHandler = MakeResetHandler,
    ApplyPositionModeToBar = ApplyPositionModeToBar,
    IsAnchorModeFree = IsAnchorModeFree,
    SetModuleEnabled = SetModuleEnabled,
    GetCurrentClassSpec = GetCurrentClassSpec,
    MakePositioningSettingsArgs = MakePositioningSettingsArgs,
    MakePositioningGroup = MakePositioningGroup,
    POSITION_MODE_TEXT = POSITION_MODE_TEXT,
}
