-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- Shared option-building utilities consumed by all per-module options files.
-- Loaded before Options.lua and all *Options.lua files.

local _, ns = ...
local C = ns.Constants
local L = ns.L
local OptionUtil = ns.OptionUtil or {}

ns.OptionUtil = OptionUtil

OptionUtil.ACTION_ICON_BUTTON_SIZE = 20
OptionUtil.ACTION_BUTTON_TEXTURES = {
    delete = {
        normal = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        pushed = "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
        disabled = "Interface\\Buttons\\UI-GroupLoot-Pass-Disabled",
    },
    moveDown = {
        normal = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
        pushed = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
        disabled = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled",
    },
    moveLeft = {
        normal = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
        pushed = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
    },
    moveRight = {
        normal = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
        pushed = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
    },
    moveUp = {
        normal = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up",
        pushed = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down",
        disabled = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled",
    },
    show = {
        normal = "Interface\\Buttons\\UI-PlusButton-Up",
        pushed = "Interface\\Buttons\\UI-PlusButton-Down",
        disabled = "Interface\\Buttons\\UI-PlusButton-Disabled",
    },
}

function OptionUtil.CreateIconAction(text, buttonTextures, enabled, tooltip, onClick)
    return {
        text = buttonTextures and "" or text,
        width = OptionUtil.ACTION_ICON_BUTTON_SIZE,
        height = OptionUtil.ACTION_ICON_BUTTON_SIZE,
        buttonTextures = buttonTextures,
        enabled = enabled,
        tooltip = tooltip,
        onClick = onClick,
    }
end

function OptionUtil.IsAnchorModeFree(cfg)
    return cfg and cfg.anchorMode == C.ANCHORMODE_FREE
end

local function createPreviewBlock(parent, width, height, point, relativeTo, relativePoint, x, y, color)
    local block = parent:CreateTexture(nil, "ARTWORK")
    block:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    block:SetSize(width, height)
    block:SetPoint(point, relativeTo, relativePoint, x, y)
    return block
end

local function createPreviewBars(parent, positions)
    for _, pos in ipairs(positions) do
        createPreviewBlock(parent, pos.width, pos.height, "TOPLEFT", parent, "TOPLEFT", pos.x, pos.y, pos.color)
    end
end

