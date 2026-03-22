-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- SpellColors/Store: Persistence layer and public API for per-spell color
-- customization. Stores colors under 4 key tiers (name, spellID, cooldownID,
-- textureFileID) with timestamp-based reconciliation for SavedVariables
-- deserialization conflicts.

local _, ns = ...
local FrameUtil = ECM.FrameUtil
local SpellColors = ECM.SpellColors

-- WoW uses Lua 5.1 (global `unpack`), busted tests use Lua 5.3+ (`table.unpack`).
local unpack = unpack or table.unpack

-- Import internal key helpers from KeyType.lua
local KEY_DEFS = SpellColors._KEY_DEFS
local KEY_TYPE_TO_STORE = SpellColors._KEY_TYPE_TO_STORE
local validateKey = SpellColors._validateKey
local normalizeKey = SpellColors._normalizeKey
local keysMatch = SpellColors._keysMatch
local mergeKeys = SpellColors._mergeKeys
local buildKey = SpellColors._buildKey

---------------------------------------------------------------------------
-- Entry metadata helpers
---------------------------------------------------------------------------

local LEGACY_METADATA_FIELDS =
    { "keyType", "primaryKey", "spellName", "spellID", "cooldownID", "textureId", "textureFileID" }

local KEY_TYPES = { spellName = true, spellID = true, cooldownID = true, textureFileID = true }

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
local _discoveredKeys = {}

---------------------------------------------------------------------------
-- Profile helpers
---------------------------------------------------------------------------

--- Ensures the color storage tables exist for the current class/spec.
---@param cfg table  buffBars config table
---@return table|nil classSpecStores  Keyed by KEY_DEFS field names; each value is the current class/spec storage table.
local function getCurrentClassSpecStores(cfg)
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()

    if not classID or not specID then
        ECM.DebugAssert(false, "SpellColors.getCurrentClassSpecStores - unable to determine player class/spec", {
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
---@param cfg table  buffBars config table
local function ensureProfileIsSetup(cfg)
    if not cfg.colors then
        cfg.colors = {
            byName = {},
            bySpellID = {},
            byCooldownID = {},
            byTexture = {},
            cache = {},
            defaultColor = ECM.Constants.BUFFBARS_DEFAULT_COLOR,
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
        cfg.colors.defaultColor = ECM.Constants.BUFFBARS_DEFAULT_COLOR
    end
end

--- Config accessor — defaults to reading from the addon's profile, but can be
--- overridden via SetConfigAccessor for testing or decoupling.
local _configAccessor

--- Allows callers (e.g., BuffBars module) to inject a config accessor,
--- decoupling SpellColors from direct db.profile access.
---@param accessor fun(): table|nil
function SpellColors.SetConfigAccessor(accessor)
    _configAccessor = accessor
end

--- Returns the buffBars config table, or nil if unavailable.
---@return table|nil cfg
local function config()
    local cfg
    if _configAccessor then
        cfg = _configAccessor()
    else
        cfg = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.buffBars or nil
    end
    if type(cfg) ~= "table" then
        ECM.DebugAssert(false, "SpellColors.config - missing or invalid buffBars config")
        return nil
    end
    ensureProfileIsSetup(cfg)
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
local function scopeTables()
    local cfg = config()
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
local function storeGet(keys)
    local tables = scopeTables()
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
local function storeSet(keys, value, meta)
    local tables = scopeTables()
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
local function storeRemove(keys)
    local tables = scopeTables()
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
local function reconcile(keys)
    local tables = scopeTables()
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
local function reconcileAll(keysList)
    local changed = 0
    for _, keys in ipairs(keysList) do
        if reconcile(keys) then
            changed = changed + 1
        end
    end
    return changed
end

---@return number changed
local function repairCurrentSpecStoreMetadata()
    local cfg = config()
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

---------------------------------------------------------------------------
-- Public store API
---------------------------------------------------------------------------

--- Gets the custom color for a spell by a normalized key object.
---@param key ECM_SpellColorKey|table|nil
---@return ECM_Color|nil
function SpellColors.GetColorByKey(key)
    local normalized = normalizeKey(key)
    if not normalized then
        return nil
    end
    return storeGet(normalized:ToArray())
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
function SpellColors.GetColorForBar(frame)
    ECM.DebugAssert(frame, "Expected bar frame")

    if not (frame and frame.__ecmHooked) then
        ECM.Log("SpellColors", "GetColorForBar - invalid bar frame", {
            frame = frame,
            nameExists = frame and type(frame.Name) == "table" and type(frame.Name.GetText) == "function",
            iconExists = frame and type(frame.Icon) == "table" and type(frame.Icon.GetRegions) == "function",
        })
        return nil
    end

    return SpellColors.GetColorByKey(makeKeyFromBar(frame))
end

--- Returns deduplicated color entries for the current class/spec.
---@return { key: ECM_SpellColorKey, color: ECM_Color }[]
function SpellColors.GetAllColorEntries()
    local cfg = config()
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
    for _, dKey in ipairs(_discoveredKeys) do
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
function SpellColors.SetColorByKey(key, color)
    ECM.DebugAssert(type(color) == "table", "Expected color to be a table")

    local normalized = normalizeKey(key)
    if not normalized then
        return
    end

    local storedColor = hasLegacyColorMetadata(color) and sanitizeColorValue(color) or color
    storeSet(normalized:ToArray(), storedColor, buildEntryMeta(normalized))
end

--- Returns the default bar color.
---@return ECM_Color
function SpellColors.GetDefaultColor()
    local cfg = config()
    if not cfg then
        return ECM.Constants.BUFFBARS_DEFAULT_COLOR
    end
    return cfg.colors.defaultColor
end

--- Sets the default bar color.
---@param color ECM_Color
function SpellColors.SetDefaultColor(color)
    local cfg = config()
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
function SpellColors.ResetColorByKey(key)
    local normalized = normalizeKey(key)
    if not normalized then
        return false, false, false, false
    end
    return storeRemove(normalized:ToArray())
end

--- Reconciles color entries for a list of normalized keys and repairs metadata.
---@param keys ECM_SpellColorKey[]|nil
---@return number changed
function SpellColors.ReconcileAllKeys(keys)
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
        changed = reconcileAll(keys_list)
    end
    return changed + repairCurrentSpecStoreMetadata()
end

--- Registers a bar frame's identifying values in the runtime discovered cache.
--- Called during layout so values are captured before they become secret.
---@param frame ECM_BuffBarMixin
function SpellColors.DiscoverBar(frame)
    local key = makeKeyFromBar(frame)
    if not key then
        return
    end
    for i, existing in ipairs(_discoveredKeys) do
        if keysMatch(existing, key) then
            _discoveredKeys[i] = mergeKeys(existing, key) or existing
            return
        end
    end
    _discoveredKeys[#_discoveredKeys + 1] = key
end

--- Wipes the runtime discovered keys cache.
function SpellColors.ClearDiscoveredKeys()
    wipe(_discoveredKeys)
end

--- Wipes all persisted spell color entries for the current class/spec.
---@return number cleared  Total entries removed across all tiers.
function SpellColors.ClearCurrentSpecColors()
    local cfg = config()
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
