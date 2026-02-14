-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod
local ImportExport = {}
ECM.ImportExport = ImportExport

local EXPORT_PREFIX = "EnhancedCooldownManager"
local EXPORT_VERSION = 1

local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")

-- Verify libraries are loaded immediately (fail fast)
assert(LibSerialize, "ImportExport: LibSerialize not loaded")
assert(LibDeflate, "ImportExport: LibDeflate not loaded")

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Deep copies a table, excluding specified paths.
---@param source table The table to copy
---@param excludePaths table|nil Array of dot-notation paths to exclude (e.g., {"buffBars.colors.cache"})
---@param currentPath string|nil Current path in recursion (internal use)
---@return table copy The deep copy
local function DeepCopyExcluding(source, excludePaths, currentPath)
    if type(source) ~= "table" then
        return source
    end

    currentPath = currentPath or ""
    excludePaths = excludePaths or {}
    local copy = {}

    for key, value in pairs(source) do
        local keyPath = currentPath == "" and tostring(key) or currentPath .. "." .. tostring(key)

        -- Check if this path should be excluded
        local shouldExclude = false
        for _, excludePath in ipairs(excludePaths) do
            if keyPath == excludePath then
                shouldExclude = true
                break
            end
        end

        if not shouldExclude then
            if type(value) == "table" then
                copy[key] = DeepCopyExcluding(value, excludePaths, keyPath)
            else
                copy[key] = value
            end
        end
    end

    return copy
end

--- Generates metadata for export string.
---@return table metadata Metadata about the export
local function GenerateMetadata()
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "unknown"

    return {
        addonVersion = version,
        exportVersion = EXPORT_VERSION,
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
        return nil, "No data provided for encoding"
    end

    local serialized = LibSerialize:Serialize(data)
    if not serialized then
        return nil, "Serialization failed"
    end

    local compressed = LibDeflate:CompressDeflate(serialized, {level = 9})
    if not compressed then
        return nil, "Compression failed"
    end

    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil, "Encoding failed"
    end

    return EXPORT_PREFIX .. ":" .. EXPORT_VERSION .. ":" .. encoded
end

--- Decodes an import string back into data.
---@param importString string The import string to decode
---@return table|nil data The decoded data, or nil on failure
---@return string|nil errorMessage Error message if decoding failed
function ImportExport.DecodeData(importString)
    if not importString or strtrim(importString) == "" then
        return nil, "Import string is empty"
    end

    -- Parse format: "AddonName:Version:EncodedData"
    -- Using more strict pattern that requires non-empty encoded portion
    local prefix, versionStr, encoded = importString:match("^([^:]+):(%d+):(.+)$")

    if not prefix or not versionStr or not encoded or encoded == "" then
        return nil, "Invalid import string format"
    end

    if prefix ~= EXPORT_PREFIX then
        return nil, "This import string is not for Enhanced Cooldown Manager (prefix: " .. tostring(prefix) .. ")"
    end

    local version = tonumber(versionStr)
    if not version or version > EXPORT_VERSION then
        return nil, "Incompatible import string version (expected " .. EXPORT_VERSION .. ", got " .. tostring(versionStr) .. ")"
    end

    -- Decode
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then
        return nil, "Failed to decode string - it may be corrupted or incomplete"
    end

    -- Decompress
    local serialized = LibDeflate:DecompressDeflate(compressed)
    if not serialized then
        return nil, "Failed to decompress data - the string may be corrupted"
    end

    -- Deserialize
    local success, data = LibSerialize:Deserialize(serialized)
    if not success or not data then
        return nil, "Failed to deserialize data - the string may be corrupted"
    end

    return data
end

--------------------------------------------------------------------------------
-- High-Level Export/Import API
--------------------------------------------------------------------------------

--- Prepares a profile for export by creating a clean copy and excluding cache data.
---@param profile table The profile to prepare
---@return table exportData Data ready for export
local function PrepareProfileForExport(profile)
    assert(profile, "profile is nil")

    -- Exclude runtime cache data
    local excludePaths = {"buffBars.colors.cache"}
    local cleanedProfile = DeepCopyExcluding(profile, excludePaths)

    return {
        metadata = GenerateMetadata(),
        profile = cleanedProfile,
    }
end

--- Exports the current profile to a shareable string.
---@return string|nil exportString The export string, or nil on failure
---@return string|nil errorMessage Error message if export failed
function ImportExport.ExportCurrentProfile()
    mod = mod or ns.Addon
    local db = mod.db
    if not db or not db.profile then
        return nil, "No active profile found"
    end

    local exportData = PrepareProfileForExport(db.profile)
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
        return nil, "Import string does not contain profile data"
    end

    return data
end

--- Applies previously validated import data to the current profile.
--- Call ValidateImportString first to get the data.
---@param data table The validated import data (from ValidateImportString)
---@return boolean success Whether apply succeeded
---@return string|nil errorMessage Error message if apply failed
function ImportExport.ApplyImportData(data)
    mod = mod or ns.Addon
    if not data or not data.profile then
        return false, "Invalid import data"
    end

    local db = mod.db
    if not db or not db.profile then
        return false, "No active profile to import into"
    end

    -- Preserve the cache if it exists (deep copy to avoid shared references)
    local existingCache = db.profile.buffBars
        and db.profile.buffBars.colors
        and db.profile.buffBars.colors.cache
    if existingCache then
        existingCache = DeepCopyExcluding(existingCache)
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
    if db.profile.schemaVersion and db.profile.schemaVersion < ECM.Constants.CURRENT_SCHEMA_VERSION then
        ECM.Migration.Run(db.profile)
    end

    return true
end

--- Imports profile data from a string and applies it to the current profile.
--- Note: This does NOT trigger a UI reload - caller must handle that.
--- Prefer using ValidateImportString + ApplyImportData for better UX.
---@param importString string The import string
---@return boolean success Whether import succeeded
---@return string|nil errorMessage Error message if import failed
---@return table|nil metadata Metadata from the import (if successful)
function ImportExport.ImportProfile(importString)
    local data, errorMsg = ImportExport.ValidateImportString(importString)
    if not data then
        return false, errorMsg
    end

    local success, applyErr = ImportExport.ApplyImportData(data)
    if not success then
        return false, applyErr
    end

    return true, nil, data.metadata
end
