-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

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
    local logMessages

    local function findLogMessage(needle)
        for _, message in ipairs(logMessages or {}) do
            if type(message) == "string" and string.find(message, needle, 1, true) then
                return message
            end
        end
        return nil
    end

    local function findLogMessages(needle)
        local matches = {}
        for _, message in ipairs(logMessages or {}) do
            if type(message) == "string" and string.find(message, needle, 1, true) then
                matches[#matches + 1] = message
            end
        end
        return matches
    end

    local function findLogMessageIndex(needle)
        for i, message in ipairs(logMessages or {}) do
            if type(message) == "string" and string.find(message, needle, 1, true) then
                return i
            end
        end
        return nil
    end

    local function parseMetric(message, key)
        if type(message) ~= "string" then
            return nil
        end
        local value = string.match(message, "%f[%w]" .. key .. "=(%d+)")
        return value and tonumber(value) or nil
    end

    local function parseTierMetrics(message, tier)
        if type(message) ~= "string" then
            return nil
        end
        local s, i, f = string.match(message, tier .. "%(s=(%d+) i=(%d+) f=(%d+)%)")
        if not (s and i and f) then
            return nil
        end
        return {
            scanned = tonumber(s),
            invalid = tonumber(i),
            final = tonumber(f),
        }
    end

    local function countKeys(tbl)
        if type(tbl) ~= "table" then
            return 0
        end
        local n = 0
        for _ in pairs(tbl) do
            n = n + 1
        end
        return n
    end

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
        logMessages = {}
        _G.ECM = {}
        _G.ECM_log = function(_, _, message)
            logMessages[#logMessages + 1] = message
        end
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

    it("migrates schema 8 to 10, backfills fallback tiers, and stores metadata on wrappers", function()
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

        assert.are.equal(10, profile.schemaVersion)
        assert.is_nil(persistedColor.keyType)
        assert.is_nil(persistedColor.spellID)
        assert.is_nil(persistedColor.cooldownID)
        assert.is_nil(persistedColor.textureId)
        assert.are.equal("spellName", stamped.meta.keyType)
        assert.are.equal("Persisted Spell", stamped.meta.spellName)
        assert.are.equal(1357, stamped.meta.spellID)
        assert.are.equal(2468, stamped.meta.cooldownID)
        assert.are.equal(3699, stamped.meta.textureFileID)
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

        assert.are.equal(10, profile.schemaVersion)
        assert.are.equal("spellID", spellIDEntry.meta.keyType)
        assert.are.equal(2468, spellIDEntry.meta.spellID)
        assert.are.equal("cooldownID", cooldownEntry.meta.keyType)
        assert.are.equal(135, cooldownEntry.meta.cooldownID)
        assert.are.equal("textureFileID", textureEntry.meta.keyType)
        assert.are.equal(9876, textureEntry.meta.textureFileID)
        assert.is_nil(spellIDEntry.value.keyType)
        assert.is_nil(spellIDEntry.value.spellID)
        assert.is_nil(cooldownEntry.value.cooldownID)
        assert.is_nil(textureEntry.value.textureId)
    end)

    it("collapses existing fallback-tier duplicates into a single wrapper", function()
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

        assert.are.equal(10, profile.schemaVersion)
        assert.are.same(byNameEntry, profile.buffBars.colors.byName[12][2]["Do Not Replace"])
        assert.are.same(byNameEntry, profile.buffBars.colors.bySpellID[12][2][1001])
        assert.are.same(byNameEntry, profile.buffBars.colors.byCooldownID[12][2][1002])
        assert.are.same(byNameEntry, profile.buffBars.colors.byTexture[12][2][1003])
        assert.are.equal("spellName", byNameEntry.meta.keyType)
        assert.are.equal("Do Not Replace", byNameEntry.meta.spellName)
    end)

    it("handles missing buffBars or invalid colors tables while advancing schema", function()
        local noBuffBars = {
            schemaVersion = 8,
        }
        Migration.Run(noBuffBars)
        assert.are.equal(10, noBuffBars.schemaVersion)

        local invalidColors = {
            schemaVersion = 8,
            buffBars = {
                colors = "invalid",
            },
        }
        Migration.Run(invalidColors)
        assert.are.equal(10, invalidColors.schemaVersion)
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
        assert.are.equal(10, invalidByName.schemaVersion)
        assert.is_table(invalidByName.buffBars.colors.byName)
    end)

    it("logs V10 diagnostic summary and anomaly details for malformed spell-color stores", function()
        local byNameEntry = {
            value = { r = 0.2, g = 0.3, b = 0.4, a = 1, spellID = 111, cooldownID = 222, textureId = 333 },
            t = 1,
        }
        local bySpellIDEntry = {
            value = { r = 0.9, g = 0.8, b = 0.7, a = 1 },
            t = 2,
        }
        local profile = {
            schemaVersion = 9,
            buffBars = {
                colors = {
                    byName = {
                        [12] = {
                            [2] = {
                                ["Diagnostic Spell"] = byNameEntry,
                                ["Broken Wrapper"] = true,
                            },
                        },
                    },
                    bySpellID = {
                        [12] = {
                            [2] = {
                                [111] = bySpellIDEntry,
                                [999] = { value = "bad-value" },
                            },
                        },
                    },
                    byCooldownID = "bad-tier",
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(10, profile.schemaVersion)
        local summary = assert(findLogMessage("V10 spell color normalization summary:"))
        local tierBreakdown = assert(findLogMessage("V10 tier breakdown:"))
        local created = assert(findLogMessage("V10 created missing tier stores: byCooldownID, byTexture"))
        local anomaly = assert(findLogMessage("V10 anomaly: class=12 spec=2"))
        local overflow = findLogMessage("V10 anomaly: additional specs omitted=")

        local summaryIndex = assert(findLogMessageIndex("V10 spell color normalization summary:"))
        local tierIndex = assert(findLogMessageIndex("V10 tier breakdown:"))
        local createdIndex = assert(findLogMessageIndex("V10 created missing tier stores: byCooldownID, byTexture"))
        local anomalyIndex = assert(findLogMessageIndex("V10 anomaly: class=12 spec=2"))
        local migratedIndex = assert(findLogMessageIndex("Migrated to V10"))

        assert.is_true(summaryIndex < tierIndex)
        assert.is_true(tierIndex < createdIndex)
        assert.is_true(createdIndex < anomalyIndex)
        assert.is_true(anomalyIndex < migratedIndex)
        assert.is_nil(overflow)
        assert.are.equal(1, #findLogMessages("V10 anomaly: class=12 spec=2"))
        assert.are.equal(1, #findLogMessages("V10 spell color normalization summary:"))
        assert.are.equal(1, #findLogMessages("V10 tier breakdown:"))
        assert.are.equal(1, #findLogMessages("V10 created missing tier stores: byCooldownID, byTexture"))

        assert.are.equal(4, parseMetric(summary, "scanned"))
        assert.are.equal(2, parseMetric(summary, "valid"))
        assert.are.equal(1, parseMetric(summary, "canonical"))
        assert.are.equal(1, parseMetric(summary, "aliases"))
        assert.are.equal(2, parseMetric(summary, "invalid"))
        assert.are.equal(2, parseMetric(summary, "invalidRetained"))
        assert.are.equal(0, parseMetric(summary, "invalidKeyCollisions"))
        assert.are.equal(1, parseMetric(summary, "metaNormalized"))
        assert.are.equal(6, parseMetric(summary, "final"))

        assert.is_not_nil(string.find(anomaly, "aliases=1", 1, true))
        assert.is_not_nil(string.find(anomaly, "invalid=2", 1, true))
        assert.is_not_nil(string.find(anomaly, "invalidByTier[byName=1,bySpellID=1]", 1, true))
        assert.are.equal("V10 created missing tier stores: byCooldownID, byTexture", created)

        local byNameTier = assert(parseTierMetrics(tierBreakdown, "byName"))
        local bySpellIDTier = assert(parseTierMetrics(tierBreakdown, "bySpellID"))
        local byCooldownIDTier = assert(parseTierMetrics(tierBreakdown, "byCooldownID"))
        local byTextureTier = assert(parseTierMetrics(tierBreakdown, "byTexture"))
        assert.are.same({ scanned = 2, invalid = 1, final = 2 }, byNameTier)
        assert.are.same({ scanned = 2, invalid = 1, final = 2 }, bySpellIDTier)
        assert.are.same({ scanned = 0, invalid = 0, final = 1 }, byCooldownIDTier)
        assert.are.same({ scanned = 0, invalid = 0, final = 1 }, byTextureTier)

        local colors = profile.buffBars.colors
        local byNameSpec = colors.byName[12][2]
        local bySpellIDSpec = colors.bySpellID[12][2]
        local byCooldownIDSpec = colors.byCooldownID[12][2]
        local byTextureSpec = colors.byTexture[12][2]
        local canonical = byNameSpec["Diagnostic Spell"]

        assert.are.same(canonical, bySpellIDSpec[111])
        assert.are.same(canonical, byCooldownIDSpec[222])
        assert.are.same(canonical, byTextureSpec[333])
        assert.are.equal("spellName", canonical.meta.keyType)
        assert.are.equal("Diagnostic Spell", canonical.meta.spellName)
        assert.are.equal(111, canonical.meta.spellID)
        assert.are.equal(222, canonical.meta.cooldownID)
        assert.are.equal(333, canonical.meta.textureFileID)

        assert.is_true(byNameSpec["Broken Wrapper"])
        assert.is_table(bySpellIDSpec[999])
        assert.are.equal("bad-value", bySpellIDSpec[999].value)

        assert.are.equal(byNameTier.final, countKeys(byNameSpec))
        assert.are.equal(bySpellIDTier.final, countKeys(bySpellIDSpec))
        assert.are.equal(byCooldownIDTier.final, countKeys(byCooldownIDSpec))
        assert.are.equal(byTextureTier.final, countKeys(byTextureSpec))
        assert.are.equal(
            parseMetric(summary, "final"),
            byNameTier.final + bySpellIDTier.final + byCooldownIDTier.final + byTextureTier.final
        )
        assert.are.equal(
            parseMetric(summary, "scanned"),
            byNameTier.scanned + bySpellIDTier.scanned + byCooldownIDTier.scanned + byTextureTier.scanned
        )
        assert.are.equal(
            parseMetric(summary, "invalid"),
            byNameTier.invalid + bySpellIDTier.invalid + byCooldownIDTier.invalid + byTextureTier.invalid
        )
        assert.are.equal(parseMetric(summary, "valid"), parseMetric(summary, "scanned") - parseMetric(summary, "invalid"))
    end)

    it("logs V10 skip diagnostics when spell-color stores are unavailable", function()
        local noBuffBars = { schemaVersion = 9 }
        Migration.Run(noBuffBars)

        assert.are.equal(10, noBuffBars.schemaVersion)
        assert.is_not_nil(findLogMessage("V10 spell color normalization skipped: buffBars.colors missing"))
        assert.is_nil(findLogMessage("V10 spell color normalization summary:"))
        assert.is_nil(findLogMessage("V10 tier breakdown:"))
        assert.is_nil(findLogMessage("V10 anomaly:"))

        logMessages = {}
        local invalidColors = {
            schemaVersion = 9,
            buffBars = { colors = "invalid" },
        }
        Migration.Run(invalidColors)

        assert.are.equal(10, invalidColors.schemaVersion)
        assert.is_not_nil(findLogMessage("V10 spell color normalization skipped: buffBars.colors missing"))
        assert.is_nil(findLogMessage("V10 spell color normalization summary:"))
        assert.is_nil(findLogMessage("V10 tier breakdown:"))
        assert.is_nil(findLogMessage("V10 anomaly:"))
    end)

    it("caps V10 anomaly logs and reports omitted spec count", function()
        local byName = { [12] = {} }
        for specID = 1, 22 do
            byName[12][specID] = {
                ["Broken " .. specID] = true,
            }
        end

        local profile = {
            schemaVersion = 9,
            buffBars = {
                colors = {
                    byName = byName,
                    bySpellID = {},
                    byCooldownID = {},
                    byTexture = {},
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(10, profile.schemaVersion)
        local summary = assert(findLogMessage("V10 spell color normalization summary:"))
        local tierBreakdown = assert(findLogMessage("V10 tier breakdown:"))
        local specAnomalies = findLogMessages("V10 anomaly: class=12 spec=")
        local allAnomalies = findLogMessages("V10 anomaly:")
        local overflow = assert(findLogMessage("V10 anomaly: additional specs omitted="))

        assert.are.equal(1, parseMetric(summary, "classes"))
        assert.are.equal(22, parseMetric(summary, "specs"))
        assert.are.equal(22, parseMetric(summary, "scanned"))
        assert.are.equal(0, parseMetric(summary, "valid"))
        assert.are.equal(0, parseMetric(summary, "canonical"))
        assert.are.equal(0, parseMetric(summary, "aliases"))
        assert.are.equal(22, parseMetric(summary, "invalid"))
        assert.are.equal(22, parseMetric(summary, "invalidRetained"))
        assert.are.equal(0, parseMetric(summary, "invalidKeyCollisions"))
        assert.are.equal(0, parseMetric(summary, "metaNormalized"))
        assert.are.equal(22, parseMetric(summary, "final"))

        local byNameTier = assert(parseTierMetrics(tierBreakdown, "byName"))
        local bySpellIDTier = assert(parseTierMetrics(tierBreakdown, "bySpellID"))
        local byCooldownIDTier = assert(parseTierMetrics(tierBreakdown, "byCooldownID"))
        local byTextureTier = assert(parseTierMetrics(tierBreakdown, "byTexture"))
        assert.are.same({ scanned = 22, invalid = 22, final = 22 }, byNameTier)
        assert.are.same({ scanned = 0, invalid = 0, final = 0 }, bySpellIDTier)
        assert.are.same({ scanned = 0, invalid = 0, final = 0 }, byCooldownIDTier)
        assert.are.same({ scanned = 0, invalid = 0, final = 0 }, byTextureTier)

        assert.are.equal(20, #specAnomalies)
        assert.are.equal(21, #allAnomalies)
        assert.is_not_nil(string.find(overflow, "omitted=2", 1, true))
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

        assert.are.equal(10, profile.schemaVersion)
        assert.is_table(profile.buffBars.colors.bySpellID)
        assert.is_table(profile.buffBars.colors.byCooldownID)
        assert.is_table(profile.buffBars.colors.byTexture)
        assert.are.same(entry, profile.buffBars.colors.bySpellID[12][2][7001])
        assert.are.same(entry, profile.buffBars.colors.byCooldownID[12][2][7002])
        assert.are.same(entry, profile.buffBars.colors.byTexture[12][2][7003])
        assert.are.equal("spellName", entry.meta.keyType)
        assert.are.equal("Init Me", entry.meta.spellName)
        assert.are.equal(7001, entry.meta.spellID)
        assert.are.equal(7002, entry.meta.cooldownID)
        assert.are.equal(7003, entry.meta.textureFileID)
    end)

    it("moves legacy metadata to wrapper meta and normalizes color payloads", function()
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

        assert.are.equal(10, profile.schemaVersion)
        assert.are.equal("spellName", byNameEntry.meta.keyType)
        assert.are.equal("KeepNameMetadata", byNameEntry.meta.spellName)
        assert.are.equal("spellID", bySpellIDEntry.meta.keyType)
        assert.are.equal(2468, bySpellIDEntry.meta.spellID)
        assert.are.equal("cooldownID", byCooldownEntry.meta.keyType)
        assert.are.equal(1357, byCooldownEntry.meta.cooldownID)
        assert.are.equal("textureFileID", byTextureEntry.meta.keyType)
        assert.are.equal(9876, byTextureEntry.meta.textureFileID)
        assert.is_nil(byNameEntry.value.keyType)
        assert.is_nil(bySpellIDEntry.value.spellID)
        assert.is_nil(byCooldownEntry.value.cooldownID)
        assert.is_nil(byTextureEntry.value.textureId)
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

        assert.are.equal(10, profile.schemaVersion)
        assert.is_table(profile.buffBars.colors.bySpellID[12][2])
        assert.is_table(profile.buffBars.colors.byCooldownID[12][2])
        assert.is_table(profile.buffBars.colors.byTexture[12][2])
        assert.is_nil(profile.buffBars.colors.bySpellID[12][2]["7001"])
        assert.is_nil(profile.buffBars.colors.byCooldownID[12][2][false])
        assert.is_nil(profile.buffBars.colors.byTexture[12][2]["7003"])
        assert.is_true(profile.buffBars.colors.bySpellID[12][2][100])
        assert.are.same({ value = "nope" }, profile.buffBars.colors.bySpellID[12][2][200])
    end)

    it("migrates schema version 9 to 10 and normalizes wrapper metadata", function()
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

        assert.are.equal(10, profile.schemaVersion)
        assert.are.equal("spellName", byNameEntry.meta.keyType)
        assert.are.equal(9001, byNameEntry.meta.spellID)
        assert.are.equal(9002, byNameEntry.meta.cooldownID)
        assert.are.equal(9003, byNameEntry.meta.textureFileID)
        assert.are.same(byNameEntry, profile.buffBars.colors.bySpellID[12][2][9001])
        assert.are.same(byNameEntry, profile.buffBars.colors.byCooldownID[12][2][9002])
        assert.are.same(byNameEntry, profile.buffBars.colors.byTexture[12][2][9003])
        assert.is_nil(byNameEntry.value.spellID)
        assert.is_nil(byNameEntry.value.cooldownID)
        assert.is_nil(byNameEntry.value.textureId)
        assert.are.same(byNameEntry, profile.buffBars.colors.bySpellID[12][2][9001])
        assert.is_nil(spellIDEntry.meta)
    end)

    it("is a no-op for schema versions above 10", function()
        local spellIDEntry = { value = { r = 0.3, g = 0.3, b = 0.3, a = 1 } }
        local profile = {
            schemaVersion = 11,
            buffBars = {
                colors = {
                    bySpellID = { [12] = { [2] = { [1234] = spellIDEntry } } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(11, profile.schemaVersion)
        assert.is_nil(spellIDEntry.value.keyType)
        assert.is_nil(spellIDEntry.value.spellID)
        assert.is_nil(profile.buffBars.colors.byCooldownID)
        assert.is_nil(profile.buffBars.colors.byTexture)
    end)

    it("collapses fragmented spell-color entries across tiers and keeps newest timestamp", function()
        local byNameEntry = { value = { r = 0.1, g = 0.2, b = 0.3, a = 1, spellID = 203720 }, t = 10 }
        local bySpellEntry = { value = { r = 0.9, g = 0.8, b = 0.7, a = 1, cooldownID = 11431 }, t = 30 }
        local byTextureEntry = { value = { r = 0.4, g = 0.4, b = 0.4, a = 1, spellID = 203720 }, t = 20 }
        local profile = {
            schemaVersion = 9,
            buffBars = {
                colors = {
                    byName = { [12] = { [2] = { ["Demon Spikes"] = byNameEntry } } },
                    bySpellID = { [12] = { [2] = { [203720] = bySpellEntry } } },
                    byCooldownID = { [12] = { [2] = {} } },
                    byTexture = { [12] = { [2] = { [1344645] = byTextureEntry } } },
                },
            },
        }

        Migration.Run(profile)

        assert.are.equal(10, profile.schemaVersion)
        local winner = profile.buffBars.colors.bySpellID[12][2][203720]
        assert.are.same(bySpellEntry, winner)
        assert.are.same(winner, profile.buffBars.colors.byName[12][2]["Demon Spikes"])
        assert.are.same(winner, profile.buffBars.colors.byCooldownID[12][2][11431])
        assert.are.same(winner, profile.buffBars.colors.byTexture[12][2][1344645])
        assert.are.equal("spellName", winner.meta.keyType)
        assert.are.equal("Demon Spikes", winner.meta.spellName)
        assert.are.equal(203720, winner.meta.spellID)
        assert.are.equal(11431, winner.meta.cooldownID)
        assert.are.equal(1344645, winner.meta.textureFileID)
        assert.is_nil(winner.value.spellID)
        assert.is_nil(winner.value.cooldownID)
        assert.is_nil(winner.value.textureId)
    end)
end)
