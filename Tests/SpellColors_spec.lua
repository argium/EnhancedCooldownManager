-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("SpellColors", function()
    local originalGlobals

    local SpellColors
    local BuffSpellColors
    local ExternalSpellColors
    local buffBarsConfig
    local externalBarsConfig

    local currentClassID
    local currentSpecID
    local fakeNow
    local secretValues
    local ns

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

    local color = TestHelpers.color

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

    --- Iterates every 4-bit secret-mask permutation (0…15), resetting
    --- secretValues each iteration and passing the boolean mask to `fn`.
    local function forEachSecretPermutation(fn)
        for bits = 0, 15 do
            secretValues = {}
            local mask = {
                bitIsSet(bits, 0), bitIsSet(bits, 1),
                bitIsSet(bits, 2), bitIsSet(bits, 3),
            }
            fn(mask)
        end
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "UnitClass",
            "GetSpecialization",
            "issecretvalue",
            "issecrettable",
            "canaccessvalue",
            "canaccesstable",
            "time",
            "wipe",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeNow = 1000
        secretValues = {}
        currentClassID = 12
        currentSpecID = 2

        ns = {
            IsDebugEnabled = function() return false end,
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

        ns.DebugAssert = function() end
        ns.Log = function() end
        ns.ToString = function(value)
            return tostring(value)
        end

        _G.wipe = function(t)
            for k in pairs(t) do t[k] = nil end
        end

        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        buffBarsConfig = {}
        externalBarsConfig = {
            colors = {
                byName = {},
                bySpellID = {},
                byCooldownID = {},
                byTexture = {},
                cache = {},
                defaultColor = { r = 0.40, g = 0.78, b = 0.95, a = 1 },
            },
        }
        ns.Addon = {
            db = {
                profile = {
                    buffBars = buffBarsConfig,
                    externalBars = externalBarsConfig,
                },
            },
        }

        TestHelpers.LoadChunk("SpellColors.lua", "Unable to load SpellColors.lua")(nil, ns)

        SpellColors = assert(ns.SpellColors, "SpellColors module did not initialize")
        BuffSpellColors = SpellColors.Get(ns.Constants.SCOPE_BUFFBARS)
        ExternalSpellColors = SpellColors.Get(ns.Constants.SCOPE_EXTERNALBARS)
    end)

    it("New creates isolated stores and _SetConfigAccessor is reserved for test use", function()
        local firstExternalConfig = {}
        local secondExternalConfig = {}
        local store = SpellColors.New(ns.Constants.SCOPE_EXTERNALBARS, function()
            return { externalBars = firstExternalConfig }
        end)
        local key = SpellColors.MakeKey("Private Test Store", 9876, nil, nil)
        local storedColor = color(0.25, 0.5, 0.75)

        store:SetColorByKey(key, storedColor)
        assert.are.same(storedColor, store:GetColorByKey({ spellName = "Private Test Store" }))

        store:_SetConfigAccessor(function()
            return { externalBars = secondExternalConfig }
        end)

        assert.is_nil(store:GetColorByKey({ spellName = "Private Test Store" }))
        assert.are.same({}, store:GetAllColorEntries())
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

        forEachSecretPermutation(function(mask)
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
        end)
    end)

    it("NormalizeKey returns opaque key objects with methods", function()
        local key = SpellColors.NormalizeKey({ keyType = "spellID", primaryKey = 777, textureId = 9090 })

        assert.is_table(key)
        assert.are.equal("spellID", key.keyType)
        assert.are.equal(777, key.primaryKey)
        assert.are.equal(777, key.spellID)
        assert.are.equal(9090, key.textureFileID)
        assert.is_function(key.Matches)
        assert.is_function(key.Merge)
    end)

    it("KeysMatch compares key identity by all identifiers", function()
        local byName = SpellColors.MakeKey("Blade Dance", 188499, nil, 1234)

        assert.is_true(SpellColors.KeysMatch(byName, { spellName = "Blade Dance" }))
        assert.is_true(byName:Matches({ spellID = 188499 }))
        assert.is_true(SpellColors.KeysMatch(byName, { textureFileID = 1234 }))
        assert.is_false(SpellColors.KeysMatch(byName, { spellName = "Other", spellID = 999999 }))

        local textureOnlyA = SpellColors.MakeKey(nil, nil, nil, 4321)
        local textureOnlyB = SpellColors.MakeKey(nil, nil, nil, 4321)
        assert.is_true(textureOnlyA:Matches(textureOnlyB))
    end)

    it("MergeKeys and key:Merge combine discovered identifiers", function()
        local base = SpellColors.MakeKey("Immolation Aura", nil, nil, nil)
        local merged = SpellColors.MergeKeys(base, { spellName = "Immolation Aura", spellID = 258920, cooldownID = 77, textureFileID = 9001 })

        assert.is_not_nil(merged)
        assert.are.equal("spellName", merged.keyType)
        assert.are.equal("Immolation Aura", merged.primaryKey)
        assert.are.equal(258920, merged.spellID)
        assert.are.equal(77, merged.cooldownID)
        assert.are.equal(9001, merged.textureFileID)

        local mergedViaMethod = base:Merge({ spellName = "Immolation Aura", spellID = 258920 })
        assert.is_not_nil(mergedViaMethod)
        assert.are.equal(258920, mergedViaMethod.spellID)
    end)

    it("MergeKeys returns nil for non-matching keys", function()
        local left = SpellColors.MakeKey("Sigil of Flame", 204596, nil, nil)
        local right = SpellColors.MakeKey("Throw Glaive", 185123, nil, nil)
        assert.is_nil(SpellColors.MergeKeys(left, right))
        assert.is_nil(left:Merge(right))
    end)

    it("MergeKeys promotes primary key to strongest discovered identifier", function()
        local byCooldown = SpellColors.MakeKey(nil, nil, 77, nil)
        local withName = { spellName = "Immolation Aura", cooldownID = 77 }

        local merged = SpellColors.MergeKeys(byCooldown, withName)
        assert.is_not_nil(merged)
        assert.are.equal("spellName", merged.keyType)
        assert.are.equal("Immolation Aura", merged.primaryKey)

        local mergedViaMethod = byCooldown:Merge(withName)
        assert.is_not_nil(mergedViaMethod)
        assert.are.equal("spellName", mergedViaMethod.keyType)
        assert.are.equal("Immolation Aura", mergedViaMethod.primaryKey)
    end)

    it("SetColorByKey does not mutate color payload and supports lookup from each key tier", function()
        local c = color(0.1, 0.2, 0.3)
        local key = SpellColors.MakeKey("Immolation Aura", 258920, 77, 9001)

        BuffSpellColors:SetColorByKey(key, c)

        assert.are.same({ r = 0.1, g = 0.2, b = 0.3, a = 1 }, c)

        assert.are.same(c, BuffSpellColors:GetColorByKey({ spellName = "Immolation Aura" }))
        assert.are.same(c, BuffSpellColors:GetColorByKey({ spellID = 258920 }))
        assert.are.same(c, BuffSpellColors:GetColorByKey({ cooldownID = 77 }))
        assert.are.same(c, BuffSpellColors:GetColorByKey({ textureFileID = 9001 }))
    end)

    it("SetColorByKey accepts normalized keyType and primaryKey payloads", function()
        local c = color(0.4, 0.5, 0.6)

        BuffSpellColors:SetColorByKey({ keyType = "spellID", primaryKey = 321 }, c)

        assert.are.same(c, BuffSpellColors:GetColorByKey({ spellID = 321 }))
        assert.are.same({ r = 0.4, g = 0.5, b = 0.6, a = 1 }, c)
    end)

    it("GetColorByKey accepts legacy textureId field", function()
        local c = color(0.3, 0.6, 0.9)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(nil, nil, nil, 444), c)

        assert.are.same(c, BuffSpellColors:GetColorByKey({ textureId = 444 }))
    end)

    it("SetColorByKey is a no-op for invalid keys", function()
        local c = color(0.2, 0.7, 0.4)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Stored", nil, nil, nil), c)

        BuffSpellColors:SetColorByKey(nil, color(1, 1, 1))
        BuffSpellColors:SetColorByKey({}, color(1, 1, 1))

        assert.are.same(c, BuffSpellColors:GetColorByKey({ spellName = "Stored" }))
    end)

    it("ResetColorByKey clears all populated tiers and returns clear flags", function()
        local c = color(0.7, 0.1, 0.2)
        local key = SpellColors.MakeKey("Sigil of Flame", 204596, 44, 8888)
        BuffSpellColors:SetColorByKey(key, c)

        assert.are.same({ true, true, true, true }, { BuffSpellColors:ResetColorByKey(key) })

        assert.is_nil(BuffSpellColors:GetColorByKey({ spellName = "Sigil of Flame" }))
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellID = 204596 }))
        assert.is_nil(BuffSpellColors:GetColorByKey({ cooldownID = 44 }))
        assert.is_nil(BuffSpellColors:GetColorByKey({ textureFileID = 8888 }))
    end)

    it("ResetColorByKey returns all false for unknown or invalid keys", function()
        assert.are.same({ false, false, false, false }, { BuffSpellColors:ResetColorByKey({ spellName = "never-set" }) })
        assert.are.same({ false, false, false, false }, { BuffSpellColors:ResetColorByKey(nil) })
    end)

    it("GetDefaultColor initializes missing profile color storage", function()
        local defaultColor = BuffSpellColors:GetDefaultColor()
        assert.are.same(ns.Constants.BUFFBARS_DEFAULT_COLOR, defaultColor)

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

        local defaultColor = BuffSpellColors:GetDefaultColor()

        assert.are.same(ns.Constants.BUFFBARS_DEFAULT_COLOR, defaultColor)
        assert.is_table(buffBarsConfig.colors.byName)
        assert.is_table(buffBarsConfig.colors.bySpellID)
        assert.is_table(buffBarsConfig.colors.byCooldownID)
        assert.is_table(buffBarsConfig.colors.byTexture)
        assert.is_table(buffBarsConfig.colors.cache)
    end)

    it("SetDefaultColor stores rgb and normalizes alpha to 1", function()
        BuffSpellColors:SetDefaultColor({ r = 0.2, g = 0.4, b = 0.6, a = 0.05 })

        local got = BuffSpellColors:GetDefaultColor()
        assert.are.same({ r = 0.2, g = 0.4, b = 0.6, a = 1 }, got)
    end)

    it("stores and reads colors independently by scope", function()
        local buffColor = color(0.2, 0.3, 0.4)
        local externalColor = color(0.7, 0.6, 0.5)
        local key = SpellColors.MakeKey("Scoped Spell", 111, 222, 333)

        BuffSpellColors:SetColorByKey(key, buffColor)
        ExternalSpellColors:SetColorByKey(key, externalColor)

        assert.are.same(buffColor, BuffSpellColors:GetColorByKey({ spellName = "Scoped Spell" }))
        assert.are.same(externalColor, ExternalSpellColors:GetColorByKey({ spellName = "Scoped Spell" }))
    end)

    it("GetColorForBar respects the requested scope", function()
        local buffColor = color(0.1, 0.2, 0.3)
        local externalColor = color(0.8, 0.7, 0.6)
        local frame = makeFrame({
            spellName = "Scoped Bar",
            spellID = 444,
            cooldownID = 555,
            textureFileID = 666,
        })

        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Scoped Bar", 444, 555, 666), buffColor)
        ExternalSpellColors:SetColorByKey(SpellColors.MakeKey("Scoped Bar", 444, 555, 666), externalColor)

        assert.are.same(buffColor, BuffSpellColors:GetColorForBar(frame))
        assert.are.same(externalColor, ExternalSpellColors:GetColorForBar(frame))
    end)

    it("GetDefaultColor and SetDefaultColor are scoped", function()
        assert.are.same({ r = 0.40, g = 0.78, b = 0.95, a = 1 }, ExternalSpellColors:GetDefaultColor())

        ExternalSpellColors:SetDefaultColor({ r = 0.9, g = 0.8, b = 0.7, a = 0.1 })

        assert.are.same({ r = 0.9, g = 0.8, b = 0.7, a = 1 }, ExternalSpellColors:GetDefaultColor())
        assert.are.same(ns.Constants.BUFFBARS_DEFAULT_COLOR, BuffSpellColors:GetDefaultColor())
    end)

    it("GetColorForBar returns nil for invalid or unhooked frames", function()
        assert.is_nil(BuffSpellColors:GetColorForBar(nil))
        assert.is_nil(BuffSpellColors:GetColorForBar({}))
        assert.is_nil(BuffSpellColors:GetColorForBar(makeFrame({ hooked = false, spellName = "x", textureFileID = 1 })))
    end)

    it("GetColorForBar resolves color from frame identifiers", function()
        local c = color(0.8, 0.2, 0.4)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Throw Glaive", 185123, 66, 1234), c)

        local frame = makeFrame({ spellName = "Throw Glaive", spellID = 185123, cooldownID = 66, textureFileID = 1234 })
        assert.are.same(c, BuffSpellColors:GetColorForBar(frame))
    end)

    it("GetColorForBar falls back to spellID when other keys are secret", function()
        local c = color(0.6, 0.2, 0.9)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(nil, 777, nil, nil), c)

        local frame = makeFrame({
            spellName = markSecret("Secret Name"),
            spellID = 777,
            textureFileID = markSecret(9999),
        })

        assert.are.same(c, BuffSpellColors:GetColorForBar(frame))
    end)

    it("GetColorForBar handles every secret-key permutation", function()
        local c = color(0.33, 0.44, 0.55)
        local base = { "Permutation Bar Spell", 9090, 8080, 7070 }
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(base[1], base[2], base[3], base[4]), c)

        forEachSecretPermutation(function(mask)
            local keys = applySecretMask(base, mask)
            local frame = makeFrame({
                spellName = keys[1],
                spellID = keys[2],
                cooldownID = keys[3],
                textureFileID = keys[4],
            })

            local got = BuffSpellColors:GetColorForBar(frame)
            if mask[1] and mask[2] and mask[3] and mask[4] then
                assert.is_nil(got)
            else
                assert.are.same(c, got)
            end
        end)
    end)

    it("ReconcileAllKeys unifies conflicting entries to the most recent write", function()
        local older = color(0.1, 0.1, 0.1)
        local newer = color(0.9, 0.9, 0.2)

        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Fel Rush", nil, nil, 5678), older)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(nil, nil, nil, 5678), newer)

        BuffSpellColors:ReconcileAllKeys({ SpellColors.MakeKey("Fel Rush", nil, nil, 5678) })

        assert.are.same(newer, BuffSpellColors:GetColorByKey({ spellName = "Fel Rush" }))
    end)

    it("ReconcileAllKeys operates only within the requested scope", function()
        local buffColor = color(0.2, 0.2, 0.2)
        local externalColor = color(0.8, 0.8, 0.1)

        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Scoped Reconcile", nil, nil, 5678), buffColor)
        ExternalSpellColors:SetColorByKey(SpellColors.MakeKey(nil, nil, nil, 5678), externalColor)

        ExternalSpellColors:ReconcileAllKeys({ SpellColors.MakeKey("Scoped Reconcile", nil, nil, 5678) })

        assert.are.same(buffColor, BuffSpellColors:GetColorByKey({ spellName = "Scoped Reconcile" }))
        assert.are.same(externalColor, ExternalSpellColors:GetColorByKey({ spellName = "Scoped Reconcile" }))
    end)

    it("RemoveEntriesByKeys clears matching persisted and discovered entries", function()
        BuffSpellColors:ClearDiscoveredKeys()

        local staleColor = color(0.4, 0.5, 0.6)
        local keepColor = color(0.8, 0.2, 0.1)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), staleColor)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Keep Me", 12345, 67890, 13579), keepColor)

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Immolation Aura",
            spellID = 258920,
            cooldownID = 77,
            textureFileID = 9001,
        }))
        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Keep Me",
            spellID = 12345,
            cooldownID = 67890,
            textureFileID = 13579,
        }))

        local removed = BuffSpellColors:RemoveEntriesByKeys({
            SpellColors.MakeKey("Immolation Aura", 258920, nil, nil),
        })

        assert.are.equal(1, #removed)
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellName = "Immolation Aura" }))
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellID = 258920 }))

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Keep Me", entries[1].key.spellName)
        assert.are.same(keepColor, entries[1].color)
    end)

    it("RemoveEntriesByKeys only removes entries from the requested scope", function()
        local buffColor = color(0.1, 0.5, 0.9)
        local externalColor = color(0.9, 0.5, 0.1)
        local key = SpellColors.MakeKey("Scoped Remove", 2468, nil, nil)

        BuffSpellColors:SetColorByKey(key, buffColor)
        ExternalSpellColors:SetColorByKey(key, externalColor)

        local removed = ExternalSpellColors:RemoveEntriesByKeys({ key })

        assert.are.equal(1, #removed)
        assert.are.same(buffColor, BuffSpellColors:GetColorByKey({ spellName = "Scoped Remove" }))
        assert.is_nil(ExternalSpellColors:GetColorByKey({ spellName = "Scoped Remove" }))
    end)

    it("RemoveEntriesByKeys only removes discovered entries from the requested scope", function()
        BuffSpellColors:ClearDiscoveredKeys()
        ExternalSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Scoped Discovered Remove",
            spellID = 2468,
        }))
        ExternalSpellColors:DiscoverBar(makeFrame({
            spellName = "Scoped Discovered Remove",
            spellID = 2468,
        }))

        local removed = ExternalSpellColors:RemoveEntriesByKeys({
            SpellColors.MakeKey("Scoped Discovered Remove", 2468, nil, nil),
        })

        assert.are.equal(1, #removed)
        assert.are.equal(1, #BuffSpellColors:GetAllColorEntries())
        assert.are.equal("Scoped Discovered Remove", BuffSpellColors:GetAllColorEntries()[1].key.spellName)
        assert.are.equal(0, #ExternalSpellColors:GetAllColorEntries())
    end)

    it("GetAllColorEntries returns deduplicated entries for shared references", function()
        local c = color(0.2, 0.3, 0.4)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Eye Beam", 198013, 55, 1111), c)

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)

        local entry = entries[1]
        assert.are.same(c, entry.color)
        assert.are.equal("spellName", entry.key.keyType)
        assert.are.equal("Eye Beam", entry.key.primaryKey)
    end)

    it("GetAllColorEntries derives keys from raw persisted key when metadata is absent", function()
        BuffSpellColors:GetDefaultColor()

        buffBarsConfig.colors.bySpellID[currentClassID] = buffBarsConfig.colors.bySpellID[currentClassID] or {}
        buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID] = buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID] or {}

        local persistedValue = color(0.5, 0.4, 0.3)
        buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID][2468] = { value = persistedValue }

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("spellID", entries[1].key.keyType)
        assert.are.equal(2468, entries[1].key.primaryKey)
        assert.are.same(persistedValue, entries[1].color)
    end)

    it("GetAllColorEntries preserves each store tier raw key when value.keyType mismatches", function()
        BuffSpellColors:GetDefaultColor()

        local tierCases = {
            {
                storeKey = "byName",
                rawKey = "Raw Persisted Name",
                value = { r = 0.1, g = 0.2, b = 0.3, a = 1, keyType = "spellID", spellID = 7101 },
                rawField = "spellName",
            },
            {
                storeKey = "bySpellID",
                rawKey = 7102,
                value = { r = 0.2, g = 0.3, b = 0.4, a = 1, keyType = "spellName", spellName = "Metadata Name" },
                rawField = "spellID",
            },
            {
                storeKey = "byCooldownID",
                rawKey = 7103,
                value = { r = 0.3, g = 0.4, b = 0.5, a = 1, keyType = "spellName", spellName = "Metadata Name" },
                rawField = "cooldownID",
            },
            {
                storeKey = "byTexture",
                rawKey = 7104,
                value = { r = 0.4, g = 0.5, b = 0.6, a = 1, keyType = "spellName", spellName = "Metadata Name" },
                rawField = "textureFileID",
            },
        }

        for _, tierCase in ipairs(tierCases) do
            for _, storeKey in ipairs({ "byName", "bySpellID", "byCooldownID", "byTexture" }) do
                buffBarsConfig.colors[storeKey][currentClassID] = buffBarsConfig.colors[storeKey][currentClassID] or {}
                buffBarsConfig.colors[storeKey][currentClassID][currentSpecID] = {}
            end

            buffBarsConfig.colors[tierCase.storeKey][currentClassID][currentSpecID][tierCase.rawKey] = {
                value = tierCase.value,
            }

            local entries = BuffSpellColors:GetAllColorEntries()
            assert.are.equal(1, #entries)
            assert.are.equal(tierCase.rawKey, entries[1].key[tierCase.rawField])
            assert.is_nil(entries[1].color.keyType)
        end
    end)

    it("GetAllColorEntries logically deduplicates fragmented wrappers and prefers newest color", function()
        BuffSpellColors:GetDefaultColor()

        for _, storeKey in ipairs({ "byName", "bySpellID", "byCooldownID", "byTexture" }) do
            buffBarsConfig.colors[storeKey][currentClassID] = buffBarsConfig.colors[storeKey][currentClassID] or {}
            buffBarsConfig.colors[storeKey][currentClassID][currentSpecID] = {}
        end

        local older = {
            value = { r = 0.2, g = 0.3, b = 0.4, a = 1 }, t = 10,
            meta = { keyType = "spellName", primaryKey = "Demon Spikes", spellName = "Demon Spikes", spellID = 203720 },
        }
        local newer = {
            value = { r = 0.8, g = 0.7, b = 0.6, a = 1 }, t = 20,
            meta = { keyType = "spellID", primaryKey = 203720, spellID = 203720, cooldownID = 11431 },
        }

        buffBarsConfig.colors.byName[currentClassID][currentSpecID]["Demon Spikes"] = older
        buffBarsConfig.colors.bySpellID[currentClassID][currentSpecID][203720] = newer
        buffBarsConfig.colors.byCooldownID[currentClassID][currentSpecID][11431] = newer

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Demon Spikes", entries[1].key.spellName)
        assert.are.equal(203720, entries[1].key.spellID)
        assert.are.equal(11431, entries[1].key.cooldownID)
        assert.are.same(newer.value, entries[1].color)
    end)

    it("GetAllColorEntries keeps reconciled byName raw keys so reset clears byName mappings", function()
        local persisted = color(0.6, 0.1, 0.9)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey(nil, 1357, nil, nil), persisted)

        BuffSpellColors:ReconcileAllKeys({ SpellColors.MakeKey("Persisted Name", 1357, nil, nil) })

        assert.are.same(persisted, BuffSpellColors:GetColorByKey({ spellName = "Persisted Name" }))

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Persisted Name", entries[1].key.spellName)
        assert.are.equal(1357, entries[1].key.spellID)

        local nameCleared, spellIDCleared = BuffSpellColors:ResetColorByKey(entries[1].key)
        assert.is_true(nameCleared)
        assert.is_true(spellIDCleared)
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellName = "Persisted Name" }))
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellID = 1357 }))
    end)

    it("isolates stored colors by class and specialization", function()
        currentClassID, currentSpecID = 12, 1
        local c = color(0.3, 0.8, 0.1)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Shared Name", nil, nil, nil), c)

        currentClassID, currentSpecID = 12, 2
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellName = "Shared Name" }))

        currentClassID, currentSpecID = 11, 1
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellName = "Shared Name" }))

        currentClassID, currentSpecID = 12, 1
        assert.are.same(c, BuffSpellColors:GetColorByKey({ spellName = "Shared Name" }))
    end)

    it("ClearCurrentSpecColors only clears the requested scope", function()
        local buffColor = color(0.1, 0.2, 0.3)
        local externalColor = color(0.4, 0.5, 0.6)
        local key = SpellColors.MakeKey("Scoped Clear", nil, nil, nil)

        BuffSpellColors:SetColorByKey(key, buffColor)
        ExternalSpellColors:SetColorByKey(key, externalColor)

        local cleared = ExternalSpellColors:ClearCurrentSpecColors()
        assert.are.equal(1, cleared)
        assert.are.same(buffColor, BuffSpellColors:GetColorByKey({ spellName = "Scoped Clear" }))
        assert.is_nil(ExternalSpellColors:GetColorByKey({ spellName = "Scoped Clear" }))
    end)

    it("returns empty entries when class or spec cannot be determined", function()
        local c = color(0.4, 0.4, 0.4)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Stored", nil, nil, nil), c)

        _G.GetSpecialization = function()
            return nil
        end
        assert.are.same({}, BuffSpellColors:GetAllColorEntries())

        _G.GetSpecialization = function()
            return currentSpecID
        end
        _G.UnitClass = function()
            return "Demon Hunter", "DEMONHUNTER", nil
        end
        assert.are.same({}, BuffSpellColors:GetAllColorEntries())
    end)

    it("ClearCurrentSpecColors clears current class/spec entries across all tiers and reports count", function()
        BuffSpellColors:GetDefaultColor()

        local otherClassID = currentClassID + 1
        local otherSpecID = currentSpecID + 1
        local tierDefs = {
            { store = "byName", key = "clear-test-name" },
            { store = "bySpellID", key = 100001 },
            { store = "byCooldownID", key = 100002 },
            { store = "byTexture", key = 100003 },
        }

        for _, tier in ipairs(tierDefs) do
            local store = buffBarsConfig.colors[tier.store]

            store[currentClassID] = store[currentClassID] or {}
            store[currentClassID][currentSpecID] = store[currentClassID][currentSpecID] or {}
            store[currentClassID][currentSpecID][tier.key] = { value = color(0.1, 0.2, 0.3), t = 1 }

            store[otherClassID] = store[otherClassID] or {}
            store[otherClassID][otherSpecID] = store[otherClassID][otherSpecID] or {}
            store[otherClassID][otherSpecID][tier.key] = { value = color(0.9, 0.8, 0.7), t = 2 }
        end

        local cleared = BuffSpellColors:ClearCurrentSpecColors()
        assert.are.equal(4, cleared)

        for _, tier in ipairs(tierDefs) do
            local store = buffBarsConfig.colors[tier.store]
            assert.is_table(store[currentClassID][currentSpecID])
            assert.is_nil(next(store[currentClassID][currentSpecID]))
            assert.is_not_nil(store[otherClassID][otherSpecID][tier.key])
        end
    end)

    it("ClearCurrentSpecColors invalidates and rebuilds cached map for subsequent lookups", function()
        local oldColor = color(0.2, 0.5, 0.8)
        local newColor = color(0.8, 0.2, 0.5)
        local key = SpellColors.MakeKey("Map Reset Spell", 543210, 654321, 765432)

        BuffSpellColors:SetColorByKey(key, oldColor)
        assert.are.same(oldColor, BuffSpellColors:GetColorByKey({ spellName = "Map Reset Spell" }))

        local cleared = BuffSpellColors:ClearCurrentSpecColors()
        assert.is_true(cleared > 0)
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellName = "Map Reset Spell" }))
        assert.is_nil(BuffSpellColors:GetColorByKey({ spellID = 543210 }))

        BuffSpellColors:SetColorByKey(key, newColor)
        assert.are.same(newColor, BuffSpellColors:GetColorByKey({ spellName = "Map Reset Spell" }))
        assert.are.same(newColor, BuffSpellColors:GetColorByKey({ spellID = 543210 }))
    end)

    ---------------------------------------------------------------------------
    -- DiscoverBar / ClearDiscoveredKeys / GetAllColorEntries integration
    ---------------------------------------------------------------------------

    it("DiscoverBar adds keys to discovered cache and GetAllColorEntries includes them", function()
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Demon Spikes",
            spellID = 203720,
        }))

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Demon Spikes", entries[1].key.spellName)
        assert.are.equal(203720, entries[1].key.spellID)
        assert.is_nil(entries[1].color)
    end)

    it("DiscoverBar and GetAllColorEntries keep discovered keys scoped", function()
        BuffSpellColors:ClearDiscoveredKeys()
        ExternalSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Buff Scoped",
            spellID = 101,
        }))
        ExternalSpellColors:DiscoverBar(makeFrame({
            spellName = "External Scoped",
            spellID = 202,
        }))

        local buffEntries = BuffSpellColors:GetAllColorEntries()
        local externalEntries = ExternalSpellColors:GetAllColorEntries()

        assert.are.equal(1, #buffEntries)
        assert.are.equal("Buff Scoped", buffEntries[1].key.spellName)
        assert.are.equal(1, #externalEntries)
        assert.are.equal("External Scoped", externalEntries[1].key.spellName)
    end)

    it("ClearDiscoveredKeys only clears the requested scope", function()
        BuffSpellColors:ClearDiscoveredKeys()
        ExternalSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Buff Scoped",
            spellID = 101,
        }))
        ExternalSpellColors:DiscoverBar(makeFrame({
            spellName = "External Scoped",
            spellID = 202,
        }))

        ExternalSpellColors:ClearDiscoveredKeys()

        local buffEntries = BuffSpellColors:GetAllColorEntries()
        local externalEntries = ExternalSpellColors:GetAllColorEntries()

        assert.are.equal(1, #buffEntries)
        assert.are.equal("Buff Scoped", buffEntries[1].key.spellName)
        assert.are.equal(0, #externalEntries)
    end)

    it("DiscoverBar deduplicates matching keys and merges identifiers", function()
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Eye Beam",
            spellID = 198013,
        }))
        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Eye Beam",
            cooldownID = 55,
            textureFileID = 1111,
        }))

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Eye Beam", entries[1].key.spellName)
        assert.are.equal(198013, entries[1].key.spellID)
        assert.are.equal(55, entries[1].key.cooldownID)
        assert.are.equal(1111, entries[1].key.textureFileID)
    end)

    it("discovered keys merge with persisted entries in GetAllColorEntries", function()
        BuffSpellColors:ClearDiscoveredKeys()

        local c = color(0.5, 0.6, 0.7)
        BuffSpellColors:SetColorByKey(SpellColors.MakeKey("Immolation Aura", 258920, nil, nil), c)

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Immolation Aura",
            spellID = 258920,
            cooldownID = 77,
            textureFileID = 9001,
        }))

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Immolation Aura", entries[1].key.spellName)
        assert.are.equal(258920, entries[1].key.spellID)
        assert.are.equal(77, entries[1].key.cooldownID)
        assert.are.equal(9001, entries[1].key.textureFileID)
        assert.are.same(c, entries[1].color)
    end)

    it("ClearDiscoveredKeys wipes the discovered cache", function()
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({ spellName = "Temp Spell" }))
        assert.are.equal(1, #BuffSpellColors:GetAllColorEntries())

        BuffSpellColors:ClearDiscoveredKeys()
        assert.are.equal(0, #BuffSpellColors:GetAllColorEntries())
    end)

    it("DiscoverBar ignores frames with all secret values", function()
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = markSecret("Secret Name"),
            spellID = markSecret(12345),
        }))

        assert.are.equal(0, #BuffSpellColors:GetAllColorEntries())
    end)

    it("ClearDiscoveredKeys on spec change prevents cross-spec leaking", function()
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Demon Spikes",
            spellID = 203720,
        }))
        assert.are.equal(1, #BuffSpellColors:GetAllColorEntries())

        -- Simulate spec change: BuffBars:UpdateLayout calls ClearDiscoveredKeys
        currentSpecID = 1
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Fel Rush",
            spellID = 195072,
        }))

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(1, #entries)
        assert.are.equal("Fel Rush", entries[1].key.spellName)
    end)

    it("ClearDiscoveredKeys on spec change with no new bars yields empty entries", function()
        BuffSpellColors:ClearDiscoveredKeys()

        BuffSpellColors:DiscoverBar(makeFrame({
            spellName = "Demon Spikes",
            spellID = 203720,
        }))
        assert.are.equal(1, #BuffSpellColors:GetAllColorEntries())

        -- Simulate spec change: BuffBars:UpdateLayout calls ClearDiscoveredKeys
        currentSpecID = 1
        BuffSpellColors:ClearDiscoveredKeys()

        local entries = BuffSpellColors:GetAllColorEntries()
        assert.are.equal(0, #entries)
    end)
end)
