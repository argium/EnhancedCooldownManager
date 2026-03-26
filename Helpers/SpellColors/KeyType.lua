-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- SpellColors/KeyType: Key construction, normalization, and matching for
-- spell-color entries. Backed by a multi-tier key system where each spell
-- can be identified by name, spell ID, cooldown ID, or texture file ID.

local SpellColors = {}
ECM.SpellColors = SpellColors

--- Key tier definitions, ordered highest-priority first.
--- Must match the field names returned by Store's getCurrentClassSpecStores().
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
-- SpellColorKeyType class
---------------------------------------------------------------------------

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

---------------------------------------------------------------------------
-- Internal exports for Store.lua
---------------------------------------------------------------------------

SpellColors._KEY_DEFS = KEY_DEFS
SpellColors._KEY_TYPE_TO_STORE = KEY_TYPE_TO_STORE
SpellColors._validateKey = validateKey
SpellColors._buildKey = buildKey
SpellColors._normalizeKey = normalizeKey
SpellColors._keysMatch = keysMatch
SpellColors._mergeKeys = mergeKeys
