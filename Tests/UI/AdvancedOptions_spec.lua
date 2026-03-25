-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("AdvancedOptions getters/setters/defaults", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings, advancedCategory, initializers

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
            ns.OptionsSections["Advanced Options"].RegisterSettings(SB)
        end)
        advancedCategory = SB._subcategories[ECM.L["ADVANCED_OPTIONS"]]
        initializers = SB._layouts[advancedCategory]._initializers
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
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_global_showReleasePopupOnUpdate"]:GetValue())
        end)

        it("setter writes to profile", function()
            settings["ECM_global_showReleasePopupOnUpdate"]:SetValue(true)
            assert.is_true(profile.global.showReleasePopupOnUpdate)
        end)

        it("default matches expected", function()
            assert.is_false(settings["ECM_global_showReleasePopupOnUpdate"]._default)
        end)
    end)

    describe("Show What's New button", function()
        it("uses a placeholder label for the button row", function()
            local button = assert(TestHelpers.FindButtonInitializer(initializers, ECM.L["SHOW_WHATS_NEW"]))
            assert.are.equal(" ", button._name)
        end)

        it("forces the popup open through the addon method", function()
            local forced
            ns.Addon.ShowReleasePopup = function(_, force)
                forced = force
            end

            TestHelpers.FindButtonInitializer(initializers, ECM.L["SHOW_WHATS_NEW"])._onClick()

            assert.is_true(forced)
        end)
    end)
end)
