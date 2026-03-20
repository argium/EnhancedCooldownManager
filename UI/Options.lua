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

local function createPreviewBlock(parent, width, height, point, relativeTo, relativePoint, x, y, color)
    local block = parent:CreateTexture(nil, "ARTWORK")
    if type(block.SetColorTexture) == "function" then
        block:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    end
    block:SetSize(width, height)
    block:SetPoint(point, relativeTo, relativePoint, x, y)
    return block
end

local function createPreviewBars(parent, positions)
    for _, pos in ipairs(positions) do
        createPreviewBlock(parent, pos.width, pos.height, "TOPLEFT", parent, "TOPLEFT", pos.x, pos.y, pos.color)
    end
end

local function createPositioningExamplesCanvas()
    if type(CreateFrame) ~= "function" then
        return {}
    end

    local frame = CreateFrame("Frame")
    frame:SetHeight(C.POSITION_MODE_EXPLAINER_HEIGHT)

    local columns = {
        {
            title = C.POSITION_MODE_EXPLAINER_TITLE_ATTACHED,
            caption = C.POSITION_MODE_EXPLAINER_CAPTION_ATTACHED,
            build = function(preview)
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 18, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 36, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 54, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBars(preview, {
                    { x = 12, y = -38, width = 72, height = 10, color = { 0.22, 0.74, 0.98, 1 } },
                    { x = 12, y = -52, width = 72, height = 10, color = { 0.65, 0.41, 0.96, 1 } },
                    { x = 12, y = -66, width = 72, height = 10, color = { 0.30, 0.82, 0.52, 1 } },
                })
            end,
        },
        {
            title = C.POSITION_MODE_EXPLAINER_TITLE_DETACHED,
            caption = C.POSITION_MODE_EXPLAINER_CAPTION_DETACHED,
            build = function(preview)
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 10, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 28, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 46, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 2, 26, "TOPLEFT", preview, "TOPLEFT", 78, -34, { 0.95, 0.95, 0.95, 0.65 })
                createPreviewBlock(preview, 26, 2, "TOPLEFT", preview, "TOPLEFT", 66, -22, { 0.95, 0.95, 0.95, 0.65 })
                createPreviewBars(preview, {
                    { x = 92, y = -16, width = 60, height = 10, color = { 0.22, 0.74, 0.98, 1 } },
                    { x = 92, y = -30, width = 60, height = 10, color = { 0.65, 0.41, 0.96, 1 } },
                    { x = 92, y = -44, width = 60, height = 10, color = { 0.30, 0.82, 0.52, 1 } },
                })
            end,
        },
        {
            title = C.POSITION_MODE_EXPLAINER_TITLE_FREE,
            caption = C.POSITION_MODE_EXPLAINER_CAPTION_FREE,
            build = function(preview)
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 14, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 32, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 50, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBars(preview, {
                    { x = 6, y = -42, width = 52, height = 10, color = { 0.22, 0.74, 0.98, 1 } },
                    { x = 76, y = -26, width = 54, height = 10, color = { 0.65, 0.41, 0.96, 1 } },
                    { x = 56, y = -64, width = 58, height = 10, color = { 0.30, 0.82, 0.52, 1 } },
                })
            end,
        },
    }

    local columnWidth = 170
    local previewWidth = 156
    local previewHeight = 82
    local leftInset = 8

    for index, column in ipairs(columns) do
        local columnFrame = CreateFrame("Frame", nil, frame)
        columnFrame:SetSize(columnWidth, C.POSITION_MODE_EXPLAINER_HEIGHT)
        columnFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", leftInset + ((index - 1) * columnWidth), 0)

        local title = columnFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", columnFrame, "TOP", 0, 0)
        title:SetText(column.title)

        local preview = CreateFrame("Frame", nil, columnFrame)
        preview:SetSize(previewWidth, previewHeight)
        preview:SetPoint("TOP", title, "BOTTOM", 0, -6)

        local previewBg = preview:CreateTexture(nil, "BACKGROUND")
        previewBg:SetAllPoints(preview)
        if type(previewBg.SetColorTexture) == "function" then
            previewBg:SetColorTexture(0.08, 0.08, 0.08, 0.65)
        end

        column.build(preview)

        local caption = columnFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        caption:SetPoint("TOP", preview, "BOTTOM", 0, -6)
        caption:SetPoint("LEFT", columnFrame, "LEFT", 8, 0)
        caption:SetPoint("RIGHT", columnFrame, "RIGHT", -8, 0)
        caption:SetJustifyH("LEFT")
        caption:SetWordWrap(true)
        caption:SetText(column.caption)
    end

    return frame
