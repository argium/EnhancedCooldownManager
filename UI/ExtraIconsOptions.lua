-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

StaticPopupDialogs["ECM_CONFIRM_REMOVE_EXTRA_ICON"] =
    ns.OptionUtil.MakeConfirmDialog(L["REMOVE_ENTRY_CONFIRM"])

local BUILTIN_STACKS = C.BUILTIN_STACKS
local BUILTIN_STACK_ORDER = C.BUILTIN_STACK_ORDER
local RACIAL_ABILITIES = C.RACIAL_ABILITIES

local VIEWER_COLLECTION_HEIGHT = 448
local ACTION_ICON_BUTTON_SIZE = 20
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

local ACTION_BUTTON_TEXTURES = {
    delete = {
        normal = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        pushed = "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
        disabled = "Interface\\Buttons\\UI-GroupLoot-Pass-Disabled",
    },
    hide = {
        normal = "Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
        pushed = "Interface\\Buttons\\UI-Panel-MinimizeButton-Down",
        disabled = "Interface\\Buttons\\UI-Panel-MinimizeButton-Disabled",
    },
    moveDown = {
        normal = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up",
        pushed = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down",
        disabled = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Disabled",
    },
    moveLeft = {
        normal = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
        pushed = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
    },
    moveRight = {
        normal = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
        pushed = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
        disabled = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
    },
    moveUp = {
        normal = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up",
        pushed = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down",
        disabled = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled",
    },
    show = {
        normal = "Interface\\Buttons\\UI-PlusButton-Up",
        pushed = "Interface\\Buttons\\UI-PlusButton-Down",
        disabled = "Interface\\Buttons\\UI-PlusButton-Disabled",
    },
}

local BUILTIN_STACK_SET = {}
local BUILTIN_EQUIP_SLOTS = {}
local RACIAL_SPELL_IDS = {}
for _, key in ipairs(BUILTIN_STACK_ORDER) do
    BUILTIN_STACK_SET[key] = true
end
for _, stack in pairs(BUILTIN_STACKS) do
    if stack.kind == "equipSlot" and stack.slotId then
        BUILTIN_EQUIP_SLOTS[stack.slotId] = true
    end
end
for _, racial in pairs(RACIAL_ABILITIES) do
    RACIAL_SPELL_IDS[racial.spellId] = true
end

local ExtraIconsOptions = ns.ExtraIconsOptions or {}
ns.ExtraIconsOptions = ExtraIconsOptions

ExtraIconsOptions._pendingItemLoads = ExtraIconsOptions._pendingItemLoads or {}
ExtraIconsOptions._draftStates = ExtraIconsOptions._draftStates or {}
local draftStates = ExtraIconsOptions._draftStates

local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("extraIcons")
local registeredPage

for _, viewerKey in ipairs(VIEWER_ORDER) do
    draftStates[viewerKey] = draftStates[viewerKey] or { kind = "spell", idText = "" }
end

local function getProfile() return ns.Addon.db.profile end
local function getViewers() return getProfile().extraIcons.viewers end

local function refreshPage()
    if registeredPage then
        registeredPage:Refresh()
    end
end

local function doAction(fn)
    if fn then
        fn()
    end
    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    refreshPage()
end

local function getSpellName(spellId)
    local api = type(C_Spell) == "table" and C_Spell or nil
    return spellId and api and api.GetSpellName and api.GetSpellName(spellId) or nil
end

local function getSpellTexture(spellId)
    local api = type(C_Spell) == "table" and C_Spell or nil
    return spellId and api and api.GetSpellTexture and api.GetSpellTexture(spellId) or nil
end

local function isDisabledBuiltinEntry(entry) return entry and entry.stackKey and entry.disabled and BUILTIN_STACK_SET[entry.stackKey] == true end

local function getEntrySpellId(entry)
    if not (entry and entry.kind == "spell" and entry.ids and entry.ids[1]) then
        return nil
    end
    local first = entry.ids[1]
    return type(first) == "table" and first.spellId or first
end

local function getItemIdFromEntry(entry) return type(entry) == "table" and (entry.itemID or entry.itemId) or entry end

