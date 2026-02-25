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

describe("BuffBarsOptions", function()
    local originalGlobals
    local BuffBarsOptions
    local SpellColors
    local layoutUpdateCalls
    local notifyChangeCalls
    local addonDB

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
            "ECM_tostring",
            "LibStub",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        layoutUpdateCalls = 0
        notifyChangeCalls = 0

        _G.ECM = {
            FrameUtil = {
                GetIconTextureFileID = function()
                    return nil
                end,
            },
            ScheduleLayoutUpdate = function()
                layoutUpdateCalls = layoutUpdateCalls + 1
            end,
            BuffBars = {
                IsEditLocked = function()
                    return false, nil
                end,
                GetActiveSpellData = function()
                    return {}
                end,
            },
            OptionUtil = {
                GetCurrentClassSpec = function()
                    return 12, 2, "Demon Hunter", "Havoc"
                end,
                IsValueChanged = function()
                    return false
                end,
                MakeResetHandler = function()
                    return function() end
                end,
                MakePositioningGroup = function()
                    return {
                        type = "group",
                        name = "Positioning",
                        args = {},
                    }
                end,
                SetModuleEnabled = function() end,
            },
            OptionBuilder = {
                MergeArgs = function(target, source)
                    for key, value in pairs(source or {}) do
                        target[key] = value
                    end
                    return target
                end,
                MakeSpacer = function(order)
                    return { type = "description", name = "\n", order = order }
                end,
                BuildFontOverrideArgs = function()
                    return {
                        fontOverrideDesc = { type = "description", order = 14 },
                        overrideFont = { type = "toggle", name = "Override font", order = 15 },
                        font = { type = "select", name = "Font", order = 16 },
                        fontReset = { type = "execute", order = 17 },
                        fontSize = { type = "range", name = "Font Size", order = 18 },
                        fontSizeReset = { type = "execute", order = 19 },
                    }
                end,
            },
        }

        _G.UnitClass = function()
            return "Demon Hunter", "DEMONHUNTER", 12
        end
        _G.GetSpecialization = function()
            return 2
        end

        _G.issecretvalue = function()
            return false
        end
        _G.issecrettable = function()
            return false
        end
        _G.canaccessvalue = function()
            return true
        end
        _G.canaccesstable = function()
            return true
        end

        _G.time = function()
            return 1000
        end

        _G.ECM.DebugAssert = function() end
        _G.ECM.Log = function() end
        _G.ECM_tostring = function(value)
            return tostring(value)
        end

        _G.LibStub = function()
            return {
                NotifyChange = function()
                    notifyChangeCalls = notifyChangeCalls + 1
                end,
            }
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

        local addonNS = {
            Addon = {
                db = {
                    profile = {
                        buffBars = {},
                    },
                },
            },
        }
        addonDB = addonNS.Addon.db

        local spellColorsChunk = TestHelpers.loadChunk(
            {
                "Modules/SpellColors.lua",
                "../Modules/SpellColors.lua",
            },
            "Unable to load Modules/SpellColors.lua"
        )
        spellColorsChunk(nil, addonNS)
        SpellColors = assert(ECM.SpellColors, "SpellColors module did not initialize")

        local optionsNS = {
            Addon = addonNS.Addon,
        }
        local optionsChunk = TestHelpers.loadChunk(
            {
                "Options/BuffBarsOptions.lua",
                "../Options/BuffBarsOptions.lua",
            },
            "Unable to load Options/BuffBarsOptions.lua"
        )
        optionsChunk(nil, optionsNS)
        BuffBarsOptions = assert(optionsNS.BuffBarsOptions, "BuffBarsOptions module did not initialize")
    end)

    it("_BuildSpellColorRows keeps active-bar order and appends persisted-only rows", function()
        local activeBars = {
            SpellColors.MakeKey("Active Name", 1001, nil, nil),
            SpellColors.MakeKey(nil, nil, nil, 2002),
        }
        local savedEntries = {
            { key = SpellColors.MakeKey("Active Name", 1001, 77, 9001) },
            { key = SpellColors.MakeKey("Persisted Only", 3003, nil, nil) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(activeBars, savedEntries)
        assert.are.equal(3, #rows)
        assert.are.equal("Active Name", rows[1].key.primaryKey)
        assert.are.equal(2002, rows[2].key.primaryKey)
        assert.are.equal("Persisted Only", rows[3].key.primaryKey)
    end)

    it("_BuildSpellColorRows merges matching keys and carries fallback identifiers", function()
        local activeBars = {
            SpellColors.MakeKey("Immolation Aura", 258920, nil, nil),
        }
        local savedEntries = {
            { key = SpellColors.MakeKey(nil, 258920, 77, 9001) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(activeBars, savedEntries)
        assert.are.equal(1, #rows)
        assert.are.equal("spellName", rows[1].key.keyType)
        assert.are.equal("Immolation Aura", rows[1].key.primaryKey)
        assert.are.equal(258920, rows[1].key.spellID)
        assert.are.equal(77, rows[1].key.cooldownID)
        assert.are.equal(9001, rows[1].key.textureFileID)
        assert.are.equal(9001, rows[1].textureFileID)
    end)

    it("_BuildSpellColorRows does not merge unrelated rows that only share texture", function()
        local activeBars = {
            SpellColors.MakeKey("Spell A", nil, nil, 1234),
        }
        local savedEntries = {
            { key = SpellColors.MakeKey("Spell B", nil, nil, 1234) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(activeBars, savedEntries)
        assert.are.equal(2, #rows)
        assert.are.equal("Spell A", rows[1].key.primaryKey)
        assert.are.equal("Spell B", rows[2].key.primaryKey)
    end)

    it("_BuildSpellColorRows merges texture-only keys", function()
        local activeBars = {
            SpellColors.MakeKey(nil, nil, nil, 4444),
        }
        local savedEntries = {
            { key = SpellColors.MakeKey(nil, nil, nil, 4444) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(activeBars, savedEntries)
        assert.are.equal(1, #rows)
        assert.are.equal(4444, rows[1].key.primaryKey)
        assert.are.equal(4444, rows[1].textureFileID)
    end)

    it("_BuildSpellColorRows ignores invalid entries and handles nil inputs", function()
        local rows = BuffBarsOptions._BuildSpellColorRows(nil, {
            {},
            { key = nil },
            { key = SpellColors.MakeKey("Valid", nil, nil, nil) },
        })

        assert.are.equal(1, #rows)
        assert.are.equal("Valid", rows[1].key.primaryKey)
    end)

    it("_BuildSpellColorArgsFromRows builds row getters with default fallback", function()
        local rowKey = SpellColors.MakeKey("Getter Spell", 1111, 55, 3333)
        local rows = {
            { key = rowKey, textureFileID = 3333 },
        }

        local customColorCalls = 0
        local customColor = { r = 0.1, g = 0.2, b = 0.3, a = 1 }
        local defaultColor = { r = 0.7, g = 0.6, b = 0.5, a = 1 }
        local originalGetColorByKey = ECM.SpellColors.GetColorByKey
        local originalGetDefaultColor = ECM.SpellColors.GetDefaultColor

        ECM.SpellColors.GetColorByKey = function(key)
            assert.are.same(rowKey, key)
            customColorCalls = customColorCalls + 1
            if customColorCalls == 1 then
                return customColor
            end
            return nil
        end
        ECM.SpellColors.GetDefaultColor = function()
            return defaultColor
        end

        local args = BuffBarsOptions._BuildSpellColorArgsFromRows(rows)
        local r1, g1, b1 = args.spellColor1.get()
        local r2, g2, b2 = args.spellColor1.get()

        assert.are.equal(customColor.r, r1)
        assert.are.equal(customColor.g, g1)
        assert.are.equal(customColor.b, b1)
        assert.are.equal(defaultColor.r, r2)
        assert.are.equal(defaultColor.g, g2)
        assert.are.equal(defaultColor.b, b2)
        assert.is_true(args.spellColor1.name:find("|T3333:14:14|t", 1, true) ~= nil)

        ECM.SpellColors.GetColorByKey = originalGetColorByKey
        ECM.SpellColors.GetDefaultColor = originalGetDefaultColor
    end)

    it("_BuildSpellColorArgsFromRows row set callback writes color and refreshes layout", function()
        local rowKey = SpellColors.MakeKey("Setter Spell", 2222, 66, 4444)
        local rows = {
            { key = rowKey, textureFileID = 4444 },
        }

        local capturedKey, capturedColor
        local originalSetColorByKey = ECM.SpellColors.SetColorByKey
        ECM.SpellColors.SetColorByKey = function(key, color)
            capturedKey = key
            capturedColor = color
        end

        local args = BuffBarsOptions._BuildSpellColorArgsFromRows(rows)
        args.spellColor1.set(nil, 0.9, 0.8, 0.7)

        assert.are.same(rowKey, capturedKey)
        assert.are.same({ r = 0.9, g = 0.8, b = 0.7, a = 1 }, capturedColor)
        assert.are.equal(1, layoutUpdateCalls)

        ECM.SpellColors.SetColorByKey = originalSetColorByKey
    end)

    it("_BuildSpellColorArgsFromRows reset button hidden and func use row key", function()
        local rowKey = SpellColors.MakeKey("Reset Spell", 3333, 77, 5555)
        local rows = {
            { key = rowKey, textureFileID = 5555 },
        }

        local hasColor = false
        local capturedResetKey
        local originalGetColorByKey = ECM.SpellColors.GetColorByKey
        local originalResetColorByKey = ECM.SpellColors.ResetColorByKey
        ECM.SpellColors.GetColorByKey = function(key)
            assert.are.same(rowKey, key)
            if hasColor then
                return { r = 0.2, g = 0.3, b = 0.4, a = 1 }
            end
            return nil
        end
        ECM.SpellColors.ResetColorByKey = function(key)
            capturedResetKey = key
        end

        local args = BuffBarsOptions._BuildSpellColorArgsFromRows(rows)
        assert.is_true(args.spellColor1Reset.hidden())
        hasColor = true
        assert.is_false(args.spellColor1Reset.hidden())

        args.spellColor1Reset.func()
        assert.are.same(rowKey, capturedResetKey)
        assert.are.equal(1, layoutUpdateCalls)

        ECM.SpellColors.GetColorByKey = originalGetColorByKey
        ECM.SpellColors.ResetColorByKey = originalResetColorByKey
    end)

    it("_BuildSpellColorArgsFromRows returns noData description for empty rows", function()
        local args = BuffBarsOptions._BuildSpellColorArgsFromRows({})
        assert.is_table(args.noData)
        assert.are.equal("description", args.noData.type)
    end)

    it("GetOptionsTable reset callback clears persisted-only reconciled name mappings", function()
        local persisted = { r = 0.4, g = 0.2, b = 0.8, a = 1 }
        SpellColors.SetColorByKey(SpellColors.MakeKey(nil, 8080, nil, nil), persisted)
        SpellColors.ReconcileBar({
            __ecmHooked = true,
            Bar = {
                Name = {
                    GetText = function()
                        return "Persisted Name"
                    end,
                },
            },
            cooldownInfo = { spellID = 8080 },
        })

        assert.are.same(persisted, SpellColors.GetColorByKey({ spellName = "Persisted Name" }))
        assert.are.same(persisted, SpellColors.GetColorByKey({ spellID = 8080 }))

        local options = BuffBarsOptions.GetOptionsTable()
        local spellArgs = options.args.spells.args.spellColorsGroup.args
        local reset = spellArgs.spellColor1Reset

        assert.is_table(reset)
        assert.is_false(reset.hidden())
        reset.func()

        assert.are.equal(1, layoutUpdateCalls)
        assert.is_nil(SpellColors.GetColorByKey({ spellName = "Persisted Name" }))
        assert.is_nil(SpellColors.GetColorByKey({ spellID = 8080 }))
    end)

    it("Refresh Spell List reconciles active keys before notifying options", function()
        local activeKeys = {
            SpellColors.MakeKey("Demon Spikes", 203720, 11431, 1344645),
        }
        local gotKeys
        local reconcileCalls = 0

        ECM.BuffBars.GetActiveSpellData = function()
            return activeKeys
        end

        local originalReconcileAllKeys = ECM.SpellColors.ReconcileAllKeys
        ECM.SpellColors.ReconcileAllKeys = function(keys)
            reconcileCalls = reconcileCalls + 1
            gotKeys = keys
            return 1
        end

        local options = BuffBarsOptions.GetOptionsTable()
        options.args.spells.args.refreshSpellList.func()

        assert.are.equal(1, reconcileCalls)
        assert.are.same(activeKeys, gotKeys)
        assert.are.equal(1, notifyChangeCalls)

        ECM.SpellColors.ReconcileAllKeys = originalReconcileAllKeys
    end)

    it("adds a free grow direction selector to positioning settings", function()
        local options = BuffBarsOptions.GetOptionsTable()
        local positioningArgs = options.args.positioningSettings.args
        local desc = positioningArgs.freeGrowDirectionDesc
        local selector = positioningArgs.freeGrowDirection
        local reset = positioningArgs.freeGrowDirectionReset

        assert.is_table(desc)
        assert.is_table(selector)
        assert.are.equal("select", selector.type)
        assert.are.equal("Free Grow Direction", selector.name)
        assert.is_true(desc.hidden())
        assert.is_true(selector.hidden())
        assert.is_true(reset.hidden())

        addonDB.profile.buffBars.anchorMode = ECM.Constants.ANCHORMODE_FREE
        assert.is_false(desc.hidden())
        assert.is_false(selector.hidden())

        selector.set(nil, ECM.Constants.GROW_DIRECTION_UP)
        assert.are.equal(ECM.Constants.GROW_DIRECTION_UP, addonDB.profile.buffBars.freeGrowDirection)
        assert.are.equal(1, layoutUpdateCalls)

        ECM.OptionUtil.IsValueChanged = function()
            return true
        end
        assert.is_false(reset.hidden())

        addonDB.profile.buffBars.anchorMode = ECM.Constants.ANCHORMODE_CHAIN
        assert.is_true(reset.hidden())
    end)

    it("GetOptionsTable includes font override controls in display settings", function()
        local options = BuffBarsOptions.GetOptionsTable()
        local displayArgs = options.args.displaySettings.args

        assert.is_table(displayArgs.fontOverrideDesc)
        assert.is_table(displayArgs.overrideFont)
        assert.is_table(displayArgs.font)
        assert.is_table(displayArgs.fontReset)
        assert.is_table(displayArgs.fontSize)
        assert.is_table(displayArgs.fontSizeReset)
    end)
end)
