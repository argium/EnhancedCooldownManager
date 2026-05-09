-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("LibLSMSettingsWidgets", function()
    local originalGlobals
    local lsm

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "LibStub",
            "SettingsListElementMixin",
            "LibLSMSettingsWidgets_FontPickerMixin",
            "LibLSMSettingsWidgets_TexturePickerMixin",
            "wipe",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupLibStub()
        _G.wipe = function(tbl)
            for key in pairs(tbl) do
                tbl[key] = nil
            end
        end
        _G.SettingsListElementMixin = {
            OnLoad = function() end,
            Init = function() end,
        }

        lsm = LibStub:NewLibrary("LibSharedMedia-3.0", 1)
        if lsm then
            lsm.callbacks = {}
            lsm.List = function() return {} end
            lsm.Fetch = function() return nil end
            lsm.RegisterCallback = function(_, event, callback)
                lsm.callbacks[event] = callback
            end
        end

        TestHelpers.LoadChunk("Libs/LibLSMSettingsWidgets/LibLSMSettingsWidgets.lua", "Unable to load LibLSMSettingsWidgets.lua")()
    end)

    it("returns sorted font values and fallback statusbar values", function()
        lsm.List = function(_, mediaType)
            if mediaType == "font" then
                return { "Zulu", "Alpha" }
            end
            return {}
        end

        local lib = LibStub("LibLSMSettingsWidgets-1.0")
        assert.are.same({ Alpha = "Alpha", Zulu = "Zulu" }, lib.GetFontValues())
        assert.are.same({ Blizzard = "Blizzard" }, lib.GetStatusbarValues())
    end)

    it("invalidates cached media names when LibSharedMedia registers new media", function()
        local fontNames = { "Alpha" }
        lsm.List = function()
            return fontNames
        end

        local lib = LibStub("LibLSMSettingsWidgets-1.0")
        assert.are.same({ Alpha = "Alpha" }, lib.GetFontValues())

        fontNames = { "Beta" }
        assert.are.same({ Alpha = "Alpha" }, lib.GetFontValues())

        lsm.callbacks.LibSharedMedia_Registered()
        assert.are.same({ Beta = "Beta" }, lib.GetFontValues())
    end)

    it("font dropdown radio selections update the setting and preview", function()
        local selected = "Alpha"
        local previewUpdates = 0
        local radioEntries = {}
        lsm.List = function()
            return { "Beta", "Alpha" }
        end

        local picker = {
            setting = {
                GetValue = function()
                    return selected
                end,
                SetValue = function(_, value)
                    selected = value
                end,
            },
            DropDown = {
                SetupMenu = function(_, callback)
                    callback(nil, {
                        SetScrollMode = function(self, height)
                            self.height = height
                        end,
                        CreateRadio = function(_, label, isChecked, onClick)
                            radioEntries[#radioEntries + 1] = {
                                label = label,
                                isChecked = isChecked,
                                onClick = onClick,
                            }
                        end,
                    })
                end,
            },
            UpdatePreview = function()
                previewUpdates = previewUpdates + 1
            end,
        }

        LibLSMSettingsWidgets_FontPickerMixin.SetupDropdown(picker)

        assert.are.equal("Alpha", radioEntries[1].label)
        assert.is_true(radioEntries[1].isChecked())
        radioEntries[2].onClick()
        assert.are.equal("Beta", selected)
        assert.are.equal(1, previewUpdates)
    end)

    it("SetupDropdown is a no-op until Init provides a setting", function()
        local setupMenuCalled = false
        local picker = {
            DropDown = {
                SetupMenu = function()
                    setupMenuCalled = true
                end,
            },
        }

        LibLSMSettingsWidgets_TexturePickerMixin.SetupDropdown(picker)

        assert.is_false(setupMenuCalled)
    end)

    it("updates font and texture previews from LibSharedMedia fetch results", function()
        local fetched = {
            font = "/fonts/alpha.ttf",
            statusbar = "/textures/bar",
        }
        lsm.Fetch = function(_, mediaType)
            return fetched[mediaType]
        end

        local fontPicker = {
            setting = { GetValue = function() return "Alpha" end },
            DropDown = {
                OverrideText = function(self, text)
                    self.text = text
                end,
            },
            Preview = {
                SetFont = function(self, path, size, flags)
                    self.font = { path, size, flags }
                end,
                SetText = function(self, text)
                    self.text = text
                end,
            },
        }
        LibLSMSettingsWidgets_FontPickerMixin.UpdatePreview(fontPicker)
        assert.are.equal("Alpha", fontPicker.DropDown.text)
        assert.are.same({ "/fonts/alpha.ttf", 14, "" }, fontPicker.Preview.font)
        assert.are.equal("AaBbCcDd 1234", fontPicker.Preview.text)

        local texturePicker = {
            setting = { GetValue = function() return "Bar" end },
            DropDown = {
                OverrideText = function(self, text)
                    self.text = text
                end,
            },
            Preview = {
                SetTexture = function(self, texture)
                    self.texture = texture
                end,
            },
        }
        LibLSMSettingsWidgets_TexturePickerMixin.UpdatePreview(texturePicker)
        assert.are.equal("Bar", texturePicker.DropDown.text)
        assert.are.equal("/textures/bar", texturePicker.Preview.texture)
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

        it(case.name .. " Init bridges initializer.SetEnabled to frame", function()
            local dropdownEnabled, previewShown

            local setting = {
                GetValue = function() return "TestFont" end,
                SetValue = function() end,
            }
            local staleSetting = {
                GetValue = function() return "chain" end,
                SetValue = function() end,
            }

            local initializer = {
                GetData = function() return { name = "Test", setting = setting } end,
                GetSetting = function() return staleSetting end,
            }

            local picker = {
                Text = { SetText = function() end },
                DropDown = {
                    SetupMenu = function() end,
                    OverrideText = function() end,
                    SetEnabled = function(_, enabled) dropdownEnabled = enabled end,
                    EnableMouse = function() end,
                },
                DropDownHost = {
                    SetEnabled = function() end,
                    EnableMouse = function() end,
                },
                Preview = {
                    SetFont = function() end,
                    SetText = function() end,
                    Show = function() previewShown = true end,
                    Hide = function() previewShown = false end,
                },
                SetupDropdown = function() end,
                UpdatePreview = function() end,
            }

            local mixin = _G[case.global]
            picker.SetEnabled = mixin.SetEnabled
            mixin.Init(picker, initializer)

            assert.are.same(setting, picker.setting)

            -- Init should have bridged SetEnabled onto the initializer
            assert.is_function(initializer.SetEnabled)

            -- Calling initializer:SetEnabled propagates to the frame
            initializer:SetEnabled(false)
            assert.is_false(dropdownEnabled)
            assert.is_false(previewShown)

            initializer:SetEnabled(true)
            assert.is_true(dropdownEnabled)
            assert.is_true(previewShown)
        end)
    end
end)
