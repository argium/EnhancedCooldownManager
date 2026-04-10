-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

-- LibSettingsBuilder: A standalone path-based settings builder for the
-- World of Warcraft Settings API.  Provides proxy controls, composite groups
-- and utility helpers.

local MAJOR, MINOR = "LibSettingsBuilder-1.0", 2
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end

lib.EMBED_CANVAS_TEMPLATE = "SettingsListElementTemplate"
lib.SUBHEADER_TEMPLATE = "SettingsListElementTemplate"
lib.INFOROW_TEMPLATE = "SettingsListElementTemplate"
lib.INPUTROW_TEMPLATE = "SettingsListElementTemplate"
lib.SCROLL_DROPDOWN_TEMPLATE = "SettingsDropdownControlTemplate"

local TOOLTIP_TITLE_COLOR = CreateColor(1, 1, 1, 1)

lib._pageLifecycleCallbacks = lib._pageLifecycleCallbacks or {}
lib._pageLifecycleHooked = lib._pageLifecycleHooked or false

--- Installs one-time hooks on SettingsPanel to fire page-level onShow/onHide
--- callbacks registered via RegisterFromTable.  Defers automatically if
--- SettingsPanel has not been created yet (Blizzard_Settings loads on demand).
local function installPageLifecycleHooks()
    if lib._pageLifecycleHooked then
        return
    end

    if type(SettingsPanel) ~= "table" or type(SettingsPanel.DisplayCategory) ~= "function" then
        -- SettingsPanel not yet loaded; listen for ADDON_LOADED to retry.
        if lib._pageLifecycleDeferred or type(CreateFrame) ~= "function" then
            return
        end
        lib._pageLifecycleDeferred = true
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self)
            if type(SettingsPanel) == "table" and type(SettingsPanel.DisplayCategory) == "function" then
                self:UnregisterAllEvents()
                installPageLifecycleHooks()
            end
        end)
        return
    end

    lib._pageLifecycleHooked = true

    -- DisplayCategory fires for both sidebar clicks and OpenToCategory.
    -- Retrieve the active category via GetCurrentCategory inside the hook.
    hooksecurefunc(SettingsPanel, "DisplayCategory", function(panel)
        local category = panel.GetCurrentCategory and panel:GetCurrentCategory() or nil
        local old = lib._activeLifecycleCategory
        if old == category then
            return
        end

        if old then
            local cbs = lib._pageLifecycleCallbacks[old]
            if cbs and cbs.onHide then
                cbs.onHide()
            end
        end

        lib._activeLifecycleCategory = category
        if category then
            local cbs = lib._pageLifecycleCallbacks[category]
            if cbs and cbs.onShow then
                cbs.onShow()
            end
        end
    end)

    SettingsPanel:HookScript("OnHide", function()
        local active = lib._activeLifecycleCategory
        if active then
            local cbs = lib._pageLifecycleCallbacks[active]
            if cbs and cbs.onHide then
                cbs.onHide()
            end
        end
        lib._activeLifecycleCategory = nil
    end)
end

local listElementKeysToHide = {
    "_lsbSubheaderTitle",
    "_lsbInfoTitle",
    "_lsbInfoValue",
    "_lsbCanvas",
    "_lsbInputTitle",
    "_lsbInputEditBox",
    "_lsbInputPreview",
}

local function copyMixin(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

local function setInitializerExtent(initializer, extent)
    if initializer.SetExtent then
        initializer:SetExtent(extent)
        return
    end

    initializer.GetExtent = function()
        return extent
    end
end

local function getInitializerData(initializer)
    if initializer and initializer._lsbData then
        return initializer._lsbData
    end

    if initializer and initializer.GetData then
        return initializer:GetData()
    end
end

local function getSettingVariable(setting)
    return setting and (setting._lsbVariable or setting._variable)
end

local function registerValueChangedCallback(frame, variable, callback, owner)
    if not variable then
        return
    end

    local handles = frame and frame.cbrHandles
    if handles and handles.SetOnValueChangedCallback then
        handles:SetOnValueChangedCallback(variable, callback, owner or frame)
    end
end

local function makeStableSortKey(value)
    local valueType = type(value)
    if valueType == "number" then
        return "1:" .. string.format("%020.10f", value)
    end
    if valueType == "boolean" then
        return value and "2:true" or "2:false"
    end
    return valueType .. ":" .. tostring(value):lower()
end

local function getOrderedValueEntries(values)
    local entries = {}
    if not values then
        return entries
    end

    for value, label in pairs(values) do
        entries[#entries + 1] = {
            value = value,
            label = label,
            labelSortKey = tostring(label):lower(),
            valueSortKey = makeStableSortKey(value),
        }
    end

    table.sort(entries, function(left, right)
        if left.labelSortKey == right.labelSortKey then
            return left.valueSortKey < right.valueSortKey
        end
        return left.labelSortKey < right.labelSortKey
    end)

    return entries
end

local function resetListElement(frame)
    for _, key in ipairs(listElementKeysToHide) do
        local region = frame[key]
        if region then
            region:Hide()
        end
    end
end

local function hideListElementChildren(frame)
    if not frame or not frame.GetChildren then
        return
    end

    local children = { frame:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if child and child.Hide then
            child:Hide()
        end
    end
end

local function hideListElementRegions(frame)
    if not frame or not frame.GetRegions then
        return
    end

    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local region = regions[i]
        if region and region.Hide then
            region:Hide()
        end
    end
end

local function resetPlainListElementFrame(frame)
    hideListElementChildren(frame)
    hideListElementRegions(frame)
    resetListElement(frame)
end

local function showFrame(frame)
    if frame and frame.Show then
        frame:Show()
    end
end

local function setGameTooltipText(text, wrap)
    GameTooltip:SetText(text, TOOLTIP_TITLE_COLOR, 1, wrap == true)
end

local function setSimpleTooltip(owner, text)
    if not owner or not owner.SetScript then
        return
    end

    owner:SetScript("OnEnter", nil)
    owner:SetScript("OnLeave", nil)

    if not text or text == "" then
        return
    end

    owner:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
        setGameTooltipText(text, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        if GameTooltip_Hide then
            GameTooltip_Hide()
        end
    end)
end

local function evaluateStaticOrFunction(value, ...)
    if type(value) == "function" then
        return value(...)
    end
    return value
end

local function createSubheaderTitle(parent, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 35, -8)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetFontObject(GameFontHighlight)
    if text ~= nil then
        title:SetText(text)
    end
    title:Show()
    return title
end

local function createHeaderTitle(parent, text)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 7, -16)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    if text ~= nil then
        title:SetText(text)
    end
    title:Show()
    return title
end

lib.CreateHeaderTitle = createHeaderTitle
lib.CreateSubheaderTitle = createSubheaderTitle

local function ensureSubheaderTitle(frame)
    if frame._lsbSubheaderTitle then
        return frame._lsbSubheaderTitle
    end

    local title = createSubheaderTitle(frame)
    frame._lsbSubheaderTitle = title
    frame.Title = title
    return title
end

local function ensureInfoRowWidgets(frame)
    if frame._lsbInfoTitle and frame._lsbInfoValue then
        return frame._lsbInfoTitle, frame._lsbInfoValue
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", 37, 0)
    title:SetPoint("RIGHT", frame, "CENTER", -85, 0)
    title:SetJustifyH("LEFT")

    local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("LEFT", frame, "CENTER", -80, 0)
    value:SetJustifyH("LEFT")

    frame._lsbInfoTitle = title
    frame._lsbInfoValue = value
    frame.Title = title
    frame.Value = value

    return title, value
end

local function ensureHeaderRowWidgets(frame)
    if frame._lsbHeaderTitle then
        return frame
    end

    frame._lsbHeaderTitle = createHeaderTitle(frame)
    frame._lsbHeaderActionButtons = frame._lsbHeaderActionButtons or {}

    return frame
end

local function getSettingsListHeader()
    local settingsList = SettingsPanel and SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
    return settingsList and settingsList.Header or nil
end

local function hideHeaderActionButtons(frame)
    for _, button in ipairs(frame._lsbHeaderActionButtons or {}) do
        button:SetScript("OnClick", nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
        button:Hide()
    end
end

local function applyHeaderActionButtons(frame, actions, actionParent, rightAnchor)
    ensureHeaderRowWidgets(frame)
    local buttons = frame._lsbHeaderActionButtons
    local anchor = nil
    local visibleCount = 0

    actionParent = actionParent or frame
    hideHeaderActionButtons(frame)

    for _, action in ipairs(actions or {}) do
        if not evaluateStaticOrFunction(action.hidden, action, frame) then
            visibleCount = visibleCount + 1

            local button = buttons[visibleCount]
            if button and button._lsbActionParent ~= actionParent then
                button:Hide()
                button = nil
            end
            if not button then
                button = CreateFrame("Button", nil, actionParent, "UIPanelButtonTemplate")
                button._lsbActionParent = actionParent
                buttons[visibleCount] = button
            end

            button:ClearAllPoints()
            if anchor then
                button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
            elseif rightAnchor then
                button:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)
            else
                button:SetPoint("RIGHT", actionParent, "RIGHT", -20, 0)
            end
            button:SetSize(action.width or 100, action.height or 22)
            button:SetText(action.text or action.name or "")
            if button.SetEnabled then
                local enabled = evaluateStaticOrFunction(action.enabled, action, frame)
                if enabled == nil then
                    enabled = true
                end
                button:SetEnabled(enabled)
            end
            setSimpleTooltip(button, evaluateStaticOrFunction(action.tooltip, action, frame))
            button:SetScript("OnClick", function()
                if action.onClick then
                    action.onClick(action, frame)
                end
            end)
            button:Show()
            anchor = button
        end
    end
end

local function applySubheaderFrame(frame, data)
    local title = ensureSubheaderTitle(frame)
    title:SetText(data.name)
    title:Show()
end

local function applyHeaderFrame(frame, data)
    ensureHeaderRowWidgets(frame)
    local settingsHeader = data.attachToCategoryHeader and getSettingsListHeader() or nil
    local actionParent = settingsHeader or frame
    local rightAnchor = settingsHeader and settingsHeader.DefaultsButton or nil

    if frame._lsbHeaderTitle then
        frame._lsbHeaderTitle:ClearAllPoints()
        frame._lsbHeaderTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -16)
        frame._lsbHeaderTitle:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
        frame._lsbHeaderTitle:SetText(data.name or "")
    end

    applyHeaderActionButtons(frame, data.actions, actionParent, rightAnchor)

    if frame._lsbHeaderTitle then
        if data.hideTitle then
            frame._lsbHeaderTitle:Hide()
            return
        end

        local titleRight = -20
        local buttons = frame._lsbHeaderActionButtons or {}
        for i = 1, #buttons do
            local button = buttons[i]
            if button and button.IsShown and button:IsShown() then
                frame._lsbHeaderTitle:ClearAllPoints()
                frame._lsbHeaderTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 7, -16)
                frame._lsbHeaderTitle:SetPoint("RIGHT", button, "LEFT", -12, 0)
                titleRight = nil
                break
            end
        end
        if titleRight then
            frame._lsbHeaderTitle:SetPoint("RIGHT", frame, "RIGHT", titleRight, 0)
        end
        frame._lsbHeaderTitle:Show()
    end
end

