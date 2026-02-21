if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("Migration", function()
    local originalGlobals
    local Migration

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "ECM_log",
            "date",
            "strtrim",
            "wipe",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {}
        _G.ECM_log = function() end
        _G.date = function()
            return "2026-02-21 00:00:00"
        end
        _G.strtrim = function(s)
            return tostring(s):match("^%s*(.-)%s*$")
        end
        _G.wipe = function(tbl)
            for k in pairs(tbl) do
                tbl[k] = nil
            end
        end

        local constantsChunk = TestHelpers.loadChunk(
            {
                "Constants.lua",
                "../Constants.lua",
            },
            "Unable to load Constants.lua"
        )
        constantsChunk()

        local migrationChunk = TestHelpers.loadChunk(
            {
                "Options/Migration.lua",
                "../Options/Migration.lua",
            },
            "Unable to load Options/Migration.lua"
        )
        migrationChunk()

        Migration = assert(ECM.Migration, "Migration module did not initialize")
    end)

    it("migrates schema 8 to 9 and backfills fallback tiers from byName", function()
        local persistedColor = { r = 0.9, g = 0.1, b = 0.7, a = 1, spellID = 1357, cooldownID = 2468, textureId = 3699 }
        local stamped = { value = persistedColor, t = 5 }

        local profile = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = {
                        [12] = {
                            [2] = {
                                ["Persisted Spell"] = stamped,
                            },
                        },
                    },
                    bySpellID = { [12] = { [2] = {} } },
                    byCooldownID = { [12] = { [2] = {} } },
                    byTexture = { [12] = { [2] = {} } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.are.equal("spellName", persistedColor.keyType)
        assert.are.same(stamped, profile.buffBars.colors.bySpellID[12][2][1357])
        assert.are.same(stamped, profile.buffBars.colors.byCooldownID[12][2][2468])
        assert.are.same(stamped, profile.buffBars.colors.byTexture[12][2][3699])
    end)

    it("fills missing key metadata in spellID, cooldownID, and texture tiers", function()
        local spellIDEntry = { value = { r = 0.2, g = 0.3, b = 0.4, a = 1 } }
        local cooldownEntry = { value = { r = 0.3, g = 0.4, b = 0.5, a = 1 } }
        local textureEntry = { value = { r = 0.4, g = 0.5, b = 0.6, a = 1 } }

        local profile = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = {},
                    bySpellID = { [12] = { [2] = { [2468] = spellIDEntry } } },
                    byCooldownID = { [12] = { [2] = { [135] = cooldownEntry } } },
                    byTexture = { [12] = { [2] = { [9876] = textureEntry } } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.are.equal("spellID", spellIDEntry.value.keyType)
        assert.are.equal(2468, spellIDEntry.value.spellID)
        assert.are.equal("cooldownID", cooldownEntry.value.keyType)
        assert.are.equal(135, cooldownEntry.value.cooldownID)
        assert.are.equal("textureFileID", textureEntry.value.keyType)
        assert.are.equal(9876, textureEntry.value.textureId)
    end)

    it("does not overwrite existing fallback-tier entries", function()
        local byNameEntry = { value = { r = 0.1, g = 0.2, b = 0.3, a = 1, spellID = 1001, cooldownID = 1002, textureId = 1003 } }
        local existingSpellID = { value = { r = 0.8, g = 0.8, b = 0.8, a = 1 } }
        local existingCooldownID = { value = { r = 0.7, g = 0.7, b = 0.7, a = 1 } }
        local existingTexture = { value = { r = 0.6, g = 0.6, b = 0.6, a = 1 } }

        local profile = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = { [12] = { [2] = { ["Do Not Replace"] = byNameEntry } } },
                    bySpellID = { [12] = { [2] = { [1001] = existingSpellID } } },
                    byCooldownID = { [12] = { [2] = { [1002] = existingCooldownID } } },
                    byTexture = { [12] = { [2] = { [1003] = existingTexture } } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.are.same(existingSpellID, profile.buffBars.colors.bySpellID[12][2][1001])
        assert.are.same(existingCooldownID, profile.buffBars.colors.byCooldownID[12][2][1002])
        assert.are.same(existingTexture, profile.buffBars.colors.byTexture[12][2][1003])
    end)

    it("handles missing buffBars or invalid colors tables while advancing schema", function()
        local noBuffBars = {
            schemaVersion = 8,
        }
        Migration.Run(noBuffBars)
        assert.are.equal(9, noBuffBars.schemaVersion)

        local invalidColors = {
            schemaVersion = 8,
            buffBars = {
                colors = "invalid",
            },
        }
        Migration.Run(invalidColors)
        assert.are.equal(9, invalidColors.schemaVersion)
        assert.are.equal("invalid", invalidColors.buffBars.colors)

        local invalidByName = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = "bad",
                    bySpellID = {},
                    byCooldownID = {},
                    byTexture = {},
                },
            },
        }
        Migration.Run(invalidByName)
        assert.are.equal(9, invalidByName.schemaVersion)
        assert.is_table(invalidByName.buffBars.colors.byName)
    end)

    it("initializes invalid tier tables and creates class/spec buckets during backfill", function()
        local entry = { value = { r = 0.5, g = 0.5, b = 0.5, a = 1, spellID = 7001, cooldownID = 7002, textureId = 7003 } }
        local profile = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = { [12] = { [2] = { ["Init Me"] = entry } } },
                    bySpellID = "bad",
                    byCooldownID = false,
                    byTexture = 123,
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.is_table(profile.buffBars.colors.bySpellID)
        assert.is_table(profile.buffBars.colors.byCooldownID)
        assert.is_table(profile.buffBars.colors.byTexture)
        assert.are.same(entry, profile.buffBars.colors.bySpellID[12][2][7001])
        assert.are.same(entry, profile.buffBars.colors.byCooldownID[12][2][7002])
        assert.are.same(entry, profile.buffBars.colors.byTexture[12][2][7003])
    end)

    it("does not overwrite existing keyType or ID metadata fields", function()
        local byNameEntry = { value = { r = 0.1, g = 0.2, b = 0.3, a = 1, keyType = "customName" } }
        local bySpellIDEntry = { value = { r = 0.2, g = 0.3, b = 0.4, a = 1, keyType = "customSpell", spellID = 999 } }
        local byCooldownEntry = { value = { r = 0.3, g = 0.4, b = 0.5, a = 1, keyType = "customCooldown", cooldownID = 888 } }
        local byTextureEntry = { value = { r = 0.4, g = 0.5, b = 0.6, a = 1, keyType = "customTexture", textureId = 777 } }

        local profile = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = { [12] = { [2] = { ["KeepNameMetadata"] = byNameEntry } } },
                    bySpellID = { [12] = { [2] = { [2468] = bySpellIDEntry } } },
                    byCooldownID = { [12] = { [2] = { [1357] = byCooldownEntry } } },
                    byTexture = { [12] = { [2] = { [9876] = byTextureEntry } } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.are.equal("customName", byNameEntry.value.keyType)
        assert.are.equal("customSpell", bySpellIDEntry.value.keyType)
        assert.are.equal(999, bySpellIDEntry.value.spellID)
        assert.are.equal("customCooldown", byCooldownEntry.value.keyType)
        assert.are.equal(888, byCooldownEntry.value.cooldownID)
        assert.are.equal("customTexture", byTextureEntry.value.keyType)
        assert.are.equal(777, byTextureEntry.value.textureId)
    end)

    it("ignores invalid wrapped entries and non-numeric byName IDs during backfill", function()
        local profile = {
            schemaVersion = 8,
            buffBars = {
                colors = {
                    byName = {
                        [12] = {
                            [2] = {
                                ["Bad IDs"] = {
                                    value = { r = 0.1, g = 0.2, b = 0.3, a = 1, spellID = "7001", cooldownID = false, textureId = "7003" },
                                },
                                ["Invalid Entry"] = true,
                                ["Invalid Value"] = { value = "not-a-table" },
                            },
                        },
                    },
                    bySpellID = { [12] = { [2] = { [100] = true, [200] = { value = "nope" } } } },
                    byCooldownID = { [12] = "not-a-table" },
                    byTexture = { [12] = { [2] = "not-a-table" } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.is_table(profile.buffBars.colors.bySpellID[12][2])
        assert.is_table(profile.buffBars.colors.byCooldownID[12][2])
        assert.is_table(profile.buffBars.colors.byTexture[12][2])
        assert.is_nil(profile.buffBars.colors.bySpellID[12][2]["7001"])
        assert.is_nil(profile.buffBars.colors.byCooldownID[12][2][false])
        assert.is_nil(profile.buffBars.colors.byTexture[12][2]["7003"])
        assert.is_true(profile.buffBars.colors.bySpellID[12][2][100])
        assert.are.same({ value = "nope" }, profile.buffBars.colors.bySpellID[12][2][200])
    end)

    it("is a no-op for schema version 9", function()
        local byNameEntry = {
            value = { r = 0.4, g = 0.4, b = 0.4, a = 1, spellID = 9001, cooldownID = 9002, textureId = 9003 }
        }
        local spellIDEntry = { value = { r = 0.3, g = 0.3, b = 0.3, a = 1 } }

        local profile = {
            schemaVersion = 9,
            buffBars = {
                colors = {
                    byName = { [12] = { [2] = { ["NoOp"] = byNameEntry } } },
                    bySpellID = { [12] = { [2] = { [9001] = spellIDEntry } } },
                    byCooldownID = {},
                    byTexture = {},
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(9, profile.schemaVersion)
        assert.is_nil(spellIDEntry.value.keyType)
        assert.is_nil(spellIDEntry.value.spellID)
        assert.is_nil(profile.buffBars.colors.byCooldownID[12])
        assert.is_nil(profile.buffBars.colors.byTexture[12])
    end)

    it("is a no-op for schema versions above 9", function()
        local spellIDEntry = { value = { r = 0.3, g = 0.3, b = 0.3, a = 1 } }
        local profile = {
            schemaVersion = 10,
            buffBars = {
                colors = {
                    bySpellID = { [12] = { [2] = { [1234] = spellIDEntry } } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(10, profile.schemaVersion)
        assert.is_nil(spellIDEntry.value.keyType)
        assert.is_nil(spellIDEntry.value.spellID)
        assert.is_nil(profile.buffBars.colors.byCooldownID)
        assert.is_nil(profile.buffBars.colors.byTexture)
    end)
end)
