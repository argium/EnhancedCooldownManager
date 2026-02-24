-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- SpellColors: Manages per-spell color customization for buff bars.
-- Backed by a PriorityKeyMap with four ordered tiers:
--   1. spell name   (highest priority — human-readable, preferred key)
--   2. spell ID      (numeric, survives secrets better than name)
--   3. cooldown ID   (numeric, frame-level identifier)
--   4. texture file ID (lowest priority — last-resort fallback)

local _, ns = ...
local FrameUtil = ECM.FrameUtil
local SpellColors = {}
ECM.SpellColors = SpellColors

--- Key tier definitions, ordered highest-priority first.
--- Must match the field names returned by get_current_class_spec_stores().
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
-- Profile helpers
---------------------------------------------------------------------------

--- Ensures the color storage tables exist for the current class/spec.
---@param cfg table  buffBars config table
---@return table|nil classSpecStores  Keyed by KEY_DEFS field names; each value is the current class/spec storage table.
local function get_current_class_spec_stores(cfg)
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()

    if not classID or not specID then
        ECM_debug_assert(false, "SpellColors.get_current_class_spec_stores - unable to determine player class/spec", {
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
local function ensure_profile_is_setup(cfg)
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

--- Returns the buffBars config table, or nil if unavailable.
---@return table|nil cfg
local function config()
    local mod = ns.Addon
    local cfg = mod and mod.db and mod.db.profile and mod.db.profile.buffBars or nil
    if type(cfg) ~= "table" then
        ECM_debug_assert(false, "SpellColors.config - missing or invalid buffBars config")
        return nil
    end
    ensure_profile_is_setup(cfg)
    return cfg
end

---------------------------------------------------------------------------
-- Lazy singleton
---------------------------------------------------------------------------

local _map -- PriorityKeyMap instance (created on first use)

---@class ECM_SpellColorKeyType
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
local function select_primary_key(spellName, spellID, cooldownID, textureId)
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
local function build_key(spellName, spellID, cooldownID, textureFileID, preferredType)
    local keyType = preferredType
    local primaryKey
    if keyType == "spellName" then primaryKey = spellName
    elseif keyType == "spellID" then primaryKey = spellID
    elseif keyType == "cooldownID" then primaryKey = cooldownID
    elseif keyType == "textureFileID" then primaryKey = textureFileID
    end
    if not primaryKey then
        primaryKey, keyType = select_primary_key(spellName, spellID, cooldownID, textureFileID)
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
local function normalize_key(key)
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

    return build_key(spellName, spellID, cooldownID, textureFileID, keyType)
end

---@param a ECM_SpellColorKey|nil
---@param b ECM_SpellColorKey|nil
---@return boolean
local function keys_match(a, b)
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
    if aTextureOnly and bTextureOnly and a.textureFileID and b.textureFileID and a.textureFileID == b.textureFileID then
        return true
    end

    return false
end

---@param base ECM_SpellColorKey|nil
---@param other ECM_SpellColorKey|nil
---@return ECM_SpellColorKey|nil
local function merge_keys(base, other)
    if base == nil then
        return other
    end
    if other == nil then
        return base
    end
    if not keys_match(base, other) then
        return nil
    end

    return build_key(
        base.spellName or other.spellName,
        base.spellID or other.spellID,
        base.cooldownID or other.cooldownID,
        base.textureFileID or other.textureFileID,
        nil
    )
end

---@param key ECM_SpellColorKey|table|nil
---@return string|nil spellName
---@return number|nil spellID
---@return number|nil cooldownID
---@return number|nil textureFileID
---@return ECM_SpellColorKey|nil normalized
local function key_to_tuple(key)
    local normalized = normalize_key(key)
    if not normalized then
        return nil, nil, nil, nil, nil
    end
    return normalized.spellName, normalized.spellID, normalized.cooldownID, normalized.textureFileID, normalized
end

---@param entry any
---@return number
local function entry_ts(entry)
    return (type(entry) == "table" and type(entry.t) == "number") and entry.t or 0
end

---@param color table|nil
---@return ECM_Color|nil
local function sanitize_color_value(color)
    if type(color) ~= "table" then
        return nil
    end
    return { r = color.r, g = color.g, b = color.b, a = color.a or 1 }
end

local LEGACY_METADATA_FIELDS = { "keyType", "primaryKey", "spellName", "spellID", "cooldownID", "textureId", "textureFileID" }

---@param value table|nil
---@return boolean changed
local function scrub_legacy_color_metadata(value)
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
local function build_entry_meta(normalized)
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
local function build_key_from_entry(entry, tierKeyType, rawKey)
    if type(entry) ~= "table" or type(entry.value) ~= "table" then
        return nil
    end

    local value = entry.value
    local meta = type(entry.meta) == "table" and entry.meta or nil

    local spellName = validateKey((meta and meta.spellName) or value.spellName)
    local spellID = validateKey((meta and meta.spellID) or value.spellID)
    local cooldownID = validateKey((meta and meta.cooldownID) or value.cooldownID)
    local textureFileID = validateKey(
        (meta and (meta.textureFileID or meta.textureId)) or value.textureFileID or value.textureId
    )
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

    return build_key(spellName, spellID, cooldownID, textureFileID, preferredType)
end

---@param entry table|nil
---@param normalized ECM_SpellColorKey|nil
---@return boolean changed
local function normalize_entry_metadata(entry, normalized)
    if type(entry) ~= "table" or type(entry.value) ~= "table" or not normalized then
        return false
    end

    local changed = scrub_legacy_color_metadata(entry.value)
    local desired = build_entry_meta(normalized)
    local current = type(entry.meta) == "table" and entry.meta or nil
    if not current
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
local function has_legacy_color_metadata(value)
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

---@param other ECM_SpellColorKey|table|nil
---@return boolean
function SpellColorKeyType:Matches(other)
    return keys_match(self, normalize_key(other))
end

---@param other ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
function SpellColorKeyType:Merge(other)
    return merge_keys(self, normalize_key(other))
end

--- Returns the PriorityKeyMap instance, creating it on first call.
---@return PriorityKeyMap|nil
local function get_map()
    if _map then
        return _map
    end

    local cfg = config()
    if not cfg then
        return nil
    end

    _map = ECM.PriorityKeyMap.New(
        KEY_DEFS,
        function()
            local cfg = config()
            if not cfg then return nil end
            return get_current_class_spec_stores(cfg)
        end,
        validateKey
    )
    return _map
end

---@return number changed
local function repair_current_spec_store_metadata()
    local cfg = config()
    if not cfg then
        return 0
    end

    local classSpecStores = get_current_class_spec_stores(cfg)
    if not classSpecStores then
        return 0
    end

    local changed = 0
    for _, scopeKey in ipairs(KEY_DEFS) do
        local tierKeyType = KEY_TYPE_TO_STORE[scopeKey]
        local storeTable = classSpecStores[scopeKey]
        if type(storeTable) == "table" then
            for rawKey, entry in pairs(storeTable) do
                local normalized = build_key_from_entry(entry, tierKeyType, rawKey)
                if normalized and normalize_entry_metadata(entry, normalized) then
                    changed = changed + 1
                elseif type(entry) == "table" and type(entry.value) == "table" and scrub_legacy_color_metadata(entry.value) then
                    changed = changed + 1
                end
            end
        end
    end
    return changed
end

---------------------------------------------------------------------------
-- Public interface
---------------------------------------------------------------------------

--- Creates a normalized spell-color key from identifying values.
--- Input values are validated and secret values are dropped.
---@param spellName string|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureFileID number|nil
---@return ECM_SpellColorKey|nil
function SpellColors.MakeKey(spellName, spellID, cooldownID, textureFileID)
    local validSpellName = validateKey(spellName)
    local validSpellID = validateKey(spellID)
    local validCooldownID = validateKey(cooldownID)
    local validTextureID = validateKey(textureFileID)
    return build_key(validSpellName, validSpellID, validCooldownID, validTextureID, nil)
end

--- Normalizes a key payload into an opaque spell-color key object.
---@param key ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
function SpellColors.NormalizeKey(key)
    return normalize_key(key)
end

--- Returns true when two keys identify the same logical spell-color entry.
---@param left ECM_SpellColorKey|table|nil
---@param right ECM_SpellColorKey|table|nil
---@return boolean
function SpellColors.KeysMatch(left, right)
    return keys_match(normalize_key(left), normalize_key(right))
end

--- Merges identifiers from matching keys into a single normalized key.
--- Returns nil when both keys are valid but identify different entries.
---@param base ECM_SpellColorKey|table|nil
---@param other ECM_SpellColorKey|table|nil
---@return ECM_SpellColorKey|nil
function SpellColors.MergeKeys(base, other)
    return merge_keys(normalize_key(base), normalize_key(other))
end

--- Gets the custom color for a spell by a normalized key object.
---@param key ECM_SpellColorKey|table|nil
---@return ECM_Color|nil
function SpellColors.GetColorByKey(key)
    local map = get_map()
    if not map then
        return nil
    end

    local spellName, spellID, cooldownID, textureFileID = key_to_tuple(key)
    if not (spellName or spellID or cooldownID or textureFileID) then
        return nil
    end
    return map:Get({ spellName, spellID, cooldownID, textureFileID })
end

--- Extracts identifying values from a bar frame and returns a normalized key.
---@param frame ECM_BuffBarMixin
---@return ECM_SpellColorKey|nil
local function make_key_from_bar(frame)
    return SpellColors.MakeKey(
        validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText()),
        validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID),
        validateKey(frame.cooldownID),
        validateKey(FrameUtil.GetIconTextureFileID(frame))
    )