function OptionUtil.CreatePositioningExamplesCanvas()
    local frame = CreateFrame("Frame")
    frame:SetHeight(C.POSITION_MODE_EXPLAINER_HEIGHT)

    local columns = {
        {
            title = L["POSITION_MODE_EXPLAINER_TITLE_ATTACHED"],
            caption = L["POSITION_MODE_EXPLAINER_CAPTION_ATTACHED"],
            build = function(preview)
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 12, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 31, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 51, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 70, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBars(preview, {
                    { x = 12, y = -38, width = 72, height = 10, color = { 0.22, 0.74, 0.98, 1 } },
                    { x = 12, y = -52, width = 72, height = 10, color = { 0.65, 0.41, 0.96, 1 } },
                    { x = 12, y = -66, width = 72, height = 10, color = { 0.30, 0.82, 0.52, 1 } },
                })
            end,
        },
        {
            title = L["POSITION_MODE_EXPLAINER_TITLE_DETACHED"],
            caption = L["POSITION_MODE_EXPLAINER_CAPTION_DETACHED"],
            build = function(preview)
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 10, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 28, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBlock(preview, 14, 14, "TOPLEFT", preview, "TOPLEFT", 46, -14, { 0.92, 0.78, 0.23, 1 })
                createPreviewBars(preview, {
                    { x = 92, y = -16, width = 60, height = 10, color = { 0.22, 0.74, 0.98, 1 } },
                    { x = 92, y = -30, width = 60, height = 10, color = { 0.65, 0.41, 0.96, 1 } },
                    { x = 92, y = -44, width = 60, height = 10, color = { 0.30, 0.82, 0.52, 1 } },
                })
            end,
        },
        {
            title = L["POSITION_MODE_EXPLAINER_TITLE_FREE"],
            caption = L["POSITION_MODE_EXPLAINER_CAPTION_FREE"],
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
        previewBg:SetColorTexture(0.08, 0.08, 0.08, 1)

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

function OptionUtil.OpenLayoutPage()
    local root = ns.Settings
    local page = root and root:GetPage("layout", "main")
    local categoryID = page and page:GetId()
    if categoryID then
        Settings.OpenToCategory(categoryID)
    end
end

function OptionUtil.CreateLayoutBreadcrumbArgs(order)
    order = order or 10
    return {
        layoutMovedButton = {
            type = "button",
            name = L["LAYOUT_SUBCATEGORY"],
            buttonText = L["LAYOUT_PAGE_MOVED_BUTTON_TEXT"],
            onClick = OptionUtil.OpenLayoutPage,
            order = order,
        },
    }
end

function OptionUtil.CreateDefaultValueTransform(defaultValue)
    return function(value)
        return value or defaultValue
    end
end

--- Gets the nested value from table using dot-separated path
---@param tbl table The table to get the value from
---@param path string The dot-separated path to the value
---@return any The value at the specified path, or nil if any part of the path is invalid
function OptionUtil.GetNestedValue(tbl, path)
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
function OptionUtil.SetNestedValue(tbl, path, value)
    local current, lastKey = tbl, nil
    for segment in path:gmatch("[^.]+") do
        if lastKey then
            local resolved
            if current[lastKey] == nil then
                local num = tonumber(lastKey)
                if num and current[num] ~= nil then
                    resolved = num
                end
            end
            resolved = resolved or lastKey
            if current[resolved] == nil then
                current[resolved] = {}
            end
            current = current[resolved]
        end
        lastKey = segment
    end
    local resolved
    if current[lastKey] == nil then
        local num = tonumber(lastKey)
        if num then
            resolved = num
        end
    end
    resolved = resolved or lastKey
    current[resolved] = value
end

--- Gets the current player's class and specialization information.
---@return number classID
---@return number specIndex
---@return string localisedClassName
---@return string specName
---@return string className
function OptionUtil.GetCurrentClassSpec()
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
function OptionUtil.OpenColorPicker(currentColor, hasOpacity, onChange)
    local isSettingUp = true
    ColorPickerFrame:SetupColorPickerAndShow({
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        opacity = currentColor.a,
        hasOpacity = hasOpacity,
        swatchFunc = function()
            if isSettingUp then
                return
            end
            local r, g, b = ColorPickerFrame:GetColorRGB()
            local a = hasOpacity and ColorPickerFrame:GetColorAlpha() or 1
            onChange({ r = r, g = g, b = b, a = a })
        end,
        cancelFunc = function(prev)
            local source = prev or currentColor
            onChange({ r = source.r, g = source.g, b = source.b, a = hasOpacity and (source.opacity or source.a) or 1 })
        end,
    })
    isSettingUp = false
end

--- Returns a closure that checks if the module at configPath is disabled.
---@param configPath string e.g. "powerBar"
---@return fun(): boolean
function OptionUtil.GetIsDisabledDelegate(configPath)
    local enabledPath = configPath .. ".enabled"
    return function()
        return not OptionUtil.GetNestedValue(ns.Addon.db.profile, enabledPath)
    end
end

local function setModuleEnabledValue(moduleName, value, setting)
    if setting and type(setting.SetValueNoCallback) == "function" then
        setting:SetValueNoCallback(value)
        return
    end

    local profile = ns.Addon.db.profile
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
---@return fun(ctx: table, value: boolean)
function OptionUtil.CreateModuleEnabledHandler(moduleName, requiresReload)
    return function(ctx, value)
        local setting = ctx and ctx.setting
        if value then
            ns.Addon:EnableModule(moduleName)
            return
        end

        if requiresReload then
            setModuleEnabledValue(moduleName, true, setting)
            ns.Addon:ConfirmReloadUI(requiresReload, function()
                setModuleEnabledValue(moduleName, false, setting)
                ns.Addon:DisableModule(moduleName)
            end, function()
                setModuleEnabledValue(moduleName, true, setting)
            end)
            return
        end

        ns.Addon:DisableModule(moduleName)
    end
end

local function getGlobalFont()
    local gc = ns.GetGlobalConfig()
    return gc and gc.font
end

local function getGlobalFontSize()
    local gc = ns.GetGlobalConfig()
    return gc and gc.fontSize
end

function OptionUtil.CreateFontOverrideRow(isDisabled)
    return {
        type = "fontOverride",
        path = "",
        disabled = isDisabled,
        fontFallback = getGlobalFont,
        fontSizeFallback = getGlobalFontSize,
    }
end

--- Generates standard layout and appearance rows shared by bar-type modules.
--- This is the canonical rows-array form used by declarative section/page specs.
---@param isDisabled fun(): boolean
---@param options table|nil { showText: boolean, border: boolean }
---@return table[] rows
function OptionUtil.CreateBarRows(isDisabled, options)
    options = options or {}
    local rows = {
        OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton,
        {
            type = "header",
            name = L["APPEARANCE"],
            disabled = isDisabled,
        },
    }

    if options.showText ~= false then
        rows[#rows + 1] = {
            type = "checkbox",
            path = "showText",
            name = L["SHOW_TEXT"],
            tooltip = L["SHOW_TEXT_DESC"],
            disabled = isDisabled,
        }
    end

    rows[#rows + 1] = { type = "heightOverride", path = "", disabled = isDisabled }
    rows[#rows + 1] = OptionUtil.CreateFontOverrideRow(isDisabled)

    if options.border ~= false then
        rows[#rows + 1] = {
            type = "border",
            path = "border",
            disabled = isDisabled,
        }
    end

    return rows
end

local function nilForZero(value)
    return value > 0 and value or nil
end

--- Generates appearance rows shared by aura-style bar modules.
---@param isDisabled fun(): boolean
---@param extraRowsAfterHeader table[]|nil Rows inserted after the Appearance header.
---@return table[] rows
function OptionUtil.CreateAuraBarModuleRows(isDisabled, extraRowsAfterHeader)
    local defaultZero = OptionUtil.CreateDefaultValueTransform(0)
    local rows = {
        { id = "appearanceHeader", type = "header", name = L["APPEARANCE"], disabled = isDisabled },
    }

    if extraRowsAfterHeader then
        for _, row in ipairs(extraRowsAfterHeader) do
            rows[#rows + 1] = row
        end
    end

    rows[#rows + 1] = {
        id = "showIcon",
        type = "checkbox",
        path = "showIcon",
        name = L["SHOW_ICON"],
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        id = "showSpellName",
        type = "checkbox",
        path = "showSpellName",
        name = L["SHOW_SPELL_NAME"],
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        id = "showDuration",
        type = "checkbox",
        path = "showDuration",
        name = L["SHOW_REMAINING_DURATION"],
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        id = "height",
        type = "slider",
        path = "height",
        name = L["HEIGHT_OVERRIDE"],
        tooltip = L["HEIGHT_OVERRIDE_DESC"],
        min = 0,
        max = 40,
        step = 1,
        disabled = isDisabled,
        getTransform = defaultZero,
        setTransform = nilForZero,
    }
    rows[#rows + 1] = {
        id = "verticalSpacing",
        type = "slider",
        path = "verticalSpacing",
        name = L["AURA_VERTICAL_SPACING"],
        tooltip = L["AURA_VERTICAL_SPACING_DESC"],
        min = 0,
        max = 20,
        step = 1,
        disabled = isDisabled,
        getTransform = defaultZero,
    }

    local fontOverride = OptionUtil.CreateFontOverrideRow(isDisabled)
    fontOverride.id = "fontOverride"
    rows[#rows + 1] = fontOverride

    return rows
end

local function createDetachedSettingSpecs()
    return {
        {
            key = "detachedBarWidth",
            name = L["WIDTH"],
            tooltip = L["DETACHED_WIDTH_DESC"],
            default = C.DEFAULT_BAR_WIDTH,
            min = 100,
            max = 600,
            step = 1,
            updateReason = "DetachedAnchorWidth",
        },
        {
            key = "detachedModuleSpacing",
            name = L["SPACING"],
            tooltip = L["DETACHED_SPACING_DESC"],
            default = 0,
            min = 0,
            max = 20,
            step = 1,
            updateReason = "DetachedAnchorSpacing",
        },
        {
            key = "detachedGrowDirection",
            name = L["GROW_DIRECTION"],
            tooltip = L["DETACHED_GROW_DIRECTION_DESC"],
            default = C.GROW_DIRECTION_DOWN,
            values = {
                { text = L["DOWN"], value = C.GROW_DIRECTION_DOWN },
                { text = L["UP"], value = C.GROW_DIRECTION_UP },
            },
            updateReason = "DetachedAnchorGrowDirection",
        },
    }
end

function OptionUtil.CreateDetachedStackRows()
    local rows = {
        {
            type = "header",
            name = L["POSITION_MODE_DETACHED"],
        },
    }

    local defaultZero = OptionUtil.CreateDefaultValueTransform(0)
    for _, spec in ipairs(createDetachedSettingSpecs()) do
        local row = {
            path = "global." .. spec.key,
            name = spec.name,
            tooltip = spec.tooltip,
            getTransform = spec.default == 0 and defaultZero or OptionUtil.CreateDefaultValueTransform(spec.default),
        }

        if spec.values then
            row.type = "dropdown"
            row.values = {}
            for _, option in ipairs(spec.values) do
                row.values[option.value] = option.text
            end
        else
            row.type = "slider"
            row.min = spec.min
            row.max = spec.max
            row.step = spec.step
        end

        rows[#rows + 1] = row
    end

    return rows
end

function OptionUtil.CreateDetachedAnchorEditModeSettings(getGlobalConfig, onChanged)
    local settingType = ns.EditMode.Lib.SettingType
    local settings = {}

    for _, spec in ipairs(createDetachedSettingSpecs()) do
        local setting = {
            name = spec.name,
            get = function()
                local gc = getGlobalConfig()
                return (gc and gc[spec.key]) or spec.default
            end,
            set = function(_, value)
                local gc = getGlobalConfig()
                if gc then
                    gc[spec.key] = value
                    onChanged(spec.updateReason)
                end
            end,
        }

        if spec.values then
            setting.kind = settingType.Dropdown
            setting.values = spec.values
        else
            setting.kind = settingType.Slider
            setting.default = spec.default
            setting.minValue = spec.min
            setting.maxValue = spec.max
            setting.valueStep = spec.step
            setting.allowInput = true
        end

        settings[#settings + 1] = setting
    end

    return settings
end

function OptionUtil.MakeConfirmDialog(text, button1, button2)
    assert(type(button1) == "string" and button1 ~= "", "OptionUtil.MakeConfirmDialog requires button1")
    assert(type(button2) == "string" and button2 ~= "", "OptionUtil.MakeConfirmDialog requires button2")

    return {
        text = text,
        button1 = button1,
        button2 = button2,
        OnAccept = function(self, data)
            if data and data.onAccept then data.onAccept() end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

local function getPopupEditBox(frame) return frame and (frame.EditBox or frame.editBox) end

local function trimDialogText(text)
    return strtrim(text or "")
end

local function setDialogAcceptEnabled(frame, enabled)
    local button = frame and frame.button1
    if button then
        button:SetEnabled(enabled)
    end
end

function OptionUtil.MakeTextInputDialog(text, button1, button2)
    assert(type(button1) == "string" and button1 ~= "", "OptionUtil.MakeTextInputDialog requires button1")
    assert(type(button2) == "string" and button2 ~= "", "OptionUtil.MakeTextInputDialog requires button2")

    return {
        text = text,
        button1 = button1,
        button2 = button2,
        hasEditBox = true,
        OnAccept = function(self, data)
            data = data or (self and self.data)
            local name = trimDialogText(getPopupEditBox(self) and getPopupEditBox(self):GetText())
            if name ~= "" and data and data.onAccept then
                data.onAccept(name)
            end
        end,
        OnShow = function(self, data)
            data = data or (self and self.data)
            local editBox = getPopupEditBox(self)
            if not editBox then
                return
            end
            editBox:SetText(data and data.defaultText or "")
            editBox:HighlightText()
            setDialogAcceptEnabled(self, trimDialogText(editBox:GetText()) ~= "")
        end,
        EditBoxOnTextChanged = function(self)
            local parent = self:GetParent()
            setDialogAcceptEnabled(parent, trimDialogText(self:GetText()) ~= "")
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            if not parent then
                return
            end
            if parent.button1 and not parent.button1:IsEnabled() then
                return
            end
            parent:Hide()
            local dialog = parent.which and StaticPopupDialogs[parent.which]
            dialog = dialog or (parent.data and parent.data.popupKey and StaticPopupDialogs[parent.data.popupKey])
            if dialog and dialog.OnAccept then
                dialog.OnAccept(parent, parent.data)
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

