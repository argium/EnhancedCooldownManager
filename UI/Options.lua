-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

--------------------------------------------------------------------------------
-- Option helpers
--------------------------------------------------------------------------------

local function isAnchorModeFree(cfg)
    return cfg and cfg.anchorMode == C.ANCHORMODE_FREE
end

--- Gets the nested value from table using dot-separated path
---@param tbl table The table to get the value from
---@param path string The dot-separated path to the value
---@return any The value at the specified path, or nil if any part of the path is invalid
local function getNestedValue(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        local val = current[segment]
        if val == nil then
            local num = tonumber(segment)
            if num then val = current[num] end
        end
        current = val
    end
    return current
end

--- Sets a nested value in a table using a dot-separated path, creating intermediate tables as needed.
---@param tbl table The table to set the value in
---@param path string The dot-separated path to the value
---@param value any The value to set at the specified path
local function setNestedValue(tbl, path, value)
    local current, lastKey = tbl, nil
    for segment in path:gmatch("[^.]+") do
        if lastKey then
            -- Resolve the key type: prefer existing key, fall back to numeric
            local resolved = lastKey
            if current[lastKey] == nil then
                local num = tonumber(lastKey)
                if num and current[num] ~= nil then
                    resolved = num
                end
            end
            if current[resolved] == nil then current[resolved] = {} end
            current = current[resolved]
        end
        lastKey = segment
    end
    -- Resolve final key the same way
    local resolved = lastKey
    if current[lastKey] == nil then
        local num = tonumber(lastKey)
        if num then resolved = num end
    end
    current[resolved] = value
end

--- Gets the current player's class and specialization information.
---@return number classID
---@return number specIndex
---@return string localisedClassName
---@return string specName
---@return string className
local function getCurrentClassSpec()
    local localisedClassName, className, classID = UnitClass("player")
    local specIndex = GetSpecialization()
    local specName
    if specIndex then
        _, specName = GetSpecializationInfo(specIndex)
    end
    return classID, specIndex, localisedClassName or "Unknown", specName or "None", className
end

--- Opens the Blizzard ColorPickerFrame with the given color.
--- Calls onChange with the selected {r, g, b, a} table on both accept and cancel.
---@param currentColor {r:number, g:number, b:number, a:number|nil}
---@param hasOpacity boolean
---@param onChange fun(color: {r:number, g:number, b:number, a:number})
local function openColorPicker(currentColor, hasOpacity, onChange)
    ColorPickerFrame:SetupColorPickerAndShow({
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
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
local function getIsDisabledDelegate(configPath)
    local enabledPath = configPath .. ".enabled"
    return function()
        return not getNestedValue(ns.Addon.db.profile, enabledPath)
    end
end

--- Creates a standard onSet handler for module enable/disable toggles.
--- For modules that require a reload to disable, pass requiresReload with a message.
---@param moduleName string The module name (e.g., "PowerBar")
---@param requiresReload string|nil If set, disabling shows a reload confirmation with this message
---@return fun(value: boolean, setting: table)
local function createModuleEnabledHandler(moduleName, requiresReload)
    return function(value, setting)
        if value then
            setting:SetValue(true)
            ns.Addon:EnableModule(moduleName)
            return
        elseif requiresReload then
            -- Some modules require a reload to disable them. In those cases, the user can click accept or cancel. Cancelling will switch the module back on.
            ns.Addon:ConfirmReloadUI(
                requiresReload,
                function()
                    -- On accept, disable the module and set the toggle to false
                    setting:SetValue(false)
                    ns.Addon:DisableModule(moduleName)
                end,
                function()
                    -- On cancel, revert the toggle back to enabled
                    setting:SetValue(true)
                end)
        else
            setting:SetValue(false)
            ns.Addon:DisableModule(moduleName)
        end
    end
end

--- Generates standard layout and appearance args shared by bar-type modules.
--- Callers can override individual entries or omit features via the options table.
---@param isDisabled fun(): boolean
---@param options table|nil { showText: boolean, border: boolean, layoutOrder: number, appearanceOrder: number }
---@return table args Partial args table to merge into RegisterFromTable
local function createBarArgs(isDisabled, options)
    options = options or {}
    local layoutOrder = options.layoutOrder or 10
    local appearanceOrder = options.appearanceOrder or 20

    local args = {
        layoutHeader     = { type = "header", name = "Layout", disabled = isDisabled, order = layoutOrder },
        positioning      = { type = "positioning", disabled = isDisabled, order = layoutOrder + 1 },
        appearanceHeader = { type = "header", name = "Appearance", disabled = isDisabled, order = appearanceOrder },
        heightOverride   = { type = "heightOverride", disabled = isDisabled, order = appearanceOrder + 1 },
        fontOverride     = { type = "fontOverride", disabled = isDisabled, order = appearanceOrder + 2 },
    }

    if options.showText ~= false then
        args.showText = {
            type = "toggle",
            path = "showText",
            name = "Show text",
            desc = "Display the current value on the bar.",
            disabled = isDisabled,
            order = appearanceOrder + 1,
        }
        args.heightOverride.order = appearanceOrder + 2
        args.fontOverride.order = appearanceOrder + 3
    end

    if options.border ~= false then
        args.border = { type = "border", path = "border", disabled = isDisabled, order = args.fontOverride.order + 1 }
    end

    return args
end

ECM.OptionUtil = {
    GetNestedValue = getNestedValue,
    SetNestedValue = setNestedValue,
    IsAnchorModeFree = isAnchorModeFree,
    GetCurrentClassSpec = getCurrentClassSpec,
    OpenColorPicker = openColorPicker,
    GetIsDisabledDelegate = getIsDisabledDelegate,
    CreateModuleEnabledHandler = createModuleEnabledHandler,
    CreateBarArgs = createBarArgs,
}

--------------------------------------------------------------------------------
-- SettingsBuilder instance
--------------------------------------------------------------------------------

ECM.SettingsBuilder = LibStub("LibSettingsBuilder-1.0"):New({
    getProfile = function() return ns.Addon.db and ns.Addon.db.profile end,
    getDefaults = function() return ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile end,
    getNestedValue = getNestedValue,
    setNestedValue = setNestedValue,
    varPrefix = "ECM",
    onChanged = function(spec)
        if spec.layout ~= false then
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    compositeDefaults = {
        FontOverrideGroup = {
            fontValues = LSMW.GetFontValues,
            fontFallback = function() return ns.Addon.db.profile.global.font end,
            fontSizeFallback = function() return ns.Addon.db.profile.global.fontSize end,
            fontTemplate = LSMW.FONT_PICKER_TEMPLATE,
        },
        PositioningGroup = {
            positionModes = {
                [C.ANCHORMODE_CHAIN] = "Locked to Cooldown Manager",
                [C.ANCHORMODE_FREE] = "Manual",
            },
            isAnchorModeFree = isAnchorModeFree,
            applyPositionMode = function(cfg, mode) cfg.anchorMode = mode end,
        },
    },
})

--------------------------------------------------------------------------------
-- Options module
--------------------------------------------------------------------------------

ns.OptionsSections = ns.OptionsSections or {}

local Options = ns.Addon:NewModule("Options")

function Options:OnInitialize()
    local SB = ECM.SettingsBuilder
    SB.CreateRootCategory(C.ADDON_NAME)

    -- Register sections in display order
    local sectionOrder = {
        "General",
        "PowerBar",
        "ResourceBar",
        "RuneBar",
        "BuffBars",
        "ItemIcons",
        "Profile",
        "Advanced Options",
    }

    for _, key in ipairs(sectionOrder) do
        local section = ns.OptionsSections[key]
        if section and section.RegisterSettings then
            section.RegisterSettings(SB)
        end
    end

    SB.SetRootRedirect("General") -- TODO: the redirect doesn't work. replace it with the old about section.
    SB.RegisterCategories()

    local db = ns.Addon.db
    db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
end

function Options:OnProfileChanged()
    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
end

function Options:OpenOptions()
    local categoryID = ECM.SettingsBuilder.GetSubcategoryID("General")
        or ECM.SettingsBuilder.GetRootCategoryID()
    if categoryID then
        Settings.OpenToCategory(categoryID)
    end
end
