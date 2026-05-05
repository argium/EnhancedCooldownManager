-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("AdvancedOptions getters/setters/defaults", function()
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
            TestHelpers.LoadChunk("UI/AdvancedOptions.lua", "AdvancedOptions")(nil, ns)
            TestHelpers.RegisterSectionSpec(SB, ns.AdvancedOptions)
        end)
    end)

    describe("debug", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_global_debug"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_global_debug"]:SetValue(true)
            assert.is_true(profile.global.debug)
        end)
        it("default matches expected", function()
            assert.is_false(settings["ECM_global_debug"]._default)
        end)
    end)

    describe("errorLogging", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_global_errorLogging"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_global_errorLogging"]:SetValue(false)
            assert.is_false(profile.global.errorLogging)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_global_errorLogging"]._default)
        end)
    end)

    describe("updateFrequency", function()
        it("getter returns profile value", function()
            assert.are.equal(0.04, settings["ECM_global_updateFrequency"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_global_updateFrequency"]:SetValue(0.5)
            assert.are.equal(0.5, profile.global.updateFrequency)
        end)
        it("default matches expected", function()
            assert.are.equal(0.04, settings["ECM_global_updateFrequency"]._default)
        end)
    end)

    describe("showReleasePopupOnUpdate", function()
        it("does not register a show on update toggle", function()
            assert.is_nil(settings["ECM_global_showReleasePopupOnUpdate"])
        end)
    end)

    it("does not register the About page What's New button", function()
        assert.is_nil(settings["ECM_global_showReleasePopupOnUpdate"])
    end)
end)
