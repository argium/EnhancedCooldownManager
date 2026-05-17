-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local OptionUtil = ns.OptionUtil
local Shared = ns.ExtraIconsShared
local EnsureItemStacks = Shared.EnsureItemStacks

StaticPopupDialogs["ECM_CREATE_ITEM_STACK"] =
    OptionUtil.MakeTextInputDialog(L["ITEM_STACK_CREATE_PROMPT"], L["CREATE"], L["DONT_CREATE"])
StaticPopupDialogs["ECM_RENAME_ITEM_STACK"] =
    OptionUtil.MakeTextInputDialog(L["ITEM_STACK_RENAME_PROMPT"], L["RENAME"], L["DONT_RENAME"])
StaticPopupDialogs["ECM_CONFIRM_DELETE_ITEM_STACK"] =
    OptionUtil.MakeConfirmDialog(L["ITEM_STACK_DELETE_CONFIRM"], L["DELETE"], L["DONT_DELETE"])
StaticPopupDialogs["ECM_CONFIRM_REMOVE_ITEM_STACK_ITEM"] =
    OptionUtil.MakeConfirmDialog(L["ITEM_STACK_REMOVE_ITEM_CONFIRM"], L["REMOVE"], L["DONT_REMOVE"])
StaticPopupDialogs["ECM_CONFIRM_REVERT_ITEM_STACK"] =
    OptionUtil.MakeConfirmDialog(L["ITEM_STACK_REVERT_CONFIRM"], L["REVERT"], L["DONT_REVERT"])

local ITEM_STACK_ROW_HEIGHT = 22
local ITEM_STACK_COLLECTION_HEIGHT = 220
local ITEM_ID_SUFFIX_COLOR = "ff808080"
local ACTION_BUTTON_TEXTURES = OptionUtil.ACTION_BUTTON_TEXTURES

local ItemStacksOptions = ns.ItemStacksOptions or {}
ns.ItemStacksOptions = ItemStacksOptions

ItemStacksOptions._pendingItemLoads = ItemStacksOptions._pendingItemLoads or {}
ItemStacksOptions._draftState = ItemStacksOptions._draftState or { idText = "" }

local registeredPage

local function getProfile() return ns.Addon.db.profile end

local function getDefaultStack(stackId)
    local defaults = ns.Addon.db.defaults.profile
    local defaultStacks = defaults and defaults.extraIcons and defaults.extraIcons.itemStacks
    local defaultStack = defaultStacks and defaultStacks.byId and defaultStacks.byId[stackId]
    if defaultStack then
        return defaultStack
    end

    defaults = ns.defaults and ns.defaults.profile
    defaultStacks = defaults and defaults.extraIcons and defaults.extraIcons.itemStacks
    return defaultStacks and defaultStacks.byId and defaultStacks.byId[stackId] or nil
end

local function refreshPage()
    local page = registeredPage
    if page then
        page:Refresh()
    end
end

local function doAction(fn, page)
    if fn then
        fn()
    end
    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    if registeredPage then
        refreshPage()
    elseif page then
        page:Refresh()
    end
end

local function getItemStacks() return EnsureItemStacks(getProfile()) end

local function isDefaultStackId(stackId) return getDefaultStack(stackId) ~= nil end

local function getSelectedStackId()
    local itemStacks = getItemStacks()
    local selected = Shared.ResolveSelectedStackId(itemStacks, ItemStacksOptions._selectedStackId)
    ItemStacksOptions._selectedStackId = selected
    return selected
end

local function getSelectedStack()
    local stackId = getSelectedStackId()
    return stackId and getItemStacks().byId[stackId] or nil
end

local function getItemQualityMarkup(entry)
    return ns.ExtraIconsOptions
        and ns.ExtraIconsOptions.GetItemQualityMarkup
        and ns.ExtraIconsOptions.GetItemQualityMarkup(entry)
        or nil
end

local function makeItemEntry(itemId) return { itemID = itemId } end

local function getItemEntryDisplayName(entry, includeItemId)
    local itemId = Shared.GetItemIdFromEntry(entry)
    local name = Shared.GetItemDisplayName(itemId, ItemStacksOptions._pendingItemLoads)
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

local function resolveDraftItemPreview(text)
    local id = Shared.ParseSingleId(text)
    if not id or not C_Item.DoesItemExistByID(id) then
        return "invalid", nil, nil
    end

    local name = C_Item.GetItemNameByID(id)
    local icon = C_Item.GetItemIconByID(id)
    if name then
        ItemStacksOptions._pendingItemLoads[id] = nil
        return "resolved", getItemEntryDisplayName(makeItemEntry(id), false), icon
    end

    Shared.RequestItemLoad(ItemStacksOptions._pendingItemLoads, id)
    return "pending", nil, icon
