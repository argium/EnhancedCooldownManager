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

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM", "ECM_CloneValue", "ECM_DeepEquals",
            "Settings", "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer", "MinimalSliderWithSteppersMixin",
            "CreateColor", "StaticPopupDialogs", "StaticPopup_Show", "YES", "NO",
            "UnitClass", "GetSpecialization", "GetSpecializationInfo",
            "issecretvalue", "issecrettable", "canaccessvalue", "canaccesstable",
            "time", "ECM_tostring",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.setupSettingsStubs()

        _G.UnitClass = function() return "Demon Hunter", "DEMONHUNTER", 12 end
        _G.GetSpecialization = function() return 2 end
        _G.GetSpecializationInfo = function() return nil, "Havoc" end

        _G.issecretvalue = function() return false end
        _G.issecrettable = function() return false end
        _G.canaccessvalue = function() return true end
        _G.canaccesstable = function() return true end
        _G.time = function() return 1000 end
        _G.ECM_tostring = function(v) return tostring(v) end

        _G.ECM = {
            Constants = {},
            FrameUtil = { GetIconTextureFileID = function() return nil end },
            ScheduleLayoutUpdate = function() end,
            BuffBars = {
                IsEditLocked = function() return false, nil end,
                GetActiveSpellData = function() return {} end,
            },
            OptionUtil = {
                GetCurrentClassSpec = function() return 12, 2, "Demon Hunter", "Havoc", "DEMONHUNTER" end,
                SetModuleEnabled = function() end,
                GetNestedValue = function(tbl, path)
                    local current = tbl
                    for key in path:gmatch("[^.]+") do
                        if type(current) ~= "table" then return nil end
                        current = current[key]
                    end
                    return current
                end,
                SetNestedValue = function(tbl, path, value)
                    local parts = {}
                    for key in path:gmatch("[^.]+") do parts[#parts + 1] = key end
                    local current = tbl
                    for i = 1, #parts - 1 do
                        if current[parts[i]] == nil then current[parts[i]] = {} end
                        current = current[parts[i]]
                    end
                    current[parts[#parts]] = value
                end,
                IsAnchorModeFree = function() return false end,
                POSITION_MODE_TEXT = {},
                ApplyPositionModeToBar = function() end,
                IsValueChanged = function() return false end,
            },
            SharedMediaOptions = {
                GetFontValues = function() return {} end,
            },
            DebugAssert = function() end,
            Log = function() end,
        }

        -- Load Constants
        local constantsChunk = TestHelpers.loadChunk(
            { "Constants.lua", "../Constants.lua" },
            "Unable to load Constants.lua"
        )
        constantsChunk()

        -- Load PriorityKeyMap
        local priorityMapChunk = TestHelpers.loadChunk(
            { "Modules/PriorityKeyMap.lua", "../Modules/PriorityKeyMap.lua" },
            "Unable to load PriorityKeyMap.lua"
        )
        priorityMapChunk()

        -- Load SpellColors
        local addonNS = {
            Addon = {
                db = {
                    profile = { buffBars = {} },
                    defaults = { profile = { buffBars = {} } },
                },
            },
        }

        local spellColorsChunk = TestHelpers.loadChunk(
            { "Modules/SpellColors.lua", "../Modules/SpellColors.lua" },
            "Unable to load SpellColors.lua"
        )
        spellColorsChunk(nil, addonNS)
        SpellColors = ECM.SpellColors

        -- Load OptionUtil + SettingsBuilder so BuffBarsOptions can register
        local optUtilChunk = TestHelpers.loadChunk(
            { "Options/OptionUtil.lua", "../Options/OptionUtil.lua" },
            "Unable to load OptionUtil.lua"
        )
        optUtilChunk(nil, addonNS)

        local sbChunk = TestHelpers.loadChunk(
            { "Options/SettingsBuilder.lua", "../Options/SettingsBuilder.lua" },
            "Unable to load SettingsBuilder.lua"
        )
        sbChunk(nil, addonNS)

        -- Create root category so subcategory calls work
        ECM.SettingsBuilder.CreateRootCategory("Test")

        -- Load BuffBarsOptions
        local optionsNS = {
            Addon = addonNS.Addon,
            OptionsSections = {},
        }
        local buffChunk = TestHelpers.loadChunk(
            { "Options/BuffBarsOptions.lua", "../Options/BuffBarsOptions.lua" },
            "Unable to load BuffBarsOptions.lua"
        )
        buffChunk(nil, optionsNS)
        BuffBarsOptions = optionsNS.BuffBarsOptions
    end)

    -- _BuildSpellColorRows tests (pure logic, preserved from old tests)

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

    it("section registers with key BuffBars", function()
        -- BuffBarsOptions should have registered itself
        assert.is_function(BuffBarsOptions.RegisterSettings)
    end)
end)
