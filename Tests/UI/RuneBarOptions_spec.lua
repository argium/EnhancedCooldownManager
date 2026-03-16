-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("RuneBarOptions getters/setters/defaults", function()
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
        -- RuneBar requires DK class to register most settings
        _G.UnitClass = function() return "Death Knight", "DEATHKNIGHT", 6 end
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/RuneBarOptions.lua", "RuneBarOptions")(nil, ns)
            ns.OptionsSections.RuneBar.RegisterSettings(SB)
        end)
    end)

    describe("enabled", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_runeBar_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_runeBar_enabled"]:SetValue(false)
            assert.is_false(profile.runeBar.enabled)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_runeBar_enabled"]._default)
        end)
    end)

    describe("useSpecColor", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_runeBar_useSpecColor"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_runeBar_useSpecColor"]:SetValue(false)
            assert.is_false(profile.runeBar.useSpecColor)
        end)
    end)

    -- Color settings
    describe("color", function()
        it("getter returns hex string", function()
            local hex = settings["ECM_runeBar_color"]:GetValue()
            assert.is_string(hex)
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_runeBar_color"]:SetValue("FFFF0000")
            assert.is_table(profile.runeBar.color)
        end)
    end)

    describe("colorBlood", function()
        it("getter returns hex string", function()
            assert.is_string(settings["ECM_runeBar_colorBlood"]:GetValue())
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_runeBar_colorBlood"]:SetValue("FF00FF00")
            assert.is_table(profile.runeBar.colorBlood)
        end)
    end)

    describe("colorFrost", function()
        it("getter returns hex string", function()
            assert.is_string(settings["ECM_runeBar_colorFrost"]:GetValue())
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_runeBar_colorFrost"]:SetValue("FF0000FF")
            assert.is_table(profile.runeBar.colorFrost)
        end)
    end)

    describe("colorUnholy", function()
        it("getter returns hex string", function()
            assert.is_string(settings["ECM_runeBar_colorUnholy"]:GetValue())
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_runeBar_colorUnholy"]:SetValue("FF00FF00")
            assert.is_table(profile.runeBar.colorUnholy)
        end)
    end)

    -- Positioning composite
    describe("anchorMode", function()
        it("getter returns profile value", function()
            assert.are.equal("chain", settings["ECM_runeBar_anchorMode"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_runeBar_anchorMode"]:SetValue("free")
            assert.are.equal("free", profile.runeBar.anchorMode)
        end)
    end)

    -- Height override composite
    describe("height", function()
        it("getter applies transform for nil", function()
            profile.runeBar.height = nil
            assert.are.equal(0, settings["ECM_runeBar_height"]:GetValue())
        end)
        it("setter transforms zero to nil", function()
            settings["ECM_runeBar_height"]:SetValue(0)
            assert.is_nil(profile.runeBar.height)
        end)
        it("setter writes non-zero to profile", function()
            settings["ECM_runeBar_height"]:SetValue(18)
            assert.are.equal(18, profile.runeBar.height)
        end)
    end)

    -- Font override composite
    describe("overrideFont", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_runeBar_overrideFont"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_runeBar_overrideFont"]:SetValue(true)
            assert.is_true(profile.runeBar.overrideFont)
        end)
    end)
end)

describe("RuneBarOptions class gating (non-DK)", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("section registers but settings still created for non-DK", function()
        TestHelpers.SetupOptionsGlobals()
        _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
        local profile, defaults = TestHelpers.MakeOptionsProfile()
        local SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        TestHelpers.LoadChunk("UI/RuneBarOptions.lua", "RuneBarOptions")(nil, ns)
        assert.is_not_nil(ns.OptionsSections.RuneBar)
        assert.is_function(ns.OptionsSections.RuneBar.RegisterSettings)
    end)
end)
