-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local Shared = ns.ExtraIconsShared

StaticPopupDialogs["ECM_CONFIRM_REMOVE_EXTRA_ICON"] =
    ns.OptionUtil.MakeConfirmDialog(L["REMOVE_ENTRY_CONFIRM"], L["REMOVE"], L["DONT_REMOVE"])

local BUILTIN_STACKS = C.BUILTIN_STACKS
local BUILTIN_STACK_ORDER = C.BUILTIN_STACK_ORDER
local RACIAL_ABILITIES = C.RACIAL_ABILITIES

local VIEWER_COLLECTION_HEIGHT = 448
local DEFAULT_SPECIAL_VIEWER = "utility"
local VIEWER_ORDER = { "utility", "main" }
local VIEWER_LABELS = {
    utility = L["UTILITY_VIEWER_ICONS"],
    main = L["MAIN_VIEWER_ICONS"],
}
local VIEWER_SHORT_LABELS = {
    utility = L["UTILITY_VIEWER_SHORT"],
    main = L["MAIN_VIEWER_SHORT"],
}

local ACTION_BUTTON_TEXTURES = ns.OptionUtil.ACTION_BUTTON_TEXTURES

local BUILTIN_STACK_SET = {}
local BUILTIN_EQUIP_SLOTS = {}
local RACIAL_SPELL_IDS = {}
local function getRacialSpellIds(racial) return racial.spellIds or { racial.spellId } end
local function getSpellId(id) return type(id) == "table" and id.spellId or id end
for _, key in ipairs(BUILTIN_STACK_ORDER) do
    BUILTIN_STACK_SET[key] = true
end
for _, stack in pairs(BUILTIN_STACKS) do
    if stack.kind == "equipSlot" and stack.slotId then
        BUILTIN_EQUIP_SLOTS[stack.slotId] = true
    end
end
for _, racial in pairs(RACIAL_ABILITIES) do
    for _, spellId in ipairs(getRacialSpellIds(racial)) do
        RACIAL_SPELL_IDS[spellId] = true
    end
end

local ExtraIconsOptions = ns.ExtraIconsOptions or {}
ns.ExtraIconsOptions = ExtraIconsOptions

ExtraIconsOptions._pendingItemLoads = ExtraIconsOptions._pendingItemLoads or {}
ExtraIconsOptions._draftStates = ExtraIconsOptions._draftStates or {}
ExtraIconsOptions._selectedItemStackIds = ExtraIconsOptions._selectedItemStackIds or {}
local draftStates = ExtraIconsOptions._draftStates

local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("extraIcons")
local registeredPage

for _, viewerKey in ipairs(VIEWER_ORDER) do
    draftStates[viewerKey] = draftStates[viewerKey] or { kind = "spell", idText = "" }
end

local function getProfile() return ns.Addon.db.profile end
local function getViewers() return getProfile().extraIcons.viewers end

local function getItemStack(stackId)
    return stackId and Shared.EnsureItemStacks(getProfile()).byId[stackId] or nil
end

local function getItemStackName(stackId)
    local itemStack = getItemStack(stackId)
    return itemStack and itemStack.name or nil
end

local function ensureSelectedItemStackId(viewerKey)
    viewerKey = viewerKey or DEFAULT_SPECIAL_VIEWER
    local itemStacks = Shared.EnsureItemStacks(getProfile())
    local selected = Shared.ResolveSelectedStackId(itemStacks, ExtraIconsOptions._selectedItemStackIds[viewerKey])
    ExtraIconsOptions._selectedItemStackIds[viewerKey] = selected
    return selected
end

local function refreshPage()
    if registeredPage then
        registeredPage:Refresh()
    end
end

local function doActionAndUpdateLayout(fn)
    if fn then
        fn()
    end
    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    refreshPage()
end

local function getSpellName(spellId)
    return spellId and C_Spell.GetSpellName(spellId) or nil
end

local function getSpellTexture(spellId)
    return spellId and C_Spell.GetSpellTexture(spellId) or nil
end

local function isDisabledBuiltinEntry(entry) return entry and entry.stackKey and entry.disabled and BUILTIN_STACK_SET[entry.stackKey] == true end

local function getEntrySpellId(entry)
    if not (entry and entry.kind == "spell" and entry.ids and entry.ids[1]) then
        return nil
    end
    return getSpellId(entry.ids[1])
