-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("BuffBarsOptions settings getters/setters/defaults", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings, capturedPage

    local function getRow(rows, rowID)
        for _, row in ipairs(rows or {}) do
            if row.id == rowID then
                return row
            end
        end
        return nil
    end

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
        capturedPage = nil

        ns.SpellColors = {
            NormalizeKey = function() end,
            GetAllColorEntries = function() return {} end,
            GetDefaultColor = function() return { r = 1, g = 1, b = 1, a = 1 } end,
            ClearCurrentSpecColors = function() end,
            GetColorByKey = function() return nil end,
            SetColorByKey = function() end,
            SetDefaultColor = function() end,
        }
        ns.Addon.BuffBars = {
            IsEditLocked = function() return false end,
            IsEnabled = function() return true end,
            Enable = function() end,
            Disable = function() end,
        }
        ns.Addon.ConfirmReloadUI = function(_, _, cb) if cb then cb() end end

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/SpellColorsPage.lua", "SpellColorsPage")(nil, ns)
            TestHelpers.LoadChunk("UI/BuffBarsOptions.lua", "BuffBarsOptions")(nil, ns)
            TestHelpers.RegisterSectionSpec(SB, ns.BuffBarsOptions)
            capturedPage = ns.BuffBarsOptions.pages[1]
        end)

        assert.is_not_nil(capturedPage)
    end)

    describe("enabled", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_buffBars_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            -- Enable → disable triggers reload UI confirmation, so test enable path
            profile.buffBars.enabled = false
            settings["ECM_buffBars_enabled"]:SetValue(true)
            assert.is_true(profile.buffBars.enabled)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_buffBars_enabled"]._default)
        end)
        it("registers the row as a checkbox in the ordered rows array", function()
            assert.is_not_nil(capturedPage)
            assert.are.equal("checkbox", capturedPage.rows[1].type)
            assert.are.equal("enabled", capturedPage.rows[1].id)
        end)
    end)

    -- Positioning composite
    describe("anchorMode", function()
        it("moves off the Aura Bars page", function()
            assert.is_nil(settings["ECM_buffBars_anchorMode"])
        end)
        it("uses the updated labels and help text", function()
            local layoutMovedButton = getRow(capturedPage.rows, "layoutMovedButton")

            assert.is_nil(getRow(capturedPage.rows, "layoutMovedInfo"))
            assert.are.equal(ns.L["LAYOUT_SUBCATEGORY"], layoutMovedButton.name)
            assert.are.equal("button", layoutMovedButton.type)
            assert.is_nil(getRow(capturedPage.rows, "positioning"))
        end)
    end)

    describe("freeGrowDirection", function()
        it("moves off the Aura Bars page", function()
            assert.is_nil(settings["ECM_buffBars_freeGrowDirection"])
            assert.is_nil(getRow(capturedPage.rows, "freeGrowDirection"))
        end)
    end)

    -- Appearance toggles
    describe("showIcon", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_buffBars_showIcon"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_buffBars_showIcon"]:SetValue(true)
            assert.is_true(profile.buffBars.showIcon)
        end)
    end)

    describe("showSpellName", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_buffBars_showSpellName"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_buffBars_showSpellName"]:SetValue(false)
            assert.is_false(profile.buffBars.showSpellName)
        end)
    end)

    describe("showDuration", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_buffBars_showDuration"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_buffBars_showDuration"]:SetValue(false)
            assert.is_false(profile.buffBars.showDuration)
        end)
    end)

    -- Height with transform
    describe("height", function()
        it("getter applies transform for nil", function()
            profile.buffBars.height = nil
            assert.are.equal(0, settings["ECM_buffBars_height"]:GetValue())
        end)
        it("setter transforms zero to nil", function()
            settings["ECM_buffBars_height"]:SetValue(0)
            assert.is_nil(profile.buffBars.height)
        end)
        it("setter writes non-zero to profile", function()
            settings["ECM_buffBars_height"]:SetValue(18)
            assert.are.equal(18, profile.buffBars.height)
        end)
    end)

    -- Vertical spacing with transform
    describe("verticalSpacing", function()
        it("getter returns profile value", function()
            assert.are.equal(0, settings["ECM_buffBars_verticalSpacing"]:GetValue())
        end)
        it("getter applies transform for nil", function()
            profile.buffBars.verticalSpacing = nil
            assert.are.equal(0, settings["ECM_buffBars_verticalSpacing"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_buffBars_verticalSpacing"]:SetValue(5)
            assert.are.equal(5, profile.buffBars.verticalSpacing)
        end)
    end)

    -- Font override composite
    describe("overrideFont", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_buffBars_overrideFont"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_buffBars_overrideFont"]:SetValue(true)
            assert.is_true(profile.buffBars.overrideFont)
        end)
    end)
end)
