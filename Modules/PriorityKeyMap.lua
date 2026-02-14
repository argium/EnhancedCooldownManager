-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- PriorityKeyMap: A reusable N-key, scope-aware map with priority-ordered
-- lookup.
--
-- Each logical entry can be stored under an arbitrary number of keys
-- (e.g. spell name, spell ID, cooldown ID, texture file ID).  The key
-- spaces are kept in independent tables — one per tier — so they can be
-- enumerated separately.  Every write is timestamped so that conflicts
-- (the same logical entry written under different keys at different
-- times) can be resolved automatically: the most-recently-written value
-- wins.
--
-- The consumer provides:
--   keyDefs       → ordered array of scope field names, highest-priority first
--                   e.g. {"byName", "bySpellID", "byCooldownID", "byTexture"}
--   scopeFn()     → returns a table whose fields match keyDefs
--   validateKey(k)→ returns k if it is a valid, non-secret value; nil otherwise
--
-- Reconciliation happens:
--   • Lazily on every Get / Set (when multiple keys are known)
--   • Eagerly via Reconcile(keys) or ReconcileAll(keysList)

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
-- PriorityKeyMap
---------------------------------------------------------------------------

---@class PriorityKeyMap
---@field _keyDefs string[]
---@field _scopeFn fun(): table
---@field _validateKey fun(k: any): any|nil
local PriorityKeyMap = {}
PriorityKeyMap.__index = PriorityKeyMap