local function applyInfoRowFrame(frame, data)
    local title, value = ensureInfoRowWidgets(frame)
    local name = evaluateStaticOrFunction(data.name, frame, data)
    local resolvedValue = evaluateStaticOrFunction(data.value, frame, data)
    local isWide = data.wide == true or name == nil or name == ""
    local isMultiline = data.multiline == true

    title:ClearAllPoints()
    value:ClearAllPoints()

    if isWide then
        title:SetText("")
        title:Hide()
        value:SetPoint("TOPLEFT", frame, "TOPLEFT", 37, isMultiline and -4 or 0)
        value:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    else
        title:SetText(name or "")
        title:SetPoint("LEFT", 37, 0)
        title:SetPoint("RIGHT", frame, "CENTER", -85, 0)
        title:Show()
        value:SetPoint("LEFT", frame, "CENTER", -80, 0)
        value:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    end

    if value.SetWordWrap then
        value:SetWordWrap(isMultiline)
    end
    if value.SetJustifyV then
        value:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
    end
    if value.SetJustifyH then
        value:SetJustifyH("LEFT")
    end
    value:SetText(resolvedValue or "")
    if not isWide then
        title:Show()
    end
    value:Show()
end

local function ensureInputRowWidgets(frame)
    if frame._lsbInputTitle and frame._lsbInputEditBox and frame._lsbInputPreview then
        return frame._lsbInputTitle, frame._lsbInputEditBox, frame._lsbInputPreview
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:SetAutoFocus(false)

    local preview = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    preview:SetJustifyH("LEFT")
    preview:SetJustifyV("TOP")
    preview:SetWordWrap(false)
    preview:Hide()

    frame._lsbInputTitle = title
    frame._lsbInputEditBox = editBox
    frame._lsbInputPreview = preview
    frame.Title = title
    frame.EditBox = editBox
    frame.Preview = preview

    return title, editBox, preview
end

local function setInputPreviewText(frame, text)
    local preview = frame._lsbInputPreview
    if not preview then
        return
    end

    text = text and tostring(text) or ""
    preview:SetText(text)
    if text ~= "" then
        preview:Show()
    else
        preview:Hide()
    end
end

local function cancelInputPreviewTimer(frame)
    local timer = frame and frame._lsbInputPreviewTimer
    if timer and timer.Cancel then
        timer:Cancel()
    end
    if frame then
        frame._lsbInputPreviewTimer = nil
    end
end

local function syncInputRowText(frame, value)
    local editBox = frame and frame._lsbInputEditBox
    if not editBox then
        return
    end

    value = value == nil and "" or tostring(value)
    if editBox.GetText and editBox:GetText() == value then
        return
    end

    frame._lsbUpdatingInputText = true
    editBox:SetText(value)
    frame._lsbUpdatingInputText = nil
end

local function resolveInputPreview(frame)
    local data = frame and frame._lsbInputData
    local setting = frame and frame._lsbInputSetting
    if not data or not data.resolveText then
        setInputPreviewText(frame, nil)
        return
    end

    local value = setting and setting.GetValue and setting:GetValue() or nil
    setInputPreviewText(frame, data.resolveText(value, setting, frame))
end

local function scheduleInputPreview(frame, immediate)
    cancelInputPreviewTimer(frame)

    local data = frame and frame._lsbInputData
    if not data or not data.resolveText then
        setInputPreviewText(frame, nil)
        return
    end

    local delay = immediate and 0 or (data.debounce or 0)
    if delay > 0 and C_Timer and C_Timer.NewTimer then
        frame._lsbInputPreviewTimer = C_Timer.NewTimer(delay, function()
            frame._lsbInputPreviewTimer = nil
            resolveInputPreview(frame)
        end)
        return
    end

    resolveInputPreview(frame)
end

local function applyInputRowEnabledState(frame, enabled)
    if not frame then
        return
    end

    if frame.SetAlpha then
        frame:SetAlpha(enabled and 1 or 0.5)
    end

    local editBox = frame._lsbInputEditBox
    if not editBox then
        return
    end

    if editBox.SetEnabled then
        editBox:SetEnabled(enabled)
    end
    if editBox.EnableMouse then
        editBox:EnableMouse(enabled)
    end
end

local function applyInputRowFrame(frame, data)
    local title, editBox, preview = ensureInputRowWidgets(frame)
    local hasPreview = data.resolveText ~= nil

    title:ClearAllPoints()
    title:SetPoint(hasPreview and "TOPLEFT" or "LEFT", frame, hasPreview and "TOPLEFT" or "LEFT", 37, hasPreview and -6 or 0)
    title:SetPoint("RIGHT", frame, "CENTER", -85, 0)
    title:SetJustifyV(hasPreview and "TOP" or "MIDDLE")
    title:SetText(data.name)
    title:Show()

    editBox:ClearAllPoints()
    editBox:SetPoint(hasPreview and "TOPLEFT" or "LEFT", frame, "CENTER", -80, hasPreview and -2 or 0)
    editBox:SetSize(data.width or 140, 20)
    if editBox.SetNumeric then
        editBox:SetNumeric(data.numeric == true)
    end
    if editBox.SetMaxLetters and data.maxLetters then
        editBox:SetMaxLetters(data.maxLetters)
    end
    if editBox.SetTextInsets then
        editBox:SetTextInsets(6, 6, 0, 0)
    end
    editBox:Show()

    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -3)
    preview:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    if hasPreview then
        preview:Show()
    else
        preview:Hide()
    end

    frame._lsbInputData = data
    frame._lsbInputSetting = data.setting
    editBox._lsbOwnerFrame = frame

    if not editBox._lsbInputScriptsBound then
        editBox:SetScript("OnTextChanged", function(self)
            local owner = self._lsbOwnerFrame
            if not owner or owner._lsbUpdatingInputText then
                return
            end

            local setting = owner._lsbInputSetting
            local text = self:GetText() or ""
            if setting and setting.SetValue then
                setting:SetValue(text)
            end

            local inputData = owner._lsbInputData
            if inputData and inputData.onTextChanged then
                inputData.onTextChanged(text, setting, owner)
            end

            scheduleInputPreview(owner, false)
        end)
        editBox:SetScript("OnEnterPressed", function(self)
            if self.ClearFocus then
                self:ClearFocus()
            end
        end)
        editBox:SetScript("OnEscapePressed", function(self)
            local owner = self._lsbOwnerFrame
            if owner then
                local setting = owner._lsbInputSetting
                local value = setting and setting.GetValue and setting:GetValue() or ""
                syncInputRowText(owner, value)
                scheduleInputPreview(owner, true)
            end
            if self.ClearFocus then
                self:ClearFocus()
            end
        end)
        editBox._lsbInputScriptsBound = true
    end

    syncInputRowText(frame, data.setting and data.setting.GetValue and data.setting:GetValue() or "")

    local ownVariable = data.settingVariable
    registerValueChangedCallback(frame, ownVariable, function()
        local currentSetting = frame._lsbInputSetting
        local value = currentSetting and currentSetting.GetValue and currentSetting:GetValue() or ""
        syncInputRowText(frame, value)
    end, frame)

    if data.watchVariables then
        for _, variable in ipairs(data.watchVariables) do
            if variable ~= ownVariable then
                registerValueChangedCallback(frame, variable, function()
                    scheduleInputPreview(frame, true)
                end, frame)
            end
        end
    end

    scheduleInputPreview(frame, true)
end

local function applyEmbedCanvasFrame(frame, data, initializer)
    local canvas = data.canvas
    if not canvas then
        return
    end

    frame._lsbCanvas = canvas
    canvas:SetParent(frame)
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", 0, 0)
    canvas:SetPoint("TOPRIGHT", 0, 0)
    canvas:SetHeight(initializer:GetExtent())
    canvas:Show()
end

local function ensureListElementCallbackHandles(frame)
    if frame.cbrHandles or not (Settings and Settings.CreateCallbackHandleContainer) then
        return
    end

    frame.cbrHandles = Settings.CreateCallbackHandleContainer()
end

local function initializerShouldShow(initializer)
    if initializer and initializer.ShouldShow then
        return initializer:ShouldShow()
    end

    if initializer and initializer._shownPredicates then
        for _, predicate in ipairs(initializer._shownPredicates) do
            if not predicate() then
                return false
            end
        end
    end

    return true
end

local function initializerIsEnabled(initializer)
    if initializer and initializer.EvaluateModifyPredicates then
        return initializer:EvaluateModifyPredicates()
    end

    if initializer and initializer._modifyPredicates then
        for _, predicate in ipairs(initializer._modifyPredicates) do
            if not predicate() then
                return false
            end
        end
    end

    return true
end

local function createCustomListRowInitializer(template, data, extent, initFrame)
    local initializer = Settings.CreateElementInitializer(template, data)
    setInitializerExtent(initializer, extent)

    initializer.InitFrame = function(self, frame)
        ensureListElementCallbackHandles(frame)

        frame.data = self.data
        if frame.Text then
            frame.Text:SetText("")
        end
        if frame.NewFeature then
            frame.NewFeature:Hide()
        end

        resetPlainListElementFrame(frame)
        initFrame(frame, self.data, self)
        self._lsbActiveFrame = frame

        if not frame._lsbHasCustomEvaluateState then
            frame.EvaluateState = function(control)
                local currentInitializer = control.GetElementData and control:GetElementData()
                    or control._lsbInitializer
                if currentInitializer and currentInitializer.SetEnabled then
                    currentInitializer:SetEnabled(initializerIsEnabled(currentInitializer))
                end
                control:SetShown(initializerShouldShow(currentInitializer))
            end
            frame._lsbHasCustomEvaluateState = true
        end

        frame._lsbInitializer = self
        frame:EvaluateState()
    end

    initializer.Resetter = function(self, frame)
        if frame.cbrHandles and frame.cbrHandles.Unregister then
            frame.cbrHandles:Unregister()
        end
        if frame.Text then
            frame.Text:SetText("")
        end
        if frame.NewFeature then
            frame.NewFeature:Hide()
        end
        if frame._lsbCanvas then
            frame._lsbCanvas:Hide()
            frame._lsbCanvas = nil
        end
        if self._lsbActiveFrame == frame then
            self._lsbActiveFrame = nil
        end
        if self._lsbResetFrame then
            self._lsbResetFrame(frame, self)
        end

        resetPlainListElementFrame(frame)
        frame.data = nil
        frame._lsbInitializer = nil
    end

    return initializer
end

local ScrollDropdownMethods = {}

function ScrollDropdownMethods:GetSetting()
    if self.initializer and self.initializer.GetSetting then
        return self.initializer:GetSetting()
    end
    return self.lsbData and self.lsbData.setting or nil
end

function ScrollDropdownMethods:RefreshDropdownText(value)
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

function ScrollDropdownMethods:SetValue(value)
    self:RefreshDropdownText(value)
end

function ScrollDropdownMethods:InitDropdown()
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

local function configureScrollDropdownFrame(frame, initializer)
    if not frame._lsbOriginalSetValue then
        frame._lsbOriginalSetValue = frame.SetValue
    end

    copyMixin(frame, ScrollDropdownMethods)
    frame.initializer = initializer
    frame.lsbData = getInitializerData(initializer) or {}
    initializer._lsbActiveFrame = frame
    frame:InitDropdown()
end

