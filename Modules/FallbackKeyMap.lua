-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0
--
-- FallbackKeyMap: A reusable dual-key, scope-aware map.
--
-- Each logical entry can be stored under a primary key (e.g. spell name)
-- and/or a fallback key (e.g. texture file ID).  The two key spaces are
-- kept in independent tables so they can be enumerated separately.
-- Every write is timestamped so that conflicts (the same logical entry
-- written under both keys at different times) can be resolved
-- automatically: the most-recently-written value wins.
--
-- The consumer provides:
--   scopeFn()        → returns { byPrimary = {}, byFallback = {} }
--   validateKey(k)   → returns k if it is a valid, non-secret value; nil otherwise
--
-- Reconciliation happens:
--   • Lazily on every Get / Set (when both keys are known)
--   • Eagerly via Reconcile(primaryKey, fallbackKey) or ReconcileAll(pairs)

local _, ns = ...

local C = ns.Constants

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Wraps a value with a write-timestamp.
---@param value any
---@return table { value = any, t = number }
local function stamp(value)
    return { value = value, t = time() }
end

--- Returns the underlying value from a stamped entry, or nil.
local function unwrap(entry)
    if type(entry) == "table" and entry.value ~= nil then
        return entry.value
    end
    return nil
end

--- Returns the timestamp from a stamped entry, or 0.
local function ts(entry)
    return (type(entry) == "table" and type(entry.t) == "number") and entry.t or 0
end

---------------------------------------------------------------------------
-- FallbackKeyMap
---------------------------------------------------------------------------

---@class FallbackKeyMap
---@field _scopeFn fun(): table
---@field _validateKey fun(k: any): any|nil
local FallbackKeyMap = {}
FallbackKeyMap.__index = FallbackKeyMap

--- Creates a new FallbackKeyMap.
---@param scopeFn fun(): { byPrimary: table, byFallback: table }  Returns the storage tables for the current scope.
---@param validateKey fun(k: any): any|nil  Returns k when valid; nil when the key should be rejected (nil, secret, wrong type).
---@return FallbackKeyMap
function FallbackKeyMap.New(scopeFn, validateKey)
    ECM_debug_assert(type(scopeFn) == "function", "FallbackKeyMap.New: scopeFn must be a function")
    ECM_debug_assert(type(validateKey) == "function", "FallbackKeyMap.New: validateKey must be a function")

    local self = setmetatable({}, FallbackKeyMap)
    self._scopeFn = scopeFn
    self._validateKey = validateKey
    return self
end

--- Returns the two storage sub-tables for the current scope, or nil.
---@return table|nil byPrimary
---@return table|nil byFallback
function FallbackKeyMap:_tables()
    local scope = self._scopeFn()
    if type(scope) ~= "table" then
        return nil, nil
    end
    return scope.byPrimary, scope.byFallback
end

--- Reconciles a single primary/fallback pair.  Most-recently-written wins,
--- and the losing entry is deleted.  If only the fallback entry exists and
--- the primary key is now available, the entry is migrated to primary.
---
---@param primaryKey any|nil  Validated primary key (may still be nil).
---@param fallbackKey any|nil  Validated fallback key (may still be nil).
---@return boolean changed  True if any entry was migrated or deleted.
function FallbackKeyMap:Reconcile(primaryKey, fallbackKey)
    primaryKey = self._validateKey(primaryKey)
    fallbackKey = self._validateKey(fallbackKey)

    if not primaryKey or not fallbackKey then
        return false
    end

    local byPrimary, byFallback = self:_tables()
    if not byPrimary or not byFallback then
        return false
    end

    local pEntry = byPrimary[primaryKey]
    local fEntry = byFallback[fallbackKey]

    if not pEntry and not fEntry then
        return false
    end

    -- Only fallback exists → migrate to primary.
    if not pEntry and fEntry then
        byPrimary[primaryKey] = fEntry
        byFallback[fallbackKey] = nil
        ECM_log(C.SYS.SpellColors, "FallbackKeyMap", "Reconcile - migrated fallback to primary", {
            primaryKey = primaryKey,
            fallbackKey = fallbackKey,
        })
        return true
    end

    -- Only primary exists → nothing to do.
    if pEntry and not fEntry then
        return false
    end

    -- Both exist → most-recently-written wins.  Keep under primary, delete fallback.
    if ts(fEntry) > ts(pEntry) then
        byPrimary[primaryKey] = fEntry
    end
    byFallback[fallbackKey] = nil

    ECM_log(C.SYS.SpellColors, "FallbackKeyMap", "Reconcile - resolved conflict", {
        primaryKey = primaryKey,
        fallbackKey = fallbackKey,
        winner = ts(fEntry) > ts(pEntry) and "fallback" or "primary",
    })
    return true
