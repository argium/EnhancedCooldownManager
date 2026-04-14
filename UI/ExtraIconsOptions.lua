-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local BUILTIN_STACKS = C.BUILTIN_STACKS
local BUILTIN_STACK_ORDER = C.BUILTIN_STACK_ORDER
local RACIAL_ABILITIES = C.RACIAL_ABILITIES
local BUILTIN_EQUIP_SLOTS = {}
local VIEWER_COLLECTION_HEIGHT = 448
local ACTION_ICON_BUTTON_SIZE = 20
local DEFAULT_SPECIAL_VIEWER = "utility"
local VIEWER_ORDER = { "utility", "main" }
local VIEWER_LABELS = { utility = "UTILITY_VIEWER_ICONS", main = "MAIN_VIEWER_ICONS" }

local ACTION_BUTTON_TEXTURE_BASE = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\"
local function makeTexturePair(name)
    return { normal = ACTION_BUTTON_TEXTURE_BASE .. name .. "_normal", pushed = ACTION_BUTTON_TEXTURE_BASE .. name .. "_down" }
end
local ACTION_BUTTON_TEXTURES = {
    delete = makeTexturePair("delete"), hide = makeTexturePair("hide"),
    moveDown = makeTexturePair("move_down"), moveUp = makeTexturePair("move_up"),
    show = makeTexturePair("show"), swap = makeTexturePair("swap"),
}

local BUILTIN_STACK_SET = {}
for _, key in ipairs(BUILTIN_STACK_ORDER) do BUILTIN_STACK_SET[key] = true end
for _, stack in pairs(BUILTIN_STACKS) do
    if stack.kind == "equipSlot" and stack.slotId then BUILTIN_EQUIP_SLOTS[stack.slotId] = true end
end

local function isDisabledBuiltinEntry(entry)
    return entry and entry.stackKey and entry.disabled and BUILTIN_STACK_SET[entry.stackKey] == true
end

local ExtraIconsOptions = {}
ns.ExtraIconsOptions = ExtraIconsOptions
ExtraIconsOptions._pendingItemLoads = ExtraIconsOptions._pendingItemLoads or {}

--------------------------------------------------------------------------------
-- Entry Data Helpers
--------------------------------------------------------------------------------

local function getEntrySpellId(entry)
    if not (entry and entry.kind == "spell" and entry.ids and entry.ids[1]) then return nil end
    local first = entry.ids[1]
    return type(first) == "table" and first.spellId or first
end

local function getItemIdFromEntry(entry)
    return type(entry) == "table" and (entry.itemID or entry.itemId) or entry
end

local function getCurrentRacialEntry()
    local _, raceFile = UnitRace("player")
    local entry = RACIAL_ABILITIES[raceFile]
    if entry then return entry end
    for _, racialEntry in pairs(RACIAL_ABILITIES) do
        if racialEntry.spellId and C_SpellBook.IsSpellKnown(racialEntry.spellId) then return racialEntry end
    end
    return nil
end

local function getCurrentRacialSpellId()
    local racial = getCurrentRacialEntry()
    return racial and racial.spellId or nil
end

local function getItemDisplayName(itemId)
    if not itemId then return nil end
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

function ExtraIconsOptions._isStackKeyPresent(viewers, stackKey)
    for _, entries in pairs(viewers) do
        for _, entry in ipairs(entries) do
            if entry.stackKey == stackKey then return true end
        end
    end
    return false
end

function ExtraIconsOptions._shouldShowBuiltinStackRow(stackKey)
    local stack = stackKey and BUILTIN_STACKS[stackKey]
    if not stack or stack.kind ~= "equipSlot" then return true end
    local itemId = GetInventoryItemID("player", stack.slotId)
    if not itemId then return false end
    local _, spellId = C_Item.GetItemSpell(itemId)
    return spellId ~= nil
end

function ExtraIconsOptions._isRacialPresent(viewers, spellId)
    for _, entries in pairs(viewers) do
        for _, entry in ipairs(entries) do
            if getEntrySpellId(entry) == spellId then return true end
        end
    end
    return false
end

function ExtraIconsOptions._isCurrentRacialEntry(entry)
    local racialSpellId = getCurrentRacialSpellId()
    return racialSpellId ~= nil and getEntrySpellId(entry) == racialSpellId
end

