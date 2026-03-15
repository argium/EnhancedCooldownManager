-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ImportExport", function()
    local originalGlobals
    local ImportExport
    local ns
    local serializedInput
    local deserializeSuccess
    local deserializeValue
    local migrationCalls

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "LibStub",
            "C_AddOns",
            "time",
            "strtrim",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        serializedInput = nil
        deserializeSuccess = true
        deserializeValue = { profile = { imported = true } }
        migrationCalls = {}

        _G.ECM = {
            Log = function() end,
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        ECM.Migration = {
            Run = function(profile)
                migrationCalls[#migrationCalls + 1] = profile
            end,
        }

        _G.C_AddOns = {
            GetAddOnMetadata = function()
                return "1.2.3"
            end,
        }
        _G.time = function()
            return 123456
        end
        _G.strtrim = function(value)
            return (value:gsub("^%s+", ""):gsub("%s+$", ""))
        end

        _G.LibStub = function(name)
            if name == "LibSerialize" then
                return {
                    Serialize = function(_, data)
                        serializedInput = data
                        return "SERIALIZED"
                    end,
                    Deserialize = function(_, serialized)
                        if serialized == "BROKEN" then
                            return false, nil
                        end
                        return deserializeSuccess, deserializeValue
                    end,
                }
            end

            if name == "LibDeflate" then
                return {
                    CompressDeflate = function(_, serialized)
                        if serialized == "FAIL_COMPRESS" then
                            return nil
                        end
                        return "CMP:" .. serialized
                    end,
                    EncodeForPrint = function(_, compressed)
                        if compressed == "FAIL_ENCODE" then
                            return nil
                        end
                        return "ENC:" .. compressed
                    end,
                    DecodeForPrint = function(_, encoded)
                        if encoded == "bad" then
                            return nil
                        end
                        return encoded:gsub("^ENC:", "")
                    end,
                    DecompressDeflate = function(_, compressed)
                        if compressed == "badcmp" then
                            return nil
                        end
                        return compressed:gsub("^CMP:", "")
                    end,
                }
            end
        end

        ns = {
            Addon = {
                db = {
                    profile = {
                        schemaVersion = 10,
                        keepMe = true,
                        buffBars = {
                            colors = {
                                cache = {
                                    persisted = true,
                                },
                            },
                        },
                    },
                },
            },
        }

        TestHelpers.LoadChunk("Helpers/ImportExport.lua", "Unable to load Helpers/ImportExport.lua")(nil, ns)
        ImportExport = assert(ECM.ImportExport, "ImportExport did not initialize")
    end)

    it("EncodeData returns a shareable export string", function()
        local encoded, errorMessage = ImportExport.EncodeData({ profile = { enabled = true } })

        assert.is_nil(errorMessage)
        assert.are.equal("EnhancedCooldownManager:1:ENC:CMP:SERIALIZED", encoded)
    end)

    it("DecodeData rejects invalid input and corrupted payloads", function()
        local data, errorMessage = ImportExport.DecodeData("  ")
        assert.is_nil(data)
        assert.are.equal("Import string is empty", errorMessage)

        data, errorMessage = ImportExport.DecodeData("WrongPrefix:1:ENC:CMP:SERIALIZED")
        assert.is_nil(data)
        assert.is_true(errorMessage:find("not for Enhanced Cooldown Manager", 1, true) ~= nil)

        data, errorMessage = ImportExport.DecodeData("EnhancedCooldownManager:99:ENC:CMP:SERIALIZED")
        assert.is_nil(data)
        assert.is_true(errorMessage:find("Incompatible import string version", 1, true) ~= nil)

        data, errorMessage = ImportExport.DecodeData("EnhancedCooldownManager:1:bad")
        assert.is_nil(data)
        assert.are.equal("Failed to decode string - it may be corrupted or incomplete", errorMessage)

        data, errorMessage = ImportExport.DecodeData("EnhancedCooldownManager:1:ENC:badcmp")
        assert.is_nil(data)
        assert.are.equal("Failed to decompress data - the string may be corrupted", errorMessage)

        data, errorMessage = ImportExport.DecodeData("EnhancedCooldownManager:1:ENC:CMP:BROKEN")
        assert.is_nil(data)
        assert.are.equal("Failed to deserialize data - the string may be corrupted", errorMessage)
    end)

    it("ExportCurrentProfile excludes runtime cache data", function()
        local encoded = assert(ImportExport.ExportCurrentProfile())

        assert.are.equal("EnhancedCooldownManager:1:ENC:CMP:SERIALIZED", encoded)
        assert.are.equal("1.2.3", serializedInput.metadata.addonVersion)
        assert.are.equal(1, serializedInput.metadata.exportVersion)
        assert.are.equal(123456, serializedInput.metadata.exportedAt)
        assert.is_nil(serializedInput.profile.buffBars.colors.cache)
    end)

    it("ExportCurrentProfile errors on circular references", function()
        ns.Addon.db.profile.self = ns.Addon.db.profile

        assert.has_error(function()
            ImportExport.ExportCurrentProfile()
        end)
    end)

    it("ValidateImportString requires profile data", function()
        deserializeValue = { metadata = { exportVersion = 1 } }

        local data, errorMessage = ImportExport.ValidateImportString("EnhancedCooldownManager:1:ENC:CMP:SERIALIZED")
        assert.is_nil(data)
        assert.are.equal("Import string does not contain profile data", errorMessage)
    end)

    it("ApplyImportData preserves cache and runs migrations for older schemas", function()
        local success, errorMessage = ImportExport.ApplyImportData({
            profile = {
                schemaVersion = 9,
                importedField = "yes",
                buffBars = {
                    colors = {},
                },
            },
        })

        assert.is_true(success)
        assert.is_nil(errorMessage)
        assert.are.equal("yes", ns.Addon.db.profile.importedField)
        assert.same({ persisted = true }, ns.Addon.db.profile.buffBars.colors.cache)
        assert.are.equal(1, #migrationCalls)
        assert.are.equal(ns.Addon.db.profile, migrationCalls[1])
    end)

    it("ApplyImportData validates input and active profile availability", function()
        local success, errorMessage = ImportExport.ApplyImportData({})
        assert.is_false(success)
        assert.are.equal("Invalid import data", errorMessage)

        ns.Addon.db = nil
        success, errorMessage = ImportExport.ApplyImportData({ profile = { schemaVersion = 10 } })
        assert.is_false(success)
        assert.are.equal("No active profile to import into", errorMessage)
    end)
end)
