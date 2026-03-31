-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("Migration", function()
    local originalGlobals
    local Migration
    local logMessages
    local assertAbsolutePositionPreserved = TestHelpers.assertAbsolutePositionPreserved
    local ns

    local function searchLogMessages(needle)
        local matches, firstIndex = {}, nil
        for i, message in ipairs(logMessages) do
            if string.find(message, needle, 1, true) then
                if not firstIndex then
                    firstIndex = i
                end
                matches[#matches + 1] = message
            end
        end
        return matches[1], matches, firstIndex
    end

    local function parseMetric(message, key)
        local value = string.match(message, "%f[%w]" .. key .. "=(%d+)")
        return value and tonumber(value) or nil
    end

    local function parseTierMetrics(message, tier)
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
        local n = 0
        for _ in pairs(tbl) do
            n = n + 1
        end
        return n
    end

    local function extractAllTierMetrics(tierBreakdown)
        return {
            byName = assert(parseTierMetrics(tierBreakdown, "byName")),
            bySpellID = assert(parseTierMetrics(tierBreakdown, "bySpellID")),
            byCooldownID = assert(parseTierMetrics(tierBreakdown, "byCooldownID")),
            byTexture = assert(parseTierMetrics(tierBreakdown, "byTexture")),
        }
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "C_EditMode",
            "date",
            "strtrim",
            "UIParent",
            "LibStub",
            "wipe",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        logMessages = {}
        ns = {}
        _G.C_EditMode = {
            GetLayouts = function()
                return { activeLayout = 1, layouts = {} }
            end,
        }
        ns.Log = function(_, message)
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
        _G.UIParent = {
            GetWidth = function()
                return 1920
            end,
            GetHeight = function()
                return 1080
            end,
        }

        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)
        TestHelpers.LoadChunk("FrameUtil.lua", "Unable to load FrameUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("Migration.lua", "Unable to load Migration.lua")(nil, ns)

        Migration = assert(ns.Migration, "Migration module did not initialize")
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

        assert.are.equal(11, profile.schemaVersion)
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

        assert.are.equal(11, profile.schemaVersion)
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
        local byNameEntry =
            { value = { r = 0.1, g = 0.2, b = 0.3, a = 1, spellID = 1001, cooldownID = 1002, textureId = 1003 } }
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

        assert.are.equal(11, profile.schemaVersion)
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
        assert.are.equal(11, noBuffBars.schemaVersion)

        local invalidColors = {
            schemaVersion = 8,
            buffBars = {
                colors = "invalid",
            },
        }
        Migration.Run(invalidColors)
        assert.are.equal(11, invalidColors.schemaVersion)
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
        assert.are.equal(11, invalidByName.schemaVersion)
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

        assert.are.equal(11, profile.schemaVersion)
        local summary = assert(searchLogMessages("V10 spell color normalization summary:"))
        local tierBreakdown = assert(searchLogMessages("V10 tier breakdown:"))
        local created = assert(searchLogMessages("V10 created missing tier stores: byCooldownID, byTexture"))
        local anomaly = assert(searchLogMessages("V10 anomaly: class=12 spec=2"))

        local summaryIndex = assert(select(3, searchLogMessages("V10 spell color normalization summary:")))
        local tierIndex = assert(select(3, searchLogMessages("V10 tier breakdown:")))
        local createdIndex =
            assert(select(3, searchLogMessages("V10 created missing tier stores: byCooldownID, byTexture")))
        local anomalyIndex = assert(select(3, searchLogMessages("V10 anomaly: class=12 spec=2")))
        local migratedIndex = assert(select(3, searchLogMessages("Migrated to V10")))

        assert.is_true(summaryIndex < tierIndex)
        assert.is_true(tierIndex < createdIndex)
        assert.is_true(createdIndex < anomalyIndex)
        assert.is_true(anomalyIndex < migratedIndex)
        assert.is_nil(searchLogMessages("V10 anomaly: additional specs omitted="))
        assert.are.equal(1, #select(2, searchLogMessages("V10 anomaly: class=12 spec=2")))
        assert.are.equal(1, #select(2, searchLogMessages("V10 spell color normalization summary:")))
        assert.are.equal(1, #select(2, searchLogMessages("V10 tier breakdown:")))
        assert.are.equal(1, #select(2, searchLogMessages("V10 created missing tier stores: byCooldownID, byTexture")))

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

        local tiers = extractAllTierMetrics(tierBreakdown)
        assert.are.same({ scanned = 2, invalid = 1, final = 2 }, tiers.byName)
        assert.are.same({ scanned = 2, invalid = 1, final = 2 }, tiers.bySpellID)
        assert.are.same({ scanned = 0, invalid = 0, final = 1 }, tiers.byCooldownID)
        assert.are.same({ scanned = 0, invalid = 0, final = 1 }, tiers.byTexture)

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

        assert.are.equal(tiers.byName.final, countKeys(byNameSpec))
        assert.are.equal(tiers.bySpellID.final, countKeys(bySpellIDSpec))
        assert.are.equal(tiers.byCooldownID.final, countKeys(byCooldownIDSpec))
        assert.are.equal(tiers.byTexture.final, countKeys(byTextureSpec))
        assert.are.equal(
            parseMetric(summary, "final"),
            tiers.byName.final + tiers.bySpellID.final + tiers.byCooldownID.final + tiers.byTexture.final
        )
        assert.are.equal(
            parseMetric(summary, "scanned"),
            tiers.byName.scanned + tiers.bySpellID.scanned + tiers.byCooldownID.scanned + tiers.byTexture.scanned
        )
        assert.are.equal(
            parseMetric(summary, "invalid"),
            tiers.byName.invalid + tiers.bySpellID.invalid + tiers.byCooldownID.invalid + tiers.byTexture.invalid
        )
        assert.are.equal(
            parseMetric(summary, "valid"),
            parseMetric(summary, "scanned") - parseMetric(summary, "invalid")
        )
    end)

    it("logs V10 skip diagnostics when spell-color stores are unavailable", function()
        local noBuffBars = { schemaVersion = 9 }
        Migration.Run(noBuffBars)

        assert.are.equal(11, noBuffBars.schemaVersion)
        assert.is_not_nil(searchLogMessages("V10 spell color normalization skipped: buffBars.colors missing"))
        assert.is_nil(searchLogMessages("V10 spell color normalization summary:"))
        assert.is_nil(searchLogMessages("V10 tier breakdown:"))
        assert.is_nil(searchLogMessages("V10 anomaly:"))

        logMessages = {}
        local invalidColors = {
            schemaVersion = 9,
            buffBars = { colors = "invalid" },
        }
        Migration.Run(invalidColors)

        assert.are.equal(11, invalidColors.schemaVersion)
        assert.is_not_nil(searchLogMessages("V10 spell color normalization skipped: buffBars.colors missing"))
        assert.is_nil(searchLogMessages("V10 spell color normalization summary:"))
        assert.is_nil(searchLogMessages("V10 tier breakdown:"))
        assert.is_nil(searchLogMessages("V10 anomaly:"))
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

        assert.are.equal(11, profile.schemaVersion)
        local summary = assert(searchLogMessages("V10 spell color normalization summary:"))
        local tierBreakdown = assert(searchLogMessages("V10 tier breakdown:"))
        local specAnomalies = select(2, searchLogMessages("V10 anomaly: class=12 spec="))
        local allAnomalies = select(2, searchLogMessages("V10 anomaly:"))
        local overflow = assert(searchLogMessages("V10 anomaly: additional specs omitted="))

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

        local tiers = extractAllTierMetrics(tierBreakdown)
        assert.are.same({ scanned = 22, invalid = 22, final = 22 }, tiers.byName)
        assert.are.same({ scanned = 0, invalid = 0, final = 0 }, tiers.bySpellID)
        assert.are.same({ scanned = 0, invalid = 0, final = 0 }, tiers.byCooldownID)
        assert.are.same({ scanned = 0, invalid = 0, final = 0 }, tiers.byTexture)

        assert.are.equal(20, #specAnomalies)
        assert.are.equal(21, #allAnomalies)
        assert.is_not_nil(string.find(overflow, "omitted=2", 1, true))
    end)

    it("initializes invalid tier tables and creates class/spec buckets during backfill", function()
        local entry =
            { value = { r = 0.5, g = 0.5, b = 0.5, a = 1, spellID = 7001, cooldownID = 7002, textureId = 7003 } }
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

        assert.are.equal(11, profile.schemaVersion)
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
        local byCooldownEntry =
            { value = { r = 0.3, g = 0.4, b = 0.5, a = 1, keyType = "customCooldown", cooldownID = 888 } }
        local byTextureEntry =
            { value = { r = 0.4, g = 0.5, b = 0.6, a = 1, keyType = "customTexture", textureId = 777 } }

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

        assert.are.equal(11, profile.schemaVersion)
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
                                    value = {
                                        r = 0.1,
                                        g = 0.2,
                                        b = 0.3,
                                        a = 1,
                                        spellID = "7001",
                                        cooldownID = false,
                                        textureId = "7003",
                                    },
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

        assert.are.equal(11, profile.schemaVersion)
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
            value = { r = 0.4, g = 0.4, b = 0.4, a = 1, spellID = 9001, cooldownID = 9002, textureId = 9003 },
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

        assert.are.equal(11, profile.schemaVersion)
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

        assert.are.equal(11, profile.schemaVersion)
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

    -- V11: offsetX/offsetY → editModePositions migration

    it("V11 migrates offsetX/offsetY to editModePositions for all bar modules", function()
        local profile = {
            schemaVersion = 10,
            powerBar = { offsetX = 5, offsetY = -275 },
            resourceBar = { offsetY = -300 },
            runeBar = { offsetX = 0, offsetY = -325 },
            buffBars = { anchorPoint = "TOP", relativePoint = "BOTTOM", offsetX = 10, offsetY = -350 },
        }

        Migration.Run(profile)

        assert.are.equal(11, profile.schemaVersion)

        -- powerBar: both offsets migrated, cleared
        assert.is_nil(profile.powerBar.offsetX)
        assert.is_nil(profile.powerBar.offsetY)
        local pb = profile.powerBar.editModePositions.Modern
        assert.is_not_nil(pb)
        assert.are.equal("CENTER", pb.point) -- no anchorPoint field → defaults to CENTER
        assert.are.equal(5, pb.x)
        assert.are.equal(-275, pb.y)

        -- resourceBar: only offsetY was set
        assert.is_nil(profile.resourceBar.offsetX)
        assert.is_nil(profile.resourceBar.offsetY)
        local rb = profile.resourceBar.editModePositions.Modern
        assert.is_not_nil(rb)
        assert.are.equal("CENTER", rb.point)
        assert.are.equal(0, rb.x) -- offsetX was nil → 0
        assert.are.equal(-300, rb.y)

        -- runeBar
        local rune = profile.runeBar.editModePositions.Modern
        assert.is_not_nil(rune)
        assert.are.equal(0, rune.x)
        assert.are.equal(-325, rune.y)

        -- buffBars: had anchorPoint, so that is used in the migrated position
        local bb = profile.buffBars.editModePositions.Modern
        assert.is_not_nil(bb)
        assert.are.equal("TOP", bb.point) -- came from cfg.anchorPoint
        assert.are.equal(10, bb.x)
        assert.are.equal(-1430, bb.y)
        -- anchorPoint/relativePoint cleared
        assert.is_nil(profile.buffBars.anchorPoint)
        assert.is_nil(profile.buffBars.relativePoint)
    end)

    it("V11 skips sections with no offsetX or offsetY (chain mode defaults)", function()
        local profile = {
            schemaVersion = 10,
            powerBar = { anchorMode = "chain" },
            resourceBar = { anchorMode = "chain" },
            runeBar = { anchorMode = "chain" },
            buffBars = { anchorMode = "chain" },
        }

        Migration.Run(profile)

        assert.are.equal(11, profile.schemaVersion)
        assert.is_nil(profile.powerBar.editModePositions)
        assert.is_nil(profile.resourceBar.editModePositions)
        assert.is_nil(profile.runeBar.editModePositions)
        assert.is_nil(profile.buffBars.editModePositions)
    end)

    it("V11 clears anchorPoint and relativePoint even when no offsets exist", function()
        local profile = {
            schemaVersion = 10,
            buffBars = { anchorPoint = "CENTER", relativePoint = "CENTER" },
            powerBar = {},
            resourceBar = {},
            runeBar = {},
        }

        Migration.Run(profile)

        assert.is_nil(profile.buffBars.anchorPoint)
        assert.is_nil(profile.buffBars.relativePoint)
    end)

    it("V11 seeds legacy free-mode defaults when offsets were never persisted", function()
        local profile = {
            schemaVersion = 10,
            powerBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            resourceBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            runeBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            buffBars = { anchorMode = ns.Constants.ANCHORMODE_FREE },
        }

        Migration.Run(profile)

        local expected = {
            powerBar = { point = "CENTER", x = 0, y = -275 },
            resourceBar = { point = "CENTER", x = 0, y = -300 },
            runeBar = { point = "CENTER", x = 0, y = -325 },
            buffBars = { point = "CENTER", x = 0, y = -350 },
        }
        for section, pos in pairs(expected) do
            assert.same(pos, profile[section].editModePositions.Modern)
            assert.same(pos, profile[section].editModePositions.Classic)
        end
    end)

    it("V11 preserves absolute free-position coordinates for all modules when seeding legacy defaults", function()
        local profile = {
            schemaVersion = 10,
            powerBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            resourceBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            runeBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            buffBars = { anchorMode = ns.Constants.ANCHORMODE_FREE },
        }

        Migration.Run(profile)

        assertAbsolutePositionPreserved(ns, nil, nil, 0, -275, profile.powerBar.editModePositions.Modern)
        assertAbsolutePositionPreserved(ns, nil, nil, 0, -300, profile.resourceBar.editModePositions.Modern)
        assertAbsolutePositionPreserved(ns, nil, nil, 0, -325, profile.runeBar.editModePositions.Modern)
        assertAbsolutePositionPreserved(ns, nil, nil, 0, -350, profile.buffBars.editModePositions.Modern)
    end)

    it("V11 preserves absolute free-position coordinates for all explicitly positioned free-mode modules", function()
        local profile = {
            schemaVersion = 10,
            powerBar = {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                offsetX = 5,
                offsetY = -275,
            },
            resourceBar = {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                anchorPoint = "TOP",
                relativePoint = "BOTTOM",
                offsetX = 0,
                offsetY = -300,
            },
            runeBar = {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                anchorPoint = "BOTTOMRIGHT",
                relativePoint = "TOPLEFT",
                offsetX = 15,
                offsetY = -25,
            },
            buffBars = {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                anchorPoint = "TOPLEFT",
                relativePoint = "BOTTOMLEFT",
                offsetX = 10,
                offsetY = -350,
            },
        }

        Migration.Run(profile)

        assertAbsolutePositionPreserved(ns, nil, nil, 5, -275, profile.powerBar.editModePositions.Modern)
        assertAbsolutePositionPreserved(ns, "TOP", "BOTTOM", 0, -300, profile.resourceBar.editModePositions.Modern)
        assertAbsolutePositionPreserved(
            ns,
            "BOTTOMRIGHT",
            "TOPLEFT",
            15,
            -25,
            profile.runeBar.editModePositions.Modern
        )
        assertAbsolutePositionPreserved(
            ns,
            "TOPLEFT",
            "BOTTOMLEFT",
            10,
            -350,
            profile.buffBars.editModePositions.Modern
        )
    end)

    it("V11 normalizes differing anchorPoint and relativePoint into exact edit-mode coordinates", function()
        local profile = {
            schemaVersion = 10,
            buffBars = {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                anchorPoint = "TOPLEFT",
                relativePoint = "BOTTOMLEFT",
                offsetX = 10,
                offsetY = -350,
            },
            powerBar = {},
            resourceBar = {},
            runeBar = {},
        }

        Migration.Run(profile)

        local migrated = profile.buffBars.editModePositions.Modern
        assert.are.equal("TOPLEFT", migrated.point)
        assert.are.equal(10, migrated.x)
        assert.are.equal(-1430, migrated.y)
        assertAbsolutePositionPreserved(ns, "TOPLEFT", "BOTTOMLEFT", 10, -350, migrated)
    end)

    it("V11 logs migration source and normalization details", function()
        local profile = {
            schemaVersion = 10,
            powerBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            resourceBar = {},
            runeBar = {},
            buffBars = {
                anchorMode = ns.Constants.ANCHORMODE_FREE,
                anchorPoint = "TOPLEFT",
                relativePoint = "BOTTOMLEFT",
                offsetX = 10,
                offsetY = -350,
            },
        }

        Migration.Run(profile)

        local powerLog = assert(searchLogMessages("powerBar: migrated to editModePositions["))
        assert.is_not_nil(string.find(powerLog, "source=legacy-free-default", 1, true))
        assert.is_not_nil(string.find(powerLog, "normalized=false", 1, true))

        local buffLog = assert(searchLogMessages("buffBars: migrated to editModePositions["))
        assert.is_not_nil(string.find(buffLog, "source=saved-offsets", 1, true))
        assert.is_not_nil(string.find(buffLog, "normalized=true", 1, true))
    end)

    it("V11 preserves existing editModePositions when present", function()
        local profile = {
            schemaVersion = 10,
            powerBar = {
                offsetY = -275,
                editModePositions = { Modern = { point = "TOPLEFT", x = 50, y = 50 } },
            },
            resourceBar = {},
            runeBar = {},
            buffBars = {},
        }

        Migration.Run(profile)

        -- Existing Modern entry is preserved; Classic gets the migrated value
        assert.are.equal(50, profile.powerBar.editModePositions.Modern.x)
        assert.same({ point = "CENTER", x = 0, y = -275 }, profile.powerBar.editModePositions.Classic)
    end)

    it("V11 seeds all layouts from C_EditMode.GetLayouts()", function()
        local profile = {
            schemaVersion = 10,
            powerBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            resourceBar = {},
            runeBar = {},
            buffBars = {},
        }

        Migration.Run(profile)

        assert.are.equal(11, profile.schemaVersion)
        local expected = { point = "CENTER", x = 0, y = -275 }
        assert.same(expected, profile.powerBar.editModePositions.Modern)
        assert.same(expected, profile.powerBar.editModePositions.Classic)
    end)

    it("V11 seeds custom layout names from C_EditMode.GetLayouts()", function()
        _G.C_EditMode = {
            GetLayouts = function()
                return {
                    activeLayout = 3,
                    layouts = { { layoutName = "MyCustomLayout" } },
                }
            end,
        }

        local profile = {
            schemaVersion = 10,
            powerBar = { anchorMode = ns.Constants.ANCHORMODE_FREE },
            resourceBar = {},
            runeBar = {},
            buffBars = {},
        }

        Migration.Run(profile)

        assert.are.equal(11, profile.schemaVersion)
        local expected = { point = "CENTER", x = 0, y = -275 }
        assert.same(expected, profile.powerBar.editModePositions.Modern)
        assert.same(expected, profile.powerBar.editModePositions.Classic)
        assert.same(expected, profile.powerBar.editModePositions.MyCustomLayout)
    end)

    it("V11 advances schema even when the active layout name cannot be resolved", function()
        _G.C_EditMode = nil

        local profile = {
            schemaVersion = 10,
            powerBar = { offsetY = -275 },
            resourceBar = {},
            runeBar = {},
            buffBars = {},
        }

        Migration.Run(profile)

        assert.are.equal(11, profile.schemaVersion)
        assert.is_nil(profile.powerBar.editModePositions)
        assert.are.equal(-275, profile.powerBar.offsetY)
        assert.is_not_nil(searchLogMessages("V11 no layouts available; skipping position migration"))
    end)

    it("ValidateRollback rejects non-integer target versions", function()
        local current = ns.Constants.CURRENT_SCHEMA_VERSION
        _G[ns.Constants.SV_NAME] = {
            _versions = {
                [current - 1] = {},
                [current] = {},
            },
        }

        local ok, message = Migration.ValidateRollback(2.5)
        assert.is_false(ok)
        assert.are.equal("Target version must be a whole number.", message)
    end)

    it("PrepareDatabase reseeds from the prior slot version even when copied profiles drifted forward", function()
        local current = ns.Constants.CURRENT_SCHEMA_VERSION
        local prior = current - 1

        _G[ns.Constants.SV_NAME] = {
            _versions = {
                [prior] = {
                    profiles = {
                        Default = {
                            schemaVersion = current,
                            global = { debug = false },
                        },
                    },
                    profileKeys = {
                        Player = "Default",
                    },
                },
            },
        }

        Migration.PrepareDatabase()

        local active = _G[ns.Constants.ACTIVE_SV_KEY]
        assert.is_not_nil(active)
        assert.are.equal(prior, active.profiles.Default.schemaVersion)
        assert.are.equal(current, _G[ns.Constants.SV_NAME]._versions[prior].profiles.Default.schemaVersion)
    end)

    it("PrepareDatabase preserves non-profile slot data while aligning copied profile schema versions", function()
        local current = ns.Constants.CURRENT_SCHEMA_VERSION
        local prior = current - 1

        _G[ns.Constants.SV_NAME] = {
            _versions = {
                [prior] = {
                    profiles = {
                        Default = {
                            schemaVersion = current,
                        },
                    },
                    _migrationLog = { "old entry" },
                },
            },
        }

        Migration.PrepareDatabase()

        local active = _G[ns.Constants.ACTIVE_SV_KEY]
        assert.are.same({ "old entry" }, active._migrationLog)
        assert.are.equal(prior, active.profiles.Default.schemaVersion)
    end)

    it("ValidateRollback accepts integer targets and reports deleted versions", function()
        local current = ns.Constants.CURRENT_SCHEMA_VERSION
        local floor = current - 2
        _G[ns.Constants.SV_NAME] = {
            _versions = {
                [floor - 1] = {},
                [floor] = {},
                [floor + 1] = {},
                [current] = {},
            },
        }

        local ok, message = Migration.ValidateRollback(floor)
        assert.is_true(ok)

        local deleted = {}
        for v = floor + 1, current do
            deleted[#deleted + 1] = "V" .. v
        end
        assert.are.equal(
            "Will delete " .. table.concat(deleted, ", ") .. " and re-migrate from V" .. floor .. ".",
            message
        )
    end)

    describe("PrintInfo", function()
        local printedMessages

        before_each(function()
            printedMessages = {}
            ns.Print = function(...)
                local args = { ... }
                for i = 1, #args do
                    args[i] = tostring(args[i])
                end
                printedMessages[#printedMessages + 1] = table.concat(args, " ")
            end
        end)

        it("prints current schema version", function()
            _G[ns.Constants.SV_NAME] = { _versions = { [10] = {} } }

            Migration.PrintInfo()

            assert.are.equal("Current schema version: V" .. ns.Constants.CURRENT_SCHEMA_VERSION, printedMessages[1])
        end)

        it("lists available version slots sorted", function()
            _G[ns.Constants.SV_NAME] = {
                _versions = {
                    [7] = {},
                    [10] = {},
                    [8] = {},
                    nonNumeric = {},
                },
            }

            Migration.PrintInfo()

            assert.is_not_nil(string.find(printedMessages[2], "V7, V8, V10", 1, true))
        end)

        it("prints no versioned settings when versions table is nil", function()
            _G[ns.Constants.SV_NAME] = {}

            Migration.PrintInfo()

            assert.are.equal("No versioned settings found.", printedMessages[2])
        end)

        it("prints no versioned settings when versions table has no numeric keys", function()
            _G[ns.Constants.SV_NAME] = { _versions = { foo = {} } }

            Migration.PrintInfo()

            assert.are.equal("No versioned settings found.", printedMessages[2])
        end)

        it("prints subcommand help lines", function()
            _G[ns.Constants.SV_NAME] = { _versions = { [10] = {} } }

            Migration.PrintInfo()

            local hasLogCmd = false
            local hasRollbackCmd = false
            for _, msg in ipairs(printedMessages) do
                if string.find(msg, "/ecm migration log", 1, true) then
                    hasLogCmd = true
                end
                if string.find(msg, "/ecm migration rollback", 1, true) then
                    hasRollbackCmd = true
                end
            end
            assert.is_true(hasLogCmd, "Expected log command in help output")
            assert.is_true(hasRollbackCmd, "Expected rollback command in help output")
        end)

        it("prints no versioned settings when SV_NAME global is nil", function()
            _G[ns.Constants.SV_NAME] = nil

            Migration.PrintInfo()

            assert.are.equal("No versioned settings found.", printedMessages[2])
        end)
    end)

    describe("GetLogText", function()
        it("returns nil when SV_NAME global is nil", function()
            _G[ns.Constants.SV_NAME] = nil
            assert.is_nil(Migration.GetLogText())
        end)

        it("returns nil when versions table is missing", function()
            _G[ns.Constants.SV_NAME] = {}
            assert.is_nil(Migration.GetLogText())
        end)

        it("returns nil when current version slot is missing", function()
            _G[ns.Constants.SV_NAME] = { _versions = {} }
            assert.is_nil(Migration.GetLogText())
        end)

        it("returns nil when migration log is empty", function()
            _G[ns.Constants.SV_NAME] = {
                _versions = { [ns.Constants.CURRENT_SCHEMA_VERSION] = { _migrationLog = {} } },
            }
            assert.is_nil(Migration.GetLogText())
        end)

        it("returns newline-joined log entries", function()
            _G[ns.Constants.SV_NAME] = {
                _versions = {
                    [ns.Constants.CURRENT_SCHEMA_VERSION] = {
                        _migrationLog = {
                            "2024-01-01 00:00:00  migrated V2 to V3",
                            "2024-01-01 00:00:01  migrated V3 to V4",
                        },
                    },
                },
            }
            local result = Migration.GetLogText()
            assert.are.equal(
                "2024-01-01 00:00:00  migrated V2 to V3\n2024-01-01 00:00:01  migrated V3 to V4",
                result
            )
        end)
    end)
end)