if not lib._scrollDropdownHookInstalled and hooksecurefunc and SettingsDropdownControlMixin then
    hooksecurefunc(SettingsDropdownControlMixin, "Init", function(frame, initializer)
        local data = getInitializerData(initializer)
        if not data or data._lsbKind ~= "scrollDropdown" then
            if frame._lsbOriginalSetValue then
                frame.SetValue = frame._lsbOriginalSetValue
            end
            frame.initializer = initializer
            frame.lsbData = nil
            return
        end

        configureScrollDropdownFrame(frame, initializer)
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

local function applyCollectionRowStyle(row, item)
    local alpha = item and item.alpha or 1

    if row._label and row._label.SetFontObject and item and item.labelFontObject then
        row._label:SetFontObject(item.labelFontObject)
    end
    if row._label and row._label.SetTextColor and item and item.labelColor then
        row._label:SetTextColor(
            item.labelColor[1] or 1,
            item.labelColor[2] or 1,
            item.labelColor[3] or 1,
            item.labelColor[4] or 1
        )
    end
    if row._label and row._label.SetAlpha then
        row._label:SetAlpha(alpha)
    end
    if row._icon and row._icon.SetAlpha then
        row._icon:SetAlpha(alpha)
    end
    if row._icon and row._icon.SetDesaturated then
        row._icon:SetDesaturated(item and item.iconDesaturated == true or false)
    end
    if row._icon and row._icon.SetVertexColor then
        local color = item and item.iconVertexColor
        if color then
            row._icon:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1)
        else
            row._icon:SetVertexColor(1, 1, 1, 1)
        end
    end
end

local function bindCollectionRowTooltip(row, item)
    if not row or not row.SetScript then
        return
    end

    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)

    if not item then
        return
    end

    row:SetScript("OnEnter", function(self)
        if self._highlight and self._highlight.Show then
            self._highlight:Show()
        end
        if item.onEnter then
            item.onEnter(self, item)
        elseif item.tooltip then
            if GameTooltip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if GameTooltip.ClearLines then
                    GameTooltip:ClearLines()
                end
                setGameTooltipText(item.tooltip, true)
                GameTooltip:Show()
            end
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self._highlight and self._highlight.Hide then
            self._highlight:Hide()
        end
        if item.onLeave then
            item.onLeave(self, item)
        elseif GameTooltip_Hide then
            GameTooltip_Hide()
        end
    end)
end

local function ensureHighlight(row)
    if row._highlight then
        return row._highlight
    end

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    highlight:Hide()
    row._highlight = highlight
    return highlight
end

local function ensureSwatchCollectionRow(row)
    if row._lsbSwatchRow then
        return
    end

    row._lsbSwatchRow = true
    row:SetHeight(26)
    ensureHighlight(row)

    row._icon = row:CreateTexture(nil, "ARTWORK")
    row._icon:SetPoint("LEFT", 0, 0)
    row._icon:SetSize(16, 16)
    row._icon:Hide()

    row._label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row._label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row._label:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    row._label:SetJustifyH("LEFT")
    row._label:SetWordWrap(false)

    row._swatch = lib.CreateColorSwatch(row)
    row._swatch:SetPoint("RIGHT", row, "RIGHT", -18, 0)
end

local function refreshSwatchCollectionRow(row, item)
    ensureSwatchCollectionRow(row)

    if item.icon then
        row._icon:SetTexture(item.icon)
        row._icon:Show()
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
        row._label:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    else
        row._icon:SetTexture(nil)
        row._icon:Hide()
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row, "LEFT", 0, 0)
        row._label:SetPoint("RIGHT", row, "RIGHT", -100, 0)
    end

    row._label:SetText(item.label or "")
    applyCollectionRowStyle(row, item)
    bindCollectionRowTooltip(row, item)

    local color = item.color or {}
    local colorValue = color.value or color
    row._swatch:SetColorRGB(colorValue.r or 1, colorValue.g or 1, colorValue.b or 1)
    setSimpleTooltip(row._swatch, item.swatchTooltip or color.tooltip)
    row._swatch:SetScript("OnClick", function()
        local onClick = color.onClick or item.onColorClick
        if onClick then
            onClick(item, row)
        end
    end)
    if row._swatch.SetEnabled then
        row._swatch:SetEnabled(
            evaluateStaticOrFunction(item.enabled, item, row) ~= false
                and evaluateStaticOrFunction(color.enabled, item, row) ~= false
        )
    end
end

local function ensureEditorCollectionRow(row)
    if row._lsbEditorRow then
        return
    end

    row._lsbEditorRow = true
    row:SetHeight(34)
    ensureHighlight(row)

    row._label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row._label:SetPoint("LEFT", row, "LEFT", 10, 0)
    row._label:SetWidth(70)
    row._label:SetJustifyH("LEFT")

    row._fieldWidgets = {}
    row._swatch = lib.CreateColorSwatch(row)
    row._removeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._removeButton:SetSize(70, 22)
end

local function ensureEditorFieldWidgets(row, index)
    local widgets = row._fieldWidgets[index]
    if widgets then
        return widgets
    end

    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetJustifyH("LEFT")

    widgets = {
        slider = slider,
        valueText = valueText,
    }
    row._fieldWidgets[index] = widgets
    return widgets
end

local function refreshEditorCollectionRow(row, item)
    ensureEditorCollectionRow(row)

    row._label:SetText(item.label or "")
    applyCollectionRowStyle(row, item)
    bindCollectionRowTooltip(row, item)

    local labelAnchor = row._label
    local previousControl = labelAnchor
    local previousValueText = nil
    local fields = item.fields or {}

    for i = 1, #fields do
        local field = fields[i]
        local widgets = ensureEditorFieldWidgets(row, i)
        local slider = widgets.slider
        local valueText = widgets.valueText
        local minValue, maxValue, step = field.min or 0, field.max or 1, field.step or 1

        if field.getRange then
            local nextMin, nextMax, nextStep = field.getRange(item, field.value)
            if nextMin ~= nil then
                minValue = nextMin
            end
            if nextMax ~= nil then
                maxValue = nextMax
            end
            if nextStep ~= nil then
                step = nextStep
            end
        end

        field.min = minValue
        field.max = maxValue
        field.step = step

        slider:ClearAllPoints()
        if previousValueText then
            slider:SetPoint("LEFT", previousValueText, "RIGHT", field.gap or 12, 0)
        else
            slider:SetPoint("LEFT", row._label, "RIGHT", 8, 0)
        end
        slider:SetWidth(field.sliderWidth or 120)

        valueText:ClearAllPoints()
        valueText:SetPoint("LEFT", slider, "RIGHT", 6, 0)
        valueText:SetWidth(field.valueWidth or 40)

        configureInlineSlider(slider, valueText, field, function(rounded)
            if row._lsbRefreshing then
                return
            end
            if field.onValueChanged then
                field.onValueChanged(rounded, item, row)
            end
        end)

        previousControl = slider
        previousValueText = valueText
    end

    local color = item.color or {}
    row._swatch:ClearAllPoints()
    if previousValueText then
        row._swatch:SetPoint("LEFT", previousValueText, "RIGHT", 10, 0)
    else
        row._swatch:SetPoint("LEFT", row._label, "RIGHT", 10, 0)
    end

    row._removeButton:ClearAllPoints()
    row._removeButton:SetPoint("LEFT", row._swatch, "RIGHT", 8, 0)
    row._removeButton:SetSize((item.remove and item.remove.width) or 70, 22)
    row._removeButton:SetText((item.remove and item.remove.text) or REMOVE or "Remove")
    row._removeButton:SetScript("OnClick", function()
        if item.remove and item.remove.onClick then
            item.remove.onClick(item, row)
        end
    end)
    if row._removeButton.SetEnabled then
        row._removeButton:SetEnabled(item.remove == nil or item.remove.enabled ~= false)
    end
    setSimpleTooltip(row._removeButton, item.remove and item.remove.tooltip)

    row._lsbRefreshing = true
    for i = 1, #fields do
        local field = fields[i]
        local widgets = row._fieldWidgets[i]
        widgets.slider._lsbMinValue = field.min or 0
        widgets.slider._lsbMaxValue = field.max or 1
        widgets.slider._lsbStep = field.step or 1
        if widgets.slider.SetValue then
            widgets.slider:SetValue(field.value or 0)
        end
        widgets.valueText:SetText(tostring(field.value or 0))
    end
    row._lsbRefreshing = nil

    row._swatch:SetColorRGB((color.value and color.value.r) or 1, (color.value and color.value.g) or 1, (color.value and color.value.b) or 1)
    row._swatch:SetScript("OnClick", function()
        if color.onClick then
            color.onClick(item, row)
        end
    end)
    setSimpleTooltip(row._swatch, color.tooltip)
    if row._swatch.SetEnabled then
        row._swatch:SetEnabled(color.enabled ~= false)
    end
end

local ACTION_BUTTON_ORDER = { "up", "down", "move", "delete" }

local function ensureActionsCollectionRow(row)
    if row._lsbActionsRow then
        return
    end

    row._lsbActionsRow = true
    row:SetHeight(26)
    ensureHighlight(row)

    row._icon = row:CreateTexture(nil, "ARTWORK")
    row._icon:SetPoint("LEFT", 0, 0)
    row._icon:SetSize(20, 20)

    row._label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
    row._label:SetJustifyH("LEFT")
    row._label:SetWordWrap(false)

    row._buttons = {}
    for _, key in ipairs(ACTION_BUTTON_ORDER) do
        local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row._buttons[key] = button
    end
end

local function refreshActionsCollectionRow(row, item)
    ensureActionsCollectionRow(row)

    row._label:SetText(item.label or "")
    row._icon:SetTexture(item.icon or 134400)
    applyCollectionRowStyle(row, item)
    bindCollectionRowTooltip(row, item)

    local anchor = nil
    for _, key in ipairs(ACTION_BUTTON_ORDER) do
        local button = row._buttons[key]
        local action = item.actions and item.actions[key] or nil

        button:ClearAllPoints()
        button:SetScript("OnClick", nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)

        if action and not evaluateStaticOrFunction(action.hidden, action, row, item) then
            if not anchor then
                button:SetPoint("RIGHT", row, "RIGHT", 0, 0)
            else
                button:SetPoint("RIGHT", anchor, "LEFT", -2, 0)
            end
            button:SetSize(action.width or 26, action.height or 22)
            button:SetText(action.text or "")
            if button.SetEnabled then
                local enabled = evaluateStaticOrFunction(action.enabled, action, row, item)
                if enabled == nil then
                    enabled = true
                end
                button:SetEnabled(enabled)
            end
            setSimpleTooltip(button, evaluateStaticOrFunction(action.tooltip, action, row, item))
            button:SetScript("OnClick", function()
                if action.onClick then
                    action.onClick(item, row, action)
                end
            end)
            button:Show()
            anchor = button
        else
            button:Hide()
        end
    end

    if anchor then
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
        row._label:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
    else
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
        row._label:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    end
end

