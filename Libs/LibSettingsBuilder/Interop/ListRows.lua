-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local foundation = internal.foundation
local interop = internal.interop
local evaluateStaticOrFunction = foundation.evaluateStaticOrFunction
local registerValueChangedCallback = interop.registerValueChangedCallback
local setInitializerExtent = interop.setInitializerExtent

local listElementKeysToHide = {
    "_lsbSubheaderTitle",
    "_lsbInfoTitle",
    "_lsbInfoValue",
    "_lsbColorTitle",
    "_lsbColorSwatch",
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
    local objects = { frame[getterName](frame) }
    for i = 1, #objects do
        objects[i]:Hide()
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

    local title = interop.createSubheaderTitle(frame)
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

    frame._lsbHeaderTitle = interop.createHeaderTitle(frame)
    frame._lsbHeaderActionButtons = frame._lsbHeaderActionButtons or {}

    return frame
end

local function getSettingsListHeader()
    local settingsList = SettingsPanel:GetSettingsList()
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
            local enabled = evaluateStaticOrFunction(action.enabled, action, frame)
            if enabled == nil then
                enabled = true
            end
            button:SetEnabled(enabled)
            interop.setSimpleTooltip(button, evaluateStaticOrFunction(action.tooltip, action, frame))
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

    value:SetWordWrap(isMultiline)
    value:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
    value:SetJustifyH("LEFT")
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
    if delay > 0 then
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

    frame:SetAlpha(enabled and 1 or 0.5)

    local editBox = frame._lsbInputEditBox
    if not editBox then
        return
    end

    editBox:SetEnabled(enabled)
    editBox:EnableMouse(enabled)
end

local function getButtonRowButton(frame)
    local control = frame and frame.Control
    return frame and (frame.Button or (control and (control.Button or control))) or nil
end

local function applyButtonRowEnabledState(frame, enabled)
    if not frame then
        return
    end

    frame:SetAlpha(enabled and 1 or 0.5)

    local button = getButtonRowButton(frame)
    if not button then
        return
    end
    button:SetEnabled(enabled)
    button:EnableMouse(enabled)
end

local function ensureColorRowWidgets(frame)
    if frame._lsbColorTitle and frame._lsbColorSwatch then
        return frame._lsbColorTitle, frame._lsbColorSwatch
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local swatch = interop.createColorSwatch(frame)

    frame._lsbColorTitle = title
    frame._lsbColorSwatch = swatch
    frame.Title = title
    frame.Swatch = swatch

    return title, swatch
end

local function parseHexColor(hexValue)
    hexValue = type(hexValue) == "string" and hexValue or "FFFFFFFF"
    if not hexValue:match("^%x%x%x%x%x%x%x%x$") then
        hexValue = "FFFFFFFF"
    end

    local color = interop.createColorFromHexString(hexValue)
    return { r = color.r, g = color.g, b = color.b, a = color.a }
end

local function applyColorSwatchValue(swatch, color)
    if not swatch or not color then
        return
    end

    if swatch.SetColorRGB then
        swatch:SetColorRGB(color.r, color.g, color.b, color.a)
    end

    local texture = swatch._tex or swatch.Color
    if texture and texture.SetColorTexture then
        texture:SetColorTexture(color.r, color.g, color.b, color.a)
    elseif texture and texture.SetVertexColor then
        texture:SetVertexColor(color.r, color.g, color.b, color.a)
    end
end

local function getPickerRGB()
    if ColorPickerFrame and ColorPickerFrame.GetColorRGB then
        return ColorPickerFrame:GetColorRGB()
    end

    local picker = ColorPickerFrame and ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker
    if picker and picker.GetColorRGB then
        return picker:GetColorRGB()
    end

    return 1, 1, 1
end

local function getPickerAlpha()
    if ColorPickerFrame and ColorPickerFrame.GetColorAlpha then
        return ColorPickerFrame:GetColorAlpha()
    end

    return 1
end

local function setPickerRGB(r, g, b)
    if ColorPickerFrame and ColorPickerFrame.SetColorRGB then
        ColorPickerFrame:SetColorRGB(r, g, b)
        return
    end

    local picker = ColorPickerFrame and ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker
    if picker and picker.SetColorRGB then
        picker:SetColorRGB(r, g, b)
    end
end

local function getNormalizedSixDigitHex(text)
    text = tostring(text or ""):match("^%s*(.-)%s*$")
    if text:sub(1, 1) == "#" then
        text = text:sub(2)
    end

    return #text == 6 and text:match("^%x%x%x%x%x%x$") and text or nil
end

local colorPickerSession = nil
local colorPickerHooksInstalled = false

local function findFirstEditBox(...)
    for i = 1, select("#", ...) do
        local editBox = select(i, ...)
        if editBox and editBox.GetText and editBox.SetScript then
            return editBox
        end
    end

    return nil
end

local function findColorPickerHexEditBox()
    if not ColorPickerFrame then
        return nil
    end

    local content = ColorPickerFrame.Content
    local picker = content and content.ColorPicker
    return findFirstEditBox(
        ColorPickerFrame.HexBox,
        ColorPickerFrame.HexEditBox,
        ColorPickerFrame.HexInput,
        ColorPickerFrame.EditBox,
        content and content.HexBox,
        content and content.HexEditBox,
        content and content.HexInput,
        content and content.HexColor,
        content and content.HexColorBox,
        content and content.HexColorEditBox,
        picker and picker.HexBox,
        picker and picker.HexEditBox,
        picker and picker.HexInput
    )
end

local function bindColorPickerHexEditBox()
    local editBox = findColorPickerHexEditBox()
    if not editBox or editBox._lsbColorPickerHexBound then
        return
    end

    local originalOnTextChanged = editBox.GetScript and editBox:GetScript("OnTextChanged") or nil
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if originalOnTextChanged then
            originalOnTextChanged(self, userInput)
        end
        if userInput == false then
            return
        end

        local hex = getNormalizedSixDigitHex(self:GetText())
        if not hex then
            return
        end

        setPickerRGB(
            tonumber(hex:sub(1, 2), 16) / 255,
            tonumber(hex:sub(3, 4), 16) / 255,
            tonumber(hex:sub(5, 6), 16) / 255
        )
    end)
    editBox._lsbColorPickerHexBound = true