end

local function createStack(profile, name)
    local itemStacks = EnsureItemStacks(profile)
    local stackId = itemStacks.nextId
    itemStacks.nextId = stackId + 1
    itemStacks.order[#itemStacks.order + 1] = stackId
    itemStacks.byId[stackId] = { name = name, ids = {} }
    ItemStacksOptions._selectedStackId = stackId
    return stackId
end

local function renameStack(profile, stackId, name)
    if isDefaultStackId(stackId) then
        return
    end
    local itemStack = EnsureItemStacks(profile).byId[stackId]
    if itemStack then
        itemStack.name = name
    end
end

local function deleteStack(profile, stackId)
    if isDefaultStackId(stackId) then
        return
    end
    local itemStacks = EnsureItemStacks(profile)
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
        ItemStacksOptions._selectedStackId = Shared.GetFirstStackIdAlphabetically(itemStacks)
    end
    if ns.ExtraIconsOptions and ns.ExtraIconsOptions._selectedItemStackIds then
        for viewerKey, selectedStackId in pairs(ns.ExtraIconsOptions._selectedItemStackIds) do
            if selectedStackId == stackId then
                ns.ExtraIconsOptions._selectedItemStackIds[viewerKey] = nil
            end
        end
    end
end

local function revertStackToDefault(profile, stackId)
    local defaultStack = getDefaultStack(stackId)
    if not defaultStack then
        return
    end
    EnsureItemStacks(profile).byId[stackId] = ns.CloneValue(defaultStack)
end

local function setStackVisibility(profile, stackId, key, value)
    local itemStack = EnsureItemStacks(profile).byId[stackId]
    if itemStack then
        itemStack[key] = value and true or false
    end
end

local function setStackShowIfMissing(profile, stackId, value)
    local itemStack = EnsureItemStacks(profile).byId[stackId]
    if itemStack then
        itemStack.showIfMissing = value and true or nil
    end
end

local function addItem(profile, stackId, itemId)
    local itemStack = EnsureItemStacks(profile).byId[stackId]
    if not itemStack then
        return
    end
    for _, entry in ipairs(itemStack.ids) do
        if Shared.GetItemIdFromEntry(entry) == itemId then
            return
        end
    end
    itemStack.ids[#itemStack.ids + 1] = makeItemEntry(itemId)
end

local function removeItem(profile, stackId, index)
    local itemStack = EnsureItemStacks(profile).byId[stackId]
    if itemStack and index >= 1 and index <= #itemStack.ids then
        table.remove(itemStack.ids, index)
    end
end

local function reorderItem(profile, stackId, index, direction)
    local itemStack = EnsureItemStacks(profile).byId[stackId]
    local target = itemStack and index + direction or nil
    if target and target >= 1 and target <= #itemStack.ids then
        itemStack.ids[index], itemStack.ids[target] = itemStack.ids[target], itemStack.ids[index]
    end
end

local function buildItemRow(itemStack, stackId, entry, index)
    local itemId = Shared.GetItemIdFromEntry(entry)
    local count = #itemStack.ids
    return {
        label = getItemEntryDisplayName(entry, true),
        icon = C_Item.GetItemIconByID(itemId) or 134400,
        actions = {
            up = OptionUtil.CreateIconAction("^", ACTION_BUTTON_TEXTURES.moveUp, index > 1, L["MOVE_UP_TOOLTIP"],
                function()
                    doAction(function()
                        reorderItem(getProfile(), stackId, index, -1)
                    end)
                end),
            down = OptionUtil.CreateIconAction("v", ACTION_BUTTON_TEXTURES.moveDown, index < count, L["MOVE_DOWN_TOOLTIP"],
                function()
                    doAction(function()
                        reorderItem(getProfile(), stackId, index, 1)
                    end)
                end),
            delete = OptionUtil.CreateIconAction("x", ACTION_BUTTON_TEXTURES.delete, true, L["REMOVE_TOOLTIP"], function()
                StaticPopup_Show(
                    "ECM_CONFIRM_REMOVE_ITEM_STACK_ITEM",
                    Shared.GetItemDisplayName(itemId, ItemStacksOptions._pendingItemLoads),
                    nil,
                    {
                    onAccept = function()
                        doAction(function()
                            removeItem(getProfile(), stackId, index)
                        end)
                    end,
                })
            end),
        },
    }
end

local function getDraftPreviewState()
    local itemId = Shared.ParseSingleId(ItemStacksOptions._draftState.idText)
    local status, name, icon = resolveDraftItemPreview(ItemStacksOptions._draftState.idText)
    local duplicate = false
    if itemId then
        local itemStack = getSelectedStack()
        for _, entry in ipairs(itemStack and itemStack.ids or {}) do
            if Shared.GetItemIdFromEntry(entry) == itemId then
                duplicate = true
                break
            end
        end
    end
    return status, name, icon, duplicate, itemId
end

local function addDraftItem()
    local stackId = getSelectedStackId()
    local status, _, _, duplicate, itemId = getDraftPreviewState()
    if not stackId or status ~= "resolved" or duplicate then
        return false
    end
    addItem(getProfile(), stackId, itemId)
    ItemStacksOptions._draftState.idText = ""
    doAction()
    return true
end

local function buildItemInputTrailer()
    local ds = ItemStacksOptions._draftState

    return {
        type = "modeInput",
        modeHidden = true,
        inputText = function() return ds.idText end,
        placeholder = L["EXTRA_ICONS_ITEM_ID_PLACEHOLDER"],
        previewIcon = function()
            local _, _, icon = getDraftPreviewState()
            return icon
        end,
        previewText = function()
            local status, name, _, duplicate = getDraftPreviewState()
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
            local status, _, _, duplicate = getDraftPreviewState()
            return getSelectedStackId() ~= nil and status == "resolved" and not duplicate
        end,
        onTextChanged = function(text) ds.idText = text or "" end,
        onSubmit = addDraftItem,
    }
end

local function buildSections()
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

local function getSelectedVisibility(key)
    local itemStack = getSelectedStack()
    return itemStack and itemStack[key] == true or false
end

local function setSelectedVisibility(key, value)
    local stackId = getSelectedStackId()
    if stackId then
        setStackVisibility(getProfile(), stackId, key, value)
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

local function disableManagedStackActions()
    local stackId = getSelectedStackId()
    return stackId == nil or isDefaultStackId(stackId)
end

local function disableDefaultStackActions()
    local stackId = getSelectedStackId()
    return stackId == nil or not isDefaultStackId(stackId)
end

local function openCreateDialog(ctx)
    StaticPopup_Show("ECM_CREATE_ITEM_STACK", nil, nil, {
        popupKey = "ECM_CREATE_ITEM_STACK",
        onAccept = function(name)
            doAction(function()
                createStack(getProfile(), name)
            end, ctx and ctx.page or registeredPage)
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
                renameStack(getProfile(), stackId, name)
            end, ctx and ctx.page or registeredPage)
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
                deleteStack(getProfile(), stackId)
            end, ctx and ctx.page or registeredPage)
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
                revertStackToDefault(getProfile(), stackId)
            end, ctx and ctx.page or registeredPage)
        end,
    })
