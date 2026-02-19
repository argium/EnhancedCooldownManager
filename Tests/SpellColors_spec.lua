if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("SpellColors", function()
    local originalGlobals

    local SpellColors
    local addonNS
    local buffBarsConfig

    local currentClassID
    local currentSpecID
    local fakeNow
    local secretValues

    local function markSecret(value)
        secretValues[value] = true
        return value
    end

    --- Applies a boolean secret mask to a key tuple.
    --- For each index i, when mask[i] is true the corresponding values[i]
    --- is marked secret via markSecret(); otherwise the original value is kept.
    ---@param values table Ordered key values: { spellName, spellID, cooldownID, textureFileID }
    ---@param mask boolean[] Boolean flags aligned with `values` indexes
    ---@return table maskedValues Copy of `values` with selected entries marked secret
    local function applySecretMask(values, mask)
        local result = {}
        for i = 1, #values do
            if mask[i] then
                result[i] = markSecret(values[i])
            else
                result[i] = values[i]
            end
        end
        return result
    end

    local function bitIsSet(value, bitIndex)
        local divisor = 2 ^ bitIndex
        return math.floor(value / divisor) % 2 == 1
    end

    local function color(r, g, b, a)
        return { r = r, g = g, b = b, a = a or 1 }
    end

    local function makeFrame(opts)
        opts = opts or {}
        return {
            __ecmHooked = opts.hooked ~= false,
            Bar = {
                Name = {
                    GetText = function()
                        return opts.spellName
                    end,
                },
            },
            cooldownInfo = opts.spellID and { spellID = opts.spellID } or nil,
            cooldownID = opts.cooldownID,
            __textureFileID = opts.textureFileID,
        }
    end

    local function setClassSpec(classID, specID)
        currentClassID = classID
        currentSpecID = specID
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "UnitClass",
            "GetSpecialization",
            "issecretvalue",
            "issecrettable",
            "canaccessvalue",
            "canaccesstable",
            "time",
            "ECM_debug_assert",
            "ECM_log",
            "ECM_tostring",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeNow = 1000
        secretValues = {}
        currentClassID = 12
        currentSpecID = 2

        _G.ECM = {
            FrameUtil = {
                GetIconTextureFileID = function(frame)
                    return frame and frame.__textureFileID or nil
                end,
            },
        }

        _G.UnitClass = function()
            return "Demon Hunter", "DEMONHUNTER", currentClassID
        end

        _G.GetSpecialization = function()
            return currentSpecID
        end

        _G.issecretvalue = function(value)
            return secretValues[value] == true
        end
        _G.issecrettable = function()
            return false
        end
        _G.canaccessvalue = function(value)
            return not _G.issecretvalue(value)
        end
        _G.canaccesstable = function(value)
            return not _G.issecretvalue(value)
        end

        _G.time = function()
            fakeNow = fakeNow + 1
            return fakeNow
        end

        _G.ECM_debug_assert = function() end
        _G.ECM_log = function() end
        _G.ECM_tostring = function(value)
            return tostring(value)
        end

        local constantsChunk = TestHelpers.loadChunk(
            {
                "Constants.lua",
                "../Constants.lua",
            },
            "Unable to load Constants.lua"
        )
        constantsChunk()

        local priorityMapChunk = TestHelpers.loadChunk(
            {
                "Modules/PriorityKeyMap.lua",
                "../Modules/PriorityKeyMap.lua",
            },
            "Unable to load Modules/PriorityKeyMap.lua"
        )
        priorityMapChunk()

        buffBarsConfig = {}
        addonNS = {
            Addon = {
                db = {
                    profile = {
                        buffBars = buffBarsConfig,
                    },
                },
            },
        }

        local spellColorsChunk = TestHelpers.loadChunk(
            {
                "Modules/SpellColors.lua",
                "../Modules/SpellColors.lua",
            },
            "Unable to load Modules/SpellColors.lua"
        )
        spellColorsChunk(nil, addonNS)

        SpellColors = assert(ECM.SpellColors, "SpellColors module did not initialize")
    end)

    it("MakeKey returns nil when no valid key is available", function()
        assert.is_nil(SpellColors.MakeKey(nil, nil, nil, nil))
        assert.is_nil(SpellColors.MakeKey({}, {}, {}, {}))
    end)

    it("MakeKey chooses primary key by configured priority", function()
        local byName = SpellColors.MakeKey("Chaos Nova", 111, 222, 333)
        assert.are.equal("spellName", byName.keyType)
        assert.are.equal("Chaos Nova", byName.primaryKey)

        local bySpellID = SpellColors.MakeKey(nil, 111, 222, 333)
        assert.are.equal("spellID", bySpellID.keyType)
        assert.are.equal(111, bySpellID.primaryKey)

        local byCooldownID = SpellColors.MakeKey(nil, nil, 222, 333)
        assert.are.equal("cooldownID", byCooldownID.keyType)
        assert.are.equal(222, byCooldownID.primaryKey)

        local byTexture = SpellColors.MakeKey(nil, nil, nil, 333)
        assert.are.equal("textureFileID", byTexture.keyType)
        assert.are.equal(333, byTexture.primaryKey)
    end)

    it("MakeKey drops secret identifiers and falls back to non-secret keys", function()
        local secretName = markSecret("Hidden Spell")
        local key = SpellColors.MakeKey(secretName, 10, 20, 30)
        assert.are.equal("spellID", key.keyType)
        assert.are.equal(10, key.primaryKey)
        assert.is_nil(key.spellName)

        local secretSpellID = markSecret(10)
        local key2 = SpellColors.MakeKey(secretName, secretSpellID, 20, 30)
        assert.are.equal("cooldownID", key2.keyType)
        assert.are.equal(20, key2.primaryKey)

        local secretCooldownID = markSecret(20)
        local secretTexture = markSecret(30)
        assert.is_nil(SpellColors.MakeKey(secretName, secretSpellID, secretCooldownID, secretTexture))
    end)

    it("MakeKey handles every secret-key permutation", function()
        local base = { "Permutation Spell", 1101, 2202, 3303 }
        local expectedTypeOrder = { "spellName", "spellID", "cooldownID", "textureFileID" }

        for bits = 0, 15 do
            secretValues = {}
            local mask = {
                bitIsSet(bits, 0),
                bitIsSet(bits, 1),
                bitIsSet(bits, 2),
                bitIsSet(bits, 3),
            }
            local keys = applySecretMask(base, mask)
            local k = SpellColors.MakeKey(keys[1], keys[2], keys[3], keys[4])

            local expectedIndex = nil
            for i = 1, 4 do
                if not mask[i] then
                    expectedIndex = i
                    break
                end
            end

            if expectedIndex == nil then
                assert.is_nil(k)
            else
                assert.is_not_nil(k)
                assert.are.equal(expectedTypeOrder[expectedIndex], k.keyType)
                assert.are.equal(base[expectedIndex], k.primaryKey)
            end
        end
    end)

    it("SetColorByKey stores metadata and supports lookup from each key tier", function()
        local c = color(0.1, 0.2, 0.3)
        local key = SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001)

        SpellColors.SetColorByKey(key, c)

        assert.are.equal("spellName", c.keyType)
        assert.are.equal(258920, c.spellID)
        assert.are.equal(77, c.cooldownID)
        assert.are.equal(9001, c.textureId)

        assert.are.same(c, SpellColors.GetColorByKey({ spellName = "Immolation Aura" }))
        assert.are.same(c, SpellColors.GetColorByKey({ spellID = 258920 }))
        assert.are.same(c, SpellColors.GetColorByKey({ cooldownID = 77 }))
        assert.are.same(c, SpellColors.GetColorByKey({ textureFileID = 9001 }))
    end)

    it("SetColorByKey accepts normalized keyType and primaryKey payloads", function()
        local c = color(0.4, 0.5, 0.6)

        SpellColors.SetColorByKey({ keyType = "spellID", primaryKey = 321 }, c)

        assert.are.same(c, SpellColors.GetColorByKey({ spellID = 321 }))
        assert.are.equal("spellID", c.keyType)
        assert.are.equal(321, c.spellID)
    end)

    it("GetColorByKey accepts legacy textureId field", function()
        local c = color(0.3, 0.6, 0.9)
        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, nil, nil, 444), c)

        assert.are.same(c, SpellColors.GetColorByKey({ textureId = 444 }))
    end)

    it("SetColorByKey is a no-op for invalid keys", function()
        local c = color(0.2, 0.7, 0.4)
        SpellColors.SetColorByKey(SpellColors.MakeKey("Stored", nil, nil, nil), c)

        SpellColors.SetColorByKey(nil, color(1, 1, 1))
        SpellColors.SetColorByKey({}, color(1, 1, 1))

        assert.are.same(c, SpellColors.GetColorByKey({ spellName = "Stored" }))
    end)

    it("ResetColorByKey clears all populated tiers and returns clear flags", function()
        local c = color(0.7, 0.1, 0.2)
        local key = SpellColors.MakeKey("Sigil of Flame", 204596, 44, 8888)
        SpellColors.SetColorByKey(key, c)

        local nameCleared, spellIDCleared, cooldownIDCleared, textureCleared = SpellColors.ResetColorByKey(key)
        assert.is_true(nameCleared)
        assert.is_true(spellIDCleared)
        assert.is_true(cooldownIDCleared)
        assert.is_true(textureCleared)

        assert.is_nil(SpellColors.GetColorByKey({ spellName = "Sigil of Flame" }))
        assert.is_nil(SpellColors.GetColorByKey({ spellID = 204596 }))
        assert.is_nil(SpellColors.GetColorByKey({ cooldownID = 44 }))
        assert.is_nil(SpellColors.GetColorByKey({ textureFileID = 8888 }))
    end)

    it("ResetColorByKey returns all false for unknown or invalid keys", function()
        local a, b, c, d = SpellColors.ResetColorByKey({ spellName = "never-set" })
        assert.is_false(a)
        assert.is_false(b)
        assert.is_false(c)
        assert.is_false(d)

        local w, x, y, z = SpellColors.ResetColorByKey(nil)
        assert.is_false(w)
        assert.is_false(x)
        assert.is_false(y)
        assert.is_false(z)
    end)

    it("GetDefaultColor initializes missing profile color storage", function()
        local defaultColor = SpellColors.GetDefaultColor()
        assert.are.same(ECM.Constants.BUFFBARS_DEFAULT_COLOR, defaultColor)

        assert.is_table(buffBarsConfig.colors)
        assert.is_table(buffBarsConfig.colors.byName)
        assert.is_table(buffBarsConfig.colors.bySpellID)
        assert.is_table(buffBarsConfig.colors.byCooldownID)
        assert.is_table(buffBarsConfig.colors.byTexture)
        assert.is_table(buffBarsConfig.colors.cache)
    end)

    it("GetDefaultColor repairs invalid color storage types", function()
        buffBarsConfig.colors = {
            byName = "bad",
            bySpellID = false,
            byCooldownID = 7,
            byTexture = "bad",
            cache = "bad",
            defaultColor = "bad",
        }

        local defaultColor = SpellColors.GetDefaultColor()

        assert.are.same(ECM.Constants.BUFFBARS_DEFAULT_COLOR, defaultColor)
        assert.is_table(buffBarsConfig.colors.byName)
        assert.is_table(buffBarsConfig.colors.bySpellID)
        assert.is_table(buffBarsConfig.colors.byCooldownID)
        assert.is_table(buffBarsConfig.colors.byTexture)
        assert.is_table(buffBarsConfig.colors.cache)
    end)

    it("SetDefaultColor stores rgb and normalizes alpha to 1", function()
        SpellColors.SetDefaultColor({ r = 0.2, g = 0.4, b = 0.6, a = 0.05 })

        local got = SpellColors.GetDefaultColor()
        assert.are.same({ r = 0.2, g = 0.4, b = 0.6, a = 1 }, got)
    end)

    it("GetColorForBar returns nil for invalid or unhooked frames", function()
        assert.is_nil(SpellColors.GetColorForBar(nil))
        assert.is_nil(SpellColors.GetColorForBar({}))
        assert.is_nil(SpellColors.GetColorForBar(makeFrame({ hooked = false, spellName = "x", textureFileID = 1 })))
    end)

    it("GetColorForBar resolves color from frame identifiers", function()
        local c = color(0.8, 0.2, 0.4)
        SpellColors.SetColorByKey(SpellColors.MakeKey("Throw Glaive", 185123, 66, 1234), c)

        local frame = makeFrame({ spellName = "Throw Glaive", spellID = 185123, cooldownID = 66, textureFileID = 1234 })
        assert.are.same(c, SpellColors.GetColorForBar(frame))
    end)

    it("GetColorForBar falls back to spellID when other keys are secret", function()
        local c = color(0.6, 0.2, 0.9)
        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, 777, nil, nil), c)

        local frame = makeFrame({
            spellName = markSecret("Secret Name"),
            spellID = 777,
            textureFileID = markSecret(9999),
        })

        assert.are.same(c, SpellColors.GetColorForBar(frame))
    end)

    it("GetColorForBar handles every secret-key permutation", function()
        local c = color(0.33, 0.44, 0.55)
        local base = { "Permutation Bar Spell", 9090, 8080, 7070 }
        SpellColors.SetColorByKey(SpellColors.MakeKey(base[1], base[2], base[3], base[4]), c)

        for bits = 0, 15 do
            secretValues = {}
            local mask = {
                bitIsSet(bits, 0),
                bitIsSet(bits, 1),
                bitIsSet(bits, 2),
                bitIsSet(bits, 3),
            }
            local keys = applySecretMask(base, mask)
            local frame = makeFrame({
                spellName = keys[1],
                spellID = keys[2],
                cooldownID = keys[3],
                textureFileID = keys[4],
            })

            local got = SpellColors.GetColorForBar(frame)
            if mask[1] and mask[2] and mask[3] and mask[4] then
                assert.is_nil(got)
            else
                assert.are.same(c, got)
            end
        end
    end)

    it("ReconcileBar unifies conflicting entries to the most recent write", function()
        local older = color(0.1, 0.1, 0.1)
        local newer = color(0.9, 0.9, 0.2)

        SpellColors.SetColorByKey(SpellColors.MakeKey("Fel Rush", nil, nil, 5678), older)
        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, nil, nil, 5678), newer)

        SpellColors.ReconcileBar(makeFrame({ spellName = "Fel Rush", textureFileID = 5678 }))

        assert.are.same(newer, SpellColors.GetColorByKey({ spellName = "Fel Rush" }))
    end)

    it("ReconcileAllBars reports changed count and skips invalid frames", function()
        local older = color(0.1, 0.2, 0.3)
        local newer = color(0.7, 0.8, 0.9)

        SpellColors.SetColorByKey(SpellColors.MakeKey("Blur", nil, nil, 6789), older)
        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, nil, nil, 6789), newer)

        local changed = SpellColors.ReconcileAllBars({
            {},
            makeFrame({ hooked = false, spellName = "Blur", textureFileID = 6789 }),
            makeFrame({ spellName = "Blur", textureFileID = 6789 }),
        })

        assert.are.equal(1, changed)
        assert.are.same(newer, SpellColors.GetColorByKey({ spellName = "Blur" }))
    end)

    it("GetAllColorEntries returns deduplicated entries for shared references", function()
        local c = color(0.2, 0.3, 0.4)
        SpellColors.SetColorByKey(SpellColors.MakeKey("Eye Beam", 198013, 55, 1111), c)

        local entries = SpellColors.GetAllColorEntries()
        assert.are.equal(1, #entries)

        local entry = entries[1]
        assert.are.same(c, entry.color)
        assert.are.equal("spellName", entry.key.keyType)
        assert.are.equal("Eye Beam", entry.key.primaryKey)
    end)

    it("GetAllColorEntries derives keys from raw persisted key when metadata is absent", function()
        SpellColors.GetDefaultColor()

        buffBarsConfig.colors.bySpellID[currentClassID] = buffBarsConfig.colors.bySpellID[currentClassID] or {}
        buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID] = buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID] or {}

        local persistedValue = color(0.5, 0.4, 0.3)
        buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID][2468] = { value = persistedValue }

        local entries = SpellColors.GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("spellID", entries[1].key.keyType)
        assert.are.equal(2468, entries[1].key.primaryKey)
        assert.are.same(persistedValue, entries[1].color)
    end)

    it("repairs fallback tiers from byName persisted entries with embedded IDs", function()
        SpellColors.GetDefaultColor()

        local classTables = {
            byName = buffBarsConfig.colors.byName,
            bySpellID = buffBarsConfig.colors.bySpellID,
            byCooldownID = buffBarsConfig.colors.byCooldownID,
            byTexture = buffBarsConfig.colors.byTexture,
        }

        for _, tbl in pairs(classTables) do
            tbl[currentClassID] = tbl[currentClassID] or {}
            tbl[currentClassID][currentSpecID] = tbl[currentClassID][currentSpecID] or {}
        end

        local persistedColor = color(0.9, 0.1, 0.7)
        persistedColor.spellID = 1357
        persistedColor.cooldownID = 2468
        persistedColor.textureId = 3699

        local stamped = { value = persistedColor }
        buffBarsConfig.colors.byName[currentClassID][currentSpecID]["Persisted Spell"] = stamped

        assert.is_nil(buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID][1357])
        assert.is_nil(buffBarsConfig.colors.byCooldownID[currentClassID][currentSpecID][2468])
        assert.is_nil(buffBarsConfig.colors.byTexture[currentClassID][currentSpecID][3699])

        local got = SpellColors.GetColorByKey({ spellID = 1357 })
        assert.are.same(persistedColor, got)

        assert.are.same(stamped, buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID][1357])
        assert.are.same(stamped, buffBarsConfig.colors.byCooldownID[currentClassID][currentSpecID][2468])
        assert.are.same(stamped, buffBarsConfig.colors.byTexture[currentClassID][currentSpecID][3699])
    end)

    it("isolates stored colors by class and specialization", function()
        setClassSpec(12, 1)
        local c = color(0.3, 0.8, 0.1)
        SpellColors.SetColorByKey(SpellColors.MakeKey("Shared Name", nil, nil, nil), c)

        setClassSpec(12, 2)
        assert.is_nil(SpellColors.GetColorByKey({ spellName = "Shared Name" }))

        setClassSpec(11, 1)
        assert.is_nil(SpellColors.GetColorByKey({ spellName = "Shared Name" }))

        setClassSpec(12, 1)
        assert.are.same(c, SpellColors.GetColorByKey({ spellName = "Shared Name" }))
    end)

    it("returns empty entries when class or spec cannot be determined", function()
        local c = color(0.4, 0.4, 0.4)
        SpellColors.SetColorByKey(SpellColors.MakeKey("Stored", nil, nil, nil), c)

        _G.GetSpecialization = function()
            return nil
        end
        assert.are.same({}, SpellColors.GetAllColorEntries())

        _G.GetSpecialization = function()
            return currentSpecID
        end
        _G.UnitClass = function()
            return "Demon Hunter", "DEMONHUNTER", nil
        end
        assert.are.same({}, SpellColors.GetAllColorEntries())
    end)
end)