--- Creates a new PriorityKeyMap.
---@param keyDefs string[]  Ordered array of scope field names, highest-priority first.
---@param scopeFn fun(): table  Returns the storage tables for the current scope, keyed by keyDefs values.
---@param validateKey fun(k: any): any|nil  Returns k when valid; nil when the key should be rejected (nil, secret, wrong type).
---@return PriorityKeyMap
function PriorityKeyMap.New(keyDefs, scopeFn, validateKey)
    ECM_debug_assert(type(keyDefs) == "table" and #keyDefs >= 2, "PriorityKeyMap.New: keyDefs must be an array with at least 2 entries")
    ECM_debug_assert(type(scopeFn) == "function", "PriorityKeyMap.New: scopeFn must be a function")
    ECM_debug_assert(type(validateKey) == "function", "PriorityKeyMap.New: validateKey must be a function")

    local self = setmetatable({}, PriorityKeyMap)
    self._keyDefs = keyDefs
    self._scopeFn = scopeFn
    self._validateKey = validateKey
    return self
end

--- Returns an ordered array of storage sub-tables for the current scope,
--- matching the keyDefs order.  Returns nil if the scope is unavailable.
---@return table[]|nil tables  Array of sub-tables (same length as keyDefs), or nil.
function PriorityKeyMap:_tables()
    local scope = self._scopeFn()
    if type(scope) ~= "table" then
        return nil
    end

    local result = {}
    for i, def in ipairs(self._keyDefs) do
        result[i] = scope[def]
    end
    return result
end

--- Reconciles all known key pairs so every key space stays in sync.
--- For every pair of valid keys (i, j) where both have sub-tables:
--- if only one entry exists, it is copied to the other; if both exist
--- with different timestamps, the most-recently-written value wins.
---
---@param keys table  Array of key values, one per keyDefs tier (may contain nils).
---@return boolean changed  True if any entry was migrated or unified.
function PriorityKeyMap:Reconcile(keys)
    local tables = self:_tables()
    if not tables then
        return false
    end

    -- Validate all keys up front.  Use a numeric loop instead of ipairs
    -- so that nil holes (e.g. a missing spellName) don't short-circuit
    -- iteration and prevent later keys from being validated.
    local vkeys = {}
    local validCount = 0
    for i = 1, #self._keyDefs do
        vkeys[i] = self._validateKey(keys[i])
        if vkeys[i] then
            validCount = validCount + 1
        end
    end

    -- Need at least two valid keys to reconcile.
    if validCount < 2 then
        return false
    end

    local changed = false

    -- Find the winning entry across all valid tiers (most recent timestamp).
    local winner = nil
    local winnerTs = -1
    for i = 1, #self._keyDefs do
        if vkeys[i] and tables[i] then
            local entry = tables[i][vkeys[i]]
            if entry then
                local t = ts(entry)
                if t > winnerTs then
                    winner = entry
                    winnerTs = t
                end
            end
        end
    end

    if not winner then
        return false
    end

    -- Propagate the winner to every valid tier that is missing or outdated.
    for i = 1, #self._keyDefs do
        if vkeys[i] and tables[i] then
            local existing = tables[i][vkeys[i]]
            if not existing then
                tables[i][vkeys[i]] = winner
                changed = true
                ECM_log(ECM.Constants.SYS.SpellColors, "PriorityKeyMap",
                    "Reconcile - copied to " .. self._keyDefs[i] .. " key " .. ECM_tostring(vkeys[i]),
                    { value = unwrap(winner) })
            elseif ts(existing) < winnerTs then
                tables[i][vkeys[i]] = winner
                changed = true
                ECM_log(ECM.Constants.SYS.SpellColors, "PriorityKeyMap",
                    "Reconcile - unified " .. self._keyDefs[i] .. " key " .. ECM_tostring(vkeys[i]) .. " to most recent",
                    { value = unwrap(winner) })
            end
        end
    end

    return changed
end

--- Reconciles a batch of key arrays.
---@param keysList table[]  Array of key arrays (each array has one entry per tier).
---@return number changed  Count of entries that were migrated or resolved.
function PriorityKeyMap:ReconcileAll(keysList)
    local changed = 0
    for _, keys in ipairs(keysList) do
        if self:Reconcile(keys) then
            changed = changed + 1
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Get
---------------------------------------------------------------------------

--- Looks up a value by trying keys in priority order (index 1 first).
--- Reconciles if multiple keys are available before lookup.
---@param keys table  Array of key values, one per keyDefs tier (may contain nils).
---@return any|nil value  The stored value, or nil.
function PriorityKeyMap:Get(keys)
    local tables = self:_tables()
    if not tables then
        return nil
    end

    -- Validate keys.  Use a numeric loop instead of ipairs so that nil
    -- holes don't prevent later keys from being checked.
    local vkeys = {}
    local validCount = 0
    for i = 1, #self._keyDefs do
        vkeys[i] = self._validateKey(keys[i])
        if vkeys[i] then
            validCount = validCount + 1
        end
    end

    -- Reconcile if multiple keys are available.
    if validCount >= 2 then
        self:Reconcile(keys)
    end

    -- Look up in priority order (index 1 = highest priority).
    for i = 1, #self._keyDefs do
        if vkeys[i] and tables[i] then
            local entry = tables[i][vkeys[i]]
            if entry then
                return unwrap(entry)
            end
        end
    end

    return nil
end

---------------------------------------------------------------------------
-- Set
---------------------------------------------------------------------------

--- Stores a value under all valid keys so that any single non-secret key
--- can retrieve the color later.
---@param keys table  Array of key values, one per keyDefs tier (may contain nils).
---@param value any  The value to store.
function PriorityKeyMap:Set(keys, value)
    local tables = self:_tables()
    if not tables then
        return
    end

    local entry = stamp(value)

    for i = 1, #self._keyDefs do
        local k = self._validateKey(keys[i])
        if k and tables[i] then
            tables[i][k] = entry
        end
    end

    local parts = {}
    for i = 1, #self._keyDefs do
        parts[i] = ECM_tostring(keys[i])
    end
    ECM_log(ECM.Constants.SYS.SpellColors, "PriorityKeyMap", "Set (" .. table.concat(parts, ",") .. ") = " .. ECM_tostring(value))
end

---------------------------------------------------------------------------
-- Remove
---------------------------------------------------------------------------

--- Removes entries from all key tier tables.
---@param keys table  Array of key values, one per keyDefs tier (may contain nils).
---@return boolean ...  One boolean per tier indicating whether that tier was cleared.
function PriorityKeyMap:Remove(keys)
    local tables = self:_tables()

    local cleared = {}
    for i = 1, #self._keyDefs do
        cleared[i] = false
        local k = self._validateKey(keys[i])
        if k and tables and tables[i] and tables[i][k] ~= nil then
            tables[i][k] = nil
            cleared[i] = true
        end
    end

    return unpack(cleared)
end

---------------------------------------------------------------------------
-- GetAll
---------------------------------------------------------------------------

--- Returns a merged view of all entries (higher-priority tiers win for
--- display purposes).  Values are unwrapped; the returned table is
--- { [key] = value, ... }.
---@return table<any, any>
function PriorityKeyMap:GetAll()
    local tables = self:_tables()
    local result = {}

    if not tables then
        return result
    end

    -- Iterate from lowest priority to highest so higher-priority overwrites.
    for i = #self._keyDefs, 1, -1 do
        local tbl = tables[i]
        if tbl then
            for k, entry in pairs(tbl) do
                local v = unwrap(entry)
                if v ~= nil then
                    result[k] = v
                end
            end
        end
    end

    return result
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------

ECM.PriorityKeyMap = PriorityKeyMap
