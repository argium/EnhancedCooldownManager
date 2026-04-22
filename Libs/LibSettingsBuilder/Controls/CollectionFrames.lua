-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local ADD = _G.ADD
local REMOVE = _G.REMOVE

local internal = lib._internal
local applyActionButtonTextures = internal.applyActionButtonTextures
local configureInlineSlider = internal.configureInlineSlider
local evaluateStaticOrFunction = internal.evaluateStaticOrFunction
local setGameTooltipText = internal.setGameTooltipText
local setSimpleTooltip = internal.setSimpleTooltip
local setTextureValue = internal.setTextureValue
local showFrame = internal.showFrame

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

    if row.EnableMouse then
        row:EnableMouse(item ~= nil)
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

local DEFAULT_SWATCH_CENTER_X = internal.defaultSwatchCenterX or -73

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
    row._label:SetJustifyH("LEFT")
    row._label:SetWordWrap(false)

    row._swatch = internal.createColorSwatch(row)
    row._swatch:SetPoint("LEFT", row, "CENTER", DEFAULT_SWATCH_CENTER_X, 0)
end

local function refreshSwatchCollectionRow(row, item)
    ensureSwatchCollectionRow(row)

    if item.icon then
        setTextureValue(row._icon, item.icon)
        row._icon:Show()
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
    else
        setTextureValue(row._icon, nil)
        row._icon:Hide()
        row._label:ClearAllPoints()
        row._label:SetPoint("LEFT", row, "LEFT", 0, 0)
    end
    row._label:SetPoint("RIGHT", row._swatch, "LEFT", -8, 0)

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
    row._swatch = internal.createColorSwatch(row)
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
local ACTION_BUTTON_SPACING = 2

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
        if button.RegisterForClicks then
            button:RegisterForClicks("LeftButtonDown")
        end
        row._buttons[key] = button
    end
end

local function refreshActionsCollectionRow(row, item)
    ensureActionsCollectionRow(row)

    row._label:SetText(item.label or "")
    setTextureValue(row._icon, item.icon or 134400)
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
                button:SetPoint("RIGHT", row, "RIGHT", -ACTION_BUTTON_SPACING, 0)
            else
                button:SetPoint("RIGHT", anchor, "LEFT", -ACTION_BUTTON_SPACING, 0)
            end
            button:SetSize(action.width or 26, action.height or 22)
            local enabled = evaluateStaticOrFunction(action.enabled, action, row, item)
            if enabled == nil then
                enabled = true
            end
            applyActionButtonTextures(button, action, enabled)
            if button.SetEnabled then
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
        if row._lsbTrailerRefresh then
            row._lsbTrailerRefresh(row)
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
        local keepFocus = nil
        if trailer and trailer.onTabPressed then
            keepFocus = trailer.onTabPressed(trailer, row, row._lsbSectionData)
        end
        if row._lsbTrailerRefresh then
            row._lsbTrailerRefresh(row)
        end
        if keepFocus then
            row._editBox:SetFocus()
            row._editBox:HighlightText()
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

local function getModeInputTrailerValue(trailer, key, row, sectionData)
    return evaluateStaticOrFunction(trailer and trailer[key], trailer, row, sectionData)
end