local function ensureModeInputRow(row)
    if row._lsbModeInputRow then
        return
    end

    row._lsbModeInputRow = true
    row:SetHeight(28)

    row._modeButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._modeButton:SetPoint("LEFT", row, "LEFT", 0, 0)
    row._modeButton:SetSize(58, 22)

    row._editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row._editBox:SetPoint("LEFT", row._modeButton, "RIGHT", 6, 0)
    row._editBox:SetSize(120, 20)
    row._editBox:SetAutoFocus(false)
    if row._editBox.SetNumeric then
        row._editBox:SetNumeric(true)
    end
    if row._editBox.SetMaxLetters then
        row._editBox:SetMaxLetters(10)
    end
    if row._editBox.SetTextInsets then
        row._editBox:SetTextInsets(6, 6, 0, 0)
    end

    row._placeholder = row._editBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row._placeholder:SetPoint("LEFT", row._editBox, "LEFT", 6, 0)
    row._placeholder:SetPoint("RIGHT", row._editBox, "RIGHT", -6, 0)
    row._placeholder:SetJustifyH("LEFT")
    row._placeholder:SetWordWrap(false)

    row._previewIcon = row:CreateTexture(nil, "ARTWORK")
    row._previewIcon:SetPoint("LEFT", row._editBox, "RIGHT", 8, 0)
    row._previewIcon:SetSize(16, 16)
    row._previewIcon:Hide()

    row._previewLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row._previewLabel:SetPoint("LEFT", row._previewIcon, "RIGHT", 4, 0)
    row._previewLabel:SetJustifyH("LEFT")
    row._previewLabel:SetWordWrap(false)
    row._previewLabel:Hide()

    row._submitButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._submitButton:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row._submitButton:SetSize(44, 22)
    row._submitButton:SetText(ADD or "Add")

    row._previewLabel:SetPoint("RIGHT", row._submitButton, "LEFT", -6, 0)

    row._editBox:SetScript("OnEditFocusGained", function()
        row._lsbHasFocus = true
        if row._lsbTrailerRefresh then
            row._lsbTrailerRefresh(row)
        end
    end)
    row._editBox:SetScript("OnEditFocusLost", function()
        row._lsbHasFocus = false
        if row._lsbTrailerRefresh then
            row._lsbTrailerRefresh(row)
        end
    end)
    row._editBox:SetScript("OnTextChanged", function(self)
        if row._lsbSyncingText then
            return
        end
        local trailer = row._lsbTrailerData
        if trailer and trailer.onTextChanged then
            trailer.onTextChanged(self:GetText() or "", trailer, row, row._lsbSectionData)
        end
    end)
    row._editBox:SetScript("OnEnterPressed", function()
        local trailer = row._lsbTrailerData
        if trailer and trailer.onSubmit then
            local keepFocus = trailer.onSubmit(trailer, row, row._lsbSectionData)
            if keepFocus then
                row._editBox:SetFocus()
                row._editBox:HighlightText()
            end
        end
    end)
    row._editBox:SetScript("OnTabPressed", function()
        local trailer = row._lsbTrailerData
        if trailer and trailer.onTabPressed then
            local keepFocus = trailer.onTabPressed(trailer, row, row._lsbSectionData)
            if keepFocus then
                row._editBox:SetFocus()
                row._editBox:HighlightText()
            end
        end
    end)
    row._editBox:SetScript("OnEscapePressed", function(self)
        local trailer = row._lsbTrailerData
        if trailer and trailer.onEscapePressed then
            trailer.onEscapePressed(trailer, row, row._lsbSectionData)
        end
        if self.ClearFocus then
            self:ClearFocus()
        end
        row._lsbHasFocus = false
        if row._lsbTrailerRefresh then
            row._lsbTrailerRefresh(row)
        end
    end)
end

local function refreshModeInputRow(row, trailer, sectionData)
    ensureModeInputRow(row)

    row._lsbTrailerData = trailer
    row._lsbSectionData = sectionData

    row._lsbTrailerRefresh = function(activeRow)
        local currentTrailer = activeRow._lsbTrailerData or {}
        local text = currentTrailer.inputText or ""

        activeRow._modeButton:SetText(currentTrailer.modeText or "")
        setSimpleTooltip(activeRow._modeButton, currentTrailer.modeTooltip)
        activeRow._modeButton:SetScript("OnClick", function()
            if currentTrailer.onToggleMode then
                currentTrailer.onToggleMode(currentTrailer, activeRow, activeRow._lsbSectionData)
            end
        end)
        if activeRow._modeButton.SetEnabled then
            activeRow._modeButton:SetEnabled(currentTrailer.disabled ~= true and currentTrailer.modeEnabled ~= false)
        end

        if activeRow._editBox.GetText and activeRow._editBox:GetText() ~= text then
            activeRow._lsbSyncingText = true
            activeRow._editBox:SetText(text)
            activeRow._lsbSyncingText = nil
        end
        if activeRow._editBox.SetEnabled then
            activeRow._editBox:SetEnabled(currentTrailer.disabled ~= true and currentTrailer.inputEnabled ~= false)
        end

        activeRow._placeholder:SetText(currentTrailer.placeholder or "")
        if activeRow._lsbHasFocus or text ~= "" then
            activeRow._placeholder:Hide()
        else
            activeRow._placeholder:Show()
        end

        if currentTrailer.previewIcon then
            activeRow._previewIcon:SetTexture(currentTrailer.previewIcon)
            activeRow._previewIcon:Show()
        else
            activeRow._previewIcon:SetTexture(nil)
            activeRow._previewIcon:Hide()
        end

        if currentTrailer.previewText and currentTrailer.previewText ~= "" then
            activeRow._previewLabel:SetText(currentTrailer.previewText)
            activeRow._previewLabel:Show()
        else
            activeRow._previewLabel:SetText("")
            activeRow._previewLabel:Hide()
        end

        activeRow._submitButton:SetText(currentTrailer.submitText or ADD or "Add")
        setSimpleTooltip(activeRow._submitButton, currentTrailer.submitTooltip)
        activeRow._submitButton:SetScript("OnClick", function()
            if currentTrailer.onSubmit then
                local keepFocus = currentTrailer.onSubmit(currentTrailer, activeRow, activeRow._lsbSectionData)
                if keepFocus then
                    activeRow._editBox:SetFocus()
                    activeRow._editBox:HighlightText()
                end
            end
        end)
        if activeRow._submitButton.SetEnabled then
            activeRow._submitButton:SetEnabled(currentTrailer.disabled ~= true and currentTrailer.submitEnabled ~= false)
        end
    end

    row._lsbTrailerRefresh(row)
end

local function ensureCollectionContent(frame)
    if frame._lsbCollectionContent then
        showFrame(frame._lsbCollectionContent)
        return frame._lsbCollectionContent
    end

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    content:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    content:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame._lsbCollectionContent = content
    return content
end

local function ensureFlatCollectionWidgets(frame, data)
    if frame._lsbCollectionScrollBox then
        showFrame(frame._lsbCollectionScrollBox)
        showFrame(frame._lsbCollectionScrollBar)
        return
    end

    local insetLeft = data.insetLeft or 37
    local insetRight = data.insetRight or 20
    local insetTop = data.insetTop or 0
    local insetBottom = data.insetBottom or 10

    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", frame, "TOPLEFT", insetLeft, insetTop)
    scrollBox:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, insetBottom)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(data.rowHeight or 26)
    view:SetElementInitializer("Frame", function(rowFrame, rowData)
        local preset = rowData.preset or data.preset
        if preset == "swatch" then
            refreshSwatchCollectionRow(rowFrame, rowData.item)
        elseif preset == "editor" then
            refreshEditorCollectionRow(rowFrame, rowData.item)
        end
    end)

    local dataProvider = CreateDataProvider()
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    scrollBox:SetDataProvider(dataProvider)

    frame._lsbCollectionScrollBox = scrollBox
    frame._lsbCollectionScrollBar = scrollBar
    frame._lsbCollectionView = view
    frame._lsbCollectionDataProvider = dataProvider
end

local function refreshFlatCollection(frame, data)
    ensureFlatCollectionWidgets(frame, data)

    local scrollBox = frame._lsbCollectionScrollBox
    local dataProvider = frame._lsbCollectionDataProvider
    local items = data.items and data.items(frame) or {}

    if dataProvider and dataProvider.Flush then
        dataProvider:Flush()
    end

    for _, item in ipairs(items or {}) do
        if dataProvider and dataProvider.Insert then
            dataProvider:Insert({
                preset = data.preset,
                item = item,
            })
        end
    end

    if scrollBox and scrollBox.SetDataProvider then
        scrollBox:SetDataProvider(dataProvider)
    end
end

local function ensureSectionHeaderRow(content, headers, sectionKey, title)
    local row = headers[sectionKey]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, content)
    row:SetHeight(28)
    row._title = createSubheaderTitle(row, title)
    headers[sectionKey] = row
    return row
end

local function ensureSectionEmptyLabel(content, labels, sectionKey)
    local label = labels[sectionKey]
    if label then
        return label
    end

    label = content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    label:SetJustifyH("LEFT")
    labels[sectionKey] = label
    return label
end

local function refreshSectionedCollection(frame, data)
    local content = ensureCollectionContent(frame)
    local sections = data.sections and data.sections(frame) or {}
    local headers = frame._lsbSectionHeaders or {}
    local rowPools = frame._lsbSectionRowPools or {}
    local emptyLabels = frame._lsbSectionEmptyLabels or {}
    local trailerRows = frame._lsbSectionTrailerRows or {}
    local y = 0
    local insetLeft = data.insetLeft or 37
    local insetRight = data.insetRight or 20
    local rowSpacing = data.rowSpacing or 4
    local sectionSpacing = data.sectionSpacing or 12

    frame._lsbSectionHeaders = headers
    frame._lsbSectionRowPools = rowPools
    frame._lsbSectionEmptyLabels = emptyLabels
    frame._lsbSectionTrailerRows = trailerRows

    for sectionKey, pool in pairs(rowPools) do
        for _, row in ipairs(pool) do
            row:Hide()
        end
    end
    for _, row in pairs(headers) do
        row:Hide()
    end
    for _, label in pairs(emptyLabels) do
        label:Hide()
    end
    for _, trailer in pairs(trailerRows) do
        trailer:Hide()
    end

    for _, section in ipairs(sections) do
        local sectionKey = section.key or section.name or tostring(_)
        local header = ensureSectionHeaderRow(content, headers, sectionKey, section.title or section.name or "")
        header._title:SetText(section.title or section.name or "")
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
        header:SetPoint("RIGHT", content, "RIGHT", 0, 0)
        header:Show()
        y = y - (section.headerHeight or 28)

        local items = section.items or {}
        local pool = rowPools[sectionKey] or {}
        rowPools[sectionKey] = pool

        if #items == 0 and section.emptyText then
            local label = ensureSectionEmptyLabel(content, emptyLabels, sectionKey)
            label:SetText(section.emptyText)
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", content, "TOPLEFT", insetLeft, y)
            label:Show()
            y = y - ((section.emptyHeight or 26) + rowSpacing)
        end

        for index, item in ipairs(items) do
            local row = pool[index]
            if not row then
                row = CreateFrame("Frame", nil, content)
                pool[index] = row
            end

            refreshActionsCollectionRow(row, item)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", content, "TOPLEFT", insetLeft, y)
            row:SetPoint("RIGHT", content, "RIGHT", -insetRight, 0)
            row:Show()
            y = y - ((section.rowHeight or 26) + rowSpacing)
        end

        if section.trailer and section.trailer.preset == "modeInput" then
            local trailerRow = trailerRows[sectionKey]
            if not trailerRow then
                trailerRow = CreateFrame("Frame", nil, content)
                trailerRows[sectionKey] = trailerRow
            end

            refreshModeInputRow(trailerRow, section.trailer, section)
            trailerRow:ClearAllPoints()
            trailerRow:SetPoint("TOPLEFT", content, "TOPLEFT", insetLeft, y)
            trailerRow:SetPoint("RIGHT", content, "RIGHT", -insetRight, 0)
            trailerRow:Show()
            y = y - (section.trailerHeight or 28)
        end

        y = y - (section.spacingAfter or sectionSpacing)
    end
end

local function applyCollectionFrame(frame, data, initializer)
    frame.OnDefault = data.onDefault
    frame._lsbCollectionData = data
    frame._lsbCollectionInitializer = initializer

    if data.sections then
        refreshSectionedCollection(frame, data)
    else
        refreshFlatCollection(frame, data)
    end
end