end

local function commitColorPickerSession()
    local session = colorPickerSession
    if not session then
        return
    end

    session.committed = true
    if session.setting and session.setting.SetValue then
        session.setting:SetValue(foundation.colorTableToHex(session.pendingColor))
    end
    colorPickerSession = nil
end

local function cancelColorPickerSession()
    local session = colorPickerSession
    if not session then
        return
    end

    session.cancelled = true
    applyColorSwatchValue(session.swatch, session.originalColor)
    colorPickerSession = nil
end

local function showColorPickerSession(session)
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        return
    end

    session.settingUp = true
    ColorPickerFrame:SetupColorPickerAndShow({
        r = session.pendingColor.r,
        g = session.pendingColor.g,
        b = session.pendingColor.b,
        opacity = session.pendingColor.a,
        hasOpacity = true,
        swatchFunc = function()
            if colorPickerSession ~= session or session.settingUp then
                return
            end
            local r, g, b = getPickerRGB()
            session.pendingColor.r = r
            session.pendingColor.g = g
            session.pendingColor.b = b
            applyColorSwatchValue(session.swatch, session.pendingColor)
        end,
        opacityFunc = function()
            if colorPickerSession ~= session or session.settingUp then
                return
            end
            session.pendingColor.a = getPickerAlpha()
            applyColorSwatchValue(session.swatch, session.pendingColor)
        end,
        cancelFunc = function() end,
    })
    session.settingUp = nil
    bindColorPickerHexEditBox()
end

local function installColorPickerHooks()
    if colorPickerHooksInstalled or not ColorPickerFrame then
        return
    end

    local footer = ColorPickerFrame.Footer
    local okayButton = footer and footer.OkayButton
    local cancelButton = footer and footer.CancelButton
    if okayButton and okayButton.HookScript then
        okayButton:HookScript("OnClick", commitColorPickerSession)
    end
    if cancelButton and cancelButton.HookScript then
        cancelButton:HookScript("OnClick", cancelColorPickerSession)
    end
    if ColorPickerFrame.HookScript then
        ColorPickerFrame:HookScript("OnHide", function()
            local session = colorPickerSession
            if not session or session.committed or session.cancelled or session.reopening then
                return
            end

            session.reopening = true
            C_Timer.After(0, function()
                session.reopening = nil
                if colorPickerSession == session and not session.committed and not session.cancelled then
                    showColorPickerSession(session)
                end
            end)
        end)
    end

    colorPickerHooksInstalled = true
end

local function openColorPicker(frame)
    local setting = frame and frame._lsbColorSetting
    if not setting or not setting.GetValue then
        return
    end

    installColorPickerHooks()

    local originalColor = parseHexColor(setting:GetValue())
    colorPickerSession = {
        frame = frame,
        setting = setting,
        swatch = frame._lsbColorSwatch,
        originalColor = originalColor,
        pendingColor = { r = originalColor.r, g = originalColor.g, b = originalColor.b, a = originalColor.a },
    }
    showColorPickerSession(colorPickerSession)
