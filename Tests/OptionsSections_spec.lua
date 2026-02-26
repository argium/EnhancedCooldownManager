-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("Options sections and root assembly", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM", "ECM_CloneValue", "ECM_DeepEquals",
            "Settings", "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer", "MinimalSliderWithSteppersMixin",
            "CreateColor", "StaticPopupDialogs", "StaticPopup_Show", "YES", "NO",
            "UnitClass", "GetSpecialization", "GetSpecializationInfo",
            "Enum",
            "LibStub", "CreateFromMixins", "SettingsListElementInitializer",
            "LibSettingsBuilder_EmbedCanvasMixin",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    it("root Options module creates categories and calls RegisterSettings on sections", function()
        TestHelpers.setupLibStub()
        TestHelpers.setupSettingsStubs()

        local libChunk = TestHelpers.loadChunk(
            { "Libs/LibSettingsBuilder/LibSettingsBuilder.lua" },
            "Unable to load LibSettingsBuilder.lua"
        )
        libChunk()

        local lsmw = LibStub:NewLibrary("LibLSMSettingsWidgets-1.0", 1)
        if lsmw then
            lsmw.GetFontValues = function() return {} end
            lsmw.GetStatusbarValues = function() return {} end
            lsmw.FONT_PICKER_TEMPLATE = "TestFontPickerTemplate"
            lsmw.TEXTURE_PICKER_TEMPLATE = "TestTexturePickerTemplate"
        end

        local registerSettingsCalls = {}
        local dbCallbacks = {}

        _G.ECM = {
            Constants = {
                ADDON_NAME = "ECM",
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            ScheduleLayoutUpdate = function() end,
            SettingsBuilder = nil, -- Will be loaded
        }

        _G.ECM_DeepEquals = function(a, b) return a == b end
        _G.ECM_CloneValue = function(v) return v end

        _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
        _G.GetSpecialization = function() return 1 end
        _G.GetSpecializationInfo = function() return nil, "Arms" end

        local createdModule
        local mod = {
            db = {
                profile = {},
                defaults = { profile = {} },
                RegisterCallback = function(_, owner, eventName, methodName)
                    dbCallbacks[#dbCallbacks + 1] = { eventName = eventName, methodName = methodName }
                end,
            },
            NewModule = function(self, name)
                createdModule = { moduleName = name }
                return createdModule
            end,
        }

        local ns = {
            Addon = mod,
            OptionsSections = {},
        }

        -- Load OptionUtil first (SB depends on it)
        local optionUtilChunk = TestHelpers.loadChunk(
            { "Options/OptionUtil.lua", "../Options/OptionUtil.lua" },
            "Unable to load OptionUtil.lua"
        )
        optionUtilChunk(nil, ns)

        local sbChunk = TestHelpers.loadChunk(
            { "Options/SettingsBuilder.lua", "../Options/SettingsBuilder.lua" },
            "Unable to load SettingsBuilder.lua"
        )
        sbChunk(nil, ns)

        -- Register mock sections
        for _, key in ipairs({ "General", "PowerBar", "ResourceBar", "RuneBar", "BuffBars", "ItemIcons", "Profile", "About" }) do
            ns.OptionsSections[key] = {
                RegisterSettings = function(SB)
                    registerSettingsCalls[#registerSettingsCalls + 1] = key
                end,
            }
        end

        -- Load Options.lua
        local optionsChunk = TestHelpers.loadChunk(
            { "Options/Options.lua", "../Options/Options.lua" },
            "Unable to load Options.lua"
        )
        optionsChunk(nil, ns)

        assert.is_table(createdModule)
        createdModule:OnInitialize()

        -- All 8 sections should have been called, in order
        assert.are.same({
            "About",
            "General",
            "PowerBar",
            "ResourceBar",
            "RuneBar",
            "BuffBars",
            "ItemIcons",
            "Profile",
        }, registerSettingsCalls)

        -- DB callbacks registered
        assert.are.equal(3, #dbCallbacks)

        -- GetRootCategoryID returns something
        assert.is_not_nil(ECM.SettingsBuilder.GetRootCategoryID())
    end)

    it("resource/rune sections register via SB.RegisterSection and have class gating", function()
        TestHelpers.setupLibStub()
        TestHelpers.setupSettingsStubs()

        local libChunk = TestHelpers.loadChunk(
            { "Libs/LibSettingsBuilder/LibSettingsBuilder.lua" },
            "Unable to load LibSettingsBuilder.lua"
        )
        libChunk()

        local lsmw = LibStub:NewLibrary("LibLSMSettingsWidgets-1.0", 1)
        if lsmw then
            lsmw.GetFontValues = function() return {} end
            lsmw.GetStatusbarValues = function() return {} end
            lsmw.FONT_PICKER_TEMPLATE = "TestFontPickerTemplate"
            lsmw.TEXTURE_PICKER_TEMPLATE = "TestTexturePickerTemplate"
        end

        local className = "WARRIOR"
        _G.UnitClass = function() return "Player", className, 1 end
        _G.GetSpecialization = function() return 1 end
        _G.GetSpecializationInfo = function() return nil, "Arms" end

        _G.Enum = {
            PowerType = {
                ArcaneCharges = 1, Chi = 2, ComboPoints = 3,
                Essence = 4, HolyPower = 5, SoulShards = 6,
            },
        }

        _G.ECM = {
            Constants = {
                CLASS = { DEATHKNIGHT = "DEATHKNIGHT" },
                RESOURCEBAR_TYPE_MAELSTROM_WEAPON = "maelstromWeapon",
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            ScheduleLayoutUpdate = function() end,
        }

        local ns = {
            Addon = {
                db = {
                    profile = {
                        resourceBar = { enabled = true, anchorMode = 1, border = { enabled = false, thickness = 1, color = { r = 0, g = 0, b = 0, a = 1 } } },
                        runeBar = { enabled = true, useSpecColor = false, anchorMode = 1, border = { enabled = false, thickness = 1, color = { r = 0, g = 0, b = 0, a = 1 } } },
                    },
                    defaults = {
                        profile = {
                            resourceBar = { enabled = true, anchorMode = 1, border = { enabled = false, thickness = 1, color = { r = 0, g = 0, b = 0, a = 1 } } },
                            runeBar = { enabled = true, useSpecColor = false, anchorMode = 1, border = { enabled = false, thickness = 1, color = { r = 0, g = 0, b = 0, a = 1 } } },
                        },
                    },
                },
            },
            OptionsSections = {},
        }

        -- Load OptionUtil and SettingsBuilder
        local optUtil = TestHelpers.loadChunk({ "Options/OptionUtil.lua" }, "OptionUtil")
        optUtil(nil, ns)

        local sbChunk = TestHelpers.loadChunk({ "Options/SettingsBuilder.lua" }, "SettingsBuilder")
        sbChunk(nil, ns)

        -- Set up root category so subcategories can be created
        ECM.SettingsBuilder.CreateRootCategory("Test")

        -- Load ResourceBarOptions and RuneBarOptions
        local resChunk = TestHelpers.loadChunk({ "Options/ResourceBarOptions.lua" }, "ResourceBarOptions")
        resChunk(nil, ns)
        local runeChunk = TestHelpers.loadChunk({ "Options/RuneBarOptions.lua" }, "RuneBarOptions")
        runeChunk(nil, ns)

        -- Both should have registered themselves
        assert.is_not_nil(ns.OptionsSections.ResourceBar)
        assert.is_not_nil(ns.OptionsSections.RuneBar)
        assert.is_function(ns.OptionsSections.ResourceBar.RegisterSettings)
        assert.is_function(ns.OptionsSections.RuneBar.RegisterSettings)
    end)
end)
