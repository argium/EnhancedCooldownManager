-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- SpellColors: Key construction, normalization, and matching for spell-color
-- entries. Backed by a multi-tier key system where each spell can be identified
-- by name, spell ID, cooldown ID, or texture file ID. Includes persistence and
-- public APIs for per-spell color customization.

local _, ns = ...

local C = ns.Constants

---@class ECM_SpellColorStore
---@field _scope string
---@field _configAccessor (fun(): table|nil)|nil
---@field _discoveredKeys ECM_SpellColorKey[]
---@field _SetConfigAccessor fun(self: ECM_SpellColorStore, accessor: fun(): table|nil)

local SpellColors = {}
ns.SpellColors = SpellColors
local SpellColorStore = {}
SpellColorStore.__index = SpellColorStore
local FrameUtil = ns.FrameUtil
local DEFAULT_SCOPE = C.SCOPE_BUFFBARS
local _storesByScope = {}

local KEY_DEFS = { "byName", "bySpellID", "byCooldownID", "byTexture" }
local KEY_TYPE_TO_STORE = {
    byName = "spellName",
    bySpellID = "spellID",
    byCooldownID = "cooldownID",
    byTexture = "textureFileID",
}
local KEY_TYPES = {
    spellName = true,
    spellID = true,
    cooldownID = true,
    textureFileID = true,
}

local function normalizeScope(scope)
    return type(scope) == "string" and scope or DEFAULT_SCOPE
end

---------------------------------------------------------------------------
-- Key validation
---------------------------------------------------------------------------

--- Returns k if it is a valid, non-secret string or number; nil otherwise.
local function validateKey(k)
    local t = type(k)
    if (t == "string" or t == "number") and not issecretvalue(k) then
        return k
    end
    return nil
end

---------------------------------------------------------------------------
-- SpellColorKeyType class
---------------------------------------------------------------------------

---@class ECM_SpellColorKeyType : ECM_SpellColorKey
local SpellColorKeyType = {}
SpellColorKeyType.__index = SpellColorKeyType

---@class ECM_SpellColorKey
---@field keyType "spellName"|"spellID"|"cooldownID"|"textureFileID"
---@field primaryKey string|number
---@field spellName string|nil
---@field spellID number|nil
---@field cooldownID number|nil
---@field textureFileID number|nil

---@param spellName string|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureId number|nil
---@return string|number|nil primaryKey
---@return "spellName"|"spellID"|"cooldownID"|"textureFileID"|nil keyType
local function selectPrimaryKey(spellName, spellID, cooldownID, textureId)
    if spellName then
        return spellName, "spellName"
    end
    if spellID then
        return spellID, "spellID"
    end
    if cooldownID then
        return cooldownID, "cooldownID"
    end
    if textureId then
        return textureId, "textureFileID"
    end
    return nil, nil
end

---@param spellName string|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureFileID number|nil
---@param preferredType "spellName"|"spellID"|"cooldownID"|"textureFileID"|nil
---@return ECM_SpellColorKey|nil
local function buildKey(spellName, spellID, cooldownID, textureFileID, preferredType)
    local keyType = preferredType
    local primaryKey
    if keyType == "spellName" then
        primaryKey = spellName
    elseif keyType == "spellID" then
        primaryKey = spellID
    elseif keyType == "cooldownID" then
        primaryKey = cooldownID
    elseif keyType == "textureFileID" then
        primaryKey = textureFileID
    end
    if not primaryKey then
        primaryKey, keyType = selectPrimaryKey(spellName, spellID, cooldownID, textureFileID)
    end
    if not (keyType and primaryKey) then
        return nil
    end

    return setmetatable({
        keyType = keyType,
        primaryKey = primaryKey,
        spellName = spellName,
        spellID = spellID,
        cooldownID = cooldownID,
        textureFileID = textureFileID,
    }, SpellColorKeyType)
end