local function buildEntry(kind, ids)
    local entryIds = {}
    for _, id in ipairs(ids) do
        entryIds[#entryIds + 1] = kind == "item" and { itemID = getItemIdFromEntry(id) } or id
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

local function getCurrentRacialSpellId()
    local _, raceFile = UnitRace("player")
    local racial = raceFile and RACIAL_ABILITIES[raceFile] or nil
    return racial and racial.spellId or nil
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
        ExtraIconsOptions._pendingItemLoads[itemId] = true
        C_Item.RequestLoadItemDataByID(itemId)
        return L["EXTRA_ICONS_ITEM_LOADING"]
    end

    return "Item " .. tostring(itemId)
end

local function getEntryTooltipTitle(entry)
    local name = ExtraIconsOptions._getEntryName(entry)
    if entry.kind == "spell" then
        local id = getEntrySpellId(entry)
        if id then
            return ("%s (spell ID %s)"):format(name, id)
        end
    end
    if entry.kind == "item" and entry.ids and entry.ids[1] then
        local id = getItemIdFromEntry(entry.ids[1])
        if id then
            return ("%s (item ID %s)"):format(name, id)
        end
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
    if not (entry.kind and entry.ids and #entry.ids > 0) then
        return nil
    end

    local parts = { entry.kind }
    for _, id in ipairs(entry.ids) do
        if entry.kind == "spell" then
            parts[#parts + 1] = tostring(type(id) == "table" and id.spellId or id)
        else
            parts[#parts + 1] = tostring(getItemIdFromEntry(id))
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

local function showRowTooltip(owner, rowData)
    if not rowData then
        return
    end

    local displayEntry = rowData.displayEntry
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    if GameTooltip.ClearLines then
        GameTooltip:ClearLines()
    end
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
    if stack and stack.kind == "item" and stack.ids and #stack.ids > 0 then
        tip(L["EXTRA_ICONS_STACK_TOOLTIP_INTRO"])
        for _, itemEntry in ipairs(stack.ids) do
            local itemId = getItemIdFromEntry(itemEntry)
            local parts = {}
            local icon = itemId and C_Item.GetItemIconByID(itemId)
            if icon then
                parts[#parts + 1] = CreateTextureMarkup(icon, 64, 64, 14, 14, 0, 1, 0, 1)
            end
            parts[#parts + 1] = getItemDisplayName(itemId) or ("Item " .. tostring(itemId))
            local quality = type(itemEntry) == "table" and itemEntry.quality
            if quality then
                parts[#parts + 1] = CreateAtlasMarkup("Professions-Icon-Quality-Tier" .. quality .. "-Small", 14, 14)
            end
            tip(table.concat(parts, " "))
        end
    end

    GameTooltip:Show()
end

function ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) return ExtraIconsOptions._findDuplicateEntry(viewers, { stackKey = stackKey }) ~= nil end

function ExtraIconsOptions._shouldShowBuiltinStackRow(stackKey)
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

function ExtraIconsOptions._isRacialPresent(viewers, spellId) return ExtraIconsOptions._findDuplicateEntry(viewers, buildEntry("spell", { spellId })) ~= nil end

function ExtraIconsOptions._isCurrentRacialEntry(entry) return getEntrySpellId(entry) == getCurrentRacialSpellId() end

function ExtraIconsOptions._isRacialForCurrentPlayer(entry)
    local spellId = getEntrySpellId(entry)
    if not spellId then
        return true
    end

    local currentSpellId = getCurrentRacialSpellId()
    return not currentSpellId or spellId == currentSpellId or not RACIAL_SPELL_IDS[spellId]
end

local function shouldShowEntryRow(entry) return ExtraIconsOptions._isRacialForCurrentPlayer(entry) and (not entry.stackKey or ExtraIconsOptions._shouldShowBuiltinStackRow(entry.stackKey)) end

function ExtraIconsOptions._getEntryName(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then
            return entry.stackKey
        end
        if stack.kind == "equipSlot" then
            local itemId = GetInventoryItemID("player", stack.slotId)
            local itemName = itemId and getItemDisplayName(itemId)
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
        return getItemDisplayName(getItemIdFromEntry(entry.ids[1]))
    end

    return "Unknown"
end

function ExtraIconsOptions._getEntryIcon(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then
            return nil
        end
        if stack.kind == "equipSlot" then
            return GetInventoryItemTexture("player", stack.slotId)
        end
        if stack.ids and stack.ids[1] then
            local itemId = getItemIdFromEntry(stack.ids[1])
            return itemId and C_Item.GetItemIconByID(itemId)
        end
        return nil
    end

    if entry.kind == "spell" then
        return getSpellTexture(getEntrySpellId(entry))
    end

    if entry.kind == "item" and entry.ids then
        local itemId = getItemIdFromEntry(entry.ids[1])
        return itemId and C_Item.GetItemIconByID(itemId)
    end

    return nil
end

function ExtraIconsOptions._addStackKey(profile, viewerKey, stackKey)
    local viewers = profile.extraIcons.viewers
    if not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then appendViewerEntry(viewers, viewerKey, { stackKey = stackKey }) end
end

function ExtraIconsOptions._addRacial(profile, viewerKey, spellId)
    local viewers = profile.extraIcons.viewers
    if not ExtraIconsOptions._isRacialPresent(viewers, spellId) then appendViewerEntry(viewers, viewerKey, buildEntry("spell", { spellId })) end
end

function ExtraIconsOptions._addCustomEntry(profile, viewerKey, kind, ids)
    local viewers = profile.extraIcons.viewers
    local entry = buildEntry(kind, ids)
    if not ExtraIconsOptions._isDuplicateEntry(viewers, entry) then appendViewerEntry(viewers, viewerKey, entry) end
end

function ExtraIconsOptions._removeEntry(profile, viewerKey, index)
    local entries = profile.extraIcons.viewers[viewerKey]
    if entries and index >= 1 and index <= #entries then table.remove(entries, index) end
end

function ExtraIconsOptions._setEntryDisabled(profile, viewerKey, index, disabled)
    local entries = profile.extraIcons.viewers[viewerKey]
    local entry = entries and entries[index]
    if entry then entry.disabled = disabled and true or nil end
end

function ExtraIconsOptions._toggleBuiltinRow(profile, viewerKey, index, stackKey)
    if not index then
        ExtraIconsOptions._addStackKey(profile, viewerKey, stackKey)
        return
    end

    local entry = (profile.extraIcons.viewers[viewerKey] or {})[index]
    if entry then entry.disabled = not entry.disabled and true or nil end
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

function ExtraIconsOptions._reorderEntry(profile, viewerKey, index, direction)
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

function ExtraIconsOptions._moveEntry(profile, fromViewer, toViewer, index)
    local viewers = profile.extraIcons.viewers
    local from = viewers[fromViewer]
    if not from or index < 1 or index > #from then
        return
    end
    if ExtraIconsOptions._findDuplicateEntry(viewers, from[index], fromViewer, index) == toViewer then
        return
    end

    local entry = table.remove(from, index)
    appendViewerEntry(viewers, toViewer, entry)
end

function ExtraIconsOptions._otherViewer(viewerKey) return viewerKey == "utility" and "main" or "utility" end

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

function ExtraIconsOptions._resolveDraftEntryPreview(kind, text)
    local id = ExtraIconsOptions._parseSingleId(text)
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

        ExtraIconsOptions._pendingItemLoads[id] = true
        C_Item.RequestLoadItemDataByID(id)
        return "pending", nil, icon
    end

    return "invalid", nil, nil
end

function ExtraIconsOptions._findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    local candidateKey = getEntryIdentityKey(candidateEntry)
    if not candidateKey then
        return nil, nil
    end

    return findViewerEntry(viewers, function(entry)
        return getEntryIdentityKey(entry) == candidateKey
    end, ignoreViewerKey, ignoreIndex)
end

function ExtraIconsOptions._isDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex) return ExtraIconsOptions._findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex) ~= nil end

local function makeRowData(rowType, viewerKey, displayEntry, index)
    local isPlaceholder = rowType ~= "entry"
    return {
        rowType = rowType,
        viewerKey = viewerKey,
        index = index,
        stackKey = displayEntry.stackKey,
        spellId = getEntrySpellId(displayEntry),
        displayEntry = displayEntry,
        isBuiltin = displayEntry.stackKey ~= nil,
        isCurrentRacial = rowType == "racialPlaceholder" or ExtraIconsOptions._isCurrentRacialEntry(displayEntry),
        isPlaceholder = isPlaceholder,
        isDisabled = isPlaceholder or displayEntry.disabled == true,
    }
end

function ExtraIconsOptions._buildViewerRows(viewers, viewerKey)
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
            and ExtraIconsOptions._shouldShowBuiltinStackRow(stackKey)
            and not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
            rows[#rows + 1] = makeRowData("builtinPlaceholder", viewerKey, { stackKey = stackKey })
        end
    end

    if viewerKey == DEFAULT_SPECIAL_VIEWER then
        local racialSpellId = getCurrentRacialSpellId()
        if racialSpellId and not ExtraIconsOptions._isRacialPresent(viewers, racialSpellId) then
            rows[#rows + 1] = makeRowData("racialPlaceholder", viewerKey, buildEntry("spell", { racialSpellId }))
        end
    end

    return rows
end

function ExtraIconsOptions.SetRegisteredPage(page) registeredPage = page end

function ExtraIconsOptions.EnsureItemLoadFrame()
    local itemLoadFrame = ExtraIconsOptions._itemLoadFrame
    if not itemLoadFrame then
        itemLoadFrame = CreateFrame("Frame")
        ExtraIconsOptions._itemLoadFrame = itemLoadFrame
    end
    if itemLoadFrame._ecmHooked then
        return
    end

    itemLoadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemLoadFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    itemLoadFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "GET_ITEM_INFO_RECEIVED" and arg1 and ExtraIconsOptions._pendingItemLoads[arg1] then
            ExtraIconsOptions._pendingItemLoads[arg1] = nil
            refreshPage()
        elseif event == "PLAYER_EQUIPMENT_CHANGED" and BUILTIN_EQUIP_SLOTS[arg1] then
            refreshPage()
        end
    end)
    itemLoadFrame._ecmHooked = true
end

local function getDraftDuplicateInfo(viewerKey)
    local ds = draftStates[viewerKey]
    local id = ExtraIconsOptions._parseSingleId(ds.idText)
    if not id then
        return false, nil
    end
    local dupViewer = ExtraIconsOptions._findDuplicateEntry(getViewers(), buildEntry(ds.kind, { id }))
    return dupViewer ~= nil, dupViewer
end

local function addDraftEntry(viewerKey)
    local ds = draftStates[viewerKey]
    local status = ExtraIconsOptions._resolveDraftEntryPreview(ds.kind, ds.idText)
    local isDuplicate = getDraftDuplicateInfo(viewerKey)
    if status ~= "resolved" or isDuplicate then
        return false
    end

    local id = ExtraIconsOptions._parseSingleId(ds.idText)
    ExtraIconsOptions._addCustomEntry(getProfile(), viewerKey, ds.kind, { id })
    ds.idText = ""
    doAction()
    return true
end

local function makeAction(text, buttonTextures, enabled, tooltip, onClick)
    return {
        text = buttonTextures and "" or text,
        width = ACTION_ICON_BUTTON_SIZE,
        height = ACTION_ICON_BUTTON_SIZE,
        buttonTextures = buttonTextures,
        enabled = enabled,
        tooltip = tooltip,
        onClick = onClick,
    }
end

local function profileAction(fn)
    return function()
        doAction(function()
            fn(getProfile())
        end)
    end
end

local function getDeleteAction(rowData, displayEntry, controlsDisabled)
    if rowData.isBuiltin then
        return makeAction(
            rowData.isDisabled and "+" or "x",
            rowData.isDisabled and ACTION_BUTTON_TEXTURES.show or ACTION_BUTTON_TEXTURES.hide,
            not controlsDisabled,
            rowData.isDisabled and L["ENABLE_TOOLTIP"] or L["EXTRA_ICONS_HIDE_TOOLTIP"],
            profileAction(function(profile)
                ExtraIconsOptions._toggleBuiltinRow(
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
            ExtraIconsOptions._toggleCurrentRacialRow(profile, rowData.viewerKey, nil, rowData.spellId)
        end))
    end

    return makeAction("x", ACTION_BUTTON_TEXTURES.delete, not controlsDisabled, L["REMOVE_TOOLTIP"], function()
        StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", ExtraIconsOptions._getEntryName(displayEntry), nil, {
            onAccept = profileAction(function(profile)
                ExtraIconsOptions._removeEntry(profile, rowData.viewerKey, rowData.index)
            end),
        })
    end)
end

local function makeReorderAction(rowData, text, buttonTextures, enabled, direction)
    return makeAction(text, buttonTextures, enabled, direction < 0 and L["MOVE_UP_TOOLTIP"] or L["MOVE_DOWN_TOOLTIP"],
        profileAction(function(profile)
            ExtraIconsOptions._reorderEntry(profile, rowData.viewerKey, rowData.index, direction)
        end))
end

local function getMoveTooltip(hasMoveDup, posLocked, otherViewer)
    if hasMoveDup then
        return L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(VIEWER_SHORT_LABELS[otherViewer])
    end
    if posLocked then
        return L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"]
    end
    return L["MOVE_TO_VIEWER_TOOLTIP"]:format(VIEWER_SHORT_LABELS[otherViewer])
end

local function buildActionItem(rowData)
    local controlsDisabled = isDisabled()
    local displayEntry = rowData.displayEntry
    local otherViewer = ExtraIconsOptions._otherViewer(rowData.viewerKey)
    local dupViewer = rowData.index ~= nil
        and ExtraIconsOptions._findDuplicateEntry(getViewers(), displayEntry, rowData.viewerKey, rowData.index) or nil
    local hasMoveDup = dupViewer == otherViewer
    local posLocked = rowData.isBuiltin and rowData.isDisabled
    local canReorder = not controlsDisabled and rowData.activeIndex ~= nil and not posLocked
    local canMove = not controlsDisabled and rowData.index ~= nil and not posLocked and not hasMoveDup
    local moveTextures = rowData.viewerKey == "utility" and ACTION_BUTTON_TEXTURES.moveRight or ACTION_BUTTON_TEXTURES.moveLeft

    return {
        label = ExtraIconsOptions._getEntryName(displayEntry),
        icon = ExtraIconsOptions._getEntryIcon(displayEntry) or 134400,
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
                    ExtraIconsOptions._moveEntry(profile, rowData.viewerKey, otherViewer, rowData.index)
                end)
            ),
            delete = getDeleteAction(rowData, displayEntry, controlsDisabled),
        },
    }
end

local function buildModeInputTrailer(viewerKey)
    local ds = draftStates[viewerKey]

    local function getPreviewState()
        local status, name, icon = ExtraIconsOptions._resolveDraftEntryPreview(ds.kind, ds.idText)
        local isDup, dupViewer = getDraftDuplicateInfo(viewerKey)
        return status, name, icon, isDup, dupViewer
    end

    local function toggleKind()
        if isDisabled() then return false end
        ds.kind = ds.kind == "spell" and "item" or "spell"; return true
    end

    return {
        type = "modeInput",
        disabled = isDisabled,
        modeText = function() return ds.kind == "spell" and L["ADD_SPELL"] or L["ADD_ITEM"] end,
        modeTooltip = L["EXTRA_ICONS_DRAFT_TYPE_TOOLTIP"],
        inputText = function() return ds.idText end,
        placeholder = function() return ds.kind == "spell" and L["EXTRA_ICONS_SPELL_ID_PLACEHOLDER"] or L["EXTRA_ICONS_ITEM_ID_PLACEHOLDER"] end,
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
        onTextChanged = function(text) ds.idText = text or "" end,
        onSubmit = function() return not isDisabled() and addDraftEntry(viewerKey) or false end,
        onTabPressed = toggleKind,
    }
end

function ExtraIconsOptions.BuildSections()
    local viewers = getViewers()
    local sections = {}
    for _, viewerKey in ipairs(VIEWER_ORDER) do
        local items = {}
        for _, rowData in ipairs(ExtraIconsOptions._buildViewerRows(viewers, viewerKey)) do
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
    local defaults = ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
    if not (defaults and defaults.extraIcons) then
        return
    end

    ns.Addon.db.profile.extraIcons = ns.CloneValue(defaults.extraIcons)
    for _, viewerKey in ipairs(VIEWER_ORDER) do
        draftStates[viewerKey].kind = "spell"
        draftStates[viewerKey].idText = ""
    end
    doAction()
end

ExtraIconsOptions.key = "extraIcons"
ExtraIconsOptions.name = L["EXTRA_ICONS"]

ExtraIconsOptions.pages = {
    {
        key = "main",
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
                id = "viewers",
                type = "sectionList",
                height = VIEWER_COLLECTION_HEIGHT,
                disabled = isDisabled,
                sections = ExtraIconsOptions.BuildSections,
                onDefault = ExtraIconsOptions.ResetToDefaults,
            },
        },
    },
}
