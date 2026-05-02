-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarOptions getters/setters/defaults", function()
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
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        ns.PowerBarTickMarksOptions = { key = "tickMarks", name = "Tick Marks", rows = {} }

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/PowerBarOptions.lua", "PowerBarOptions")(nil, ns)
            TestHelpers.RegisterSectionSpec(SB, ns.PowerBarOptions)
            capturedPage = ns.PowerBarOptions.pages[1]
        end)
    end)

    -- Core toggles
    describe("enabled", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_powerBar_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_powerBar_enabled"]:SetValue(false)
            assert.is_false(profile.powerBar.enabled)
        end)
        it("default matches expected", function()
            assert.is_true(settings["ECM_powerBar_enabled"]._default)
        end)
    end)

    describe("showText", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_powerBar_showText"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_powerBar_showText"]:SetValue(false)
            assert.is_false(profile.powerBar.showText)
        end)
    end)

    describe("showManaAsPercent", function()
        it("getter returns profile value", function()
            assert.is_true(settings["ECM_powerBar_showManaAsPercent"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_powerBar_showManaAsPercent"]:SetValue(false)
            assert.is_false(profile.powerBar.showManaAsPercent)
        end)
    end)

    describe("layout breadcrumb", function()
        it("removes anchorMode from the module page", function()
            assert.is_nil(settings["ECM_powerBar_anchorMode"])
        end)
        it("adds an inline layout button row to the page", function()
            assert.are.equal("button", capturedPage.rows[2].type)
            assert.are.equal(ns.L["LAYOUT_SUBCATEGORY"], capturedPage.rows[2].name)
            assert.are.equal(ns.L["LAYOUT_PAGE_MOVED_BUTTON_TEXT"], capturedPage.rows[2].buttonText)
        end)
    end)

    -- Height override composite
    describe("height", function()
        it("getter applies transform for nil", function()
            profile.powerBar.height = nil
            assert.are.equal(0, settings["ECM_powerBar_height"]:GetValue())
        end)
        it("setter transforms zero to nil", function()
            settings["ECM_powerBar_height"]:SetValue(0)
            assert.is_nil(profile.powerBar.height)
        end)
        it("setter writes non-zero to profile", function()
            settings["ECM_powerBar_height"]:SetValue(30)
            assert.are.equal(30, profile.powerBar.height)
        end)
    end)

    -- Border composite
    describe("border.enabled", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_powerBar_border_enabled"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_powerBar_border_enabled"]:SetValue(true)
            assert.is_true(profile.powerBar.border.enabled)
        end)
    end)

    describe("border.thickness", function()
        it("getter returns profile value", function()
            assert.are.equal(4, settings["ECM_powerBar_border_thickness"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_powerBar_border_thickness"]:SetValue(8)
            assert.are.equal(8, profile.powerBar.border.thickness)
        end)
    end)

    describe("border.color", function()
        it("getter returns hex string", function()
            local hex = settings["ECM_powerBar_border_color"]:GetValue()
            assert.is_string(hex)
        end)
        it("setter writes RGBA table to profile", function()
            settings["ECM_powerBar_border_color"]:SetValue("FF0000FF")
            assert.is_table(profile.powerBar.border.color)
        end)
    end)

    -- Font override composite
    describe("overrideFont", function()
        it("getter returns profile value", function()
            assert.is_false(settings["ECM_powerBar_overrideFont"]:GetValue())
        end)
        it("setter writes to profile", function()
            settings["ECM_powerBar_overrideFont"]:SetValue(true)
            assert.is_true(profile.powerBar.overrideFont)
        end)
    end)

    -- Color list (spot check a few power types)
    describe("colors", function()
        it("Mana color getter returns hex string", function()
            local hex = settings["ECM_powerBar_colors_0"]:GetValue()
            assert.is_string(hex)
        end)
        it("Rage color setter writes RGBA to profile", function()
            settings["ECM_powerBar_colors_1"]:SetValue("FFFF0000")
            assert.is_table(profile.powerBar.colors[1])
        end)
        it("all 9 power type color settings exist", function()
            local keys = { 0, 1, 2, 3, 6, 8, 11, 13, 17 }
            for _, key in ipairs(keys) do
                assert.is_not_nil(settings["ECM_powerBar_colors_" .. key],
                    "Missing color setting for power type " .. key)
            end
        end)
    end)

    describe("tick marks menu placement", function()
        it("registers Tick Marks as a subcategory of Power Bar", function()
            local profile2, defaults2 = TestHelpers.MakeOptionsProfile()
            local SB2, ns2 = TestHelpers.SetupOptionsEnv(profile2, defaults2)

            TestHelpers.LoadChunk("UI/PowerBarTickMarksOptions.lua", "PowerBarTickMarksOptions")(nil, ns2)
            TestHelpers.LoadChunk("UI/PowerBarOptions.lua", "PowerBarOptions")(nil, ns2)

            local _, section = TestHelpers.RegisterSectionSpec(SB2, ns2.PowerBarOptions)
            local powerBarCategory = SB2:GetPage(section.key, "main")._category
            local tickMarksCategory = SB2:GetPage(section.key, "tickMarks")._category

            assert.is_not_nil(powerBarCategory)
            assert.is_not_nil(tickMarksCategory)
            assert.are.equal(powerBarCategory, tickMarksCategory._parent)
            assert.are.equal(ns2.L["ADDON_NAME"] .. "." .. ns2.L["POWER_BAR"], powerBarCategory:GetID())
        end)
    end)
end)
