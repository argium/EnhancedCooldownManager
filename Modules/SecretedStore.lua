-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local SecretedStore = {}
ns.SecretedStore = SecretedStore

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local _callbacksRegistered = false
local _activeProfile = nil

local function ResolveActiveProfile()
    if _activeProfile then
        return _activeProfile
    end

    local addon = ns.Addon
    local db = addon and addon.db
    _activeProfile = db and db.profile or nil
    return _activeProfile
end

local function CountEntries(map)
    if type(map) ~= "table" then
        return 0
    end

    local count = 0
    for _ in pairs(map) do
        count = count + 1
    end
    return count
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function SecretedStore.GetProfileRoot()
    return ResolveActiveProfile()
end

function SecretedStore.OnProfileChanged()
    _activeProfile = nil
    return ResolveActiveProfile()
end

function SecretedStore.RegisterProfileCallbacks(db)
    if _callbacksRegistered or not db or type(db.RegisterCallback) ~= "function" then
        SecretedStore.OnProfileChanged()
        return
    end

    db:RegisterCallback(SecretedStore, "OnProfileChanged", "OnProfileChanged")
    db:RegisterCallback(SecretedStore, "OnProfileCopied", "OnProfileChanged")
    db:RegisterCallback(SecretedStore, "OnProfileReset", "OnProfileChanged")
    _callbacksRegistered = true

    SecretedStore.OnProfileChanged()
end

---@param pathSegments string[]
---@param createMissing boolean|nil
---@return any
function SecretedStore.GetPath(pathSegments, createMissing)
    local profile = SecretedStore.GetProfileRoot()
    if type(profile) ~= "table" then
        return nil
    end

    if type(pathSegments) ~= "table" or #pathSegments == 0 then
        return profile
    end

    local cursor = profile
    for i = 1, #pathSegments do
        local key = pathSegments[i]
        local value = cursor[key]
        local isLeaf = i == #pathSegments

        if value == nil then
            if not createMissing then
                return nil
            end
            value = {}
            cursor[key] = value
        end

        if isLeaf then
            return value
        end

        if type(value) ~= "table" then
            if not createMissing then
                return nil
            end
            value = {}
            cursor[key] = value
        end

        cursor = value
    end

    return cursor
end

---@param pathSegments string[]
---@param value any
---@return boolean
function SecretedStore.SetPath(pathSegments, value)
    if type(pathSegments) ~= "table" or #pathSegments == 0 then
        return false
    end

    if #pathSegments == 1 then
        local root = SecretedStore.GetProfileRoot()
        if type(root) ~= "table" then
            return false
        end
        root[pathSegments[1]] = value
        return true
    end

    local parentPath = {}
    for i = 1, #pathSegments - 1 do
        parentPath[i] = pathSegments[i]
    end

    local parent = SecretedStore.GetPath(parentPath, true)
    if type(parent) ~= "table" then
        return false
    end

    parent[pathSegments[#pathSegments]] = value
    return true
end

function SecretedStore.IsSecretValue(v)
    return type(issecretvalue) == "function" and issecretvalue(v)
end

function SecretedStore.IsSecretTable(v)
    return type(issecrettable) == "function" and issecrettable(v)
end

function SecretedStore.CanAccessValue(v)
    return type(canaccessvalue) == "function" and canaccessvalue(v)
end

function SecretedStore.CanAccessTable(v)
    return type(canaccesstable) == "function" and canaccesstable(v)
end

---@param raw any
---@param opts table|nil
---@return string|nil
function SecretedStore.NormalizeString(raw, opts)
    if SecretedStore.IsSecretValue(raw) then
        return nil
    end

    if type(raw) ~= "string" then
        return nil
    end

    local out = raw
    if opts and opts.trim then
        out = strtrim(out)
    end

    local emptyToNil = not opts or opts.emptyToNil ~= false
    if emptyToNil and out == "" then
        return nil
    end

    return out
end

---@param raw any
---@param opts table|nil
---@return number|nil
function SecretedStore.NormalizeNumber(raw, opts)
    if SecretedStore.IsSecretValue(raw) then
        return nil
    end

    if type(raw) ~= "number" then
        return nil
    end

    if opts and opts.integer and raw ~= math.floor(raw) then
        return nil
    end

    if opts and opts.min and raw < opts.min then
        return nil
    end

    if opts and opts.max and raw > opts.max then
        return nil
    end

    return raw
end

---@param record any
---@param fieldSpecs table<string, table>
---@return table
function SecretedStore.NormalizeRecord(record, fieldSpecs)
    if SecretedStore.IsSecretTable(record) then
        return {}
    end

    if type(record) ~= "table" then
        return {}
    end

    local out = {}
    for outKey, spec in pairs(fieldSpecs or {}) do
        local sourceKey = spec.sourceKey or outKey
        local raw = record[sourceKey]

        if spec.valueType == "string" then
            out[outKey] = SecretedStore.NormalizeString(raw, spec)
        elseif spec.valueType == "number" then
            out[outKey] = SecretedStore.NormalizeNumber(raw, spec)
        end
    end

    return out
end

---@param oldA table|nil
---@param newA table|nil
---@param oldB table|nil
---@param newB table|nil
---@param comparer fun(oldValue:any, newValue:any, index:any, oldB:table|nil, newB:table|nil):boolean|nil
---@return boolean
function SecretedStore.HasIndexedMapsChanged(oldA, newA, oldB, newB, comparer)
    if type(oldA) ~= "table" then
        return true
    end

    local resolvedNewA = type(newA) == "table" and newA or {}
    if CountEntries(oldA) ~= CountEntries(resolvedNewA) then
        return true
    end

    for index, newValue in pairs(resolvedNewA) do
        local oldValue = oldA[index]
        if oldValue == nil then
            return true
        end

        local equivalent = nil
        if type(comparer) == "function" then
            equivalent = comparer(oldValue, newValue, index, oldB, newB)
        else
            equivalent = oldValue == newValue
        end

        if not equivalent then
            return true
        end

        local oldSecond = type(oldB) == "table" and oldB[index] or nil
        local newSecond = type(newB) == "table" and newB[index] or nil
        if oldSecond ~= newSecond then
            return true
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

-- Profile callback registration is triggered from ECM:OnInitialize after AceDB is created.
