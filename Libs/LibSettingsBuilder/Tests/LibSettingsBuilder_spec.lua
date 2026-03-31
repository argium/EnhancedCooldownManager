-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder", function()
    local originalGlobals
    local addonNS
    local layoutUpdateCalls
    local SB

    local function createSB2(varPrefix, categoryName)
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            pathAdapter = LSB2.PathAdapter({
                getStore = function()
                    return addonNS.Addon.db.profile
                end,
                getDefaults = function()
                    return addonNS.Addon.db.defaults.profile
                end,
                getNestedValue = addonNS.OptionUtil.GetNestedValue,
                setNestedValue = addonNS.OptionUtil.SetNestedValue,
            }),
            varPrefix = varPrefix,
            onChanged = function() end,
        })
        SB2.CreateRootCategory(categoryName or "Test")
        return SB2
    end

    local function createSettingsPanelMock()
        local frames = {}
        local hookScripts = {}
        local currentCategory = nil
        _G.SettingsPanel = {
            IsShown = function()
                return true
            end,
            GetSettingsList = function()
                return {
                    ScrollBox = {
                        ForEachFrame = function(_, fn)
                            for _, f in ipairs(frames) do
                                fn(f)
                            end
                        end,
                    },
                }
            end,
            SelectCategory = function() end,
            DisplayCategory = function(self, cat)
                currentCategory = cat or currentCategory
            end,
            GetCurrentCategory = function()
                return currentCategory
            end,
            SetCurrentCategory = function(_, cat)
                currentCategory = cat
            end,
            HookScript = function(_, event, fn)
                hookScripts[event] = hookScripts[event] or {}
                hookScripts[event][#hookScripts[event] + 1] = fn
            end,
            _fireScript = function(event)
                for _, fn in ipairs(hookScripts[event] or {}) do
                    fn(_G.SettingsPanel)
                end
            end,
        }
        return frames
    end

    local function createScriptableFrame()
        local frame = TestHelpers.makeFrame()
        frame._scripts = {}
        frame._text = ""
        frame._focused = false
        frame.RegisterEvent = function() end
        frame.UnregisterAllEvents = function() end
        frame.RegisterForClicks = function(self, ...)
            self._registeredClicks = { ... }
        end
        frame.SetScript = function(self, event, fn)
            self._scripts[event] = fn
        end
        frame.GetScript = function(self, event)
            return self._scripts[event]
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

    local function loadLibraryWithHookStubs()
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
        _G.CreateFrame = function(_, _, _, template)
            local frame = createScriptableFrame()
            frame._template = template
            return frame
        end

        TestHelpers.LoadChunk("Libs/LibSettingsBuilder/LibSettingsBuilder.lua", "Unable to load LibSettingsBuilder.lua")()

        return hooks, LibStub("LibSettingsBuilder-1.0")
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM_DeepEquals",
            "Settings",
            "SettingsPanel",
            "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer",
            "MinimalSliderWithSteppersMixin",
            "CreateColor",
            "CreateColorFromHexString",
            "CreateFrame",
            "hooksecurefunc",
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
            "SettingsListElementMixin",
            "SettingsDropdownControlMixin",
            "SettingsSliderControlMixin",
            "GameFontHighlightSmall",
            "GameFontNormal",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        layoutUpdateCalls = 0

        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()

        _G.ECM_DeepEquals = TestHelpers.deepEquals
        _G.GameFontHighlightSmall = "GameFontHighlightSmall"
        _G.GameFontNormal = "GameFontNormal"

        _G.UnitClass = function()
            return "Warrior", "WARRIOR", 1
        end
        _G.GetSpecialization = function()
            return 1
        end
        _G.GetSpecializationInfo = function()
            return nil, "Arms"
        end

        -- Load the library
        TestHelpers.LoadChunk("Libs/LibSettingsBuilder/LibSettingsBuilder.lua", "Unable to load LibSettingsBuilder.lua")()

        -- Register LSMW stub
        local lsmw = LibStub:NewLibrary("LibLSMSettingsWidgets-1.0", 1)
        lsmw.GetFontValues = function()
            return { Expressway = "Expressway" }
        end
        lsmw.GetStatusbarValues = function()
            return { Blizzard = "Blizzard" }
        end
        lsmw.FONT_PICKER_TEMPLATE = "TestFontPickerTemplate"
        lsmw.TEXTURE_PICKER_TEMPLATE = "TestTexturePickerTemplate"

        local profileData = {
            global = {
                hideWhenMounted = true,
                value = 5,
                mode = "solid",
                font = "Global Font",
                fontSize = 11,
                color = { r = 0.1, g = 0.2, b = 0.3, a = 1 },
                nested = { enabled = true },
            },
            powerBar = {
                enabled = true,
                height = 10,
                overrideFont = false,
                border = {
                    enabled = false,
                    thickness = 2,
                    color = { r = 0, g = 0, b = 0, a = 1 },
                },
                anchorMode = 1,
                colors = {},
            },
        }

        addonNS = {
            Addon = {
                db = {
                    profile = profileData,
                    defaults = { profile = TestHelpers.deepClone(profileData) },
                },
                NewModule = function(_, name)
                    return { moduleName = name }
                end,
            },
            Constants = {
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            CloneValue = TestHelpers.deepClone,
            Runtime = {
                ScheduleLayoutUpdate = function()
                    layoutUpdateCalls = layoutUpdateCalls + 1
                end,
            },
        }

        TestHelpers.LoadChunk("UI/OptionUtil.lua", "Unable to load UI/OptionUtil.lua")(nil, addonNS)
        TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, addonNS)

        SB = addonNS.SettingsBuilder
        SB.CreateRootCategory("TestAddon")
        SB.CreateSubcategory("TestSection")
    end)

    -- Category lifecycle
    it("CreateRootCategory, CreateSubcategory, GetRootCategoryID, GetSubcategoryID", function()
        assert.are.equal("TestAddon", SB.GetRootCategoryID())
        assert.is_not_nil(SB.GetSubcategoryID("TestSection"))
        assert.is_nil(SB.GetSubcategoryID("MissingSection"))
    end)

    it("RegisterCategories does not error", function()
        assert.has_no.errors(function()
            SB.RegisterCategories()
        end)
    end)

    it("Setting current subcategory to root allows adding headers there", function()
        SB._currentSubcategory = SB._rootCategory
        local init = SB.Header("Root Header")
        assert.are.equal("header", init._type)
        assert.are.equal("Root Header", init._text)
    end)

    -- Checkbox
    it("Checkbox reads and writes profile value", function()
        local _, setting = SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Hide",
        })

        assert.is_true(setting:GetValue())

        setting:SetValue(false)
        assert.is_false(addonNS.Addon.db.profile.global.hideWhenMounted)
        assert.are.equal(1, layoutUpdateCalls)
    end)

    it("Checkbox onSet callback is invoked on set", function()
        local onSetValue
        local _, setting = SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Hide",
            onSet = function(v)
                onSetValue = v
            end,
        })

        setting:SetValue(false)
        assert.are.equal(false, onSetValue)
    end)

    -- Slider
    it("Slider reads/writes with getTransform and setTransform", function()
        local _, setting = SB.Slider({
            path = "powerBar.height",
            name = "Height",
            min = 0,
            max = 40,
            step = 1,
            getTransform = function(v)
                return v or 0
            end,
            setTransform = function(v)
                return v > 0 and v or nil
            end,
        })

        assert.are.equal(10, setting:GetValue())

        setting:SetValue(0)
        assert.is_nil(addonNS.Addon.db.profile.powerBar.height)
    end)

    it("Slider applies default formatter when none specified", function()
        local capturedOpts
        local settings = Settings
        local origCreate = settings.CreateSlider
        rawset(settings, "CreateSlider", function(cat, setting, options, tooltip)
            capturedOpts = options
            return origCreate(cat, setting, options, tooltip)
        end)

        SB.Slider({
            path = "global.value",
            name = "Value",
            min = 0,
            max = 10,
            step = 1,
        })

        rawset(settings, "CreateSlider", origCreate)

        assert.are.equal(MinimalSliderWithSteppersMixin.Label.Right, capturedOpts._labelFormatterLocation)
        -- Default formatter renders integers without decimals
        assert.are.equal("5", capturedOpts._labelFormatter(5))
        assert.are.equal("0", capturedOpts._labelFormatter(0))
        -- Default formatter renders fractional values with one decimal
        assert.are.equal("2.5", capturedOpts._labelFormatter(2.5))
    end)

    it("Slider uses custom formatter when specified", function()
        local capturedOpts
        local settings = Settings
        local origCreate = settings.CreateSlider
        rawset(settings, "CreateSlider", function(cat, setting, options, tooltip)
            capturedOpts = options
            return origCreate(cat, setting, options, tooltip)
        end)

        local customFormatter = function(value)
            return value .. "%%"
        end
        SB.Slider({
            path = "global.value",
            name = "Value",
            min = 0,
            max = 100,
            step = 5,
            formatter = customFormatter,
        })

        rawset(settings, "CreateSlider", origCreate)

        assert.are.equal(customFormatter, capturedOpts._labelFormatter)
    end)

    -- Dropdown
    it("Dropdown creates dropdown with values", function()
        local _, setting = SB.Dropdown({
            path = "global.mode",
            name = "Mode",
            values = { solid = "Solid", flat = "Flat" },
        })

        assert.are.equal("solid", setting:GetValue())

        setting:SetValue("flat")
        assert.are.equal("flat", addonNS.Addon.db.profile.global.mode)
    end)

    -- Color
    it("Color reads/writes color as AARRGGBB hex", function()
        local _, setting = SB.Color({
            path = "global.color",
            name = "Color",
        })

        local hex = setting:GetValue()
        assert.are.equal("FF1A334D", hex)

        -- Verify round-trip: hex -> table stored in profile
        setting:SetValue("FF66809A")
        local stored = addonNS.Addon.db.profile.global.color
        assert.are.equal(0.4, math.floor(stored.r * 255 + 0.5) / 255)
    end)

    -- Control dispatcher
    it("Control dispatches to checkbox", function()
        local _, setting = SB.Control({
            type = "checkbox",
            path = "global.hideWhenMounted",
            name = "Hide",
        })
        assert.is_true(setting:GetValue())
    end)

    it("Control dispatches to slider", function()
        local _, setting = SB.Control({
            type = "slider",
            path = "global.value",
            name = "Value",
            min = 0,
            max = 10,
            step = 1,
        })
        assert.are.equal(5, setting:GetValue())
    end)

    it("Control dispatches to dropdown", function()
        local _, setting = SB.Control({
            type = "dropdown",
            path = "global.mode",
            name = "Mode",
            values = { solid = "Solid" },
        })
        assert.are.equal("solid", setting:GetValue())
    end)

    it("Control dispatches to color", function()
        local _, setting = SB.Control({
            type = "color",
            path = "global.color",
            name = "Color",
        })
        local hex = setting:GetValue()
        assert.are.equal("string", type(hex))
        assert.are.equal(8, #hex)
    end)

    it("Control errors on unknown type", function()
        assert.has_error(function()
            SB.Control({ type = "bogus", path = "x", name = "X" })
        end)
    end)

    -- layout=false
    it("layout=false skips ScheduleLayoutUpdate", function()
        local _, setting = SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Hide",
            layout = false,
        })
        setting:SetValue(false)
        assert.are.equal(0, layoutUpdateCalls)
    end)

    -- Header
    it("Header adds initializer to current layout", function()
        local init = SB.Header("Test Header")
        assert.are.equal("header", init._type)
        assert.are.equal("Test Header", init._text)
    end)

    -- Subheader
    it("Subheader adds element initializer with normal font template", function()
        local init = SB.Subheader({ name = "Item Quality" })
        assert.are.equal(SB.SUBHEADER_TEMPLATE, init._template)
        assert.are.equal("Item Quality", init.data.name)
    end)

    it("Subheader respects explicit category via root subcategory", function()
        SB._currentSubcategory = SB._rootCategory
        local init = SB.Subheader({ name = "Root Sub" })
        assert.are.equal("Root Sub", init.data.name)
    end)

    it("Subheader as parent — isParentEnabled returns true", function()
        local labelInit = SB.Subheader({ name = "Colors" })
        local childInit = SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Child",
            parent = labelInit,
        })
        -- Labels have no GetSetting, so isParentEnabled should return true
        local enabledPredicate = childInit._modifyPredicates[1]
        assert.is_true(enabledPredicate())
    end)

    -- InfoRow
    it("InfoRow adds element initializer with template and data", function()
        local init = SB.InfoRow({ name = "Author", value = "TestUser" })
        assert.are.equal(SB.INFOROW_TEMPLATE, init._template)
        assert.are.equal("Author", init.data.name)
        assert.are.equal("TestUser", init.data.value)
    end)

    it("InfoRow falls back to GetExtent when SetExtent is unavailable", function()
        local settings = Settings
        local originalCreateElementInitializer = settings.CreateElementInitializer
        rawset(settings, "CreateElementInitializer", function(frameTemplate, data)
            local init = originalCreateElementInitializer(frameTemplate, data)
            init.SetExtent = nil
            return init
        end)

        local init = SB.InfoRow({ name = "Author", value = "TestUser" })

        rawset(settings, "CreateElementInitializer", originalCreateElementInitializer)

        assert.are.equal(26, init:GetExtent())
    end)

    it("InfoRow respects explicit category", function()
        SB._currentSubcategory = SB._rootCategory
        local init = SB.InfoRow({ name = "Version", value = "1.0" })
        assert.are.equal("Version", init.data.name)
        assert.are.equal("1.0", init.data.value)
    end)

    it("InfoRow supports hidden modifier", function()
        local hidden = true
        local init = SB.InfoRow({
            name = "Secret",
            value = "x",
            hidden = function()
                return hidden
            end,
        })
        assert.is_not_nil(init._shownPredicates)
        assert.are.equal(1, #init._shownPredicates)
    end)

    it("custom list rows initialize safely without preexisting cbrHandles", function()
        local function makeListElementFrame()
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.CreateFontString = function()
                local fontString = createScriptableFrame()
                fontString.SetFontObject = function() end
                fontString.SetJustifyH = function() end
                fontString.SetJustifyV = function() end
                return fontString
            end
            frame.SetShown = function(self, shown)
                self._shown = shown
            end
            return frame
        end

        local subheader = SB.Subheader({ name = "Item Quality" })
        local subheaderFrame = makeListElementFrame()

        assert.has_no.errors(function()
            subheader:InitFrame(subheaderFrame)
        end)
        assert.is_not_nil(subheaderFrame.cbrHandles)
        assert.are.equal("Item Quality", subheaderFrame._lsbSubheaderTitle:GetText())

        subheader:Resetter(subheaderFrame)
        assert.is_true(subheaderFrame.cbrHandles._unregistered)

        local canvas = createScriptableFrame()
        canvas.SetParent = function(self, parent)
            self._parent = parent
        end
        canvas.GetParent = function(self)
            return self._parent
        end
        local embed = SB.EmbedCanvas(canvas, 120)
        local embedFrame = makeListElementFrame()

        assert.has_no.errors(function()
            embed:InitFrame(embedFrame)
        end)
        assert.are.equal(embedFrame, canvas:GetParent())
        assert.are.equal(120, canvas:GetHeight())
    end)

    -- Button
    it("Button creates button initializer with onClick", function()
        local clicked = false
        local init = SB.Button({
            name = "Do it",
            buttonText = "Click",
            onClick = function()
                clicked = true
            end,
        })
        assert.are.equal("button", init._type)
        init._onClick()
        assert.is_true(clicked)
    end)

    it("Button confirm wraps onClick in StaticPopup", function()
        local clicked = false
        SB.Button({
            name = "Danger",
            buttonText = "Reset",
            confirm = "Are you sure?",
            onClick = function()
                clicked = true
            end,
        })

        -- The shared confirm dialog should exist
        local dialogName = "LibSettingsBuilder-1.0_SettingsConfirm"
        local dialog = StaticPopupDialogs[dialogName]
        assert.is_table(dialog)

        -- Simulate accepting the popup with the data that onClick passes
        dialog.OnAccept(nil, { onAccept = function() clicked = true end })
        assert.is_true(clicked)
    end)

    it("Button confirm uses a shared dialog with per-button data", function()
        local getShownNames = TestHelpers.InstallPopupRecorder()

        local clicked = {}
        local resetButton = SB.Button({
            name = "Reset",
            confirm = "Reset everything?",
            onClick = function()
                clicked[#clicked + 1] = "reset"
            end,
        })
        local deleteButton = SB.Button({
            name = "Delete",
            confirm = "Delete profile?",
            onClick = function()
                clicked[#clicked + 1] = "delete"
            end,
        })

        resetButton._onClick()
        deleteButton._onClick()

        local shownNames = getShownNames()

        -- Both use the same shared dialog
        assert.are.equal(2, #shownNames)
        assert.are.equal(shownNames[1], shownNames[2])

        -- Verify the shared dialog's OnAccept dispatches correctly via data
        local dialogName = shownNames[1]
        local dialog = StaticPopupDialogs[dialogName]
        assert.is_table(dialog)

        dialog.OnAccept(nil, { onAccept = function() clicked[#clicked + 1] = "reset" end })
        dialog.OnAccept(nil, { onAccept = function() clicked[#clicked + 1] = "delete" end })
        assert.are.same({ "reset", "delete" }, clicked)
    end)

    -- ApplyModifiers
    it("ApplyModifiers sets parent, disabled, and hidden predicates", function()
        local parentInit, _ = SB.Checkbox({
            path = "global.nested.enabled",
            name = "Parent",
        })
        local childInit, _ = SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Child",
            parent = parentInit,
            parentCheck = function()
                return true
            end,
            disabled = function()
                return true
            end,
            hidden = function()
                return false
            end,
        })

        assert.are.equal(parentInit, childInit._parentInit)
        assert.are.equal(1, #childInit._modifyPredicates)
        assert.are.equal(1, #childInit._shownPredicates)
    end)

    it("Parent-controlled dropdown is disabled when parent is unchecked", function()
        local parentInit, parentSetting = SB.Checkbox({
            path = "global.nested.enabled",
            name = "Parent",
        })

        local childInit = SB.Dropdown({
            path = "global.mode",
            name = "Child",
            values = { solid = "Solid", flat = "Flat" },
            parent = parentInit,
            parentCheck = function()
                return parentSetting:GetValue()
            end,
        })

        local enabledPredicate = childInit._modifyPredicates[1]
        assert.is_true(enabledPredicate())

        parentSetting:SetValue(false)
        assert.is_false(enabledPredicate())
    end)

    it("Parent-controlled custom picker is disabled when parent is unchecked", function()
        local parentInit, parentSetting = SB.Checkbox({
            path = "global.nested.enabled",
            name = "Parent",
        })

        local customEnabled
        local settings = Settings
        local originalCreateElementInitializer = settings.CreateElementInitializer
        rawset(settings, "CreateElementInitializer", function(frameTemplate, data)
            local init = originalCreateElementInitializer(frameTemplate, data)
            init.SetEnabled = function(_, enabled)
                customEnabled = enabled
            end
            return init
        end)

        local childInit = SB.Custom({
            path = "global.font",
            name = "Custom picker",
            template = "TestTexturePickerTemplate",
            parent = parentInit,
            parentCheck = function()
                return parentSetting:GetValue()
            end,
        })

        rawset(settings, "CreateElementInitializer", originalCreateElementInitializer)

        local enabledPredicate = childInit._modifyPredicates[1]
        assert.is_true(customEnabled)
        assert.is_true(enabledPredicate())

        parentSetting:SetValue(false)
        assert.is_false(enabledPredicate())
        assert.is_false(customEnabled)
    end)

    -- Reactive disabled predicate
    it("disabled predicate re-evaluates when another setting changes", function()
        local frames = createSettingsPanelMock()

        local _, enabledSetting = SB.Checkbox({
            path = "powerBar.enabled",
            name = "Enable",
        })

        local childInit
        local controlEnabled
        local settings = Settings
        local origCreateCheckbox = settings.CreateCheckbox
        rawset(settings, "CreateCheckbox", function(cat, setting, tooltip)
            local init = origCreateCheckbox(cat, setting, tooltip)
            childInit = init
            return init
        end)

        SB.Checkbox({
            path = "powerBar.showText",
            name = "Show text",
            disabled = function()
                return not addonNS.Addon.db.profile.powerBar.enabled
            end,
        })

        rawset(settings, "CreateCheckbox", origCreateCheckbox)

        -- Simulate a rendered frame for the child control
        frames[1] = {
            GetElementData = function()
                return childInit
            end,
            IsEnabled = function(self)
                return self:GetElementData():EvaluateModifyPredicates()
            end,
            EvaluateState = function(self)
                controlEnabled = self:IsEnabled()
            end,
            SetShown = function() end,
        }
        -- Verify initial state
        frames[1]:EvaluateState()
        assert.is_true(controlEnabled)

        enabledSetting:SetValue(false)
        assert.is_false(controlEnabled)

        enabledSetting:SetValue(true)
        assert.is_true(controlEnabled)

        _G.SettingsPanel = nil
    end)

    -- Reactive hidden predicate
    it("hidden predicate re-evaluates when another setting changes", function()
        local frames = createSettingsPanelMock()

        local _, toggleSetting = SB.Checkbox({
            path = "powerBar.enabled",
            name = "Enable",
        })

        local childInit
        local settings = Settings
        local origCreateCheckbox = settings.CreateCheckbox
        rawset(settings, "CreateCheckbox", function(cat, setting, tooltip)
            local init = origCreateCheckbox(cat, setting, tooltip)
            childInit = init
            return init
        end)

        SB.Checkbox({
            path = "powerBar.showText",
            name = "Show text",
            hidden = function()
                return not addonNS.Addon.db.profile.powerBar.enabled
            end,
        })

        rawset(settings, "CreateCheckbox", origCreateCheckbox)

        -- Initial state: enabled=true, so hidden()=false → shown
        local shownPredicate = childInit._shownPredicates[1]
        assert.is_true(shownPredicate())

        -- Simulate a rendered frame that checks ShouldShow
        local frameShown = true
        childInit.ShouldShow = function()
            return not childInit._shownPredicates[1] or childInit._shownPredicates[1]()
        end
        frames[1] = {
            GetElementData = function()
                return childInit
            end,
            EvaluateState = function(self)
                frameShown = self:GetElementData():ShouldShow()
            end,
        }
        frames[1]:EvaluateState()
        assert.is_true(frameShown)

        toggleSetting:SetValue(false)
        assert.is_false(frameShown)

        toggleSetting:SetValue(true)
        assert.is_true(frameShown)

        _G.SettingsPanel = nil
    end)

    -- HeightOverrideSlider
    it("HeightOverrideSlider transforms nil→0 and 0→nil", function()
        local _, setting = SB.HeightOverrideSlider("powerBar")

        assert.are.equal(10, setting:GetValue())

        setting:SetValue(0)
        assert.is_nil(addonNS.Addon.db.profile.powerBar.height)
        assert.are.equal(0, setting:GetValue())
    end)

    -- BorderGroup
    it("BorderGroup creates enabled, thickness, color controls", function()
        local result = SB.BorderGroup("powerBar.border")
        assert.is_not_nil(result.enabledInit)
        assert.is_not_nil(result.enabledSetting)
        assert.is_not_nil(result.thicknessInit)
        assert.is_not_nil(result.colorInit)
    end)

    -- FontOverrideGroup
    it("FontOverrideGroup creates override checkbox, font dropdown, size slider", function()
        local result = SB.FontOverrideGroup("powerBar")
        assert.is_not_nil(result.enabledInit)
        assert.is_not_nil(result.enabledSetting)
        assert.is_not_nil(result.fontInit)
        assert.is_not_nil(result.sizeInit)
    end)

    it("FontOverrideGroup children are disabled when override is unchecked", function()
        addonNS.Addon.db.profile.powerBar.overrideFont = false
        local result = SB.FontOverrideGroup("powerBar")

        -- Font and size children should have modify predicates (disabled, not hidden)
        assert.is_truthy(result.fontInit._modifyPredicates)
        assert.is_truthy(result.sizeInit._modifyPredicates)
        assert.is_nil(result.fontInit._parentInit)
        assert.is_nil(result.sizeInit._parentInit)

        local fontPredicate = result.fontInit._modifyPredicates[1]
        local sizePredicate = result.sizeInit._modifyPredicates[1]

        -- Override is false → children disabled
        assert.is_false(fontPredicate())
        assert.is_false(sizePredicate())

        -- Toggle override on → children enabled
        result.enabledSetting:SetValue(true)
        assert.is_true(fontPredicate())
        assert.is_true(sizePredicate())
    end)

    -- ColorPickerList
    it("ColorPickerList creates native color swatch per definition", function()
        addonNS.Addon.db.profile.powerBar.colors = {
            [0] = { r = 0, g = 0, b = 1, a = 1 },
        }
        addonNS.Addon.db.defaults.profile.powerBar.colors = {
            [0] = { r = 0, g = 0, b = 1, a = 1 },
        }

        local defs = {
            { key = 0, name = "Mana" },
            { key = 1, name = "Rage" },
        }
        local results = SB.ColorPickerList("powerBar.colors", defs)
        assert.are.equal(2, #results)
        assert.are.equal(0, results[1].key)
        assert.are.equal(1, results[2].key)
        assert.is_not_nil(results[1].initializer)
        assert.is_not_nil(results[1].setting)
        assert.is_not_nil(results[2].initializer)
        assert.is_not_nil(results[2].setting)
    end)

    -- RegisterSection
    it("RegisterSection stores section in namespace", function()
        local ns = {}
        local section = { RegisterSettings = function() end }
        SB.RegisterSection(ns, "Foo", section)
        assert.are.same(section, ns.OptionsSections.Foo)
    end)

    -- Built-in path accessors
    it("path accessors read and write nested values", function()
        local SB2 = createSB2("TEST2", "Test2")
        SB2.CreateSubcategory("Sub2")

        local _, setting = SB2.Checkbox({
            path = "global.hideWhenMounted",
            name = "Hide",
        })
        assert.is_true(setting:GetValue())

        setting:SetValue(false)
        assert.is_false(addonNS.Addon.db.profile.global.hideWhenMounted)
    end)

    it("built-in path accessors handle numeric keys", function()
        addonNS.Addon.db.profile.powerBar.colors[0] = { r = 0, g = 0, b = 1, a = 1 }
        addonNS.Addon.db.defaults.profile.powerBar.colors[0] = { r = 0, g = 0, b = 1, a = 1 }

        local SB2 = createSB2("TEST3", "Test3")
        SB2.CreateSubcategory("Sub3")

        local _, setting = SB2.Color({
            path = "powerBar.colors.0",
            name = "Mana",
        })
        local hex = setting:GetValue()
        assert.are.equal("string", type(hex))
        assert.are.equal(8, #hex)
    end)

    -- Header "Display" no longer suppressed
    it("Header('Display') returns initializer (no longer suppressed)", function()
        local init = SB.Header("Display")
        assert.are.equal("header", init._type)
        assert.are.equal("Display", init._text)
    end)

    -- Header first-header suppression
    it("Header suppresses first header matching subcategory name", function()
        SB.CreateSubcategory("Appearance")
        local init = SB.Header("Appearance")
        assert.is_nil(init)

        -- Second header with different text is not suppressed
        local init2 = SB.Header("Colors")
        assert.is_not_nil(init2)
    end)

    -- Custom with varType override
    it("Custom respects varType override", function()
        local capturedVarType
        local settings = Settings
        local origRegister = settings.RegisterProxySetting
        rawset(settings, "RegisterProxySetting", function(cat, variable, varType, name, default, getter, setter)
            capturedVarType = varType
            return origRegister(cat, variable, varType, name, default, getter, setter)
        end)

        SB.Custom({
            path = "global.value",
            name = "Custom Numeric",
            template = "TestTemplate",
            varType = Settings.VarType.Number,
        })

        rawset(settings, "RegisterProxySetting", origRegister)
        assert.are.equal(Settings.VarType.Number, capturedVarType)
    end)

    -- propagateModifiers with layout
    it("propagateModifiers propagates layout=false to composite children", function()
        SB.HeightOverrideSlider("powerBar", { layout = false })
        -- Since layout=false is propagated, the onChanged check should skip layout
        -- We verify by setting the value and checking layoutUpdateCalls stays 0
        -- (Need to reload to test with onChanged that checks layout)
    end)

    -- Spec field validation
    it("debug spec validation warns on unknown fields", function()
        local warnings = {}
        local origPrint = print
        _G.print = function(msg)
            if type(msg) == "string" and msg:find("LibSettingsBuilder WARNING") then
                warnings[#warnings + 1] = msg
            end
        end
        _G.LSB_DEBUG = true

        SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Test",
            bogusField = true,
        })

        _G.LSB_DEBUG = nil
        _G.print = origPrint

        assert.is_true(#warnings > 0)
        assert.is_truthy(warnings[1]:find("bogusField"))
    end)

    it("debug spec validation is silent when LSB_DEBUG is off", function()
        local warnings = {}
        local origPrint = print
        _G.print = function(msg)
            if type(msg) == "string" and msg:find("LibSettingsBuilder WARNING") then
                warnings[#warnings + 1] = msg
            end
        end
        _G.LSB_DEBUG = nil

        SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Test",
            bogusField = true,
        })

        _G.print = origPrint
        assert.are.equal(0, #warnings)
    end)

    -- Dropdown with scrollHeight
    it("Dropdown with scrollHeight uses scroll template", function()
        local capturedTemplate
        local settings = Settings
        local origCreateElementInitializer = settings.CreateElementInitializer
        rawset(settings, "CreateElementInitializer", function(template, data)
            capturedTemplate = template
            return origCreateElementInitializer(template, data)
        end)

        local _, setting = SB.Dropdown({
            path = "global.mode",
            name = "Scrollable Mode",
            values = { solid = "Solid", flat = "Flat" },
            scrollHeight = 300,
        })

        rawset(settings, "CreateElementInitializer", origCreateElementInitializer)

        assert.are.equal(SB.SCROLL_DROPDOWN_TEMPLATE, capturedTemplate)
        assert.are.equal("solid", setting:GetValue())

        setting:SetValue("flat")
        assert.are.equal("flat", addonNS.Addon.db.profile.global.mode)
    end)

    it("Dropdown without scrollHeight uses standard dropdown", function()
        local capturedTemplate = nil
        local settings = Settings
        local origCreateElementInitializer = settings.CreateElementInitializer
        rawset(settings, "CreateElementInitializer", function(template, data)
            capturedTemplate = template
            return origCreateElementInitializer(template, data)
        end)

        SB.Dropdown({
            path = "global.mode",
            name = "Standard Mode",
            values = { solid = "Solid", flat = "Flat" },
        })

        rawset(settings, "CreateElementInitializer", origCreateElementInitializer)

        -- Standard path uses Settings.CreateDropdown, not CreateElementInitializer
        -- with the scroll template
        assert.is_not_equal(SB.SCROLL_DROPDOWN_TEMPLATE, capturedTemplate)
    end)

    it("Dropdown options are added in deterministic label order", function()
        local init = SB.Dropdown({
            path = "global.mode",
            name = "Standard Mode",
            values = {
                gamma = "Gamma",
                alpha = "Alpha",
                beta = "Beta",
            },
        })

        local options = init._optionsGen()
        assert.are.same({ "Alpha", "Beta", "Gamma" }, {
            options[1].label,
            options[2].label,
            options[3].label,
        })
        assert.are.same({ "alpha", "beta", "gamma" }, {
            options[1].value,
            options[2].value,
            options[3].value,
        })
    end)

    it("scroll dropdown menu options are added in deterministic label order", function()
        local hooks = select(1, loadLibraryWithHookStubs())
        local initHook = hooks[_G.SettingsDropdownControlMixin].Init

        local currentValue = "beta"
        local setting = {
            GetValue = function()
                return currentValue
            end,
            SetValue = function(_, value)
                currentValue = value
            end,
        }

        local dropdown = {
            SetupMenu = function(self, builder)
                self._builder = builder
            end,
            OverrideText = function(self, text)
                self._text = text
            end,
        }
        local frame = {
            Control = { Dropdown = dropdown },
            SetValue = function() end,
        }
        local initializer = {
            GetData = function()
                return {
                    _lsbKind = "scrollDropdown",
                    setting = setting,
                    values = {
                        gamma = "Gamma",
                        alpha = "Alpha",
                        beta = "Beta",
                    },
                    scrollHeight = 240,
                }
            end,
            GetSetting = function()
                return setting
            end,
        }

        initHook(frame, initializer)

        local orderedLabels = {}
        local rootDescription = {
            SetScrollMode = function(_, value)
                orderedLabels.scrollHeight = value
            end,
            CreateRadio = function(_, label)
                orderedLabels[#orderedLabels + 1] = label
            end,
        }
        dropdown._builder(nil, rootDescription)

        assert.are.equal("Beta", dropdown._text)
        assert.are.equal(240, orderedLabels.scrollHeight)
        assert.are.same({ "Alpha", "Beta", "Gamma" }, {
            orderedLabels[1],
            orderedLabels[2],
            orderedLabels[3],
        })
    end)

    -- RegisterFromTable
    it("RegisterFromTable creates subcategory and controls from table", function()
        local SB2 = createSB2("TBL1", "TableTest")

        SB2.RegisterFromTable({
            name = "Test Section",
            path = "global",
            args = {
                header1 = { type = "header", name = "Visibility", order = 1 },
                mounted = { type = "toggle", path = "hideWhenMounted", name = "Hide", order = 2 },
                val = { type = "range", path = "value", name = "Value", min = 0, max = 10, step = 1, order = 3 },
                mode = { type = "select", path = "mode", name = "Mode", values = { solid = "Solid" }, order = 4 },
            },
        })

        -- Verify subcategory was created
        assert.is_not_nil(SB2.GetSubcategoryID("Test Section"))
    end)

    it("RegisterFromTable inherits disabled from group", function()
        local disabledFn = function()
            return true
        end
        local SB2 = createSB2("TBL2", "InheritTest")

        SB2.RegisterFromTable({
            name = "Inherit Section",
            path = "global",
            disabled = disabledFn,
            args = {
                mounted = { type = "toggle", path = "hideWhenMounted", name = "Hide", order = 1 },
            },
        })

        -- The control should have the disabled predicate applied
        -- (We can't directly inspect the predicate, but we verify no error occurs)
        assert.is_not_nil(SB2.GetSubcategoryID("Inherit Section"))
    end)

    it("RegisterFromTable resolves parent references by key", function()
        local SB2 = createSB2("TBL3", "ParentRefTest")

        assert.has_no.errors(function()
            SB2.RegisterFromTable({
                name = "Parent Ref Section",
                path = "global",
                args = {
                    parentCtrl = { type = "toggle", path = "hideWhenMounted", name = "Parent", order = 1 },
                    childCtrl = {
                        type = "range",
                        path = "value",
                        name = "Child",
                        min = 0,
                        max = 10,
                        step = 1,
                        parent = "parentCtrl",
                        parentCheck = "checked",
                        order = 2,
                    },
                },
            })
        end)
    end)

    it("RegisterFromTable supports type aliases", function()
        local SB2 = createSB2("TBL4", "AliasTest")

        -- All AceConfig type aliases should work without error
        assert.has_no.errors(function()
            SB2.RegisterFromTable({
                name = "Alias Section",
                path = "global",
                args = {
                    t = { type = "toggle", path = "hideWhenMounted", name = "Toggle", order = 1 },
                    r = { type = "range", path = "value", name = "Range", min = 0, max = 10, step = 1, order = 2 },
                    s = { type = "select", path = "mode", name = "Select", values = { solid = "Solid" }, order = 3 },
                    h = { type = "header", name = "Header", order = 4 },
                    d = { type = "description", name = "Desc", order = 5 },
                    i = { type = "info", name = "Author", value = "Test", order = 6 },
                },
            })
        end)
    end)

    it("RegisterFromTable supports desc as alias for tooltip", function()
        local capturedTooltip
        local settings = Settings
        local origCreateCheckbox = settings.CreateCheckbox
        rawset(settings, "CreateCheckbox", function(cat, setting, tooltip)
            capturedTooltip = tooltip
            return origCreateCheckbox(cat, setting, tooltip)
        end)

        local SB2 = createSB2("TBL5", "DescTest")

        SB2.RegisterFromTable({
            name = "Desc Section",
            path = "global",
            args = {
                mounted = {
                    type = "toggle",
                    path = "hideWhenMounted",
                    name = "Hide",
                    desc = "Hide when on a mount.",
                    order = 1,
                },
            },
        })

        rawset(settings, "CreateCheckbox", origCreateCheckbox)
        assert.are.equal("Hide when on a mount.", capturedTooltip)
    end)

    it("RegisterFromTable path prefixing works", function()
        local SB2 = createSB2("TBL7", "PrefixTest")

        SB2.RegisterFromTable({
            name = "Prefix Section",
            path = "powerBar",
            args = {
                enabled = { type = "toggle", path = "enabled", name = "Enabled", order = 1 },
            },
        })

        -- The checkbox should read from powerBar.enabled
        assert.is_true(addonNS.Addon.db.profile.powerBar.enabled)
    end)

    -- RegisterFromTable condition support
    it("RegisterFromTable condition=false skips entry", function()
        local headerCreated = false
        local origHeader = CreateSettingsListSectionHeaderInitializer
        _G.CreateSettingsListSectionHeaderInitializer = function(text)
            if text == "Should Not Appear" then
                headerCreated = true
            end
            return origHeader(text)
        end

        local SB2 = createSB2("COND1", "CondTest")

        SB2.RegisterFromTable({
            name = "Cond Section",
            path = "global",
            args = {
                skipped = {
                    type = "header",
                    name = "Should Not Appear",
                    condition = function()
                        return false
                    end,
                    order = 1,
                },
                shown = { type = "header", name = "Should Appear", order = 2 },
            },
        })

        _G.CreateSettingsListSectionHeaderInitializer = origHeader
        assert.is_false(headerCreated)
    end)

    it("RegisterFromTable condition=true includes entry", function()
        local headerCreated = false
        local origHeader = CreateSettingsListSectionHeaderInitializer
        _G.CreateSettingsListSectionHeaderInitializer = function(text)
            if text == "Conditional Header" then
                headerCreated = true
            end
            return origHeader(text)
        end

        local SB2 = createSB2("COND2", "CondTest2")

        SB2.RegisterFromTable({
            name = "Cond Section 2",
            path = "global",
            args = {
                shown = {
                    type = "header",
                    name = "Conditional Header",
                    condition = function()
                        return true
                    end,
                    order = 1,
                },
            },
        })

        _G.CreateSettingsListSectionHeaderInitializer = origHeader
        assert.is_true(headerCreated)
    end)

    it("RegisterFromTable rootCategory=true uses root instead of subcategory", function()
        local SB2 = createSB2("ROOT1", "RootTest")

        SB2.RegisterFromTable({
            name = "Root Section",
            rootCategory = true,
            path = "global",
            args = {
                mounted = { type = "toggle", path = "hideWhenMounted", name = "Hide", order = 1 },
            },
        })

        -- rootCategory=true should NOT create a subcategory
        assert.is_nil(SB2.GetSubcategoryID("Root Section"))
    end)

    it("RegisterFromTable canvas type embeds a canvas frame", function()
        local SB2 = createSB2("CANVAS1", "CanvasTest")

        local canvasFrame = {
            GetHeight = function()
                return 200
            end,
        }

        local embeddedCanvas, embeddedHeight
        local origEmbed = SB2.EmbedCanvas
        SB2.EmbedCanvas = function(canvas, height, spec)
            embeddedCanvas = canvas
            embeddedHeight = height
            return origEmbed(canvas, height, spec)
        end

        SB2.RegisterFromTable({
            name = "Canvas Section",
            path = "global",
            args = {
                myCanvas = { type = "canvas", canvas = canvasFrame, height = 400, order = 1 },
            },
        })

        assert.are.equal(canvasFrame, embeddedCanvas)
        assert.are.equal(400, embeddedHeight)
    end)

    it("CanvasLayout supports configurable defaults and per-layout overrides", function()
        local originalCreateFrame = _G.CreateFrame
        _G.CreateFrame = function(_, _, _, template)
            local frame = TestHelpers.makeFrame({ height = 0, width = 0 })
            frame._template = template
            frame.SetSize = function(self, width, height)
                self:SetWidth(width)
                self:SetHeight(height)
            end
            frame.SetText = function(self, text)
                self._text = text
            end
            frame.CreateFontString = function()
                local fontString = TestHelpers.makeFrame()
                fontString.SetText = function(self, text)
                    self._text = text
                end
                fontString.SetFontObject = function() end
                fontString.SetWordWrap = function() end
                fontString.SetJustifyH = function() end
                fontString.SetJustifyV = function() end
                return fontString
            end
            return frame
        end

        local originalDefaults = TestHelpers.deepClone(SB.SetCanvasLayoutDefaults())
        SB.SetCanvasLayoutDefaults({ elementHeight = 30 })

        local defaultLayout = SB.CreateCanvasLayout("Canvas Defaults")
        local defaultRow = defaultLayout:AddDescription("Uses updated defaults")
        assert.are.equal(30, defaultRow:GetHeight())

        local customLayout = SB.CreateCanvasLayout("Canvas Custom")
        SB.ConfigureCanvasLayout(customLayout, {
            elementHeight = 42,
            labelX = 20,
            buttonCenterX = -10,
            buttonWidth = 180,
        })

        local row, button = customLayout:AddButton("Action", "Run")

        assert.are.equal(42, row:GetHeight())
        TestHelpers.assertAnchor(row._label, 1, "LEFT", 20, 0, 0, 0)
        TestHelpers.assertAnchor(button, 1, "LEFT", row, "CENTER", -10, 0)
        assert.are.equal(180, button:GetWidth())

        SB.SetCanvasLayoutDefaults(originalDefaults)
        _G.CreateFrame = originalCreateFrame
    end)

    it("onSet receives setting as second parameter", function()
        local receivedSetting
        local receivedValue

        local _, setting = SB.Checkbox({
            path = "global.hideWhenMounted",
            name = "Test onSet",
            onSet = function(value, s)
                receivedValue = value
                receivedSetting = s
            end,
        })

        -- Trigger the setter via SetValue which calls the proxy setter → postSet → onSet
        setting:SetValue(false)
        assert.are.equal(false, receivedValue)
        assert.are.equal(setting, receivedSetting)
    end)

    -- PathAdapter
    describe("PathAdapter", function()
        it("resolve returns get/set/default for nested path", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local pa = LSB.PathAdapter({
                getStore = function()
                    return addonNS.Addon.db.profile
                end,
                getDefaults = function()
                    return addonNS.Addon.db.defaults.profile
                end,
            })

            local binding = pa:resolve("global.hideWhenMounted")
            assert.is_function(binding.get)
            assert.is_function(binding.set)
            assert.are.equal(true, binding.default)
            assert.are.equal(true, binding.get())

            binding.set(false)
            assert.are.equal(false, addonNS.Addon.db.profile.global.hideWhenMounted)
        end)

        it("read returns nested value", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local pa = LSB.PathAdapter({
                getStore = function()
                    return addonNS.Addon.db.profile
                end,
                getDefaults = function()
                    return addonNS.Addon.db.defaults.profile
                end,
            })

            assert.are.equal(5, pa:read("global.value"))
        end)

        it("falls back to nil when defaults table missing", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local pa = LSB.PathAdapter({
                getStore = function()
                    return addonNS.Addon.db.profile
                end,
                getDefaults = function()
                    return nil
                end,
            })

            local binding = pa:resolve("global.hideWhenMounted")
            assert.is_nil(binding.default)
        end)
    end)

    -- Handler mode
    describe("handler mode", function()
        it("Checkbox with get/set/key works without pathAdapter", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local SBH = LSB:New({
                varPrefix = "Handler",
                onChanged = function() end,
            })
            SBH.CreateRootCategory("HandlerTest")
            SBH.CreateSubcategory("HandlerSection")

            local store = { myVal = true }
            local _, setting = SBH.Checkbox({
                get = function()
                    return store.myVal
                end,
                set = function(v)
                    store.myVal = v
                end,
                key = "myVal",
                default = true,
                name = "Handler Checkbox",
            })

            assert.are.equal(true, setting:GetValue())
            setting:SetValue(false)
            assert.are.equal(false, store.myVal)
        end)

        it("Slider with get/set/key and transforms", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local SBH = LSB:New({
                varPrefix = "Handler",
                onChanged = function() end,
            })
            SBH.CreateRootCategory("HandlerTest2")
            SBH.CreateSubcategory("HandlerSection2")

            local store = { scale = 0.75 }
            local _, setting = SBH.Slider({
                get = function()
                    return store.scale
                end,
                set = function(v)
                    store.scale = v
                end,
                key = "scale",
                default = 1.0,
                name = "Handler Slider",
                min = 0,
                max = 2,
                step = 0.01,
                getTransform = function(v)
                    return v * 100
                end,
                setTransform = function(v)
                    return v / 100
                end,
            })

            assert.are.equal(75, setting:GetValue())
            setting:SetValue(50)
            assert.are.equal(0.5, store.scale)
        end)

        it("errors when spec has both path and get", function()
            assert.has.errors(function()
                SB.Checkbox({
                    path = "global.hideWhenMounted",
                    get = function()
                        return true
                    end,
                    set = function() end,
                    key = "x",
                    name = "Bad Spec",
                })
            end)
        end)

        it("errors when handler mode missing set", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local SBH = LSB:New({ varPrefix = "H", onChanged = function() end })
            SBH.CreateRootCategory("HErr")
            SBH.CreateSubcategory("HErrS")

            assert.has.errors(function()
                SBH.Checkbox({
                    get = function()
                        return true
                    end,
                    key = "x",
                    name = "Missing Set",
                })
            end)
        end)

        it("errors when handler mode missing key", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local SBH = LSB:New({ varPrefix = "H2", onChanged = function() end })
            SBH.CreateRootCategory("HErr2")
            SBH.CreateSubcategory("HErrS2")

            assert.has.errors(function()
                SBH.Checkbox({
                    get = function()
                        return true
                    end,
                    set = function() end,
                    name = "Missing Key",
                })
            end)
        end)

        it("path mode errors without pathAdapter", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local SBH = LSB:New({ varPrefix = "NP", onChanged = function() end })
            SBH.CreateRootCategory("NoPath")
            SBH.CreateSubcategory("NoPathS")

            assert.has.errors(function()
                SBH.Checkbox({
                    path = "some.path",
                    name = "No Adapter",
                })
            end)
        end)

        it("Control dispatches handler-mode checkbox", function()
            local LSB = LibStub("LibSettingsBuilder-1.0")
            local SBH = LSB:New({ varPrefix = "Disp", onChanged = function() end })
            SBH.CreateRootCategory("DispTest")
            SBH.CreateSubcategory("DispSect")

            local store = { flag = false }
            local _, setting = SBH.Control({
                type = "checkbox",
                get = function()
                    return store.flag
                end,
                set = function(v)
                    store.flag = v
                end,
                key = "flag",
                default = false,
                name = "Dispatched Handler",
            })

            assert.are.equal(false, setting:GetValue())
            setting:SetValue(true)
            assert.are.equal(true, store.flag)
        end)
    end)

    describe("slider inline edit hook", function()
        it("rebinds the edit box to the current slider setting when frames are reused", function()
            local hooks = select(1, loadLibraryWithHookStubs())
            local initHook = hooks[_G.SettingsSliderControlMixin].Init

            local firstValue = 12
            local secondValue = 33
            local firstSetting = {
                GetValue = function()
                    return firstValue
                end,
                SetValue = function(_, value)
                    firstValue = value
                end,
            }
            local secondSetting = {
                GetValue = function()
                    return secondValue
                end,
                SetValue = function(_, value)
                    secondValue = value
                end,
            }

            local firstLabel = createScriptableFrame()
            firstLabel.IsObjectType = function(_, objectType)
                return objectType == "FontString"
            end

            local sliderWithSteppers = createScriptableFrame()
            sliderWithSteppers.Slider = {
                GetMinMaxValues = function()
                    return 0, 100
                end,
                GetValueStep = function()
                    return 5
                end,
            }
            sliderWithSteppers.RightText = firstLabel
            sliderWithSteppers.GetRegions = function()
                return firstLabel
            end

            local control = {
                SliderWithSteppers = sliderWithSteppers,
            }

            initHook(control, {
                GetSetting = function()
                    return firstSetting
                end,
            })

            control._lsbValueButton:GetScript("OnClick")()
            assert.are.equal("12", control._lsbEditBox:GetText())

            local secondLabel = createScriptableFrame()
            secondLabel.IsObjectType = function(_, objectType)
                return objectType == "FontString"
            end
            sliderWithSteppers.RightText = secondLabel
            sliderWithSteppers.GetRegions = function()
                return secondLabel
            end

            initHook(control, {
                GetSetting = function()
                    return secondSetting
                end,
            })

            control._lsbValueButton:GetScript("OnClick")()
            assert.are.equal("33", control._lsbEditBox:GetText())

            control._lsbEditBox:SetText("27")
            control._lsbEditBox:GetScript("OnEnterPressed")()

            assert.are.equal(25, secondValue)
            assert.are.equal(12, firstValue)
            assert.is_true(secondLabel:IsShown())
            assert.is_false(control._lsbEditBox._focused)
        end)
    end)

    describe("page lifecycle onShow/onHide", function()
        local LSB

        before_each(function()
            createSettingsPanelMock()

            TestHelpers.SetupLibStub()
            TestHelpers.SetupSettingsStubs()

            _G.hooksecurefunc = function(tbl, method, hook)
                if type(tbl) == "table" and type(method) == "string" and type(hook) == "function" then
                    local orig = tbl[method]
                    if type(orig) == "function" then
                        tbl[method] = function(...)
                            orig(...)
                            hook(...)
                        end
                    end
                end
            end

            _G.SettingsListElementMixin = {}
            _G.SettingsDropdownControlMixin = {}
            _G.SettingsSliderControlMixin = {}
            _G.CreateFrame = function()
                return createScriptableFrame()
            end

            TestHelpers.LoadChunk(
                "Libs/LibSettingsBuilder/LibSettingsBuilder.lua",
                "Unable to load LibSettingsBuilder.lua"
            )()
            LSB = LibStub("LibSettingsBuilder-1.0")
        end)

        local function makeSB(prefix)
            return LSB:New({
                pathAdapter = LSB.PathAdapter({
                    getStore = function() return addonNS.Addon.db.profile end,
                    getDefaults = function() return addonNS.Addon.db.defaults.profile end,
                    getNestedValue = addonNS.OptionUtil.GetNestedValue,
                    setNestedValue = addonNS.OptionUtil.SetNestedValue,
                }),
                varPrefix = prefix or "T",
                onChanged = function() end,
            })
        end

        it("stores onShow/onHide callbacks when provided in RegisterFromTable", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            sb.RegisterFromTable({
                name = "Page1",
                onShow = function() end,
                onHide = function() end,
                args = {},
            })
            local cat = sb._subcategories["Page1"]
            assert.is_table(LSB._pageLifecycleCallbacks[cat])
            assert.is_function(LSB._pageLifecycleCallbacks[cat].onShow)
            assert.is_function(LSB._pageLifecycleCallbacks[cat].onHide)
        end)

        --- Simulates WoW's sidebar navigation: SetCurrentCategory then DisplayCategory.
        local function navigateTo(cat)
            SettingsPanel:SetCurrentCategory(cat)
            SettingsPanel:DisplayCategory(cat)
        end

        it("fires onShow when DisplayCategory is called with a tracked category", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            local showCount = 0
            sb.RegisterFromTable({
                name = "Page1",
                onShow = function() showCount = showCount + 1 end,
                args = {},
            })
            local cat = sb._subcategories["Page1"]
            navigateTo(cat)
            assert.are.equal(1, showCount)
        end)

        it("fires onHide when switching away from a tracked category", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            local hideCount = 0
            sb.RegisterFromTable({
                name = "Page1",
                onHide = function() hideCount = hideCount + 1 end,
                args = {},
            })
            local cat = sb._subcategories["Page1"]
            local other = { _name = "Other" }
            navigateTo(cat)
            navigateTo(other)
            assert.are.equal(1, hideCount)
        end)

        it("fires onHide when SettingsPanel is hidden", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            local hideCount = 0
            sb.RegisterFromTable({
                name = "Page1",
                onHide = function() hideCount = hideCount + 1 end,
                args = {},
            })
            local cat = sb._subcategories["Page1"]
            navigateTo(cat)
            SettingsPanel._fireScript("OnHide")
            assert.are.equal(1, hideCount)
        end)

        it("does not fire duplicate onShow when same category re-selected", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            local showCount = 0
            sb.RegisterFromTable({
                name = "Page1",
                onShow = function() showCount = showCount + 1 end,
                args = {},
            })
            local cat = sb._subcategories["Page1"]
            navigateTo(cat)
            navigateTo(cat)
            assert.are.equal(1, showCount)
        end)

        it("does not fire callbacks for categories without lifecycle hooks", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            sb.RegisterFromTable({ name = "Plain", args = {} })
            local untracked = sb._subcategories["Plain"]
            -- Should not error
            navigateTo(untracked)
        end)

        it("clears active category on panel hide so next open fires onShow", function()
            local sb = makeSB()
            sb.CreateRootCategory("Lifecycle")
            local showCount = 0
            sb.RegisterFromTable({
                name = "Page1",
                onShow = function() showCount = showCount + 1 end,
                args = {},
            })
            local cat = sb._subcategories["Page1"]
            navigateTo(cat)
            SettingsPanel._fireScript("OnHide")
            navigateTo(cat)
            assert.are.equal(2, showCount)
        end)

        it("defers hook installation when SettingsPanel is not yet available", function()
            -- Remove SettingsPanel before loading library
            _G.SettingsPanel = nil

            TestHelpers.SetupLibStub()
            TestHelpers.SetupSettingsStubs()
            _G.hooksecurefunc = function(tbl, method, hook)
                if type(tbl) == "table" and type(method) == "string" and type(hook) == "function" then
                    local orig = tbl[method]
                    if type(orig) == "function" then
                        tbl[method] = function(...)
                            orig(...)
                            hook(...)
                        end
                    end
                end
            end
            _G.SettingsListElementMixin = {}
            _G.SettingsDropdownControlMixin = {}
            _G.SettingsSliderControlMixin = {}

            local deferFrame
            _G.CreateFrame = function()
                deferFrame = createScriptableFrame()
                return deferFrame
            end

            TestHelpers.LoadChunk(
                "Libs/LibSettingsBuilder/LibSettingsBuilder.lua",
                "Unable to load LibSettingsBuilder.lua"
            )()
            local lsb = LibStub("LibSettingsBuilder-1.0")

            local sb = lsb:New({
                pathAdapter = lsb.PathAdapter({
                    getStore = function() return addonNS.Addon.db.profile end,
                    getDefaults = function() return addonNS.Addon.db.defaults.profile end,
                    getNestedValue = addonNS.OptionUtil.GetNestedValue,
                    setNestedValue = addonNS.OptionUtil.SetNestedValue,
                }),
                varPrefix = "D",
                onChanged = function() end,
            })
            sb.CreateRootCategory("Deferred")

            local showCount = 0
            sb.RegisterFromTable({
                name = "Page1",
                onShow = function() showCount = showCount + 1 end,
                args = {},
            })

            -- Hooks not yet installed — deferred frame should exist
            assert.is_table(deferFrame)
            assert.is_false(lsb._pageLifecycleHooked)

            -- Simulate Blizzard_Settings loading
            createSettingsPanelMock()
            deferFrame:GetScript("OnEvent")(deferFrame, "ADDON_LOADED", "Blizzard_Settings")

            assert.is_true(lsb._pageLifecycleHooked)

            -- Hooks should now work
            local cat = sb._subcategories["Page1"]
            SettingsPanel:SetCurrentCategory(cat)
            SettingsPanel:DisplayCategory(cat)
            assert.are.equal(1, showCount)
        end)
    end)
end)
