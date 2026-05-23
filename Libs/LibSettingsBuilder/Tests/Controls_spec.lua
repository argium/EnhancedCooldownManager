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
        frame.SetJustifyV = function() end
        frame.SetSize = function(self, width, height)
            self:SetWidth(width)
            self:SetHeight(height)
        end
        frame.SetColorRGB = function(self, r, g, b, a)
            self._color = { r = r, g = g, b = b, a = a or 1 }
        end
        frame.GetColorRGB = function(self)
            local color = self._color or { r = 1, g = 1, b = 1, a = 1 }
            return color.r, color.g, color.b, color.a
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
            "ColorPickerFrame",
            "C_Timer",
            "SettingsPanel",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    local function makeHookableControl()
        local control = createScriptableFrame()
        control._hooks = {}
        control.HookScript = function(self, scriptName, callback)
            self._hooks[scriptName] = self._hooks[scriptName] or {}
            self._hooks[scriptName][#self._hooks[scriptName] + 1] = callback
        end
        control.FireScript = function(self, scriptName)
            local script = self:GetScript(scriptName)
            if script then
                script(self)
            end
            for _, callback in ipairs(self._hooks[scriptName] or {}) do
                callback(self)
            end
        end
        return control
    end

    local function installColorPickerStub()
        local picker = makeHookableControl()
        local hexBox = createScriptableFrame()
        local okayButton = makeHookableControl()
        local cancelButton = makeHookableControl()

        picker._setupCalls = 0
        picker._r, picker._g, picker._b, picker._a = 1, 1, 1, 1
        picker.Content = {
            HexBox = hexBox,
            ColorPicker = {
                SetColorRGB = function(_, r, g, b)
                    picker:SetColorRGB(r, g, b)
                end,
                GetColorRGB = function()
                    return picker:GetColorRGB()
                end,
            },
        }
        picker.Footer = {
            OkayButton = okayButton,
            CancelButton = cancelButton,
        }
        picker.SetupColorPickerAndShow = function(self, config)
            self._setupCalls = self._setupCalls + 1
            self._config = config
            self._r, self._g, self._b, self._a = config.r, config.g, config.b, config.opacity or 1
            self:Show()
        end
        picker.GetColorRGB = function(self)
            return self._r, self._g, self._b
        end
        picker.GetColorAlpha = function(self)
            return self._a
        end
        picker.SetColorRGB = function(self, r, g, b)
            self._r, self._g, self._b = r, g, b
            if self._config and self._config.swatchFunc then
                self._config.swatchFunc()
            end
        end
        picker.SetColorAlpha = function(self, a)
            self._a = a
            if self._config and self._config.opacityFunc then
                self._config.opacityFunc()
            end
        end
        picker.Hide = function(self)
            self.__shown = false
            for _, callback in ipairs(self._hooks.OnHide or {}) do
                callback(self)
            end
        end
        okayButton.Click = function(self)
            self:FireScript("OnClick")
        end
        cancelButton.Click = function(self)
            self:FireScript("OnClick")
        end

        _G.ColorPickerFrame = picker
        return picker
    end

    local function setupColorRow(initialColor)
        TestHelpers._pendingCTimers = {}
        _G.C_Timer = {
            After = function(delay, callback)
                TestHelpers._pendingCTimers[#TestHelpers._pendingCTimers + 1] = { delay = delay, callback = callback }
            end,
        }

        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        local picker = installColorPickerStub()
        _G.hooksecurefunc = function() end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.CreateFrame = function(_, _, _, template)
            local frame = createScriptableFrame()
            if template == "SettingsColorSwatchTemplate" then
                frame.Color = TestHelpers.makeTexture()
            end
            return frame
        end

        TestHelpers.LoadLibSettingsBuilder()

        local profile = { general = { color = initialColor or { r = 1, g = 0, b = 0, a = 1 } } }
        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Color Rows",
            store = function() return profile end,
            defaults = function() return { general = { color = { r = 1, g = 0, b = 0, a = 1 } } } end,
            onChanged = function() end,
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "color", path = "color", name = "Color" },
                            },
                        },
                    },
                },
            },
        })

        local initializer = builder:GetPage("general", "main")._category:GetLayout()._initializers[1]
        local frame = createScriptableFrame()
        initializer:InitFrame(frame)
        return profile, picker, frame
    end

    it("keeps the color picker open on click-away without committing pending color", function()
        local profile, picker, frame = setupColorRow()
        local swatch = frame._lsbColorSwatch

        swatch:GetScript("OnClick")(swatch)
        picker:SetColorRGB(0, 1, 0)
        picker:Hide()

        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, profile.general.color)
        assert.are.equal(1, picker._setupCalls)

        TestHelpers.RunNextTimer()

        assert.are.equal(2, picker._setupCalls)
        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, profile.general.color)
        assert.are.same({ r = 0, g = 1, b = 0, a = 1 }, swatch._color)
    end)

    it("commits color picker pending color only from the okay button", function()
        local profile, picker, frame = setupColorRow()
        local swatch = frame._lsbColorSwatch

        swatch:GetScript("OnClick")(swatch)
        picker:SetColorRGB(0, 0, 1)
        picker:SetColorAlpha(0.5)

        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, profile.general.color)

        picker.Footer.OkayButton:Click()

        assert.are.equal(0, profile.general.color.r)
        assert.are.equal(0, profile.general.color.g)
        assert.are.equal(1, profile.general.color.b)
        assert.is_true(math.abs(profile.general.color.a - 0.5) < 0.01)
    end)

    it("cancels color picker pending color without changing the setting", function()
        local profile, picker, frame = setupColorRow()
        local swatch = frame._lsbColorSwatch

        swatch:GetScript("OnClick")(swatch)
        picker:SetColorRGB(0, 1, 0)

        assert.are.same({ r = 0, g = 1, b = 0, a = 1 }, swatch._color)

        picker.Footer.CancelButton:Click()

        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, profile.general.color)
        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, swatch._color)
    end)

    it("applies six typed or pasted hex chars immediately without enter", function()
        local profile, picker, frame = setupColorRow()
        local swatch = frame._lsbColorSwatch

        swatch:GetScript("OnClick")(swatch)
        picker.Content.HexBox:SetText("00ff80")

        assert.are.equal(0, picker._r)
        assert.are.equal(1, picker._g)
        assert.is_true(math.abs(picker._b - 128 / 255) < 0.001)
        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, profile.general.color)
        assert.is_true(math.abs(swatch._color.b - 128 / 255) < 0.001)
    end)

    it("ignores incomplete or invalid color picker hex text", function()
        local _, picker, frame = setupColorRow()
        local swatch = frame._lsbColorSwatch

        swatch:GetScript("OnClick")(swatch)
        picker.Content.HexBox:SetText("00ff8")
        picker.Content.HexBox:SetText("zzzzzz")

        assert.are.equal(1, picker._r)
        assert.are.equal(0, picker._g)
        assert.are.equal(0, picker._b)
        assert.are.same({ r = 1, g = 0, b = 0, a = 1 }, swatch._color)
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

    it("does not let stale dropdown initializers refresh reused frames", function()
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

        local originalCreateDropdown = Settings.CreateDropdown
        local initializers = {}
        rawset(Settings, "CreateDropdown", function(...)
            local initializer = originalCreateDropdown(...)
            initializers[#initializers + 1] = initializer
            return initializer
        end)

        local profile = { general = { old = "OUTLINE", selected = 1 } }
        local defaults = { general = { old = "OUTLINE", selected = 1 } }
        LibStub("LibSettingsBuilder-1.0").New({
            name = "Dropdown Reuse",
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
                                    id = "oldDropdown",
                                    type = "dropdown",
                                    path = "old",
                                    name = "Old",
                                    values = function()
                                        return { OUTLINE = "Outline" }
                                    end,
                                },
                                {
                                    id = "selectedDropdown",
                                    type = "dropdown",
                                    path = "selected",
                                    name = "Selected",
                                    values = function()
                                        return { [1] = "Potions" }
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        })

        local oldInitializer = initializers[1]
        local selectedInitializer = initializers[2]
        local displayedText
        local menuCallback
        local frame = {
            Control = {
                Dropdown = {
                    OverrideText = function(_, text)
                        displayedText = text
                    end,
                    SetupMenu = function(_, callback)
                        menuCallback = callback
                    end,
                },
            },
            SetValue = function() end,
        }
        local function buildMenuEntries()
            local rootDescription = {
                entries = {},
                CreateRadio = function(self, label, isSelected, setSelected, value)
                    self.entries[#self.entries + 1] = {
                        label = label,
                        isSelected = isSelected,
                        setSelected = setSelected,
                        value = value,
                    }
                end,
                SetScrollMode = function(self, height)
                    self.scrollHeight = height
                end,
            }
            menuCallback(frame.Control.Dropdown, rootDescription)
            return rootDescription
        end

        dropdownHook(frame, oldInitializer)
        assert.are.equal("Outline", displayedText)
        assert.are.equal(frame, oldInitializer._lsbActiveFrame)
        local oldMenu = buildMenuEntries()
        assert.are.equal("Outline", oldMenu.entries[1].label)
        assert.is_nil(oldMenu.scrollHeight)

        dropdownHook(frame, selectedInitializer)
        assert.are.equal("Potions", displayedText)
        assert.is_nil(oldInitializer._lsbActiveFrame)
        assert.are.equal(frame, selectedInitializer._lsbActiveFrame)
        local selectedMenu = buildMenuEntries()
        assert.are.equal("Potions", selectedMenu.entries[1].label)

        oldInitializer._lsbRefreshFrame(frame, oldInitializer)
        assert.are.equal("Potions", displayedText)
    end)

    it("passes registered row settings through initializer data", function()
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
        LibStub("LibSettingsBuilder-1.0"):RegisterRowType("testPicker", {
            applyFrame = function() end,
        })

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
                                    type = "testPicker",
                                    path = "font",
                                    name = "Font",
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

    it("reevaluates dynamic button disabled predicates after handler-backed settings change", function()
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

        local selected = "custom"
        local disabledCalls = 0
        local builder
        local settings = TestHelpers.CollectSettings(function()
            builder = LibStub("LibSettingsBuilder-1.0").New({
                name = "Dynamic Button Disabled",
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
                                        id = "stack",
                                        type = "dropdown",
                                        key = "stack",
                                        name = "Stack",
                                        values = { custom = "Custom", default = "Default" },
                                        get = function() return selected end,
                                        set = function(value) selected = value end,
                                    },
                                    {
                                        type = "button",
                                        name = "Rename",
                                        buttonText = "Rename",
                                        disabled = function()
                                            disabledCalls = disabledCalls + 1
                                            return selected == "default"
                                        end,
                                        onClick = function() end,
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end)

        local initializers = builder:GetPage("general", "main")._category:GetLayout()._initializers
        local dropdownSetting
        for _, setting in pairs(settings) do
            dropdownSetting = setting
        end
        local buttonInitializer = TestHelpers.FindButtonInitializer(initializers, "Rename")

        assert.is_true(buttonInitializer._enabled)
        assert.are.equal(1, disabledCalls)

        dropdownSetting:SetValue("default")

        assert.is_false(buttonInitializer._enabled)
        assert.are.equal(2, disabledCalls)
    end)

    it("applies button disabled state to the active button frame", function()
        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.hooksecurefunc = function() end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.CreateFrame = function()
            return createScriptableFrame()
        end

        local originalButtonInitializer = _G.CreateSettingsButtonInitializer
        _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
            local initializer = originalButtonInitializer(name, buttonText, onClick, tooltip)
            initializer.InitFrame = function(_, frame)
                frame.Button = createScriptableFrame()
            end
            return initializer
        end

        TestHelpers.LoadLibSettingsBuilder()

        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Button Visuals",
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
                                    type = "button",
                                    name = "Rename",
                                    buttonText = "Rename",
                                    disabled = function() return false end,
                                    onClick = function() end,
                                },
                            },
                        },
                    },
                },
            },
        })

        local initializer = TestHelpers.FindButtonInitializer(
            builder:GetPage("general", "main")._category:GetLayout()._initializers,
            "Rename"
        )
        local frame = createScriptableFrame()
        initializer:InitFrame(frame)

        assert.are.equal(1, frame:GetAlpha())
        assert.is_true(frame.Button:IsEnabled())
        assert.is_true(frame.Button:IsMouseEnabled())

        initializer:SetEnabled(false)

        assert.are.equal(0.5, frame:GetAlpha())
        assert.is_false(frame.Button:IsEnabled())
        assert.is_false(frame.Button:IsMouseEnabled())
    end)

    it("reapplies button disabled visuals after page refresh", function()
        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.hooksecurefunc = function() end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.CreateFrame = function()
            return createScriptableFrame()
        end

        local originalButtonInitializer = _G.CreateSettingsButtonInitializer
        _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
            local initializer = originalButtonInitializer(name, buttonText, onClick, tooltip)
            initializer.InitFrame = function(_, frame)
                frame.Button = createScriptableFrame()
            end
            return initializer
        end

        TestHelpers.LoadLibSettingsBuilder()

        local disabled = false
        local builder = LibStub("LibSettingsBuilder-1.0").New({
            name = "Button Refresh Visuals",
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
                                    type = "button",
                                    name = "Rename",
                                    buttonText = "Rename",
                                    disabled = function() return disabled end,
                                    onClick = function() end,
                                },
                            },
                        },
                    },
                },
            },
        })

        local page = builder:GetPage("general", "main")
        local initializer = TestHelpers.FindButtonInitializer(page._category:GetLayout()._initializers, "Rename")
        local frame = createScriptableFrame()
        initializer:InitFrame(frame)
        frame.EvaluateState = function(self)
            self:SetAlpha(1)
            self.Button:SetEnabled(false)
        end
        _G.SettingsPanel = {
            IsShown = function() return true end,
            GetCurrentCategory = function() return page._category end,
            GetSettingsList = function()
                return {
                    ScrollBox = {
                        ForEachFrame = function(_, callback)
                            callback(frame)
                        end,
                    },
                }
            end,
        }

        disabled = true
        page:Refresh()

        assert.are.equal(0.5, frame:GetAlpha())
        assert.is_false(frame.Button:IsEnabled())
        assert.is_false(frame.Button:IsMouseEnabled())
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
