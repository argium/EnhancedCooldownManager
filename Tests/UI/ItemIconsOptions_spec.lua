-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ItemIconsOptions", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        TestHelpers.SetupItemIconsConstants(ECM.Constants)
        ECM.Constants.RACE_RACIALS = {
            Human = { 59752 },
            Tauren = { 20549 },
        }

        _G.UnitRace = function() return "Tauren", "Tauren" end

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ItemIconsStore.lua", "ItemIconsStore")(nil, ns)
            TestHelpers.LoadChunk("UI/ItemIconsOptions.lua", "ItemIconsOptions")(nil, ns)
            ns.OptionsSections.ItemIcons.RegisterSettings(SB)
        end)
    end)

    describe("enabled", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_itemIcons_enabled"]:GetValue())
        end)

        it("setter writes to profile", function()
            settings["ECM_itemIcons_enabled"]:SetValue(false)
            assert.is_false(profile.itemIcons.enabled)
        end)

        it("default matches expected", function()
            assert.is_true(settings["ECM_itemIcons_enabled"]._default)
        end)
    end)

    it("registers Item Icons subcategory", function()
        assert.is_not_nil(SB._subcategories["Item Icons"])
    end)
end)
