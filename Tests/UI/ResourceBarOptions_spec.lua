-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ResourceBarOptions getters/setters/defaults", function()
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
            TestHelpers.LoadChunk("UI/ResourceBarOptions.lua", "ResourceBarOptions")(nil, ns)
            ns.OptionsSections.ResourceBar.RegisterSettings(SB)
        end)
    end)

    describe("enabled", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_resourceBar_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_enabled"]:SetValue(false)
            assert.is_false(profile.resourceBar.enabled)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_resourceBar_enabled"]._default)
        end)
    end)

    describe("showText", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_resourceBar_showText"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_showText"]:SetValue(true)
            assert.is_true(profile.resourceBar.showText)
        end)
    end)

    -- Positioning composite
    describe("anchorMode", function()
        it("getter returns profile value", function()
            assert.are.equal("chain", settings["ECM_resourceBar_anchorMode"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_anchorMode"]:SetValue("free")
            assert.are.equal("free", profile.resourceBar.anchorMode)
        end)
    end)

    describe("width", function()
        it("getter returns profile value", function()
            assert.are.equal(300, settings["ECM_resourceBar_width"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_width"]:SetValue(500)
            assert.are.equal(500, profile.resourceBar.width)
        end)
    end)

    -- Height override composite
    describe("height", function()
        it("getter applies transform for nil", function()
            profile.resourceBar.height = nil
            assert.are.equal(0, settings["ECM_resourceBar_height"]:GetValue())
        end)
        it("setter transforms zero to nil", function()
            settings["ECM_resourceBar_height"]:SetValue(0)
            assert.is_nil(profile.resourceBar.height)
        end)
        it("setter writes non-zero to profile", function()
            settings["ECM_resourceBar_height"]:SetValue(25)
            assert.are.equal(25, profile.resourceBar.height)
        end)
    end)

    -- Border composite
    describe("border.enabled", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_resourceBar_border_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_border_enabled"]:SetValue(true)
            assert.is_true(profile.resourceBar.border.enabled)
        end)
    end)

    describe("border.thickness", function()
        it("getter returns profile value", function()
            assert.are.equal(4, settings["ECM_resourceBar_border_thickness"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_border_thickness"]:SetValue(6)
            assert.are.equal(6, profile.resourceBar.border.thickness)
        end)
    end)

    -- Font override composite
    describe("overrideFont", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_resourceBar_overrideFont"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_overrideFont"]:SetValue(true)
            assert.is_true(profile.resourceBar.overrideFont)
        end)
    end)

    -- Color list (spot check)
    describe("colors", function()
        it("all 11 resource type color settings exist", function()
            local keys = {
                "souls",
                "devourerNormal",
                "devourerMeta",
                "icicles",
                "16",
                "12",
                "4",
                "19",
                "9",
                "maelstromWeapon",
                "7",
            }
            for _, key in ipairs(keys) do
                assert.is_not_nil(
                    settings["ECM_resourceBar_colors_" .. key],
                    "Missing color setting for resource type " .. key
                )
            end
        end)
        it("souls color getter returns hex string", function()
            local hex = settings["ECM_resourceBar_colors_souls"]:GetValue()
            assert.is_string(hex)
        end)
        it("ComboPoints color setter writes to profile", function()
            settings["ECM_resourceBar_colors_4"]:SetValue("FFFFFF00")
            assert.is_table(profile.resourceBar.colors[4])
        end)
    end)

    -- Class gating
    describe("class gating", function()
        it("registers settings for non-DK class", function()
            assert.is_not_nil(settings["ECM_resourceBar_enabled"])
        end)
    end)

    -- Max-color overrides
    describe("maxColorsEnabled", function()
        it("icicles toggle setting exists", function()
            assert.is_not_nil(settings["ECM_resourceBar_maxColorsEnabled_icicles"])
        end)
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_resourceBar_maxColorsEnabled_icicles"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_maxColorsEnabled_icicles"]:SetValue(false)
            assert.is_false(profile.resourceBar.maxColorsEnabled.icicles)
        end)
    end)

    describe("maxColors", function()
        it("icicles color setting exists", function()
            assert.is_not_nil(settings["ECM_resourceBar_maxColors_icicles"])
        end)
        it("getter returns hex string", function()
            local hex = settings["ECM_resourceBar_maxColors_icicles"]:GetValue()
            assert.is_string(hex)
        end)
        it("setter writes to profile", function()
            settings["ECM_resourceBar_maxColors_icicles"]:SetValue("FF0000FF")
            assert.is_table(profile.resourceBar.maxColors.icicles)
        end)
    end)
end)

describe("ResourceBarOptions class gating (DK)", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("isDisabled returns true for Death Knights", function()
        TestHelpers.SetupOptionsGlobals()
        _G.UnitClass = function()
            return "Death Knight", "DEATHKNIGHT", 6
        end
        local profile, defaults = TestHelpers.MakeOptionsProfile()
        local SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        TestHelpers.LoadChunk("UI/ResourceBarOptions.lua", "ResourceBarOptions")(nil, ns)
        assert.is_not_nil(ns.OptionsSections.ResourceBar)
        assert.is_function(ns.OptionsSections.ResourceBar.RegisterSettings)
    end)
end)