---@param key ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
local function normalizeKey(key)
    if type(key) ~= "table" then
        return nil
    end

    local spellName = validateKey(key.spellName)
    local spellID = validateKey(key.spellID)
    local cooldownID = validateKey(key.cooldownID)
    local textureFileID = validateKey(key.textureFileID or key.textureId)
    local keyType = KEY_TYPES[key.keyType] and key.keyType or nil
    local primaryKey = validateKey(key.primaryKey)

    if keyType == "spellName" and type(primaryKey) == "string" and not spellName then
        spellName = primaryKey
    elseif keyType == "spellID" and type(primaryKey) == "number" and not spellID then
        spellID = primaryKey
    elseif keyType == "cooldownID" and type(primaryKey) == "number" and not cooldownID then
        cooldownID = primaryKey
    elseif keyType == "textureFileID" and type(primaryKey) == "number" and not textureFileID then
        textureFileID = primaryKey
    end

    return buildKey(spellName, spellID, cooldownID, textureFileID, keyType)
end

---@param a ECM_SpellColorKey|nil
---@param b ECM_SpellColorKey|nil
---@return boolean
local function keysMatch(a, b)
    if not (a and b) then
        return false
    end

    if a.spellName and b.spellName and a.spellName == b.spellName then
        return true
    end
    if a.spellID and b.spellID and a.spellID == b.spellID then
        return true
    end
    if a.cooldownID and b.cooldownID and a.cooldownID == b.cooldownID then
        return true
    end

    local aTextureOnly = (a.spellName == nil and a.spellID == nil and a.cooldownID == nil)
    local bTextureOnly = (b.spellName == nil and b.spellID == nil and b.cooldownID == nil)
    if
        (aTextureOnly or bTextureOnly)
        and a.textureFileID
        and b.textureFileID
        and a.textureFileID == b.textureFileID
    then
        return true
    end

    return false
end

---@param base ECM_SpellColorKey|nil
---@param other ECM_SpellColorKey|nil
---@return ECM_SpellColorKey|nil
local function mergeKeys(base, other)
    if base == nil then
        return other
    end
    if other == nil then
        return base
    end
    if not keysMatch(base, other) then
        return nil
    end

    return buildKey(
        base.spellName or other.spellName,
        base.spellID or other.spellID,
        base.cooldownID or other.cooldownID,
        base.textureFileID or other.textureFileID,
        nil
    )
end

---------------------------------------------------------------------------
-- SpellColorKeyType methods
---------------------------------------------------------------------------

---@param other ECM_SpellColorKey|table|nil
---@return boolean
function SpellColorKeyType:Matches(other)
    return keysMatch(self, normalizeKey(other))
end

---@param other ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
function SpellColorKeyType:Merge(other)
    return mergeKeys(self, normalizeKey(other))
end

function SpellColorKeyType:ToString()
    return string.format(
        "SpellColorKey{type=%s, spellName=%s, spellID=%s, cooldownID=%s, textureFileID=%s}",
        tostring(self.keyType),
        tostring(self.spellName),
        tostring(self.spellID),
        tostring(self.cooldownID),
        tostring(self.textureFileID)
    )
end

function SpellColorKeyType:ToArray()
    return { self.spellName, self.spellID, self.cooldownID, self.textureFileID }
end

---------------------------------------------------------------------------
-- Public key API
---------------------------------------------------------------------------

--- Creates a normalized spell-color key from identifying values.
--- Input values are validated and secret values are dropped.
---@param spellName string|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureFileID number|nil
---@return ECM_SpellColorKey|nil
function SpellColors.MakeKey(spellName, spellID, cooldownID, textureFileID)
    return buildKey(
        validateKey(spellName),
        validateKey(spellID),
        validateKey(cooldownID),
        validateKey(textureFileID),
        nil
    )
end

--- Normalizes a key payload into an opaque spell-color key object.
---@param key ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
function SpellColors.NormalizeKey(key)
    return normalizeKey(key)
end

--- Returns true when two keys identify the same logical spell-color entry.
---@param left ECM_SpellColorKey|table|nil
---@param right ECM_SpellColorKey|table|nil
---@return boolean
function SpellColors.KeysMatch(left, right)
    return keysMatch(normalizeKey(left), normalizeKey(right))
end

--- Merges identifiers from matching keys into a single normalized key.
--- Returns nil when both keys are valid but identify different entries.
---@param base ECM_SpellColorKey|table|nil
---@param other ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
function SpellColors.MergeKeys(base, other)
    return mergeKeys(normalizeKey(base), normalizeKey(other))
end

