-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BuffBarsOptions", function()
    local originalGlobals
    local BuffBarsOptions
    local SpellColors
    local SB
    local ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM_DeepEquals",
            "Settings",
            "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer",
            "MinimalSliderWithSteppersMixin",
            "CreateColor",
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "YES",
            "NO",
            "UnitClass",
            "GetSpecialization",
            "GetSpecializationInfo",
            "issecretvalue",
            "issecrettable",
            "canaccessvalue",
            "canaccesstable",
            "time",
            "InCombatLockdown",
            "IsInInstance",
            "LibStub",
            "CreateFromMixins",
            "SettingsListElementInitializer",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()

        local profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        _G.UnitClass = function()
            return "Demon Hunter", "DEMONHUNTER", 12
        end
        _G.GetSpecialization = function()
            return 2
        end
        _G.GetSpecializationInfo = function()
            return nil, "Havoc"
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
        _G.InCombatLockdown = function()
            return false
        end
        _G.IsInInstance = function()
            return false
        end

        ns.Constants = {}
        ns.FrameUtil = {
            GetIconTextureFileID = function()
                return nil
            end,
        }
        ns.ScheduleLayoutUpdate = function() end
        ns.ToString = function(v)
            return tostring(v)
        end
        ns.OptionUtil = {
            GetCurrentClassSpec = function()
                return 12, 2, "Demon Hunter", "Havoc", "DEMONHUNTER"
            end,
            IsAnchorModeFree = function()
                return false
            end,
            POSITION_MODE_TEXT = {},
            ApplyPositionModeToBar = function() end,
            IsValueChanged = function()
                return false
            end,
        }

        ns.DebugAssert = function() end
        ns.Log = function() end

        -- Load library
        local lsmw = LibStub("LibLSMSettingsWidgets-1.0", true) or TestHelpers.SetupLibSettingsBuilder()
        lsmw.GetFontValues = function()
            return {}
        end
        lsmw.GetStatusbarValues = function()
            return {}
        end

        -- Load Constants
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        -- Load SpellColors
        ns.Addon = {
            db = {
                profile = { buffBars = {} },
                defaults = { profile = { buffBars = {} } },
            },
            BuffBars = {
                IsEditLocked = function()
                    return false, nil
                end,
                GetActiveSpellData = function()
                    return {}
                end,
            },
            NewModule = function(_, name)
                return { moduleName = name }
            end,
        }

        TestHelpers.LoadChunk("Helpers/SpellColors.lua", "Unable to load Helpers/SpellColors.lua")(nil, ns)
        SpellColors = ns.SpellColors

        -- Load Options (includes SettingsBuilder adapter)
        TestHelpers.LoadChunk("UI/OptionUtil.lua", "Unable to load UI/OptionUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

        -- Create root category so subcategory calls work
        SB.CreateRootCategory("Test")

        -- Load BuffBarsOptions
        TestHelpers.LoadChunk("UI/BuffBarsOptions.lua", "Unable to load UI/BuffBarsOptions.lua")(nil, ns)
        BuffBarsOptions = ns.BuffBarsOptions
    end)

    -- _BuildSpellColorRows tests (pure logic, preserved from old tests)

    it("_BuildSpellColorRows deduplicates matching entries and preserves order", function()
        local entries = {
            { key = SpellColors.MakeKey("Active Name", 1001, nil, nil) },
            { key = SpellColors.MakeKey(nil, nil, nil, 2002) },
            { key = SpellColors.MakeKey("Active Name", 1001, 77, 9001) },
            { key = SpellColors.MakeKey("Persisted Only", 3003, nil, nil) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(3, #rows)
        assert.are.equal("Active Name", rows[1].key.primaryKey)
        assert.are.equal(2002, rows[2].key.primaryKey)
        assert.are.equal("Persisted Only", rows[3].key.primaryKey)
    end)

    it("_BuildSpellColorRows merges matching keys and carries fallback identifiers", function()
        local entries = {
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
            { key = SpellColors.MakeKey(nil, 258920, 77, 9001) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(1, #rows)
        assert.are.equal("spellName", rows[1].key.keyType)
        assert.are.equal("Immolation Aura", rows[1].key.primaryKey)
        assert.are.equal(258920, rows[1].key.spellID)
        assert.are.equal(77, rows[1].key.cooldownID)
        assert.are.equal(9001, rows[1].key.textureFileID)
        assert.are.equal(9001, rows[1].textureFileID)
    end)

    it("_BuildSpellColorRows does not merge unrelated rows that only share texture", function()
        local entries = {
            { key = SpellColors.MakeKey("Spell A", nil, nil, 1234) },
            { key = SpellColors.MakeKey("Spell B", nil, nil, 1234) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(2, #rows)
        assert.are.equal("Spell A", rows[1].key.primaryKey)
        assert.are.equal("Spell B", rows[2].key.primaryKey)
    end)

    it("_BuildSpellColorRows merges texture-only keys", function()
        local entries = {
            { key = SpellColors.MakeKey(nil, nil, nil, 4444) },
            { key = SpellColors.MakeKey(nil, nil, nil, 4444) },
        }

        local rows = BuffBarsOptions._BuildSpellColorRows(entries)
        assert.are.equal(1, #rows)
        assert.are.equal(4444, rows[1].key.primaryKey)
        assert.are.equal(4444, rows[1].textureFileID)
    end)

    it("_BuildSpellColorRows ignores invalid entries and handles nil inputs", function()
        local rows = BuffBarsOptions._BuildSpellColorRows({
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

    it("_GetSecretNameFooterState hides the footer when all bar names are available", function()
        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = SpellColors.MakeKey("Immolation Aura", 258920, nil, nil) },
        })

        assert.is_false(state.show)
        assert.is_false(state.enabled)
    end)

    it("_GetSecretNameFooterState shows an enabled footer for unlabeled bars outside restricted areas", function()
        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = { primaryKey = "" } },
        })

        assert.is_true(state.show)
        assert.is_true(state.enabled)
    end)

    it("_GetSecretNameFooterState disables reload in instances", function()
        _G.IsInInstance = function()
            return true, "party"
        end

        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = { primaryKey = "" } },
        })

        assert.is_true(state.show)
        assert.is_false(state.enabled)
    end)

    it("_GetSecretNameFooterState disables reload during combat", function()
        _G.InCombatLockdown = function()
            return true
        end
        _G.issecretvalue = function(value)
            return value == "Secret Spell"
        end

        local state = BuffBarsOptions._GetSecretNameFooterState({
            { key = { primaryKey = "Secret Spell" } },
        })

        assert.is_true(state.show)
        assert.is_false(state.enabled)
    end)
end)
