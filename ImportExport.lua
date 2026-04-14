-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ImportExport = {}
ns.ImportExport = ImportExport

local C = ns.Constants
local L = ns.L

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Generates metadata for export string.
---@return table metadata Metadata about the export
local function generateMetadata()
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "unknown"
    return {
        addonVersion = version,
        exportVersion = C.EXPORT_VERSION,
        exportedAt = time(),
    }
end

--------------------------------------------------------------------------------
-- Core Encoding/Decoding
--------------------------------------------------------------------------------

--- Encodes data into a compressed, shareable string.
--- Format: "ECM:1:{encoded}"
---@param data table The data to encode
---@return string|nil exportString The encoded string, or nil on failure
---@return string|nil errorMessage Error message if encoding failed
function ImportExport.EncodeData(data)
    if not data then
        return nil, L["ENCODE_NO_DATA"]
    end

    local serialized = LibSerialize:Serialize(data)
    if not serialized then
        return nil, L["ENCODE_SERIALIZATION_FAILED"]
    end

    local compressed = LibDeflate:CompressDeflate(serialized, { level = 9 })
    if not compressed then
        return nil, L["ENCODE_COMPRESSION_FAILED"]
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, L["ENCODE_ENCODING_FAILED"]
    end

    return C.EXPORT_PREFIX .. ":" .. C.EXPORT_VERSION .. ":" .. encoded
end

--- Decodes an import string back into data.
---@param importString string The import string to decode
---@return table|nil data The decoded data, or nil on failure
---@return string|nil errorMessage Error message if decoding failed
function ImportExport.DecodeData(importString)
    if not importString or strtrim(importString) == "" then
        return nil, L["DECODE_EMPTY"]
    end

    -- Parse format: "AddonName:Version:EncodedData"
    local prefix, versionStr, encoded = importString:match("^([^:]+):(%d+):(.+)$")

    if not prefix or not versionStr or not encoded then
        return nil, L["DECODE_INVALID_FORMAT"]
    end

    if prefix ~= C.EXPORT_PREFIX then
        return nil, string.format(L["DECODE_WRONG_ADDON"], tostring(prefix))
    end

    local version = tonumber(versionStr)
    if not version or version > C.EXPORT_VERSION then
        return nil, string.format(L["DECODE_INCOMPATIBLE_VERSION"], C.EXPORT_VERSION, tostring(versionStr))
    end

    -- Decode
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return nil, L["DECODE_CORRUPTED"]
    end

    -- Decompress
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, L["DECODE_DECOMPRESS_FAILED"]
    end

    -- Deserialize
    local success, data = LibSerialize:Deserialize(serialized)
    if not success or not data then
        return nil, L["DECODE_DESERIALIZE_FAILED"]
    end

    return data
end

--------------------------------------------------------------------------------
-- High-Level Export/Import API
--------------------------------------------------------------------------------

--- Prepares a profile for export by creating a clean copy and excluding cache data.
---@param profile table The profile to prepare
---@return table exportData Data ready for export
local function prepareProfileForExport(profile)
    assert(profile, "profile is nil")

    local cleanedProfile = ns.CloneValue(profile)
    -- Strip runtime cache data from the export
    if cleanedProfile.buffBars and cleanedProfile.buffBars.colors then
        cleanedProfile.buffBars.colors.cache = nil
    end

    return {
        metadata = generateMetadata(),
        profile = cleanedProfile,
    }
end

--- Exports the current profile to a shareable string.
---@return string|nil exportString The export string, or nil on failure
---@return string|nil errorMessage Error message if export failed
function ImportExport.ExportCurrentProfile()
    local db = ns.Addon.db
    if not db or not db.profile then
        return nil, L["EXPORT_NO_PROFILE"]
    end

    local exportData = prepareProfileForExport(db.profile)
    return ImportExport.EncodeData(exportData)
end

--- Validates an import string and returns the decoded data without applying it.
--- Use this to preview/validate before calling ApplyImportData.
---@param importString string The import string to validate
---@return table|nil data The decoded data, or nil on failure
---@return string|nil errorMessage Error message if validation failed
function ImportExport.ValidateImportString(importString)
    local data, errorMsg = ImportExport.DecodeData(importString)
    if not data then
        return nil, errorMsg
    end

    -- Validate structure
    if not data.profile then
        return nil, L["IMPORT_NO_PROFILE_DATA"]
    end

    return data
end

--- Applies previously validated import data to the current profile.
--- Call ValidateImportString first to get the data.
---@param data table The validated import data (from ValidateImportString)
---@return boolean success Whether apply succeeded
---@return string|nil errorMessage Error message if apply failed
function ImportExport.ApplyImportData(data)
    if not data or not data.profile then
        return false, L["IMPORT_NO_PROFILE_DATA"]
    end

    local db = ns.Addon.db
    if not db or not db.profile then
        return false, L["IMPORT_NO_PROFILE"]
    end

    -- Preserve the cache if it exists (deep copy to avoid shared references)
    local existingCache = db.profile.buffBars and db.profile.buffBars.colors and db.profile.buffBars.colors.cache
    if existingCache then
        existingCache = ns.CloneValue(existingCache)
    end

    -- Clear and replace profile
    for key in pairs(db.profile) do
        db.profile[key] = nil
    end

    for key, value in pairs(data.profile) do
        db.profile[key] = value
    end

    -- Restore cache
    if existingCache and db.profile.buffBars and db.profile.buffBars.colors then
        db.profile.buffBars.colors.cache = existingCache
    end

    -- Run migrations on imported data (it may be from an older schema)
    if db.profile.schemaVersion and db.profile.schemaVersion < ns.Constants.CURRENT_SCHEMA_VERSION then
        ns.Migration.Run(db.profile)
    end

    return true
end
