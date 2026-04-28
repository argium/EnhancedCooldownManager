-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local copyMixin = internal.copyMixin
local getInitializerData = internal.getInitializerData
local getOrderedValueEntries = internal.getOrderedValueEntries

local DropdownMethods = {}

function DropdownMethods:GetSetting()
    if self.lsbData and self.lsbData.setting then
        return self.lsbData.setting
    end
    if self.initializer and self.initializer.GetSetting then
        return self.initializer:GetSetting()
    end
    return nil
end

function DropdownMethods:RefreshDropdownText(value)
    local dropdown = self.Control and self.Control.Dropdown
    if not dropdown then
        return
    end

    local setting = self:GetSetting()
    local currentValue = value
    if currentValue == nil and setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    local values = self.lsbData and self.lsbData.values
    if type(values) == "function" then
        values = values()
    end
    local text = values and values[currentValue] or tostring(currentValue or "")

    if dropdown.OverrideText then
        dropdown:OverrideText(text)
    elseif dropdown.SetText then
        dropdown:SetText(text)
    end
end

function DropdownMethods:SetValue(value)
    if self._lsbOriginalSetValue then
        self:_lsbOriginalSetValue(value)
    end
    self:RefreshDropdownText(value)
end

function DropdownMethods:InitDropdown()
    local setting = self:GetSetting()
    local data = self.lsbData or {}
    local scrollHeight = data.scrollHeight or 200

    local dropdown = self.Control and self.Control.Dropdown
    if not dropdown or not setting then
        return
    end

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(scrollHeight)

        local values = data.values
        if type(values) == "function" then
            values = values()
        end
        if not values then
            return
        end

        for _, entry in ipairs(getOrderedValueEntries(values)) do
            rootDescription:CreateRadio(entry.label, function()
                return setting:GetValue() == entry.value
            end, function()
                setting:SetValue(entry.value)
                self:RefreshDropdownText(entry.value)
            end, entry.value)
        end
    end)

    self:RefreshDropdownText()
end

local function configureDropdownFrame(frame, initializer, data)
    if not frame._lsbOriginalSetValue then
        frame._lsbOriginalSetValue = frame.SetValue
    end

    copyMixin(frame, DropdownMethods)
    frame.initializer = initializer
    frame.lsbData = data or {}
    initializer._lsbActiveFrame = frame
    if frame.lsbData._lsbKind == "scrollDropdown" then
        frame:InitDropdown()
    else
        frame:RefreshDropdownText()
    end
end

if not lib._scrollDropdownHookInstalled and hooksecurefunc and SettingsDropdownControlMixin then
    hooksecurefunc(SettingsDropdownControlMixin, "Init", function(frame, initializer)
        local data = getInitializerData(initializer)
        if not data or (data._lsbKind ~= "dropdown" and data._lsbKind ~= "scrollDropdown") then
            if frame._lsbOriginalSetValue then
                frame.SetValue = frame._lsbOriginalSetValue
            end
            frame.initializer = initializer
            frame.lsbData = nil
            return
        end

        configureDropdownFrame(frame, initializer, data)
    end)

    lib._scrollDropdownHookInstalled = true
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

local function createInlineSliderFormatters()
    if not MinimalSliderWithSteppersMixin or not MinimalSliderWithSteppersMixin.Label then
        return nil
    end

    return {
        [MinimalSliderWithSteppersMixin.Label.Right] = function()
            return ""
        end,
    }
end

local function attachInlineSliderEditor(slider, textLabel, editBoxWidth)
    if slider._lsbValueButton then
        return
    end

    local function hideEditBox()
        if slider._lsbEditBox and slider._lsbEditBox.ClearFocus then
            slider._lsbEditBox:ClearFocus()
        end
        if slider._lsbEditBox then
            slider._lsbEditBox:Hide()
        end
        if textLabel and textLabel.Show then
            textLabel:Show()
        end
    end

    local function applyEditBoxValue()
        local editBox = slider._lsbEditBox
        local enteredValue = editBox and tonumber(editBox:GetText())
        if enteredValue then
            local minValue = slider._lsbMinValue or 0
            local maxValue = slider._lsbMaxValue
            if slider._lsbRangeResolver then
                local nextMin, nextMax, nextStep = slider._lsbRangeResolver(enteredValue)
                if nextMin ~= nil then
                    minValue = nextMin
                end
                if nextMax ~= nil then
                    maxValue = nextMax
                end
                if nextStep ~= nil then
                    slider._lsbStep = nextStep
                end
                if maxValue ~= nil then
                    slider._lsbMaxValue = maxValue
                end
                slider._lsbMinValue = minValue
            end

            slider:SetValue(roundSliderValue(enteredValue, slider._lsbStep, minValue, maxValue))
        end
        hideEditBox()
    end

    local valueButton = CreateFrame("Button", nil, slider)
    valueButton:RegisterForClicks("LeftButtonDown")
    valueButton:SetAllPoints(textLabel)
    slider._lsbValueButton = valueButton

    local editBox = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(false)
    editBox:SetSize(editBoxWidth or 50, 20)
    editBox:SetPoint("CENTER", textLabel, "CENTER")
    editBox:SetJustifyH("CENTER")
    editBox:Hide()
    slider._lsbEditBox = editBox

    editBox:SetScript("OnEnterPressed", applyEditBoxValue)
    editBox:SetScript("OnEscapePressed", hideEditBox)
    editBox:SetScript("OnEditFocusLost", hideEditBox)

    valueButton:SetScript("OnClick", function()
        editBox:SetText(textLabel and textLabel.GetText and textLabel:GetText() or "")
        if textLabel and textLabel.Hide then
            textLabel:Hide()
        end
        editBox:Show()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
end

local function configureInlineSlider(slider, textLabel, field, onValueChanged)
    local minValue = field.min or 0
    local maxValue = field.max or 1
    local step = field.step or 1

    slider._lsbMinValue = minValue
    slider._lsbMaxValue = maxValue
    slider._lsbStep = step
    slider._lsbRangeResolver = field.getRange

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
        slider:Init(minValue, minValue, maxValue, getSliderStepCount(minValue, maxValue, step), createInlineSliderFormatters())
        if slider.Slider and slider.Slider.SetValueStep then
            slider.Slider:SetValueStep(step)
        end
    else
        slider:SetMinMaxValues(minValue, maxValue)
        slider:SetValueStep(step)
        slider:SetObeyStepOnDrag(true)
    end

    attachInlineSliderEditor(slider, textLabel, field.editWidth or 50)

    if not slider._lsbValueChangedBound then
        local function handleValueChanged(_, value)
            local rounded = roundSliderValue(value, slider._lsbStep, slider._lsbMinValue, slider._lsbMaxValue)
            if textLabel and textLabel.SetText then
                textLabel:SetText(tostring(rounded))
            end
            if onValueChanged then
                onValueChanged(rounded)
            end
        end

        if slider.RegisterCallback and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
            slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, handleValueChanged, slider)
        else
            slider:HookScript("OnValueChanged", handleValueChanged)
        end
        slider._lsbValueChangedBound = true
    end
