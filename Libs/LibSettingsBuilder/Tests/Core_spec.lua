-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder Core", function()
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

    it("loads the split library through the shared ordered loader", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        assert.is_table(lsb)
        assert.is_function(lsb.PathAdapter)
        assert.is_function(lsb.CreateColorSwatch)
        assert.is_nil(lsb._loadState.open)
    end)

    it("PathAdapter resolves nested values and defaults", function()
        local profile = {
            root = {
                enabled = true,
            },
        }
        local defaults = {
            root = {
                enabled = false,
            },
        }
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local adapter = lsb.PathAdapter({
            getStore = function()
                return profile
            end,
            getDefaults = function()
                return defaults
            end,
        })

        local binding = adapter:resolve("root.enabled")
        assert.are.equal(true, binding.get())
        assert.are.equal(false, binding.default)

        binding.set(false)
        assert.are.equal(false, profile.root.enabled)
    end)
end)