-- WoW uses Lua 5.1 (global `unpack`), busted tests use Lua 5.3+ (`table.unpack`).
local unpack = _G.unpack or table.unpack

---------------------------------------------------------------------------
-- Entry metadata helpers
---------------------------------------------------------------------------

local LEGACY_METADATA_FIELDS =
    { "keyType", "primaryKey", "spellName", "spellID", "cooldownID", "textureId", "textureFileID" }

---@param entry any
---@return number
local function entryTs(entry)
    return (type(entry) == "table" and type(entry.t) == "number") and entry.t or 0
end

---@param color table|nil
---@return ECM_Color|nil
local function sanitizeColorValue(color)
    if type(color) ~= "table" then
        return nil
    end
    return { r = color.r, g = color.g, b = color.b, a = color.a or 1 }
end

---@param value table|nil
---@return boolean changed
local function scrubLegacyColorMetadata(value)
    if type(value) ~= "table" then
        return false
    end

    local changed = false
    for _, field in ipairs(LEGACY_METADATA_FIELDS) do
        if value[field] ~= nil then
            value[field] = nil
            changed = true
        end
    end
    return changed
end

---@param normalized ECM_SpellColorKey|nil
---@return table|nil
local function buildEntryMeta(normalized)
    if not normalized then
        return nil
    end
    return {
        keyType = normalized.keyType,
        primaryKey = normalized.primaryKey,
        spellName = normalized.spellName,
        spellID = normalized.spellID,
        cooldownID = normalized.cooldownID,
        textureFileID = normalized.textureFileID,
    }
end

---@param entry table|nil
---@param tierKeyType "spellName"|"spellID"|"cooldownID"|"textureFileID"
---@param rawKey string|number|nil
---@return ECM_SpellColorKey|nil
local function buildKeyFromEntry(entry, tierKeyType, rawKey)
    if type(entry) ~= "table" or type(entry.value) ~= "table" then
        return nil
    end

    local value = entry.value
    local meta = type(entry.meta) == "table" and entry.meta or nil

    local spellName = validateKey((meta and meta.spellName) or value.spellName)
    local spellID = validateKey((meta and meta.spellID) or value.spellID)
    local cooldownID = validateKey((meta and meta.cooldownID) or value.cooldownID)
    local textureFileID =
        validateKey((meta and (meta.textureFileID or meta.textureId)) or value.textureFileID or value.textureId)
    local preferredType = ((meta and meta.keyType) or value.keyType or tierKeyType)
    if not KEY_TYPES[preferredType] then
        preferredType = tierKeyType
    end

    local validRawKey = validateKey(rawKey)
    if tierKeyType == "spellName" and type(validRawKey) == "string" then
        spellName = validRawKey
    elseif tierKeyType == "spellID" and type(validRawKey) == "number" then
        spellID = validRawKey
    elseif tierKeyType == "cooldownID" and type(validRawKey) == "number" then
        cooldownID = validRawKey
    elseif tierKeyType == "textureFileID" and type(validRawKey) == "number" then
        textureFileID = validRawKey
    end

    return buildKey(spellName, spellID, cooldownID, textureFileID, preferredType)
end

---@param entry table|nil
---@param normalized ECM_SpellColorKey|nil
---@return boolean changed
local function normalizeEntryMetadata(entry, normalized)
    if type(entry) ~= "table" or type(entry.value) ~= "table" or not normalized then
        return false
    end

    local changed = scrubLegacyColorMetadata(entry.value)
    local desired = buildEntryMeta(normalized)
    local current = type(entry.meta) == "table" and entry.meta or nil
    if
        not current
        or current.keyType ~= desired.keyType
        or current.primaryKey ~= desired.primaryKey
        or current.spellName ~= desired.spellName
        or current.spellID ~= desired.spellID
        or current.cooldownID ~= desired.cooldownID
        or current.textureFileID ~= desired.textureFileID
    then
        entry.meta = desired
        changed = true
    end
    return changed
end

---@param value table|nil
---@return boolean
local function hasLegacyColorMetadata(value)
    if type(value) ~= "table" then
        return false
    end
    for _, field in ipairs(LEGACY_METADATA_FIELDS) do
        if value[field] ~= nil then
            return true
        end
    end
    return false
