-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ResourceBarOptions getters/setters/defaults", function()
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

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ResourceBarOptions.lua", "ResourceBarOptions")(nil, ns)
            TestHelpers.RegisterSectionSpec(SB, ns.ResourceBarOptions)
            capturedPage = ns.ResourceBarOptions
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

    describe("layout breadcrumb", function()
        it("removes anchorMode from the module page", function()
            assert.is_nil(settings["ECM_resourceBar_anchorMode"])
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
        it("all non-secret resource type color settings exist", function()
            local keys = {
                "souls",
                "devourerNormal",
                "devourerMeta",
                "icicles",
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

            assert.is_nil(settings["ECM_resourceBar_colors_16"])
        end)
        it("souls color getter returns hex string", function()
            local hex = settings["ECM_resourceBar_colors_souls"]:GetValue()
            assert.is_string(hex)
        end)
        it("ComboPoints color setter writes to profile", function()
            settings["ECM_resourceBar_colors_4"]:SetValue("FFFFFF00")
            assert.is_table(profile.resourceBar.colors[4])
        end)
        it("prefixes each resource label with its class icon and color", function()
            local defsByKey = {}
            for _, def in ipairs(capturedPage.rows[9].defs) do
                defsByKey[def.key] = def.name
            end

            assert.are.equal("|A:classicon-demonhunter:14:14|a |cff" .. ns.Constants.CLASS_COLORS.DEMONHUNTER .. ns.L["RESOURCE_SOUL_FRAGMENTS_DH"] .. "|r", defsByKey[ns.Constants.RESOURCEBAR_TYPE_VENGEANCE_SOULS])
            assert.are.equal("|A:classicon-demonhunter:14:14|a |cff" .. ns.Constants.CLASS_COLORS.DEMONHUNTER .. ns.L["RESOURCE_SOUL_FRAGMENTS_DEVOURER"] .. "|r", defsByKey[ns.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL])
            assert.are.equal("|A:classicon-mage:14:14|a |cff" .. ns.Constants.CLASS_COLORS.MAGE .. ns.L["RESOURCE_ICICLES"] .. "|r", defsByKey[ns.Constants.RESOURCEBAR_TYPE_ICICLES])
            assert.are.equal("|A:classicon-monk:14:14|a |cff" .. ns.Constants.CLASS_COLORS.MONK .. ns.L["RESOURCE_CHI"] .. "|r", defsByKey[Enum.PowerType.Chi])
            assert.are.equal("|A:classicon-rogue:14:14|a |cff" .. ns.Constants.CLASS_COLORS.ROGUE .. ns.L["RESOURCE_COMBO_POINTS"] .. "|r", defsByKey[Enum.PowerType.ComboPoints])
            assert.are.equal("|A:classicon-evoker:14:14|a |cff" .. ns.Constants.CLASS_COLORS.EVOKER .. ns.L["RESOURCE_ESSENCE"] .. "|r", defsByKey[Enum.PowerType.Essence])
            assert.are.equal("|A:classicon-paladin:14:14|a |cff" .. ns.Constants.CLASS_COLORS.PALADIN .. ns.L["RESOURCE_HOLY_POWER"] .. "|r", defsByKey[Enum.PowerType.HolyPower])
            assert.are.equal("|A:classicon-shaman:14:14|a |cff" .. ns.Constants.CLASS_COLORS.SHAMAN .. ns.L["RESOURCE_MAELSTROM_WEAPON"] .. "|r", defsByKey[ns.Constants.RESOURCEBAR_TYPE_MAELSTROM_WEAPON])
            assert.are.equal("|A:classicon-warlock:14:14|a |cff" .. ns.Constants.CLASS_COLORS.WARLOCK .. ns.L["RESOURCE_SOUL_SHARDS"] .. "|r", defsByKey[Enum.PowerType.SoulShards])
            assert.is_nil(defsByKey[Enum.PowerType.ArcaneCharges])
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
        it("reuses the icon-prefixed names for capped resource rows", function()
            local defsByKey = {}
            for _, def in ipairs(capturedPage.rows[11].defs) do
                defsByKey[def.key] = def.name
            end

            assert.are.equal(
                "|A:classicon-demonhunter:14:14|a |cff" .. ns.Constants.CLASS_COLORS.DEMONHUNTER .. ns.L["RESOURCE_SOUL_FRAGMENTS_DEVOURER"] .. "|r",
                defsByKey[ns.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL]
            )
            assert.are.equal(
                "|A:classicon-demonhunter:14:14|a |cff" .. ns.Constants.CLASS_COLORS.DEMONHUNTER .. ns.L["RESOURCE_VOID_FRAGMENTS_DEVOURER"] .. "|r",
                defsByKey[ns.Constants.RESOURCEBAR_TYPE_DEVOURER_META]
            )
            assert.are.equal(
                "|A:classicon-mage:14:14|a |cff" .. ns.Constants.CLASS_COLORS.MAGE .. ns.L["RESOURCE_ICICLES"] .. "|r",
                defsByKey[ns.Constants.RESOURCEBAR_TYPE_ICICLES]
            )
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
        local _, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        TestHelpers.LoadChunk("UI/ResourceBarOptions.lua", "ResourceBarOptions")(nil, ns)
        assert.is_true(ns.ResourceBarOptions.disabled())
    end)
end)
