-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local foundation = lib._internal.foundation
local interop = lib._internal.interop
local copyMixin = foundation.copyMixin
local getInitializerData = interop.getInitializerData
local getOrderedValueEntries = foundation.getOrderedValueEntries

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
    local previousInitializer = frame.initializer
    if previousInitializer and previousInitializer ~= initializer and previousInitializer._lsbActiveFrame == frame then
        previousInitializer._lsbActiveFrame = nil
    end

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
            if frame.initializer and frame.initializer._lsbActiveFrame == frame then
                frame.initializer._lsbActiveFrame = nil
            end
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
        if slider._lsbEditBox then
            slider._lsbEditBox:ClearFocus()
        end
        if slider._lsbEditBox then
            slider._lsbEditBox:Hide()
        end
        if textLabel then
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
    valueButton:SetPropagateMouseClicks(false)
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

local function configureInlineSlider(slider, textLabel, field, onValueChanged, rangeResolver)
    local minValue = field.min or 0
    local maxValue = field.max or 1
    local step = field.step or 1

    slider._lsbOnValueChanged = onValueChanged
    slider._lsbMinValue = minValue
    slider._lsbMaxValue = maxValue
    slider._lsbStep = step
    slider._lsbRangeResolver = rangeResolver or field.getRange

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
        local wasSuppressed = slider._lsbSuppressValueChanged
        slider._lsbSuppressValueChanged = true
        local ok, err = pcall(function()
            slider:Init(field.value or minValue, minValue, maxValue, getSliderStepCount(minValue, maxValue, step), createInlineSliderFormatters())
            if slider.Slider then
                slider.Slider:SetValueStep(step)
            end
        end)
        slider._lsbSuppressValueChanged = wasSuppressed
        if not ok then
            error(err, 0)
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
            if textLabel then
                textLabel:SetText(tostring(rounded))
            end
            if not slider._lsbSuppressValueChanged and slider._lsbOnValueChanged then
                slider._lsbOnValueChanged(rounded)
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

interop.configureInlineSlider = configureInlineSlider

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

            valueButton:ClearAllPoints()
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

            if self._lsbEditBox then
                self._lsbEditBox:ClearFocus()
                self._lsbEditBox:Hide()
            end
            valueLabel:Show()
        end)
    end

    setupSliderEditableValue()
    lib._sliderHookInstalled = true
end

local function getCategoryDefaultsButton()
    local settingsList = SettingsPanel and SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
    local header = settingsList and settingsList.Header
    return header and header.DefaultsButton or nil
end

function interop.installCategoryDefaultsOverride(onClick, enabledPredicate, confirmDefaults, pageName)
    local button = getCategoryDefaultsButton()
    if not button then
        return function() end
    end

    local originalOnClick = button:GetScript("OnClick")
    local originalEnabled = button:IsEnabled()

    local function applyEnabled()
        if enabledPredicate then
            button:SetEnabled(enabledPredicate() and true or false)
        elseif not onClick then
            button:SetEnabled(originalEnabled)
        else
            button:SetEnabled(true)
        end
    end

    button:SetScript("OnClick", function(self)
        if enabledPredicate and not enabledPredicate() then
            return
        end

        local function reset()
            if onClick then
                onClick()
                applyEnabled()
            elseif originalOnClick then
                originalOnClick(self)
            end
        end

        if confirmDefaults then
            confirmDefaults(pageName, reset)
        else
            reset()
        end
    end)
    applyEnabled()

    return function()
        if button:GetScript("OnClick") then
            button:SetScript("OnClick", originalOnClick)
        end
        button:SetEnabled(originalEnabled)
    end
end

local function notifyLifecycleHidden(category)
    local cbs = category and lib._pageLifecycleCallbacks[category] or nil
    if not cbs then
        return
    end
    if cbs._defaultsRestore then
        cbs._defaultsRestore()
        cbs._defaultsRestore = nil
    end
    if cbs.onHide then
        cbs.onHide()
    end
end

function interop.installPageLifecycleHooks()
    if lib._pageLifecycleHooked then
        return
    end

    if type(SettingsPanel) ~= "table" or type(SettingsPanel.DisplayCategory) ~= "function" then
        if lib._pageLifecycleDeferred or type(CreateFrame) ~= "function" then
            return
        end
        lib._pageLifecycleDeferred = true
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self)
            if type(SettingsPanel) == "table" and type(SettingsPanel.DisplayCategory) == "function" then
                self:UnregisterAllEvents()
                interop.installPageLifecycleHooks()
            end
        end)
        return
    end

    lib._pageLifecycleHooked = true

    hooksecurefunc(SettingsPanel, "DisplayCategory", function(panel)
        local category = panel.GetCurrentCategory and panel:GetCurrentCategory() or nil
        local old = lib._activeLifecycleCategory
        if old == category then
            return
        end

        notifyLifecycleHidden(old)

        lib._activeLifecycleCategory = category
        local cbs = category and lib._pageLifecycleCallbacks[category] or nil
        if cbs then
            if cbs.onDefault or cbs.confirmDefaults then
                cbs._defaultsRestore = interop.installCategoryDefaultsOverride(
                    cbs.onDefault,
                    cbs.onDefaultEnabled,
                    cbs.confirmDefaults,
                    cbs.pageName
                )
            end
            if cbs.onShow then
                cbs.onShow()
            end
        end
    end)

    SettingsPanel:HookScript("OnHide", function()
        notifyLifecycleHidden(lib._activeLifecycleCategory)
        lib._activeLifecycleCategory = nil
    end)
end

function interop.getCurrentSettingsCategory()
    return SettingsPanel and SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory() or nil
end

function interop.isSettingsPanelShown()
    return SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown()
end

function interop.forEachVisibleSettingsFrame(callback)
    local settingsList = SettingsPanel and SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
    local scrollBox = settingsList and settingsList.ScrollBox
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(callback)
    end
end

function interop.reevaluateVisibleSettingsFrames()
    if interop.isSettingsPanelShown() then
        interop.forEachVisibleSettingsFrame(function(frame)
            if frame.EvaluateState then
                frame:EvaluateState()
            end
        end)
    end
end

function interop.refreshVisibleSettingsFrames()
    interop.forEachVisibleSettingsFrame(interop.refreshSettingsFrame)
end

function interop.ensureConfirmDialog(name)
    if not StaticPopupDialogs[name] then
        StaticPopupDialogs[name] = {
            text = "%s",
            button1 = YES,
            button2 = NO,
            OnAccept = function(_, data)
                if data and data.onAccept then
                    data.onAccept()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end
    return name
end

function interop.showConfirmDialog(name, text, data)
    StaticPopup_Show(name, text, nil, data)
end
