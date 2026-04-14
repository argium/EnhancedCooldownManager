-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local evaluateStaticOrFunction = internal.evaluateStaticOrFunction
local registerValueChangedCallback = internal.registerValueChangedCallback
local setInitializerExtent = internal.setInitializerExtent

local listElementKeysToHide = {
    "_lsbSubheaderTitle",
    "_lsbInfoTitle",
    "_lsbInfoValue",
    "_lsbCanvas",
    "_lsbInputTitle",
    "_lsbInputEditBox",
    "_lsbInputPreview",
}

local function resetListElement(frame)
    for _, key in ipairs(listElementKeysToHide) do
        local region = frame[key]
        if region then
            region:Hide()
        end
    end
end

local function hideListElementObjects(frame, getterName)
    if not frame or not frame[getterName] then
        return
    end

    local objects = { frame[getterName](frame) }
    for i = 1, #objects do
        local object = objects[i]
        if object and object.Hide then
            object:Hide()
        end
    end
end

local function resetPlainListElementFrame(frame)
    hideListElementObjects(frame, "GetChildren")
    hideListElementObjects(frame, "GetRegions")
    resetListElement(frame)
end

local function ensureSubheaderTitle(frame)
    if frame._lsbSubheaderTitle then
        return frame._lsbSubheaderTitle
    end

    local title = lib.CreateSubheaderTitle(frame)
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

    frame._lsbHeaderTitle = lib.CreateHeaderTitle(frame)
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
            internal.setSimpleTooltip(button, evaluateStaticOrFunction(action.tooltip, action, frame))
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
        -- Canvas rows are recycled by Blizzard's list view. Hide and detach the
        -- previous row-owned canvas here so it cannot remain visible on the
        -- wrong page when the frame is reused for a different initializer.
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

internal.hideHeaderActionButtons = hideHeaderActionButtons
internal.applyHeaderFrame = applyHeaderFrame
internal.applySubheaderFrame = applySubheaderFrame
internal.applyInfoRowFrame = applyInfoRowFrame
internal.applyInputRowFrame = applyInputRowFrame
internal.applyInputRowEnabledState = applyInputRowEnabledState
internal.cancelInputPreviewTimer = cancelInputPreviewTimer
internal.applyEmbedCanvasFrame = applyEmbedCanvasFrame
internal.createCustomListRowInitializer = createCustomListRowInitializer
