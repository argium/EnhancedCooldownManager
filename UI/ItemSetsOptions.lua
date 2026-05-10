-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

StaticPopupDialogs["ECM_CREATE_ITEM_SET"] =
    ns.OptionUtil.MakeTextInputDialog(L["ITEM_SET_CREATE_PROMPT"], L["CREATE"], L["DONT_CREATE"])
StaticPopupDialogs["ECM_RENAME_ITEM_SET"] =
    ns.OptionUtil.MakeTextInputDialog(L["ITEM_SET_RENAME_PROMPT"], L["RENAME"], L["DONT_RENAME"])
StaticPopupDialogs["ECM_CONFIRM_DELETE_ITEM_SET"] =
    ns.OptionUtil.MakeConfirmDialog(L["ITEM_SET_DELETE_CONFIRM"], L["DELETE"], L["DONT_DELETE"])
StaticPopupDialogs["ECM_CONFIRM_REMOVE_ITEM_SET_ITEM"] =
    ns.OptionUtil.MakeConfirmDialog(L["ITEM_SET_REMOVE_ITEM_CONFIRM"], L["REMOVE"], L["DONT_REMOVE"])

local ITEM_SET_COLLECTION_HEIGHT = 320
local ACTION_BUTTON_TEXTURES = ns.OptionUtil.ACTION_BUTTON_TEXTURES

local ItemSetsOptions = ns.ItemSetsOptions or {}
ns.ItemSetsOptions = ItemSetsOptions

ItemSetsOptions._pendingItemLoads = ItemSetsOptions._pendingItemLoads or {}
ItemSetsOptions._draftState = ItemSetsOptions._draftState or { idText = "" }

local registeredPage

local function getProfile() return ns.Addon.db.profile end

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

local function ensureItemSets(profile)
    local extraIcons = profile.extraIcons
    extraIcons.itemSets = extraIcons.itemSets or { nextId = 1, order = {}, byId = {} }
    local itemSets = extraIcons.itemSets
    itemSets.order = itemSets.order or {}
    itemSets.byId = itemSets.byId or {}
    itemSets.nextId = itemSets.nextId or 1
    return itemSets
end

local function getItemSets() return ensureItemSets(getProfile()) end

local function getSelectedSetId()
    local itemSets = getItemSets()
    local selected = ItemSetsOptions._selectedSetId
    if selected and itemSets.byId[selected] then
        return selected
    end
    selected = itemSets.order[1]
    ItemSetsOptions._selectedSetId = selected
    return selected
end

local function getSelectedSet()
    local setId = getSelectedSetId()
    return setId and getItemSets().byId[setId] or nil
end

local function getItemIdFromEntry(entry) return type(entry) == "table" and (entry.itemID or entry.itemId) or entry end

local function getItemDisplayName(itemId)
    if not itemId then
        return nil
    end

    local name = C_Item.GetItemNameByID(itemId)
    if name then
        ItemSetsOptions._pendingItemLoads[itemId] = nil
        return name
    end

    if C_Item.DoesItemExistByID(itemId) then
        ItemSetsOptions._pendingItemLoads[itemId] = true
        C_Item.RequestLoadItemDataByID(itemId)
        return L["EXTRA_ICONS_ITEM_LOADING"]
    end

    return "Item " .. tostring(itemId)
end

local function getItemIcon(itemId) return itemId and C_Item.GetItemIconByID(itemId) or nil end

function ItemSetsOptions._parseSingleId(text)
    if not text or text == "" then
        return nil
    end
    local num = tonumber(text)
    if not num or num <= 0 or num ~= math.floor(num) then
        return nil
    end
    return num
end

function ItemSetsOptions._resolveDraftItemPreview(text)
    local id = ItemSetsOptions._parseSingleId(text)
    if not id or not C_Item.DoesItemExistByID(id) then
        return "invalid", nil, nil
    end

    local name = C_Item.GetItemNameByID(id)
    local icon = C_Item.GetItemIconByID(id)
    if name then
        ItemSetsOptions._pendingItemLoads[id] = nil
        return "resolved", name, icon
    end

    ItemSetsOptions._pendingItemLoads[id] = true
    C_Item.RequestLoadItemDataByID(id)
    return "pending", nil, icon
end

local function selectedSetHasItem(itemId)
    local itemSet = getSelectedSet()
    for _, entry in ipairs(itemSet and itemSet.ids or {}) do
        if getItemIdFromEntry(entry) == itemId then
            return true
        end
    end
    return false
end

