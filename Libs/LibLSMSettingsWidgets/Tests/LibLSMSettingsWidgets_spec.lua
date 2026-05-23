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

    local function makeSetting(value)
        return {
            GetValue = function()
                return value
            end,
            SetValue = function(_, nextValue)
                value = nextValue
            end,
        }
    end

    local function makeDropdownHost()
        local host = TestHelpers.makeFrame()
        host.DecrementButton = TestHelpers.makeFrame()
        host.IncrementButton = TestHelpers.makeFrame()
        host.Dropdown = TestHelpers.makeFrame()
        host.Dropdown.SetupMenu = function(self, callback)
            self.__menuCallback = callback
        end
        host.Dropdown.OverrideText = function(self, text)
            self.__overrideText = text
        end
        return host
    end

    local function makePickerFrame()
        local frame = TestHelpers.makeFrame()
        frame.Text = frame:CreateFontString()
        return frame
    end

    local function buildMenu(dropdown)
        local menu = { entries = {} }
        function menu:SetScrollMode(height)
            self.height = height
        end
        function menu:CreateRadio(label, isChecked, onClick)
            self.entries[#self.entries + 1] = {
                label = label,
                isChecked = isChecked,
                onClick = onClick,
            }
        end
        dropdown.__menuCallback(nil, menu)
        return menu
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "CreateFrame",
            "GameFontHighlight",
            "LibStub",
            "wipe",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupLibStub()
        _G.GameFontHighlight = {}
        _G.wipe = function(tbl)
            for key in pairs(tbl) do
                tbl[key] = nil
            end
        end
        _G.CreateFrame = function()
            return makeDropdownHost()
        end

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

    it("applies a font picker row and updates the setting from menu selection", function()
        lsm.List = function()
            return { "Beta", "Alpha" }
        end
        lsm.Fetch = function(_, mediaType, name)
            return mediaType == "font" and "/fonts/" .. name .. ".ttf" or nil
        end

        local lib = LibStub("LibLSMSettingsWidgets-1.0")
        local setting = makeSetting("Alpha")
        local frame = makePickerFrame()
        local initializer = {}

        lib.ApplyFontPickerRow(frame, { name = "Font", setting = setting }, initializer)

        local picker = frame._lsmwPicker
        assert.are.equal("Font", frame.Text:GetText())
        assert.are.equal("Alpha", picker.dropdown.__overrideText)
        assert.are.same({ "/fonts/Alpha.ttf", 14, "" }, { picker.preview:GetFont() })
        assert.are.equal("AaBbCcDd 1234", picker.preview:GetText())

        local menu = buildMenu(picker.dropdown)
        assert.are.equal(200, menu.height)
        assert.are.equal("Alpha", menu.entries[1].label)
        assert.is_true(menu.entries[1].isChecked())
        menu.entries[2].onClick()
        assert.are.equal("Beta", setting:GetValue())
        assert.are.equal("Beta", picker.dropdown.__overrideText)
    end)

    it("rebinds a recycled row from font to texture and reset hides picker children", function()
        lsm.Fetch = function(_, mediaType, name)
            if mediaType == "font" then
                return "/fonts/" .. name .. ".ttf"
            end
            return "/textures/" .. name
        end

        local lib = LibStub("LibLSMSettingsWidgets-1.0")
        local frame = makePickerFrame()
        local initializer = {}

        lib.ApplyFontPickerRow(frame, { name = "Font", setting = makeSetting("Alpha") }, initializer)
        local fontPreview = frame._lsmwPicker.fontPreview
        assert.is_true(fontPreview:IsShown())

        lib.ApplyTexturePickerRow(frame, { name = "Texture", setting = makeSetting("Smooth") }, initializer)
        local picker = frame._lsmwPicker
        assert.is_false(fontPreview:IsShown())
        assert.are.equal("/textures/Smooth", picker.texturePreview:GetTexture())
        assert.are.equal("Texture", frame.Text:GetText())

        lib.ResetPickerRow(frame)
        assert.is_false(picker.host:IsShown())
        assert.is_false(picker.texturePreview:IsShown())
    end)

    it("bridges initializer enabled state to the active picker frame", function()
        local lib = LibStub("LibLSMSettingsWidgets-1.0")
        local frame = makePickerFrame()
        local initializer = {}

        lib.ApplyTexturePickerRow(frame, { name = "Texture", setting = makeSetting("Smooth") }, initializer)
        initializer:SetEnabled(false)

        local picker = frame._lsmwPicker
        assert.is_false(picker.dropdown:IsEnabled())
        assert.is_false(picker.dropdown:IsMouseEnabled())
        assert.is_false(picker.host:IsEnabled())
        assert.is_false(picker.host:IsMouseEnabled())
        assert.is_false(picker.preview:IsShown())
    end)

    it("ignores stale initializer enabled updates after a picker frame is recycled", function()
        local lib = LibStub("LibLSMSettingsWidgets-1.0")
        local frame = makePickerFrame()
        local oldInitializer = {}
        local newInitializer = {}

        lib.ApplyTexturePickerRow(frame, { name = "Old Texture", setting = makeSetting("Smooth") }, oldInitializer)
        frame._lsbInitializer = oldInitializer
        oldInitializer:SetEnabled(false)

        lib.ApplyTexturePickerRow(frame, { name = "New Texture", setting = makeSetting("Blizzard") }, newInitializer)
        frame._lsbInitializer = newInitializer
        newInitializer:SetEnabled(true)

        local picker = frame._lsmwPicker
        assert.is_true(picker.dropdown:IsEnabled())
        assert.is_true(picker.host:IsEnabled())
        assert.is_true(picker.preview:IsShown())

        oldInitializer:SetEnabled(false)

        assert.is_true(picker.dropdown:IsEnabled())
        assert.is_true(picker.host:IsEnabled())
        assert.is_true(picker.preview:IsShown())
    end)

    it("registers declarative font and texture row types with LibSettingsBuilder", function()
        local registered = {}
        local lib = LibStub("LibLSMSettingsWidgets-1.0")

        lib.Register({
            RegisterRowType = function(_, name, descriptor)
                registered[name] = descriptor
            end,
        })

        assert.is_function(registered.font.applyFrame)
        assert.is_function(registered.texture.applyFrame)
        assert.are.equal("string", registered.font.varType)
        assert.are.equal("string", registered.texture.varType)
    end)
end)