end

--- Runtime cache of keys discovered from active bars during layout.
--- Merged into GetAllColorEntries so the options UI sees all visible bars
--- without reaching into BuffBars directly.
---@param store ECM_SpellColorStore
---@return ECM_SpellColorKey[]
local function getDiscoveredKeys(store)
    local discoveredKeys = store._discoveredKeys
    if not discoveredKeys then
        discoveredKeys = {}
        store._discoveredKeys = discoveredKeys
    end
    return discoveredKeys
end

---------------------------------------------------------------------------
-- Profile helpers
---------------------------------------------------------------------------

--- Returns the scope-specific default color fallback.
---@param scope string|nil
---@return ECM_Color
local function getScopeDefaultColor(scope)
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile[normalizeScope(scope)]
    local color = defaults and defaults.colors and defaults.colors.defaultColor
    return color or ns.Constants.BUFFBARS_DEFAULT_COLOR
end

--- Ensures the color storage tables exist for the current class/spec.
---@param cfg table  scope config table
---@return table|nil classSpecStores  Keyed by KEY_DEFS field names; each value is the current class/spec storage table.
local function getCurrentClassSpecStores(cfg)
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()

    if not classID or not specID then
        ns.DebugAssert(false, "SpellColors.getCurrentClassSpecStores - unable to determine player class/spec", {
            classID = classID,
            specID = specID,
        })
        return nil
    end

    local classSpecStores = {}
    for _, def in ipairs(KEY_DEFS) do
        cfg.colors[def][classID] = cfg.colors[def][classID] or {}
        cfg.colors[def][classID][specID] = cfg.colors[def][classID][specID] or {}
        classSpecStores[def] = cfg.colors[def][classID][specID]
    end
    return classSpecStores
end

--- Ensures nested tables exist for color storage.
---@param cfg table  scope config table
---@param scope string|nil
local function ensureProfileIsSetup(cfg, scope)
    if not cfg.colors then
        cfg.colors = {
            byName = {},
            bySpellID = {},
            byCooldownID = {},
            byTexture = {},
            cache = {},
            defaultColor = getScopeDefaultColor(scope),
        }
    end
    for _, def in ipairs(KEY_DEFS) do
        if type(cfg.colors[def]) ~= "table" then
            cfg.colors[def] = {}
        end
    end
    if type(cfg.colors.cache) ~= "table" then
        cfg.colors.cache = {}
    end
    if type(cfg.colors.defaultColor) ~= "table" then
        cfg.colors.defaultColor = getScopeDefaultColor(scope)
    end
end

--- Creates a spell-colour store bound to a single scope.
---@param scope string|nil
---@param configAccessor (fun(): table|nil)|nil
---@return ECM_SpellColorStore
function SpellColors.New(scope, configAccessor)
    return setmetatable({
        _scope = normalizeScope(scope),
        _configAccessor = configAccessor,
        _discoveredKeys = {},
    }, SpellColorStore)
end

--- Returns the shared spell-colour store for a scope.
---@param scope string|nil
---@return ECM_SpellColorStore
function SpellColors.Get(scope)
    local resolvedScope = normalizeScope(scope)
    local store = _storesByScope[resolvedScope]
    if not store then
        store = SpellColors.New(resolvedScope)
        _storesByScope[resolvedScope] = store
    end
    return store
end

-- Not used by production code; retained for tests that need to swap config sources after construction.
function SpellColorStore:_SetConfigAccessor(accessor)
    self._configAccessor = accessor
end

--- Returns the profile or scope config source table for a store, or nil if unavailable.
---@param store ECM_SpellColorStore
---@return table|nil source
local function configSource(store)
    local source
    if store._configAccessor then
        source = store._configAccessor()
    else
        source = ns.Addon and ns.Addon.db and ns.Addon.db.profile or nil
    end
    if type(source) == "table" and type(source.profile) == "table" then
        source = source.profile
    end
    return source
end