function ItemSetsOptions._createSet(profile, name)
    local itemSets = ensureItemSets(profile)
    local setId = itemSets.nextId
    itemSets.nextId = setId + 1
    itemSets.order[#itemSets.order + 1] = setId
    itemSets.byId[setId] = { name = name, ids = {} }
    ItemSetsOptions._selectedSetId = setId
    return setId
end

function ItemSetsOptions._renameSet(profile, setId, name)
    local itemSet = ensureItemSets(profile).byId[setId]
    if itemSet then
        itemSet.name = name
    end
end

function ItemSetsOptions._deleteSet(profile, setId)
    local itemSets = ensureItemSets(profile)
    itemSets.byId[setId] = nil
    for index = #itemSets.order, 1, -1 do
        if itemSets.order[index] == setId then
            table.remove(itemSets.order, index)
        end
    end

    local viewers = profile.extraIcons.viewers or {}
    for _, entries in pairs(viewers) do
        for index = #entries, 1, -1 do
            local entry = entries[index]
            if entry.kind == "itemSet" and entry.itemSetId == setId then
                table.remove(entries, index)
            end
        end
    end

    if ItemSetsOptions._selectedSetId == setId then
        ItemSetsOptions._selectedSetId = itemSets.order[1]
    end
    if ns.ExtraIconsOptions and ns.ExtraIconsOptions._selectedItemSetId == setId then
        ns.ExtraIconsOptions._selectedItemSetId = nil
    end
end

function ItemSetsOptions._addItem(profile, setId, itemId)
    local itemSet = ensureItemSets(profile).byId[setId]
    if not itemSet then
        return
    end
    for _, entry in ipairs(itemSet.ids) do
        if getItemIdFromEntry(entry) == itemId then
            return
        end
    end
    itemSet.ids[#itemSet.ids + 1] = { itemID = itemId }
end

function ItemSetsOptions._removeItem(profile, setId, index)
    local itemSet = ensureItemSets(profile).byId[setId]
    if itemSet and index >= 1 and index <= #itemSet.ids then
        table.remove(itemSet.ids, index)
    end
end

function ItemSetsOptions._reorderItem(profile, setId, index, direction)
    local itemSet = ensureItemSets(profile).byId[setId]
    local target = itemSet and index + direction or nil
    if target and target >= 1 and target <= #itemSet.ids then
        itemSet.ids[index], itemSet.ids[target] = itemSet.ids[target], itemSet.ids[index]
    end
end

local function makeAction(text, buttonTextures, enabled, tooltip, onClick)
    return ns.OptionUtil.CreateIconAction(text, buttonTextures, enabled, tooltip, onClick)
end

local function profileAction(fn)
    return function()
        doAction(function()
            fn(getProfile())
        end)
    end
end

local function buildItemRow(itemSet, setId, entry, index)
    local itemId = getItemIdFromEntry(entry)
    local count = #itemSet.ids
    return {
        label = getItemDisplayName(itemId),
        icon = getItemIcon(itemId) or 134400,
        actions = {
            up = makeAction("^", ACTION_BUTTON_TEXTURES.moveUp, index > 1, L["MOVE_UP_TOOLTIP"],
                profileAction(function(profile)
                    ItemSetsOptions._reorderItem(profile, setId, index, -1)
                end)),
            down = makeAction("v", ACTION_BUTTON_TEXTURES.moveDown, index < count, L["MOVE_DOWN_TOOLTIP"],
                profileAction(function(profile)
                    ItemSetsOptions._reorderItem(profile, setId, index, 1)
                end)),
            delete = makeAction("x", ACTION_BUTTON_TEXTURES.delete, true, L["REMOVE_TOOLTIP"], function()
                StaticPopup_Show("ECM_CONFIRM_REMOVE_ITEM_SET_ITEM", getItemDisplayName(itemId), nil, {
                    onAccept = profileAction(function(profile)
                        ItemSetsOptions._removeItem(profile, setId, index)
                    end),
                })
            end),
        },
    }
end

local function addDraftItem()
    local setId = getSelectedSetId()
    local status = ItemSetsOptions._resolveDraftItemPreview(ItemSetsOptions._draftState.idText)
    local itemId = ItemSetsOptions._parseSingleId(ItemSetsOptions._draftState.idText)
    if not setId or status ~= "resolved" or selectedSetHasItem(itemId) then
        return false
    end
    ItemSetsOptions._addItem(getProfile(), setId, itemId)
    ItemSetsOptions._draftState.idText = ""
    doAction()
    return true
end

local function buildItemInputTrailer()
    local ds = ItemSetsOptions._draftState

    local function getPreviewState()
        local status, name, icon = ItemSetsOptions._resolveDraftItemPreview(ds.idText)
        local itemId = ItemSetsOptions._parseSingleId(ds.idText)
        return status, name, icon, itemId and selectedSetHasItem(itemId) or false
    end

    return {
        type = "modeInput",
        modeHidden = true,
        inputText = function() return ds.idText end,
        placeholder = L["EXTRA_ICONS_ITEM_ID_PLACEHOLDER"],
        previewIcon = function() local _, _, icon = getPreviewState(); return icon end,
        previewText = function()
            local status, name, _, duplicate = getPreviewState()
            if status == "resolved" and duplicate then
                return L["ITEM_SET_DUPLICATE_ITEM"]
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
            local status, _, _, duplicate = getPreviewState()
            return getSelectedSetId() ~= nil and status == "resolved" and not duplicate
        end,
        onTextChanged = function(text) ds.idText = text or "" end,
        onSubmit = addDraftItem,
    }
end

function ItemSetsOptions.BuildSections()
    local setId = getSelectedSetId()
    local itemSet = getSelectedSet()
    local items = {}
    for index, entry in ipairs(itemSet and itemSet.ids or {}) do
        items[#items + 1] = buildItemRow(itemSet, setId, entry, index)
    end

    return {
        {
            key = "items",
            title = itemSet and itemSet.name or L["ITEM_SET_ITEMS"],
            items = items,
            emptyText = itemSet and L["ITEM_SET_NO_ITEMS"] or L["ITEM_SET_NONE"],
            footer = itemSet and buildItemInputTrailer() or nil,
            footerSpacing = 4,
        },
    }
end

function ItemSetsOptions.BuildSetValues()
    local itemSets = getItemSets()
    local values = {}
    for _, setId in ipairs(itemSets.order) do
        local itemSet = itemSets.byId[setId]
        if itemSet then
            values[setId] = itemSet.name
        end
    end
    return values
end

function ItemSetsOptions.EnsureItemLoadFrame()
    local itemLoadFrame = ItemSetsOptions._itemLoadFrame
    if not itemLoadFrame then
        itemLoadFrame = CreateFrame("Frame")
        ItemSetsOptions._itemLoadFrame = itemLoadFrame
    end
    if itemLoadFrame._ecmHooked then
        return
    end
    itemLoadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemLoadFrame:SetScript("OnEvent", function(_, _, itemId)
        if itemId and ItemSetsOptions._pendingItemLoads[itemId] then
            ItemSetsOptions._pendingItemLoads[itemId] = nil
            refreshPage()
        end
    end)
    itemLoadFrame._ecmHooked = true
end

function ItemSetsOptions.SetRegisteredPage(page) registeredPage = page end

local function openCreateDialog(ctx)
    StaticPopup_Show("ECM_CREATE_ITEM_SET", nil, nil, {
        popupKey = "ECM_CREATE_ITEM_SET",
        onAccept = function(name)
            doAction(function()
                ItemSetsOptions._createSet(getProfile(), name)
            end)
            ctx.page:Refresh()
        end,
    })
end

local function openRenameDialog(ctx)
    local setId = getSelectedSetId()
    local itemSet = getSelectedSet()
    if not itemSet then
        return
    end
    StaticPopup_Show("ECM_RENAME_ITEM_SET", nil, nil, {
        popupKey = "ECM_RENAME_ITEM_SET",
        defaultText = itemSet.name,
        onAccept = function(name)
            doAction(function()
                ItemSetsOptions._renameSet(getProfile(), setId, name)
            end)
            ctx.page:Refresh()
        end,
    })
end

local function openDeleteDialog(ctx)
    local setId = getSelectedSetId()
    local itemSet = getSelectedSet()
    if not itemSet then
        return
    end
    StaticPopup_Show("ECM_CONFIRM_DELETE_ITEM_SET", itemSet.name, nil, {
        onAccept = function()
            doAction(function()
                ItemSetsOptions._deleteSet(getProfile(), setId)
            end)
            ctx.page:Refresh()
        end,
    })
end

ItemSetsOptions.page = {
    key = "itemSets",
    name = L["ITEM_SETS"],
    onShow = ItemSetsOptions.EnsureItemLoadFrame,
    rows = {
        {
            id = "createItemSet",
            type = "button",
            name = L["CREATE_ITEM_SET"],
            buttonText = L["CREATE"],
            tooltip = L["CREATE_ITEM_SET_DESC"],
            layout = false,
            onClick = openCreateDialog,
        },
        {
            id = "selectedItemSet",
            type = "dropdown",
            key = "selectedItemSet",
            name = L["ITEM_SET"],
            tooltip = L["ITEM_SET_SELECT_DESC"],
            values = ItemSetsOptions.BuildSetValues,
            layout = false,
            get = function()
                return getSelectedSetId() or ""
            end,
            set = function(value)
                ItemSetsOptions._selectedSetId = tonumber(value) or value
            end,
            onSet = function(ctx)
                ItemSetsOptions._draftState.idText = ""
                ctx.page:Refresh()
            end,
        },
        {
            id = "itemSetItems",
            type = "sectionList",
            height = ITEM_SET_COLLECTION_HEIGHT,
            footerSpacing = 4,
            sections = ItemSetsOptions.BuildSections,
            layout = false,
        },
        {
            id = "renameItemSet",
            type = "button",
            name = L["RENAME_ITEM_SET"],
            buttonText = L["RENAME"],
            tooltip = L["RENAME_ITEM_SET_DESC"],
            disabled = function() return getSelectedSetId() == nil end,
            layout = false,
            onClick = openRenameDialog,
        },
        {
            id = "deleteItemSet",
            type = "button",
            name = L["DELETE_ITEM_SET"],
            buttonText = L["DELETE"],
            tooltip = L["DELETE_ITEM_SET_DESC"],
            disabled = function() return getSelectedSetId() == nil end,
            layout = false,
            onClick = openDeleteDialog,
        },
    },
}

if ns.ExtraIconsOptions and ns.ExtraIconsOptions.pages then
    ns.ExtraIconsOptions.pages[#ns.ExtraIconsOptions.pages + 1] = ItemSetsOptions.page
end
