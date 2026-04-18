local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("Options root assembly", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM_DeepEquals",
            "Settings",
            "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer",
            "MinimalSliderWithSteppersMixin",
            "CreateColor",
            "StaticPopupDialogs",
            "StaticPopup_Show",
            "YES",
            "NO",
            "UnitClass",
            "GetSpecialization",
            "GetSpecializationInfo",
            "Enum",
            "LibStub",
            "CreateFromMixins",
            "SettingsListElementInitializer",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("OnInitialize builds one root page and all declarative sections", function()
        TestHelpers.SetupOptionsGlobals()
        local lsmw = TestHelpers.SetupLibSettingsBuilder()
        lsmw.GetFontValues = function()
            return {}
        end
        lsmw.GetStatusbarValues = function()
            return {}
        end

        local createdModule
        local ns = {
            Runtime = {
                ScheduleLayoutUpdate = function() end,
            },
            ColorUtil = {
                Sparkle = function(text)
                    return text
                end,
            },
        }

        TestHelpers.LoadLiveConstants(ns)
        ns.CloneValue = function(v)
            return v
        end
        ns.Constants.ANCHORMODE_CHAIN = 1
        ns.Constants.ANCHORMODE_FREE = 2
        ns.Constants.ANCHORMODE_DETACHED = 3

        ns.Addon = {
            db = {
                profile = {},
                defaults = { profile = {} },
                RegisterCallback = function() end,
            },
            NewModule = function(_, name)
                createdModule = { moduleName = name }
                return createdModule
            end,
        }

        TestHelpers.LoadChunk("UI/OptionUtil.lua", "OptionUtil")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

        local function placeholderSection(key, name)
            return {
                key = key,
                name = name,
                pages = {
                    {
                        key = "main",
                        rows = {},
                    },
                },
            }
        end

        ns.GeneralOptions = placeholderSection("general", ns.L["GENERAL"])
        ns.LayoutOptions = placeholderSection("layout", ns.L["LAYOUT_SUBCATEGORY"])
        ns.PowerBarOptions = placeholderSection("powerBar", ns.L["POWER_BAR"])
        ns.ResourceBarOptions = placeholderSection("resourceBar", ns.L["RESOURCE_BAR"])
        ns.RuneBarOptions = placeholderSection("runeBar", ns.L["RUNE_BAR"])
        ns.BuffBarsOptions = placeholderSection("buffBars", ns.L["AURA_BARS"])
        ns.ExtraIconsOptions = placeholderSection("extraIcons", ns.L["EXTRA_ICONS"])
        ns.ProfileOptions = placeholderSection("profile", ns.L["PROFILES"])
        ns.AdvancedOptions = placeholderSection("advancedOptions", ns.L["ADVANCED_OPTIONS"])
        ns.SpellColorsPage = {
            CreatePage = function(name)
                return { key = "spellColors", name = name, rows = {} }
            end,
            SetRegisteredPage = function() end,
        }

        assert.is_table(createdModule)
        createdModule:OnInitialize()

        assert.is_table(ns.Settings)
        assert.are.equal(ns.L["ADDON_NAME"], ns.Settings.name)
        assert.is_not_nil(ns.Settings:GetRootPage())

        for _, key in ipairs({
            "general",
            "layout",
            "powerBar",
            "resourceBar",
            "runeBar",
            "buffBars",
            "extraIcons",
            "spellColors",
            "profile",
            "advancedOptions",
        }) do
            assert.is_not_nil(ns.Settings:GetSection(key), "missing registered section: " .. key)
        end
    end)

    it("General and Advanced options export declarative section specs", function()
        TestHelpers.SetupOptionsGlobals()
        local profile, defaults = TestHelpers.MakeOptionsProfile()
        local _, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        TestHelpers.LoadChunk("UI/GeneralOptions.lua", "GeneralOptions")(nil, ns)

        assert.are.equal("general", ns.GeneralOptions.key)
        assert.are.equal(ns.L["GENERAL"], ns.GeneralOptions.name)
        assert.are.equal("global", ns.GeneralOptions.path)
        assert.are.equal(1, #ns.GeneralOptions.pages)
        assert.are.equal(16, #ns.GeneralOptions.pages[1].rows)
        assert.are.equal("header", ns.GeneralOptions.pages[1].rows[1].type)
        assert.are.equal("slider", ns.GeneralOptions.pages[1].rows[16].type)

        assert.are.equal("advancedOptions", ns.AdvancedOptions.key)
        assert.are.equal(ns.L["ADVANCED_OPTIONS"], ns.AdvancedOptions.name)
        assert.are.equal("global", ns.AdvancedOptions.path)
        assert.are.equal(1, #ns.AdvancedOptions.pages)
        assert.are.equal(7, #ns.AdvancedOptions.pages[1].rows)
        assert.are.equal("button", ns.AdvancedOptions.pages[1].rows[5].type)
    end)
end)