--- Returns the scoped config table for a store, or nil if unavailable.
---@param store ECM_SpellColorStore
---@return table|nil cfg
local function config(store)
    local resolvedScope = store._scope
    local source = configSource(store)
    local cfg

    if type(source) == "table" then
        -- Treat the requested scope table as a valid profile signal so New(scope, accessor) works when tests seed only that scope.
        local looksLikeProfile = type(source[resolvedScope]) == "table" or type(source[DEFAULT_SCOPE]) == "table"
        if looksLikeProfile then
            cfg = source[resolvedScope]
        elseif resolvedScope == DEFAULT_SCOPE then
            cfg = source
        end
    end

    if type(cfg) ~= "table" then
        ns.DebugAssert(false, "SpellColors.config - missing or invalid scope config", { scope = resolvedScope })
        return nil
    end
    ensureProfileIsSetup(cfg, resolvedScope)
    return cfg
end

---------------------------------------------------------------------------
-- Stamped entry helpers
---------------------------------------------------------------------------

--- Wraps a value with a write-timestamp.
local function stamp(value, meta)
    return { value = value, t = time(), meta = meta }
end

--- Returns the underlying value from a stamped entry, or nil.
local function unwrap(entry)
    if type(entry) == "table" and entry.value ~= nil then
        return entry.value
    end
    return nil
end

--- Returns the timestamp from a stamped entry, or 0.
local function stampTs(entry)
    return (type(entry) == "table" and type(entry.t) == "number") and entry.t or 0
end

---------------------------------------------------------------------------
-- Tier-table operations (inlined from former PriorityKeyMap)
---------------------------------------------------------------------------

--- Returns the 4 tier sub-tables for the current class/spec, or nil.
---@param store ECM_SpellColorStore
local function scopeTables(store)
    local cfg = config(store)
    if not cfg then
        return nil
    end
    return getCurrentClassSpecStores(cfg)
end

--- Validates keys, returning an array of validated keys + the count of valid ones.
local function validateKeys(keys)
    local vkeys = {}
    local validCount = 0
    for i = 1, #KEY_DEFS do
        vkeys[i] = validateKey(keys[i])
        if vkeys[i] then
            validCount = validCount + 1
        end
    end
    return vkeys, validCount
end

--- Looks up a value by trying keys in priority order (index 1 first).
---@param store ECM_SpellColorStore
local function storeGet(store, keys)
    local tables = scopeTables(store)
    if not tables then
        return nil
    end
    for i = 1, #KEY_DEFS do
        local k = validateKey(keys[i])
        if k and tables[KEY_DEFS[i]] then
            local entry = tables[KEY_DEFS[i]][k]
            if entry then
                return unwrap(entry)
            end
        end
    end
    return nil
end

--- Stores a value under all valid keys. Reuses the oldest existing stamped
--- wrapper to keep all tier references pointing to the same table.
---@param store ECM_SpellColorStore
local function storeSet(store, keys, value, meta)
    local tables = scopeTables(store)
    if not tables then
        return
    end

    local vkeys = validateKeys(keys)
    local winner, winnerTs = nil, -1
    for i = 1, #KEY_DEFS do
        local k = vkeys[i]
        if k and tables[KEY_DEFS[i]] then
            local existing = tables[KEY_DEFS[i]][k]
            if type(existing) == "table" and existing.value ~= nil then
                local t = stampTs(existing)
                if t > winnerTs then
                    winner = existing
                    winnerTs = t
                end
            end
        end
    end

    local entry = winner or stamp(value, meta)
    if winner then
        entry.value = value
        entry.t = time()
        entry.meta = meta
    end

    for i = 1, #KEY_DEFS do
        local k = vkeys[i]
        if k and tables[KEY_DEFS[i]] then
            tables[KEY_DEFS[i]][k] = entry
        end
    end
end

--- Removes entries from all tier tables.
---@param store ECM_SpellColorStore
local function storeRemove(store, keys)
    local tables = scopeTables(store)
    local cleared = {}
    for i = 1, #KEY_DEFS do
        cleared[i] = false
        local k = validateKey(keys[i])
        if k and tables and tables[KEY_DEFS[i]] and tables[KEY_DEFS[i]][k] ~= nil then
            tables[KEY_DEFS[i]][k] = nil
            cleared[i] = true
        end
    end
    return unpack(cleared)
end

