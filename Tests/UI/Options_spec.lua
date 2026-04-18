-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("OptionUtil", function()
    local originalGlobals
    local ns
    local optionsModule

    local function getRow(rows, rowType, path)
        for _, row in ipairs(rows) do
            if row.type == rowType and (path == nil or row.path == path) then
                return row
            end
        end
    end

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
        }
        ns.ColorUtil = {
            Sparkle = function(text)
                return text
            end,
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

    describe("About page spec", function()
        it("registers the root About page with ordered rows", function()
            local _, registeredPage = TestHelpers.RegisterRootPageSpec(
                ns.SettingsBuilder,
                ns.AboutPage,
                ns.L["ADDON_NAME"]
            )
            local rows = ns.AboutPage.rows

            assert.is_table(registeredPage)
            assert.are.equal(ns.L["ADDON_NAME"], registeredPage:GetId())
            assert.are.equal(6, #rows)
            assert.are.equal("info", rows[1].type)
            assert.are.equal("info", rows[2].type)
            assert.are.equal("info", rows[3].type)
            assert.are.equal("subheader", rows[4].type)
            assert.are.equal(ns.L["LINKS"], rows[4].name)
            assert.are.equal("button", rows[5].type)
            assert.are.equal("button", rows[6].type)
        end)
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
            handler({}, true)

            assert.are.equal("PowerBar", enabledModule)
        end)

        it("calls DisableModule when value is false (no reload)", function()
            local disabledModule
            ns.Addon.DisableModule = function(_, name)
                disabledModule = name
            end

            local handler = ns.OptionUtil.CreateModuleEnabledHandler("PowerBar")
            handler({}, false)

            assert.are.equal("PowerBar", disabledModule)
        end)

        it("does not call ConfirmReloadUI for simple modules", function()
            local reloadCalled = false
            ns.Addon.ConfirmReloadUI = function()
                reloadCalled = true
            end

            local handler = ns.OptionUtil.CreateModuleEnabledHandler("PowerBar")
            handler({}, false)

            assert.is_false(reloadCalled)
        end)

        describe("with requiresReload", function()
            it("calls EnableModule when value is true", function()
                local enabledModule
                ns.Addon.EnableModule = function(_, name)
                    enabledModule = name
                end

                local handler = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", "Reload?")
                handler({}, true)

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
                handler({ setting = setting }, false)

                assert.is_true(revertedValue)
                assert.are.equal("Reload now?", reloadMessage)
            end)

            it("falls back to profile state when no silent setting API exists", function()
                ns.Addon.db.profile.buffBars = { enabled = false }
                ns.Addon.ConfirmReloadUI = function() end

                local handler = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", "Reload now?")
                handler({}, false)

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
                handler({ setting = setting }, false)

                assert.is_function(capturedCallback)
                capturedCallback()
                assert.are.equal("BuffBars", disabledModule)
            end)
        end)
    end)

    describe("CreateBarRows", function()
        it("is exposed on ECM.OptionUtil", function()
            assert.is_function(ns.OptionUtil.CreateBarRows)
        end)

        it("returns layout and appearance rows with defaults", function()
            local disabled = function()
                return false
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled)

            local layoutMovedButton = getRow(rows, "button")
            local appearanceHeader = getRow(rows, "header")

            assert.is_table(layoutMovedButton)
            assert.are.equal(ns.L["LAYOUT_SUBCATEGORY"], layoutMovedButton.name)
            assert.are.equal(ns.L["LAYOUT_PAGE_MOVED_BUTTON_TEXT"], layoutMovedButton.buttonText)

            assert.is_table(appearanceHeader)
            assert.are.equal("Appearance", appearanceHeader.name)
        end)

        it("includes showText and border by default", function()
            local disabled = function()
                return false
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled)
            local showText = getRow(rows, "checkbox", "showText")
            local border = getRow(rows, "border", "border")

            assert.is_table(showText)
            assert.are.equal("showText", showText.path)

            assert.is_table(border)
        end)

        it("orders showText before height and font when present", function()
            local disabled = function()
                return false
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled)

            assert.are.equal("checkbox", rows[3].type)
            assert.are.equal("heightOverride", rows[4].type)
            assert.are.equal("fontOverride", rows[5].type)
            assert.are.equal("border", rows[6].type)
        end)

        it("omits showText when showText=false", function()
            local disabled = function()
                return false
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled, { showText = false })

            assert.is_nil(getRow(rows, "checkbox", "showText"))
            assert.are.equal("heightOverride", rows[3].type)
            assert.are.equal("fontOverride", rows[4].type)
        end)

        it("omits border when border=false", function()
            local disabled = function()
                return false
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled, { border = false })

            assert.is_nil(getRow(rows, "border", "border"))
        end)

        it("omits both showText and border", function()
            local disabled = function()
                return false
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled, { showText = false, border = false })

            assert.is_nil(getRow(rows, "checkbox", "showText"))
            assert.is_nil(getRow(rows, "border", "border"))
            assert.are.equal("heightOverride", rows[3].type)
            assert.are.equal("fontOverride", rows[4].type)
        end)

        it("passes isDisabled to all rows", function()
            local disabled = function()
                return true
            end
            local rows = ns.OptionUtil.CreateBarRows(disabled)

            assert.are.equal(disabled, rows[2].disabled)
            assert.are.equal(disabled, getRow(rows, "checkbox", "showText").disabled)
            assert.are.equal(disabled, getRow(rows, "heightOverride").disabled)
            assert.are.equal(disabled, getRow(rows, "fontOverride").disabled)
            assert.are.equal(disabled, getRow(rows, "border", "border").disabled)
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

            optionsModule:OnInitialize()
            generalCategory = ns.Settings:GetPage("general", "main")._category
            profileCategory = ns.Settings:GetPage("profile", "main")._category
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
