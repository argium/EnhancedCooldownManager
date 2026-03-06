-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants

local QUESTION_MARK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DESC_TEXT = "Only usable items in your bags and known spells will be shown."
local CANVAS_HEIGHT = 550
local ROW_HEIGHT = 34
local HEADER_ROW_HEIGHT = 28
local ADD_ROW_HEIGHT = 30
local LABEL_X = 37
local ICON_SIZE = 24
local QUALITY_BADGE_SIZE = 14
local DRAG_HIGHLIGHT_COLOR = { 0.3, 0.6, 1.0, 0.15 }
local NORMAL_HIGHLIGHT_COLOR = { 1, 1, 1, 0.08 }
local HEADER_BG_COLOR = { 0.15, 0.15, 0.15, 0.6 }
local RESTORE_POTIONS_POPUP = "ECM_RESTORE_ITEM_ICONS_POTIONS"
local VIEWERS = {
    { key = "essential", label = "Essential Viewer" },
    { key = "utility", label = "Utility Viewer" },
}
local store = assert(ECM.ItemIconsStore, "ECM.ItemIconsStore is required")

--------------------------------------------------------------------------------
-- Confirmation popup
--------------------------------------------------------------------------------

StaticPopupDialogs[RESTORE_POTIONS_POPUP] = {
    text = "Restore default potion and healthstone entries at the top of the utility list?",
    button1 = YES, button2 = NO,
    OnAccept = function() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

--------------------------------------------------------------------------------
-- Drag state
--------------------------------------------------------------------------------

local dragState = {}

local function refreshOptions(refreshFn)
    refreshFn()
    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
end

local function resetDragState()
    dragState.active = false
    dragState.mouseDown = false
    dragState.targetViewerKey = nil
    dragState.targetEntryIndex = nil
    dragState.sourceViewerKey = nil
    dragState.sourceEntryIndex = nil
    dragState.refreshFn = nil
    ResetCursor()
end

local function showDropTarget(rowFrame, viewerKey, entryIndex)
    if not dragState.mouseDown then
        return false
    end
    if not dragState.active then
        dragState.active = true
        SetCursor("Interface\\CURSOR\\UI-Cursor-Move")
    end
    dragState.targetViewerKey = viewerKey
    dragState.targetEntryIndex = entryIndex
    rowFrame._highlight:SetColorTexture(unpack(DRAG_HIGHLIGHT_COLOR))
    rowFrame._highlight:Show()
    return true
end

local function hideDropTarget(rowFrame, viewerKey, entryIndex)
    rowFrame._highlight:Hide()
    rowFrame._highlight:SetColorTexture(unpack(NORMAL_HIGHLIGHT_COLOR))
    if dragState.active
        and dragState.targetViewerKey == viewerKey
        and dragState.targetEntryIndex == entryIndex
    then
        dragState.targetViewerKey = nil
        dragState.targetEntryIndex = nil
    end
end

local function applyDrop()
    if not (dragState.active and dragState.targetViewerKey and dragState.targetEntryIndex) then
        return false
    end
    if dragState.sourceViewerKey == dragState.targetViewerKey then
        if dragState.sourceEntryIndex == dragState.targetEntryIndex then
            return false
        end
        store.MoveEntry(dragState.sourceViewerKey, dragState.sourceEntryIndex, dragState.targetEntryIndex)
        return true
    end
    store.TransferEntry(
        dragState.sourceViewerKey,
        dragState.sourceEntryIndex,
        dragState.targetViewerKey,
        dragState.targetEntryIndex
    )
    return true
end

--------------------------------------------------------------------------------
-- Unified data builder
--------------------------------------------------------------------------------

local function buildUnifiedData()
    local data = {}
    for _, viewer in ipairs(VIEWERS) do
        data[#data + 1] = { rowType = "header", viewerKey = viewer.key, label = viewer.label }
        for i, entry in ipairs(store.GetEntries(viewer.key)) do
            data[#data + 1] = { rowType = "entry", viewerKey = viewer.key, entryIndex = i, entry = entry }
        end
    end
    return data
end

--------------------------------------------------------------------------------
-- Tooltip helpers
--------------------------------------------------------------------------------

local function showEntryTooltip(frame, entry)
    GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
    if entry.type == C.ITEM_ICON_TYPE_ITEM then
        GameTooltip:SetItemByID(entry.id)
    else
        GameTooltip:SetSpellByID(entry.id)
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Row widgets
--------------------------------------------------------------------------------

local function getEntryDisplayInfo(entry)
    if entry.type == C.ITEM_ICON_TYPE_ITEM then
        return C_Item.GetItemIconByID(entry.id),
               C_Item.GetItemNameByID(entry.id) or ("Item #" .. entry.id)
    end
    return C_Spell.GetSpellTexture(entry.id),
           C_Spell.GetSpellName(entry.id) or ("Spell #" .. entry.id)
end

local function updateQualityBadge(qualityTex, entry)
    if entry.type ~= C.ITEM_ICON_TYPE_ITEM
        or not C_TradeSkillUI or not C_TradeSkillUI.GetItemReagentQualityByItemInfo
    then
        qualityTex:Hide()
        return
    end
    local q = C_TradeSkillUI.GetItemReagentQualityByItemInfo(entry.id)
    if q and q > 0 then
        qualityTex:SetAtlas(string.format(C.ITEM_ICON_QUALITY_ATLAS, q))
        qualityTex:Show()
    else
        qualityTex:Hide()
    end
end

local function createEntryWidgets(rowFrame)
    rowFrame:SetHeight(ROW_HEIGHT)

    local icon = rowFrame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetPoint("LEFT", 6, 0)
    rowFrame._icon = icon

    -- Quality badge overlays the icon's top-left corner
    local quality = rowFrame:CreateTexture(nil, "ARTWORK", nil, 2)
    quality:SetSize(QUALITY_BADGE_SIZE, QUALITY_BADGE_SIZE)
    quality:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
    rowFrame._quality = quality

    local name = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    name:SetWidth(180)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    rowFrame._name = name

    local idText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    idText:SetPoint("LEFT", name, "RIGHT", 4, 0)
    idText:SetWidth(60)
    idText:SetJustifyH("LEFT")
    rowFrame._idText = idText

    local typeText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    typeText:SetPoint("LEFT", idText, "RIGHT", 4, 0)
    typeText:SetWidth(36)
    typeText:SetJustifyH("LEFT")
    rowFrame._typeText = typeText

    local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelCloseButtonNoScripts")
    removeBtn:SetSize(20, 20)
    removeBtn:SetPoint("LEFT", typeText, "RIGHT", 4, 0)
    rowFrame._removeBtn = removeBtn
end

local function createHeaderWidgets(rowFrame)
    rowFrame:SetHeight(HEADER_ROW_HEIGHT)

    local bg = rowFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(HEADER_BG_COLOR))
    rowFrame._bg = bg

    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", 8, 0)
    label:SetJustifyH("LEFT")
    rowFrame._headerLabel = label
end

local function populateHeader(rowFrame, data)
    rowFrame._headerLabel:SetText(data.label)
    rowFrame._viewerKey = data.viewerKey
    rowFrame._isHeader = true

    -- Headers are drop targets during drag (insert at position 1)
    rowFrame:SetScript("OnEnter", function(self)
        showDropTarget(self, self._viewerKey, 1)
    end)
    rowFrame:SetScript("OnLeave", function(self)
        hideDropTarget(self, self._viewerKey, 1)
    end)
    rowFrame:SetScript("OnMouseDown", nil)
    rowFrame:SetScript("OnMouseUp", nil)
end

local function populateEntry(rowFrame, data, refreshFn)
    local entry = data.entry
    rowFrame._viewerKey = data.viewerKey
    rowFrame._entryIndex = data.entryIndex
    rowFrame._isHeader = false
    rowFrame._entry = entry

    local tex, label = getEntryDisplayInfo(entry)
    rowFrame._icon:SetTexture(tex or QUESTION_MARK_ICON)
    rowFrame._name:SetText(label)
    updateQualityBadge(rowFrame._quality, entry)

    rowFrame._idText:SetText(tostring(entry.id))
    rowFrame._typeText:SetText(entry.type)

    rowFrame:SetScript("OnEnter", function(self)
        if not showDropTarget(self, self._viewerKey, self._entryIndex) then
            self._highlight:Show()
            showEntryTooltip(self, self._entry)
        end
    end)

    rowFrame:SetScript("OnLeave", function(self)
        hideDropTarget(self, self._viewerKey, self._entryIndex)
        GameTooltip:Hide()
    end)

    rowFrame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        dragState.mouseDown = true
        dragState.sourceViewerKey = self._viewerKey
        dragState.sourceEntryIndex = self._entryIndex
        dragState.refreshFn = refreshFn
        GameTooltip:Hide()
    end)

    rowFrame:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or not dragState.mouseDown then return end
        local fn = dragState.refreshFn
        local changed = applyDrop()
        resetDragState()
        if changed and fn then
            refreshOptions(fn)
        end
    end)

    rowFrame._removeBtn:SetScript("OnClick", function()
        store.RemoveEntry(data.viewerKey, data.entryIndex)
        refreshOptions(refreshFn)
    end)
