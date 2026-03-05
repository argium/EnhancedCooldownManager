-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ItemIconsOptions getters/setters/defaults", function()
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

        settings = TestHelpers.CollectSettings(function()
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

    describe("showTrinket1", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_itemIcons_showTrinket1"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_itemIcons_showTrinket1"]:SetValue(false)
            assert.is_false(profile.itemIcons.showTrinket1)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_itemIcons_showTrinket1"]._default)
        end)
    end)

    describe("showTrinket2", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_itemIcons_showTrinket2"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_itemIcons_showTrinket2"]:SetValue(false)
            assert.is_false(profile.itemIcons.showTrinket2)
        end)
    end)

    describe("showHealthPotion", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_itemIcons_showHealthPotion"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_itemIcons_showHealthPotion"]:SetValue(false)
            assert.is_false(profile.itemIcons.showHealthPotion)
        end)
    end)

    describe("showCombatPotion", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_itemIcons_showCombatPotion"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_itemIcons_showCombatPotion"]:SetValue(false)
            assert.is_false(profile.itemIcons.showCombatPotion)
        end)
    end)

    describe("showHealthstone", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_itemIcons_showHealthstone"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_itemIcons_showHealthstone"]:SetValue(false)
            assert.is_false(profile.itemIcons.showHealthstone)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_itemIcons_showHealthstone"]._default)
        end)
    end)
end)
