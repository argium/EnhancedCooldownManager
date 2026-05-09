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
            local onTextChanged = self.GetScript and self:GetScript("OnTextChanged") or nil
            if onTextChanged then
                onTextChanged(self)
            end
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

    it("evaluates native custom row predicates without requiring SetEnabled", function()
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

        local originalCreateElementInitializer = Settings.CreateElementInitializer
        rawset(Settings, "CreateElementInitializer", function(frameTemplate, data)
            local initializer = originalCreateElementInitializer(frameTemplate, data)
            initializer.SetEnabled = nil
            initializer.EvaluateModifyPredicates = nil
            initializer.modifyPredicates = {}
            initializer.shownPredicates = {}
            initializer._modifyPredicates = nil
            initializer._shownPredicates = nil
            initializer.AddModifyPredicate = function(self, predicate)
                self.modifyPredicates[#self.modifyPredicates + 1] = predicate
            end
            initializer.AddShownPredicate = function(self, predicate)
                self.shownPredicates[#self.shownPredicates + 1] = predicate
            end
            return initializer
        end)

        local enabled = true
        local shown = true
        local modifyCalls = 0
        local shownCalls = 0
        local interop = LibStub("LibSettingsBuilder-1.0")._internal.interop
        local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
            _lsbKind = "nativeCustomRow",
        }, 24, function() end)
        local frame = TestHelpers.makeFrame()

        initializer:AddModifyPredicate(function()
            modifyCalls = modifyCalls + 1
            return enabled
        end)
        initializer:AddShownPredicate(function()
            shownCalls = shownCalls + 1
            return shown
        end)
        frame.GetElementData = function()
            return initializer
        end

        assert.is_nil(initializer.SetEnabled)
        assert.has_no.errors(function()
            initializer:InitFrame(frame)
        end)
        assert.is_true(frame:IsShown())
        assert.are.equal(1, modifyCalls)
        assert.are.equal(1, shownCalls)

        enabled = false
        shown = false

        assert.has_no.errors(function()
            frame:EvaluateState()
        end)
        assert.is_false(frame:IsShown())
        assert.are.equal(2, modifyCalls)
        assert.are.equal(2, shownCalls)
    end)

    it("renders page action buttons from live hidden, enabled, and tooltip callbacks", function()
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

        local clickedAction, clickedFrame
        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Action Rows",
            store = function() return { general = {} } end,
            defaults = function() return { general = {} } end,
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
                                    type = "pageActions",
                                    actions = {
                                        {
                                            text = "Hidden",
                                            hidden = function() return true end,
                                        },
                                        {
                                            text = "Run",
                                            enabled = function() return false end,
                                            tooltip = function() return "Cannot run" end,
                                            onClick = function(action, frame)
                                                clickedAction = action
                                                clickedFrame = frame
                                            end,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })

        local initializer = builder:GetPage("general", "main")._category:GetLayout()._initializers[1]
        local frame = createScriptableFrame()
        initializer:InitFrame(frame)

        local button = assert(frame._lsbHeaderActionButtons[1])
        assert.are.equal("Run", button:GetText())
        assert.is_false(button:IsEnabled())
        assert.is_function(button:GetScript("OnEnter"))
        assert.is_nil(frame._lsbHeaderActionButtons[2])

        button:GetScript("OnClick")(button)

        assert.are.equal(initializer:GetData().actions[2], clickedAction)
        assert.are.equal(frame, clickedFrame)
    end)

    it("renders dynamic info rows without freezing display text or multiline state", function()
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

        local nameText, valueText = "Current", "Ready"
        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Info Rows",
            store = function() return { general = {} } end,
            defaults = function() return { general = {} } end,
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
                                    type = "info",
                                    name = function() return nameText end,
                                    value = function() return valueText end,
                                    multiline = true,
                                },
                            },
                        },
                    },
                },
            },
        })

        local initializer = builder:GetPage("general", "main")._category:GetLayout()._initializers[1]
        local frame = createScriptableFrame()
        initializer:InitFrame(frame)

        assert.are.equal("Current", frame._lsbInfoTitle:GetText())
        assert.are.equal("Ready", frame._lsbInfoValue:GetText())
        assert.is_true(frame._lsbInfoValue.__wordWrap)

        nameText, valueText = "Changed", "Done"
        initializer._lsbRefreshFrame(frame)

        assert.are.equal("Changed", frame._lsbInfoTitle:GetText())
        assert.are.equal("Done", frame._lsbInfoValue:GetText())
    end)

    it("keeps input row preview and text-change callbacks bound to the active setting", function()
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

        local changedText
        local profile = { general = { code = "abc" } }
        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Input Rows",
            store = function() return profile end,
            defaults = function() return { general = { code = "abc" } } end,
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
                                    type = "input",
                                    path = "code",
                                    name = "Code",
                                    resolveText = function(value)
                                        return "preview:" .. value
                                    end,
                                    onTextChanged = function(text)
                                        changedText = text
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        })

        local initializer = builder:GetPage("general", "main")._category:GetLayout()._initializers[1]
        local frame = createScriptableFrame()
        initializer:InitFrame(frame)

        assert.are.equal("abc", frame._lsbInputEditBox:GetText())
        assert.are.equal("preview:abc", frame._lsbInputPreview:GetText())

        frame._lsbInputEditBox:SetText("xyz")

        assert.are.equal("xyz", profile.general.code)
        assert.are.equal("xyz", changedText)
        assert.are.equal("preview:xyz", frame._lsbInputPreview:GetText())
    end)
end)
