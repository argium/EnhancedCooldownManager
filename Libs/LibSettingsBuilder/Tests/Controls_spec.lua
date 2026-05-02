-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder Controls", function()
    local originalGlobals

    local function createScriptableFrame()
        local frame = TestHelpers.makeFrame()
        frame._text = ""
        frame._focused = false
        frame.RegisterForClicks = function(self, ...)
            self._registeredClicks = { ... }
        end
        frame.SetAutoFocus = function() end
        frame.SetNumeric = function() end
        frame.SetJustifyH = function() end
        frame.SetSize = function(self, width, height)
            self:SetWidth(width)
            self:SetHeight(height)
        end
        frame.SetText = function(self, text)
            self._text = text
        end
        frame.GetText = function(self)
            return self._text
        end
        frame.SetFocus = function(self)
            self._focused = true
        end
        frame.ClearFocus = function(self)
            self._focused = false
        end
        frame.HighlightText = function(self)
            self._highlighted = true
        end
        return frame
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "LibStub",
            "Settings",
            "CreateFrame",
            "hooksecurefunc",
            "SettingsDropdownControlMixin",
            "SettingsSliderControlMixin",
            "SettingsListElementMixin",
            "MinimalSliderWithSteppersMixin",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("installs dropdown and slider hooks when the mixins are available before load", function()
        local hooks = {}

        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.hooksecurefunc = function(target, method, fn)
            hooks[target] = hooks[target] or {}
            hooks[target][method] = fn
        end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.CreateFrame = function()
            return createScriptableFrame()
        end

        TestHelpers.LoadLibSettingsBuilder()

        assert.is_function(hooks[_G.SettingsDropdownControlMixin].Init)
        assert.is_function(hooks[_G.SettingsSliderControlMixin].Init)
    end)

    it("refreshes standard dropdown text through the label map after Blizzard init", function()
        local dropdownHook

        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.hooksecurefunc = function(target, method, fn)
            if target == _G.SettingsDropdownControlMixin and method == "Init" then
                dropdownHook = fn
            end
        end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.CreateFrame = function()
            return createScriptableFrame()
        end

        TestHelpers.LoadLibSettingsBuilder()

        local profile = { general = { mode = "chain" } }
        local defaults = { general = { mode = "chain" } }
        local originalCreateDropdown = Settings.CreateDropdown
        local initializer
        rawset(Settings, "CreateDropdown", function(...)
            initializer = originalCreateDropdown(...)
            return initializer
        end)

        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Dropdown Labels",
            store = function()
                return profile
            end,
            defaults = function()
                return defaults
            end,
            onChanged = function() end,
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                {
                                    type = "dropdown",
                                    path = "mode",
                                    name = "Mode",
                                    values = {
                                        chain = "Attached",
                                        detached = "Detached",
                                        free = "Free",
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })

        assert.is_table(builder:GetPage("general", "main"))
        initializer.GetSetting = function()
            return {
                GetValue = function()
                    return "OUTLINE"
                end,
            }
        end
        local displayedText, originalValue
        local frame = {
            Control = {
                Dropdown = {
                    OverrideText = function(_, text)
                        displayedText = text
                    end,
                },
            },
            SetValue = function(_, value)
                originalValue = value
            end,
        }

        dropdownHook(frame, initializer)

        assert.are.equal("Attached", displayedText)

        frame:SetValue("free")

        assert.are.equal("free", originalValue)
        assert.are.equal("Free", displayedText)
    end)

    it("passes custom row settings through initializer data", function()
        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.hooksecurefunc = function() end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.CreateFrame = function()
            return createScriptableFrame()
        end

        TestHelpers.LoadLibSettingsBuilder()

        local profile = { general = { font = "Expressway" } }
        local defaults = { general = { font = "Expressway" } }
        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Custom Setting Data",
            store = function()
                return profile
            end,
            defaults = function()
                return defaults
            end,
            onChanged = function() end,
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                {
                                    type = "custom",
                                    path = "font",
                                    name = "Font",
                                    template = "TestFontPickerTemplate",
                                },
                            },
                        },
                    },
                },
            },
        })

        local initializer = builder:GetPage("general", "main")._category:GetLayout()._initializers[1]
        local data = initializer:GetData()

        assert.is_table(data.setting)
        assert.are.equal("Expressway", data.setting:GetValue())
    end)
end)
