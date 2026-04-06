-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local BUILTIN_STACKS = C.BUILTIN_STACKS
local BUILTIN_STACK_ORDER = C.BUILTIN_STACK_ORDER
local RACIAL_ABILITIES = C.RACIAL_ABILITIES

local ROW_HEIGHT = 26
local ICON_SIZE = 20
local BTN_SIZE = 22
local CANVAS_MARGIN = 37
local VIEWER_ORDER = { "utility", "main" }
local VIEWER_LABELS = {
    utility = "UTILITY_VIEWER_ICONS",
    main = "MAIN_VIEWER_ICONS",
}

local ExtraIconsOptions = {}
ns.ExtraIconsOptions = ExtraIconsOptions

--------------------------------------------------------------------------------
-- Data Helpers
--------------------------------------------------------------------------------

--- Check if a stackKey is present in any viewer's entries.
function ExtraIconsOptions._isStackKeyPresent(viewers, stackKey)
    for _, entries in pairs(viewers) do
        for _, entry in ipairs(entries) do
            if entry.stackKey == stackKey then
                return true
            end
        end
    end
    return false
end

--- Check if a racial spellId is present in any viewer's entries.
function ExtraIconsOptions._isRacialPresent(viewers, spellId)
    for _, entries in pairs(viewers) do
        for _, entry in ipairs(entries) do
            if entry.kind == "spell" and entry.ids then
                for _, id in ipairs(entry.ids) do
                    local sid = type(id) == "table" and id.spellId or id
                    if sid == spellId then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Get display name for a config entry.
