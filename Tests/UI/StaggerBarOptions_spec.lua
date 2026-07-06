-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

-- Mirrors production ClassUtil.IsBrewmasterMonk so tests drive it via UnitClass/GetSpecialization.
local function installBrewmasterGate(ns)
    ns.ClassUtil.IsBrewmasterMonk = function()
        local _, class = UnitClass("player")
        return class == "MONK" and GetSpecialization() == ns.Constants.MONK_BREWMASTER_SPEC_INDEX
    end
end

describe("StaggerBarOptions getters/setters/defaults", function()
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
        -- StaggerBar is only enabled for the Brewmaster Monk spec.
        _G.UnitClass = function() return "Monk", "MONK", 10 end
        _G.GetSpecialization = function() return 1 end
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)
        installBrewmasterGate(ns)

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/StaggerBarOptions.lua", "StaggerBarOptions")(nil, ns)
            TestHelpers.RegisterSectionSpec(SB, ns.StaggerBarOptions)
            capturedPage = ns.StaggerBarOptions.pages[1]
        end)
    end)

    describe("enabled", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_staggerBar_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_staggerBar_enabled"]:SetValue(false)
            assert.is_false(profile.staggerBar.enabled)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_staggerBar_enabled"]._default)
        end)
    end)

    describe("colorLight", function()
        it("getter returns hex string", function()
            assert.is_string(settings["ECM_staggerBar_colorLight"]:GetValue())
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_staggerBar_colorLight"]:SetValue("FF00FF00")
            assert.is_table(profile.staggerBar.colorLight)
        end)
    end)

    describe("colorModerate", function()
        it("getter returns hex string", function()
            assert.is_string(settings["ECM_staggerBar_colorModerate"]:GetValue())
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_staggerBar_colorModerate"]:SetValue("FFFFFF00")
            assert.is_table(profile.staggerBar.colorModerate)
        end)
    end)

    describe("colorHeavy", function()
        it("getter returns hex string", function()
            assert.is_string(settings["ECM_staggerBar_colorHeavy"]:GetValue())
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_staggerBar_colorHeavy"]:SetValue("FFFF0000")
            assert.is_table(profile.staggerBar.colorHeavy)
        end)
    end)

    describe("brewmaster gating", function()
        it("section is enabled for a Brewmaster Monk", function()
            assert.is_false(ns.StaggerBarOptions.disabled())
        end)
        it("keeps the class-requirement warning hidden when Brewmaster", function()
            local warningRow
            for _, row in ipairs(capturedPage.rows) do
                if row.name == ns.L["BREWMASTER_ONLY_WARNING"] then
                    warningRow = row
                end
            end
            assert.is_not_nil(warningRow)
            assert.is_function(warningRow.hidden)
            assert.is_true(warningRow.hidden())
        end)
    end)
end)

describe("StaggerBarOptions class gating (non-Brewmaster)", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("disables the section and warns for a non-Brewmaster class", function()
        TestHelpers.SetupOptionsGlobals()
        _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
        _G.GetSpecialization = function() return 1 end
        local profile, defaults = TestHelpers.MakeOptionsProfile()
        local _, ns = TestHelpers.SetupOptionsEnv(profile, defaults)
        installBrewmasterGate(ns)

        TestHelpers.LoadChunk("UI/StaggerBarOptions.lua", "StaggerBarOptions")(nil, ns)

        assert.is_true(ns.StaggerBarOptions.disabled())

        local warningRow
        for _, row in ipairs(ns.StaggerBarOptions.pages[1].rows) do
            if row.name == ns.L["BREWMASTER_ONLY_WARNING"] then
                warningRow = row
            end
        end
        assert.is_not_nil(warningRow)
        assert.is_function(warningRow.hidden)
        assert.is_false(warningRow.hidden())
    end)
end)
