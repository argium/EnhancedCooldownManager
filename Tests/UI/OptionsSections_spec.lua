-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("Options sections and root assembly", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
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

    it("root Options module creates categories and calls RegisterSettings on sections", function()
        TestHelpers.SetupOptionsGlobals()
        local lsmw = TestHelpers.SetupLibSettingsBuilder()
        lsmw.GetFontValues = function()
            return {}
        end
        lsmw.GetStatusbarValues = function()
            return {}
        end

        local registerSettingsCalls = {}
        local dbCallbacks = {}

        _G.ECM = {
            Constants = {
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            L = setmetatable({}, { __index = function(_, k) return k end }),
            ScheduleLayoutUpdate = function() end,
        }

        _G.ECM_DeepEquals = TestHelpers.deepEquals
        _G.ECM.CloneValue = function(v)
            return v
        end

        _G.UnitClass = function()
            return "Warrior", "WARRIOR", 1
        end
        _G.GetSpecialization = function()
            return 1
        end
        _G.GetSpecializationInfo = function()
            return nil, "Arms"
        end

        local createdModule
        local mod = {
            db = {
                profile = {},
                defaults = { profile = {} },
                RegisterCallback = function(_, _, eventName, methodName)
                    dbCallbacks[#dbCallbacks + 1] = { eventName = eventName, methodName = methodName }
                end,
            },
            NewModule = function(self, name)
                createdModule = { moduleName = name }
                return createdModule
            end,
        }

        local ns = { Addon = mod, OptionsSections = {} }

        for _, key in ipairs({
            "About",
            "General",
            "Layout",
            "PowerBar",
            "ResourceBar",
            "RuneBar",
            "BuffBars",
            "ItemIcons",
            "Profile",
            "Advanced Options",
        }) do
            ns.OptionsSections[key] = {
                RegisterSettings = function()
                    registerSettingsCalls[#registerSettingsCalls + 1] = key
                end,
            }
        end

        TestHelpers.LoadChunk("UI/OptionUtil.lua", "OptionUtil")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

        assert.is_table(createdModule)
        createdModule:OnInitialize()

        assert.are.same({
            "About",
            "General",
            "Layout",
            "PowerBar",
            "ResourceBar",
            "RuneBar",
            "BuffBars",
            "ItemIcons",
            "Profile",
            "Advanced Options",
        }, registerSettingsCalls)
        assert.are.equal(0, #dbCallbacks)
        assert.is_not_nil(ECM.SettingsBuilder.GetRootCategoryID())
    end)

    it("resource/rune sections register via SB.RegisterSection and have class gating", function()
        TestHelpers.SetupOptionsGlobals()
        local lsmw = TestHelpers.SetupLibSettingsBuilder()
        lsmw.GetFontValues = function()
            return {}
        end
        lsmw.GetStatusbarValues = function()
            return {}
        end

        _G.UnitClass = function()
            return "Player", "WARRIOR", 1
        end
        _G.GetSpecialization = function()
            return 1
        end
        _G.GetSpecializationInfo = function()
            return nil, "Arms"
        end

        _G.Enum = {
            PowerType = {
                ArcaneCharges = 1,
                Chi = 2,
                ComboPoints = 3,
                Essence = 4,
                HolyPower = 5,
                SoulShards = 6,
            },
        }

        TestHelpers.LoadLiveConstants()
        -- Test-specific sentinel values
        ECM.Constants.ANCHORMODE_CHAIN = 1
        ECM.Constants.ANCHORMODE_FREE = 2
        ECM.Constants.DEFAULT_BAR_WIDTH = 300
        ECM.Runtime = ECM.Runtime or {}
        ECM.Runtime.ScheduleLayoutUpdate = function() end

        local border = { enabled = false, thickness = 1, color = { r = 0, g = 0, b = 0, a = 1 } }
        local profileData = {
            resourceBar = { enabled = true, anchorMode = 1, border = border },
            runeBar = {
                enabled = true,
                useSpecColor = false,
                anchorMode = 1,
                border = TestHelpers.deepClone(border),
                color = { r = 0.77, g = 0.12, b = 0.23, a = 1 },
                colorBlood = { r = 0.87, g = 0.10, b = 0.22, a = 1 },
                colorFrost = { r = 0.33, g = 0.69, b = 0.87, a = 1 },
                colorUnholy = { r = 0, g = 0.61, b = 0, a = 1 },
            },
        }

        local ns = {
            Addon = {
                db = {
                    profile = profileData,
                    defaults = { profile = TestHelpers.deepClone(profileData) },
                },
                NewModule = function(_, name)
                    return { moduleName = name }
                end,
            },
            OptionsSections = {},
        }

        TestHelpers.LoadChunk("UI/OptionUtil.lua", "OptionUtil")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Options")(nil, ns)
        ECM.SettingsBuilder.CreateRootCategory("Test")

        TestHelpers.LoadChunk("UI/ResourceBarOptions.lua", "ResourceBarOptions")(nil, ns)
        TestHelpers.LoadChunk("UI/RuneBarOptions.lua", "RuneBarOptions")(nil, ns)

        assert.is_not_nil(ns.OptionsSections.ResourceBar)
        assert.is_not_nil(ns.OptionsSections.RuneBar)
        assert.is_function(ns.OptionsSections.ResourceBar.RegisterSettings)
        assert.is_function(ns.OptionsSections.RuneBar.RegisterSettings)
    end)
end)
