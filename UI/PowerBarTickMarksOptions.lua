-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local L = ECM.L

local function getPowerBarConfig()
    local profile = ns.Addon.db.profile
    local powerBar = profile.powerBar
    if powerBar then
        return powerBar
    end

    powerBar = {}
    profile.powerBar = powerBar
    return powerBar
end

local function getTicksConfig()
    local powerBar = getPowerBarConfig()
    if powerBar.ticks then
        return powerBar.ticks
    end

    powerBar.ticks = {
        mappings = {},
        defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
        defaultWidth = 1,
    }
    return powerBar.ticks
end

local store = {}

function store.GetCurrentTicks()
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return {}
    end
    local mappings = getTicksConfig().mappings
    local classMappings = mappings and mappings[classID]
    return classMappings and classMappings[specIndex] or {}
end

function store.SetCurrentTicks(ticks)
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return
    end
    local ticksCfg = getTicksConfig()
    if not ticksCfg.mappings[classID] then
        ticksCfg.mappings[classID] = {}
    end
    ticksCfg.mappings[classID][specIndex] = ticks
end

function store.AddTick(value, color, width)
    local ticks = store.GetCurrentTicks()
    local ticksCfg = getTicksConfig()
    ticks[#ticks + 1] = {
        value = value,
        color = color or ECM.CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
    store.SetCurrentTicks(ticks)
end

function store.RemoveTick(index)
    local ticks = store.GetCurrentTicks()
    if not ticks[index] then
        return
    end
    table.remove(ticks, index)
    store.SetCurrentTicks(ticks)
end

function store.UpdateTick(index, field, value)
    local ticks = store.GetCurrentTicks()
    if not ticks[index] then
        return
    end
    ticks[index][field] = value
    store.SetCurrentTicks(ticks)
end

function store.GetDefaultColor()
    return getTicksConfig().defaultColor
end

function store.SetDefaultColor(color)
    getTicksConfig().defaultColor = color
end

function store.GetDefaultWidth()
    return getTicksConfig().defaultWidth
end

function store.SetDefaultWidth(width)
    getTicksConfig().defaultWidth = width
end

ECM.PowerBarTickMarksStore = store

StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"] = ECM.OptionUtil.MakeConfirmDialog(L["TICK_MARKS_CLEAR_CONFIRM"])

local function roundToStep(value)
    return math.floor(value + 0.5)
end

local function getValueSliderRange(currentValue)
    for _, tier in ipairs(C.VALUE_SLIDER_TIERS) do
        if currentValue <= tier.ceiling then
            return tier.ceiling, tier.step
        end
    end
    local last = C.VALUE_SLIDER_TIERS[#C.VALUE_SLIDER_TIERS]
    return math.ceil(currentValue / last.step) * last.step, last.step
end

local function roundSliderValue(value, step, minValue, maxValue)
    local actualStep = step or 1
    local baseValue = minValue or 0
    local rounded = math.floor(((value - baseValue) / actualStep) + 0.5) * actualStep + baseValue
    if minValue then
        rounded = math.max(minValue, rounded)
    end
    if maxValue then
        rounded = math.min(maxValue, rounded)
    end
    return rounded
end

local function getSliderStepCount(minValue, maxValue, step)
    return math.max(1, math.floor(((maxValue - minValue) / (step or 1)) + 0.5))
end

local function createSliderFormatters()
    if not MinimalSliderWithSteppersMixin or not MinimalSliderWithSteppersMixin.Label then
        return nil
    end

    return {
        [MinimalSliderWithSteppersMixin.Label.Right] = function()
            return ""
        end,
    }
end

local function attachSliderValueEditor(slider, textLabel, editBoxWidth)
    if slider._ecmValueButton then
        return
    end

    local function hideEditBox()
        if slider._ecmEditBox and slider._ecmEditBox.ClearFocus then
            slider._ecmEditBox:ClearFocus()
        end
        if slider._ecmEditBox then
            slider._ecmEditBox:Hide()
        end
        textLabel:Show()
    end

    local function applyEditBoxValue()
        local editBox = slider._ecmEditBox
        local enteredValue = editBox and tonumber(editBox:GetText())
        if enteredValue then
            local clamped = math.max(slider._ecmMinValue or 1, math.floor(enteredValue + 0.5))
            if slider._ecmRescale then
                slider._ecmRescale(clamped)
            end
            slider:SetValue(roundSliderValue(clamped, slider._ecmStep, slider._ecmMinValue, slider._ecmMaxValue))
        end
        hideEditBox()
    end

    local valueButton = CreateFrame("Button", nil, slider)
    valueButton:RegisterForClicks("LeftButtonDown")
    valueButton:SetAllPoints(textLabel)
    slider._ecmValueButton = valueButton

    local editBox = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(false)
    editBox:SetSize(editBoxWidth, 20)
    editBox:SetPoint("CENTER", textLabel, "CENTER")
    editBox:SetJustifyH("CENTER")
    editBox:Hide()
    slider._ecmEditBox = editBox

    editBox:SetScript("OnEnterPressed", applyEditBoxValue)
    editBox:SetScript("OnEscapePressed", hideEditBox)
    editBox:SetScript("OnEditFocusLost", hideEditBox)

    valueButton:SetScript("OnClick", function()
        valueButton:ClearAllPoints()
        valueButton:SetAllPoints(textLabel)
        editBox:SetText(textLabel:GetText())
        textLabel:Hide()
        editBox:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

local function configureSlider(slider, textLabel, minValue, maxValue, step, editBoxWidth, onValueChanged)
    slider._ecmMinValue = minValue
    slider._ecmMaxValue = maxValue
    slider._ecmStep = step

    if slider.MinText then
        slider.MinText:Hide()
    end
    if slider.MaxText then
        slider.MaxText:Hide()
    end
    if slider.RightText then
        slider.RightText:Hide()
    end

    if slider.Init then
        slider:Init(minValue, minValue, maxValue, getSliderStepCount(minValue, maxValue, step), createSliderFormatters())
        if slider.Slider and slider.Slider.SetValueStep then
            slider.Slider:SetValueStep(step)
        end
    else
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
    end

    attachSliderValueEditor(slider, textLabel, editBoxWidth)

    local function handleValueChanged(_, value)
        local rounded = roundSliderValue(value, slider._ecmStep, slider._ecmMinValue, slider._ecmMaxValue)
        textLabel:SetText(tostring(roundToStep(rounded)))
        onValueChanged(rounded)
    end

    if slider.RegisterCallback and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, handleValueChanged, slider)
    else
        slider:HookScript("OnValueChanged", handleValueChanged)
    end
end

local function createTickRowWidgets(rowFrame, SB)
    rowFrame:SetHeight(34)

    local highlight = rowFrame:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    highlight:Hide()
    rowFrame._highlight = highlight

    rowFrame:EnableMouse(true)
    rowFrame:SetScript("OnEnter", function(self)
        self._highlight:Show()
    end)
    rowFrame:SetScript("OnLeave", function(self)
        self._highlight:Hide()
    end)

    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0)
    label:SetWidth(70)
    label:SetJustifyH("LEFT")
    rowFrame._label = label

    local valueSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
    valueSlider:SetPoint("LEFT", label, "RIGHT", 8, 0)
    valueSlider:SetWidth(150)
    rowFrame._valueSlider = valueSlider

    local valueText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", valueSlider, "RIGHT", 6, 0)
    valueText:SetWidth(50)
    valueText:SetJustifyH("LEFT")
    rowFrame._valueText = valueText

    local widthSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
    widthSlider:SetPoint("LEFT", valueText, "RIGHT", 12, 0)
    widthSlider:SetWidth(90)
    rowFrame._widthSlider = widthSlider

    local widthText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    widthText:SetPoint("LEFT", widthSlider, "RIGHT", 6, 0)
    widthText:SetWidth(18)
    widthText:SetJustifyH("LEFT")
    rowFrame._widthText = widthText

    local swatch = SB.CreateColorSwatch(rowFrame)
    swatch:SetPoint("LEFT", widthText, "RIGHT", 10, 0)
    rowFrame._swatch = swatch

    local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
    removeBtn:SetSize(70, 22)
    removeBtn:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    removeBtn:SetText(L["REMOVE"])
    rowFrame._removeBtn = removeBtn

    local function rescaleValueSlider(targetValue)
        local newMax, newStep = getValueSliderRange(math.max(1, targetValue))
        if newMax ~= valueSlider._ecmMaxValue then
            valueSlider._ecmMaxValue = newMax
            valueSlider._ecmStep = newStep
            if valueSlider.Init then
                valueSlider:Init(targetValue, 1, newMax, getSliderStepCount(1, newMax, newStep), createSliderFormatters())
                if valueSlider.Slider and valueSlider.Slider.SetValueStep then
                    valueSlider.Slider:SetValueStep(newStep)
                end
            end
        end
    end

    configureSlider(valueSlider, valueText, 1, 200, 1, 60, function(rounded)
        if rowFrame._isRefreshing then
            return
        end
        store.UpdateTick(rowFrame._rowIndex, "value", rounded)
        ECM.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end)
    valueSlider._ecmRescale = rescaleValueSlider

    configureSlider(widthSlider, widthText, 1, 5, 1, 34, function(rounded)
        if rowFrame._isRefreshing then
            return
        end
        store.UpdateTick(rowFrame._rowIndex, "width", rounded)
        ECM.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end)
end

local function createTickMarksCanvas(SB, subcatName, parentCategory)
    local layout = SB.CreateCanvasLayout(subcatName, parentCategory)
    local frame = layout.frame

    local function clearAllTicks()
        store.SetCurrentTicks({})
        frame:RefreshTicks()
        ECM.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end

    local headerRow = layout:AddHeader(subcatName)
    local defaultsBtn = headerRow._defaultsButton
    defaultsBtn:SetText(SETTINGS_DEFAULTS)
    defaultsBtn:SetScript("OnClick", function()
        StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"].OnAccept = clearAllTicks
        StaticPopup_Show("ECM_CONFIRM_CLEAR_TICKS")
    end)

    layout:AddSpacer(2)

    layout:AddDescription(L["TICK_MARKS_DESC"], "GameFontHighlight")._text:SetWordWrap(true)

    local infoRow = layout:AddDescription("")
    local infoText = infoRow._text
    infoText:SetWordWrap(true)

    local _, defaultColorSwatch = layout:AddColorSwatch(L["DEFAULT_COLOR"])
    defaultColorSwatch:SetScript("OnClick", function()
        local c = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        ECM.OptionUtil.OpenColorPicker(c, true, function(color)
            store.SetDefaultColor(color)
            defaultColorSwatch:SetColorRGB(color.r, color.g, color.b)
        end)
    end)

    local _, defaultWidthSlider, defaultWidthText = layout:AddSlider(L["DEFAULT_WIDTH"], 1, 5, 1)
    configureSlider(defaultWidthSlider, defaultWidthText, 1, 5, 1, 44, function(rounded)
        store.SetDefaultWidth(rounded)
    end)

    local _, addBtn = layout:AddButton(L["ADD_TICK_MARK"], L["ADD"])
    addBtn:SetScript("OnClick", function()
        store.AddTick(50, nil, nil)
        frame:RefreshTicks()
    end)

    local scrollBox, _, view = layout:AddScrollList(C.SCROLL_ROW_HEIGHT_WITH_CONTROLS)

    view:SetElementInitializer("Frame", function(rowFrame, data)
        if not rowFrame._initialized then
            createTickRowWidgets(rowFrame, SB)
            rowFrame._initialized = true
        end

        local index = data.index
        rowFrame._rowIndex = index
        rowFrame._highlight:Hide()
        rowFrame._label:SetText(string.format(L["TICK_N"], index))

        local tickValue = data.tick.value or 50
        local tickWidth = data.tick.width or store.GetDefaultWidth()

        rowFrame._isRefreshing = true
        if rowFrame._valueSlider._ecmRescale then
            rowFrame._valueSlider._ecmRescale(tickValue)
        end
        rowFrame._valueSlider:SetValue(tickValue)
        rowFrame._valueText:SetText(tostring(roundToStep(tickValue)))
        rowFrame._widthSlider:SetValue(tickWidth)
        rowFrame._widthText:SetText(tostring(roundToStep(tickWidth)))
        rowFrame._isRefreshing = false

        local tc = data.tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        rowFrame._swatch:SetColorRGB(tc.r, tc.g, tc.b)

        rowFrame._swatch:SetScript("OnClick", function()
            local current = data.tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
            ECM.OptionUtil.OpenColorPicker(current, true, function(color)
                store.UpdateTick(rowFrame._rowIndex, "color", color)
                rowFrame._swatch:SetColorRGB(color.r, color.g, color.b)
                ECM.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
            end)
        end)

        rowFrame._removeBtn:SetScript("OnClick", function()
            store.RemoveTick(rowFrame._rowIndex)
            frame:RefreshTicks()
            ECM.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    function frame:RefreshTicks()
        local ticks = store.GetCurrentTicks()

        dataProvider:Flush()
        for i, tick in ipairs(ticks) do
            dataProvider:Insert({ index = i, tick = tick })
        end

        local _, _, localisedClassName, specName, className = ECM.OptionUtil.GetCurrentClassSpec()
        local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
        local classSpecLabel = "|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown")
        local count = #ticks
        if count == 0 then
            infoText:SetText(string.format(L["NO_TICK_MARKS"], classSpecLabel))
        else
            infoText:SetText(string.format(L["TICK_COUNT"], classSpecLabel, count))
        end

        defaultsBtn:SetEnabled(count > 0)

        local dc = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        defaultColorSwatch:SetColorRGB(dc.r, dc.g, dc.b)

        local dw = store.GetDefaultWidth() or 1
        defaultWidthSlider:SetValue(dw)
        defaultWidthText:SetText(tostring(roundToStep(dw)))
    end

    frame.OnDefault = clearAllTicks

    frame:SetScript("OnShow", function(self)
        self:RefreshTicks()
    end)
end

ECM.PowerBarTickMarksOptions = {
    RegisterSettings = function(SB, parentCategory)
        createTickMarksCanvas(SB, "Tick Marks", parentCategory)
    end,
}
