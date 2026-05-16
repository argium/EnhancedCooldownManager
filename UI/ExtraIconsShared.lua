-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

local ExtraIconsShared = ns.ExtraIconsShared or {}
ns.ExtraIconsShared = ExtraIconsShared

function ExtraIconsShared.EnsureItemStacks(profile)
    local extraIcons = profile.extraIcons
    extraIcons.itemStacks = extraIcons.itemStacks or { nextId = 1, order = {}, byId = {} }
    local itemStacks = extraIcons.itemStacks
    itemStacks.order = itemStacks.order or {}
    itemStacks.byId = itemStacks.byId or {}
    itemStacks.nextId = itemStacks.nextId or 1
    return itemStacks
end

function ExtraIconsShared.GetFirstStackIdAlphabetically(itemStacks)
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

function ExtraIconsShared.ResolveSelectedStackId(itemStacks, selectedStackId)
    if selectedStackId and itemStacks.byId[selectedStackId] then
        return selectedStackId
    end
    return ExtraIconsShared.GetFirstStackIdAlphabetically(itemStacks)
end

function ExtraIconsShared.BuildItemStackValues(itemStacks)
    local values = {}
    for _, stackId in ipairs(itemStacks.order) do
        local itemStack = itemStacks.byId[stackId]
        if itemStack then
            values[tostring(stackId)] = itemStack.name
        end
    end
    return values
end

function ExtraIconsShared.GetItemIdFromEntry(entry)
    return type(entry) == "table" and (entry.itemID or entry.itemId) or entry
end

function ExtraIconsShared.ParseSingleId(text)
    if not text or text == "" then
        return nil
    end
    local num = tonumber(text)
    if not num or num <= 0 or num ~= math.floor(num) then
        return nil
    end
    return num
end

function ExtraIconsShared.RequestItemLoad(pendingItemLoads, itemId)
    pendingItemLoads[itemId] = true
    C_Item.RequestLoadItemDataByID(itemId)
end

function ExtraIconsShared.EnsureItemLoadFrame(owner, events, onEvent)
    assert(type(owner) == "table", "ExtraIconsShared.EnsureItemLoadFrame requires owner")
    assert(type(events) == "table", "ExtraIconsShared.EnsureItemLoadFrame requires events")
    assert(type(onEvent) == "function", "ExtraIconsShared.EnsureItemLoadFrame requires onEvent")

    local itemLoadFrame = owner._itemLoadFrame
    if not itemLoadFrame then
        itemLoadFrame = CreateFrame("Frame")
        owner._itemLoadFrame = itemLoadFrame
    end
    if itemLoadFrame._ecmHooked then
        return
    end

    for _, event in ipairs(events) do
        itemLoadFrame:RegisterEvent(event)
    end
    itemLoadFrame:SetScript("OnEvent", onEvent)
    itemLoadFrame._ecmHooked = true
end

function ExtraIconsShared.GetItemDisplayName(itemId, pendingItemLoads)
    if not itemId then
        return nil
    end

    local name = C_Item.GetItemNameByID(itemId)
    if name then
        pendingItemLoads[itemId] = nil
        return name
    end

    if C_Item.DoesItemExistByID(itemId) then
        ExtraIconsShared.RequestItemLoad(pendingItemLoads, itemId)
        return L["EXTRA_ICONS_ITEM_LOADING"]
    end

    return "Item " .. tostring(itemId)
end
