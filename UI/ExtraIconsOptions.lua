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
local DRAFT_ENTRY_ROW_HEIGHT = 28
local DRAFT_ENTRY_PREVIEW_ICON_SIZE = 16
local DRAFT_TYPE_BUTTON_WIDTH = 58
local DRAFT_ID_BOX_WIDTH = 120
local DRAFT_ADD_BUTTON_WIDTH = 44
local TOOLTIP_ITEM_ICON_SIZE = 14
local TOOLTIP_QUALITY_ICON_SIZE = 14
local SETTINGS_LABEL_X = 37
local SPECIAL_ROWS_LEGEND_HEIGHT = 24
local VIEWER_ROW_SPACING = 4
local VIEWER_CANVAS_HEIGHT = 448
local DEFAULT_SPECIAL_VIEWER = "utility"
local DRAFT_PENDING_TEXT = "..."
local VIEWER_ORDER = { "utility", "main" }
local VIEWER_LABELS = {
    utility = "UTILITY_VIEWER_ICONS",
    main = "MAIN_VIEWER_ICONS",
}
local RACIAL_ALIASES = {
    undead = "Scourge",
    earthen = "EarthenDwarf",
}

local RACIAL_ABILITIES_BY_NORMALIZED_KEY = {}
for raceKey, racialEntry in pairs(RACIAL_ABILITIES) do
    if type(raceKey) == "string" then
        local normalizedKey = raceKey:gsub("[^%a%d]", ""):lower()
        RACIAL_ABILITIES_BY_NORMALIZED_KEY[normalizedKey] = racialEntry
    end
end

local function getViewerShortLabel(viewerKey)
    return viewerKey == "utility" and L["UTILITY_VIEWER_SHORT"] or L["MAIN_VIEWER_SHORT"]
end

local function getBuiltinOrderIndex(stackKey)
    for index, builtinKey in ipairs(BUILTIN_STACK_ORDER) do
        if builtinKey == stackKey then
            return index
        end
    end

    return nil
end

local function isDisabledBuiltinEntry(entry)
    return entry and entry.stackKey and entry.disabled and getBuiltinOrderIndex(entry.stackKey) ~= nil
end

local ExtraIconsOptions = {}
ns.ExtraIconsOptions = ExtraIconsOptions
ExtraIconsOptions._pendingItemLoads = ExtraIconsOptions._pendingItemLoads or {}

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

local function lookupRacialEntryByRaceKey(raceKey)
    if type(raceKey) ~= "string" or raceKey == "" then
        return nil
    end

    local direct = RACIAL_ABILITIES[raceKey]
    if direct then
        return direct
    end

    local normalizedKey = raceKey:gsub("[^%a%d]", ""):lower()
    local aliasKey = RACIAL_ALIASES[normalizedKey]
    if aliasKey and RACIAL_ABILITIES[aliasKey] then
        return RACIAL_ABILITIES[aliasKey]
    end

    return RACIAL_ABILITIES_BY_NORMALIZED_KEY[normalizedKey]
end

local function lookupKnownRacialEntry()
    if type(IsPlayerSpell) ~= "function" then
        return nil
    end

    for _, racialEntry in pairs(RACIAL_ABILITIES) do
        if racialEntry and racialEntry.spellId and IsPlayerSpell(racialEntry.spellId) then
            return racialEntry
        end
    end

    return nil
end

local function getCurrentRacialEntry()
    local raceName, raceFile = UnitRace("player")
    return lookupRacialEntryByRaceKey(raceFile)
        or lookupRacialEntryByRaceKey(raceName)
        or lookupKnownRacialEntry()
end

local function getCurrentRacialSpellId()
    local racial = getCurrentRacialEntry()
    return racial and racial.spellId or nil
end

local function getEntrySpellId(entry)
    if not (entry and entry.kind == "spell" and entry.ids and entry.ids[1]) then
        return nil
    end

    local first = entry.ids[1]
    return type(first) == "table" and first.spellId or first
end

local function markPendingItemLoad(itemId)
    if itemId then
        ExtraIconsOptions._pendingItemLoads[itemId] = true
    end
end

--- Check if a racial spellId is present in any viewer's entries.
function ExtraIconsOptions._isRacialPresent(viewers, spellId)
    for _, entries in pairs(viewers) do
        for _, entry in ipairs(entries) do
            if getEntrySpellId(entry) == spellId then
                return true
            end
        end
    end
    return false
end

function ExtraIconsOptions._isCurrentRacialEntry(entry)
    local racialSpellId = getCurrentRacialSpellId()
    return racialSpellId ~= nil and getEntrySpellId(entry) == racialSpellId
end

local function getItemIdFromEntry(entry)
    return type(entry) == "table" and (entry.itemID or entry.itemId) or entry
end

local function getItemDisplayName(itemId)
    if not itemId then
        return nil
    end

    local name = C_Item.GetItemNameByID(itemId)
    if name then
        ExtraIconsOptions._pendingItemLoads[itemId] = nil
        return name
    end

    if C_Item.DoesItemExistByID(itemId) then
        markPendingItemLoad(itemId)
        C_Item.RequestLoadItemDataByID(itemId)
        return L["EXTRA_ICONS_ITEM_LOADING"]
    end

    return "Item " .. tostring(itemId)
