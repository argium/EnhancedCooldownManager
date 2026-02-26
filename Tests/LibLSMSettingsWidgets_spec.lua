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

describe("LibLSMSettingsWidgets", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "LibStub",
            "SettingsListElementMixin",
            "LibLSMSettingsWidgets_FontPickerMixin",
            "LibLSMSettingsWidgets_TexturePickerMixin",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.setupLibStub()
        _G.SettingsListElementMixin = {
            OnLoad = function() end,
            Init = function() end,
        }

        local lsm = LibStub:NewLibrary("LibSharedMedia-3.0", 1)
        if lsm then
            lsm.List = function() return {} end
            lsm.Fetch = function() return nil end
        end

        local chunk = TestHelpers.loadChunk(
            { "Libs/LibLSMSettingsWidgets/LibLSMSettingsWidgets.lua" },
            "Unable to load LibLSMSettingsWidgets.lua"
        )
        chunk()
    end)

    local pickerCases = {
        { name = "FontPicker",    global = "LibLSMSettingsWidgets_FontPickerMixin" },
        { name = "TexturePicker", global = "LibLSMSettingsWidgets_TexturePickerMixin" },
    }

    for _, case in ipairs(pickerCases) do
        it(case.name .. " SetEnabled disables dropdown and hides preview", function()
            local dropdownEnabled, dropdownMouse
            local hostEnabled, hostMouse
            local previewShown = true

            local picker = {
                DropDown = {
                    SetEnabled = function(_, enabled) dropdownEnabled = enabled end,
                    EnableMouse = function(_, enabled) dropdownMouse = enabled end,
                },
                DropDownHost = {
                    SetEnabled = function(_, enabled) hostEnabled = enabled end,
                    EnableMouse = function(_, enabled) hostMouse = enabled end,
                },
                Preview = {
                    Show = function() previewShown = true end,
                    Hide = function() previewShown = false end,
                },
            }

            local mixin = _G[case.global]
            mixin.SetEnabled(picker, false)
            assert.is_false(dropdownEnabled)
            assert.is_false(dropdownMouse)
            assert.is_false(hostEnabled)
            assert.is_false(hostMouse)
            assert.is_false(previewShown)

            mixin.SetEnabled(picker, true)
            assert.is_true(dropdownEnabled)
            assert.is_true(dropdownMouse)
            assert.is_true(hostEnabled)
            assert.is_true(hostMouse)
            assert.is_true(previewShown)
        end)
    end
end)
