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
end)