end

function ItemStacksOptions.EnsureItemLoadFrame()
    Shared.EnsureItemLoadFrame(ItemStacksOptions, { "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT" }, function(_, _, itemId)
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
end

function ItemStacksOptions.OnInitialize()
    registeredPage = ns.Settings:GetPage("extraIcons", "itemStacks")
    ItemStacksOptions.EnsureItemLoadFrame()
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
            values = function() return Shared.BuildItemStackValues(getItemStacks()) end,
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
                return getSelectedVisibility("hideInInstances")
            end,
            set = function(value)
                setSelectedVisibility("hideInInstances", value)
            end,
            disabled = isNoStackSelected,
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
                return getSelectedVisibility("hideInRatedPvp")
            end,
            set = function(value)
                setSelectedVisibility("hideInRatedPvp", value)
            end,
            disabled = isNoStackSelected,
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
            sections = buildSections,
            layout = false,
        },
        {
            id = "renameItemStack",
            type = "button",
            name = L["RENAME_ITEM_STACK"],
            buttonText = L["RENAME"],
            tooltip = L["RENAME_ITEM_STACK_DESC"],
            disabled = disableManagedStackActions,
            layout = false,
            onClick = openRenameDialog,
        },
        {
            id = "deleteItemStack",
            type = "button",
            name = L["DELETE_ITEM_STACK"],
            buttonText = L["DELETE"],
            tooltip = L["DELETE_ITEM_STACK_DESC"],
            disabled = disableManagedStackActions,
            layout = false,
            onClick = openDeleteDialog,
        },
        {
            id = "revertItemStack",
            type = "button",
            name = L["REVERT_ITEM_STACK"],
            buttonText = L["REVERT"],
            tooltip = L["REVERT_ITEM_STACK_DESC"],
            disabled = disableDefaultStackActions,
            layout = false,
            onClick = revertSelectedStack,
        },
    },
}

if ns.ExtraIconsOptions and ns.ExtraIconsOptions.pages then
    ns.ExtraIconsOptions.pages[#ns.ExtraIconsOptions.pages + 1] = ItemStacksOptions.page
end