end

--- Reconciles a batch of { primaryKey, fallbackKey } pairs.
---@param pairs table[]  Array of { [1]=primaryKey, [2]=fallbackKey }.
---@return number changed  Count of entries that were migrated or resolved.
function FallbackKeyMap:ReconcileAll(pairs)
    local changed = 0
    for _, pair in ipairs(pairs) do
        if self:Reconcile(pair[1], pair[2]) then
            changed = changed + 1
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Get
---------------------------------------------------------------------------

--- Looks up a value by primary key first, then fallback key.
--- Reconciles if both keys are present.
---@param primaryKey any|nil
---@param fallbackKey any|nil
---@return any|nil value  The stored value, or nil.
function FallbackKeyMap:Get(primaryKey, fallbackKey)
    primaryKey = self._validateKey(primaryKey)
    fallbackKey = self._validateKey(fallbackKey)

    local byPrimary, byFallback = self:_tables()
    if not byPrimary and not byFallback then
        return nil
    end

    -- Reconcile if both keys are available.
    if primaryKey and fallbackKey then
        self:Reconcile(primaryKey, fallbackKey)
    end

    -- After reconciliation, prefer primary.
    if primaryKey and byPrimary then
        local entry = byPrimary[primaryKey]
        if entry then
            return unwrap(entry)
        end
    end

    if fallbackKey and byFallback then
        local entry = byFallback[fallbackKey]
        if entry then
            return unwrap(entry)
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Set
---------------------------------------------------------------------------

--- Stores a value under the primary key if available, otherwise fallback.
--- If writing to primary and a fallback entry exists, the fallback is deleted.
---@param primaryKey any|nil
---@param fallbackKey any|nil
---@param value any  The value to store.
function FallbackKeyMap:Set(primaryKey, fallbackKey, value)
    primaryKey = self._validateKey(primaryKey)
    fallbackKey = self._validateKey(fallbackKey)

    local byPrimary, byFallback = self:_tables()
    if not byPrimary and not byFallback then
        return
    end

    local entry = stamp(value)

    if primaryKey and byPrimary then
        byPrimary[primaryKey] = entry
        -- Clean up fallback when primary is known.
        if fallbackKey and byFallback then
            byFallback[fallbackKey] = nil
        end
        return
    end

    if fallbackKey and byFallback then
        byFallback[fallbackKey] = entry
    end
end

---------------------------------------------------------------------------
-- Remove
---------------------------------------------------------------------------

--- Removes entries from both maps.
---@param primaryKey any|nil
---@param fallbackKey any|nil
---@return boolean primaryCleared
---@return boolean fallbackCleared
function FallbackKeyMap:Remove(primaryKey, fallbackKey)
    primaryKey = self._validateKey(primaryKey)
    fallbackKey = self._validateKey(fallbackKey)

    local byPrimary, byFallback = self:_tables()
    local pCleared = false
    local fCleared = false

    if primaryKey and byPrimary and byPrimary[primaryKey] ~= nil then
        byPrimary[primaryKey] = nil
        pCleared = true
    end

    if fallbackKey and byFallback and byFallback[fallbackKey] ~= nil then
        byFallback[fallbackKey] = nil
        fCleared = true
    end

    return pCleared, fCleared
end

---------------------------------------------------------------------------
-- GetAll
---------------------------------------------------------------------------

--- Returns a merged view of all entries (primary wins for display purposes).
--- Values are unwrapped; the returned table is { [key] = value, ... }.
---@return table<any, any>
function FallbackKeyMap:GetAll()
    local byPrimary, byFallback = self:_tables()
    local result = {}

    if byFallback then
        for k, entry in pairs(byFallback) do
            local v = unwrap(entry)
            if v ~= nil then
                result[k] = v
            end
        end
    end

    -- Primary overwrites fallback in the merged view.
    if byPrimary then
        for k, entry in pairs(byPrimary) do
            local v = unwrap(entry)
            if v ~= nil then
                result[k] = v
            end
        end
    end

    return result
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

ns.FallbackKeyMap = FallbackKeyMap