end

internal.configureInlineSlider = configureInlineSlider

if not lib._sliderHookInstalled then
    local function setupSliderEditableValue()
        if not SettingsSliderControlMixin then
            return
        end

        local function findValueLabel(sliderWithSteppers)
            if sliderWithSteppers._label then
                return sliderWithSteppers._label
            end
            if sliderWithSteppers.RightText then
                return sliderWithSteppers.RightText
            end
            if sliderWithSteppers.Label then
                return sliderWithSteppers.Label
            end
            for i = 1, select("#", sliderWithSteppers:GetRegions()) do
                local region = select(i, sliderWithSteppers:GetRegions())
                if region and region:IsObjectType("FontString") then
                    return region
                end
            end
            return nil
        end

        local function getSliderValueText(self)
            local setting = self and self._lsbCurrentSetting
            if not setting or not setting.GetValue then
                return ""
            end
            return tostring(setting:GetValue())
        end

        local function hideSliderEditBox(self)
            local editBox = self and self._lsbEditBox
            local valueLabel = self and self._lsbValueLabel
            if not editBox or not valueLabel then
                return
            end
            editBox:ClearFocus()
            editBox:Hide()
            valueLabel:Show()
        end

        local function applySliderEditValue(self)
            local editBox = self and self._lsbEditBox
            local setting = self and self._lsbCurrentSetting
            local sliderWithSteppers = self and self.SliderWithSteppers
            if not editBox or not setting or not sliderWithSteppers or not sliderWithSteppers.Slider then
                hideSliderEditBox(self)
                return
            end

            local num = tonumber(editBox:GetText())
            if num then
                local slider = sliderWithSteppers.Slider
                local min, max = slider:GetMinMaxValues()
                num = math.max(min, math.min(max, num))
                local step = slider:GetValueStep()
                if step and step > 0 then
                    num = math.floor(num / step + 0.5) * step
                end
                setting:SetValue(num)
            end

            hideSliderEditBox(self)
        end

        local function anchorSliderValueButton(self)
            local valueLabel = self and self._lsbValueLabel
            local valueButton = self and self._lsbValueButton
            if not valueLabel or not valueButton then
                return
            end

            if valueButton.ClearAllPoints then
                valueButton:ClearAllPoints()
            end
            valueButton:SetAllPoints(valueLabel)
        end

        hooksecurefunc(SettingsSliderControlMixin, "Init", function(self, initializer)
            local sliderWithSteppers = self.SliderWithSteppers
            if not sliderWithSteppers then
                return
            end

            local valueLabel = findValueLabel(sliderWithSteppers)
            if not valueLabel then
                return
            end

            self._lsbCurrentSetting = initializer:GetSetting()
            self._lsbValueLabel = valueLabel

            if not self._lsbValueButton then
                local btn = CreateFrame("Button", nil, sliderWithSteppers)
                btn:RegisterForClicks("LeftButtonDown")
                self._lsbValueButton = btn

                local editBox = CreateFrame("EditBox", nil, sliderWithSteppers, "InputBoxTemplate")
                editBox:SetAutoFocus(false)
                editBox:SetNumeric(false)
                editBox:SetSize(50, 20)
                editBox:SetPoint("CENTER", valueLabel, "CENTER")
                editBox:SetJustifyH("CENTER")
                editBox:Hide()
                self._lsbEditBox = editBox

                editBox:SetScript("OnEnterPressed", function()
                    applySliderEditValue(self)
                end)
                editBox:SetScript("OnEscapePressed", function()
                    hideSliderEditBox(self)
                end)
                editBox:SetScript("OnEditFocusLost", function()
                    hideSliderEditBox(self)
                end)

                btn:SetScript("OnClick", function()
                    local setting = self._lsbCurrentSetting
                    local currentValueLabel = self._lsbValueLabel
                    if not setting or not currentValueLabel then
                        return
                    end

                    anchorSliderValueButton(self)
                    editBox:SetText(getSliderValueText(self))
                    currentValueLabel:Hide()
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:HighlightText()
                end)
            end

            anchorSliderValueButton(self)

            if self._lsbEditBox and self._lsbEditBox.ClearFocus then
                self._lsbEditBox:ClearFocus()
                self._lsbEditBox:Hide()
            end
            valueLabel:Show()
        end)
    end

    setupSliderEditableValue()
    lib._sliderHookInstalled = true
end
