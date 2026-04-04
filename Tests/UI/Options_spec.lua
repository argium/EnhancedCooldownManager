-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("OptionUtil", function()
    local originalGlobals
    local ns
    local optionsModule

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
            "LibStub",
            "CreateFromMixins",
            "SettingsListElementInitializer",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()

        ns = {
            Addon = {
                db = {
                    profile = {},
                    defaults = { profile = {} },
                },
                _modules = {},
                NewModule = function(_, name)
                    local module = { moduleName = name }
                    ns.Addon._modules[name] = module
                    return module
                end,
                EnableModule = function() end,
                DisableModule = function() end,
                ConfirmReloadUI = function() end,
            },
            OptionsSections = {},
        }

        TestHelpers.LoadLiveConstants(ns)
        -- Test-specific sentinel values for anchor modes
        ns.Constants.ANCHORMODE_CHAIN = 1
        ns.Constants.ANCHORMODE_DETACHED = 3
        ns.Constants.ANCHORMODE_FREE = 2
        ns.Runtime = ns.Runtime or {}
        ns.Runtime.ScheduleLayoutUpdate = function() end

        local lsmw = TestHelpers.SetupLibSettingsBuilder()
        lsmw.GetFontValues = function()
            return {}
        end

        TestHelpers.LoadChunk("UI/OptionUtil.lua", "Unable to load UI/OptionUtil.lua")(nil, ns)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)
        optionsModule = ns.Addon._modules.Options
    end)

    describe("CreateModuleEnabledHandler", function()
        it("is exposed on ECM.OptionUtil", function()
            assert.is_function(ns.OptionUtil.CreateModuleEnabledHandler)
        end)

        it("returns a function", function()
            local handler = ns.OptionUtil.CreateModuleEnabledHandler("TestModule")
            assert.is_function(handler)
        end)

        it("calls EnableModule when value is true", function()
            local enabledModule
            ns.Addon.EnableModule = function(_, name)
                enabledModule = name
            end

            local handler = ns.OptionUtil.CreateModuleEnabledHandler("PowerBar")
            handler(true)

            assert.are.equal("PowerBar", enabledModule)
        end)

        it("calls DisableModule when value is false (no reload)", function()
            local disabledModule
            ns.Addon.DisableModule = function(_, name)
                disabledModule = name
            end

            local handler = ns.OptionUtil.CreateModuleEnabledHandler("PowerBar")
            handler(false)

            assert.are.equal("PowerBar", disabledModule)
        end)

        it("does not call ConfirmReloadUI for simple modules", function()
            local reloadCalled = false
            ns.Addon.ConfirmReloadUI = function()
                reloadCalled = true
            end

            local handler = ns.OptionUtil.CreateModuleEnabledHandler("PowerBar")
            handler(false)

            assert.is_false(reloadCalled)
        end)

        describe("with requiresReload", function()
            it("calls EnableModule when value is true", function()
                local enabledModule
                ns.Addon.EnableModule = function(_, name)
                    enabledModule = name
                end

                local handler = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", "Reload?")
                handler(true)

                assert.are.equal("BuffBars", enabledModule)
            end)

            it("reverts setting and shows reload confirmation when value is false", function()
                local reloadMessage, revertedValue
                ns.Addon.ConfirmReloadUI = function(_, msg)
                    reloadMessage = msg
                end

                local setting = {
                    SetValueNoCallback = function(_, val)
                        revertedValue = val
                    end,
                }

                local handler = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", "Reload now?")
                handler(false, setting)

                assert.is_true(revertedValue)
                assert.are.equal("Reload now?", reloadMessage)
            end)

            it("falls back to profile state when no silent setting API exists", function()
                ns.Addon.db.profile.buffBars = { enabled = false }
                ns.Addon.ConfirmReloadUI = function() end

                local handler = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", "Reload now?")
                handler(false)

                assert.is_true(ns.Addon.db.profile.buffBars.enabled)
            end)

            it("disables module via reload callback", function()
                local disabledModule, capturedCallback
                ns.Addon.DisableModule = function(_, name)
                    disabledModule = name
                end
                ns.Addon.ConfirmReloadUI = function(_, _, cb)
                    capturedCallback = cb
                end

                local setting = { SetValueNoCallback = function() end }

                local handler = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", "Reload now?")
                handler(false, setting)

                assert.is_function(capturedCallback)
                capturedCallback()
                assert.are.equal("BuffBars", disabledModule)
            end)
        end)
    end)

    describe("CreateBarArgs", function()
        it("is exposed on ECM.OptionUtil", function()
            assert.is_function(ns.OptionUtil.CreateBarArgs)
        end)

        it("returns layout and appearance args with defaults", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled)

            assert.is_nil(args.layoutMovedInfo)

            assert.is_table(args.layoutMovedButton)
            assert.are.equal("button", args.layoutMovedButton.type)
            assert.are.equal(ns.L["LAYOUT_SUBCATEGORY"], args.layoutMovedButton.name)
            assert.are.equal("Open", args.layoutMovedButton.buttonText)
            assert.are.equal(10, args.layoutMovedButton.order)

            assert.is_table(args.appearanceHeader)
            assert.are.equal("header", args.appearanceHeader.type)
            assert.are.equal("Appearance", args.appearanceHeader.name)
            assert.are.equal(20, args.appearanceHeader.order)
        end)

        it("includes showText and border by default", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled)

            assert.is_table(args.showText)
            assert.are.equal("toggle", args.showText.type)
            assert.are.equal("showText", args.showText.path)
            assert.are.equal(21, args.showText.order)

            assert.is_table(args.border)
            assert.are.equal("border", args.border.type)
        end)

        it("shifts height and font after showText when present", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled)

            assert.are.equal(21, args.showText.order)
            assert.are.equal(22, args.heightOverride.order)
            assert.are.equal(23, args.fontOverride.order)
            assert.are.equal(24, args.border.order)
        end)

        it("omits showText when showText=false", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled, { showText = false })

            assert.is_nil(args.showText)
            assert.are.equal(21, args.heightOverride.order)
            assert.are.equal(22, args.fontOverride.order)
        end)

        it("omits border when border=false", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled, { border = false })

            assert.is_nil(args.border)
        end)

        it("omits both showText and border", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled, { showText = false, border = false })

            assert.is_nil(args.showText)
            assert.is_nil(args.border)
            assert.are.equal(21, args.heightOverride.order)
            assert.are.equal(22, args.fontOverride.order)
        end)

        it("respects custom layoutOrder and appearanceOrder", function()
            local disabled = function()
                return false
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled, { layoutOrder = 1, appearanceOrder = 5 })

            assert.are.equal(1, args.layoutMovedButton.order)
            assert.are.equal(5, args.appearanceHeader.order)
            assert.are.equal(6, args.showText.order)
            assert.are.equal(7, args.heightOverride.order)
            assert.are.equal(8, args.fontOverride.order)
            assert.are.equal(9, args.border.order)
        end)

        it("passes isDisabled to all args", function()
            local disabled = function()
                return true
            end
            local args = ns.OptionUtil.CreateBarArgs(disabled)

            assert.are.equal(disabled, args.appearanceHeader.disabled)
            assert.are.equal(disabled, args.showText.disabled)
            assert.are.equal(disabled, args.heightOverride.disabled)
            assert.are.equal(disabled, args.fontOverride.disabled)
            assert.are.equal(disabled, args.border.disabled)
        end)
    end)

    describe("SetNestedValue export", function()
        it("is exposed on ECM.OptionUtil", function()
            assert.is_function(ns.OptionUtil.SetNestedValue)
        end)

        it("sets a simple key", function()
            local tbl = {}
            ns.OptionUtil.SetNestedValue(tbl, "foo", 42)
            assert.are.equal(42, tbl.foo)
        end)

        it("sets a nested key", function()
            local tbl = { a = { b = {} } }
            ns.OptionUtil.SetNestedValue(tbl, "a.b.c", "hello")
            assert.are.equal("hello", tbl.a.b.c)
        end)

        it("creates intermediate tables", function()
            local tbl = {}
            ns.OptionUtil.SetNestedValue(tbl, "x.y.z", true)
            assert.is_true(tbl.x.y.z)
        end)
    end)

    describe("Options:OpenOptions", function()
        local openedCategory
        local generalCategory
        local profileCategory

        before_each(function()
            openedCategory = nil
            generalCategory = nil
            profileCategory = nil

            rawset(Settings, "OpenToCategory", function(categoryID)
                openedCategory = categoryID
            end)

            ns.OptionsSections["About"] = {
                RegisterSettings = function() end,
            }
            ns.OptionsSections["General"] = {
                RegisterSettings = function(SB)
                    generalCategory = SB.CreateSubcategory(ns.L["GENERAL"])
                end,
            }
            ns.OptionsSections["Profile"] = {
                RegisterSettings = function(SB)
                    profileCategory = SB.CreateSubcategory(ns.L["PROFILES"])
                end,
            }

            optionsModule:OnInitialize()
        end)

        it("opens General when no ECM page has been visited yet", function()
            optionsModule:OpenOptions()

            assert.are.equal(generalCategory:GetID(), openedCategory)
        end)

        it("reopens the last visited ECM page", function()
            SettingsPanel:SetCurrentCategory(profileCategory)
            SettingsPanel:DisplayCategory(profileCategory)

            optionsModule:OpenOptions()

            assert.are.equal(profileCategory:GetID(), openedCategory)
        end)

        it("ignores non-ECM pages when remembering the last page", function()
            local otherCategory = {
                GetID = function()
                    return "Other.Settings.Page"
                end,
            }

            SettingsPanel:SetCurrentCategory(profileCategory)
            SettingsPanel:DisplayCategory(profileCategory)
            SettingsPanel:SetCurrentCategory(otherCategory)
            SettingsPanel:DisplayCategory(otherCategory)

            optionsModule:OpenOptions()

            assert.are.equal(profileCategory:GetID(), openedCategory)
        end)
    end)
end)