function ExtraIconsOptions._isRacialForCurrentPlayer(entry)
    local spellId = getEntrySpellId(entry)
    if not spellId then return true end
    local racial = getCurrentRacialEntry()
    if not racial then return true end
    for _, racialEntry in pairs(RACIAL_ABILITIES) do
        if racialEntry ~= racial and spellId == racialEntry.spellId then return false end
    end
    return true
end

--------------------------------------------------------------------------------
-- Entry Display
--------------------------------------------------------------------------------

function ExtraIconsOptions._getEntryName(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then return entry.stackKey end
        if stack.kind == "equipSlot" then
            local itemId = GetInventoryItemID("player", stack.slotId)
            local itemName = itemId and getItemDisplayName(itemId)
            if itemName then return ("%s [%s]"):format(stack.label, itemName) end
        end
        return stack.label
    end
    if entry.kind == "spell" and entry.ids then
        local spellId = getEntrySpellId(entry)
        local spellAPI = type(C_Spell) == "table" and C_Spell or nil
        local name = spellId and spellAPI and spellAPI.GetSpellName and spellAPI.GetSpellName(spellId)
        return name or ("Spell " .. tostring(spellId))
    end
    if entry.kind == "item" and entry.ids then
        return getItemDisplayName(getItemIdFromEntry(entry.ids[1]))
    end
    return "Unknown"
end

function ExtraIconsOptions._getEntryIcon(entry)
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then return nil end
        if stack.kind == "equipSlot" then return GetInventoryItemTexture("player", stack.slotId) end
        if stack.ids and stack.ids[1] then
            local itemId = getItemIdFromEntry(stack.ids[1])
            return itemId and C_Item.GetItemIconByID(itemId)
        end
        return nil
    end
    if entry.kind == "spell" then
        local spellId = getEntrySpellId(entry)
        local spellAPI = type(C_Spell) == "table" and C_Spell or nil
        return spellId and spellAPI and spellAPI.GetSpellTexture and spellAPI.GetSpellTexture(spellId)
    end
    if entry.kind == "item" and entry.ids then
        local itemId = getItemIdFromEntry(entry.ids[1])
        return itemId and C_Item.GetItemIconByID(itemId)
    end
    return nil
end

local function getEntryTooltipTitle(entry)
    local name = ExtraIconsOptions._getEntryName(entry)
    if type(entry) ~= "table" then return name end
    if entry.kind == "spell" then
        local id = getEntrySpellId(entry)
        if id then return ("%s (spell ID %s)"):format(name, id) end
    elseif entry.kind == "item" and entry.ids and entry.ids[1] then
        local id = getItemIdFromEntry(entry.ids[1])
        if id then return ("%s (item ID %s)"):format(name, id) end
    end
    return name
end

local function showRowTooltip(owner, rowData)
    if not rowData then return end
    local displayEntry = rowData.displayEntry
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then GameTooltip:ClearLines() end
    GameTooltip:SetText(getEntryTooltipTitle(displayEntry), 1, 1, 1, 1, false)
    local function tip(text)
        if text and text ~= "" then GameTooltip:AddLine(text, 1, 1, 1, true) end
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
            if icon and type(CreateTextureMarkup) == "function" then
                parts[#parts + 1] = CreateTextureMarkup(icon, 64, 64, 14, 14, 0, 1, 0, 1)
            end
            parts[#parts + 1] = getItemDisplayName(itemId) or ("Item " .. tostring(itemId))
            local quality = type(itemEntry) == "table" and itemEntry.quality
            if quality and type(CreateAtlasMarkup) == "function" then
                parts[#parts + 1] = CreateAtlasMarkup("Professions-Icon-Quality-Tier" .. quality .. "-Small", 14, 14)
            elseif quality then
                parts[#parts + 1] = "[R" .. quality .. "]"
            end
            tip(table.concat(parts, " "))
        end
    end
    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Entry Mutations
--------------------------------------------------------------------------------

local function appendToViewer(viewers, viewerKey, entry)
    viewers[viewerKey] = viewers[viewerKey] or {}
    viewers[viewerKey][#viewers[viewerKey] + 1] = entry
end

function ExtraIconsOptions._addStackKey(profile, viewerKey, stackKey)
    local viewers = profile.extraIcons.viewers
    if not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
        appendToViewer(viewers, viewerKey, { stackKey = stackKey })
    end
end

function ExtraIconsOptions._addRacial(profile, viewerKey, spellId)
    local viewers = profile.extraIcons.viewers
    if not ExtraIconsOptions._isRacialPresent(viewers, spellId) then
        appendToViewer(viewers, viewerKey, { kind = "spell", ids = { spellId } })
    end
end

function ExtraIconsOptions._addCustomEntry(profile, viewerKey, kind, ids)
    local viewers = profile.extraIcons.viewers
    viewers[viewerKey] = viewers[viewerKey] or {}
    local entry = { kind = kind, ids = {} }
    for _, id in ipairs(ids) do
        entry.ids[#entry.ids + 1] = kind == "item" and { itemID = id } or id
    end
    if not ExtraIconsOptions._isDuplicateEntry(viewers, entry) then
        viewers[viewerKey][#viewers[viewerKey] + 1] = entry
    end
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
    if index then
        local entry = (profile.extraIcons.viewers[viewerKey] or {})[index]
        if entry then ExtraIconsOptions._setEntryDisabled(profile, viewerKey, index, not entry.disabled) end
    else
        ExtraIconsOptions._addStackKey(profile, viewerKey, stackKey)
    end
end

function ExtraIconsOptions._toggleCurrentRacialRow(profile, viewerKey, index, spellId)
    if index then
        ExtraIconsOptions._removeEntry(profile, viewerKey, index)
    elseif spellId then
        ExtraIconsOptions._addRacial(profile, viewerKey, spellId)
    end
end

local function isVisibleActiveViewerEntry(entry)
    return not isDisabledBuiltinEntry(entry)
        and ExtraIconsOptions._isRacialForCurrentPlayer(entry)
        and (not entry.stackKey or ExtraIconsOptions._shouldShowBuiltinStackRow(entry.stackKey))
end

function ExtraIconsOptions._reorderEntry(profile, viewerKey, index, direction)
    local entries = profile.extraIcons.viewers[viewerKey]
    if not entries then return end
    local visibleIndices, activeIndex = {}, nil
    for i, entry in ipairs(entries) do
        if isVisibleActiveViewerEntry(entry) then
            visibleIndices[#visibleIndices + 1] = i
            if i == index then activeIndex = #visibleIndices end
        end
    end
    if not activeIndex then return end
    local target = visibleIndices[activeIndex + direction]
    if target then entries[index], entries[target] = entries[target], entries[index] end
end

function ExtraIconsOptions._moveEntry(profile, fromViewer, toViewer, index)
    local from = profile.extraIcons.viewers[fromViewer]
    if not from or index < 1 or index > #from then return end
    if ExtraIconsOptions._findDuplicateEntry(profile.extraIcons.viewers, from[index], fromViewer, index) == toViewer then return end
    local entry = table.remove(from, index)
    local to = profile.extraIcons.viewers[toViewer] or {}
    profile.extraIcons.viewers[toViewer] = to
    to[#to + 1] = entry
end

function ExtraIconsOptions._otherViewer(viewerKey)
    return viewerKey == "utility" and "main" or "utility"
end

--------------------------------------------------------------------------------
-- Parsing and Resolution
--------------------------------------------------------------------------------

function ExtraIconsOptions._parseSingleId(text)
    if not text or text == "" then return nil end
    local num = tonumber(text)
    if not num or num <= 0 or num ~= math.floor(num) then return nil end
    return num
end

function ExtraIconsOptions._resolveDraftEntryPreview(kind, text)
    local id = ExtraIconsOptions._parseSingleId(text)
    if not id then return "invalid", nil, nil end
    if kind == "spell" then
        local spellAPI = type(C_Spell) == "table" and C_Spell or nil
        local name = spellAPI and spellAPI.GetSpellName and spellAPI.GetSpellName(id)
        if not name then return "invalid", nil, nil end
        return "resolved", name, spellAPI.GetSpellTexture and spellAPI.GetSpellTexture(id)
    end
    if kind == "item" then
        if not C_Item.DoesItemExistByID(id) then return "invalid", nil, nil end
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

--------------------------------------------------------------------------------
-- Duplicate Detection
--------------------------------------------------------------------------------

local function getEntryIdentityKey(entry)
    if not entry then return nil end
    if entry.stackKey then return "stack:" .. entry.stackKey end
    if not (entry.kind and entry.ids and #entry.ids > 0) then return nil end
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

function ExtraIconsOptions._findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex)
    local candidateKey = getEntryIdentityKey(candidateEntry)
    if not candidateKey then return nil, nil end
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
    return ExtraIconsOptions._findDuplicateEntry(viewers, candidateEntry, ignoreViewerKey, ignoreIndex) ~= nil
end

--------------------------------------------------------------------------------
-- Row Building
--------------------------------------------------------------------------------

function ExtraIconsOptions._buildViewerRows(viewers, viewerKey)
    local activeRows, disabledBuiltinRows = {}, {}
    for index, entry in ipairs(viewers[viewerKey] or {}) do
        if ExtraIconsOptions._isRacialForCurrentPlayer(entry)
            and (not entry.stackKey or ExtraIconsOptions._shouldShowBuiltinStackRow(entry.stackKey)) then
            local rowData = {
                rowType = "entry", viewerKey = viewerKey, index = index,
                entry = entry, displayEntry = entry,
                isBuiltin = entry.stackKey ~= nil,
                isCurrentRacial = ExtraIconsOptions._isCurrentRacialEntry(entry),
                isPlaceholder = false, isDisabled = entry.disabled == true,
            }
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
            for _, rowData in ipairs(bucket) do rows[#rows + 1] = rowData end
        elseif viewerKey == DEFAULT_SPECIAL_VIEWER
            and ExtraIconsOptions._shouldShowBuiltinStackRow(stackKey)
            and not ExtraIconsOptions._isStackKeyPresent(viewers, stackKey) then
            rows[#rows + 1] = {
                rowType = "builtinPlaceholder", viewerKey = viewerKey, stackKey = stackKey,
                displayEntry = { stackKey = stackKey },
                isBuiltin = true, isCurrentRacial = false, isPlaceholder = true, isDisabled = true,
            }
        end
    end
    if viewerKey == DEFAULT_SPECIAL_VIEWER then
        local racialSpellId = getCurrentRacialSpellId()
        if racialSpellId and not ExtraIconsOptions._isRacialPresent(viewers, racialSpellId) then
            rows[#rows + 1] = {
                rowType = "racialPlaceholder", viewerKey = viewerKey, spellId = racialSpellId,
                displayEntry = { kind = "spell", ids = { racialSpellId } },
                isBuiltin = false, isCurrentRacial = true, isPlaceholder = true, isDisabled = true,
            }
        end
    end
    return rows
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

    local function getProfile() return ns.Addon.db.profile end
    local function getViewers() return getProfile().extraIcons.viewers end
    local function refreshCategory()
        if category then SB.RefreshCategory(category) else SB.RefreshCategory(categoryName) end
    end
    local function doAction(fn)
        if fn then fn() end
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        refreshCategory()
    end
    local function getViewerShortLabel(viewerKey)
        return viewerKey == "utility" and L["UTILITY_VIEWER_SHORT"] or L["MAIN_VIEWER_SHORT"]
    end

    ExtraIconsOptions._draftStates = ExtraIconsOptions._draftStates or {}
    local draftStates = ExtraIconsOptions._draftStates
    for _, viewerKey in ipairs(VIEWER_ORDER) do
        draftStates[viewerKey] = draftStates[viewerKey] or { kind = "spell", idText = "" }
    end

    local itemLoadFrame = ExtraIconsOptions._itemLoadFrame
    if not itemLoadFrame then
        itemLoadFrame = CreateFrame("Frame")
        ExtraIconsOptions._itemLoadFrame = itemLoadFrame
    end
    if not itemLoadFrame._ecmHooked then
        itemLoadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        itemLoadFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        itemLoadFrame:SetScript("OnEvent", function(_, event, arg1)
            if event == "GET_ITEM_INFO_RECEIVED" and arg1 and ExtraIconsOptions._pendingItemLoads[arg1] then
                ExtraIconsOptions._pendingItemLoads[arg1] = nil
                refreshCategory()
            elseif event == "PLAYER_EQUIPMENT_CHANGED" and BUILTIN_EQUIP_SLOTS[arg1] then
                refreshCategory()
            end
        end)
        itemLoadFrame._ecmHooked = true
    end

    local function buildDraftEntry(kind, id)
        if not id then return nil end
        if kind == "item" then return { kind = "item", ids = { { itemID = id } } } end
        if kind == "spell" then return { kind = "spell", ids = { id } } end
        return nil
    end

    local function getDraftDuplicateInfo(viewerKey)
        local ds = draftStates[viewerKey]
        local entry = buildDraftEntry(ds.kind, ExtraIconsOptions._parseSingleId(ds.idText))
        local dupViewer = entry and ExtraIconsOptions._findDuplicateEntry(getViewers(), entry) or nil
        return dupViewer ~= nil, dupViewer
    end

    local function addDraftEntry(viewerKey)
        local ds = draftStates[viewerKey]
        local status = ExtraIconsOptions._resolveDraftEntryPreview(ds.kind, ds.idText)
        if status ~= "resolved" or getDraftDuplicateInfo(viewerKey) then return false end
        local id = ExtraIconsOptions._parseSingleId(ds.idText)
        ExtraIconsOptions._addCustomEntry(getProfile(), viewerKey, ds.kind, { id })
        ds.idText = ""
        doAction()
        return true
    end

    local function makeAction(text, textures, enabled, tooltip, onClick)
        return {
            text = text, width = ACTION_ICON_BUTTON_SIZE, height = ACTION_ICON_BUTTON_SIZE,
            buttonTextures = textures, enabled = enabled, tooltip = tooltip, onClick = onClick,
        }
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

        local delText, delTex, delTip = "x", ACTION_BUTTON_TEXTURES.delete, L["REMOVE_TOOLTIP"]
        local delAction = function()
            StaticPopup_Show("ECM_CONFIRM_REMOVE_EXTRA_ICON", ExtraIconsOptions._getEntryName(displayEntry), nil, {
                onAccept = function() doAction(function()
                    ExtraIconsOptions._removeEntry(getProfile(), rowData.viewerKey, rowData.index)
                end) end,
            })
        end
        if rowData.isBuiltin then
            delText = rowData.isDisabled and "+" or "x"
            delTex = rowData.isDisabled and ACTION_BUTTON_TEXTURES.show or ACTION_BUTTON_TEXTURES.hide
            delTip = rowData.isDisabled and L["ENABLE_TOOLTIP"] or L["EXTRA_ICONS_HIDE_TOOLTIP"]
            delAction = function() doAction(function()
                ExtraIconsOptions._toggleBuiltinRow(getProfile(), rowData.viewerKey, rowData.index, rowData.stackKey or displayEntry.stackKey)
            end) end
        elseif rowData.isCurrentRacial and rowData.isPlaceholder then
            delText, delTex, delTip = "+", ACTION_BUTTON_TEXTURES.show, L["ADD_ENTRY"]
            delAction = function() doAction(function()
                ExtraIconsOptions._toggleCurrentRacialRow(getProfile(), rowData.viewerKey, nil, rowData.spellId)
            end) end
        end

        return {
            label = ExtraIconsOptions._getEntryName(displayEntry),
            icon = ExtraIconsOptions._getEntryIcon(displayEntry) or 134400,
            alpha = rowData.isDisabled and 0.55 or 1,
            labelFontObject = rowData.isDisabled and (_G.GameFontDisable or _G.GameFontNormal) or _G.GameFontNormal,
            labelColor = rowData.isDisabled and { 0.65, 0.65, 0.65, 1 } or { 1, 0.82, 0, 1 },
            iconDesaturated = rowData.isDisabled == true,
            iconVertexColor = rowData.isDisabled and { 0.6, 0.6, 0.6, 1 } or nil,
            onEnter = function(owner) showRowTooltip(owner, rowData) end,
            onLeave = function() GameTooltip_Hide() end,
            actions = {
                up = makeAction("^", ACTION_BUTTON_TEXTURES.moveUp, canReorder and rowData.activeIndex > 1, L["MOVE_UP_TOOLTIP"],
                    function() doAction(function() ExtraIconsOptions._reorderEntry(getProfile(), rowData.viewerKey, rowData.index, -1) end) end),
                down = makeAction("v", ACTION_BUTTON_TEXTURES.moveDown, canReorder and rowData.activeIndex < rowData.activeCount, L["MOVE_DOWN_TOOLTIP"],
                    function() doAction(function() ExtraIconsOptions._reorderEntry(getProfile(), rowData.viewerKey, rowData.index, 1) end) end),
                move = makeAction(rowData.viewerKey == "utility" and ">" or "<", ACTION_BUTTON_TEXTURES.swap, canMove,
                    function()
                        if hasMoveDup then return L["EXTRA_ICONS_DUPLICATE_MOVE_TOOLTIP"]:format(getViewerShortLabel(otherViewer)) end
                        if posLocked then return L["EXTRA_ICONS_BUILTIN_ORDER_TOOLTIP"] end
                        return L["MOVE_TO_VIEWER_TOOLTIP"]:format(getViewerShortLabel(otherViewer))
                    end,
                    function() doAction(function() ExtraIconsOptions._moveEntry(getProfile(), rowData.viewerKey, otherViewer, rowData.index) end) end),
                delete = makeAction(delText, delTex, not controlsDisabled, delTip, delAction),
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
            ds.kind = ds.kind == "spell" and "item" or "spell"
            return true
        end
        return {
            type = "modeInput",
            disabled = isDisabled,
            modeText = function() return ds.kind == "spell" and L["ADD_SPELL"] or L["ADD_ITEM"] end,
            modeTooltip = L["EXTRA_ICONS_DRAFT_TYPE_TOOLTIP"],
            inputText = function() return ds.idText end,
            placeholder = function()
                return ds.kind == "spell" and L["EXTRA_ICONS_SPELL_ID_PLACEHOLDER"] or L["EXTRA_ICONS_ITEM_ID_PLACEHOLDER"]
            end,
            previewIcon = function() local _, _, icon = getPreviewState(); return icon end,
            previewText = function()
                local status, name, _, isDup, dupViewer = getPreviewState()
                if status == "resolved" and isDup then return L["EXTRA_ICONS_DUPLICATE_ENTRY"]:format(getViewerShortLabel(dupViewer)) end
                if status == "resolved" then return name or "" end
                if status == "pending" then return "..." end
                return nil
            end,
            submitText = L["ADD_ENTRY"],
            submitTooltip = L["ADD_ENTRY"],
            submitEnabled = function()
                local s, _, _, d = getPreviewState()
                return s == "resolved" and not d
            end,
            onToggleMode = toggleKind,
            onTextChanged = function(text) ds.idText = text or "" end,
            onSubmit = function()
                if isDisabled() then return false end
                return addDraftEntry(viewerKey)
            end,
            onTabPressed = toggleKind,
        }
    end

    ExtraIconsOptions._refresh = refreshCategory

    SB.RegisterPage({
        name = categoryName,
        path = "extraIcons",
        onShow = function() ns.Runtime.SetLayoutPreview(true) end,
        onHide = function() ns.Runtime.SetLayoutPreview(false) end,
        rows = {
            {
                id = "enabled", type = "checkbox", path = "enabled",
                name = L["ENABLE_EXTRA_ICONS"], desc = L["ENABLE_EXTRA_ICONS_DESC"],
                onSet = function(value) ns.OptionUtil.CreateModuleEnabledHandler("ExtraIcons")(value) end,
            },
            {
                id = "specialRowsLegend", type = "info", name = "",
                value = L["EXTRA_ICONS_SPECIAL_ROWS_LEGEND"],
                wide = true, multiline = true, height = 24,
            },
            {
                id = "viewers", type = "sectionList", height = VIEWER_COLLECTION_HEIGHT,
                disabled = isDisabled,
                sections = function()
                    local viewers = getViewers()
                    local sections = {}
                    for _, vk in ipairs(VIEWER_ORDER) do
                        local items = {}
                        for _, rowData in ipairs(ExtraIconsOptions._buildViewerRows(viewers, vk)) do
                            items[#items + 1] = buildActionItem(rowData)
                        end
                        sections[#sections + 1] = {
                            key = vk, title = L[VIEWER_LABELS[vk]], items = items,
                            emptyText = L["EXTRA_ICONS_NO_ENTRIES"],
                            footer = buildModeInputTrailer(vk),
                        }
                    end
                    return sections
                end,
                onDefault = function()
                    local defaults = ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
                    if not (defaults and defaults.extraIcons) then return end
                    ns.Addon.db.profile.extraIcons = ns.CloneValue(defaults.extraIcons)
                    for _, vk in ipairs(VIEWER_ORDER) do draftStates[vk].kind = "spell"; draftStates[vk].idText = "" end
                    doAction()
                end,
            },
        },
    })

    category = SB.GetSubcategory(categoryName)
    ExtraIconsOptions._category = category
end

ns.SettingsBuilder.RegisterSection(ns, "ExtraIcons", ExtraIconsOptions)
