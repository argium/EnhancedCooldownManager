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

---------------------------------------------------------------------------
-- Key validation
---------------------------------------------------------------------------

--- Returns k if it is a valid, non-secret string or number; nil otherwise.
local function validateKey(k)
    if k == nil then
        return nil
    end
    if type(k) == "string" and not issecretvalue(k) then
        return k
    end
    if type(k) == "number" and not issecretvalue(k) then
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

    return {
        keyType = keyType,
        primaryKey = primaryKey,
        spellName = spellName,
        spellID = spellID,
        cooldownID = cooldownID,
        textureFileID = textureFileID,
    }
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
    local keyType = key.keyType
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

---@param value table
---@param keyType "spellName"|"spellID"|"cooldownID"|"textureFileID"|nil
---@param key any
local function ensure_entry_metadata(value, keyType, key)
    if type(value) ~= "table" then
        return
    end

    if not value.keyType and keyType then
        value.keyType = keyType
    end

    if keyType == "spellID" and type(key) == "number" and not value.spellID then
        value.spellID = key
    elseif keyType == "cooldownID" and type(key) == "number" and not value.cooldownID then
        value.cooldownID = key
    elseif keyType == "textureFileID" and type(key) == "number" and not value.textureId then
        -- Intentionally stored as `textureId` (not `textureFileID`) for backward
        -- compatibility with SavedVariables written by older versions of the addon.
        value.textureId = key
    end
end

---@param classSpecStores table
local function repair_entry_metadata(classSpecStores)
    -- Iterate in key priority order so primary key type is deterministic.
    for _, scopeKey in ipairs(KEY_DEFS) do
        local keyType = KEY_TYPE_TO_STORE[scopeKey]
        local storeTable = classSpecStores[scopeKey]
        if storeTable then
            for key, entry in pairs(storeTable) do
                if type(entry) == "table" and type(entry.value) == "table" then
                    ensure_entry_metadata(entry.value, keyType, key)
                end
            end
        end
    end
end

--- Repopulates lower-priority tier entries from byName for any colour
--- whose stored value carries embedded IDs (textureId, spellID,
--- cooldownID).  This repairs SavedVariables left incomplete by an
--- older Reconcile implementation that deleted fallback entries.
local function repair_from_primary()
    local cfg = config()
    if not cfg then return end

    local classSpecStores = get_current_class_spec_stores(cfg)
    if not classSpecStores then return end
    local byName = classSpecStores.byName
    if not byName then return end

    -- Ensure persisted entries carry explicit metadata (key type + key IDs).
    -- This removes the need for downstream key-type inference in options.
    repair_entry_metadata(classSpecStores)

    for _, entry in pairs(byName) do
        if type(entry) == "table" and type(entry.value) == "table" then
            local v = entry.value
            if v.textureId and classSpecStores.byTexture and not classSpecStores.byTexture[v.textureId] then
                classSpecStores.byTexture[v.textureId] = entry
            end
            if v.spellID and classSpecStores.bySpellID and not classSpecStores.bySpellID[v.spellID] then
                classSpecStores.bySpellID[v.spellID] = entry
            end
            if v.cooldownID and classSpecStores.byCooldownID and not classSpecStores.byCooldownID[v.cooldownID] then
                classSpecStores.byCooldownID[v.cooldownID] = entry
            end
        end
    end
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

    repair_from_primary()

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

    local spellName = validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText())
    local spellID = validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID)
    local cooldownID = validateKey(frame.cooldownID)
    local textureFileID = validateKey(FrameUtil.GetIconTextureFileID(frame))
    local key = SpellColors.MakeKey(spellName, spellID, cooldownID, textureFileID)
    return SpellColors.GetColorByKey(key)
end

--- Returns deduplicated color entries for the current class/spec.
---@return { key: ECM_SpellColorKey, color: ECM_Color }[]
function SpellColors.GetAllColorEntries()
    -- Ensure the map (and its one-time repair pass) has been initialised.
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
    local seenEntries = {}

    for _, scopeKey in ipairs(KEY_DEFS) do
        local keyType = KEY_TYPE_TO_STORE[scopeKey]
        local storeTable = classSpecStores[scopeKey]
        if storeTable then
            for rawKey, entry in pairs(storeTable) do
                if type(entry) == "table" and type(entry.value) == "table" and not seenEntries[entry] then
                    seenEntries[entry] = true
                    local value = entry.value

                    local spellName = validateKey(value.spellName)
                    local spellID = validateKey(value.spellID)
                    local cooldownID = validateKey(value.cooldownID)
                    local textureFileID = validateKey(value.textureId)
                    local preferredType = value.keyType or keyType
                    local validRawKey = validateKey(rawKey)

                    if preferredType == "spellName" and type(validRawKey) == "string" and not spellName then
                        spellName = validRawKey
                    elseif preferredType == "spellID" and type(validRawKey) == "number" and not spellID then
                        spellID = validRawKey
                    elseif preferredType == "cooldownID" and type(validRawKey) == "number" and not cooldownID then
                        cooldownID = validRawKey
                    elseif preferredType == "textureFileID" and type(validRawKey) == "number" and not textureFileID then
                        textureFileID = validRawKey
                    end

                    local key = build_key(spellName, spellID, cooldownID, textureFileID, preferredType)
                    if key then
                        result[#result + 1] = { key = key, color = value }
                    end
                end
            end
        end
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

    if textureFileID then
        color.textureId = textureFileID
    end
    if spellID then
        color.spellID = spellID
    end
    if cooldownID then
        color.cooldownID = cooldownID
    end
    color.keyType = normalized.keyType

    map:Set({ spellName, spellID, cooldownID, textureFileID }, color)
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
    local map = get_map()
    if not map then
        return
    end
    local spellName = validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText())
    local spellID = validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID)
    local cooldownID = validateKey(frame.cooldownID)
    local textureFileID = validateKey(FrameUtil.GetIconTextureFileID(frame))
    local key = SpellColors.MakeKey(spellName, spellID, cooldownID, textureFileID)
    if key then
        map:Reconcile({ key.spellName, key.spellID, key.cooldownID, key.textureFileID })
    end
end

--- Reconciles color entries for a list of bar frames.
---@param frames ECM_BuffBarMixin[]
---@return number changed  Count of reconciled entries.
function SpellColors.ReconcileAllBars(frames)
    local map = get_map()
    if not map then
        return 0
    end
    local keys_list = {}
    for _, frame in ipairs(frames) do
        if frame and frame.__ecmHooked then
            local spellName = validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText())
            local spellID = validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID)
            local cooldownID = validateKey(frame.cooldownID)
            local textureFileID = validateKey(FrameUtil.GetIconTextureFileID(frame))
            local key = SpellColors.MakeKey(spellName, spellID, cooldownID, textureFileID)
            if key then
                keys_list[#keys_list + 1] = { key.spellName, key.spellID, key.cooldownID, key.textureFileID }
            end
        end
    end
    return map:ReconcileAll(keys_list)
end
