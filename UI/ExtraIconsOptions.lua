-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local BUILTIN_STACKS = C.BUILTIN_STACKS
local BUILTIN_STACK_ORDER = C.BUILTIN_STACK_ORDER
local RACIAL_ABILITIES = C.RACIAL_ABILITIES

local TOOLTIP_ITEM_ICON_SIZE = 14
local TOOLTIP_QUALITY_ICON_SIZE = 14
local VIEWER_COLLECTION_HEIGHT = 448
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

local function setTooltipTitle(text, wrap)
    GameTooltip:SetText(text, 1, 1, 1, 1, wrap == true)
end

local function addTooltipLine(text, wrap)
    if text and text ~= "" then
        GameTooltip:AddLine(text, 1, 1, 1, wrap == true)
    end
end

local function addItemStackTooltipLines(entry)
    local stack = entry.stackKey and BUILTIN_STACKS[entry.stackKey]
    if not stack or stack.kind ~= "item" or not stack.ids or #stack.ids == 0 then
        return false
    end

    addTooltipLine(L["EXTRA_ICONS_STACK_TOOLTIP_INTRO"], true)

    for _, itemEntry in ipairs(stack.ids) do
        local itemId = getItemIdFromEntry(itemEntry)
        local icon = itemId and C_Item.GetItemIconByID(itemId) or nil
        local itemName = getItemDisplayName(itemId)
        local quality = type(itemEntry) == "table" and itemEntry.quality or nil
        addTooltipLine(
            buildTooltipLine(
                getTextureMarkup(icon, TOOLTIP_ITEM_ICON_SIZE),
                itemName or ("Item " .. tostring(itemId)),
                getQualityMarkup(quality)
            )
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

local function showRowTooltip(owner, rowData)
    if not rowData then
        return
    end

    local displayEntry = rowData.displayEntry
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then
        GameTooltip:ClearLines()
    end
    setTooltipTitle(getEntryTooltipTitle(displayEntry))

    if rowData.isBuiltin then
        if rowData.isPlaceholder then
            addTooltipLine(L["EXTRA_ICONS_BUILTIN_PLACEHOLDER_TOOLTIP"], true)
        end
    elseif rowData.isCurrentRacial and rowData.isPlaceholder then
        addTooltipLine(L["EXTRA_ICONS_RACIAL_PLACEHOLDER_TOOLTIP"], true)
    end

    if rowData.isBuiltin and rowData.isDisabled and not rowData.isPlaceholder then
        addTooltipLine(L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"], true)
    end

    addItemStackTooltipLines(displayEntry)
    GameTooltip:Show()
end

--- Check if a racial entry belongs to the current player character.
function ExtraIconsOptions._isRacialForCurrentPlayer(entry)
    local spellId = getEntrySpellId(entry)
    if not spellId then return true end
    local racial = getCurrentRacialEntry()
    if not racial then return true end
    for _, racialEntry in pairs(RACIAL_ABILITIES) do
        if racialEntry ~= racial and spellId == racialEntry.spellId then
            return false
        end
    end
    return true
end

--------------------------------------------------------------------------------
-- Settings Registration
--------------------------------------------------------------------------------

StaticPopupDialogs["ECM_CONFIRM_REMOVE_EXTRA_ICON"] =
    ns.OptionUtil.MakeConfirmDialog(L["REMOVE_ENTRY_CONFIRM"])

function ExtraIconsOptions.RegisterSettings(SB)
    local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("extraIcons")
    local categoryName = L["EXTRA_ICONS"]
    local category

    local function getProfile()
        return ns.Addon.db.profile
    end

    local function getViewers()
        return getProfile().extraIcons.viewers
    end

    local function refreshCategory()
        if category then
            SB.RefreshCategory(category)
        else
            SB.RefreshCategory(categoryName)
        end
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
                refreshCategory()
            end
        end)
        itemLoadFrame._ecmHooked = true
    end

    local function scheduleUpdate()
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
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

    local function addDraftEntry(viewerKey)
        local draftState = draftStates[viewerKey]
        local id = ExtraIconsOptions._parseSingleId(draftState.idText)
        if not id or not canAddDraftEntry(viewerKey) then
            return false
        end

        ExtraIconsOptions._addCustomEntry(getProfile(), viewerKey, draftState.kind, { id })
        draftState.idText = ""
        scheduleUpdate()
        refreshCategory()
        return true
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
        refreshCategory()
    end

    local function buildActionItem(rowData)
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
        local deleteText = "x"
        local deleteTooltip = L["REMOVE_TOOLTIP"]
        local deleteAction = function()
            local entryName = ExtraIconsOptions._getEntryName(displayEntry)
            StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", entryName, nil, {
                onAccept = function()
                    ExtraIconsOptions._removeEntry(getProfile(), rowData.viewerKey, rowData.index)
                    scheduleUpdate()
                    refreshCategory()
                end,
            })
        end

        if rowData.isBuiltin then
            deleteText = rowData.isDisabled and "+" or "x"
            deleteTooltip = rowData.isDisabled and L["ENABLE_TOOLTIP"] or L["EXTRA_ICONS_HIDE_TOOLTIP"]
            deleteAction = function()
                ExtraIconsOptions._toggleBuiltinRow(
                    getProfile(),
                    rowData.viewerKey,
                    rowData.index,
                    rowData.stackKey or displayEntry.stackKey
                )
                scheduleUpdate()
                refreshCategory()
            end
        elseif rowData.isCurrentRacial and rowData.isPlaceholder then
            deleteText = "+"
            deleteTooltip = L["ADD_ENTRY"]
            deleteAction = function()
                ExtraIconsOptions._toggleCurrentRacialRow(getProfile(), rowData.viewerKey, nil, rowData.spellId)
                scheduleUpdate()
                refreshCategory()
            end
        end

        return {
            label = ExtraIconsOptions._getEntryName(displayEntry),
            icon = ExtraIconsOptions._getEntryIcon(displayEntry) or 134400,
            alpha = rowData.isDisabled and 0.55 or 1,
            labelFontObject = rowData.isDisabled and (_G.GameFontDisable or _G.GameFontNormal) or _G.GameFontNormal,
            labelColor = rowData.isDisabled and { 0.65, 0.65, 0.65, 1 } or { 1, 0.82, 0, 1 },
            iconDesaturated = rowData.isDisabled == true,
            iconVertexColor = rowData.isDisabled and { 0.6, 0.6, 0.6, 1 } or nil,
            onEnter = function(owner)
                showRowTooltip(owner, rowData)
            end,
            onLeave = function()
                GameTooltip_Hide()
            end,
            actions = {
                up = {
                    text = "^",
                    width = 30,
                    enabled = canReorder and rowData.activeIndex > 1,
                    tooltip = L["MOVE_UP_TOOLTIP"],
                    onClick = function()
                        if rowData.index == nil or not canReorder then
                            return
                        end

                        ExtraIconsOptions._reorderEntry(getProfile(), rowData.viewerKey, rowData.index, -1)
                        scheduleUpdate()
                        refreshCategory()
                    end,
                },
                down = {
                    text = "v",
                    width = 30,
                    enabled = canReorder and rowData.activeIndex < rowData.activeCount,
                    tooltip = L["MOVE_DOWN_TOOLTIP"],
                    onClick = function()
                        if rowData.index == nil or not canReorder then
                            return
                        end

                        ExtraIconsOptions._reorderEntry(getProfile(), rowData.viewerKey, rowData.index, 1)
                        scheduleUpdate()
                        refreshCategory()
                    end,
                },
                move = {
                    text = rowData.viewerKey == "utility" and ">" or "<",
                    width = 30,
                    enabled = canMove,
                    tooltip = function()
                        if hasMoveDuplicate then
                            return L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(getViewerShortLabel(otherViewer))
                        end
                        if positionLocked then
                            return L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"]
                        end
                        return L["MOVE_TO_VIEWER_TOOLTIP"]:format(getViewerShortLabel(otherViewer))
                    end,
                    onClick = function()
                        if rowData.index == nil or not canMove then
                            return
                        end

                        ExtraIconsOptions._moveEntry(getProfile(), rowData.viewerKey, otherViewer, rowData.index)
                        scheduleUpdate()
                        refreshCategory()
                    end,
                },
                delete = {
                    text = deleteText,
                    width = 26,
                    enabled = not controlsDisabled,
                    tooltip = deleteTooltip,
                    onClick = deleteAction,
                },
            },
        }
    end

    local function buildModeInputTrailer(viewerKey)
        local draftState = draftStates[viewerKey]
        local function getPreviewState()
            local status, name, icon = getDraftResolution(viewerKey)
            local isDuplicate, duplicateViewerKey = getDraftDuplicateInfo(viewerKey)
            return status, name, icon, isDuplicate, duplicateViewerKey
        end

        return {
            preset = "modeInput",
            disabled = function()
                return isDisabled()
            end,
            modeText = function()
                return draftState.kind == "spell" and L["ADD_SPELL"] or L["ADD_ITEM"]
            end,
            modeTooltip = L["EXTRA_ICONS_DRAFT_TYPE_TOOLTIP"],
            inputText = function()
                return draftState.idText
            end,
            placeholder = function()
                return getDraftPlaceholderText(draftState)
            end,
            previewIcon = function()
                local _, _, icon = getPreviewState()
                return icon
            end,
            previewText = function()
                local status, name, _, isDuplicate, duplicateViewerKey = getPreviewState()
                if status == "resolved" and isDuplicate then
                    return L["EXTRA_ICONS_DUPLICATE_ENTRY"]:format(getViewerShortLabel(duplicateViewerKey))
                end
                if status == "resolved" then
                    return name or ""
                end
                if status == "pending" then
                    return DRAFT_PENDING_TEXT
                end
                return nil
            end,
            submitText = L["ADD_ENTRY"],
            submitTooltip = L["ADD_ENTRY"],
            submitEnabled = function()
                local status, _, _, isDuplicate = getPreviewState()
                return status == "resolved" and not isDuplicate
            end,
            onToggleMode = function()
                if isDisabled() then
                    return
                end

                draftState.kind = draftState.kind == "spell" and "item" or "spell"
            end,
            onTextChanged = function(text)
                draftState.idText = text or ""
            end,
            onSubmit = function()
                if isDisabled() then
                    return false
                end

                return addDraftEntry(viewerKey)
            end,
            onTabPressed = function()
                if isDisabled() then
                    return false
                end

                draftState.kind = draftState.kind == "spell" and "item" or "spell"
                return true
            end,
        }
    end

    local function buildViewerSections()
        local viewers = getViewers()
        local sections = {}

        for _, viewerKey in ipairs(VIEWER_ORDER) do
            local rows = ExtraIconsOptions._buildViewerRows(viewers, viewerKey)
            local items = {}

            for _, rowData in ipairs(rows) do
                items[#items + 1] = buildActionItem(rowData)
            end

            sections[#sections + 1] = {
                key = viewerKey,
                title = L[VIEWER_LABELS[viewerKey]],
                items = items,
                emptyText = L["EXTRA_ICONS_NO_ENTRIES"],
                trailer = buildModeInputTrailer(viewerKey),
            }
        end

        return sections
    end

    ExtraIconsOptions._viewerCanvas = nil
    ExtraIconsOptions._draftEntryCanvas = nil
    ExtraIconsOptions._addFormCanvas = nil
    ExtraIconsOptions._presetsCanvas = nil
    ExtraIconsOptions._refresh = refreshCategory

    SB.RegisterFromTable({
        name = categoryName,
        path = "extraIcons",
        onShow = function()
            ns.Runtime.SetLayoutPreview(true)
        end,
        onHide = function()
            ns.Runtime.SetLayoutPreview(false)
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
            specialRowsLegend = {
                type = "info",
                name = "",
                value = L["EXTRA_ICONS_SPECIAL_ROWS_LEGEND"],
                wide = true,
                multiline = true,
                height = 24,
                order = 10,
            },
            viewers = {
                type = "collection",
                height = VIEWER_COLLECTION_HEIGHT,
                disabled = isDisabled,
                sections = buildViewerSections,
                onDefault = restoreDefaultExtraIcons,
                order = 11,
            },
        },
    })

    category = SB.GetSubcategory(categoryName)
    ExtraIconsOptions._category = category
end

ns.SettingsBuilder.RegisterSection(ns, "ExtraIcons", ExtraIconsOptions)