--- Reconciles a single key set: finds the most-recently-written entry
--- across all tiers and propagates it to every valid tier that is missing
--- or outdated.
---@param store ECM_SpellColorStore
local function reconcile(store, keys)
    local tables = scopeTables(store)
    if not tables then
        return false
    end

    local vkeys, validCount = validateKeys(keys)
    if validCount < 2 then
        return false
    end

    -- Find the winning entry (most recent timestamp).
    local winner, winnerTs = nil, -1
    for i = 1, #KEY_DEFS do
        if vkeys[i] and tables[KEY_DEFS[i]] then
            local entry = tables[KEY_DEFS[i]][vkeys[i]]
            if entry then
                local t = stampTs(entry)
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

    -- Propagate to every valid tier that is missing or outdated.
    local changed = false
    for i = 1, #KEY_DEFS do
        if vkeys[i] and tables[KEY_DEFS[i]] then
            local existing = tables[KEY_DEFS[i]][vkeys[i]]
            if not existing or stampTs(existing) < winnerTs then
                tables[KEY_DEFS[i]][vkeys[i]] = winner
                changed = true
            end
        end
    end
    return changed
end

--- Reconciles a batch of key arrays.
---@param store ECM_SpellColorStore
local function reconcileAll(store, keysList)
    local changed = 0
    for _, keys in ipairs(keysList) do
        if reconcile(store, keys) then
            changed = changed + 1
        end
    end
    return changed
end

---@param store ECM_SpellColorStore
---@return number changed
local function repairCurrentSpecStoreMetadata(store)
    local cfg = config(store)
    if not cfg then
        return 0
    end

    local classSpecStores = getCurrentClassSpecStores(cfg)
    if not classSpecStores then
        return 0
    end

    local changed = 0
    for _, scopeKey in ipairs(KEY_DEFS) do
        local tierKeyType = KEY_TYPE_TO_STORE[scopeKey]
        local storeTable = classSpecStores[scopeKey]
        if type(storeTable) == "table" then
            for rawKey, entry in pairs(storeTable) do
                local normalized = buildKeyFromEntry(entry, tierKeyType, rawKey)
                if normalized and normalizeEntryMetadata(entry, normalized) then
                    changed = changed + 1
                elseif
                    type(entry) == "table"
                    and type(entry.value) == "table"
                    and scrubLegacyColorMetadata(entry.value)
                then
                    changed = changed + 1
                end
            end
        end
    end
    return changed
end