--------------------------------------------------------------------------------
-- CanvasLayout: Vertical stacking engine for canvas subcategory pages.
-- Replicates Blizzard's Settings panel positioning so canvas pages are
-- visually indistinguishable from vertical-layout pages.
--
-- Measurements from Blizzard_SettingControls.xml/.lua:
--   Element height:      26   (all control types)
--   Section header:      45   (GameFontHighlightLarge at TOPLEFT 7, -16)
--   Label left offset:   indent + 37
--   Label right bound:   CENTER - 85
--   Control anchor:      CENTER - 80  (checkbox, slider, color swatch)
--   Button anchor:       CENTER - 40  (width 200)
--   Indent per level:    15
--------------------------------------------------------------------------------

lib.CanvasLayoutDefaults = lib.CanvasLayoutDefaults
    or {
        elementHeight = 26,
        headerHeight = 50,
        labelX = 37,
        controlCenterX = -80,
        buttonCenterX = -40,
        buttonWidth = 200,
        sliderWidth = 250,
        swatchCenterX = -73,
        verifiedPatch = "Retail 12.0/12.1",
    }

local CanvasLayout = {}
lib.CanvasLayout = CanvasLayout

local function getCanvasLayoutMetrics(layout)
    return layout._metrics or lib.CanvasLayoutDefaults
end

function CanvasLayout:_Advance(h)
    self.yPos = self.yPos - h
end

