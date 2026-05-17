-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

StaticPopupDialogs["ECM_CREATE_ITEM_STACK"] =
    ns.OptionUtil.MakeTextInputDialog(L["ITEM_STACK_CREATE_PROMPT"], L["CREATE"], L["DONT_CREATE"])
StaticPopupDialogs["ECM_RENAME_ITEM_STACK"] =
    ns.OptionUtil.MakeTextInputDialog(L["ITEM_STACK_RENAME_PROMPT"], L["RENAME"], L["DONT_RENAME"])
StaticPopupDialogs["ECM_CONFIRM_DELETE_ITEM_STACK"] =
    ns.OptionUtil.MakeConfirmDialog(L["ITEM_STACK_DELETE_CONFIRM"], L["DELETE"], L["DONT_DELETE"])
StaticPopupDialogs["ECM_CONFIRM_REMOVE_ITEM_STACK_ITEM"] =
    ns.OptionUtil.MakeConfirmDialog(L["ITEM_STACK_REMOVE_ITEM_CONFIRM"], L["REMOVE"], L["DONT_REMOVE"])
StaticPopupDialogs["ECM_CONFIRM_REVERT_ITEM_STACK"] =
    ns.OptionUtil.MakeConfirmDialog(L["ITEM_STACK_REVERT_CONFIRM"], L["REVERT"], L["DONT_REVERT"])
StaticPopupDialogs["ECM_CONFIRM_REVERT_ITEM_STACK"] =
    ns.OptionUtil.MakeConfirmDialog(L["ITEM_STACK_REVERT_CONFIRM"], L["REVERT"], L["DONT_REVERT"])

local ITEM_STACK_ROW_HEIGHT = 22
local ITEM_STACK_COLLECTION_HEIGHT = 220
local ITEM_ID_SUFFIX_COLOR = "ff808080"
local ACTION_BUTTON_TEXTURES = ns.OptionUtil.ACTION_BUTTON_TEXTURES
local DEFAULT_ITEM_STACK_IDS = {
    combatPotions = true,
    healthPotions = true,
    healthstones = true,
}

local ItemStacksOptions = ns.ItemStacksOptions or {}
ns.ItemStacksOptions = ItemStacksOptions

ItemStacksOptions._pendingItemLoads = ItemStacksOptions._pendingItemLoads or {}
ItemStacksOptions._draftState = ItemStacksOptions._draftState or { idText = "" }

local registeredPage

local function getProfile() return ns.Addon.db.profile end
local function getDefaultItemStacks()
    local defaults = ns.Addon.db and ns.Addon.db.defaults and ns.Addon.db.defaults.profile
    defaults = defaults or (ns.defaults and ns.defaults.profile)
    return defaults and defaults.extraIcons and defaults.extraIcons.itemStacks or nil
end

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

local function ensureItemStacks(profile)
    local extraIcons = profile.extraIcons
    extraIcons.itemStacks = extraIcons.itemStacks or { nextId = 1, order = {}, byId = {} }
    local itemStacks = extraIcons.itemStacks
    itemStacks.order = itemStacks.order or {}
    itemStacks.byId = itemStacks.byId or {}
    itemStacks.nextId = itemStacks.nextId or 1
    return itemStacks
end

local function getItemStacks() return ensureItemStacks(getProfile()) end

local function isDefaultStackId(stackId)
    local defaultStacks = getDefaultItemStacks()
    if defaultStacks and defaultStacks.byId then
        return defaultStacks.byId[stackId] ~= nil
    end
    return DEFAULT_ITEM_STACK_IDS[stackId] == true
end

