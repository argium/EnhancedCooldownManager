-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("LayoutOptions getters/setters/defaults", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings, capturedPage

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()
        _G.UnitClass = function()
            return "Death Knight", "DEATHKNIGHT", 6
        end

        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        local originalRegisterPage = SB.RegisterPage
        SB.RegisterPage = function(page)
            capturedPage = page
            return originalRegisterPage(page)
        end

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/LayoutOptions.lua", "LayoutOptions")(nil, ns)
            ns.OptionsSections.Layout.RegisterSettings(SB)
        end)
    end)

    it("registers the explainer and overview rows", function()
        assert.is_table(capturedPage.rows)
        assert.are.equal("canvas", capturedPage.rows[1].type)
    end)

    it("registers page-level onShow and onHide callbacks", function()
        assert.is_function(capturedPage.onShow)
        assert.is_function(capturedPage.onHide)
    end)

    it("updates attached stack settings", function()
        settings["ECM_global_offsetY"]:SetValue(8)
        settings["ECM_global_moduleSpacing"]:SetValue(4)
        settings["ECM_global_moduleGrowDirection"]:SetValue("up")

        assert.are.equal(8, profile.global.offsetY)
        assert.are.equal(4, profile.global.moduleSpacing)
        assert.are.equal("up", profile.global.moduleGrowDirection)
    end)

    it("updates detached stack settings", function()
        settings["ECM_global_detachedBarWidth"]:SetValue(420)
        settings["ECM_global_detachedModuleSpacing"]:SetValue(3)
        settings["ECM_global_detachedGrowDirection"]:SetValue("up")

        assert.are.equal(420, profile.global.detachedBarWidth)
        assert.are.equal(3, profile.global.detachedModuleSpacing)
        assert.are.equal("up", profile.global.detachedGrowDirection)
    end)

    it("updates module anchor modes from the shared page", function()
        settings["ECM_powerBar_anchorMode"]:SetValue("detached")
        settings["ECM_resourceBar_anchorMode"]:SetValue("free")
        settings["ECM_runeBar_anchorMode"]:SetValue("detached")
        settings["ECM_buffBars_anchorMode"]:SetValue("free")

        assert.are.equal("detached", profile.powerBar.anchorMode)
        assert.are.equal("free", profile.resourceBar.anchorMode)
        assert.are.equal("detached", profile.runeBar.anchorMode)
        assert.are.equal("free", profile.buffBars.anchorMode)
    end)

    it("does not register aura-bar free grow direction", function()
        assert.is_nil(settings["ECM_buffBars_freeGrowDirection"])
        assert.is_nil(settings["ECM_global_freeGrowDirection"])
    end)

    it("registers shared attached-stack settings only once when General is also loaded", function()
        local counts = {}
        local originalSettings = Settings
        local proxiedSettings = {}

        for key, value in pairs(originalSettings) do
            proxiedSettings[key] = value
        end

        proxiedSettings.RegisterProxySetting = function(cat, variable, varType, name, default, getter, setter)
            counts[variable] = (counts[variable] or 0) + 1
            return originalSettings.RegisterProxySetting(cat, variable, varType, name, default, getter, setter)
        end
        _G.Settings = proxiedSettings

        TestHelpers.LoadChunk("UI/GeneralOptions.lua", "GeneralOptions")(nil, ns)
        ns.OptionsSections.General.RegisterSettings(SB)
        ns.OptionsSections.Layout.RegisterSettings(SB)

        _G.Settings = originalSettings

        assert.are.equal(1, counts["ECM_global_offsetY"])
        assert.are.equal(1, counts["ECM_global_moduleSpacing"])
        assert.are.equal(1, counts["ECM_global_moduleGrowDirection"])
    end)
end)