---@param storeTable table|nil
---@param tierKeyType "spellName"|"spellID"|"cooldownID"|"textureFileID"
---@param target ECM_SpellColorKey|nil
---@return boolean removed
local function removeMatchingStoreEntries(storeTable, tierKeyType, target)
    if type(storeTable) ~= "table" or not target then
        return false
    end

    local keysToRemove = nil
    for rawKey, entry in pairs(storeTable) do
        local candidate = buildKeyFromEntry(entry, tierKeyType, rawKey)
        if candidate and keysMatch(candidate, target) then
            keysToRemove = keysToRemove or {}
            keysToRemove[#keysToRemove + 1] = rawKey
        end
    end

    if not keysToRemove then
        return false
    end

    for _, rawKey in ipairs(keysToRemove) do
        storeTable[rawKey] = nil
    end

    return true
end

---@param store ECM_SpellColorStore
---@param target ECM_SpellColorKey|nil
---@return boolean removed
local function removeMatchingPersistedEntries(store, target)
    local tables = scopeTables(store)
    if not tables or not target then
        return false
    end

    local removed = false
    for _, scopeKey in ipairs(KEY_DEFS) do
        if removeMatchingStoreEntries(tables[scopeKey], KEY_TYPE_TO_STORE[scopeKey], target) then
            removed = true
        end
    end

    return removed
end

---@param store ECM_SpellColorStore
---@param target ECM_SpellColorKey|nil
---@return boolean removed
local function removeMatchingDiscoveredEntries(store, target)
    if not target then
        return false
    end

    local discoveredKeys = getDiscoveredKeys(store)
    local removed = false
    local nextIndex = 1

    for index = 1, #discoveredKeys do
        local key = discoveredKeys[index]
        if key and keysMatch(key, target) then
            removed = true
        else
            discoveredKeys[nextIndex] = key
            nextIndex = nextIndex + 1
        end
    end

    for index = nextIndex, #discoveredKeys do
        discoveredKeys[index] = nil
    end

    return removed
end

---------------------------------------------------------------------------
-- Public store API
---------------------------------------------------------------------------

--- Gets the custom color for a spell by a normalized key object.
---@param key ECM_SpellColorKey|table|nil
---@return ECM_Color|nil
function SpellColorStore:GetColorByKey(key)
    local normalized = normalizeKey(key)
    if not normalized then
        return nil
    end
    return storeGet(self, normalized:ToArray())
end

--- Extracts identifying values from a bar frame and returns a normalized key.
---@param frame ECM_BuffBarMixin
---@return ECM_SpellColorKey|nil
local function makeKeyFromBar(frame)
    return SpellColors.MakeKey(
        frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText(),
        frame.cooldownInfo and frame.cooldownInfo.spellID,
        frame.cooldownID,
        FrameUtil.GetIconTextureFileID(frame)
    )
end

--- Gets the custom color for a bar frame.
---@param frame ECM_BuffBarMixin
---@return ECM_Color|nil
function SpellColorStore:GetColorForBar(frame)
    ns.DebugAssert(frame, "Expected bar frame")

    if not (frame and frame.__ecmHooked) then
        ns.Log("SpellColors", "GetColorForBar - invalid bar frame", {
            frame = frame,
            nameExists = frame and type(frame.Name) == "table" and type(frame.Name.GetText) == "function",
            iconExists = frame and type(frame.Icon) == "table" and type(frame.Icon.GetRegions) == "function",
        })
        return nil
    end

    return self:GetColorByKey(makeKeyFromBar(frame))
end

--- Returns deduplicated color entries for the current class/spec.
---@return { key: ECM_SpellColorKey, color: ECM_Color }[]
function SpellColorStore:GetAllColorEntries()
    local cfg = config(self)
    if not cfg then
        return {}
    end
    local classSpecStores = getCurrentClassSpecStores(cfg)
    if not classSpecStores then
        return {}
    end

    local result = {}

    local function maybeSanitizeOutputColor(value)
        if hasLegacyColorMetadata(value) then
            return sanitizeColorValue(value) or value
        end
        return value
    end

    local function candidateWins(row, tsValue, tierIndex)
        if tsValue > (row._ts or 0) then
            return true
        end
        if tsValue < (row._ts or 0) then
            return false
        end
        return tierIndex < (row._tierIndex or math.huge)
    end

    for tierIndex, scopeKey in ipairs(KEY_DEFS) do
        local keyType = KEY_TYPE_TO_STORE[scopeKey]
        local storeTable = classSpecStores[scopeKey]
        if storeTable then
            for rawKey, entry in pairs(storeTable) do
                if type(entry) == "table" and type(entry.value) == "table" then
                    local key = buildKeyFromEntry(entry, keyType, rawKey)
                    if key then
                        local rowTs = entryTs(entry)
                        local rowColor = maybeSanitizeOutputColor(entry.value)
                        local merged = false

                        for _, row in ipairs(result) do
                            if row.key:Matches(key) then
                                row.key = row.key:Merge(key) or row.key
                                if candidateWins(row, rowTs, tierIndex) then
                                    row.color = rowColor
                                    row._ts = rowTs
                                    row._tierIndex = tierIndex
                                end
                                merged = true
                                break
                            end
                        end

                        if not merged then
                            result[#result + 1] = {
                                key = key,
                                color = rowColor,
                                _ts = rowTs,
                                _tierIndex = tierIndex,
                            }
                        end
                    end
                end
            end
        end
    end

    -- Merge runtime-discovered keys so the UI shows all visible bars
    -- without BuffBarsOptions reaching into BuffBars directly.
    for _, dKey in ipairs(getDiscoveredKeys(self)) do
        local merged = false
        for _, row in ipairs(result) do
            if row.key:Matches(dKey) then
                row.key = row.key:Merge(dKey) or row.key
                merged = true
                break
            end
        end
        if not merged then
            result[#result + 1] = { key = dKey }
        end
    end

    for _, row in ipairs(result) do
        row._ts = nil
        row._tierIndex = nil
    end

    return result
end

--- Sets a custom color for a spell by normalized key object.
---@param key ECM_SpellColorKey|table|nil
---@param color ECM_Color
function SpellColorStore:SetColorByKey(key, color)
    ns.DebugAssert(type(color) == "table", "Expected color to be a table")

    local normalized = normalizeKey(key)
    if not normalized then
        return
    end

    local storedColor = hasLegacyColorMetadata(color) and sanitizeColorValue(color) or color
    storeSet(self, normalized:ToArray(), storedColor, buildEntryMeta(normalized))
end

--- Returns the default bar color.
---@return ECM_Color
function SpellColorStore:GetDefaultColor()
    local cfg = config(self)
    if not cfg then
        return getScopeDefaultColor(self._scope)
    end
    return cfg.colors.defaultColor
end

--- Sets the default bar color.
---@param color ECM_Color
function SpellColorStore:SetDefaultColor(color)
    local cfg = config(self)
    if not cfg then
        return
    end
    cfg.colors.defaultColor = { r = color.r, g = color.g, b = color.b, a = 1 }
end

--- Removes the custom color for a spell from all key tiers.
---@param key ECM_SpellColorKey|table|nil
---@return boolean nameCleared
---@return boolean spellIDCleared
---@return boolean cooldownIDCleared
---@return boolean textureCleared
function SpellColorStore:ResetColorByKey(key)
    local normalized = normalizeKey(key)
    if not normalized then
        return false, false, false, false
    end
    return storeRemove(self, normalized:ToArray())
end

--- Reconciles color entries for a list of normalized keys and repairs metadata.
---@param keys ECM_SpellColorKey[]|nil
---@return number changed
function SpellColorStore:ReconcileAllKeys(keys)
    local keys_list = {}
    if type(keys) == "table" then
        for _, key in ipairs(keys) do
            local normalized = normalizeKey(key)
            if normalized then
                keys_list[#keys_list + 1] = normalized:ToArray()
            end
        end
    end

    local changed = 0
    if #keys_list > 0 then
        changed = reconcileAll(self, keys_list)
    end
    return changed + repairCurrentSpecStoreMetadata(self)
end

--- Removes persisted and discovered entries matching the given keys.
---@param keys (ECM_SpellColorKey|table)[]
---@return ECM_SpellColorKey[] removedKeys
function SpellColorStore:RemoveEntriesByKeys(keys)
    local removedKeys = {}

    if type(keys) ~= "table" then
        return removedKeys
    end

    for _, key in ipairs(keys) do
        local normalized = normalizeKey(key)
        if normalized then
            local removedPersisted = removeMatchingPersistedEntries(self, normalized)
            local removedDiscovered = removeMatchingDiscoveredEntries(self, normalized)
            if removedPersisted or removedDiscovered then
                removedKeys[#removedKeys + 1] = normalized
            end
        end
    end

    return removedKeys
end

--- Registers a bar frame's identifying values in the runtime discovered cache.
--- Called during layout so values are captured before they become secret.
---@param frame ECM_BuffBarMixin
function SpellColorStore:DiscoverBar(frame)
    local key = makeKeyFromBar(frame)
    if not key then
        return
    end
    local discoveredKeys = getDiscoveredKeys(self)
    for i, existing in ipairs(discoveredKeys) do
        if keysMatch(existing, key) then
            discoveredKeys[i] = mergeKeys(existing, key) or existing
            return
        end
    end
    discoveredKeys[#discoveredKeys + 1] = key
end

--- Wipes the runtime discovered keys cache.
function SpellColorStore:ClearDiscoveredKeys()
    wipe(getDiscoveredKeys(self))
end

--- Wipes all persisted spell color entries for the current class/spec.
---@return number cleared  Total entries removed across all tiers.
function SpellColorStore:ClearCurrentSpecColors()
    local cfg = config(self)
    if not cfg then
        return 0
    end

    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    if not classID or not specID then
        return 0
    end

    local cleared = 0
    for _, def in ipairs(KEY_DEFS) do
        local specTbl = cfg.colors[def] and cfg.colors[def][classID] and cfg.colors[def][classID][specID]
        if specTbl then
            for _ in pairs(specTbl) do
                cleared = cleared + 1
            end
            cfg.colors[def][classID][specID] = {}
        end
    end

    -- Invalidate nothing — tier tables are fetched fresh on each call.
    return cleared
end