local function refreshModeInputRow(row, trailer, sectionData)
    ensureModeInputRow(row)

    row._lsbTrailerData = trailer
    row._lsbSectionData = sectionData

    row._lsbTrailerRefresh = function(activeRow)
        local currentTrailer = activeRow._lsbTrailerData or {}
        local activeSectionData = activeRow._lsbSectionData
        local disabled = getModeInputTrailerValue(currentTrailer, "disabled", activeRow, activeSectionData) == true
        local modeEnabled = getModeInputTrailerValue(currentTrailer, "modeEnabled", activeRow, activeSectionData)
        local inputEnabled = getModeInputTrailerValue(currentTrailer, "inputEnabled", activeRow, activeSectionData)
        local submitEnabled = getModeInputTrailerValue(currentTrailer, "submitEnabled", activeRow, activeSectionData)
        local modeText = getModeInputTrailerValue(currentTrailer, "modeText", activeRow, activeSectionData)
        local modeTooltip = getModeInputTrailerValue(currentTrailer, "modeTooltip", activeRow, activeSectionData)
        local text = getModeInputTrailerValue(currentTrailer, "inputText", activeRow, activeSectionData) or ""
        local placeholder = getModeInputTrailerValue(currentTrailer, "placeholder", activeRow, activeSectionData)
        local previewIcon = getModeInputTrailerValue(currentTrailer, "previewIcon", activeRow, activeSectionData)
        local previewText = getModeInputTrailerValue(currentTrailer, "previewText", activeRow, activeSectionData)
        local submitText = getModeInputTrailerValue(currentTrailer, "submitText", activeRow, activeSectionData)
        local submitTooltip = getModeInputTrailerValue(currentTrailer, "submitTooltip", activeRow, activeSectionData)

        activeRow._modeButton:SetText(modeText or "")
        setSimpleTooltip(activeRow._modeButton, modeTooltip)
        activeRow._modeButton:SetScript("OnClick", function()
            if currentTrailer.onToggleMode then
                currentTrailer.onToggleMode(currentTrailer, activeRow, activeRow._lsbSectionData)
            end
            if activeRow._lsbTrailerRefresh then
                activeRow._lsbTrailerRefresh(activeRow)
            end
        end)
        if activeRow._modeButton.SetEnabled then
            activeRow._modeButton:SetEnabled(not disabled and modeEnabled ~= false)
        end

        if activeRow._editBox.GetText and activeRow._editBox:GetText() ~= text then
            activeRow._lsbSyncingText = true
            activeRow._editBox:SetText(text)
            activeRow._lsbSyncingText = nil
        end
        if activeRow._editBox.SetEnabled then
            activeRow._editBox:SetEnabled(not disabled and inputEnabled ~= false)
        end

        activeRow._placeholder:SetText(placeholder or "")
        if activeRow._lsbHasFocus or text ~= "" then
            activeRow._placeholder:Hide()
        else
            activeRow._placeholder:Show()
        end

        if previewIcon then
            setTextureValue(activeRow._previewIcon, previewIcon)
            activeRow._previewIcon:Show()
        else
            setTextureValue(activeRow._previewIcon, nil)
            activeRow._previewIcon:Hide()
        end

        if previewText and previewText ~= "" then
            activeRow._previewLabel:SetText(previewText)
            activeRow._previewLabel:Show()
        else
            activeRow._previewLabel:SetText("")
            activeRow._previewLabel:Hide()
        end

        activeRow._submitButton:SetText(submitText or ADD or "Add")
        setSimpleTooltip(activeRow._submitButton, submitTooltip)
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
            activeRow._submitButton:SetEnabled(not disabled and submitEnabled ~= false)
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
    row._title = internal.createHeaderTitle(row, title)
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

    for _, pool in pairs(rowPools) do
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
        local titleText = section.title or section.name or ""
        local header = ensureSectionHeaderRow(content, headers, sectionKey, titleText)
        header._title:SetText(titleText)
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

        local footer = section.footer
        local footerType = footer and (footer.type or footer.preset)
        if footerType == "modeInput" then
            local trailerRow = trailerRows[sectionKey]
            if not trailerRow then
                trailerRow = CreateFrame("Frame", nil, content)
                trailerRows[sectionKey] = trailerRow
            end

            footer.preset = footer.preset or footerType
            refreshModeInputRow(trailerRow, footer, section)
            trailerRow:ClearAllPoints()
            trailerRow:SetPoint("TOPLEFT", content, "TOPLEFT", insetLeft, y)
            trailerRow:SetPoint("RIGHT", content, "RIGHT", -insetRight, 0)
            trailerRow:Show()
            y = y - (section.footerHeight or 28)
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

internal.applyCollectionFrame = applyCollectionFrame