end

--- Gets the custom color for a bar frame.
---@param frame ECM_BuffBarMixin
---@return ECM_Color|nil
function SpellColors.GetColorForBar(frame)
    ECM_debug_assert(frame, "Expected bar frame")

    if not (frame and frame.__ecmHooked) then
        ECM_log(ECM.Constants.SYS.Styling, "SpellColors", "GetColorForBar - invalid bar frame", {
            frame = frame,
            nameExists = frame and type(frame.Name) == "table" and type(frame.Name.GetText) == "function",
            iconExists = frame and type(frame.Icon) == "table" and type(frame.Icon.GetRegions) == "function",
        })
        return nil
    end

    return SpellColors.GetColorByKey(make_key_from_bar(frame))
end

--- Returns deduplicated color entries for the current class/spec.
---@return { key: ECM_SpellColorKey, color: ECM_Color }[]
function SpellColors.GetAllColorEntries()
    -- Ensure the map is initialized before enumerating the current scope.
    get_map()
    local cfg = config()
    if not cfg then
        return {}
    end
    local classSpecStores = get_current_class_spec_stores(cfg)
    if not classSpecStores then
        return {}
    end

    local result = {}

    local function maybe_sanitize_output_color(value)
        if has_legacy_color_metadata(value) then
            return sanitize_color_value(value) or value
        end
        return value
    end

    local function candidate_wins(row, tsValue, tierIndex)
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
                    local key = build_key_from_entry(entry, keyType, rawKey)
                    if key then
                        local rowTs = entry_ts(entry)
                        local rowColor = maybe_sanitize_output_color(entry.value)
                        local merged = false

                        for _, row in ipairs(result) do
                            if row.key:Matches(key) then
                                row.key = row.key:Merge(key) or row.key
                                if candidate_wins(row, rowTs, tierIndex) then
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
    ECM_debug_assert(type(color) == "table", "Expected color to be a table")

    local map = get_map()
    if not map then
        return
    end

    local spellName, spellID, cooldownID, textureFileID, normalized = key_to_tuple(key)
    if not normalized then
        return
    end

    local storedColor = color
    if has_legacy_color_metadata(color) then
        storedColor = sanitize_color_value(color) or color
    end

    map:Set(
        { spellName, spellID, cooldownID, textureFileID },
        storedColor,
        build_entry_meta(normalized)
    )
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
    local map = get_map()
    if not map then
        return false, false, false, false
    end

    local spellName, spellID, cooldownID, textureFileID = key_to_tuple(key)
    if not (spellName or spellID or cooldownID or textureFileID) then
        return false, false, false, false
    end
    return map:Remove({ spellName, spellID, cooldownID, textureFileID })
