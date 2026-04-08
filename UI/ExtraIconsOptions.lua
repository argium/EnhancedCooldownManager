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
local CONTENT_MARGIN = 10
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

--- Parse a single positive integer ID from a string.
---@param text string|nil
---@return number|nil
function ExtraIconsOptions._parseSingleId(text)
    if not text or text == "" then
        return nil
    end

    local num = tonumber(text)
    if not num or num <= 0 or num ~= math.floor(num) then
        return nil
    end

    return num
end

--- Resolve a draft spell or item ID to a display name.
---@param kind string
---@param text string|nil
---@return string|nil
function ExtraIconsOptions._resolveDraftEntryName(kind, text)
    local id = ExtraIconsOptions._parseSingleId(text)
    if not id then
        return nil
    end

    if kind == "spell" then
        return C_Spell.GetSpellName(id)
    end

    if kind == "item" then
        if not C_Item.DoesItemExistByID(id) then
            return nil
        end

        local name = C_Item.GetItemNameByID(id)
        if name then
            return name
        end

        C_Item.RequestLoadItemDataByID(id)

        return L["EXTRA_ICONS_ITEM_LOADING"]
    end

    return nil
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
        GameTooltip:SetText(text, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

local function clearRowMouseover(row)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    if row._highlight then
        row._highlight:Hide()
    end
    if row.EnableMouse then
        row:EnableMouse(false)
    end
end

local function setRowMouseover(row)
    if row._highlight then
        row._highlight:Hide()
    end
    if row.EnableMouse then
        row:EnableMouse(true)
    end
    row:SetScript("OnEnter", function(self)
        if self._highlight then
            self._highlight:Show()
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self._highlight then
            self._highlight:Hide()
        end
    end)
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

    row._highlight = row:CreateTexture(nil, "BACKGROUND")
    row._highlight:SetAllPoints()
    row._highlight:SetColorTexture(1, 1, 1, 0.08)
    row._highlight:Hide()

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

local function createViewerHeaderRow(parent, SB, text, headerHeight)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(headerHeight)
    row._title = SB.CreateHeaderTitle(row, text)
    return row
end

--------------------------------------------------------------------------------
-- Embedded Content: Viewer lists
--------------------------------------------------------------------------------

local function createViewerListCanvas(SB, headerHeight)
    local frame = CreateFrame("Frame")
    frame:SetHeight(400)

    frame._viewerRowPools = { utility = {}, main = {} }
    frame._viewerHeaders = {}
    frame._viewerEmptyLabels = {}

    for _, vk in ipairs(VIEWER_ORDER) do
        frame._viewerHeaders[vk] = createViewerHeaderRow(frame, SB, L[VIEWER_LABELS[vk]], headerHeight)

        frame._viewerEmptyLabels[vk] = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        frame._viewerEmptyLabels[vk]:SetJustifyH("LEFT")
        frame._viewerEmptyLabels[vk]:SetText(L["EXTRA_ICONS_NO_ENTRIES"])
    end

    return frame
end

--------------------------------------------------------------------------------
-- Settings Registration
--------------------------------------------------------------------------------

StaticPopupDialogs["ECM_CONFIRM_REMOVE_EXTRA_ICON"] =
    ns.OptionUtil.MakeConfirmDialog(L["REMOVE_ENTRY_CONFIRM"])

function ExtraIconsOptions.RegisterSettings(SB)
    local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("extraIcons")
    local viewerHeaderHeight = (SB.SetCanvasLayoutDefaults and SB.SetCanvasLayoutDefaults().headerHeight) or 50
    local viewerCanvas = createViewerListCanvas(SB, viewerHeaderHeight)
    local pageCategory = nil
    ExtraIconsOptions._viewerCanvas = viewerCanvas
    ExtraIconsOptions._addFormCanvas = nil
    ExtraIconsOptions._presetsCanvas = nil

    local function getProfile()
        return ns.Addon.db.profile
    end

    local function getViewers()
        return getProfile().extraIcons.viewers
    end

    ExtraIconsOptions._formState = ExtraIconsOptions._formState or {
        kind = "spell",
        viewer = "utility",
        idText = "",
    }
    local formState = ExtraIconsOptions._formState

    local function scheduleUpdate()
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end

    local function getResolvedDraftName()
        return ExtraIconsOptions._resolveDraftEntryName(formState.kind, formState.idText)
    end

    local function canAddDraftEntry()
        local id = ExtraIconsOptions._parseSingleId(formState.idText)
        if not id then
            return false
        end

        if formState.kind == "spell" then
            return getResolvedDraftName() ~= nil
        end

        return true
    end

    local function addDraftEntry()
        local id = ExtraIconsOptions._parseSingleId(formState.idText)
        if not id or not canAddDraftEntry() then
            return
        end

        ExtraIconsOptions._addCustomEntry(getProfile(), formState.viewer, formState.kind, { id })
        formState.idText = ""
        scheduleUpdate()
        ExtraIconsOptions._refresh()
    end

    local function getPlayerRacialSpellId()
        local _, raceFile = UnitRace("player")
        local racial = raceFile and RACIAL_ABILITIES[raceFile]
        return racial and racial.spellId or nil
    end

    local function hasVisibleQuickAddEntries()
        local viewers = getViewers()
        for _, stackKey in ipairs(BUILTIN_STACK_ORDER) do
            if not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
                return true
            end
        end

        local racialSpellId = getPlayerRacialSpellId()
        return racialSpellId ~= nil and not ExtraIconsOptions._isRacialPresent(viewers, racialSpellId)
    end

    local function refreshVisibleSettingsControls()
        local panel = SettingsPanel
        if not panel or not panel.IsShown or not panel:IsShown() then
            return
        end

        local currentCategory = panel.GetCurrentCategory and panel:GetCurrentCategory() or nil
        if pageCategory and currentCategory == pageCategory and panel.DisplayCategory then
            panel:DisplayCategory(currentCategory)
            return
        end

        local settingsList = panel.GetSettingsList and panel:GetSettingsList()
        local scrollBox = settingsList and settingsList.ScrollBox
        if scrollBox and scrollBox.ForEachFrame then
            scrollBox:ForEachFrame(function(frame)
                if frame.EvaluateState then
                    frame:EvaluateState()
                end
            end)
        end
    end

    --------------------------------------------------------------------
    -- Refresh: viewer lists canvas
    --------------------------------------------------------------------
    local function refreshViewerLists()
        local viewers = getViewers()
        local y = 0

        for _, viewerKey in ipairs(VIEWER_ORDER) do
            local headerRow = viewerCanvas._viewerHeaders[viewerKey]
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", 0, y)
            headerRow:SetPoint("RIGHT", viewerCanvas, "RIGHT", 0, 0)
            headerRow:Show()
            y = y - viewerHeaderHeight

            local pool = viewerCanvas._viewerRowPools[viewerKey]
            local entries = viewers[viewerKey] or {}

            local visibleEntries = {}
            for i, entry in ipairs(entries) do
                if ExtraIconsOptions._isRacialForCurrentPlayer(entry) then
                    visibleEntries[#visibleEntries + 1] = { index = i, entry = entry }
                end
            end

            for _, row in ipairs(pool) do
                clearRowMouseover(row)
                row:Hide()
            end

            if #visibleEntries == 0 then
                viewerCanvas._viewerEmptyLabels[viewerKey]:ClearAllPoints()
                viewerCanvas._viewerEmptyLabels[viewerKey]:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", CONTENT_MARGIN + 8, y)
                viewerCanvas._viewerEmptyLabels[viewerKey]:Show()
                y = y - ROW_HEIGHT
            else
                viewerCanvas._viewerEmptyLabels[viewerKey]:Hide()
            end

            for vi, vis in ipairs(visibleEntries) do
                local entry = vis.entry
                local ci = vis.index
                local row = pool[vi]
                if not row then
                    row = createEntryRow(viewerCanvas)
                    pool[vi] = row
                end

                row._label:SetText(ExtraIconsOptions._getEntryName(entry))
                row._icon:SetTexture(ExtraIconsOptions._getEntryIcon(entry) or 134400)
                row._upBtn:SetEnabled(ci > 1)
                row._downBtn:SetEnabled(ci < #entries)

                local other = ExtraIconsOptions._otherViewer(viewerKey)

                setButtonTooltip(row._upBtn, L["MOVE_UP_TOOLTIP"])
                setButtonTooltip(row._downBtn, L["MOVE_DOWN_TOOLTIP"])
                setButtonTooltip(row._moveBtn, L["MOVE_TO_VIEWER_TOOLTIP"]:format(other))
                setButtonTooltip(row._deleteBtn, L["REMOVE_TOOLTIP"])

                row._upBtn:SetScript("OnClick", function()
                    ExtraIconsOptions._reorderEntry(getProfile(), viewerKey, ci, -1)
                    scheduleUpdate()
                    ExtraIconsOptions._refresh()
                end)
                row._downBtn:SetScript("OnClick", function()
                    ExtraIconsOptions._reorderEntry(getProfile(), viewerKey, ci, 1)
                    scheduleUpdate()
                    ExtraIconsOptions._refresh()
                end)
                row._moveBtn:SetText(viewerKey == "utility" and ">" or "<")
                row._moveBtn:SetScript("OnClick", function()
                    ExtraIconsOptions._moveEntry(getProfile(), viewerKey, other, ci)
                    scheduleUpdate()
                    ExtraIconsOptions._refresh()
                end)
                row._deleteBtn:SetScript("OnClick", function()
                    local entryName = ExtraIconsOptions._getEntryName(entry)
                    StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", entryName, nil, {
                        onAccept = function()
                            ExtraIconsOptions._removeEntry(getProfile(), viewerKey, ci)
                            scheduleUpdate()
                            ExtraIconsOptions._refresh()
                        end,
                    })
                end)

                setRowMouseover(row)

                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", CONTENT_MARGIN, y)
                row:SetPoint("RIGHT", viewerCanvas, "RIGHT", -20, 0)
                row:Show()
                y = y - ROW_HEIGHT
            end

            y = y - 12
        end
    end

    --------------------------------------------------------------------
    -- Combined refresh
    --------------------------------------------------------------------
    function ExtraIconsOptions._refresh()
        refreshViewerLists()
        refreshVisibleSettingsControls()
    end

    local function addStackPreset(stackKey)
        local viewers = getViewers()
        if ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
            return
        end

        ExtraIconsOptions._addStackKey(getProfile(), "utility", stackKey)
        scheduleUpdate()
        ExtraIconsOptions._refresh()
    end

    local function addRacialPreset()
        local spellId = getPlayerRacialSpellId()
        local viewers = getViewers()
        if not spellId or ExtraIconsOptions._isRacialPresent(viewers, spellId) then
            return
        end

        ExtraIconsOptions._addRacial(getProfile(), "utility", spellId)
        scheduleUpdate()
        ExtraIconsOptions._refresh()
    end

    --------------------------------------------------------------------
    -- Register via table
    --------------------------------------------------------------------
    local addTypeValues = {
        spell = L["ADD_SPELL"],
        item = L["ADD_ITEM"],
    }
    local addViewerValues = {
        utility = L["UTILITY_VIEWER"],
        main = L["MAIN_VIEWER"],
    }

    local args = {
        enabled = {
            type = "toggle",
            path = "enabled",
            name = L["ENABLE_EXTRA_ICONS"],
            desc = L["ENABLE_EXTRA_ICONS_DESC"],
            order = 0,
            onSet = function(value)
                local handler = ns.OptionUtil.CreateModuleEnabledHandler("ExtraIcons")
                handler(value)
            end,
        },
        addHeader = {
            type = "header",
            name = L["ADD_NEW_HEADER"],
            order = 10,
        },
        addType = {
            type = "select",
            name = L["ENTRY_TYPE"],
            values = addTypeValues,
            key = "addType",
            default = formState.kind,
            layout = false,
            order = 11,
            disabled = isDisabled,
            get = function()
                return formState.kind
            end,
            set = function(value)
                formState.kind = value
            end,
        },
        addViewer = {
            type = "select",
            name = L["ENTRY_VIEWER"],
            values = addViewerValues,
            key = "addViewer",
            default = formState.viewer,
            layout = false,
            order = 12,
            disabled = isDisabled,
            get = function()
                return formState.viewer
            end,
            set = function(value)
                formState.viewer = value
            end,
        },
        addId = {
            type = "input",
            name = L["ENTRY_ID"],
            key = "addId",
            default = formState.idText,
            debounce = 1,
            disabled = isDisabled,
            layout = false,
            maxLetters = 10,
            numeric = true,
            order = 13,
            watch = { "addType" },
            get = function()
                return formState.idText
            end,
            set = function(value)
                formState.idText = value or ""
            end,
            resolveText = function(text)
                return ExtraIconsOptions._resolveDraftEntryName(formState.kind, text)
            end,
        },
        addEntry = {
            type = "button",
            name = L["ADD_ENTRY"],
            buttonText = L["ADD_ENTRY"],
            disabled = function()
                return isDisabled() or not canAddDraftEntry()
            end,
            layout = false,
            onClick = addDraftEntry,
            order = 14,
        },
    }

    for i, stackKey in ipairs(BUILTIN_STACK_ORDER) do
        local stack = BUILTIN_STACKS[stackKey]
        args["quickAdd_" .. stackKey] = {
            type = "button",
            name = stack.label,
            buttonText = L["ADD_ENTRY"],
            hidden = function()
                return ExtraIconsOptions._isStackKeyPresent(getViewers(), stackKey)
            end,
            disabled = isDisabled,
            order = 41 + i,
            onClick = function()
                addStackPreset(stackKey)
            end,
        }
    end

    local racialSpellId = getPlayerRacialSpellId()
    local racialName = racialSpellId and C_Spell.GetSpellName(racialSpellId) or nil
    args.quickAddRacial = {
        type = "button",
        name = racialName or "Racial",
        buttonText = L["ADD_ENTRY"],
        hidden = function()
            local spellId = getPlayerRacialSpellId()
            return spellId == nil or ExtraIconsOptions._isRacialPresent(getViewers(), spellId)
        end,
        disabled = isDisabled,
        order = 42 + #BUILTIN_STACK_ORDER,
        onClick = addRacialPreset,
    }

    args.viewers = {
        type = "canvas",
        canvas = viewerCanvas,
        height = 400,
        disabled = isDisabled,
        order = 30,
    }

    args.presetsHeader = {
        type = "header",
        name = L["PRESETS_HEADER"],
        order = 40,
        disabled = isDisabled,
        hidden = function()
            return not hasVisibleQuickAddEntries()
        end,
    }

    SB.RegisterFromTable({
        name = L["EXTRA_ICONS"],
        path = "extraIcons",
        onShow = function()
            ExtraIconsOptions._refresh()
        end,
        args = args,
    })

    pageCategory = SB.GetSubcategory(L["EXTRA_ICONS"])
    ExtraIconsOptions._category = pageCategory
end

ns.SettingsBuilder.RegisterSection(ns, "ExtraIcons", ExtraIconsOptions)