function ExtraIconsOptions._getEntryName(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        return stack and stack.label or entry.stackKey
    end
    if entry.kind == "spell" and entry.ids then
        local first = entry.ids[1]
        local spellId = type(first) == "table" and first.spellId or first
        local name = spellId and C_Spell.GetSpellName(spellId)
        return name or ("Spell " .. tostring(spellId))
    end
    if entry.kind == "item" and entry.ids then
        local first = entry.ids[1]
        return "Item " .. tostring(type(first) == "table" and first.itemID or first)
    end
    return "Unknown"
end

--- Get display icon for a config entry.
function ExtraIconsOptions._getEntryIcon(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then return nil end
        if stack.kind == "equipSlot" then
            return GetInventoryItemTexture("player", stack.slotId)
        end
        if stack.ids and stack.ids[1] then
            local first = stack.ids[1]
            local itemId = type(first) == "table" and first.itemID or first
            return itemId and C_Item.GetItemIconByID(itemId)
        end
        return nil
    end
    if entry.kind == "spell" and entry.ids then
        local first = entry.ids[1]
        local spellId = type(first) == "table" and first.spellId or first
        return spellId and C_Spell.GetSpellTexture(spellId)
    end
    if entry.kind == "item" and entry.ids then
        local first = entry.ids[1]
        local itemId = type(first) == "table" and first.itemID or first
        return itemId and C_Item.GetItemIconByID(itemId)
    end
    return nil
end

--- Add a predefined stack entry to a viewer.
function ExtraIconsOptions._addStackKey(profile, viewerKey, stackKey)
    local viewers = profile.extraIcons.viewers
    viewers[viewerKey] = viewers[viewerKey] or {}
    viewers[viewerKey][#viewers[viewerKey] + 1] = { stackKey = stackKey }
end

--- Add a racial spell entry to a viewer.
function ExtraIconsOptions._addRacial(profile, viewerKey, spellId)
    local viewers = profile.extraIcons.viewers
    viewers[viewerKey] = viewers[viewerKey] or {}
    viewers[viewerKey][#viewers[viewerKey] + 1] = { kind = "spell", ids = { spellId } }
end

--- Add a custom entry to a viewer.
function ExtraIconsOptions._addCustomEntry(profile, viewerKey, kind, ids)
    local viewers = profile.extraIcons.viewers
    viewers[viewerKey] = viewers[viewerKey] or {}
    local entry = { kind = kind, ids = {} }
    for _, id in ipairs(ids) do
        if kind == "item" then
            entry.ids[#entry.ids + 1] = { itemID = id }
        else
            entry.ids[#entry.ids + 1] = id
        end
    end
    viewers[viewerKey][#viewers[viewerKey] + 1] = entry
end

--- Remove entry at index from a viewer.
function ExtraIconsOptions._removeEntry(profile, viewerKey, index)
    local entries = profile.extraIcons.viewers[viewerKey]
    if entries and index >= 1 and index <= #entries then
        table.remove(entries, index)
    end
end

--- Swap entry with its neighbor (-1 = up, +1 = down).
function ExtraIconsOptions._reorderEntry(profile, viewerKey, index, direction)
    local entries = profile.extraIcons.viewers[viewerKey]
    if not entries then return end
    local target = index + direction
    if target < 1 or target > #entries then return end
    entries[index], entries[target] = entries[target], entries[index]
end

--- Move entry from one viewer to another (appends at end).
function ExtraIconsOptions._moveEntry(profile, fromViewer, toViewer, index)
    local from = profile.extraIcons.viewers[fromViewer]
    if not from or index < 1 or index > #from then return end
    local entry = table.remove(from, index)
    local to = profile.extraIcons.viewers[toViewer] or {}
    profile.extraIcons.viewers[toViewer] = to
    to[#to + 1] = entry
end

--- Parse comma-separated numeric IDs from a string.
--- Returns array of numbers, or nil if any value is invalid.
function ExtraIconsOptions._parseIds(text)
    if not text or text == "" then return nil end
    local ids = {}
    for part in text:gmatch("[^,]+") do
        local trimmed = part:match("^%s*(.-)%s*$")
        local num = tonumber(trimmed)
        if not num or num <= 0 or num ~= math.floor(num) then
            return nil
        end
        ids[#ids + 1] = num
    end
    return #ids > 0 and ids or nil
end

--- Get the opposite viewer key.
function ExtraIconsOptions._otherViewer(viewerKey)
    return viewerKey == "utility" and "main" or "utility"
end

--------------------------------------------------------------------------------
-- UI: Tooltip helpers
--------------------------------------------------------------------------------

--- Set a simple text tooltip on a button.
local function setButtonTooltip(btn, text)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

--- Set the entry-specific tooltip on a row's hit region.
--- For spells: SetSpellByID; for items: SetItemByID; otherwise: text-only.
local function setEntryTooltip(row, entry)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if entry.kind == "spell" and entry.ids then
            local first = entry.ids[1]
            local spellId = type(first) == "table" and first.spellId or first
            if spellId then
                GameTooltip:SetSpellByID(spellId)
                GameTooltip:Show()
                return
            end
        end
        if entry.kind == "item" and entry.ids then
            local first = entry.ids[1]
            local itemId = type(first) == "table" and first.itemID or first
            if itemId then
                GameTooltip:SetItemByID(itemId)
                GameTooltip:Show()
                return
            end
        end
        if entry.stackKey then
            local stack = BUILTIN_STACKS[entry.stackKey]
            if stack and stack.kind == "equipSlot" then
                GameTooltip:SetInventoryItem("player", stack.slotId)
                GameTooltip:Show()
                return
            end
            if stack and stack.ids and stack.ids[1] then
                local first = stack.ids[1]
                local itemId = type(first) == "table" and first.itemID or first
                if itemId then
                    GameTooltip:SetItemByID(itemId)
                    GameTooltip:Show()
                    return
                end
            end
        end
        GameTooltip:SetText(ExtraIconsOptions._getEntryName(entry))
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

--- Check if a racial entry belongs to the current player character.
function ExtraIconsOptions._isRacialForCurrentPlayer(entry)
    if not (entry.kind == "spell" and entry.ids) then return true end
    local _, raceFile = UnitRace("player")
    local racial = raceFile and RACIAL_ABILITIES[raceFile]
    if not racial then return true end
    for _, racialEntry in pairs(RACIAL_ABILITIES) do
        if racialEntry ~= racial then
            for _, id in ipairs(entry.ids) do
                local sid = type(id) == "table" and id.spellId or id
                if sid == racialEntry.spellId then
                    return false
                end
            end
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- UI: Entry Row Factory
--------------------------------------------------------------------------------

local function createEntryRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)

    row._icon = row:CreateTexture(nil, "ARTWORK")
    row._icon:SetSize(ICON_SIZE, ICON_SIZE)
    row._icon:SetPoint("LEFT", 0, 0)

    row._label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row._label:SetPoint("LEFT", row._icon, "RIGHT", 6, 0)
    row._label:SetJustifyH("LEFT")
    row._label:SetWordWrap(false)

    row._deleteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._deleteBtn:SetSize(BTN_SIZE, BTN_SIZE)
    row._deleteBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row._deleteBtn:SetText("x")

    row._moveBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._moveBtn:SetSize(BTN_SIZE + 4, BTN_SIZE)
    row._moveBtn:SetPoint("RIGHT", row._deleteBtn, "LEFT", -2, 0)

    row._downBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._downBtn:SetSize(BTN_SIZE + 4, BTN_SIZE)
    row._downBtn:SetPoint("RIGHT", row._moveBtn, "LEFT", -2, 0)
    row._downBtn:SetText("v")

    row._upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._upBtn:SetSize(BTN_SIZE + 4, BTN_SIZE)
    row._upBtn:SetPoint("RIGHT", row._downBtn, "LEFT", -2, 0)
    row._upBtn:SetText("^")

    row._label:SetPoint("RIGHT", row._upBtn, "LEFT", -6, 0)

    return row
end

--------------------------------------------------------------------------------
-- Canvas Layout Page
--------------------------------------------------------------------------------

StaticPopupDialogs["ECM_CONFIRM_RESET_EXTRA_ICONS"] =
    ns.OptionUtil.MakeConfirmDialog(L["EXTRA_ICONS_RESET_CONFIRM"])

local function createCanvasPage(SB)
    local layout = SB.CreateCanvasLayout(L["EXTRA_ICONS"])
    local frame = layout.frame

    local viewerRowPools = { utility = {}, main = {} }
    local viewerEmptyLabels = {}
    local viewerHeaders = {}
    local addBtnPool = {}

    -- Header with Defaults button
    local headerRow = layout:AddHeader(L["EXTRA_ICONS"])
    local defaultsBtn = headerRow._defaultsButton
    layout:AddSpacer(2)

    -- Enabled checkbox — native layout (label left, control right)
    local enabledRow = layout:_CreateRow()
    layout:_AddLabel(enabledRow, L["ENABLE_EXTRA_ICONS"])
    local enabledCheck = CreateFrame("CheckButton", nil, enabledRow, "UICheckButtonTemplate")
    enabledCheck:SetSize(26, 26)
    enabledCheck:SetPoint("LEFT", enabledRow, "CENTER", -80, 0)
    frame._enabledCheck = enabledCheck

    enabledCheck:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        ns.Addon.db.profile.extraIcons.enabled = enabled
        local handler = ns.OptionUtil.CreateModuleEnabledHandler("ExtraIcons")
        handler(enabled)
        frame:Refresh()
    end)

    layout:AddSpacer(6)

    -- Content region (dims when disabled)
    local contentRegion = CreateFrame("Frame", nil, frame)
    contentRegion:SetPoint("TOPLEFT", 0, layout.yPos)
    contentRegion:SetPoint("BOTTOMRIGHT")
    frame._contentRegion = contentRegion

    local contentY = 0

    -- Predefined add buttons container
    local addBtnContainer = CreateFrame("Frame", nil, contentRegion)
    addBtnContainer:SetPoint("TOPLEFT", contentRegion, "TOPLEFT", CANVAS_MARGIN, contentY)
    addBtnContainer:SetPoint("RIGHT", contentRegion, "RIGHT", -20, 0)
    addBtnContainer:SetHeight(28)
    contentY = contentY - 36

    -- Custom entry form — label on left, controls right of center
    local formRow = CreateFrame("Frame", nil, contentRegion)
    formRow:SetHeight(26)
    formRow:SetPoint("TOPLEFT", contentRegion, "TOPLEFT", 0, contentY)
    formRow:SetPoint("RIGHT", contentRegion, "RIGHT", 0, 0)

    local formLabel = formRow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    formLabel:SetPoint("LEFT", CANVAS_MARGIN, 0)
    formLabel:SetPoint("RIGHT", formRow, "CENTER", -85, 0)
    formLabel:SetJustifyH("LEFT")
    formLabel:SetText(L["ADD_CUSTOM_IDS"])

    local editBox = CreateFrame("EditBox", nil, formRow, "InputBoxInstructionsTemplate")
    editBox:SetSize(140, 22)
    editBox:SetPoint("LEFT", formRow, "CENTER", -80, 0)
    editBox:SetAutoFocus(false)
    editBox.Instructions:SetText("1234, 5678")

    local viewerToggle = CreateFrame("Button", nil, formRow, "UIPanelButtonTemplate")
    viewerToggle:SetSize(60, 22)
    viewerToggle:SetPoint("LEFT", editBox, "RIGHT", 4, 0)

    local addSpellBtn = CreateFrame("Button", nil, formRow, "UIPanelButtonTemplate")
    addSpellBtn:SetSize(72, 22)
    addSpellBtn:SetPoint("LEFT", viewerToggle, "RIGHT", 4, 0)
    addSpellBtn:SetText(L["ADD_SPELL"])

    local addItemBtn = CreateFrame("Button", nil, formRow, "UIPanelButtonTemplate")
    addItemBtn:SetSize(68, 22)
    addItemBtn:SetPoint("LEFT", addSpellBtn, "RIGHT", 4, 0)
    addItemBtn:SetText(L["ADD_ITEM"])

    local customViewerKey = "utility"

    frame._customForm = {
        frame = formRow,
        editBox = editBox,
        viewerToggle = viewerToggle,
        addSpellBtn = addSpellBtn,
        addItemBtn = addItemBtn,
    }

    contentY = contentY - 36

    -- Per-viewer headers and empty labels
    for _, vk in ipairs(VIEWER_ORDER) do
        viewerHeaders[vk] = contentRegion:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        viewerHeaders[vk]:SetJustifyH("LEFT")
        viewerHeaders[vk]:SetText(L[VIEWER_LABELS[vk]])

        viewerEmptyLabels[vk] = contentRegion:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        viewerEmptyLabels[vk]:SetJustifyH("LEFT")
        viewerEmptyLabels[vk]:SetText(L["EXTRA_ICONS_NO_ENTRIES"])
    end

    -- Expose state for testing
    frame._viewerRowPools = viewerRowPools
    frame._viewerHeaders = viewerHeaders
    frame._viewerEmptyLabels = viewerEmptyLabels
    frame._addBtnContainer = addBtnContainer
    frame._addBtnPool = addBtnPool

    local function getProfile()
        return ns.Addon.db.profile
    end

    local function scheduleUpdate()
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end

    local function resetToDefaults()
        local viewers = getProfile().extraIcons.viewers
        wipe(viewers)
        viewers.utility = {}
        for _, key in ipairs(BUILTIN_STACK_ORDER) do
            viewers.utility[#viewers.utility + 1] = { stackKey = key }
        end
        viewers.main = {}
        scheduleUpdate()
        frame:Refresh()
    end

    -- Defaults button
    defaultsBtn:SetText(SETTINGS_DEFAULTS)
    defaultsBtn:SetScript("OnClick", function()
        StaticPopup_Show("ECM_CONFIRM_RESET_EXTRA_ICONS", nil, nil, {
            onAccept = resetToDefaults,
        })
    end)

    -- Custom form: viewer toggle
    local function updateViewerToggle()
        viewerToggle:SetText(customViewerKey == "utility" and "Utility" or "Main")
    end
    updateViewerToggle()
    viewerToggle:SetScript("OnClick", function()
        customViewerKey = customViewerKey == "utility" and "main" or "utility"
        updateViewerToggle()
    end)

    -- Custom form: add handlers
    local function addCustom(kind)
        local text = editBox:GetText()
        local ids = ExtraIconsOptions._parseIds(text)
        if not ids then return end
        ExtraIconsOptions._addCustomEntry(getProfile(), customViewerKey, kind, ids)
        editBox:SetText("")
        scheduleUpdate()
        frame:Refresh()
    end
    addSpellBtn:SetScript("OnClick", function() addCustom("spell") end)
    addItemBtn:SetScript("OnClick", function() addCustom("item") end)

    function frame:Refresh()
        local profile = getProfile()
        local viewers = profile.extraIcons.viewers
        local enabled = profile.extraIcons.enabled
        enabledCheck:SetChecked(enabled)
        contentRegion:SetAlpha(enabled and 1 or 0.5)

        -- Hide all add buttons
        for _, btn in ipairs(addBtnPool) do
            btn:Hide()
        end

        -- Add predefined stack buttons
        local btnIndex = 0
        local xOffset = 0
        for _, stackKey in ipairs(BUILTIN_STACK_ORDER) do
            if not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
                btnIndex = btnIndex + 1
                local btn = addBtnPool[btnIndex]
                if not btn then
                    btn = CreateFrame("Button", nil, addBtnContainer, "UIPanelButtonTemplate")
                    btn:SetHeight(24)
                    addBtnPool[btnIndex] = btn
                end
                local stack = BUILTIN_STACKS[stackKey]
                local key = stackKey
                btn:SetText(stack.label)
                btn:SetWidth(84)
                btn:ClearAllPoints()
                btn:SetPoint("LEFT", xOffset, 0)
                btn:SetScript("OnClick", function()
                    ExtraIconsOptions._addStackKey(getProfile(), "utility", key)
                    scheduleUpdate()
                    frame:Refresh()
                end)
                btn:Show()
                xOffset = xOffset + 90
            end
        end

        -- Racial button
        local _, raceFile = UnitRace("player")
        local racial = raceFile and RACIAL_ABILITIES[raceFile]
        if racial and not ExtraIconsOptions._isRacialPresent(viewers, racial.spellId) then
            btnIndex = btnIndex + 1
            local btn = addBtnPool[btnIndex]
            if not btn then
                btn = CreateFrame("Button", nil, addBtnContainer, "UIPanelButtonTemplate")
                btn:SetHeight(24)
                addBtnPool[btnIndex] = btn
            end
            local capturedSpellId = racial.spellId
            local racialName = C_Spell.GetSpellName(capturedSpellId) or "Racial"
            btn:SetText(L["ADD_RACIAL"]:format(racialName))
            btn:SetWidth(btn:GetTextWidth() + 20)
            btn:ClearAllPoints()
            btn:SetPoint("LEFT", xOffset, 0)
            btn:SetScript("OnClick", function()
                ExtraIconsOptions._addRacial(getProfile(), "utility", capturedSpellId)
                scheduleUpdate()
                frame:Refresh()
            end)
            btn:Show()
        end

        -- Viewer lists
        local y = contentY
        for _, viewerKey in ipairs(VIEWER_ORDER) do
            viewerHeaders[viewerKey]:ClearAllPoints()
            viewerHeaders[viewerKey]:SetPoint("TOPLEFT", contentRegion, "TOPLEFT", CANVAS_MARGIN, y)
            y = y - 18

            local pool = viewerRowPools[viewerKey]
            local entries = viewers[viewerKey] or {}

            -- Filter out racials not for this character
            local visibleEntries = {}
            for i, entry in ipairs(entries) do
                if ExtraIconsOptions._isRacialForCurrentPlayer(entry) then
                    visibleEntries[#visibleEntries + 1] = { index = i, entry = entry }
                end
            end

            for _, row in ipairs(pool) do
                row:Hide()
            end

            if #visibleEntries == 0 then
                viewerEmptyLabels[viewerKey]:ClearAllPoints()
                viewerEmptyLabels[viewerKey]:SetPoint("TOPLEFT", contentRegion, "TOPLEFT", CANVAS_MARGIN + 8, y)
                viewerEmptyLabels[viewerKey]:Show()
                y = y - ROW_HEIGHT
            else
                viewerEmptyLabels[viewerKey]:Hide()
            end

            for vi, vis in ipairs(visibleEntries) do
                local entry = vis.entry
                local ci = vis.index
                local row = pool[vi]
                if not row then
                    row = createEntryRow(contentRegion)
                    pool[vi] = row
                end

                local entryName = ExtraIconsOptions._getEntryName(entry)
                row._label:SetText(entryName)
                local icon = ExtraIconsOptions._getEntryIcon(entry)
                row._icon:SetTexture(icon or 134400)
                row._upBtn:SetEnabled(ci > 1)
                row._downBtn:SetEnabled(ci < #entries)

                local other = ExtraIconsOptions._otherViewer(viewerKey)

                -- Entry tooltip on hover
                setEntryTooltip(row, entry)

                -- Button tooltips
                setButtonTooltip(row._upBtn, L["MOVE_UP_TOOLTIP"])
                setButtonTooltip(row._downBtn, L["MOVE_DOWN_TOOLTIP"])
                setButtonTooltip(row._moveBtn, L["MOVE_TO_VIEWER_TOOLTIP"]:format(other))
                setButtonTooltip(row._deleteBtn, L["REMOVE_TOOLTIP"])

                row._upBtn:SetScript("OnClick", function()
                    ExtraIconsOptions._reorderEntry(getProfile(), viewerKey, ci, -1)
                    scheduleUpdate()
                    frame:Refresh()
                end)
                row._downBtn:SetScript("OnClick", function()
                    ExtraIconsOptions._reorderEntry(getProfile(), viewerKey, ci, 1)
                    scheduleUpdate()
                    frame:Refresh()
                end)
                row._moveBtn:SetText(viewerKey == "utility" and ">" or "<")
                row._moveBtn:SetScript("OnClick", function()
                    ExtraIconsOptions._moveEntry(getProfile(), viewerKey, other, ci)
                    scheduleUpdate()
                    frame:Refresh()
                end)
                row._deleteBtn:SetScript("OnClick", function()
                    StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", entryName, nil, {
                        onAccept = function()
                            ExtraIconsOptions._removeEntry(getProfile(), viewerKey, ci)
                            scheduleUpdate()
                            frame:Refresh()
                        end,
                    })
                end)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", contentRegion, "TOPLEFT", CANVAS_MARGIN, y)
                row:SetPoint("RIGHT", contentRegion, "RIGHT", -20, 0)
                row:Show()
                y = y - ROW_HEIGHT
            end

            y = y - 12
        end
    end

    frame:SetScript("OnShow", function(self)
        self:Refresh()
    end)

    return frame
end

--------------------------------------------------------------------------------
-- Settings Registration
--------------------------------------------------------------------------------

StaticPopupDialogs["ECM_CONFIRM_REMOVE_EXTRA_ICON"] =
    ns.OptionUtil.MakeConfirmDialog(L["REMOVE_ENTRY_CONFIRM"])

function ExtraIconsOptions.RegisterSettings(SB)
    local canvasFrame = createCanvasPage(SB)
    ExtraIconsOptions._canvas = canvasFrame
end

ns.SettingsBuilder.RegisterSection(ns, "ExtraIcons", ExtraIconsOptions)