end

local function getEquippedItemDisplayName(slotId)
    local itemId = GetInventoryItemID("player", slotId)
    if not itemId then
        return nil
    end

    return getItemDisplayName(itemId)
end

local function getTextureMarkup(texture, size)
    if not texture or type(CreateTextureMarkup) ~= "function" then
        return nil
    end

    return CreateTextureMarkup(texture, 64, 64, size, size, 0, 1, 0, 1)
end

local function getQualityMarkup(quality)
    if not quality then
        return nil
    end

    if type(CreateAtlasMarkup) == "function" then
        return CreateAtlasMarkup(
            "Professions-Icon-Quality-Tier" .. tostring(quality) .. "-Small",
            TOOLTIP_QUALITY_ICON_SIZE,
            TOOLTIP_QUALITY_ICON_SIZE
        )
    end

    return "[R" .. tostring(quality) .. "]"
end

local function buildTooltipLine(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if value and value ~= "" then
            parts[#parts + 1] = value
        end
    end

    return table.concat(parts, " ")
end

local function addItemStackTooltipLines(entry)
    local stack = entry.stackKey and BUILTIN_STACKS[entry.stackKey]
    if not stack or stack.kind ~= "item" or not stack.ids or #stack.ids == 0 then
        return false
    end

    GameTooltip:AddLine(L["EXTRA_ICONS_STACK_TOOLTIP_INTRO"], nil, nil, nil, true)

    for _, itemEntry in ipairs(stack.ids) do
        local itemId = getItemIdFromEntry(itemEntry)
        local icon = itemId and C_Item.GetItemIconByID(itemId) or nil
        local itemName = getItemDisplayName(itemId)
        local quality = type(itemEntry) == "table" and itemEntry.quality or nil
        GameTooltip:AddLine(
            buildTooltipLine(
                getTextureMarkup(icon, TOOLTIP_ITEM_ICON_SIZE),
                itemName or ("Item " .. tostring(itemId)),
                getQualityMarkup(quality)
            ),
            1,
            1,
            1
        )
    end

    return true
end

--- Get display name for a config entry.
function ExtraIconsOptions._getEntryName(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then
            return entry.stackKey
        end

        if stack.kind == "equipSlot" then
            local itemName = getEquippedItemDisplayName(stack.slotId)
            if itemName then
                return ("%s [%s]"):format(stack.label, itemName)
            end
        end

        return stack.label
    end
    if entry.kind == "spell" and entry.ids then
        local first = entry.ids[1]
        local spellId = type(first) == "table" and first.spellId or first
        local spellAPI = type(C_Spell) == "table" and C_Spell or nil
        local name = spellId and spellAPI and spellAPI.GetSpellName and spellAPI.GetSpellName(spellId)
        return name or ("Spell " .. tostring(spellId))
    end
    if entry.kind == "item" and entry.ids then
        local first = entry.ids[1]
        return getItemDisplayName(getItemIdFromEntry(first))
    end
    return "Unknown"
end

local function getEntryTooltipTitle(entry)
    local name = ExtraIconsOptions._getEntryName(entry)
    if type(entry) ~= "table" then
        return name
    end

    if entry.kind == "spell" then
        local spellId = getEntrySpellId(entry)
        if spellId then
            return string.format("%s (spell ID %s)", name, spellId)
        end
    elseif entry.kind == "item" and entry.ids and entry.ids[1] then
        local itemId = getItemIdFromEntry(entry.ids[1])
        if itemId then
            return string.format("%s (item ID %s)", name, itemId)
        end
    end

    return name
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
        local spellAPI = type(C_Spell) == "table" and C_Spell or nil
        return spellId and spellAPI and spellAPI.GetSpellTexture and spellAPI.GetSpellTexture(spellId)
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
    if ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
        return
    end
    viewers[viewerKey] = viewers[viewerKey] or {}
    viewers[viewerKey][#viewers[viewerKey] + 1] = { stackKey = stackKey }
end

--- Add a racial spell entry to a viewer.
function ExtraIconsOptions._addRacial(profile, viewerKey, spellId)
    local viewers = profile.extraIcons.viewers
    if ExtraIconsOptions._isRacialPresent(viewers, spellId) then
        return
    end
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
    if ExtraIconsOptions._isDuplicateEntry(viewers, entry) then
        return
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

function ExtraIconsOptions._setEntryDisabled(profile, viewerKey, index, disabled)
    local entries = profile.extraIcons.viewers[viewerKey]
    local entry = entries and entries[index]
    if not entry then
        return
    end

    entry.disabled = disabled and true or nil
end

function ExtraIconsOptions._toggleBuiltinRow(profile, viewerKey, index, stackKey)
    if index then
        local entries = profile.extraIcons.viewers[viewerKey]
        local entry = entries and entries[index]
        if not entry then
            return
        end

        ExtraIconsOptions._setEntryDisabled(profile, viewerKey, index, not entry.disabled)
        return
    end

    ExtraIconsOptions._addStackKey(profile, viewerKey, stackKey)
end

function ExtraIconsOptions._toggleCurrentRacialRow(profile, viewerKey, index, spellId)
    if index then
        ExtraIconsOptions._removeEntry(profile, viewerKey, index)
        return
    end

    if spellId then
        ExtraIconsOptions._addRacial(profile, viewerKey, spellId)
    end
end

--- Swap entry with its neighbor (-1 = up, +1 = down).
function ExtraIconsOptions._reorderEntry(profile, viewerKey, index, direction)
    local entries = profile.extraIcons.viewers[viewerKey]
    if not entries then return end
    local target = index + direction
    while target >= 1 and target <= #entries and isDisabledBuiltinEntry(entries[target]) do
        target = target + direction
    end
    if target < 1 or target > #entries then return end
    entries[index], entries[target] = entries[target], entries[index]
end

--- Move entry from one viewer to another (appends at end).
function ExtraIconsOptions._moveEntry(profile, fromViewer, toViewer, index)
    local from = profile.extraIcons.viewers[fromViewer]
    if not from or index < 1 or index > #from then return end
    local candidateEntry = from[index]
    if ExtraIconsOptions._findDuplicateEntry(profile.extraIcons.viewers, candidateEntry, fromViewer, index) == toViewer then
        return
    end
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

--- Resolve a draft spell or item ID to preview data.
---@param kind string
---@param text string|nil
---@return string status "invalid"|"pending"|"resolved"
---@return string|nil name
---@return string|number|nil icon
function ExtraIconsOptions._resolveDraftEntryPreview(kind, text)
    local id = ExtraIconsOptions._parseSingleId(text)
    if not id then
        return "invalid", nil, nil
    end

    if kind == "spell" then
        local spellAPI = type(C_Spell) == "table" and C_Spell or nil
        local name = spellAPI and spellAPI.GetSpellName and spellAPI.GetSpellName(id)
        if not name then
            return "invalid", nil, nil
        end

        return "resolved", name, spellAPI.GetSpellTexture and spellAPI.GetSpellTexture(id)
    end

    if kind == "item" then
        if not C_Item.DoesItemExistByID(id) then
            return "invalid", nil, nil
        end

        local name = C_Item.GetItemNameByID(id)
        local icon = C_Item.GetItemIconByID(id)
        if name then
            ExtraIconsOptions._pendingItemLoads[id] = nil
            return "resolved", name, icon
        end

        markPendingItemLoad(id)
        C_Item.RequestLoadItemDataByID(id)

        return "pending", nil, icon
    end

    return "invalid", nil, nil
end

--- Resolve a draft spell or item ID to a display name.
---@param kind string
---@param text string|nil
---@return string|nil
function ExtraIconsOptions._resolveDraftEntryName(kind, text)
    local status, name = ExtraIconsOptions._resolveDraftEntryPreview(kind, text)
    if status ~= "resolved" then
        return nil
    end
    return name
end

local function getEntryIdentityKey(entry)
    if not entry then
        return nil
    end

    if entry.stackKey then
        return "stack:" .. tostring(entry.stackKey)
    end

    if entry.kind == "spell" and entry.ids and #entry.ids > 0 then
        local parts = { "spell" }
        for _, id in ipairs(entry.ids) do
            local spellId = type(id) == "table" and id.spellId or id
            parts[#parts + 1] = tostring(spellId)
        end
        return table.concat(parts, ":")
    end

    if entry.kind == "item" and entry.ids and #entry.ids > 0 then
        local parts = { "item" }
        for _, id in ipairs(entry.ids) do
            parts[#parts + 1] = tostring(getItemIdFromEntry(id))
        end
        return table.concat(parts, ":")
    end

    return nil
end

function ExtraIconsOptions._findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    local candidateKey = getEntryIdentityKey(candidateEntry)
    if not candidateKey then
        return nil, nil
    end

    for viewerKey, entries in pairs(viewers) do
        for index, entry in ipairs(entries) do
            if not (viewerKey == ignoreViewerKey and index == ignoreIndex)
                and getEntryIdentityKey(entry) == candidateKey then
                return viewerKey, index
            end
        end
    end

    return nil, nil
end

function ExtraIconsOptions._isDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    local viewerKey = ExtraIconsOptions._findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    return viewerKey ~= nil
end

local function buildDraftEntry(kind, id)
    if not id then
        return nil
    end

    if kind == "item" then
        return { kind = "item", ids = { { itemID = id } } }
    end

    if kind == "spell" then
        return { kind = "spell", ids = { id } }
    end

    return nil
end

function ExtraIconsOptions._buildViewerRows(viewers, viewerKey)
    local activeRows = {}
    local entries = viewers[viewerKey] or {}
    local disabledBuiltinRows = {}

    for index, entry in ipairs(entries) do
        if ExtraIconsOptions._isRacialForCurrentPlayer(entry) then
            local rowData = {
                rowType = "entry",
                viewerKey = viewerKey,
                index = index,
                entry = entry,
                displayEntry = entry,
                isBuiltin = entry.stackKey ~= nil,
                isCurrentRacial = ExtraIconsOptions._isCurrentRacialEntry(entry),
                isPlaceholder = false,
                isDisabled = entry.disabled == true,
            }

            if isDisabledBuiltinEntry(entry) then
                disabledBuiltinRows[entry.stackKey] = disabledBuiltinRows[entry.stackKey] or {}
                disabledBuiltinRows[entry.stackKey][#disabledBuiltinRows[entry.stackKey] + 1] = rowData
            else
                activeRows[#activeRows + 1] = rowData
            end
        end
    end

    for activeIndex, rowData in ipairs(activeRows) do
        rowData.activeIndex = activeIndex
        rowData.activeCount = #activeRows
    end

    local rows = activeRows

    for _, stackKey in ipairs(BUILTIN_STACK_ORDER) do
        local bucket = disabledBuiltinRows[stackKey]
        if bucket then
            for _, rowData in ipairs(bucket) do
                rows[#rows + 1] = rowData
            end
        elseif viewerKey == DEFAULT_SPECIAL_VIEWER and not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
            rows[#rows + 1] = {
                    rowType = "builtinPlaceholder",
                    viewerKey = viewerKey,
                    stackKey = stackKey,
                    displayEntry = { stackKey = stackKey },
                    isBuiltin = true,
                    isCurrentRacial = false,
                    isPlaceholder = true,
                    isDisabled = true,
            }
        end
    end

    if viewerKey == DEFAULT_SPECIAL_VIEWER then
        local racialSpellId = getCurrentRacialSpellId()
        if racialSpellId and not ExtraIconsOptions._isRacialPresent(viewers, racialSpellId) then
            rows[#rows + 1] = {
                rowType = "racialPlaceholder",
                viewerKey = viewerKey,
                spellId = racialSpellId,
                displayEntry = { kind = "spell", ids = { racialSpellId } },
                isBuiltin = false,
                isCurrentRacial = true,
                isPlaceholder = true,
                isDisabled = true,
            }
        end
    end

    return rows
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
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
        GameTooltip:SetText(text, 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end

local function addTooltipLine(text)
    if text and text ~= "" then
        GameTooltip:AddLine(text, nil, nil, nil, true)
    end
end

local function showRowTooltip(owner, rowData)
    if not rowData then
        return
    end

    local displayEntry = rowData.displayEntry
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then
        GameTooltip:ClearLines()
    end
    GameTooltip:SetText(getEntryTooltipTitle(displayEntry), 1, 1, 1)

    if rowData.isBuiltin then
        if rowData.isPlaceholder then
            addTooltipLine(L["EXTRA_ICONS_BUILTIN_PLACEHOLDER_TOOLTIP"])
        end
    elseif rowData.isCurrentRacial and rowData.isPlaceholder then
        addTooltipLine(L["EXTRA_ICONS_RACIAL_PLACEHOLDER_TOOLTIP"])
    end

    if rowData.isBuiltin and rowData.isDisabled and not rowData.isPlaceholder then
        addTooltipLine(L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"])
    end

    addItemStackTooltipLines(displayEntry)
    GameTooltip:Show()
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

local function setRowMouseover(row, tooltipBuilder)
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
        if tooltipBuilder then
            tooltipBuilder(self)
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self._highlight then
            self._highlight:Hide()
        end
        GameTooltip_Hide()
    end)
end

--- Check if a racial entry belongs to the current player character.
function ExtraIconsOptions._isRacialForCurrentPlayer(entry)
    local spellId = getEntrySpellId(entry)
    if not spellId then return true end
    local racial = getCurrentRacialEntry()
    if not racial then return true end
    for _, racialEntry in pairs(RACIAL_ABILITIES) do
        if racialEntry ~= racial then
            if spellId == racialEntry.spellId then
                return false
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

local function createDraftRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(DRAFT_ENTRY_ROW_HEIGHT)

    row._typeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._typeBtn:SetSize(DRAFT_TYPE_BUTTON_WIDTH, BTN_SIZE)
    row._typeBtn:SetPoint("LEFT", row, "LEFT", 0, 0)

    row._editBox = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    row._editBox:SetPoint("LEFT", row._typeBtn, "RIGHT", 6, 0)
    row._editBox:SetSize(DRAFT_ID_BOX_WIDTH, 20)
    row._editBox:SetAutoFocus(false)
    if type(row._editBox.SetNumeric) == "function" then
        row._editBox:SetNumeric(true)
    end
    if type(row._editBox.SetMaxLetters) == "function" then
        row._editBox:SetMaxLetters(10)
    end
    if type(row._editBox.SetTextInsets) == "function" then
        row._editBox:SetTextInsets(6, 6, 0, 0)
    end

    row._editBoxPlaceholder = row._editBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    row._editBoxPlaceholder:SetPoint("LEFT", row._editBox, "LEFT", 6, 0)
    row._editBoxPlaceholder:SetPoint("RIGHT", row._editBox, "RIGHT", -6, 0)
    row._editBoxPlaceholder:SetJustifyH("LEFT")
    row._editBoxPlaceholder:SetWordWrap(false)

    row._previewIcon = row:CreateTexture(nil, "ARTWORK")
    row._previewIcon:SetPoint("LEFT", row._editBox, "RIGHT", 8, 0)
    row._previewIcon:SetSize(DRAFT_ENTRY_PREVIEW_ICON_SIZE, DRAFT_ENTRY_PREVIEW_ICON_SIZE)
    row._previewIcon:Hide()

    row._previewLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row._previewLabel:SetPoint("LEFT", row._previewIcon, "RIGHT", 4, 0)
    row._previewLabel:SetJustifyH("LEFT")
    row._previewLabel:SetWordWrap(false)
    row._previewLabel:Hide()

    row._addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row._addBtn:SetSize(DRAFT_ADD_BUTTON_WIDTH, BTN_SIZE)
    row._addBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row._addBtn:SetText(L["ADD_ENTRY"])

    row._previewLabel:SetPoint("RIGHT", row._addBtn, "LEFT", -6, 0)

    return row
end

local function createViewerHeaderRow(parent, SB, text, headerHeight)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(headerHeight)
    row._title = SB.CreateSubheaderTitle(row, text)
    return row
end

--------------------------------------------------------------------------------
-- Embedded Content: Viewer lists
--------------------------------------------------------------------------------

local function createViewerListCanvas(SB, headerHeight)
    local frame = CreateFrame("Frame")
    frame:SetHeight(VIEWER_CANVAS_HEIGHT)

    frame._viewerRowPools = { utility = {}, main = {} }
    frame._viewerDraftRows = {}
    frame._viewerHeaders = {}
    frame._viewerEmptyLabels = {}
    frame._legendLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame._legendLabel:SetJustifyH("LEFT")
    frame._legendLabel:SetWordWrap(true)
    frame._legendLabel:SetText(L["EXTRA_ICONS_SPECIAL_ROWS_LEGEND"])

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

    ExtraIconsOptions._viewerCanvas = viewerCanvas
    ExtraIconsOptions._draftEntryCanvas = nil
    ExtraIconsOptions._addFormCanvas = nil
    ExtraIconsOptions._presetsCanvas = nil

    local function getProfile()
        return ns.Addon.db.profile
    end

    local function getViewers()
        return getProfile().extraIcons.viewers
    end

    ExtraIconsOptions._draftStates = ExtraIconsOptions._draftStates or {}
    local draftStates = ExtraIconsOptions._draftStates
    for _, viewerKey in ipairs(VIEWER_ORDER) do
        draftStates[viewerKey] = draftStates[viewerKey] or {
            kind = "spell",
            idText = "",
        }
    end

    local itemLoadFrame = ExtraIconsOptions._itemLoadFrame
    if not itemLoadFrame then
        itemLoadFrame = CreateFrame("Frame")
        ExtraIconsOptions._itemLoadFrame = itemLoadFrame
    end
    if not itemLoadFrame._ecmHooked then
        if itemLoadFrame.RegisterEvent then
            itemLoadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        end
        itemLoadFrame:SetScript("OnEvent", function(_, _, itemId)
            if itemId and ExtraIconsOptions._pendingItemLoads[itemId] then
                ExtraIconsOptions._pendingItemLoads[itemId] = nil
                if ExtraIconsOptions._refresh then
                    ExtraIconsOptions._refresh()
                end
            end
        end)
        itemLoadFrame._ecmHooked = true
    end

    local function scheduleUpdate()
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end

    local function refreshVisibleSettingsControls()
        local panel = SettingsPanel
        if not panel or not panel.IsShown or not panel:IsShown() then
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

    local function resetDraftStates()
        for _, viewerKey in ipairs(VIEWER_ORDER) do
            draftStates[viewerKey].kind = "spell"
            draftStates[viewerKey].idText = ""
        end
    end

    local function getDraftResolution(viewerKey)
        local draftState = draftStates[viewerKey]
        return ExtraIconsOptions._resolveDraftEntryPreview(draftState.kind, draftState.idText)
    end

    local function getDraftPlaceholderText(draftState)
        if draftState.kind == "spell" then
            return L["EXTRA_ICONS_SPELL_ID_PLACEHOLDER"]
        end

        return L["EXTRA_ICONS_ITEM_ID_PLACEHOLDER"]
    end

    local function refreshDraftPlaceholder(row, viewerKey)
        if not (row and row._editBoxPlaceholder) then
            return
        end

        local draftState = draftStates[viewerKey]
        local idText = draftState and draftState.idText or ""
        row._editBoxPlaceholder:SetText(getDraftPlaceholderText(draftState))

        if row._editBoxHasFocus or idText ~= "" then
            row._editBoxPlaceholder:Hide()
        else
            row._editBoxPlaceholder:Show()
        end
    end

    local function focusDraftEditBox(row)
        if not (row and row._editBox) then
            return
        end

        if row._editBox.SetFocus then
            row._editBox:SetFocus()
        end
        row._editBoxHasFocus = true
        refreshDraftPlaceholder(row, row._viewerKey)
        if row._editBox.HighlightText then
            row._editBox:HighlightText()
        end
    end

    local function getDraftDuplicateInfo(viewerKey)
        local draftState = draftStates[viewerKey]
        local id = ExtraIconsOptions._parseSingleId(draftState.idText)
        local entry = buildDraftEntry(draftState.kind, id)
        local duplicateViewerKey = entry and ExtraIconsOptions._findDuplicateEntry(getViewers(), entry) or nil
        return duplicateViewerKey ~= nil, duplicateViewerKey
    end

    local function canAddDraftEntry(viewerKey)
        local status = getDraftResolution(viewerKey)
        if status ~= "resolved" then
            return false
        end

        local isDuplicate = getDraftDuplicateInfo(viewerKey)
        return not isDuplicate
    end

    local function addDraftEntry(viewerKey, row)
        local draftState = draftStates[viewerKey]
        local id = ExtraIconsOptions._parseSingleId(draftState.idText)
        if not id or not canAddDraftEntry(viewerKey) then
            return
        end

        ExtraIconsOptions._addCustomEntry(getProfile(), viewerKey, draftState.kind, { id })
        draftState.idText = ""
        scheduleUpdate()
        ExtraIconsOptions._refresh()
        focusDraftEditBox(row)
    end

    local function restoreDefaultExtraIcons()
        local defaultsProfile = ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
        local defaultsConfig = defaultsProfile and defaultsProfile.extraIcons
        if not defaultsConfig then
            return
        end

        ns.Addon.db.profile.extraIcons = ns.CloneValue(defaultsConfig)
        resetDraftStates()
        scheduleUpdate()
        ExtraIconsOptions._refresh()
    end

    local function setRowVisualState(row, isDisabledRow)
        local alpha = isDisabledRow and 0.55 or 1
        if row._label and type(row._label.SetFontObject) == "function" then
            local fontObject = isDisabledRow and (_G.GameFontDisable or _G.GameFontNormal) or _G.GameFontNormal
            if fontObject then
                row._label:SetFontObject(fontObject)
            end
        end
        if row._label and type(row._label.SetAlpha) == "function" then
            row._label:SetAlpha(alpha)
        end
        if row._icon and type(row._icon.SetAlpha) == "function" then
            row._icon:SetAlpha(alpha)
        end
        if row._icon and type(row._icon.SetDesaturated) == "function" then
            row._icon:SetDesaturated(isDisabledRow)
        end
        if row._icon and type(row._icon.SetVertexColor) == "function" then
            if isDisabledRow then
                row._icon:SetVertexColor(0.6, 0.6, 0.6, 1)
            else
                row._icon:SetVertexColor(1, 1, 1, 1)
            end
        end
        if row._label and type(row._label.SetTextColor) == "function" then
            if isDisabledRow then
                row._label:SetTextColor(0.65, 0.65, 0.65, 1)
            else
                row._label:SetTextColor(1, 0.82, 0, 1)
            end
        end
    end

    local function ensureDraftRow(viewerKey)
        local row = viewerCanvas._viewerDraftRows[viewerKey]
        if row then
            return row
        end

        row = createDraftRow(viewerCanvas)
        viewerCanvas._viewerDraftRows[viewerKey] = row
        row._viewerKey = viewerKey

        setButtonTooltip(row._typeBtn, L["EXTRA_ICONS_DRAFT_TYPE_TOOLTIP"])
        setButtonTooltip(row._addBtn, L["ADD_ENTRY"])

        row._typeBtn:SetScript("OnClick", function()
            if isDisabled() then
                return
            end

            local draftState = draftStates[viewerKey]
            draftState.kind = draftState.kind == "spell" and "item" or "spell"
            ExtraIconsOptions._refresh()
        end)

        row._editBox:SetScript("OnTextChanged", function(self)
            if row._syncingText then
                return
            end

            draftStates[viewerKey].idText = self:GetText() or ""
            ExtraIconsOptions._refresh()
        end)

        row._editBox:SetScript("OnEnterPressed", function()
            addDraftEntry(viewerKey, row)
        end)

        row._editBox:SetScript("OnTabPressed", function(self)
            if isDisabled() then
                return
            end

            local draftState = draftStates[viewerKey]
            draftState.kind = draftState.kind == "spell" and "item" or "spell"
            ExtraIconsOptions._refresh()
            focusDraftEditBox(row)
        end)

        row._editBox:SetScript("OnEditFocusGained", function()
            row._editBoxHasFocus = true
            refreshDraftPlaceholder(row, viewerKey)
            if row._editBox.HighlightText and (row._editBox:GetText() or "") ~= "" then
                row._editBox:HighlightText()
            end
        end)

        row._editBox:SetScript("OnEditFocusLost", function()
            row._editBoxHasFocus = false
            refreshDraftPlaceholder(row, viewerKey)
        end)

        row._editBox:SetScript("OnEscapePressed", function(self)
            if self.ClearFocus then
                self:ClearFocus()
            end
            row._editBoxHasFocus = false
            refreshDraftPlaceholder(row, viewerKey)
        end)

        row._addBtn:SetScript("OnClick", function()
            addDraftEntry(viewerKey, row)
        end)

        return row
    end

    local function refreshDraftRow(viewerKey, row)
        local draftState = draftStates[viewerKey]
        local controlsDisabled = isDisabled()
        local status, name, icon = getDraftResolution(viewerKey)
        local isDuplicate, duplicateViewerKey = getDraftDuplicateInfo(viewerKey)

        row._typeBtn:SetText(draftState.kind == "spell" and L["ADD_SPELL"] or L["ADD_ITEM"])
        if row._typeBtn.SetEnabled then
            row._typeBtn:SetEnabled(not controlsDisabled)
        end

        if row._editBox.GetText and row._editBox:GetText() ~= draftState.idText then
            row._syncingText = true
            row._editBox:SetText(draftState.idText)
            row._syncingText = nil
        end
        if row._editBox.SetEnabled then
            row._editBox:SetEnabled(not controlsDisabled)
        end
        refreshDraftPlaceholder(row, viewerKey)

        if icon then
            row._previewIcon:SetTexture(icon)
            row._previewIcon:Show()
        else
            row._previewIcon:SetTexture(nil)
            row._previewIcon:Hide()
        end

        if status == "resolved" and isDuplicate then
            row._previewLabel:SetText(
                L["EXTRA_ICONS_DUPLICATE_ENTRY"]:format(getViewerShortLabel(duplicateViewerKey)))
            row._previewLabel:Show()
        elseif status == "resolved" then
            row._previewLabel:SetText(name or "")
            row._previewLabel:Show()
        elseif status == "pending" then
            row._previewLabel:SetText(DRAFT_PENDING_TEXT)
            row._previewLabel:Show()
        else
            row._previewLabel:SetText("")
            row._previewLabel:Hide()
        end

        row._addBtn:Show()
        if row._addBtn.SetEnabled then
            row._addBtn:SetEnabled(not controlsDisabled and status == "resolved" and not isDuplicate)
        end
    end

    local function configureEntryRow(row, rowData)
        local controlsDisabled = isDisabled()
        local displayEntry = rowData.displayEntry
        local otherViewer = ExtraIconsOptions._otherViewer(rowData.viewerKey)
        local duplicateViewerKey = rowData.index ~= nil
            and ExtraIconsOptions._findDuplicateEntry(getViewers(), displayEntry, rowData.viewerKey, rowData.index)
            or nil
        local hasMoveDuplicate = duplicateViewerKey == otherViewer
        local positionLocked = rowData.isBuiltin and rowData.isDisabled
        local canReorder = not controlsDisabled and rowData.activeIndex ~= nil and not positionLocked
        local canMove = not controlsDisabled and rowData.index ~= nil and not positionLocked and not hasMoveDuplicate

        row._label:SetText(ExtraIconsOptions._getEntryName(displayEntry))
        row._icon:SetTexture(ExtraIconsOptions._getEntryIcon(displayEntry) or 134400)
        setRowVisualState(row, rowData.isDisabled)

        row._upBtn:SetEnabled(canReorder and rowData.activeIndex > 1)
        row._downBtn:SetEnabled(canReorder and rowData.activeIndex < rowData.activeCount)
        row._moveBtn:SetEnabled(canMove)
        row._deleteBtn:SetEnabled(not controlsDisabled)
        row._moveBtn:SetText(rowData.viewerKey == "utility" and ">" or "<")

        setButtonTooltip(row._upBtn, L["MOVE_UP_TOOLTIP"])
        setButtonTooltip(row._downBtn, L["MOVE_DOWN_TOOLTIP"])
        if hasMoveDuplicate then
            setButtonTooltip(row._moveBtn, L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(getViewerShortLabel(otherViewer)))
        elseif positionLocked then
            setButtonTooltip(row._moveBtn, L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"])
        else
            setButtonTooltip(row._moveBtn, L["MOVE_TO_VIEWER_TOOLTIP"]:format(otherViewer))
        end

        row._upBtn:SetScript("OnClick", function()
            if rowData.index == nil or not canReorder then
                return
            end

            ExtraIconsOptions._reorderEntry(getProfile(), rowData.viewerKey, rowData.index, -1)
            scheduleUpdate()
            ExtraIconsOptions._refresh()
        end)

        row._downBtn:SetScript("OnClick", function()
            if rowData.index == nil or not canReorder then
                return
            end

            ExtraIconsOptions._reorderEntry(getProfile(), rowData.viewerKey, rowData.index, 1)
            scheduleUpdate()
            ExtraIconsOptions._refresh()
        end)

        row._moveBtn:SetScript("OnClick", function()
            if rowData.index == nil or not canMove then
                return
            end

            ExtraIconsOptions._moveEntry(getProfile(), rowData.viewerKey, otherViewer, rowData.index)
            scheduleUpdate()
            ExtraIconsOptions._refresh()
        end)

        if rowData.isBuiltin then
            row._deleteBtn:SetText(rowData.isDisabled and "+" or "x")
            setButtonTooltip(row._deleteBtn, rowData.isDisabled and L["ENABLE_TOOLTIP"] or L["EXTRA_ICONS_HIDE_TOOLTIP"])
            row._deleteBtn:SetScript("OnClick", function()
                ExtraIconsOptions._toggleBuiltinRow(
                    getProfile(),
                    rowData.viewerKey,
                    rowData.index,
                    rowData.stackKey or displayEntry.stackKey
                )
                scheduleUpdate()
                ExtraIconsOptions._refresh()
            end)
        elseif rowData.isCurrentRacial and rowData.isPlaceholder then
            row._deleteBtn:SetText("+")
            setButtonTooltip(row._deleteBtn, L["ADD_ENTRY"])
            row._deleteBtn:SetScript("OnClick", function()
                ExtraIconsOptions._toggleCurrentRacialRow(getProfile(), rowData.viewerKey, nil, rowData.spellId)
                scheduleUpdate()
                ExtraIconsOptions._refresh()
            end)
        else
            row._deleteBtn:SetText("x")
            setButtonTooltip(row._deleteBtn, L["REMOVE_TOOLTIP"])
            row._deleteBtn:SetScript("OnClick", function()
                local entryName = ExtraIconsOptions._getEntryName(displayEntry)
                StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", entryName, nil, {
                    onAccept = function()
                        ExtraIconsOptions._removeEntry(getProfile(), rowData.viewerKey, rowData.index)
                        scheduleUpdate()
                        ExtraIconsOptions._refresh()
                    end,
                })
            end)
        end

        clearRowMouseover(row)
        setRowMouseover(row, function(self)
            showRowTooltip(self, rowData)
        end)
    end

    viewerCanvas.OnDefault = restoreDefaultExtraIcons

    --------------------------------------------------------------------
    -- Refresh: viewer lists canvas
    --------------------------------------------------------------------
    local function refreshViewerLists()
        local viewers = getViewers()
        local y = 0

        viewerCanvas._legendLabel:ClearAllPoints()
        viewerCanvas._legendLabel:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", SETTINGS_LABEL_X, y)
        viewerCanvas._legendLabel:SetPoint("RIGHT", viewerCanvas, "RIGHT", -20, 0)
        viewerCanvas._legendLabel:Show()
        y = y - SPECIAL_ROWS_LEGEND_HEIGHT

        for _, viewerKey in ipairs(VIEWER_ORDER) do
            local headerRow = viewerCanvas._viewerHeaders[viewerKey]
            headerRow:ClearAllPoints()
            headerRow:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", 0, y)
            headerRow:SetPoint("RIGHT", viewerCanvas, "RIGHT", 0, 0)
            headerRow:Show()
            y = y - viewerHeaderHeight

            local pool = viewerCanvas._viewerRowPools[viewerKey]
            local rows = ExtraIconsOptions._buildViewerRows(viewers, viewerKey)

            for _, row in ipairs(pool) do
                clearRowMouseover(row)
                row:Hide()
            end

            if #rows == 0 then
                viewerCanvas._viewerEmptyLabels[viewerKey]:ClearAllPoints()
                viewerCanvas._viewerEmptyLabels[viewerKey]:SetPoint(
                    "TOPLEFT", viewerCanvas, "TOPLEFT", SETTINGS_LABEL_X, y)
                viewerCanvas._viewerEmptyLabels[viewerKey]:Show()
                y = y - ROW_HEIGHT - VIEWER_ROW_SPACING
            else
                viewerCanvas._viewerEmptyLabels[viewerKey]:Hide()
            end

            for rowIndex, rowData in ipairs(rows) do
                local row = pool[rowIndex]
                if not row then
                    row = createEntryRow(viewerCanvas)
                    pool[rowIndex] = row
                end

                configureEntryRow(row, rowData)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", SETTINGS_LABEL_X, y)
                row:SetPoint("RIGHT", viewerCanvas, "RIGHT", -20, 0)
                row:Show()
                y = y - ROW_HEIGHT - VIEWER_ROW_SPACING
            end

            local draftRow = ensureDraftRow(viewerKey)
            refreshDraftRow(viewerKey, draftRow)
            draftRow:ClearAllPoints()
            draftRow:SetPoint("TOPLEFT", viewerCanvas, "TOPLEFT", SETTINGS_LABEL_X, y)
            draftRow:SetPoint("RIGHT", viewerCanvas, "RIGHT", -20, 0)
            draftRow:Show()
            y = y - DRAFT_ENTRY_ROW_HEIGHT

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

    SB.RegisterFromTable({
        name = L["EXTRA_ICONS"],
        path = "extraIcons",
        onShow = function()
            ExtraIconsOptions._refresh()
        end,
        args = {
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
            viewers = {
                type = "canvas",
                canvas = viewerCanvas,
                height = VIEWER_CANVAS_HEIGHT,
                disabled = isDisabled,
                order = 10,
            },
        },
    })

    ExtraIconsOptions._category = SB.GetSubcategory(L["EXTRA_ICONS"])
end

ns.SettingsBuilder.RegisterSection(ns, "ExtraIcons", ExtraIconsOptions)
