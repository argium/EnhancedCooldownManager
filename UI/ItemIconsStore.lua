-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local VIEWER_KEYS = { "essential", "utility" }

local function makeEntryKey(entryType, id)
    return entryType .. ":" .. id
end

local store = {}

function store.GetEntries(viewerKey)
    local cfg = mod.db.profile.itemIcons
    return cfg and cfg[viewerKey] or {}
end

function store.SetEntries(viewerKey, entries)
    local profile = mod.db.profile
    if not profile.itemIcons then
        profile.itemIcons = { essential = {}, utility = {} }
    end
    profile.itemIcons[viewerKey] = entries
end

function store.AddEntry(viewerKey, entryType, id)
    local entries = store.GetEntries(viewerKey)
    local key = makeEntryKey(entryType, id)
    for _, entry in ipairs(entries) do
        if makeEntryKey(entry.type, entry.id) == key then
            return false
        end
    end
    entries[#entries + 1] = { type = entryType, id = id }
    store.SetEntries(viewerKey, entries)
    return true
end

function store.RemoveEntry(viewerKey, index)
    local entries = store.GetEntries(viewerKey)
    table.remove(entries, index)
    store.SetEntries(viewerKey, entries)
end

function store.MoveEntry(viewerKey, fromIndex, toIndex)
    local entries = store.GetEntries(viewerKey)
    if fromIndex < 1 or fromIndex > #entries or toIndex < 1 or toIndex > #entries then
        return
    end
    local entry = table.remove(entries, fromIndex)
    table.insert(entries, toIndex, entry)
    store.SetEntries(viewerKey, entries)
end

function store.TransferEntry(fromViewerKey, fromIndex, toViewerKey, toIndex)
    local fromEntries = store.GetEntries(fromViewerKey)
    if fromIndex < 1 or fromIndex > #fromEntries then
        return
    end

    local entry = table.remove(fromEntries, fromIndex)
    store.SetEntries(fromViewerKey, fromEntries)

    local toEntries = store.GetEntries(toViewerKey)
    toIndex = math.max(1, math.min(toIndex, #toEntries + 1))
    table.insert(toEntries, toIndex, entry)
    store.SetEntries(toViewerKey, toEntries)
end

function store.RestoreDefaults(viewerKey, defaultEntries)
    local defaultKeys = {}
    for _, entry in ipairs(defaultEntries) do
        defaultKeys[makeEntryKey(entry.type, entry.id)] = true
    end

    local result = {}
    for _, entry in ipairs(defaultEntries) do
        result[#result + 1] = { type = entry.type, id = entry.id }
    end
    for _, entry in ipairs(store.GetEntries(viewerKey)) do
        if not defaultKeys[makeEntryKey(entry.type, entry.id)] then
            result[#result + 1] = entry
        end
    end

    store.SetEntries(viewerKey, result)
end

function store.HasEntry(entryType, id)
    local key = makeEntryKey(entryType, id)
    for _, viewerKey in ipairs(VIEWER_KEYS) do
        for _, entry in ipairs(store.GetEntries(viewerKey)) do
            if makeEntryKey(entry.type, entry.id) == key then
                return true
            end
        end
    end
    return false
end

function store.HasAllDefaults(defaultEntries)
    local lookup = {}
    for _, viewerKey in ipairs(VIEWER_KEYS) do
        for _, entry in ipairs(store.GetEntries(viewerKey)) do
            lookup[makeEntryKey(entry.type, entry.id)] = true
        end
    end
    for _, entry in ipairs(defaultEntries) do
        if not lookup[makeEntryKey(entry.type, entry.id)] then
            return false
        end
    end
    return true
end

ECM.ItemIconsStore = store