function CanvasLayout:_CreateRow(h)
    local metrics = getCanvasLayoutMetrics(self)
    h = h or metrics.elementHeight
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetPoint("TOPLEFT", 0, self.yPos)
    row:SetPoint("RIGHT")
    row:SetHeight(h)
    self.elements[#self.elements + 1] = row
    self:_Advance(h)
    return row
end

function CanvasLayout:_AddLabel(row, text, fontObject)
    local metrics = getCanvasLayoutMetrics(self)
    local label = row:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    label:SetPoint("LEFT", metrics.labelX, 0)
    label:SetPoint("RIGHT", row, "CENTER", -85, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    row._label = label
    return label
end

--- Add a page header using Blizzard's SettingsListTemplate.Header.
--- Provides Title, Options_HorizontalDivider, and DefaultsButton.
---@return Frame row  (row._title, row._defaultsButton exposed)
function CanvasLayout:AddHeader(text)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow(metrics.headerHeight)
    local settingsList = CreateFrame("Frame", nil, row, "SettingsListTemplate")
    settingsList:SetAllPoints(row)
    settingsList.ScrollBox:Hide()
    settingsList.ScrollBar:Hide()
    settingsList.Header.Title:SetText(text)
    row._title = settingsList.Header.Title
    row._defaultsButton = settingsList.Header.DefaultsButton
    return row
end

--- Add vertical spacing.
function CanvasLayout:AddSpacer(height)
    self:_Advance(height)
end

--- Add a description / informational text row.
function CanvasLayout:AddDescription(text, fontObject)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    local label = row:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    label:SetPoint("LEFT", metrics.labelX, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    row._text = label
    return row
end

--- Add a color swatch row (label + clickable swatch).
---@return Frame row, Button swatch
function CanvasLayout:AddColorSwatch(labelText)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    self:_AddLabel(row, labelText)
    local swatch = lib.CreateColorSwatch(row)
    swatch:SetPoint("LEFT", row, "CENTER", metrics.swatchCenterX, 0)
    row._swatch = swatch
    return row, swatch
end

--- Add a slider row (label + MinimalSliderWithSteppers).
---@return Frame row, Slider slider, FontString valueText
function CanvasLayout:AddSlider(labelText, min, max, step)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    self:_AddLabel(row, labelText)
    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetWidth(metrics.sliderWidth)
    slider:SetPoint("LEFT", row, "CENTER", metrics.controlCenterX, 3)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valueText:SetWidth(40)
    valueText:SetJustifyH("LEFT")
    row._slider = slider
    row._valueText = valueText
    return row, slider, valueText
end

--- Add a button row (label + UIPanelButton).
---@return Frame row, Button button
function CanvasLayout:AddButton(labelText, buttonText)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    self:_AddLabel(row, labelText)
    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(metrics.buttonWidth, 26)
    button:SetPoint("LEFT", row, "CENTER", metrics.buttonCenterX, 0)
    button:SetText(buttonText)
    row._button = button
    return row, button
end

--- Add a scroll list that fills the remaining vertical space.
---@return Frame scrollBox, EventFrame scrollBar, table view
function CanvasLayout:AddScrollList(elementExtent)
    local metrics = getCanvasLayoutMetrics(self)
    local scrollBox = CreateFrame("Frame", nil, self.frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", metrics.labelX, self.yPos)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, 10)
    local scrollBar = CreateFrame("EventFrame", nil, self.frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(elementExtent)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    return scrollBox, scrollBar, view
end

--------------------------------------------------------------------------------
-- Static utilities (shared across all instances)
--------------------------------------------------------------------------------

--- Create a color swatch button using Blizzard's SettingsColorSwatchTemplate.
--- Inherits ColorSwatchTemplate (SwatchBg/InnerBorder/Color layers) and
--- SettingsColorSwatchMixin (hover effects, color picker integration).
---@param parent Frame
---@return Button swatch  (swatch._tex points to swatch.Color for backward compat)
function lib.CreateColorSwatch(parent)
    local swatch = CreateFrame("Button", nil, parent, "SettingsColorSwatchTemplate")
    swatch._tex = swatch.Color
    return swatch
end

--------------------------------------------------------------------------------
-- Slider editable-value hook (global, runs once per lib version)
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- Path accessors: built-in dot-path resolution with numeric key support
--------------------------------------------------------------------------------

local function defaultGetNestedValue(tbl, path)
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

local function defaultSetNestedValue(tbl, path, value)
    local current, lastKey = tbl, nil
    for segment in path:gmatch("[^.]+") do
        if lastKey then
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
    local resolved = lastKey
    if current[lastKey] == nil then
        local num = tonumber(lastKey)
        if num then
            resolved = num
        end
    end
    current[resolved] = value
end

--- Creates a path adapter for resolving dot-delimited paths to get/set/default
--- bindings. Built-in accessors handle numeric path segments (e.g. "colors.0").
---@param config table
---   Required: getStore (function() -> table), getDefaults (function() -> table)
---   Optional: getNestedValue, setNestedValue (custom path accessors)
---@return table adapter with :resolve(path) and :read(path) methods
function lib.PathAdapter(config)
    assert(config.getStore, "PathAdapter: getStore is required")
    assert(config.getDefaults, "PathAdapter: getDefaults is required")

    local getNested = config.getNestedValue or defaultGetNestedValue
    local setNested = config.setNestedValue or defaultSetNestedValue

    return {
        resolve = function(self, path)
            return {
                get = function()
                    return getNested(config.getStore(), path)
                end,
                set = function(value)
                    setNested(config.getStore(), path, value)
                end,
                default = getNested(config.getDefaults(), path),
            }
        end,
        read = function(self, path)
            return getNested(config.getStore(), path)
        end,
    }
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

--- Create a new SettingsBuilder instance.
---@param config table
---   Required fields:
---     varPrefix      string            e.g. "ECM"
---     onChanged      function(spec, value) called after each setter
---   Optional fields:
---     pathAdapter    table  PathAdapter instance for path-based controls
---     compositeDefaults table keyed by composite function name
---@return table builder instance with the full SB API
function lib:New(config)
    assert(config.varPrefix, "LibSettingsBuilder: varPrefix is required")
    assert(config.onChanged, "LibSettingsBuilder: onChanged is required")

    local SB = {}
    SB._rootCategory = nil
    SB._rootCategoryName = nil
    SB._currentSubcategory = nil
    SB._subcategories = {}
    SB._subcategoryNames = {}
    SB._layouts = {}
    SB._firstHeaderAdded = {}
    SB._reactiveControls = {}
    SB._categoryRefreshables = {}

    SB.EMBED_CANVAS_TEMPLATE = lib.EMBED_CANVAS_TEMPLATE
    SB.SUBHEADER_TEMPLATE = lib.SUBHEADER_TEMPLATE
    SB.INFOROW_TEMPLATE = lib.INFOROW_TEMPLATE
    SB.INPUTROW_TEMPLATE = lib.INPUTROW_TEMPLATE
    SB.SCROLL_DROPDOWN_TEMPLATE = lib.SCROLL_DROPDOWN_TEMPLATE
    SB.CreateHeaderTitle = lib.CreateHeaderTitle
    SB.CreateSubheaderTitle = lib.CreateSubheaderTitle

    ----------------------------------------------------------------------------
    -- Internal helpers
    ----------------------------------------------------------------------------

    local function defaultSliderFormatter(value)
        return value == math.floor(value) and tostring(math.floor(value)) or string.format("%.1f", value)
    end

    local adapter = config.pathAdapter

    local function makeVarNameFromIdentifier(identifier)
        return config.varPrefix .. "_" .. tostring(identifier):gsub("%.", "_")
    end

    local function makeVarName(spec)
        local id = spec.key or spec.path
        return makeVarNameFromIdentifier(id)
    end

    local function resolveCategory(spec)
        return spec.category or SB._currentSubcategory or SB._rootCategory
    end

    local function registerCategoryRefreshable(category, initializer)
        if not category or not initializer then
            return
        end

        local refreshables = SB._categoryRefreshables[category]
        if not refreshables then
            refreshables = {}
            SB._categoryRefreshables[category] = refreshables
        end

        for _, existing in ipairs(refreshables) do
            if existing == initializer then
                return
            end
        end

        refreshables[#refreshables + 1] = initializer
    end

    local reevaluateReactiveControls
    local setCanvasInteractive

    local function postSet(spec, value, setting)
        if spec.onSet then
            spec.onSet(value, setting)
        end
        config.onChanged(spec, value)
        reevaluateReactiveControls()
    end

    --- Resolves a spec into a binding with get/set/default.
    --- Handler mode: spec provides explicit get, set, key, and default.
    --- Path mode: spec provides a path string; the pathAdapter generates get/set/default.
    local function resolveBinding(spec)
        local hasPath = spec.path ~= nil
        local hasHandler = spec.get ~= nil or spec.set ~= nil

        assert(not (hasPath and hasHandler), "spec cannot have both path and get/set")

        if hasHandler then
            assert(spec.get, "handler mode requires get")
            assert(spec.set, "handler mode requires set")
            assert(spec.key, "handler mode requires key")
            return { get = spec.get, set = spec.set, default = spec.default }
        end

        assert(hasPath, "spec must have either path or get/set")
        assert(adapter, "path mode requires a pathAdapter on the builder")

        local binding = adapter:resolve(spec.path)
        if spec.default ~= nil then
            binding.default = spec.default
        end
        return binding
    end

    --- Consolidates the getter/setter/default/transform/register boilerplate
    --- shared by Checkbox, Slider, Dropdown, and Custom.
    local function makeProxySetting(spec, varType, defaultFallback, binding)
        local variable = makeVarName(spec)
        local cat = resolveCategory(spec)
        local setting

        binding = binding or resolveBinding(spec)

        local function getter()
            local val = binding.get()
            if spec.getTransform then
                val = spec.getTransform(val)
            end
            return val
        end

        local function applyValue(value)
            if spec.setTransform then
                value = spec.setTransform(value)
            end
            binding.set(value)
            return value
        end

        local function setter(value)
            value = applyValue(value)
            postSet(spec, value, setting)
        end

        local function setValueNoCallback(_, value)
            value = applyValue(value)
            config.onChanged(spec, value)
            reevaluateReactiveControls()
        end

        local default = binding.default
        if spec.getTransform then
            default = spec.getTransform(default)
        end

        if default == nil then
            default = defaultFallback
        end

        setting = Settings.RegisterProxySetting(
            cat,
            variable,
            varType,
            spec.name,
            default,
            getter,
            setter
        )
        setting.SetValueNoCallback = setValueNoCallback
        setting._lsbVariable = variable

        return setting, cat
    end

    --- Copies inherited modifier keys from a composite spec onto a child spec
    --- when the child hasn't set them explicitly.
    local MODIFIER_KEYS = { "category", "parent", "parentCheck", "disabled", "hidden", "layout" }
    local function propagateModifiers(target, source)
        for _, key in ipairs(MODIFIER_KEYS) do
            if target[key] == nil then
                target[key] = source[key]
            end
        end
    end

    --- Merges compositeDefaults for the given composite function name onto spec.
    --- Spec values win over defaults.
    local function mergeCompositeDefaults(functionName, spec)
        local defaults = config.compositeDefaults and config.compositeDefaults[functionName]
        if not defaults then
            return spec or {}
        end
        local merged = {}
        for k, v in pairs(defaults) do
            merged[k] = v
        end
        if spec then
            for k, v in pairs(spec) do
                merged[k] = v
            end
        end
        return merged
    end

    ----------------------------------------------------------------------------
    -- Debug spec validation (active only when LSB_DEBUG is truthy)
    ----------------------------------------------------------------------------

    local COMMON_SPEC_FIELDS = {
        path = true,
        name = true,
        tooltip = true,
        category = true,
        onSet = true,
        getTransform = true,
        setTransform = true,
        parent = true,
        parentCheck = true,
        disabled = true,
        hidden = true,
        layout = true,
        type = true,
        desc = true,
        get = true,
        set = true,
        key = true,
        default = true,
    }

    local EXTRA_FIELDS_BY_TYPE = {
        checkbox = {},
        slider = { min = true, max = true, step = true, formatter = true },
        dropdown = { values = true, scrollHeight = true },
        color = {},
        input = {
            debounce = true,
            maxLetters = true,
            numeric = true,
            onTextChanged = true,
            resolveText = true,
            watch = true,
            watchVariables = true,
            width = true,
        },
        custom = { template = true, varType = true },
    }

    local function validateSpecFields(controlType, spec)
        if not LSB_DEBUG then
            return
        end
        local allowed = EXTRA_FIELDS_BY_TYPE[controlType]
        if not allowed then
            return
        end
        for key in pairs(spec) do
            if not COMMON_SPEC_FIELDS[key] and not allowed[key] then
                print(
                    "|cffFF8800LibSettingsBuilder WARNING:|r Unknown spec field '"
                        .. tostring(key)
                        .. "' on "
                        .. controlType
                        .. " control '"
                        .. tostring(spec.name or spec.path)
                        .. "'"
                )
            end
        end
    end

    setCanvasInteractive = function(frame, enabled)
        if frame.SetEnabled then
            frame:SetEnabled(enabled)
        end
        if frame.EnableMouse then
            frame:EnableMouse(enabled)
        end
        if frame.GetChildren then
            local children = { frame:GetChildren() }
            for i = 1, #children do
                setCanvasInteractive(children[i], enabled)
            end
        end
    end

    local function isParentEnabled(spec)
        if not spec.parent then
            return true
        end

        if spec.parentCheck then
            return spec.parentCheck()
        end

        if not spec.parent.GetSetting then
            return true
        end
        local setting = spec.parent:GetSetting()
        if not setting then
            return true
        end
        return setting:GetValue()
    end

    local function isControlEnabled(spec)
        if spec.disabled and spec.disabled() then
            return false
        end
        return isParentEnabled(spec)
    end

    local function applyCanvasState(canvas, enabled)
        if canvas.SetAlpha then
            canvas:SetAlpha(enabled and 1 or 0.5)
        end
        setCanvasInteractive(canvas, enabled)
    end

    reevaluateReactiveControls = function()
        -- Force the WoW settings panel to re-evaluate visible control states.
        local panel = SettingsPanel
        if panel and panel:IsShown() then
            local settingsList = panel:GetSettingsList()
            if settingsList and settingsList.ScrollBox then
                settingsList.ScrollBox:ForEachFrame(function(frame)
                    if frame.EvaluateState then
                        frame:EvaluateState()
                    end
                end)
            end
        end

        -- Canvas controls aren't part of the settings list, handle directly
        for _, entry in ipairs(SB._reactiveControls) do
            local s = entry[2]
            if s.canvas then
                applyCanvasState(s.canvas, isControlEnabled(s))
            end
        end
    end

    local function applyEnabledState(initializer, spec)
        local enabled = isControlEnabled(spec)
        if initializer.SetEnabled then
            initializer:SetEnabled(enabled)
        end
        if spec.canvas then
            applyCanvasState(spec.canvas, enabled)
        end
        return enabled
    end

    local function applyModifiers(initializer, spec)
        if not initializer then
            return
        end

        if spec.disabled or spec.canvas or spec.parent then
            initializer:AddModifyPredicate(function()
                return applyEnabledState(initializer, spec)
            end)
            applyEnabledState(initializer, spec)
        end

        if spec.parent then
            local predicate = function()
                return isParentEnabled(spec)
            end
            initializer:SetParentInitializer(spec.parent, predicate)
        end

        if spec.hidden then
            initializer:AddShownPredicate(function()
                return not spec.hidden()
            end)
        end

        if spec.canvas then
            SB._reactiveControls[#SB._reactiveControls + 1] = { initializer, spec }
        end
    end

    local function colorTableToHex(tbl)
        if not tbl then
            return "FFFFFFFF"
        end
        return string.format(
            "%02X%02X%02X%02X",
            math.floor((tbl.a or 1) * 255 + 0.5),
            math.floor((tbl.r or 1) * 255 + 0.5),
            math.floor((tbl.g or 1) * 255 + 0.5),
            math.floor((tbl.b or 1) * 255 + 0.5)
        )
    end

    ----------------------------------------------------------------------------
    -- Category management
    ----------------------------------------------------------------------------

    function SB.CreateRootCategory(name)
        local category, layout = Settings.RegisterVerticalLayoutCategory(name)
        SB._rootCategory = category
        SB._rootCategoryName = name
        SB._layouts[category] = layout
        SB._currentSubcategory = nil
        SB._firstHeaderAdded = {}
        return category
    end

    function SB.CreateSubcategory(name, parentCategory)
        local parent = parentCategory or SB._rootCategory
        local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(parent, name)
        SB._subcategories[name] = subcategory
        SB._subcategoryNames[subcategory] = name
        SB._layouts[subcategory] = layout
        SB._currentSubcategory = subcategory
        return subcategory
    end

    function SB.CreateCanvasSubcategory(frame, name, parentCategory)
        local parent = parentCategory or SB._rootCategory
        local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
        SB._subcategories[name] = subcategory
        SB._subcategoryNames[subcategory] = name
        SB._layouts[subcategory] = layout
        return subcategory
    end

    --- Creates a canvas subcategory with a CanvasLayout engine attached.
    --- Returns a layout object with AddHeader, AddDescription, AddSlider,
    --- AddColorSwatch, AddButton, AddScrollList methods that position
    --- controls to match Blizzard's vertical-layout settings pages.
    ---@param name string  Subcategory display name.
    ---@param parentCategory? table  Parent category (defaults to root).
    ---@return table layout  CanvasLayout instance (layout.frame for the raw frame).
    function SB.CreateCanvasLayout(name, parentCategory)
        local frame = CreateFrame("Frame", nil)
        SB.CreateCanvasSubcategory(frame, name, parentCategory)
        local metrics = copyMixin({}, lib.CanvasLayoutDefaults)
        local layout = setmetatable({
            frame = frame,
            yPos = 0,
            elements = {},
            _metrics = metrics,
        }, { __index = lib.CanvasLayout })
        return layout
    end

    function SB.SetCanvasLayoutDefaults(overrides)
        if not overrides then
            return lib.CanvasLayoutDefaults
        end

        for key, value in pairs(overrides) do
            lib.CanvasLayoutDefaults[key] = value
        end

        return lib.CanvasLayoutDefaults
    end

    function SB.ConfigureCanvasLayout(layout, overrides)
        assert(layout, "ConfigureCanvasLayout: layout is required")
        if not overrides then
            return getCanvasLayoutMetrics(layout)
        end

        layout._metrics = copyMixin(copyMixin({}, lib.CanvasLayoutDefaults), overrides)
        return layout._metrics
    end

    --- Static color swatch factory, forwarded from lib for convenience.
    SB.CreateColorSwatch = lib.CreateColorSwatch

    function SB.RegisterCategories()
        if SB._rootCategory then
            Settings.RegisterAddOnCategory(SB._rootCategory)
        end
    end

    function SB.GetRootCategoryID()
        return SB._rootCategory and SB._rootCategory:GetID()
    end

    function SB.GetSubcategoryID(name)
        local category = SB._subcategories[name]
        return category and category:GetID()
    end

    function SB.GetRootCategory()
        return SB._rootCategory
    end

    function SB.GetSubcategory(name)
        return SB._subcategories[name]
    end

    function SB.HasCategory(category)
        return category ~= nil and SB._layouts[category] ~= nil
    end

    ----------------------------------------------------------------------------
    -- Proxy controls
    ----------------------------------------------------------------------------

    function SB.Checkbox(spec)
        validateSpecFields("checkbox", spec)
        local setting, cat = makeProxySetting(spec, Settings.VarType.Boolean, false)
        local initializer = Settings.CreateCheckbox(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)
        return initializer, setting
    end

    function SB.Slider(spec)
        validateSpecFields("slider", spec)
        local setting, cat = makeProxySetting(spec, Settings.VarType.Number, 0)

        local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter or defaultSliderFormatter)

        local initializer = Settings.CreateSlider(cat, setting, options, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.Dropdown(spec)
        validateSpecFields("dropdown", spec)
        local binding = resolveBinding(spec)
        local cat = resolveCategory(spec)

        local default = binding.default
        if spec.getTransform then
            default = spec.getTransform(default)
        end

        local varType = spec.varType
            or (type(default) == "number" and Settings.VarType.Number)
            or Settings.VarType.String

        local setting = makeProxySetting(spec, varType, "", binding)
        local function optionsGenerator()
            local container = Settings.CreateControlTextContainer()
            local values = type(spec.values) == "function" and spec.values() or spec.values
            if values then
                for _, entry in ipairs(getOrderedValueEntries(values)) do
                    container:Add(entry.value, entry.label)
                end
            end
            return container:GetData()
        end
        setting._optionsGen = optionsGenerator

        local initializer
        if spec.scrollHeight then
            initializer = Settings.CreateDropdown(cat, setting, optionsGenerator, spec.tooltip)
            initializer._lsbData = {
                _lsbKind = "scrollDropdown",
                setting = setting,
                values = spec.values,
                scrollHeight = spec.scrollHeight,
                name = spec.name,
                tooltip = spec.tooltip,
            }
            if initializer.SetSetting then
                initializer:SetSetting(setting)
            end
            initializer._lsbRefreshFrame = function(frame)
                if frame and frame.RefreshDropdownText then
                    frame:RefreshDropdownText()
                end
            end
            registerCategoryRefreshable(cat, initializer)
        else
            initializer = Settings.CreateDropdown(cat, setting, optionsGenerator, spec.tooltip)
        end

        if initializer.SetSetting and (not initializer.GetSetting or not initializer:GetSetting()) then
            initializer:SetSetting(setting)
        end
        if type(spec.values) == "function" and not initializer._lsbRefreshFrame then
            initializer._lsbRefreshFrame = function(frame)
                if frame and frame.InitDropdown then
                    frame:InitDropdown(initializer)
                elseif frame and frame.SetValue and setting.GetValue then
                    frame:SetValue(setting:GetValue())
                end
            end
            registerCategoryRefreshable(cat, initializer)
        end

        if not initializer.GetSetting then
            initializer.GetSetting = function()
                return setting
            end
        end

        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.Color(spec)
        validateSpecFields("color", spec)
        local variable = makeVarName(spec)
        local cat = resolveCategory(spec)
        local binding = resolveBinding(spec)

        local function getter()
            local tbl = binding.get()
            return colorTableToHex(tbl)
        end

        local settingRef

        local function setter(hexValue)
            local color = CreateColorFromHexString(hexValue)
            local tbl = { r = color.r, g = color.g, b = color.b, a = color.a }
            binding.set(tbl)
            postSet(spec, tbl, settingRef)
        end

        local defaultTbl = binding.default or {}
        local defaultHex = colorTableToHex(defaultTbl)

        local setting =
            Settings.RegisterProxySetting(cat, variable, Settings.VarType.String, spec.name, defaultHex, getter, setter)
        settingRef = setting

        local initializer = Settings.CreateColorSwatch(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.Input(spec)
        validateSpecFields("input", spec)

        local setting, cat = makeProxySetting(spec, Settings.VarType.String, "")
        local data = {
            debounce = spec.debounce,
            maxLetters = spec.maxLetters,
            name = spec.name,
            numeric = spec.numeric,
            onTextChanged = spec.onTextChanged,
            resolveText = spec.resolveText,
            setting = setting,
            settingVariable = getSettingVariable(setting),
            tooltip = spec.tooltip,
            width = spec.width,
        }

        local watchVariables = {}
        if spec.watch then
            for _, identifier in ipairs(spec.watch) do
                watchVariables[#watchVariables + 1] = makeVarNameFromIdentifier(identifier)
            end
        end
        if spec.watchVariables then
            for _, variable in ipairs(spec.watchVariables) do
                watchVariables[#watchVariables + 1] = variable
            end
        end
        if #watchVariables > 0 then
            data.watchVariables = watchVariables
        end

        local extent = spec.resolveText and 46 or 26
        local initializer = createCustomListRowInitializer(lib.INPUTROW_TEMPLATE, data, extent, applyInputRowFrame)
        local originalInitFrame = initializer.InitFrame
        local originalResetter = initializer.Resetter

        initializer._lsbEnabled = true
        initializer.SetEnabled = function(controlInitializer, enabled)
            controlInitializer._lsbEnabled = enabled
            if controlInitializer._lsbActiveFrame then
                applyInputRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
            end
        end

        initializer.InitFrame = function(controlInitializer, frame)
            controlInitializer._lsbActiveFrame = frame
            originalInitFrame(controlInitializer, frame)
            applyInputRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
        end

        initializer.Resetter = function(controlInitializer, frame)
            cancelInputPreviewTimer(frame)
            if frame and frame._lsbInputEditBox then
                if frame._lsbInputEditBox.ClearFocus then
                    frame._lsbInputEditBox:ClearFocus()
                end
                frame._lsbInputEditBox._lsbOwnerFrame = nil
            end
            frame._lsbInputData = nil
            frame._lsbInputSetting = nil
            if controlInitializer._lsbActiveFrame == frame then
                controlInitializer._lsbActiveFrame = nil
            end
            originalResetter(controlInitializer, frame)
        end

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    --- Creates a proxy setting backed by a custom frame template.
    --- The template's Init receives initializer data containing {setting, name, tooltip}.
    function SB.Custom(spec)
        validateSpecFields("custom", spec)
        assert(spec.template, "Custom: spec.template is required")
        local setting, cat = makeProxySetting(spec, spec.varType or Settings.VarType.String, "")

        local initializer =
            Settings.CreateElementInitializer(spec.template, { name = spec.name, tooltip = spec.tooltip })

        if initializer.SetSetting then
            initializer:SetSetting(setting)
        end

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    --- Unified proxy control dispatch table.
    local DISPATCH = {
        checkbox = "Checkbox",
        slider = "Slider",
        dropdown = "Dropdown",
        color = "Color",
        input = "Input",
        custom = "Custom",
    }

    function SB.Control(spec)
        local fn = SB[DISPATCH[spec.type]]
        assert(fn, "Control: unknown type '" .. tostring(spec.type) .. "'")
        return fn(spec)
    end

    function SB.Collection(spec)
        assert(spec.height, "Collection: spec.height is required")

        local cat = resolveCategory(spec)
        local data = {}
        for key, value in pairs(spec) do
            data[key] = value
        end

        local initializer = createCustomListRowInitializer(lib.EMBED_CANVAS_TEMPLATE, data, spec.height, applyCollectionFrame)

        initializer._lsbEnabled = true
        initializer.SetEnabled = function(controlInitializer, enabled)
            controlInitializer._lsbEnabled = enabled
            local activeFrame = controlInitializer._lsbActiveFrame
            if activeFrame then
                if activeFrame.SetAlpha then
                    activeFrame:SetAlpha(enabled and 1 or 0.5)
                end
                setCanvasInteractive(activeFrame, enabled)
            end
        end

        initializer._lsbRefreshFrame = function(frame)
            applyCollectionFrame(frame, data, initializer)
            initializer.SetEnabled(initializer, initializer._lsbEnabled ~= false)
        end

        Settings.RegisterInitializer(cat, initializer)
        registerCategoryRefreshable(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer
    end

    ----------------------------------------------------------------------------
    -- Composite builders
    ----------------------------------------------------------------------------

    function SB.HeightOverrideSlider(sectionPath, spec)
        spec = spec or {}
        local childSpec = {
            path = sectionPath .. ".height",
            name = spec.name or "Height Override",
            tooltip = spec.tooltip or "Override the default bar height. Set to 0 to use the global default.",
            min = spec.min or 0,
            max = spec.max or 40,
            step = spec.step or 1,
            getTransform = function(value)
                return value or 0
            end,
            setTransform = function(value)
                return value > 0 and value or nil
            end,
        }
        propagateModifiers(childSpec, spec)
        return SB.Slider(childSpec)
    end

    --- Font override group.
    --- Optional spec fields:
    ---   fontValues        function() -> table     (choices for the dropdown)
    ---   fontFallback      function() -> string    (fallback font name)
    ---   fontSizeFallback  function() -> number    (fallback font size)
    ---   fontTemplate      string                  (custom template for the font picker)
    function SB.FontOverrideGroup(sectionPath, spec)
        spec = mergeCompositeDefaults("FontOverrideGroup", spec)
        local overridePath = sectionPath .. ".overrideFont"

        local enabledSpec = {
            path = overridePath,
            name = spec.enabledName or "Override font",
            tooltip = spec.enabledTooltip or "Override the global font settings for this module.",
            getTransform = function(value)
                return value == true
            end,
        }
        propagateModifiers(enabledSpec, spec)
        local enabledInit, enabledSetting = SB.Checkbox(enabledSpec)

        -- Children stay visible but disabled when override is off.
        -- The font picker's SetEnabled hides the preview automatically.
        local outerDisabled = spec.disabled
        local function isOverrideDisabled()
            if outerDisabled and outerDisabled() then
                return true
            end
            return not enabledSetting:GetValue()
        end

        local fontSpec = {
            path = sectionPath .. ".font",
            name = spec.fontName or "Font",
            tooltip = spec.fontTooltip,
            values = spec.fontValues,
            disabled = isOverrideDisabled,
            getTransform = function(value)
                if value then
                    return value
                end
                if spec.fontFallback then
                    return spec.fontFallback()
                end
                return nil
            end,
        }
        propagateModifiers(fontSpec, spec)

        local fontInit
        if spec.fontTemplate then
            fontSpec.template = spec.fontTemplate
            fontInit = SB.Custom(fontSpec)
        else
            fontInit = SB.Dropdown(fontSpec)
        end

        local sizeSpec = {
            path = sectionPath .. ".fontSize",
            name = spec.sizeName or "Font Size",
            tooltip = spec.sizeTooltip,
            min = spec.sizeMin or 6,
            max = spec.sizeMax or 32,
            step = spec.sizeStep or 1,
            disabled = isOverrideDisabled,
            getTransform = function(value)
                if value then
                    return value
                end
                if spec.fontSizeFallback then
                    return spec.fontSizeFallback()
                end
                return 11
            end,
        }
        propagateModifiers(sizeSpec, spec)
        local sizeInit = SB.Slider(sizeSpec)

        return {
            enabledInit = enabledInit,
            enabledSetting = enabledSetting,
            fontInit = fontInit,
            sizeInit = sizeInit,
        }
    end

    function SB.BorderGroup(borderPath, spec)
        spec = spec or {}

        local enabledSpec = {
            path = borderPath .. ".enabled",
            name = spec.enabledName or "Show border",
            tooltip = spec.enabledTooltip,
        }
        propagateModifiers(enabledSpec, spec)
        local enabledInit, enabledSetting = SB.Checkbox(enabledSpec)

        local thicknessSpec = {
            path = borderPath .. ".thickness",
            name = spec.thicknessName or "Border width",
            tooltip = spec.thicknessTooltip,
            min = spec.thicknessMin or 1,
            max = spec.thicknessMax or 10,
            step = spec.thicknessStep or 1,
            parent = enabledInit,
            parentCheck = function()
                return enabledSetting:GetValue()
            end,
        }
        propagateModifiers(thicknessSpec, spec)
        local thicknessInit = SB.Slider(thicknessSpec)

        local colorSpec = {
            path = borderPath .. ".color",
            name = spec.colorName or "Border color",
            tooltip = spec.colorTooltip,
            parent = enabledInit,
            parentCheck = function()
                return enabledSetting:GetValue()
            end,
        }
        propagateModifiers(colorSpec, spec)
        local colorInit = SB.Color(colorSpec)

        return {
            enabledInit = enabledInit,
            enabledSetting = enabledSetting,
            thicknessInit = thicknessInit,
            colorInit = colorInit,
        }
    end

    function SB.ColorPickerList(basePath, defs, spec)
        spec = spec or {}
        local results = {}

        for _, def in ipairs(defs) do
            local childSpec = {
                path = basePath .. "." .. tostring(def.key),
                name = def.name,
                tooltip = def.tooltip,
            }
            propagateModifiers(childSpec, spec)
            local init, setting = SB.Color(childSpec)
            results[#results + 1] = { key = def.key, initializer = init, setting = setting }
        end

        return results
    end

    function SB.CheckboxList(basePath, defs, spec)
        spec = spec or {}
        local results = {}

        for _, def in ipairs(defs) do
            local childSpec = {
                path = basePath .. "." .. tostring(def.key),
                name = def.name,
                tooltip = def.tooltip,
            }
            propagateModifiers(childSpec, spec)
            local init, setting = SB.Checkbox(childSpec)
            results[#results + 1] = { key = def.key, initializer = init, setting = setting }
        end

        return results
    end

    ----------------------------------------------------------------------------
    -- Utility helpers
    ----------------------------------------------------------------------------

    function SB.Header(textOrSpec, category)
        local spec
        if type(textOrSpec) == "table" then
            spec = textOrSpec
        else
            spec = {
                name = textOrSpec,
                category = category,
            }
        end

        local cat = resolveCategory(spec)
        local text = spec.name
        local catName = SB._subcategoryNames[cat] or (cat == SB._rootCategory and SB._rootCategoryName)
        local matchesCategoryTitle = catName and text == catName
        local isFirstHeader = not SB._firstHeaderAdded[cat]
        local attachToCategoryHeader = isFirstHeader and matchesCategoryTitle and spec.actions

        if isFirstHeader then
            SB._firstHeaderAdded[cat] = true
            if matchesCategoryTitle and not spec.actions then
                return nil
            end
        end

        local layout = SB._layouts[cat]
        if spec.actions then
            local height = spec.height
                or (attachToCategoryHeader
                    and 1
                    or (
                        (spec.hideTitle == true or (isFirstHeader and matchesCategoryTitle))
                        and 34
                        or 50
                    ))
            local initializer = createCustomListRowInitializer(lib.SUBHEADER_TEMPLATE, {
                _lsbKind = "header",
                name = text,
                actions = spec.actions,
                hideTitle = spec.hideTitle == true or (isFirstHeader and matchesCategoryTitle),
                attachToCategoryHeader = attachToCategoryHeader == true,
            }, height, applyHeaderFrame)
            initializer._lsbRefreshFrame = function(frame)
                applyHeaderFrame(frame, initializer:GetData())
            end
            initializer._lsbResetFrame = hideHeaderActionButtons
            layout:AddInitializer(initializer)
            registerCategoryRefreshable(cat, initializer)
            applyModifiers(initializer, spec)
            return initializer
        end

        local initializer = CreateSettingsListSectionHeaderInitializer(text)
        layout:AddInitializer(initializer)
        applyModifiers(initializer, spec)
        return initializer
    end

    function SB.Subheader(spec)
        local cat = resolveCategory(spec)
        local layout = SB._layouts[cat]
        local initializer = createCustomListRowInitializer(lib.SUBHEADER_TEMPLATE, {
            _lsbKind = "subheader",
            name = spec.name,
        }, 28, applySubheaderFrame)
        layout:AddInitializer(initializer)
        applyModifiers(initializer, spec)
        return initializer
    end

    function SB.InfoRow(spec)
        local cat = resolveCategory(spec)
        local layout = SB._layouts[cat]
        local initializer = createCustomListRowInitializer(lib.INFOROW_TEMPLATE, {
            _lsbKind = "infoRow",
            name = spec.name,
            value = spec.value,
            wide = spec.wide,
            multiline = spec.multiline,
        }, spec.height or 26, applyInfoRowFrame)
        layout:AddInitializer(initializer)
        initializer._lsbRefreshFrame = function(frame)
            applyInfoRowFrame(frame, initializer:GetData())
        end
        if type(spec.value) == "function" or type(spec.name) == "function" then
            registerCategoryRefreshable(cat, initializer)
        end
        applyModifiers(initializer, spec)
        return initializer
    end

    function SB.EmbedCanvas(canvas, height, spec)
        spec = spec or {}
        local cat = spec.category or SB._currentSubcategory or SB._rootCategory

        local modifiers = {}
        for k, v in pairs(spec) do
            modifiers[k] = v
        end
        modifiers.canvas = canvas

        local initializer = createCustomListRowInitializer(lib.EMBED_CANVAS_TEMPLATE, {
            _lsbKind = "embedCanvas",
            canvas = canvas,
        }, height or canvas:GetHeight(), applyEmbedCanvasFrame)

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, modifiers)

        return initializer
    end

    -- Make CONFIRM_DIALOG_NAME unique per instance to prevent single-pop collisions
    local CONFIRM_DIALOG_NAME = config.varPrefix .. "_" .. MAJOR:gsub("[%-%.]", "_") .. "_SettingsConfirm"
    StaticPopupDialogs[CONFIRM_DIALOG_NAME] = {
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

    function SB.Button(spec)
        local cat = spec.category or SB._currentSubcategory or SB._rootCategory

        local onClick = spec.onClick
        if spec.confirm then
            local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
            local originalClick = onClick
            onClick = function()
                StaticPopup_Show(CONFIRM_DIALOG_NAME, confirmText, nil, { onAccept = originalClick })
            end
        end

        local layout = SB._layouts[cat]
        local initializer =
            CreateSettingsButtonInitializer(spec.name, spec.buttonText or spec.name, onClick, spec.tooltip, true)
        layout:AddInitializer(initializer)
        applyModifiers(initializer, spec)

        return initializer
    end

    function SB.RefreshCategory(categoryOrName)
        local category = categoryOrName
        if type(categoryOrName) == "string" then
            category = SB._subcategories[categoryOrName]
                or (categoryOrName == SB._rootCategoryName and SB._rootCategory)
        end
        if not category then
            return
        end

        local currentCategory = SettingsPanel and SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory() or nil
        local isVisible = SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and currentCategory == category

        local refreshables = SB._categoryRefreshables[category] or {}
        for _, initializer in ipairs(refreshables) do
            if initializer._lsbActiveFrame and initializer._lsbRefreshFrame then
                initializer._lsbRefreshFrame(initializer._lsbActiveFrame, initializer)
            end
        end

        if not isVisible then
            return
        end

        local settingsList = SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
        local scrollBox = settingsList and settingsList.ScrollBox
        if scrollBox and scrollBox.ForEachFrame then
            scrollBox:ForEachFrame(function(frame)
                local initializer = frame.GetElementData and frame:GetElementData() or frame._lsbInitializer
                if frame.EvaluateState then
                    frame:EvaluateState()
                end
                if initializer and initializer._lsbRefreshFrame then
                    initializer._lsbRefreshFrame(frame, initializer)
                end
            end)
        end
    end

    ----------------------------------------------------------------------------
    -- Table-driven registration (AceConfig-inspired)
    ----------------------------------------------------------------------------

    local TYPE_ALIASES = {
        toggle = "checkbox",
        range = "slider",
        select = "dropdown",
        execute = "button",
        description = "subheader",
    }

    local SPEC_EXCLUDE = { type = true, order = true, defs = true, label = true, condition = true }

    -- Composite type dispatch: returns init, setting from a composite builder
    local COMPOSITE_DISPATCH = {
        border = function(path, spec)
            local r = SB.BorderGroup(path, spec)
            return r.enabledInit, r.enabledSetting
        end,
        fontOverride = function(path, spec)
            local r = SB.FontOverrideGroup(path, spec)
            return r.enabledInit, r.enabledSetting
        end,
        heightOverride = function(path, spec)
            return SB.HeightOverrideSlider(path, spec)
        end,
    }

    --- Walks an AceConfig-inspired option table and calls the imperative API.
    --- Top-level `onShow`/`onHide` callbacks fire when the page is selected or
    --- navigated away from (via SettingsPanel.SelectCategory hook).
    function SB.RegisterFromTable(tbl)
        assert(tbl.name, "RegisterFromTable: tbl.name is required")

        if tbl.rootCategory then
            SB._currentSubcategory = SB._rootCategory
        else
            SB.CreateSubcategory(tbl.name, tbl.parentCategory)
        end

        if tbl.onShow or tbl.onHide then
            lib._pageLifecycleCallbacks[SB._currentSubcategory] = {
                onShow = tbl.onShow,
                onHide = tbl.onHide,
            }
            installPageLifecycleHooks()
        end

        local groupPath = tbl.path or ""

        local function resolvePath(entryPath)
            if not entryPath then
                return groupPath
            end
            if entryPath:find("%.") or groupPath == "" then
                return entryPath
            end
            return groupPath .. "." .. entryPath
        end

        if not tbl.args then
            return
        end

        -- Sort entries by order field (stable: secondary key breaks ties)
        local sorted = {}
        for key, entry in pairs(tbl.args) do
            sorted[#sorted + 1] = { key = key, entry = entry }
        end
        table.sort(sorted, function(a, b)
            local oa, ob = a.entry.order or 100, b.entry.order or 100
            if oa ~= ob then
                return oa < ob
            end
            return a.key < b.key
        end)

        local created = {}

        for _, item in ipairs(sorted) do
            local entryKey = item.key
            local entry = item.entry
            local entryType = TYPE_ALIASES[entry.type] or entry.type

            -- Evaluate condition (skip entry if false)
            local condition = entry.condition
            local shouldProcess = condition == nil
                or (type(condition) == "function" and condition())
                or (type(condition) ~= "function" and condition)

            if shouldProcess then
                local spec = {}
                for k, v in pairs(entry) do
                    if not SPEC_EXCLUDE[k] then
                        spec[k] = v
                    end
                end

                if spec.desc and not spec.tooltip then
                    spec.tooltip = spec.desc
                    spec.desc = nil
                end

                if tbl.disabled and spec.disabled == nil then
                    spec.disabled = tbl.disabled
                end
                if tbl.hidden and spec.hidden == nil then
                    spec.hidden = tbl.hidden
                end

                -- Resolve parent string references
                if type(spec.parent) == "string" then
                    local ref = created[spec.parent]
                    assert(ref, "RegisterFromTable: parent '" .. spec.parent .. "' not found (misspelled or forward-referenced?)")
                    spec.parent = ref.initializer
                    if spec.parentCheck == "checked" then
                        local s = ref.setting
                        spec.parentCheck = function()
                            return s:GetValue()
                        end
                    elseif spec.parentCheck == "notChecked" then
                        local s = ref.setting
                        spec.parentCheck = function()
                            return not s:GetValue()
                        end
                    end
                end

                local init, setting

                if entryType == "header" then
                    init = SB.Header(spec)
                elseif entryType == "subheader" then
                    init = SB.Subheader(spec)
                elseif entryType == "info" then
                    init = SB.InfoRow(spec)
                elseif entryType == "button" then
                    init = SB.Button(spec)
                elseif entryType == "collection" then
                    init = SB.Collection(spec)
                elseif entryType == "canvas" then
                    init = SB.EmbedCanvas(entry.canvas, entry.height, spec)
                elseif entryType == "colorList" then
                    local defs = entry.defs or {}
                    if entry.label then
                        local labelInit =
                            SB.Subheader({ name = entry.label, disabled = spec.disabled, hidden = spec.hidden })
                        spec.parent = spec.parent or labelInit
                    end
                    local results = SB.ColorPickerList(resolvePath(entry.path), defs, spec)
                    if results[1] then
                        init, setting = results[1].initializer, results[1].setting
                    end
                elseif entryType == "toggleList" then
                    local defs = entry.defs or {}
                    if entry.label then
                        local labelInit =
                            SB.Subheader({ name = entry.label, disabled = spec.disabled, hidden = spec.hidden })
                        spec.parent = spec.parent or labelInit
                    end
                    local results = SB.CheckboxList(resolvePath(entry.path), defs, spec)
                    if results[1] then
                        init, setting = results[1].initializer, results[1].setting
                    end
                elseif COMPOSITE_DISPATCH[entryType] then
                    init, setting = COMPOSITE_DISPATCH[entryType](resolvePath(entry.path), spec)
                elseif DISPATCH[entryType] then
                    -- Path mode: resolve path from group prefix
                    if not spec.get then
                        spec.path = resolvePath(entry.path or spec.path)
                    end
                    -- Handler mode: fall back to entry key as spec.key if not set
                    if spec.get and not spec.key then
                        spec.key = entryKey
                    end
                    spec.type = entryType
                    init, setting = SB.Control(spec)
                end

                created[entryKey] = { initializer = init, setting = setting }
            end
        end
    end

    function SB.RegisterSection(nsTable, key, section)
        nsTable.OptionsSections = nsTable.OptionsSections or {}
        nsTable.OptionsSections[key] = section
        return section
    end

    return SB
end