end

--------------------------------------------------------------------------------
-- Canvas builder
--------------------------------------------------------------------------------

local function createUnifiedCanvas()
    local canvas = CreateFrame("Frame")
    canvas:EnableMouse(true)
    local yPos = -6
    local function refreshEntries() canvas:RefreshEntries() end

    local function createRow(h)
        h = h or 26
        local row = CreateFrame("Frame", nil, canvas)
        row:SetPoint("TOPLEFT", 0, yPos)
        row:SetPoint("RIGHT")
        row:SetHeight(h)
        yPos = yPos - h
        return row
    end

    -- Description
    local descRow = createRow()
    local descText = descRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    descText:SetPoint("LEFT", LABEL_X, 0)
    descText:SetPoint("RIGHT", -10, 0)
    descText:SetJustifyH("LEFT")
    descText:SetText(DESC_TEXT)

    -- Resolve racial spell IDs and names for current player
    local _, raceFile = UnitRace("player")
    local racialSpells = C.RACE_RACIALS and C.RACE_RACIALS[raceFile] or {}
    local racialButtons = {}

    -- Button row: [Restore Potions] [Add <SpellName>] ...
    local btnRow = createRow()

    local restorePotionsBtn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
    restorePotionsBtn:SetSize(130, 22)
    restorePotionsBtn:SetPoint("LEFT", LABEL_X, 0)
    restorePotionsBtn:SetText("Restore Potions")

    -- Create one button per racial spell
    local prevBtn = restorePotionsBtn
    for _, spellId in ipairs(racialSpells) do
        local spellName = C_Spell.GetSpellName(spellId)
        local btn = CreateFrame("Button", nil, btnRow, "UIPanelButtonTemplate")
        btn:SetSize(140, 22)
        btn:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
        btn:SetText("Add " .. (spellName or ("Spell #" .. spellId)))
        btn._spellId = spellId
        racialButtons[#racialButtons + 1] = btn
        prevBtn = btn
    end

    -- Scroll list (fills middle space, leaving room for add row at bottom)
    local scrollBox = CreateFrame("Frame", nil, canvas, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", LABEL_X, yPos)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, ADD_ROW_HEIGHT + 14)
    local scrollBar = CreateFrame("EventFrame", nil, canvas, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- The WowScrollBoxList Shadows overlay blocks mouse events on rows
    if scrollBox.Shadows then
        scrollBox.Shadows:Hide()
        scrollBox.Shadows:EnableMouse(false)
    end

    view:SetElementInitializer("Frame", function(rowFrame, data)
        -- Shared initialization (once per frame lifetime)
        if not rowFrame._sharedInit then
            rowFrame:EnableMouse(true)
            local hl = rowFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
            hl:SetAllPoints()
            hl:SetColorTexture(unpack(NORMAL_HIGHLIGHT_COLOR))
            hl:Hide()
            rowFrame._highlight = hl
            rowFrame._sharedInit = true
        end
        rowFrame._highlight:Hide()
        rowFrame._highlight:SetColorTexture(unpack(NORMAL_HIGHLIGHT_COLOR))

        if data.rowType == "header" then
            if not rowFrame._headerInitialized then
                createHeaderWidgets(rowFrame)
                rowFrame._headerInitialized = true
            end
            -- Hide entry widgets if this frame was previously an entry row
            if rowFrame._entryInitialized then
                rowFrame._icon:Hide()
                rowFrame._quality:Hide()
                rowFrame._name:Hide()
                rowFrame._idText:Hide()
                rowFrame._typeText:Hide()
            rowFrame._removeBtn:Hide()
        end
        rowFrame._bg:Show()
        rowFrame._headerLabel:Show()
        rowFrame:SetHeight(HEADER_ROW_HEIGHT)
            populateHeader(rowFrame, data)
        else
            if not rowFrame._entryInitialized then
                createEntryWidgets(rowFrame)
                rowFrame._entryInitialized = true
            end
            -- Hide header widgets if this frame was previously a header row
            if rowFrame._headerInitialized then
                rowFrame._bg:Hide()
                rowFrame._headerLabel:Hide()
            end
            rowFrame._icon:Show()
            rowFrame._name:Show()
            rowFrame._idText:Show()
            rowFrame._typeText:Show()
            rowFrame._removeBtn:Show()
            rowFrame:SetHeight(ROW_HEIGHT)
            populateEntry(rowFrame, data, refreshEntries)
        end
    end)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    local function updateButtonStates()
        -- Restore Potions: disable when all defaults already present in any viewer
        if store.HasAllDefaults(C.ITEM_ICONS_DEFAULT_UTILITY) then
            restorePotionsBtn:Disable()
        else
            restorePotionsBtn:Enable()
        end
        -- Racial buttons: each disabled when its spell is already in either viewer
        for _, btn in ipairs(racialButtons) do
            if store.HasEntry(C.ITEM_ICON_TYPE_SPELL, btn._spellId) then
                btn:Disable()
            else
                btn:Enable()
            end
        end
    end

    function canvas:RefreshEntries()
        dataProvider:Flush()
        for _, row in ipairs(buildUnifiedData()) do
            dataProvider:Insert(row)
        end
        updateButtonStates()
    end

    -- Restore Potions: adds default potions + healthstone to utility section
    restorePotionsBtn:SetScript("OnClick", function()
        StaticPopupDialogs[RESTORE_POTIONS_POPUP].OnAccept = function()
            store.RestoreDefaults("utility", C.ITEM_ICONS_DEFAULT_UTILITY)
            refreshOptions(refreshEntries)
        end
        StaticPopup_Show(RESTORE_POTIONS_POPUP)
    end)

    -- Racial buttons: each adds its specific spell to utility
    for _, btn in ipairs(racialButtons) do
        btn:SetScript("OnClick", function(self)
            store.AddEntry("utility", C.ITEM_ICON_TYPE_SPELL, self._spellId)
            refreshOptions(refreshEntries)
        end)
    end

    -- Add entry row (anchored to canvas bottom)
    local addRow = CreateFrame("Frame", nil, canvas)
    addRow:SetHeight(ADD_ROW_HEIGHT)
    addRow:SetPoint("BOTTOMLEFT", LABEL_X, 6)
    addRow:SetPoint("BOTTOMRIGHT", -10, 6)

    local addViewerKey = "utility"
    local addEntryType = C.ITEM_ICON_TYPE_ITEM

    local viewerBtn = CreateFrame("Button", nil, addRow, "UIPanelButtonTemplate")
    viewerBtn:SetSize(70, 22)
    viewerBtn:SetPoint("LEFT", 0, 0)
    viewerBtn:SetText("Utility")
    viewerBtn:SetScript("OnClick", function(self)
        if addViewerKey == "utility" then
            addViewerKey = "essential"
            self:SetText("Essential")
        else
            addViewerKey = "utility"
            self:SetText("Utility")
        end
    end)

    local typeBtn = CreateFrame("Button", nil, addRow, "UIPanelButtonTemplate")
    typeBtn:SetSize(60, 22)
    typeBtn:SetPoint("LEFT", viewerBtn, "RIGHT", 4, 0)
    typeBtn:SetText("Item")
    typeBtn:SetScript("OnClick", function(self)
        if addEntryType == C.ITEM_ICON_TYPE_ITEM then
            addEntryType = C.ITEM_ICON_TYPE_SPELL
            self:SetText("Spell")
        else
            addEntryType = C.ITEM_ICON_TYPE_ITEM
            self:SetText("Item")
        end
    end)

    local addBtn = CreateFrame("Button", nil, addRow, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("RIGHT", 0, 0)
    addBtn:SetText("Add")

    local editBox = CreateFrame("EditBox", nil, addRow, "InputBoxTemplate")
    editBox:SetHeight(22)
    editBox:SetPoint("LEFT", typeBtn, "RIGHT", 8, 0)
    editBox:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(true)

    local function submitEntry()
        local id = editBox:GetNumber()
        if id > 0 then
            store.AddEntry(addViewerKey, addEntryType, id)
            editBox:SetText("")
            refreshOptions(refreshEntries)
        end
    end

    addBtn:SetScript("OnClick", submitEntry)
    editBox:SetScript("OnEnterPressed", submitEntry)

    canvas:SetScript("OnShow", function(self)
        self:RefreshEntries()
        -- Hide the SettingsListElementTemplate's built-in hover background
        local parent = self:GetParent()
        if parent and parent.Tooltip and parent.Tooltip.HoverBackground then
            parent.Tooltip.HoverBackground:SetAlpha(0)
        end
    end)

    return canvas
end

--------------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------------

local ItemIconsOptions = {}

function ItemIconsOptions.RegisterSettings(SB)
    SB.CreateSubcategory("Item Icons")

    local enableInit, enableSetting = SB.PathCheckbox({
        path = "itemIcons.enabled",
        name = "Enable item icons",
        tooltip = "Display configurable icons for items and spells next to the cooldown viewers.",
        onSet = function(value) ECM.OptionUtil.SetModuleEnabled("ItemIcons", value) end,
    })

    SB.Header("Item Icons")
    local canvas = createUnifiedCanvas()
    SB.EmbedCanvas(canvas, CANVAS_HEIGHT, {
        parent = enableInit,
        parentCheck = function() return enableSetting:GetValue() end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ItemIcons", ItemIconsOptions)