end

--- Reconciles the color entry for a single bar frame.
---@param frame ECM_BuffBarMixin
function SpellColors.ReconcileBar(frame)
    if not (frame and frame.__ecmHooked) then
        return
    end
    local key = make_key_from_bar(frame)
    if key then
        SpellColors.ReconcileAllKeys({ key })
    end
end

--- Reconciles color entries for a list of normalized keys and repairs metadata.
---@param keys ECM_SpellColorKey[]|nil
---@return number changed
function SpellColors.ReconcileAllKeys(keys)
    local map = get_map()
    if not map then
        return 0
    end

    local keys_list = {}
    if type(keys) == "table" then
        for _, key in ipairs(keys) do
            local spellName, spellID, cooldownID, textureFileID, normalized = key_to_tuple(key)
            if normalized then
                keys_list[#keys_list + 1] = { spellName, spellID, cooldownID, textureFileID }
            end
        end
    end

    local changed = 0
    if #keys_list > 0 then
        changed = map:ReconcileAll(keys_list)
    end
    return changed + repair_current_spec_store_metadata()
end

--- Reconciles color entries for a list of bar frames.
---@param frames ECM_BuffBarMixin[]
---@return number changed  Count of reconciled entries.
function SpellColors.ReconcileAllBars(frames)
    local keys = {}
    for _, frame in ipairs(frames) do
        if frame and frame.__ecmHooked then
            local key = make_key_from_bar(frame)
            if key then
                keys[#keys + 1] = key
            end
        end
    end
    return SpellColors.ReconcileAllKeys(keys)
end