end

local function applyColorRowEnabledState(frame, enabled)
    if not frame then
        return
    end

    frame:SetAlpha(enabled and 1 or 0.5)

    local swatch = frame._lsbColorSwatch
    if not swatch then
        return
    end

    swatch:SetEnabled(enabled)
    swatch:EnableMouse(enabled)
end

local function applyColorRowFrame(frame, data)
    local title, swatch = ensureColorRowWidgets(frame)

    title:ClearAllPoints()
    title:SetPoint("LEFT", frame, "LEFT", 37, 0)
    title:SetPoint("RIGHT", swatch, "LEFT", -8, 0)
    title:SetJustifyV("MIDDLE")
    title:SetText(data.name)
    title:Show()

    swatch:ClearAllPoints()
    swatch:SetPoint("LEFT", frame, "CENTER", interop.defaultSwatchCenterX, 0)
    swatch:Show()
    interop.setSimpleTooltip(swatch, data.tooltip)

    frame._lsbColorSetting = data.setting
    swatch._lsbOwnerFrame = frame
    if not swatch._lsbColorScriptsBound then
        swatch:SetScript("OnClick", function(self)
            openColorPicker(self._lsbOwnerFrame)
        end)
        swatch._lsbColorScriptsBound = true
    end

    applyColorSwatchValue(swatch, parseHexColor(data.setting and data.setting.GetValue and data.setting:GetValue()))

    registerValueChangedCallback(frame, data.settingVariable, function()
        local currentSetting = frame._lsbColorSetting
        applyColorSwatchValue(frame._lsbColorSwatch, parseHexColor(currentSetting and currentSetting.GetValue and currentSetting:GetValue()))
    end, frame)
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
    editBox:SetNumeric(data.numeric == true)
    if data.maxLetters then
        editBox:SetMaxLetters(data.maxLetters)
    end
    editBox:SetTextInsets(6, 6, 0, 0)
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
            self:ClearFocus()
        end)
        editBox:SetScript("OnEscapePressed", function(self)
            local owner = self._lsbOwnerFrame
            if owner then
                local setting = owner._lsbInputSetting
                local value = setting and setting.GetValue and setting:GetValue() or ""
                syncInputRowText(owner, value)
                scheduleInputPreview(owner, true)
            end
            self:ClearFocus()
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
    if frame.cbrHandles then
        return
    end

    frame.cbrHandles = interop.createCallbackHandleContainer()
end

local function initializerShouldShow(initializer)
    if initializer and initializer.ShouldShow then
        if not initializer:ShouldShow() then
            return false
        end
    end

    if initializer and initializer._shownPredicates then
        for _, predicate in ipairs(initializer._shownPredicates) do
            if not predicate() then
                return false
            end
        end
    end

    if initializer and initializer.shownPredicates and initializer.shownPredicates ~= initializer._shownPredicates then
        for _, predicate in ipairs(initializer.shownPredicates) do
            if not predicate() then
                return false
            end
        end
    end

    return true
end

local function initializerIsEnabled(initializer)
    local evaluatedModifyPredicates = false

    if initializer and initializer.EvaluateModifyPredicates then
        evaluatedModifyPredicates = true
        if not initializer:EvaluateModifyPredicates() then
            return false
        end
    end

    if initializer and initializer._modifyPredicates and not evaluatedModifyPredicates then
        for _, predicate in ipairs(initializer._modifyPredicates) do
            if not predicate() then
                return false
            end
        end
    end

    if initializer and initializer.modifyPredicates and initializer.modifyPredicates ~= initializer._modifyPredicates then
        for _, predicate in ipairs(initializer.modifyPredicates) do
            if not predicate() then
                return false
            end
        end
    end

    return true
end

local function createCustomListRowInitializer(template, data, extent, initFrame, resetFrame)
    local initializer = interop.createElementInitializer(template, data)
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
                if currentInitializer then
                    local enabled = initializerIsEnabled(currentInitializer)
                    if currentInitializer.SetEnabled then
                        currentInitializer:SetEnabled(enabled)
                    end
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
        if resetFrame then
            resetFrame(frame)
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

function interop.configureDropdownInitializer(initializer, setting, spec)
    initializer._lsbData = {
        _lsbKind = "dropdown",
        setting = setting,
        values = spec.values,
        name = spec.name,
        tooltip = spec.tooltip,
    }

    if spec.scrollHeight then
        initializer._lsbData._lsbKind = "scrollDropdown"
        initializer._lsbData.scrollHeight = spec.scrollHeight
        interop.setInitializerSetting(initializer, setting)
        initializer._lsbRefreshFrame = function(frame, activeInitializer)
            if frame and frame.initializer ~= activeInitializer then
                return
            end
            if frame and frame.RefreshDropdownText then
                frame:RefreshDropdownText()
            end
        end
    end

    if not initializer:GetSetting() then
        interop.setInitializerSetting(initializer, setting)
    end

    if type(spec.values) == "function" and not initializer._lsbRefreshFrame then
        initializer._lsbRefreshFrame = function(frame, activeInitializer)
            if frame and frame.initializer ~= activeInitializer then
                return
            end
            if frame and frame.InitDropdown and frame.lsbData and frame.lsbData._lsbKind == "scrollDropdown" then
                frame:InitDropdown(initializer)
            elseif frame and frame.RefreshDropdownText then
                frame:RefreshDropdownText()
            elseif frame and frame.SetValue and setting.GetValue then
                frame:SetValue(setting:GetValue())
            end
        end
    end
end

function interop.configureColorInitializer(initializer, setting)
    interop.setInitializerSetting(initializer, setting)

    local originalInitFrame = initializer.InitFrame
    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        if controlInitializer._lsbActiveFrame then
            interop.applyColorRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
        end
    end
    initializer.InitFrame = function(controlInitializer, frame)
        originalInitFrame(controlInitializer, frame)
        interop.applyColorRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
    end
end

function interop.configureInputInitializer(initializer)
    local originalInitFrame = initializer.InitFrame
    local originalResetter = initializer.Resetter

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        if controlInitializer._lsbActiveFrame then
            interop.applyInputRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
        end
    end

    initializer.InitFrame = function(controlInitializer, frame)
        controlInitializer._lsbActiveFrame = frame
        originalInitFrame(controlInitializer, frame)
        interop.applyInputRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
    end

    initializer.Resetter = function(controlInitializer, frame)
        interop.cancelInputPreviewTimer(frame)
        if frame and frame._lsbInputEditBox then
            frame._lsbInputEditBox:ClearFocus()
            frame._lsbInputEditBox._lsbOwnerFrame = nil
        end
        frame._lsbInputData = nil
        frame._lsbInputSetting = nil
        if controlInitializer._lsbActiveFrame == frame then
            controlInitializer._lsbActiveFrame = nil
        end
        originalResetter(controlInitializer, frame)
    end
end

function interop.configurePageActionsInitializer(initializer)
    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        local activeFrame = controlInitializer._lsbActiveFrame
        if activeFrame then
            interop.applyCanvasState(activeFrame, enabled)
        end
    end

    initializer._lsbRefreshFrame = function(frame)
        interop.applyHeaderFrame(frame, initializer:GetData())
        initializer:SetEnabled(initializer._lsbEnabled ~= false)
    end
    initializer._lsbResetFrame = interop.hideHeaderActionButtons
end

function interop.configureButtonInitializer(initializer)
    local originalSetEnabled = initializer.SetEnabled
    local originalInitFrame = initializer.InitFrame
    local originalResetter = initializer.Resetter

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        if originalSetEnabled then
            originalSetEnabled(controlInitializer, enabled)
        end
        if controlInitializer._lsbActiveFrame then
            applyButtonRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
        end
    end

    if originalInitFrame then
        initializer.InitFrame = function(controlInitializer, frame)
            controlInitializer._lsbActiveFrame = frame
            originalInitFrame(controlInitializer, frame)
            applyButtonRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
        end
    end

    if originalResetter then
        initializer.Resetter = function(controlInitializer, frame)
            if controlInitializer._lsbActiveFrame == frame then
                controlInitializer._lsbActiveFrame = nil
            end
            originalResetter(controlInitializer, frame)
        end
    end
end

interop.hideHeaderActionButtons = hideHeaderActionButtons
interop.applyHeaderFrame = applyHeaderFrame
interop.applySubheaderFrame = applySubheaderFrame
interop.applyInfoRowFrame = applyInfoRowFrame
interop.applyButtonRowEnabledState = applyButtonRowEnabledState
interop.applyColorRowFrame = applyColorRowFrame
interop.applyColorRowEnabledState = applyColorRowEnabledState
interop.applyInputRowFrame = applyInputRowFrame
interop.applyInputRowEnabledState = applyInputRowEnabledState
interop.cancelInputPreviewTimer = cancelInputPreviewTimer
interop.applyEmbedCanvasFrame = applyEmbedCanvasFrame
interop.createCustomListRowInitializer = createCustomListRowInitializer