end

local function openLayoutPage()
    local categoryID = ECM.SettingsBuilder.GetSubcategoryID(C.LAYOUT_SUBCATEGORY)
    if categoryID then
        Settings.OpenToCategory(categoryID)
    end
end

local function createLayoutBreadcrumbArgs(order)
    order = order or 10
    return {
        layoutMovedButton = {
            type = "button",
            name = C.LAYOUT_PAGE_MOVED_INFO_VALUE,
            buttonText = C.LAYOUT_PAGE_MOVED_BUTTON_TEXT,
            onClick = openLayoutPage,
            order = order,
        },
    }
end

--- Gets the nested value from table using dot-separated path
---@param tbl table The table to get the value from
---@param path string The dot-separated path to the value
---@return any The value at the specified path, or nil if any part of the path is invalid
local function getNestedValue(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then
            return nil
        end
        local val = current[segment]
        if val == nil then
            local num = tonumber(segment)
            if num then
                val = current[num]
            end
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
            if current[resolved] == nil then
                current[resolved] = {}
            end
            current = current[resolved]
        end
        lastKey = segment
    end
    -- Resolve final key the same way
    local resolved = lastKey
    if current[lastKey] == nil then
        local num = tonumber(lastKey)
        if num then
            resolved = num
        end
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

local function setModuleEnabledValue(moduleName, value, setting)
    if setting and type(setting.SetValueNoCallback) == "function" then
        setting:SetValueNoCallback(value)
        return
    end

    local profile = ns.Addon and ns.Addon.db and ns.Addon.db.profile
    local configKey = moduleName:sub(1, 1):lower() .. moduleName:sub(2)
    local moduleConfig = profile and profile[configKey]
    if moduleConfig then
        moduleConfig.enabled = value
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
            ns.Addon:EnableModule(moduleName)
            return
        end

        if requiresReload then
            -- Some modules require a reload to disable them. In those cases, the user can click accept or cancel. Cancelling will switch the module back on.
            setModuleEnabledValue(moduleName, true, setting)
            ns.Addon:ConfirmReloadUI(requiresReload, function()
                -- On accept, disable the module and set the toggle to false
                setModuleEnabledValue(moduleName, false, setting)
                ns.Addon:DisableModule(moduleName)
            end, function()
                -- On cancel, revert the toggle back to enabled
                setModuleEnabledValue(moduleName, true, setting)
            end)
            return
        end

        ns.Addon:DisableModule(moduleName)
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
    local breadcrumbArgs = createLayoutBreadcrumbArgs(layoutOrder)

    local args = {
        layoutMovedButton = breadcrumbArgs.layoutMovedButton,
        appearanceHeader = { type = "header", name = "Appearance", disabled = isDisabled, order = appearanceOrder },
        heightOverride = { type = "heightOverride", disabled = isDisabled, order = appearanceOrder + 1 },
        fontOverride = { type = "fontOverride", disabled = isDisabled, order = appearanceOrder + 2 },
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
    OpenLayoutPage = openLayoutPage,
    CreateLayoutBreadcrumbArgs = createLayoutBreadcrumbArgs,
    CreatePositioningExamplesCanvas = createPositioningExamplesCanvas,
    CreateBarArgs = createBarArgs,
}

--------------------------------------------------------------------------------
-- SettingsBuilder instance
--------------------------------------------------------------------------------

local LSB = LibStub("LibSettingsBuilder-1.0")

ECM.SettingsBuilder = LSB:New({
    pathAdapter = LSB.PathAdapter({
        getStore = function()
            return ns.Addon.db and ns.Addon.db.profile
        end,
        getDefaults = function()
            return ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
        end,
        getNestedValue = getNestedValue,
        setNestedValue = setNestedValue,
    }),
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
                return ns.Addon.db.profile.global.font
            end,
            fontSizeFallback = function()
                return ns.Addon.db.profile.global.fontSize
            end,
            fontTemplate = LSMW.FONT_PICKER_TEMPLATE,
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

    -- About section renders on the root category (no subcategory entry)
    ns.OptionsSections["About"].RegisterSettings(SB)

    -- Register subcategory sections in display order
    local sectionOrder = {
        "General",
        "Layout",
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
    local categoryID = ECM.SettingsBuilder.GetSubcategoryID("General") or ECM.SettingsBuilder.GetRootCategoryID()
    if categoryID then
        Settings.OpenToCategory(categoryID)
    end
end
