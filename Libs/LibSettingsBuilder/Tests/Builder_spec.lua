-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder Builder", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "LibStub",
            "Settings",
            "CreateFrame",
            "hooksecurefunc",
            "SettingsDropdownControlMixin",
            "SettingsSliderControlMixin",
            "SettingsListElementMixin",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        TestHelpers.LoadLibSettingsBuilder()
    end)

    local function createBuilder(config)
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local profile = {
            general = {
                enabled = true,
                height = nil,
            },
        }
        local defaults = {
            general = {
                enabled = false,
                height = 12,
            },
        }

        return lsb.New({
            name = "Builder Spec",
            store = function()
                return profile
            end,
            defaults = function()
                return defaults
            end,
            defaultsConfirmation = {
                text = "Localized reset %s?",
                button1 = "Localized reset",
                button2 = "Localized don't reset",
            },
            onChanged = function() end,
            page = config and config.page or nil,
            sections = config and config.sections or nil,
        }), profile, defaults
    end

    local function createDefaultsButton()
        return {
            _enabled = true,
            _script = function(self)
                self._nativeResetCalls = (self._nativeResetCalls or 0) + 1
            end,
            GetScript = function(self)
                return self._script
            end,
            IsEnabled = function(self)
                return self._enabled
            end,
            SetEnabled = function(self, enabled)
                self._enabled = enabled
            end,
            SetScript = function(self, _, script)
                self._script = script
            end,
        }
    end

    local function installDefaultsButton(button)
        local currentCategory
        _G.hooksecurefunc = function(tbl, method, hook)
            local original = tbl[method]
            tbl[method] = function(...)
                original(...)
                hook(...)
            end
        end
        rawset(SettingsPanel, "DisplayCategory", function(_, category)
            currentCategory = category
        end)
        rawset(SettingsPanel, "GetCurrentCategory", function()
            return currentCategory
        end)
        rawset(SettingsPanel, "GetSettingsList", function()
            return { Header = { DefaultsButton = button } }
        end)
        rawset(SettingsPanel, "HookScript", function() end)
    end

    local function recordPopupAutoAccept()
        local originalShow = StaticPopup_Show
        local shown
        local text
        _G.StaticPopup_Show = function(name, text1, text2, data)
            shown = name
            text = text1
            originalShow(name, text1, text2, data)
        end
        local function getShown()
            return shown
        end
        local function getText()
            return text
        end
        return getShown, getText
    end

    it("registers root and section pages through LSB.New", function()
        local sb = createBuilder({
            page = {
                key = "about",
                rows = {
                    { type = "info", name = "Version", value = "1.0" },
                },
            },
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "checkbox", path = "general.enabled", name = "Enabled" },
                            },
                        },
                    },
                },
            },
        })

        local rootPage = assert(sb:GetRootPage())
        local generalPage = assert(sb:GetPage("general", "main"))

        assert.are.equal("Builder Spec", rootPage:GetId())
        assert.are.equal("Builder Spec.General", generalPage:GetId())
        assert.are.equal("general", assert(sb:GetSection("general")).key)
        assert.is_true(sb:HasCategory(rootPage._category))
        assert.is_true(sb:HasCategory(generalPage._category))
    end)

    it("binds a hideDefaults page into the lifecycle callbacks", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "profile",
                    name = "Profile",
                    pages = {
                        {
                            key = "main",
                            hideDefaults = true,
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })

        local page = assert(sb:GetPage("profile", "main"))
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local cbs = assert(lsb._pageLifecycleCallbacks[page._category])

        assert.is_true(cbs.hideDefaults)
        assert.is_nil(cbs.onDefault)
    end)

    it("binds custom page defaults into lifecycle callbacks", function()
        local resetCalls = 0
        local defaultEnabled = true
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "native",
                            name = "Native",
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                        {
                            key = "custom",
                            name = "Custom",
                            onDefault = function()
                                resetCalls = resetCalls + 1
                            end,
                            onDefaultEnabled = function()
                                return defaultEnabled
                            end,
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })

        local lsb = LibStub("LibSettingsBuilder-1.0")
        local nativePage = assert(sb:GetPage("general", "native"))
        local customPage = assert(sb:GetPage("general", "custom"))
        local cbs = assert(lsb._pageLifecycleCallbacks[customPage._category])

        assert.is_nil(lsb._pageLifecycleCallbacks[nativePage._category])
        assert.are.equal("Custom", cbs.pageName)
        assert.is_function(cbs.onDefault)
        assert.is_true(cbs.onDefaultEnabled())

        cbs.onDefault()

        assert.are.equal(1, resetCalls)

        defaultEnabled = false

        assert.is_false(cbs.onDefaultEnabled())
    end)

    it("resets current page settings through a custom Defaults confirmation", function()
        local button = createDefaultsButton()
        installDefaultsButton(button)
        local getPopup, getPopupText = recordPopupAutoAccept()

        local sb, profile = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            name = "General Page",
                            rows = {
                                { type = "checkbox", path = "general.enabled", name = "Enabled" },
                            },
                        },
                    },
                },
            },
        })

        local page = assert(sb:GetPage("general", "main"))
        SettingsPanel:DisplayCategory(page._category)
        button:GetScript("OnClick")(button)

        assert.are.equal(0, button._nativeResetCalls or 0)
        assert.are.equal("BS_LibSettingsBuilder_1_0_DefaultsConfirm", getPopup())
        assert.are.equal("Localized reset general page?", getPopupText())
        assert.are.equal("Localized reset", StaticPopupDialogs.BS_LibSettingsBuilder_1_0_DefaultsConfirm.button1)
        assert.are.equal("Localized don't reset", StaticPopupDialogs.BS_LibSettingsBuilder_1_0_DefaultsConfirm.button2)
        assert.is_false(profile.general.enabled)
    end)

    it("uses per-page defaultsConfirmText when provided", function()
        local button = createDefaultsButton()
        installDefaultsButton(button)
        local getPopup, getPopupText = recordPopupAutoAccept()

        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            defaultsConfirmText = "Custom confirm text",
                            onDefault = function() end,
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })

        local page = assert(sb:GetPage("general", "main"))
        SettingsPanel:DisplayCategory(page._category)
        button:GetScript("OnClick")(button)

        assert.are.equal("Custom confirm text", getPopupText())
    end)

    it("runs custom page defaults instead of generic setting resets", function()
        local resetCalls = 0
        local button = createDefaultsButton()
        installDefaultsButton(button)
        recordPopupAutoAccept()

        local sb, profile = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            onDefault = function()
                                resetCalls = resetCalls + 1
                            end,
                            rows = {
                                { type = "checkbox", path = "general.enabled", name = "Enabled" },
                            },
                        },
                    },
                },
            },
        })

        local page = assert(sb:GetPage("general", "main"))
        SettingsPanel:DisplayCategory(page._category)
        button:GetScript("OnClick")(button)

        assert.are.equal(1, resetCalls)
        assert.is_true(profile.general.enabled)
    end)

    it("disables custom page defaults when the page predicate returns false", function()
        local resetCalls = 0
        local popupShown = false
        local button = createDefaultsButton()
        installDefaultsButton(button)
        _G.StaticPopup_Show = function()
            popupShown = true
        end

        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            onDefault = function()
                                resetCalls = resetCalls + 1
                            end,
                            onDefaultEnabled = function()
                                return false
                            end,
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })

        local page = assert(sb:GetPage("general", "main"))
        SettingsPanel:DisplayCategory(page._category)
        button:GetScript("OnClick")(button)

        assert.is_false(button:IsEnabled())
        assert.is_false(popupShown)
        assert.are.equal(0, resetCalls)
    end)

    it("returns nil for missing section-page lookups", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })

        assert.is_nil(sb:GetPage("general"))
        assert.is_nil(sb:GetPage("missing", "main"))
        assert.is_nil(sb:GetPage("general", "missing"))
    end)

    it("uses the section category for an unnamed page in a multi-page section", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "power",
                    name = "Power",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "info", name = "Enabled", value = "Yes" },
                            },
                        },
                        {
                            key = "ticks",
                            name = "Ticks",
                            rows = {
                                { type = "info", name = "Count", value = "0" },
                            },
                        },
                    },
                },
            },
        })

        local mainPage = assert(sb:GetPage("power", "main"))
        local ticksPage = assert(sb:GetPage("power", "ticks"))

        assert.are.equal("Builder Spec.Power", mainPage:GetId())
        assert.are.equal("Builder Spec.Power.Ticks", ticksPage:GetId())
        assert.are.equal(mainPage._category, ticksPage._category._parent)
    end)

    it("registers root-bound composite rows from an empty path", function()
        local sb, profile = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "heightOverride", path = "", disabled = false },
                            },
                        },
                    },
                },
            },
        })

        local settings = TestHelpers.CollectSettings(function()
            TestHelpers.RegisterSectionSpec(sb, {
                key = "generalTwo",
                name = "General Two",
                path = "general",
                pages = {
                    {
                        key = "main",
                        rows = {
                            { type = "heightOverride", path = "", disabled = false },
                        },
                    },
                },
            })
        end)

        assert.is_not_nil(settings["BS_generalTwo_height"] or settings["BS_general_height"])
        assert.is_nil(profile.general.height)
    end)

    it("falls back to a dropdown for fontOverride without a registered font row", function()
        local settings = TestHelpers.CollectSettings(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    {
                                        type = "fontOverride",
                                        path = "",
                                        fontFallback = function()
                                            return "Fallback Font"
                                        end,
                                        fontValues = function()
                                            return {
                                                ["Fallback Font"] = "Fallback Font",
                                                ["Other Font"] = "Other Font",
                                            }
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end)

        local fontSetting = assert(settings["BS_general_font"])
        local fontOptions = fontSetting._optionsGen()

        assert.is_not_nil(settings["BS_general_overrideFont"])
        assert.is_not_nil(settings["BS_general_fontSize"])
        assert.is_function(fontSetting._optionsGen)
        assert.are.equal("Fallback Font", fontSetting:GetValue())
        assert.are.equal("Fallback Font", fontOptions[1].value)
        assert.are.equal("Other Font", fontOptions[2].value)
    end)

    it("uses fontFallback as the default fontOverride dropdown value source", function()
        local settings = TestHelpers.CollectSettings(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    {
                                        type = "fontOverride",
                                        path = "",
                                        fontFallback = function()
                                            return "Fallback Font"
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end)

        local fontSetting = assert(settings["BS_general_font"])
        local fontOptions = fontSetting._optionsGen()

        assert.are.equal("Fallback Font", fontSetting:GetValue())
        assert.are.equal(1, #fontOptions)
        assert.are.equal("Fallback Font", fontOptions[1].value)
        assert.are.equal("Fallback Font", fontOptions[1].label)
    end)

    it("keeps registered font rows for fontOverride when available", function()
        LibStub("LibSettingsBuilder-1.0"):RegisterRowType("font", {
            applyFrame = function() end,
        })

        local settings = TestHelpers.CollectSettings(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    {
                                        type = "fontOverride",
                                        path = "",
                                        fontValues = {
                                            ["Fallback Font"] = "Fallback Font",
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end)

        local fontSetting = assert(settings["BS_general_font"])

        assert.is_not_nil(settings["BS_general_overrideFont"])
        assert.is_not_nil(settings["BS_general_fontSize"])
        assert.is_nil(fontSetting._optionsGen)
    end)

    it("rejects deprecated desc fields at registration time", function()
        local ok, err = pcall(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    { type = "checkbox", path = "general.enabled", name = "Enabled", desc = "Old tooltip" },
                                },
                            },
                        },
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("deprecated field 'desc'", 1, true))
    end)

    it("rejects removed condition fields at registration time", function()
        local ok, err = pcall(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    {
                                        type = "checkbox",
                                        path = "general.enabled",
                                        name = "Enabled",
                                        condition = function()
                                            return true
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("removed field 'condition'", 1, true))
    end)

    it("keeps page handles limited to the v2 public surface", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })
        local page = assert(sb:GetPage("general", "main"))

        assert.is_function(page.GetId)
        assert.is_function(page.Refresh)
        assert.is_nil(page.GetID)
        assert.is_nil(page.RegisterRows)
        assert.is_nil(page.Checkbox)
        assert.is_nil(page.List)
    end)

    it("returns an lsb instance with only the public API on its prototype", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = { { type = "info", name = "Version", value = "1.0" } },
                        },
                    },
                },
            },
        })

        -- Public API accessible via narrow prototype
        assert.is_function(sb.GetSection)
        assert.is_function(sb.GetRootPage)
        assert.is_function(sb.GetPage)
        assert.is_function(sb.HasCategory)

        -- Internal row-builder methods not on the public prototype
        assert.is_nil(sb.Checkbox)
        assert.is_nil(sb.Slider)
        assert.is_nil(sb.BorderGroup)
        assert.is_nil(sb.Control)
        assert.is_nil(sb.EmbedCanvas)

        -- Instance state is raw on the table
        assert.is_table(rawget(sb, "_sections"))
        assert.is_table(rawget(sb, "_layouts"))
    end)

    it("returns plain page handles with methods directly on the table", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = { { type = "info", name = "Version", value = "1.0" } },
                        },
                    },
                },
            },
        })
        local page = assert(sb:GetPage("general", "main"))

        -- Methods are directly on the handle, not via metatable
        assert.is_function(rawget(page, "GetId"))
        assert.is_function(rawget(page, "Refresh"))
        -- _category is kept for HasCategory use
        assert.is_not_nil(rawget(page, "_category"))

        -- Internal page state is not on the handle
        assert.is_nil(page._operations)
        assert.is_nil(page._rowIDs)
        assert.is_nil(page._registered)
        assert.is_nil(page._builder)
        assert.is_nil(page._root)
    end)

    it("registers declarative pageActions rows", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            name = "Main",
                            rows = {
                                {
                                    id = "actions",
                                    type = "pageActions",
                                    name = "Spell Colors",
                                    attachToCategoryHeader = false,
                                    hideTitle = false,
                                    actions = {
                                        {
                                            text = "Reset",
                                            onClick = function() end,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })
        local page = assert(sb:GetPage("general", "main"))
        local initializers = assert(page._category:GetLayout())._initializers
        local initializer = assert(initializers[1])
        local data = initializer:GetData()

        assert.are.equal("pageActions", data._lsbKind)
        assert.are.equal("Spell Colors", data.name)
        assert.is_false(data.attachToCategoryHeader)
        assert.is_false(data.hideTitle)
        assert.are.equal("Reset", data.actions[1].text)
    end)
end)