end

local function entryHasSpellId(entry, spellId)
    if not (spellId and entry and entry.kind == "spell" and entry.ids) then
        return false
    end
    for _, id in ipairs(entry.ids) do
        if getSpellId(id) == spellId then return true end
    end
    return false
end

local function entryHasAnySpellId(entry, spellIds)
    if type(spellIds) ~= "table" then return entryHasSpellId(entry, spellIds) end
    for _, spellId in ipairs(spellIds) do
        if entryHasSpellId(entry, spellId) then return true end
    end
    return false
end

local function getItemProfessionQualityInfo(itemEntry)
    local itemId = Shared.GetItemIdFromEntry(itemEntry)
    if not itemId then return nil end
    return C_TradeSkillUI.GetItemCraftedQualityInfo(itemId) or C_TradeSkillUI.GetItemReagentQualityInfo(itemId)
end

local function buildEntry(kind, ids)
    local entryIds = {}
    for _, id in ipairs(ids) do
        entryIds[#entryIds + 1] = kind == "item" and { itemID = Shared.GetItemIdFromEntry(id) } or id
    end
    return { kind = kind, ids = entryIds }
end

local function getViewerEntries(viewers, viewerKey)
    local entries = viewers[viewerKey]
    if entries then
        return entries
    end
    entries = {}
    viewers[viewerKey] = entries
    return entries
end

local function appendViewerEntry(viewers, viewerKey, entry)
    local entries = getViewerEntries(viewers, viewerKey)
    entries[#entries + 1] = entry
end

local function getCurrentRacialSpellIds()
    local _, raceFile = UnitRace("player")
    local racial = raceFile and RACIAL_ABILITIES[raceFile] or nil
    return racial and getRacialSpellIds(racial) or nil
end

local function getEntryName(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then
            return entry.stackKey
        end
        if stack.kind == "equipSlot" then
            local itemId = GetInventoryItemID("player", stack.slotId)
            local itemName = itemId and Shared.GetItemDisplayName(itemId, ExtraIconsOptions._pendingItemLoads)
            if itemName then
                return ("%s [%s]"):format(stack.label, itemName)
            end
        end
        return stack.label
    end

    if entry.kind == "spell" and entry.ids then
        local spellId = getEntrySpellId(entry)
        return getSpellName(spellId) or ("Spell " .. tostring(spellId))
    end

    if entry.kind == "item" and entry.ids then
        return Shared.GetItemDisplayName(Shared.GetItemIdFromEntry(entry.ids[1]), ExtraIconsOptions._pendingItemLoads)
    end

    if entry.kind == "itemStack" then
        return getItemStackName(entry.itemStackId) or L["ITEM_STACK_MISSING"]
    end

    return "Unknown"
end

local function getEntryIcon(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then
            return nil
        end
        if stack.kind == "equipSlot" then
            return GetInventoryItemTexture("player", stack.slotId)
        end
        if stack.ids and stack.ids[1] then
            local itemId = Shared.GetItemIdFromEntry(stack.ids[1])
            return itemId and C_Item.GetItemIconByID(itemId)
        end
        return nil
    end

    if entry.kind == "spell" then
        return getSpellTexture(getEntrySpellId(entry))
    end

    if entry.kind == "item" and entry.ids then
        local itemId = Shared.GetItemIdFromEntry(entry.ids[1])
        return itemId and C_Item.GetItemIconByID(itemId)
    end

    if entry.kind == "itemStack" then
        local itemStack = getItemStack(entry.itemStackId)
        local first = itemStack and itemStack.ids and itemStack.ids[1]
        local itemId = Shared.GetItemIdFromEntry(first)
        return itemId and C_Item.GetItemIconByID(itemId)
    end

    return nil
end

local function getEntryTooltipTitle(entry)
    local name = getEntryName(entry)
    if entry.kind == "spell" then
        local id = getEntrySpellId(entry)
        if id then
            return ("%s (spell ID %s)"):format(name, id)
        end
    end
    if entry.kind == "item" and entry.ids and entry.ids[1] then
        local id = Shared.GetItemIdFromEntry(entry.ids[1])
        if id then
            return ("%s (item ID %s)"):format(name, id)
        end
    end
    if entry.kind == "itemStack" then
        return ("%s (%s)"):format(name, L["ITEM_STACK"])
    end
    return name
end

local function getEntryIdentityKey(entry)
    if not entry then
        return nil
    end
    if entry.stackKey then
        return "stack:" .. entry.stackKey
    end
    if entry.kind == "itemStack" and entry.itemStackId then
        return "itemStack:" .. tostring(entry.itemStackId)
    end
    if not (entry.kind and entry.ids and #entry.ids > 0) then
        return nil
    end

    local parts = { entry.kind }
    for _, id in ipairs(entry.ids) do
        if entry.kind == "spell" then
            parts[#parts + 1] = tostring(type(id) == "table" and id.spellId or id)
        else
            parts[#parts + 1] = tostring(Shared.GetItemIdFromEntry(id))
        end
    end
    return table.concat(parts, ":")
end

local function findViewerEntry(viewers, predicate, ignoreViewerKey, ignoreIndex)
    for viewerKey, entries in pairs(viewers) do
        for index, entry in ipairs(entries) do
            if not (viewerKey == ignoreViewerKey and index == ignoreIndex)
                and predicate(entry, viewerKey, index) then
                return viewerKey, index, entry
            end
        end
    end
    return nil, nil, nil
end

local function findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    local candidateKey = getEntryIdentityKey(candidateEntry)
    if not candidateKey then
        return nil, nil
    end

    return findViewerEntry(viewers, function(entry)
        return getEntryIdentityKey(entry) == candidateKey
    end, ignoreViewerKey, ignoreIndex)
end

local function isDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    return findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex) ~= nil
end

local function isStackKeyPresent(viewers, stackKey)
    return findDuplicateEntry(viewers, { stackKey = stackKey }) ~= nil
end

local function isRacialPresent(viewers, spellIds)
    return findViewerEntry(viewers, function(entry)
        return entryHasAnySpellId(entry, spellIds)
    end) ~= nil
end

local function isCurrentRacialEntry(entry)
    return entryHasAnySpellId(entry, getCurrentRacialSpellIds())
end

local function isRacialForCurrentPlayer(entry)
    if not (entry and entry.kind == "spell" and entry.ids) then
        return true
    end

    local hasRacialSpell = false
    for _, id in ipairs(entry.ids) do
        local spellId = getSpellId(id)
        if RACIAL_SPELL_IDS[spellId] then
            hasRacialSpell = true
            break
        end
    end

    local currentSpellIds = getCurrentRacialSpellIds()
    return not currentSpellIds or entryHasAnySpellId(entry, currentSpellIds) or not hasRacialSpell
end

local function showRowTooltip(owner, rowData)
    if not rowData then
        return
    end

    local displayEntry = rowData.displayEntry
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearAllPoints()
    GameTooltip:SetPoint("BOTTOMLEFT", owner, "TOPRIGHT", 0, 0)
    GameTooltip:ClearLines()
    GameTooltip:SetText(getEntryTooltipTitle(displayEntry), 1, 1, 1, 1, false)

    local function tip(text)
        if text and text ~= "" then
            GameTooltip:AddLine(text, 1, 1, 1, true)
        end
    end

    if rowData.isBuiltin and rowData.isPlaceholder then
        tip(L["EXTRA_ICONS_BUILTIN_PLACEHOLDER_TOOLTIP"])
    elseif rowData.isCurrentRacial and rowData.isPlaceholder then
        tip(L["EXTRA_ICONS_RACIAL_PLACEHOLDER_TOOLTIP"])
    end
    if rowData.isBuiltin and rowData.isDisabled and not rowData.isPlaceholder then
        tip(L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"])
    end

    local stack = displayEntry.stackKey and BUILTIN_STACKS[displayEntry.stackKey]
    local itemStack = displayEntry.kind == "itemStack" and getItemStack(displayEntry.itemStackId) or nil
    local ids = stack and stack.kind == "item" and stack.ids or itemStack and itemStack.ids
    if ids and #ids > 0 then
        tip(L["EXTRA_ICONS_STACK_TOOLTIP_INTRO"])
        for _, itemEntry in ipairs(ids) do
            local itemId = Shared.GetItemIdFromEntry(itemEntry)
            local parts = {}
            local icon = itemId and C_Item.GetItemIconByID(itemId)
            if icon then
                parts[#parts + 1] = CreateTextureMarkup(icon, 64, 64, 14, 14, 0, 1, 0, 1)
            end
            parts[#parts + 1] = Shared.GetItemDisplayName(itemId, ExtraIconsOptions._pendingItemLoads)
                or ("Item " .. tostring(itemId))
            local qualityMarkup = ExtraIconsOptions.GetItemQualityMarkup(itemEntry)
            if qualityMarkup then
                parts[#parts + 1] = qualityMarkup
            end
            tip(table.concat(parts, " "))
        end
    end

    GameTooltip:Show()
end

local function shouldShowBuiltinStackRow(stackKey)
    local stack = stackKey and BUILTIN_STACKS[stackKey]
    if not stack or stack.kind ~= "equipSlot" then
        return true
    end
    local itemId = GetInventoryItemID("player", stack.slotId)
    if not itemId then
        return false
    end
    local _, spellId = C_Item.GetItemSpell(itemId)
    return spellId ~= nil
end

local function shouldShowEntryRow(entry)
    return isRacialForCurrentPlayer(entry) and (not entry.stackKey or shouldShowBuiltinStackRow(entry.stackKey))
end

local function addStackKey(profile, viewerKey, stackKey)
    local viewers = profile.extraIcons.viewers
    if not isStackKeyPresent(viewers, stackKey) then appendViewerEntry(viewers, viewerKey, { stackKey = stackKey }) end
end

local function addRacial(profile, viewerKey, spellIds)
    local viewers = profile.extraIcons.viewers
    if not isRacialPresent(viewers, spellIds) then
        appendViewerEntry(viewers, viewerKey, buildEntry("spell", type(spellIds) == "table" and spellIds or { spellIds }))
    end
end

local function addCustomEntry(profile, viewerKey, kind, ids)
    local viewers = profile.extraIcons.viewers
    local entry = buildEntry(kind, ids)
    if not isDuplicateEntry(viewers, entry) then appendViewerEntry(viewers, viewerKey, entry) end
end

local function addItemStackEntry(profile, viewerKey, itemStackId)
    local viewers = profile.extraIcons.viewers
    local entry = { kind = "itemStack", itemStackId = itemStackId }
    if not isDuplicateEntry(viewers, entry) then appendViewerEntry(viewers, viewerKey, entry) end
end

local function removeEntry(profile, viewerKey, index)
    local entries = profile.extraIcons.viewers[viewerKey]
    if entries and index >= 1 and index <= #entries then table.remove(entries, index) end
end

local function toggleBuiltinRow(profile, viewerKey, index, stackKey)
    if not index then
        addStackKey(profile, viewerKey, stackKey)
        return
    end

    local entry = (profile.extraIcons.viewers[viewerKey] or {})[index]
    if entry then entry.disabled = not entry.disabled and true or nil end
end

local function toggleCurrentRacialRow(profile, viewerKey, index, spellIds)
    if index then
        removeEntry(profile, viewerKey, index)
        return
    end
    if spellIds then
        addRacial(profile, viewerKey, spellIds)
    end
end

local function reorderEntry(profile, viewerKey, index, direction)
    local entries = profile.extraIcons.viewers[viewerKey]
    if not entries then
        return
    end

    local visibleIndices, activeIndex = {}, nil
    for i, entry in ipairs(entries) do
        if not isDisabledBuiltinEntry(entry) and shouldShowEntryRow(entry) then
            visibleIndices[#visibleIndices + 1] = i
            if i == index then
                activeIndex = #visibleIndices
            end
        end
    end

    if not activeIndex then
        return
    end

    local target = visibleIndices[activeIndex + direction]
    if target then
        entries[index], entries[target] = entries[target], entries[index]
    end
end

local function moveEntry(profile, fromViewer, toViewer, index)
    local viewers = profile.extraIcons.viewers
    local from = viewers[fromViewer]
    if not from or index < 1 or index > #from then
        return
    end
    if findDuplicateEntry(viewers, from[index], fromViewer, index) == toViewer then
        return
    end

    local entry = table.remove(from, index)
    appendViewerEntry(viewers, toViewer, entry)
end

local function resolveDraftEntryPreview(kind, text, viewerKey)
    if kind == "itemStack" then
        local itemStackId = ensureSelectedItemStackId(viewerKey)
        local itemStack = itemStackId and getItemStack(itemStackId)
        if not itemStack then
            return "invalid", nil, nil
        end
        local first = itemStack.ids and itemStack.ids[1]
        local itemId = Shared.GetItemIdFromEntry(first)
        return "resolved", itemStack.name, itemId and C_Item.GetItemIconByID(itemId) or nil
    end

    local id = Shared.ParseSingleId(text)
    if not id then
        return "invalid", nil, nil
    end

    if kind == "spell" then
        local name = getSpellName(id)
        return name and "resolved" or "invalid", name, name and getSpellTexture(id) or nil
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

        Shared.RequestItemLoad(ExtraIconsOptions._pendingItemLoads, id)
        return "pending", nil, icon
    end

    return "invalid", nil, nil
end

local function makeRowData(rowType, viewerKey, displayEntry, index)
    local isPlaceholder = rowType ~= "entry"
    return {
        rowType = rowType,
        viewerKey = viewerKey,
        index = index,
        stackKey = displayEntry.stackKey,
        spellId = getEntrySpellId(displayEntry),
        spellIds = displayEntry.kind == "spell" and displayEntry.ids or nil,
        displayEntry = displayEntry,
        isBuiltin = displayEntry.stackKey ~= nil,
        isCurrentRacial = rowType == "racialPlaceholder" or isCurrentRacialEntry(displayEntry),
        isPlaceholder = isPlaceholder,
        isDisabled = isPlaceholder or displayEntry.disabled == true,
    }
end

local function buildViewerRows(viewers, viewerKey)
    local activeRows, disabledBuiltinRows = {}, {}
    for index, entry in ipairs(viewers[viewerKey] or {}) do
        if shouldShowEntryRow(entry) then
            local rowData = makeRowData("entry", viewerKey, entry, index)
            if isDisabledBuiltinEntry(entry) then
                local bucket = disabledBuiltinRows[entry.stackKey] or {}
                disabledBuiltinRows[entry.stackKey] = bucket
                bucket[#bucket + 1] = rowData
            else
                activeRows[#activeRows + 1] = rowData
            end
        end
    end

    for i, rowData in ipairs(activeRows) do
        rowData.activeIndex = i
        rowData.activeCount = #activeRows
    end

    local rows = activeRows
    for _, stackKey in ipairs(BUILTIN_STACK_ORDER) do
        local bucket = disabledBuiltinRows[stackKey]
        if bucket then
            for _, rowData in ipairs(bucket) do
                rows[#rows + 1] = rowData
            end
        elseif viewerKey == DEFAULT_SPECIAL_VIEWER
            and shouldShowBuiltinStackRow(stackKey)
            and not isStackKeyPresent(viewers, stackKey) then
            rows[#rows + 1] = makeRowData("builtinPlaceholder", viewerKey, { stackKey = stackKey })
        end
    end

    if viewerKey == DEFAULT_SPECIAL_VIEWER then
        local racialSpellIds = getCurrentRacialSpellIds()
        if racialSpellIds and not isRacialPresent(viewers, racialSpellIds) then
            rows[#rows + 1] = makeRowData("racialPlaceholder", viewerKey, buildEntry("spell", racialSpellIds))
        end
    end

    return rows
end

local function getDraftDuplicateInfo(viewerKey)
    local ds = draftStates[viewerKey]
    if ds.kind == "itemStack" then
        local selected = ensureSelectedItemStackId(viewerKey)
        if not selected then
            return false, nil
        end
        local dupViewer = findDuplicateEntry(getViewers(), { kind = "itemStack", itemStackId = selected })
        return dupViewer ~= nil, dupViewer
    end

    local id = Shared.ParseSingleId(ds.idText)
    if not id then
        return false, nil
    end
    local dupViewer = findDuplicateEntry(getViewers(), buildEntry(ds.kind, { id }))
    return dupViewer ~= nil, dupViewer
end

local function addDraftEntry(viewerKey)
    local ds = draftStates[viewerKey]
    if ds.kind == "itemStack" then
        local itemStackId = ensureSelectedItemStackId(viewerKey)
        local isDuplicate = getDraftDuplicateInfo(viewerKey)
        if not itemStackId or isDuplicate then
            return false
        end
        addItemStackEntry(getProfile(), viewerKey, itemStackId)
        doActionAndUpdateLayout()
        return true
    end

    local status = resolveDraftEntryPreview(ds.kind, ds.idText, viewerKey)
    local isDuplicate = getDraftDuplicateInfo(viewerKey)
    if status ~= "resolved" or isDuplicate then
        return false
    end

    local id = Shared.ParseSingleId(ds.idText)
    addCustomEntry(getProfile(), viewerKey, ds.kind, { id })
    ds.idText = ""
    doActionAndUpdateLayout()
    return true
end

local function makeAction(text, buttonTextures, enabled, tooltip, onClick)
    return ns.OptionUtil.CreateIconAction(text, buttonTextures, enabled, tooltip, onClick)
end

local function profileAction(fn)
    return function()
        doActionAndUpdateLayout(function()
            fn(getProfile())
        end)
    end
end

local function getDeleteAction(rowData, displayEntry, controlsDisabled)
    if rowData.isBuiltin then
        return makeAction(
            rowData.isDisabled and "+" or "x",
            rowData.isDisabled and ACTION_BUTTON_TEXTURES.show or ACTION_BUTTON_TEXTURES.delete,
            not controlsDisabled,
            rowData.isDisabled and L["ENABLE_TOOLTIP"] or L["EXTRA_ICONS_HIDE_TOOLTIP"],
            profileAction(function(profile)
                toggleBuiltinRow(
                    profile,
                    rowData.viewerKey,
                    rowData.index,
                    rowData.stackKey or displayEntry.stackKey
                )
            end)
        )
    end

    if rowData.isCurrentRacial and rowData.isPlaceholder then
        return makeAction("+", ACTION_BUTTON_TEXTURES.show, not controlsDisabled, L["ADD_ENTRY"], profileAction(function(profile)
            toggleCurrentRacialRow(profile, rowData.viewerKey, nil, rowData.spellIds)
        end))
    end

    if rowData.isCurrentRacial then
        return makeAction("x", ACTION_BUTTON_TEXTURES.delete, not controlsDisabled, L["REMOVE_TOOLTIP"],
            profileAction(function(profile)
                toggleCurrentRacialRow(profile, rowData.viewerKey, rowData.index)
            end))
    end

    return makeAction("x", ACTION_BUTTON_TEXTURES.delete, not controlsDisabled, L["REMOVE_TOOLTIP"], function()
        StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", getEntryName(displayEntry), nil, {
            onAccept = profileAction(function(profile)
                removeEntry(profile, rowData.viewerKey, rowData.index)
            end),
        })
    end)
end

local function makeReorderAction(rowData, text, buttonTextures, enabled, direction)
    return makeAction(text, buttonTextures, enabled, direction < 0 and L["MOVE_UP_TOOLTIP"] or L["MOVE_DOWN_TOOLTIP"],
        profileAction(function(profile)
            reorderEntry(profile, rowData.viewerKey, rowData.index, direction)
        end))
end

local function getMoveTooltip(hasMoveDup, posLocked, otherViewer)
    if hasMoveDup then
        return L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(VIEWER_SHORT_LABELS[otherViewer])
    end
    if posLocked then
        return L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"]
    end
    return L["MOVE_TO_VIEWER_TOOLTIP"]
end

local function buildActionItem(rowData)
    local controlsDisabled = isDisabled()
    local displayEntry = rowData.displayEntry
    local otherViewer = rowData.viewerKey == "utility" and "main" or "utility"
    local dupViewer = rowData.index ~= nil
        and findDuplicateEntry(getViewers(), displayEntry, rowData.viewerKey, rowData.index) or nil
    local hasMoveDup = dupViewer == otherViewer
    local posLocked = rowData.isBuiltin and rowData.isDisabled
    local canReorder = not controlsDisabled and rowData.activeIndex ~= nil and not posLocked
    local canMove = not controlsDisabled and rowData.index ~= nil and not posLocked and not hasMoveDup
    local moveTextures = rowData.viewerKey == "utility" and ACTION_BUTTON_TEXTURES.moveRight or ACTION_BUTTON_TEXTURES.moveLeft

    return {
        label = getEntryName(displayEntry),
        icon = getEntryIcon(displayEntry) or 134400,
        disabled = rowData.isDisabled,
        onEnter = function(owner)
            showRowTooltip(owner, rowData)
        end,
        onLeave = function()
            GameTooltip_Hide()
        end,
        actions = {
            up = makeReorderAction(rowData, "^", ACTION_BUTTON_TEXTURES.moveUp, canReorder and rowData.activeIndex > 1, -1),
            down = makeReorderAction(rowData, "v", ACTION_BUTTON_TEXTURES.moveDown,
                canReorder and rowData.activeIndex < rowData.activeCount, 1),
            move = makeAction(
                rowData.viewerKey == "utility" and ">" or "<",
                moveTextures,
                canMove,
                function()
                    return getMoveTooltip(hasMoveDup, posLocked, otherViewer)
                end,
                profileAction(function(profile)
                    moveEntry(profile, rowData.viewerKey, otherViewer, rowData.index)
                end)
            ),
            delete = getDeleteAction(rowData, displayEntry, controlsDisabled),
        },
    }
end

local function buildModeInputTrailer(viewerKey)
    local ds = draftStates[viewerKey]

    local function getPreviewState()
        local status, name, icon = resolveDraftEntryPreview(ds.kind, ds.idText, viewerKey)
        local isDup, dupViewer = getDraftDuplicateInfo(viewerKey)
        return status, name, icon, isDup, dupViewer
    end

    local function toggleKind()
        if isDisabled() then return false end
        if ds.kind == "spell" then
            ds.kind = "item"
        elseif ds.kind == "item" then
            ds.kind = "itemStack"
            ensureSelectedItemStackId(viewerKey)
        else
            ds.kind = "spell"
        end
        return true
    end

    return {
        type = "modeInput",
        disabled = isDisabled,
        modeText = function()
            if ds.kind == "spell" then return L["ADD_SPELL"] end
            if ds.kind == "item" then return L["ADD_ITEM"] end
            return L["ITEM_STACK"]
        end,
        modeTooltip = L["EXTRA_ICONS_DRAFT_TYPE_TOOLTIP"],
        inputType = function() return ds.kind == "itemStack" and "dropdown" or "text" end,
        inputEnabled = function() return ds.kind ~= "itemStack" or ensureSelectedItemStackId(viewerKey) ~= nil end,
        inputValues = function() return Shared.BuildItemStackValues(Shared.EnsureItemStacks(getProfile())) end,
        inputValue = function()
            local stackId = ensureSelectedItemStackId(viewerKey)
            return stackId and tostring(stackId) or ""
        end,
        onInputValueChanged = function(value)
            ExtraIconsOptions._selectedItemStackIds[viewerKey] = tonumber(value) or value
        end,
        inputText = function()
            return ds.kind == "itemStack" and (getItemStackName(ensureSelectedItemStackId(viewerKey)) or "") or ds.idText
        end,
        placeholder = function()
            if ds.kind == "spell" then return L["EXTRA_ICONS_SPELL_ID_PLACEHOLDER"] end
            if ds.kind == "item" then return L["EXTRA_ICONS_ITEM_ID_PLACEHOLDER"] end
            return L["ITEM_STACK_SELECT_PLACEHOLDER"]
        end,
        previewIcon = function() local _, _, icon = getPreviewState(); return icon end,
        previewText = function()
            local status, name, _, isDup, dupViewer = getPreviewState()
            if status == "resolved" and isDup then
                return L["EXTRA_ICONS_DUPLICATE_ENTRY"]:format(VIEWER_SHORT_LABELS[dupViewer])
            end
            if status == "resolved" then
                return name or ""
            end
            if status == "pending" then
                return "..."
            end
            return nil
        end,
        submitText = L["ADD_ENTRY"],
        submitTooltip = L["ADD_ENTRY"],
        submitEnabled = function()
            local status, _, _, isDup = getPreviewState()
            return status == "resolved" and not isDup
        end,
        onToggleMode = toggleKind,
        onTextChanged = function(text) if ds.kind ~= "itemStack" then ds.idText = text or "" end end,
        onSubmit = function() return not isDisabled() and addDraftEntry(viewerKey) or false end,
        onTabPressed = toggleKind,
    }
end

local function canResetToDefaults()
    local defaults = ns.Addon.db.defaults.profile
    return defaults and defaults.extraIcons ~= nil
end

function ExtraIconsOptions.BuildSections()
    local viewers = getViewers()
    local sections = {}
    for _, viewerKey in ipairs(VIEWER_ORDER) do
        local items = {}
        for _, rowData in ipairs(buildViewerRows(viewers, viewerKey)) do
            items[#items + 1] = buildActionItem(rowData)
        end
        sections[#sections + 1] = {
            key = viewerKey,
            title = VIEWER_LABELS[viewerKey],
            items = items,
            emptyText = L["EXTRA_ICONS_NO_ENTRIES"],
            footer = buildModeInputTrailer(viewerKey),
        }
    end
    return sections
end

function ExtraIconsOptions.ResetToDefaults()
    local defaults = ns.Addon.db.defaults.profile
    if not (defaults and defaults.extraIcons) then
        return
    end

    ns.Addon.db.profile.extraIcons = ns.CloneValue(defaults.extraIcons)
    for _, viewerKey in ipairs(VIEWER_ORDER) do
        draftStates[viewerKey].kind = "spell"
        draftStates[viewerKey].idText = ""
    end
    ExtraIconsOptions._selectedItemStackIds = {}
    doActionAndUpdateLayout()
end

function ExtraIconsOptions.GetItemQualityMarkup(itemEntry)
    local qualityInfo = getItemProfessionQualityInfo(itemEntry)
    local iconChat = type(qualityInfo) == "table" and qualityInfo.iconChat or type(itemEntry) == "table" and itemEntry.iconChat
    if iconChat then return CreateAtlasMarkup(iconChat, 14, 14) end
    local quality = type(qualityInfo) == "table" and qualityInfo.quality or type(itemEntry) == "table" and itemEntry.quality
    return quality and CreateAtlasMarkup("Professions-ChatIcon-Quality-12-Tier" .. quality, 14, 14) or nil
end

function ExtraIconsOptions.OnInitialize()
    registeredPage = ns.Settings:GetPage("extraIcons", "main")
    ExtraIconsOptions.EnsureItemLoadFrame()
end

function ExtraIconsOptions.EnsureItemLoadFrame()
    Shared.EnsureItemLoadFrame(ExtraIconsOptions, { "GET_ITEM_INFO_RECEIVED", "PLAYER_EQUIPMENT_CHANGED" }, function(_, event, arg1)
        if event == "GET_ITEM_INFO_RECEIVED" and arg1 and ExtraIconsOptions._pendingItemLoads[arg1] then
            ExtraIconsOptions._pendingItemLoads[arg1] = nil
            refreshPage()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" and BUILTIN_EQUIP_SLOTS[arg1] then
            refreshPage()
        end
    end)
end

ExtraIconsOptions.key = "extraIcons"
ExtraIconsOptions.name = L["EXTRA_ICONS"]

ExtraIconsOptions.pages = {
    {
        key = "main",
        onDefault = ExtraIconsOptions.ResetToDefaults,
        onDefaultEnabled = canResetToDefaults,
        onShow = function()
            ns.Runtime.SetLayoutPreview(true)
            ExtraIconsOptions.EnsureItemLoadFrame()
        end,
        onHide = function()
            ns.Runtime.SetLayoutPreview(false)
        end,
        rows = {
            {
                id = "enabled",
                type = "checkbox",
                path = "enabled",
                name = L["ENABLE_EXTRA_ICONS"],
                tooltip = L["ENABLE_EXTRA_ICONS_DESC"],
                onSet = function(ctx, value)
                    ns.OptionUtil.CreateModuleEnabledHandler("ExtraIcons")(ctx, value)
                    ctx.page:Refresh()
                end,
            },
            {
                id = "showStackCount",
                type = "checkbox",
                path = "showStackCount",
                name = L["SHOW_STACK_COUNT"],
                tooltip = L["SHOW_STACK_COUNT_DESC"],
                disabled = isDisabled,
                onSet = function(ctx)
                    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                    ctx.page:Refresh()
                end,
            },
            {
                id = "showCharges",
                type = "checkbox",
                path = "showCharges",
                name = L["SHOW_CHARGES"],
                tooltip = L["SHOW_CHARGES_DESC"],
                disabled = isDisabled,
                onSet = function(ctx)
                    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                    ctx.page:Refresh()
                end,
            },
            {
                id = "viewers",
                type = "sectionList",
                height = VIEWER_COLLECTION_HEIGHT,
                footerSpacing = 4,
                disabled = isDisabled,
                sections = ExtraIconsOptions.BuildSections,
            },
        },
    },
}