local function getFirstStackIdAlphabetically(itemStacks)
    local ids = {}
    for _, stackId in ipairs(itemStacks.order) do
        if itemStacks.byId[stackId] then
            ids[#ids + 1] = stackId
        end
    end
    table.sort(ids, function(a, b)
        local left = itemStacks.byId[a]
        local right = itemStacks.byId[b]
        local leftName = tostring(left and left.name or a):lower()
        local rightName = tostring(right and right.name or b):lower()
        if leftName == rightName then
            return tostring(a) < tostring(b)
        end
        return leftName < rightName
    end)
    return ids[1]
end

local function getSelectedStackId()
    local itemStacks = getItemStacks()
    local selected = ItemStacksOptions._selectedStackId
    if selected and itemStacks.byId[selected] then
        return selected
    end
    selected = getFirstStackIdAlphabetically(itemStacks)
    ItemStacksOptions._selectedStackId = selected
    return selected
end

local function getSelectedStack()
    local stackId = getSelectedStackId()
    return stackId and getItemStacks().byId[stackId] or nil
end

local function getItemIdFromEntry(entry) return type(entry) == "table" and (entry.itemID or entry.itemId) or entry end

local function getItemDisplayName(itemId)
    if not itemId then
        return nil
    end

    local name = C_Item.GetItemNameByID(itemId)
    if name then
        ItemStacksOptions._pendingItemLoads[itemId] = nil
        return name
    end

    if C_Item.DoesItemExistByID(itemId) then
        ItemStacksOptions._pendingItemLoads[itemId] = true
        C_Item.RequestLoadItemDataByID(itemId)
        return L["EXTRA_ICONS_ITEM_LOADING"]
    end

    return "Item " .. tostring(itemId)
end

local function getItemIcon(itemId) return itemId and C_Item.GetItemIconByID(itemId) or nil end

local function getItemQualityMarkup(entry)
    return ns.ExtraIconsOptions
        and ns.ExtraIconsOptions.GetItemQualityMarkup
        and ns.ExtraIconsOptions.GetItemQualityMarkup(entry)
        or nil
end

local function makeItemEntry(itemId) return { itemID = itemId } end

local function getItemEntryDisplayName(entry, includeItemId)
    local itemId = getItemIdFromEntry(entry)
    local name = getItemDisplayName(itemId)
    local displayName = name or ("Item " .. tostring(itemId))
    local qualityMarkup = getItemQualityMarkup(entry)
    if qualityMarkup then
        displayName = displayName .. " " .. qualityMarkup
    end
    if includeItemId and itemId then
        displayName = displayName .. " |c" .. ITEM_ID_SUFFIX_COLOR .. "{" .. tostring(itemId) .. "}|r"
    end
    return displayName
end

function ItemStacksOptions._parseSingleId(text)
    if not text or text == "" then
        return nil
    end
    local num = tonumber(text)
    if not num or num <= 0 or num ~= math.floor(num) then
        return nil
    end
    return num
end

function ItemStacksOptions._resolveDraftItemPreview(text)
    local id = ItemStacksOptions._parseSingleId(text)
    if not id or not C_Item.DoesItemExistByID(id) then
        return "invalid", nil, nil
    end

    local name = C_Item.GetItemNameByID(id)
    local icon = C_Item.GetItemIconByID(id)
    if name then
        ItemStacksOptions._pendingItemLoads[id] = nil
        return "resolved", getItemEntryDisplayName(makeItemEntry(id), false), icon
    end

    ItemStacksOptions._pendingItemLoads[id] = true
    C_Item.RequestLoadItemDataByID(id)
    return "pending", nil, icon
end

local function selectedStackHasItem(itemId)
    local itemStack = getSelectedStack()
    for _, entry in ipairs(itemStack and itemStack.ids or {}) do
        if getItemIdFromEntry(entry) == itemId then
            return true
        end
    end
    return false
end

function ItemStacksOptions._createStack(profile, name)
    local itemStacks = ensureItemStacks(profile)
    local stackId = itemStacks.nextId
    itemStacks.nextId = stackId + 1
    itemStacks.order[#itemStacks.order + 1] = stackId
    itemStacks.byId[stackId] = { name = name, ids = {} }
    ItemStacksOptions._selectedStackId = stackId
    return stackId
end

function ItemStacksOptions._renameStack(profile, stackId, name)
    if isDefaultStackId(stackId) then
        return
    end
    local itemStack = ensureItemStacks(profile).byId[stackId]
    if itemStack then
        itemStack.name = name
    end
end

function ItemStacksOptions._deleteStack(profile, stackId)
    if isDefaultStackId(stackId) then
        return
    end
    local itemStacks = ensureItemStacks(profile)
    itemStacks.byId[stackId] = nil
    for index = #itemStacks.order, 1, -1 do
        if itemStacks.order[index] == stackId then
            table.remove(itemStacks.order, index)
        end
    end

    local viewers = profile.extraIcons.viewers or {}
    for _, entries in pairs(viewers) do
        for index = #entries, 1, -1 do
            local entry = entries[index]
            if entry.kind == "itemStack" and entry.itemStackId == stackId then
                table.remove(entries, index)
            end
        end
    end

    if ItemStacksOptions._selectedStackId == stackId then
        ItemStacksOptions._selectedStackId = getFirstStackIdAlphabetically(itemStacks)
    end
    if ns.ExtraIconsOptions and ns.ExtraIconsOptions._selectedItemStackIds then
        for viewerKey, selectedStackId in pairs(ns.ExtraIconsOptions._selectedItemStackIds) do
            if selectedStackId == stackId then
                ns.ExtraIconsOptions._selectedItemStackIds[viewerKey] = nil
            end
        end
    end
end

function ItemStacksOptions._revertStackToDefault(profile, stackId)
    local defaultStacks = getDefaultItemStacks()
    local defaultStack = defaultStacks and defaultStacks.byId and defaultStacks.byId[stackId]
    if not defaultStack then
        return
    end
    ensureItemStacks(profile).byId[stackId] = ns.CloneValue(defaultStack)
end

function ItemStacksOptions._setStackVisibility(profile, stackId, key, value)
    local itemStack = ensureItemStacks(profile).byId[stackId]
    if itemStack then
        itemStack[key] = value and true or false
    end
end

local function setStackShowIfMissing(profile, stackId, value)
    local itemStack = ensureItemStacks(profile).byId[stackId]
    if itemStack then
        itemStack.showIfMissing = value and true or nil
    end
end

function ItemStacksOptions._addItem(profile, stackId, itemId)
    local itemStack = ensureItemStacks(profile).byId[stackId]
    if not itemStack then
        return
    end
    for _, entry in ipairs(itemStack.ids) do
        if getItemIdFromEntry(entry) == itemId then
            return
        end
    end
    itemStack.ids[#itemStack.ids + 1] = makeItemEntry(itemId)
end

function ItemStacksOptions._removeItem(profile, stackId, index)
    local itemStack = ensureItemStacks(profile).byId[stackId]
    if itemStack and index >= 1 and index <= #itemStack.ids then
        table.remove(itemStack.ids, index)
    end
end

function ItemStacksOptions._reorderItem(profile, stackId, index, direction)
    local itemStack = ensureItemStacks(profile).byId[stackId]
    local target = itemStack and index + direction or nil
    if target and target >= 1 and target <= #itemStack.ids then
        itemStack.ids[index], itemStack.ids[target] = itemStack.ids[target], itemStack.ids[index]
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

local function buildItemRow(itemStack, stackId, entry, index)
    local itemId = getItemIdFromEntry(entry)
    local count = #itemStack.ids
    return {
        label = getItemEntryDisplayName(entry, true),
        icon = getItemIcon(itemId) or 134400,
        actions = {
            up = makeAction("^", ACTION_BUTTON_TEXTURES.moveUp, index > 1, L["MOVE_UP_TOOLTIP"],
                profileAction(function(profile)
                    ItemStacksOptions._reorderItem(profile, stackId, index, -1)
                end)),
            down = makeAction("v", ACTION_BUTTON_TEXTURES.moveDown, index < count, L["MOVE_DOWN_TOOLTIP"],
                profileAction(function(profile)
                    ItemStacksOptions._reorderItem(profile, stackId, index, 1)
                end)),
            delete = makeAction("x", ACTION_BUTTON_TEXTURES.delete, true, L["REMOVE_TOOLTIP"], function()
                StaticPopup_Show("ECM_CONFIRM_REMOVE_ITEM_STACK_ITEM", getItemDisplayName(itemId), nil, {
                    onAccept = profileAction(function(profile)
                        ItemStacksOptions._removeItem(profile, stackId, index)
                    end),
                })
            end),
        },
    }
end

local function addDraftItem()
    local stackId = getSelectedStackId()
    local status = ItemStacksOptions._resolveDraftItemPreview(ItemStacksOptions._draftState.idText)
    local itemId = ItemStacksOptions._parseSingleId(ItemStacksOptions._draftState.idText)
    if not stackId or status ~= "resolved" or selectedStackHasItem(itemId) then
        return false
    end
    ItemStacksOptions._addItem(getProfile(), stackId, itemId)
    ItemStacksOptions._draftState.idText = ""
    doAction()
    return true
end

local function buildItemInputTrailer()
    local ds = ItemStacksOptions._draftState

    local function getPreviewState()
        local status, name, icon = ItemStacksOptions._resolveDraftItemPreview(ds.idText)
        local itemId = ItemStacksOptions._parseSingleId(ds.idText)
        return status, name, icon, itemId and selectedStackHasItem(itemId) or false
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
                return L["ITEM_STACK_DUPLICATE_ITEM"]
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
            return getSelectedStackId() ~= nil and status == "resolved" and not duplicate
        end,
        onTextChanged = function(text) ds.idText = text or "" end,
        onSubmit = addDraftItem,
    }
end

function ItemStacksOptions.BuildSections()
    local stackId = getSelectedStackId()
    local itemStack = getSelectedStack()
    local items = {}
    for index, entry in ipairs(itemStack and itemStack.ids or {}) do
        items[#items + 1] = buildItemRow(itemStack, stackId, entry, index)
    end

    return {
        {
            key = "items",
            title = itemStack and itemStack.name or L["ITEM_STACK_ITEMS"],
            items = items,
            emptyText = itemStack and L["ITEM_STACK_NO_ITEMS"] or L["ITEM_STACK_NONE"],
            rowHeight = ITEM_STACK_ROW_HEIGHT,
            footer = itemStack and buildItemInputTrailer() or nil,
            footerSpacing = 4,
        },
    }
end

function ItemStacksOptions.BuildStackValues()
    local itemStacks = getItemStacks()
    local values = {}
    for _, stackId in ipairs(itemStacks.order) do
        local itemStack = itemStacks.byId[stackId]
        if itemStack then
            values[tostring(stackId)] = itemStack.name
        end
    end
    return values
end

function ItemStacksOptions.GetSelectedVisibility(key)
    local itemStack = getSelectedStack()
    return itemStack and itemStack[key] == true or false
end

function ItemStacksOptions.SetSelectedVisibility(key, value)
    local stackId = getSelectedStackId()
    if stackId then
        ItemStacksOptions._setStackVisibility(getProfile(), stackId, key, value)
    end
end

local function getSelectedShowIfMissing()
    local itemStack = getSelectedStack()
    return itemStack and itemStack.showIfMissing == true or false
end

local function setSelectedShowIfMissing(value)
    local stackId = getSelectedStackId()
    if stackId then
        setStackShowIfMissing(getProfile(), stackId, value)
    end
end

local function isNoStackSelected()
    return getSelectedStackId() == nil
end

function ItemStacksOptions.EnsureItemLoadFrame()
    local itemLoadFrame = ItemStacksOptions._itemLoadFrame
    if not itemLoadFrame then
        itemLoadFrame = CreateFrame("Frame")
        ItemStacksOptions._itemLoadFrame = itemLoadFrame
    end
    if itemLoadFrame._ecmHooked then
        return
    end
    itemLoadFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemLoadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    itemLoadFrame:SetScript("OnEvent", function(_, _, itemId)
        local pendingId = tonumber(itemId) or itemId
        if pendingId and ItemStacksOptions._pendingItemLoads[pendingId] then
            ItemStacksOptions._pendingItemLoads[pendingId] = nil
            refreshPage()
            if not ItemStacksOptions._pendingRefreshScheduled then
                ItemStacksOptions._pendingRefreshScheduled = true
                C_Timer.After(0.1, function()
                    ItemStacksOptions._pendingRefreshScheduled = nil
                    refreshPage()
                end)
            end
        end
    end)
    itemLoadFrame._ecmHooked = true
end

function ItemStacksOptions.SetRegisteredPage(page) registeredPage = page end

local function openCreateDialog(ctx)
    StaticPopup_Show("ECM_CREATE_ITEM_STACK", nil, nil, {
        popupKey = "ECM_CREATE_ITEM_STACK",
        onAccept = function(name)
            doAction(function()
                ItemStacksOptions._createStack(getProfile(), name)
            end)
            ctx.page:Refresh()
        end,
    })
end

local function openRenameDialog(ctx)
    local stackId = getSelectedStackId()
    local itemStack = getSelectedStack()
    if not itemStack or isDefaultStackId(stackId) then
        return
    end
    StaticPopup_Show("ECM_RENAME_ITEM_STACK", nil, nil, {
        popupKey = "ECM_RENAME_ITEM_STACK",
        defaultText = itemStack.name,
        onAccept = function(name)
            doAction(function()
                ItemStacksOptions._renameStack(getProfile(), stackId, name)
            end)
            ctx.page:Refresh()
        end,
    })
end

local function openDeleteDialog(ctx)
    local stackId = getSelectedStackId()
    local itemStack = getSelectedStack()
    if not itemStack or isDefaultStackId(stackId) then
        return
    end
    StaticPopup_Show("ECM_CONFIRM_DELETE_ITEM_STACK", itemStack.name, nil, {
        onAccept = function()
            doAction(function()
                ItemStacksOptions._deleteStack(getProfile(), stackId)
            end)
            if ctx and ctx.page then
                ctx.page:Refresh()
            else
                refreshPage()
            end
        end,
    })
end

local function revertSelectedStack(ctx)
    local stackId = getSelectedStackId()
    local itemStack = getSelectedStack()
    if not itemStack or not isDefaultStackId(stackId) then
        return
    end
    StaticPopup_Show("ECM_CONFIRM_REVERT_ITEM_STACK", itemStack.name, nil, {
        onAccept = function()
            doAction(function()
                ItemStacksOptions._revertStackToDefault(getProfile(), stackId)
            end)
            if ctx and ctx.page then
                ctx.page:Refresh()
            else
                refreshPage()
            end
        end,
    })
end

ItemStacksOptions.page = {
    key = "itemStacks",
    name = L["ITEM_STACKS"],
    onShow = function()
        ns.Runtime.SetLayoutPreview(true)
        ItemStacksOptions.EnsureItemLoadFrame()
    end,
    onHide = function()
        ns.Runtime.SetLayoutPreview(false)
    end,
    rows = {
        {
            id = "createItemStack",
            type = "button",
            name = L["CREATE_ITEM_STACK"],
            buttonText = L["CREATE"],
            tooltip = L["CREATE_ITEM_STACK_DESC"],
            layout = false,
            onClick = openCreateDialog,
        },
        {
            id = "selectedManagedItemStack",
            type = "dropdown",
            key = "selectedManagedItemStack",
            name = L["ITEM_STACK"],
            tooltip = L["ITEM_STACK_SELECT_DESC"],
            values = ItemStacksOptions.BuildStackValues,
            layout = false,
            get = function()
                local stackId = getSelectedStackId()
                return stackId and tostring(stackId) or ""
            end,
            set = function(value)
                local stackId = tonumber(value) or value
                if getItemStacks().byId[stackId] then
                    ItemStacksOptions._selectedStackId = stackId
                end
            end,
            onSet = function(ctx)
                ItemStacksOptions._draftState.idText = ""
                ctx.page:Refresh()
            end,
        },
        {
            id = "hideStackInInstances",
            type = "checkbox",
            key = "hideStackInInstances",
            name = L["ITEM_STACK_HIDE_IN_INSTANCES"],
            tooltip = L["ITEM_STACK_HIDE_IN_INSTANCES_DESC"],
            layout = false,
            get = function()
                return ItemStacksOptions.GetSelectedVisibility("hideInInstances")
            end,
            set = function(value)
                ItemStacksOptions.SetSelectedVisibility("hideInInstances", value)
            end,
            disabled = function() return getSelectedStackId() == nil end,
            onSet = function(ctx)
                ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                ctx.page:Refresh()
            end,
        },
        {
            id = "hideStackInRatedPvp",
            type = "checkbox",
            key = "hideStackInRatedPvp",
            name = L["ITEM_STACK_HIDE_IN_RATED_PVP"],
            tooltip = L["ITEM_STACK_HIDE_IN_RATED_PVP_DESC"],
            layout = false,
            get = function()
                return ItemStacksOptions.GetSelectedVisibility("hideInRatedPvp")
            end,
            set = function(value)
                ItemStacksOptions.SetSelectedVisibility("hideInRatedPvp", value)
            end,
            disabled = function() return getSelectedStackId() == nil end,
            onSet = function(ctx)
                ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                ctx.page:Refresh()
            end,
        },
        {
            id = "showStackIfMissing",
            type = "checkbox",
            key = "showStackIfMissing",
            name = L["SHOW_IF_MISSING"],
            tooltip = L["SHOW_IF_MISSING_TOOLTIP"],
            layout = false,
            get = getSelectedShowIfMissing,
            set = setSelectedShowIfMissing,
            disabled = isNoStackSelected,
            onSet = function(ctx)
                ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                ctx.page:Refresh()
            end,
        },
        {
            id = "itemStackItems",
            type = "sectionList",
            height = ITEM_STACK_COLLECTION_HEIGHT,
            footerSpacing = 4,
            sections = ItemStacksOptions.BuildSections,
            layout = false,
        },
        {
            id = "renameItemStack",
            type = "button",
            name = L["RENAME_ITEM_STACK"],
            buttonText = L["RENAME"],
            tooltip = L["RENAME_ITEM_STACK_DESC"],
            disabled = function() return getSelectedStackId() == nil or isDefaultStackId(getSelectedStackId()) end,
            layout = false,
            onClick = openRenameDialog,
        },
        {
            id = "selectedStackActions",
            type = "pageActions",
            height = 28,
            layout = false,
            actions = {
                {
                    text = L["DELETE"],
                    tooltip = L["DELETE_ITEM_STACK_DESC"],
                    enabled = function() return getSelectedStackId() ~= nil end,
                    hidden = function() return isDefaultStackId(getSelectedStackId()) end,
                    onClick = function()
                        openDeleteDialog({ page = registeredPage })
                    end,
                },
                {
                    text = L["REVERT"],
                    tooltip = L["REVERT_ITEM_STACK_DESC"],
                    enabled = function() return getSelectedStackId() ~= nil end,
                    hidden = function() return not isDefaultStackId(getSelectedStackId()) end,
                    onClick = function()
                        revertSelectedStack({ page = registeredPage })
                    end,
                },
            },
        },
    },
}

if ns.ExtraIconsOptions and ns.ExtraIconsOptions.pages then
    ns.ExtraIconsOptions.pages[#ns.ExtraIconsOptions.pages + 1] = ItemStacksOptions.page
end
