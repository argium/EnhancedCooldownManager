-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder", function()
    local originalGlobals
    local addonNS
    local layoutUpdateCalls
    local pendingTimers
    local SB

    local function runPendingTimers()
        while #pendingTimers > 0 do
            local timer = table.remove(pendingTimers, 1)
            if not timer.cancelled and timer.callback then
                timer.callback()
            end
        end
    end

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
        SB2.GetRoot(categoryName or "Test")
        return SB2
    end

    local function setCurrentCategoryFromSection(sb, sectionSpec, rootName)
        local root, _, page = TestHelpers.RegisterSectionSpec(sb, sectionSpec, rootName)
        sb._currentSubcategory = page and page._category or nil
        return root, page
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
        frame._hooks = {}
        frame._text = ""
        frame._focused = false
        frame.RegisterEvent = function() end
        frame.UnregisterAllEvents = function() end
        frame.RegisterForClicks = function(self, ...)
            self._registeredClicks = { ... }
        end
        frame.HookScript = function(self, event, fn)
            self._hooks[event] = self._hooks[event] or {}
            self._hooks[event][#self._hooks[event] + 1] = fn
        end
        frame.RunHookScript = function(self, event, ...)
            for _, fn in ipairs(self._hooks[event] or {}) do
                fn(self, ...)
            end
        end
        frame.SetScript = function(self, event, fn)
            self._scripts[event] = fn
        end
        frame.GetScript = function(self, event)
            return self._scripts[event]
        end
        frame.SetAutoFocus = function() end
        frame.SetEnabled = function(self, enabled)
            self._enabled = enabled
        end
        frame.EnableMouse = function(self, enabled)
            self._mouseEnabled = enabled
        end
        frame.SetMaxLetters = function(self, value)
            self._maxLetters = value
        end
        frame.SetNumeric = function() end
        frame.SetJustifyH = function() end
        frame.SetJustifyV = function() end
        frame.SetWordWrap = function() end
        frame.SetTextInsets = function() end
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

        TestHelpers.LoadLibSettingsBuilder()

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
            "C_Timer",
            "GameTooltip",
            "GameTooltip_Hide",
            "GameFontHighlight",
            "GameFontHighlightSmall",
            "GameFontNormal",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        layoutUpdateCalls = 0
        pendingTimers = {}

        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.CreateFrame = function(_, _, _, template)
            local frame = createScriptableFrame()
            frame._template = template
            return frame
        end

        _G.ECM_DeepEquals = TestHelpers.deepEquals
        _G.GameFontHighlight = "GameFontHighlight"
        _G.GameFontHighlightSmall = "GameFontHighlightSmall"
        _G.GameFontNormal = "GameFontNormal"
        _G.C_Timer = {
            NewTimer = function(_, callback)
                local timer = { callback = callback, cancelled = false }
                function timer:Cancel()
                    self.cancelled = true
                end
                pendingTimers[#pendingTimers + 1] = timer
                return timer
            end,
        }

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
        TestHelpers.LoadLibSettingsBuilder()

        -- Register LSMW stub
        local lsmw = LibStub:NewLibrary("LibLSMSettingsWidgets-1.0", 1) or LibStub("LibLSMSettingsWidgets-1.0")
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
            L = setmetatable({}, { __index = function(_, key)
                return key
            end }),
            ColorUtil = {
                Sparkle = function(text)
                    return text
                end,
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
        setCurrentCategoryFromSection(SB, {
            key = "testSection",
            name = "TestSection",
            rows = {},
        }, "TestAddon")
    end)

    -- Category lifecycle
    it("GetRoot exposes registered sections and owned categories", function()
        local root = SB.GetRoot("TestAddon")
        local section = root:GetSection("testSection")
        local page = assert(section and section:GetPage("main"))

        assert.are.equal("TestAddon", root.name)
        assert.is_not_nil(section)
        assert.is_nil(root:GetSection("missingSection"))
        assert.is_true(root:HasCategory(page._category))
        assert.is_false(root:HasCategory({}))
    end)

    it("GetRoot reuses the singleton root handle", function()
        local rootA = SB.GetRoot("TestAddon")
        local rootB = SB.GetRoot("TestAddon")

        assert.are.equal(rootA, rootB)
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

    it("CreateSubheaderTitle applies the standard subheader styling", function()
        local parent = createScriptableFrame()
        parent.CreateFontString = function(_, _, _, fontTemplate)
            local fontString = createScriptableFrame()
            fontString._fontTemplate = fontTemplate
            fontString.SetFontObject = function(self, value)
                self._fontObject = value
            end
            fontString.SetJustifyH = function(self, value)
                self._justifyH = value
            end
            fontString.SetJustifyV = function(self, value)
                self._justifyV = value
            end
            return fontString
        end

        local title = SB.CreateSubheaderTitle(parent, "Viewer Icons")
        local point, relativeTo, relativePoint, x, y = title:GetPoint(1)

        assert.are.equal("GameFontHighlightSmall", title._fontTemplate)
        assert.are.equal("TOPLEFT", point)
        assert.are.equal(parent, relativeTo)
        assert.are.equal("TOPLEFT", relativePoint)
        assert.are.equal(35, x)
        assert.are.equal(-8, y)
        assert.are.equal("LEFT", title._justifyH)
        assert.are.equal("TOP", title._justifyV)
        assert.are.equal("GameFontHighlight", title._fontObject)
        assert.are.equal("Viewer Icons", title:GetText())
        assert.is_true(title:IsShown())
    end)

    it("CreateHeaderTitle applies the standard header styling", function()
        local parent = createScriptableFrame()
        parent.CreateFontString = function(_, _, _, fontTemplate)
            local fontString = createScriptableFrame()
            fontString._fontTemplate = fontTemplate
            fontString.SetJustifyH = function(self, value)
                self._justifyH = value
            end
            fontString.SetJustifyV = function(self, value)
                self._justifyV = value
            end
            return fontString
        end

        local title = SB.CreateHeaderTitle(parent, "Viewer Icons")
        local point, relativeTo, relativePoint, x, y = title:GetPoint(1)

        assert.are.equal("GameFontHighlightLarge", title._fontTemplate)
        assert.are.equal("TOPLEFT", point)
        assert.are.equal(parent, relativeTo)
        assert.are.equal("TOPLEFT", relativePoint)
        assert.are.equal(7, x)
        assert.are.equal(-16, y)
        assert.are.equal("LEFT", title._justifyH)
        assert.are.equal("TOP", title._justifyV)
        assert.are.equal("Viewer Icons", title:GetText())
        assert.is_true(title:IsShown())
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

    it("Input creates an input row initializer and writes string values", function()
        local init, setting = SB.Input({
            path = "global.font",
            name = "Entry ID",
            layout = false,
        })

        assert.are.equal(SB.INPUTROW_TEMPLATE, init._template)
        assert.are.equal("Global Font", setting:GetValue())

        setting:SetValue("12345")
        assert.are.equal("12345", addonNS.Addon.db.profile.global.font)
    end)

    it("Input rows debounce preview text and refresh when watched settings change", function()
        local currentKind = "spell"
        local draftId = ""
        local _, kindSetting = SB.Dropdown({
            get = function()
                return currentKind
            end,
            set = function(value)
                currentKind = value
            end,
            key = "kind",
            default = "spell",
            name = "Kind",
            values = { spell = "Spell", item = "Item" },
            layout = false,
        })

        local inputInit = SB.Input({
            get = function()
                return draftId
            end,
            set = function(value)
                draftId = value
            end,
            key = "draftId",
            default = "",
            name = "Entry ID",
            debounce = 1,
            layout = false,
            resolveText = function(text)
                if not text or text == "" then
                    return nil
                end
                return currentKind .. ":" .. text
            end,
            watch = { "kind" },
        })

        local frame = createScriptableFrame()
        frame.Text = createScriptableFrame()
        frame.NewFeature = createScriptableFrame()
        frame.CreateFontString = function()
            local fontString = createScriptableFrame()
            fontString.SetJustifyH = function() end
            fontString.SetJustifyV = function() end
            fontString.SetWordWrap = function() end
            return fontString
        end
        frame.SetShown = function(self, shown)
            self._shown = shown
        end

        inputInit:InitFrame(frame)

        local editBox = frame._lsbInputEditBox
        editBox:SetText("123")
        editBox:GetScript("OnTextChanged")(editBox)

        assert.are.equal("123", draftId)
        assert.are.equal("", frame._lsbInputPreview:GetText())

        runPendingTimers()
        assert.are.equal("spell:123", frame._lsbInputPreview:GetText())

        kindSetting:SetValue("item")
        assert.are.equal("item:123", frame._lsbInputPreview:GetText())
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

    it("plain list rows hide recycled custom children and preview regions", function()
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

        local subheaderFrame = makeListElementFrame()
        local subheaderForeignChild = createScriptableFrame()
        local subheaderForeignRegion = createScriptableFrame()
        subheaderFrame.GetChildren = function()
            return subheaderForeignChild
        end
        subheaderFrame.GetRegions = function()
            return subheaderForeignRegion
        end

        local subheader = SB.Subheader({ name = "Item Quality" })
        subheader:InitFrame(subheaderFrame)

        assert.is_false(subheaderForeignChild:IsShown())
        assert.is_false(subheaderForeignRegion:IsShown())

        local canvas = createScriptableFrame()
        canvas.SetParent = function(self, parent)
            self._parent = parent
        end
        canvas.GetParent = function(self)
            return self._parent
        end

        local embedFrame = makeListElementFrame()
        local embedForeignChild = createScriptableFrame()
        local embedForeignRegion = createScriptableFrame()
        embedFrame.GetChildren = function()
            return embedForeignChild
        end
        embedFrame.GetRegions = function()
            return embedForeignRegion
        end

        local embed = SB.EmbedCanvas(canvas, 120)
        embed:InitFrame(embedFrame)

        assert.is_false(embedForeignChild:IsShown())
        assert.is_false(embedForeignRegion:IsShown())
        assert.are.equal(embedFrame, canvas:GetParent())
    end)

    it("canvas rows hide the previous canvas when the frame is reused on another page", function()
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

        local canvasA = createScriptableFrame()
        canvasA.SetParent = function(self, parent)
            self._parent = parent
        end
        canvasA.GetParent = function(self)
            return self._parent
        end

        local canvasB = createScriptableFrame()
        canvasB.SetParent = function(self, parent)
            self._parent = parent
        end
        canvasB.GetParent = function(self)
            return self._parent
        end

        local canvasRowA = SB.EmbedCanvas(canvasA, 120)
        local canvasRowB = SB.EmbedCanvas(canvasB, 140)
        local subheader = SB.Subheader({ name = "Reused Frame" })
        local frame = makeListElementFrame()

        canvasRowA:InitFrame(frame)
        assert.is_true(canvasA:IsShown())
        assert.are.equal(frame, canvasA:GetParent())

        canvasRowA:Resetter(frame)
        assert.is_false(canvasA:IsShown())
        assert.is_nil(frame._lsbCanvas)

        subheader:InitFrame(frame)
        assert.is_false(canvasA:IsShown())

        subheader:Resetter(frame)

        canvasRowB:InitFrame(frame)
        assert.is_false(canvasA:IsShown())
        assert.is_true(canvasB:IsShown())
        assert.are.equal(frame, canvasB:GetParent())

        canvasRowB:Resetter(frame)
        assert.is_false(canvasB:IsShown())

        canvasRowA:InitFrame(frame)
        assert.is_true(canvasA:IsShown())
        assert.are.equal(frame, canvasA:GetParent())
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
        local dialogName = "ECM_LibSettingsBuilder_1_0_SettingsConfirm"
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

    -- Built-in path accessors
    it("path accessors read and write nested values", function()
        local SB2 = createSB2("TEST2", "Test2")
        local _, page = setCurrentCategoryFromSection(SB2, {
            key = "sub2",
            name = "Sub2",
            rows = {},
        }, "Test2")
        SB2._currentSubcategory = page._category

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
        local _, page = setCurrentCategoryFromSection(SB2, {
            key = "sub3",
            name = "Sub3",
            rows = {},
        }, "Test3")
        SB2._currentSubcategory = page._category

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

    it("Header matching subcategory name still returns a normal header", function()
        local _, page = setCurrentCategoryFromSection(SB, {
            key = "appearance",
            name = "Appearance",
            rows = {},
        }, "TestAddon")
        SB._currentSubcategory = page._category
        local init = SB.Header("Appearance")
        assert.are.equal("header", init._type)
        assert.are.equal("Appearance", init._text)
    end)

    it("Header accepts hidden predicates through spec tables", function()
        local init = SB.Header({
            name = "Quick Add",
            hidden = function()
                return true
            end,
        })

        assert.are.equal("header", init._type)
        assert.are.equal(1, #(init._shownPredicates or {}))
        assert.is_false(init._shownPredicates[1]())
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

    it("Dropdown with scrollHeight keeps Blizzard's native dropdown options callback", function()
        local init, setting = SB.Dropdown({
            path = "global.mode",
            name = "Scrollable Mode",
            values = { solid = "Solid", flat = "Flat" },
            scrollHeight = 300,
        })

        assert.is_function(init._optionsGen)
        assert.are.equal("scrollDropdown", init._lsbData._lsbKind)
        assert.are.equal(300, init._lsbData.scrollHeight)
        assert.are.equal(setting, init:GetSetting())
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
            _lsbData = {
                _lsbKind = "scrollDropdown",
                setting = setting,
                values = {
                    gamma = "Gamma",
                    alpha = "Alpha",
                    beta = "Beta",
                },
                scrollHeight = 240,
            },
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

    -- Declarative root registration
    it("root:Register creates section pages and controls from ordered rows", function()
        local SB2 = createSB2("TBL1", "TableTest")
        local root = SB2.GetRoot("TableTest")

        root:Register({
            sections = {
                {
                    key = "testSection",
                    name = "Test Section",
                    path = "global",
                    rows = {
                        { id = "header1", type = "header", name = "Visibility" },
                        { id = "mounted", type = "checkbox", path = "hideWhenMounted", name = "Hide" },
                        { id = "val", type = "slider", path = "value", name = "Value", min = 0, max = 10, step = 1 },
                        { id = "mode", type = "dropdown", path = "mode", name = "Mode", values = { solid = "Solid" } },
                    },
                },
            },
        })

        local page = root:GetSection("testSection"):GetPage("main")
        assert.is_not_nil(page)
        assert.is_true(root:HasCategory(page._category))
    end)

    it("root:Register inherits disabled from the page spec", function()
        local disabledFn = function()
            return true
        end
        local SB2 = createSB2("TBL2", "InheritTest")

        assert.has_no.errors(function()
            SB2.GetRoot("InheritTest"):Register({
                sections = {
                    {
                        key = "inheritSection",
                        name = "Inherit Section",
                        path = "global",
                        disabled = disabledFn,
                        rows = {
                            { id = "mounted", type = "checkbox", path = "hideWhenMounted", name = "Hide" },
                        },
                    },
                },
            })
        end)
    end)

    it("root:Register resolves parent references by row id", function()
        local SB2 = createSB2("TBL3", "ParentRefTest")

        assert.has_no.errors(function()
            SB2.GetRoot("ParentRefTest"):Register({
                sections = {
                    {
                        key = "parentRefSection",
                        name = "Parent Ref Section",
                        path = "global",
                        rows = {
                            { id = "parentCtrl", type = "checkbox", path = "hideWhenMounted", name = "Parent" },
                            {
                                id = "childCtrl",
                                type = "slider",
                                path = "value",
                                name = "Child",
                                min = 0,
                                max = 10,
                                step = 1,
                                parent = "parentCtrl",
                                parentCheck = "checked",
                            },
                        },
                    },
                },
            })
        end)
    end)

    it("root:Register accepts canonical row types only", function()
        local SB2 = createSB2("TBL4", "AliasTest")

        assert.has_no.errors(function()
            SB2.GetRoot("AliasTest"):Register({
                sections = {
                    {
                        key = "aliasSection",
                        name = "Alias Section",
                        path = "global",
                        rows = {
                            { id = "t", type = "checkbox", path = "hideWhenMounted", name = "Toggle" },
                            { id = "r", type = "slider", path = "value", name = "Range", min = 0, max = 10, step = 1 },
                            { id = "s", type = "dropdown", path = "mode", name = "Select", values = { solid = "Solid" } },
                            { id = "h", type = "header", name = "Header" },
                            { id = "d", type = "subheader", name = "Desc" },
                            { id = "i", type = "info", name = "Author", value = "Test" },
                        },
                    },
                },
            })
        end)
    end)

    it("root:Register supports desc as alias for tooltip", function()
        local capturedTooltip
        local settings = Settings
        local origCreateCheckbox = settings.CreateCheckbox
        rawset(settings, "CreateCheckbox", function(cat, setting, tooltip)
            capturedTooltip = tooltip
            return origCreateCheckbox(cat, setting, tooltip)
        end)

        local SB2 = createSB2("TBL5", "DescTest")

        SB2.GetRoot("DescTest"):Register({
            sections = {
                {
                    key = "descSection",
                    name = "Desc Section",
                    path = "global",
                    rows = {
                        {
                            id = "mounted",
                            type = "checkbox",
                            path = "hideWhenMounted",
                            name = "Hide",
                            desc = "Hide when on a mount.",
                        },
                    },
                },
            },
        })

        rawset(settings, "CreateCheckbox", origCreateCheckbox)
        assert.are.equal("Hide when on a mount.", capturedTooltip)
    end)

    it("root:Register applies section path prefixing", function()
        local SB2 = createSB2("TBL7", "PrefixTest")

        SB2.GetRoot("PrefixTest"):Register({
            sections = {
                {
                    key = "prefixSection",
                    name = "Prefix Section",
                    path = "powerBar",
                    rows = {
                        { id = "enabled", type = "checkbox", path = "enabled", name = "Enabled" },
                    },
                },
            },
        })

        assert.is_true(addonNS.Addon.db.profile.powerBar.enabled)
    end)

    it("root:Register condition=false skips entry", function()
        local headerCreated = false
        local origHeader = CreateSettingsListSectionHeaderInitializer
        _G.CreateSettingsListSectionHeaderInitializer = function(text)
            if text == "Should Not Appear" then
                headerCreated = true
            end
            return origHeader(text)
        end

        local SB2 = createSB2("COND1", "CondTest")

        SB2.GetRoot("CondTest"):Register({
            sections = {
                {
                    key = "condSection",
                    name = "Cond Section",
                    path = "global",
                    rows = {
                        {
                            id = "skipped",
                            type = "header",
                            name = "Should Not Appear",
                            condition = function()
                                return false
                            end,
                        },
                        { id = "shown", type = "header", name = "Should Appear" },
                    },
                },
            },
        })

        _G.CreateSettingsListSectionHeaderInitializer = origHeader
        assert.is_false(headerCreated)
    end)

    it("root:Register condition=true includes entry", function()
        local headerCreated = false
        local origHeader = CreateSettingsListSectionHeaderInitializer
        _G.CreateSettingsListSectionHeaderInitializer = function(text)
            if text == "Conditional Header" then
                headerCreated = true
            end
            return origHeader(text)
        end

        local SB2 = createSB2("COND2", "CondTest2")

        SB2.GetRoot("CondTest2"):Register({
            sections = {
                {
                    key = "condSection2",
                    name = "Cond Section 2",
                    path = "global",
                    rows = {
                        {
                            id = "shown",
                            type = "header",
                            name = "Conditional Header",
                            condition = function()
                                return true
                            end,
                        },
                    },
                },
            },
        })

        _G.CreateSettingsListSectionHeaderInitializer = origHeader
        assert.is_true(headerCreated)
    end)

    it("root:Register passes hidden predicates to header initializers", function()
        local capturedHeader
        local origHeader = CreateSettingsListSectionHeaderInitializer
        _G.CreateSettingsListSectionHeaderInitializer = function(text)
            capturedHeader = origHeader(text)
            return capturedHeader
        end

        local SB2 = createSB2("COND3", "CondTest3")

        SB2.GetRoot("CondTest3"):Register({
            sections = {
                {
                    key = "condSection3",
                    name = "Cond Section 3",
                    path = "global",
                    rows = {
                        {
                            id = "shown",
                            type = "header",
                            name = "Conditional Header",
                            hidden = function()
                                return true
                            end,
                        },
                    },
                },
            },
        })

        _G.CreateSettingsListSectionHeaderInitializer = origHeader
        assert.is_not_nil(capturedHeader)
        assert.are.equal(1, #(capturedHeader._shownPredicates or {}))
        assert.is_false(capturedHeader._shownPredicates[1]())
    end)

    it("root:Register root pages stay on the root category", function()
        local SB2 = createSB2("ROOT1", "RootTest")
        local root = SB2.GetRoot("RootTest")

        root:Register({
            page = {
                key = "rootSection",
                path = "global",
                rows = {
                    { id = "mounted", type = "checkbox", path = "hideWhenMounted", name = "Hide" },
                },
            },
        })

        assert.are.equal("RootTest", root:GetPage("rootSection"):GetID())
    end)

    it("root:Register canvas rows embed a canvas frame", function()
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

        SB2.GetRoot("CanvasTest"):Register({
            sections = {
                {
                    key = "canvasSection",
                    name = "Canvas Section",
                    path = "global",
                    rows = {
                        { id = "myCanvas", type = "canvas", canvas = canvasFrame, height = 400 },
                    },
                },
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
            local _, page = setCurrentCategoryFromSection(SBH, {
                key = "handlerSection",
                name = "HandlerSection",
                rows = {},
            }, "HandlerTest")
            SBH._currentSubcategory = page._category

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
            local _, page = setCurrentCategoryFromSection(SBH, {
                key = "handlerSection2",
                name = "HandlerSection2",
                rows = {},
            }, "HandlerTest2")
            SBH._currentSubcategory = page._category

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
            local _, page = setCurrentCategoryFromSection(SBH, {
                key = "hErrS",
                name = "HErrS",
                rows = {},
            }, "HErr")
            SBH._currentSubcategory = page._category

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
            local _, page = setCurrentCategoryFromSection(SBH, {
                key = "hErrS2",
                name = "HErrS2",
                rows = {},
            }, "HErr2")
            SBH._currentSubcategory = page._category

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
            local _, page = setCurrentCategoryFromSection(SBH, {
                key = "noPathS",
                name = "NoPathS",
                rows = {},
            }, "NoPath")
            SBH._currentSubcategory = page._category

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
            local _, page = setCurrentCategoryFromSection(SBH, {
                key = "dispSect",
                name = "DispSect",
                rows = {},
            }, "DispTest")
            SBH._currentSubcategory = page._category

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

            TestHelpers.LoadLibSettingsBuilder()
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

        local function registerLifecycleSection(sb, opts)
            local root = sb.GetRoot(opts.rootName or "Lifecycle")
            local key = opts.key or "page1"

            root:Register({
                sections = {
                    {
                        key = key,
                        name = opts.name or "Page1",
                        onShow = opts.onShow,
                        onHide = opts.onHide,
                        rows = opts.rows or {},
                    },
                },
            })

            local page = root:GetSection(key):GetPage("main")
            return root, page, page._category
        end

        it("stores onShow/onHide callbacks when provided declaratively", function()
            local sb = makeSB()
            local _, _, cat = registerLifecycleSection(sb, {
                onShow = function() end,
                onHide = function() end,
            })

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
            local showCount = 0
            local _, _, cat = registerLifecycleSection(sb, {
                onShow = function() showCount = showCount + 1 end,
            })

            navigateTo(cat)
            assert.are.equal(1, showCount)
        end)

        it("fires onHide when switching away from a tracked category", function()
            local sb = makeSB()
            local hideCount = 0
            local _, _, cat = registerLifecycleSection(sb, {
                onHide = function() hideCount = hideCount + 1 end,
            })

            local other = { _name = "Other" }
            navigateTo(cat)
            navigateTo(other)
            assert.are.equal(1, hideCount)
        end)

        it("fires onHide when SettingsPanel is hidden", function()
            local sb = makeSB()
            local hideCount = 0
            local _, _, cat = registerLifecycleSection(sb, {
                onHide = function() hideCount = hideCount + 1 end,
            })

            navigateTo(cat)
            SettingsPanel._fireScript("OnHide")
            assert.are.equal(1, hideCount)
        end)

        it("does not fire duplicate onShow when same category re-selected", function()
            local sb = makeSB()
            local showCount = 0
            local _, _, cat = registerLifecycleSection(sb, {
                onShow = function() showCount = showCount + 1 end,
            })

            navigateTo(cat)
            navigateTo(cat)
            assert.are.equal(1, showCount)
        end)

        it("does not fire callbacks for categories without lifecycle hooks", function()
            local sb = makeSB()
            local _, _, untracked = registerLifecycleSection(sb, {
                key = "plain",
                name = "Plain",
            })

            -- Should not error
            navigateTo(untracked)
        end)

        it("clears active category on panel hide so next open fires onShow", function()
            local sb = makeSB()
            local showCount = 0
            local _, _, cat = registerLifecycleSection(sb, {
                onShow = function() showCount = showCount + 1 end,
            })

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

            TestHelpers.LoadLibSettingsBuilder()
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
            local root = sb.GetRoot("Deferred")

            local showCount = 0
            root:Register({
                sections = {
                    {
                        key = "page1",
                        name = "Page1",
                        onShow = function() showCount = showCount + 1 end,
                        rows = {},
                    },
                },
            })

            -- Hooks not yet installed — deferred frame should exist
            assert.is_table(deferFrame)
            assert.is_false(lsb._pageLifecycleHooked)

            -- Simulate Blizzard_Settings loading
            createSettingsPanelMock()
            deferFrame:GetScript("OnEvent")(deferFrame, "ADDON_LOADED", "Blizzard_Settings")

            assert.is_true(lsb._pageLifecycleHooked)

            -- Hooks should now work
            local cat = root:GetSection("page1"):GetPage("main")._category
            SettingsPanel:SetCurrentCategory(cat)
            SettingsPanel:DisplayCategory(cat)
            assert.are.equal(1, showCount)
        end)
    end)

    ---------------------------------------------------------------------------
    -- SB.Custom integration: template, setting, and InitFrame pipeline
    ---------------------------------------------------------------------------
    describe("Dynamic layout rows", function()
        it("PageActions accepts action buttons through spec tables", function()
            local init = SB.PageActions({
                name = "TestSection",
                actions = {
                    { text = "Defaults", width = 100 },
                },
            })

            assert.are.equal(SB.SUBHEADER_TEMPLATE, init._template)
            assert.are.equal("TestSection", init.data.name)
            assert.are.equal("Defaults", init.data.actions[1].text)
        end)

        it("PageActions tooltips use the current GameTooltip SetText signature", function()
            TestHelpers.SetupGameTooltipStub()

            local init = SB.PageActions({
                name = "TestSection",
                actions = {
                    { text = "Add", tooltip = "Create entry" },
                },
            })
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.CreateFontString = function()
                return createScriptableFrame()
            end
            frame.SetShown = function(self, shown)
                self._shown = shown
            end

            assert.has_no.errors(function()
                init:InitFrame(frame)
            end)

            local button = assert(frame._lsbHeaderActionButtons[1])
            assert.has_no.errors(function()
                button:GetScript("OnEnter")(button)
            end)

            assert.are.equal("Create entry", _G.GameTooltip._title)
            assert.are.same({ r = 1, g = 1, b = 1, a = 1 }, _G.GameTooltip._titleColor)
            assert.are.equal(1, _G.GameTooltip._titleAlpha)
            assert.is_true(_G.GameTooltip._titleWrap)
        end)

        it("PageActions attach buttons to the page title row without rendering a duplicate header", function()
            local init = SB.PageActions({
                name = "TestSection",
                category = SB._currentSubcategory,
                actions = {
                    { text = "Defaults", width = 100 },
                },
            })

            assert.is_table(init)
            assert.is_true(init.data.hideTitle)
            assert.is_true(init.data.attachToCategoryHeader)
            assert.are.equal(1, init:GetExtent())
        end)

        it("InfoRow with function-backed value registers as refreshable", function()
            local category = SB._currentSubcategory
            SB.InfoRow({
                name = "Dynamic",
                value = function()
                    return "value"
                end,
            })

            assert.is_table(SB._categoryRefreshables[category])
            assert.are.equal(1, #SB._categoryRefreshables[category])
        end)

        it("root:Register dispatches list rows through SB.List", function()
            local called
            local originalList = SB.List
            SB.List = function(spec)
                called = spec
                return { _type = "list" }
            end

            SB.GetRoot("TestAddon"):Register({
                sections = {
                    {
                        key = "collectionPage",
                        name = "Collection Page",
                        rows = {
                            {
                                id = "items",
                                type = "list",
                                height = 200,
                                variant = "swatch",
                                items = function()
                                    return {}
                                end,
                            },
                        },
                    },
                },
            })

            SB.List = originalList

            assert.is_table(called)
            assert.are.equal(200, called.height)
            assert.are.equal("swatch", called.variant)
        end)

        it("page:Refresh reevaluates visible frames and dynamic refreshables", function()
            local frames = createSettingsPanelMock()
            local page = SB.GetRoot("TestAddon"):GetSection("testSection"):GetPage("main")
            local category = page._category
            local refreshed = 0
            local frame = createScriptableFrame()
            frame.EvaluateState = function(self)
                self._evaluated = true
            end

            frames[1] = frame
            SettingsPanel:SetCurrentCategory(category)

            SB._categoryRefreshables[category] = {
                {
                    _lsbActiveFrame = frame,
                    _lsbRefreshFrame = function(activeFrame)
                        refreshed = refreshed + 1
                        activeFrame._refreshed = true
                    end,
                },
            }

            page:Refresh()

            assert.are.equal(1, refreshed)
            assert.is_true(frame._evaluated)
            assert.is_true(frame._refreshed)
        end)

        it("List shows cached scroll widgets when a settings row is reused", function()
            local originalCreateFrame = _G.CreateFrame
            local originalCreateDataProvider = _G.CreateDataProvider
            local originalCreateView = _G.CreateScrollBoxListLinearView
            local originalScrollUtil = _G.ScrollUtil

            _G.CreateFrame = function(_, _, _, template)
                local frame = createScriptableFrame()
                frame._template = template
                frame.SetDataProvider = function(self, provider)
                    self._dataProvider = provider
                end
                return frame
            end
            _G.CreateDataProvider = function()
                return {
                    Flush = function() end,
                    Insert = function() end,
                }
            end
            _G.CreateScrollBoxListLinearView = function()
                return {
                    SetElementExtent = function() end,
                    SetElementInitializer = function() end,
                }
            end
            _G.ScrollUtil = {
                InitScrollBoxListWithScrollBar = function() end,
            }

            local init = SB.List({
                height = 80,
                variant = "swatch",
                items = function()
                    return {}
                end,
            })
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.SetShown = function(self, shown)
                self._shown = shown
            end

            init:InitFrame(frame)
            local scrollBox = assert(frame._lsbCollectionScrollBox)
            local scrollBar = assert(frame._lsbCollectionScrollBar)
            scrollBox:Hide()
            scrollBar:Hide()

            init:InitFrame(frame)

            assert.is_true(scrollBox:IsShown())
            assert.is_true(scrollBar:IsShown())

            _G.CreateFrame = originalCreateFrame
            _G.CreateDataProvider = originalCreateDataProvider
            _G.CreateScrollBoxListLinearView = originalCreateView
            _G.ScrollUtil = originalScrollUtil
        end)

        it("swatch list rows open the color callback from the swatch click script", function()
            local originalCreateFrame = _G.CreateFrame
            local originalCreateDataProvider = _G.CreateDataProvider
            local originalCreateView = _G.CreateScrollBoxListLinearView
            local originalScrollUtil = _G.ScrollUtil
            local clicked = 0
            local entered = 0

            _G.CreateFrame = function(frameType, name, parent, template)
                local frame = originalCreateFrame(frameType, name, parent, template)
                frame.SetDataProvider = function(self, provider)
                    self._dataProvider = provider
                end
                frame.SetColorRGB = function(self, r, g, b)
                    self._color = { r, g, b }
                end
                return frame
            end
            _G.CreateDataProvider = function()
                return {
                    Flush = function() end,
                    Insert = function() end,
                }
            end
            _G.CreateScrollBoxListLinearView = function()
                return {
                    SetElementExtent = function() end,
                    SetElementInitializer = function(self, _, fn)
                        self._initFn = fn
                    end,
                }
            end
            _G.ScrollUtil = {
                InitScrollBoxListWithScrollBar = function() end,
            }

            local init = SB.List({
                height = 80,
                variant = "swatch",
                items = function()
                    return {
                        {
                            label = "Spell",
                            icon = 1234,
                            onEnter = function()
                                entered = entered + 1
                            end,
                            color = {
                                value = { r = 0.1, g = 0.2, b = 0.3 },
                                onClick = function()
                                    clicked = clicked + 1
                                end,
                            },
                        },
                    }
                end,
            })
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.SetShown = function(self, shown)
                self._shown = shown
            end

            init:InitFrame(frame)

            local row = createScriptableFrame()
            row.CreateTexture = function()
                local texture = createScriptableFrame()
                texture.SetTexture = function(self, value)
                    self._texture = value
                end
                texture.GetTexture = function(self)
                    return self._texture
                end
                return texture
            end
            row.CreateFontString = function()
                local fontString = createScriptableFrame()
                fontString.SetFontObject = function() end
                return fontString
            end
            frame._lsbCollectionView._initFn(row, {
                preset = "swatch",
                item = init.data.items()[1],
            })

            local point, relativeTo, relativePoint, x, y = row._swatch:GetPoint(1)
            assert.is_true(row._mouseEnabled)
            assert.are.equal("LEFT", point)
            assert.are.equal(row, relativeTo)
            assert.are.equal("CENTER", relativePoint)
            assert.are.equal(-73, x)
            assert.are.equal(0, y)

            row:GetScript("OnEnter")(row)
            assert.are.equal(1, entered)

            assert.is_nil(row:GetScript("OnMouseUp"))
            row._swatch:GetScript("OnClick")(row._swatch, "LeftButton")

            assert.are.equal(1, clicked)

            _G.CreateFrame = originalCreateFrame
            _G.CreateDataProvider = originalCreateDataProvider
            _G.CreateScrollBoxListLinearView = originalCreateView
            _G.ScrollUtil = originalScrollUtil
        end)

        it("swatch list rows rebind the swatch click handler when a recycled row is reused", function()
            local originalCreateFrame = _G.CreateFrame
            local originalCreateDataProvider = _G.CreateDataProvider
            local originalCreateView = _G.CreateScrollBoxListLinearView
            local originalScrollUtil = _G.ScrollUtil
            local firstClicks = 0
            local secondClicks = 0

            _G.CreateFrame = function(frameType, name, parent, template)
                local frame = originalCreateFrame(frameType, name, parent, template)
                frame.SetDataProvider = function(self, provider)
                    self._dataProvider = provider
                end
                frame.SetColorRGB = function(self, r, g, b)
                    self._color = { r, g, b }
                end
                return frame
            end
            _G.CreateDataProvider = function()
                return {
                    Flush = function() end,
                    Insert = function() end,
                }
            end
            _G.CreateScrollBoxListLinearView = function()
                return {
                    SetElementExtent = function() end,
                    SetElementInitializer = function(self, _, fn)
                        self._initFn = fn
                    end,
                }
            end
            _G.ScrollUtil = {
                InitScrollBoxListWithScrollBar = function() end,
            }

            local init = SB.List({
                height = 80,
                variant = "swatch",
                items = function()
                    return {}
                end,
            })
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.SetShown = function(self, shown)
                self._shown = shown
            end

            init:InitFrame(frame)

            local row = createScriptableFrame()
            row.CreateTexture = function()
                local texture = createScriptableFrame()
                texture.SetTexture = function(self, value)
                    self._texture = value
                end
                texture.GetTexture = function(self)
                    return self._texture
                end
                return texture
            end
            row.CreateFontString = function()
                local fontString = createScriptableFrame()
                fontString.SetFontObject = function() end
                return fontString
            end

            frame._lsbCollectionView._initFn(row, {
                preset = "swatch",
                item = {
                    label = "First",
                    color = {
                        value = { r = 0.1, g = 0.2, b = 0.3 },
                        onClick = function()
                            firstClicks = firstClicks + 1
                        end,
                    },
                },
            })
            row._swatch:GetScript("OnClick")(row._swatch, "LeftButton")

            frame._lsbCollectionView._initFn(row, {
                preset = "swatch",
                item = {
                    label = "Second",
                    color = {
                        value = { r = 0.4, g = 0.5, b = 0.6 },
                        onClick = function()
                            secondClicks = secondClicks + 1
                        end,
                    },
                },
            })
            row._swatch:GetScript("OnClick")(row._swatch, "LeftButton")

            assert.are.equal(1, firstClicks)
            assert.are.equal(1, secondClicks)

            _G.CreateFrame = originalCreateFrame
            _G.CreateDataProvider = originalCreateDataProvider
            _G.CreateScrollBoxListLinearView = originalCreateView
            _G.ScrollUtil = originalScrollUtil
        end)

        it("editor list rows open the color callback from the swatch click script", function()
            local originalCreateFrame = _G.CreateFrame
            local originalCreateDataProvider = _G.CreateDataProvider
            local originalCreateView = _G.CreateScrollBoxListLinearView
            local originalScrollUtil = _G.ScrollUtil
            local clicked = 0

            _G.CreateFrame = function(frameType, name, parent, template)
                local frame = originalCreateFrame(frameType, name, parent, template)
                frame.SetDataProvider = function(self, provider)
                    self._dataProvider = provider
                end
                frame.SetColorRGB = function(self, r, g, b)
                    self._color = { r, g, b }
                end
                return frame
            end
            _G.CreateDataProvider = function()
                return {
                    Flush = function() end,
                    Insert = function() end,
                }
            end
            _G.CreateScrollBoxListLinearView = function()
                return {
                    SetElementExtent = function() end,
                    SetElementInitializer = function(self, _, fn)
                        self._initFn = fn
                    end,
                }
            end
            _G.ScrollUtil = {
                InitScrollBoxListWithScrollBar = function() end,
            }

            local row = createScriptableFrame()
            row.CreateTexture = function()
                return createScriptableFrame()
            end
            row.CreateFontString = function()
                local fontString = createScriptableFrame()
                fontString.SetFontObject = function() end
                return fontString
            end

            local item = {
                label = "Tick",
                fields = {},
                color = {
                    value = { r = 0.1, g = 0.2, b = 0.3 },
                    onClick = function()
                        clicked = clicked + 1
                    end,
                },
                remove = {
                    onClick = function() end,
                },
            }

            local init = SB.List({
                height = 80,
                variant = "editor",
                items = function()
                    return { item }
                end,
            })
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.SetShown = function(self, shown)
                self._shown = shown
            end

            init:InitFrame(frame)
            frame._lsbCollectionView._initFn(row, {
                preset = "editor",
                item = item,
            })

            row._swatch:GetScript("OnClick")(row._swatch, "LeftButton")

            assert.are.equal(1, clicked)

            _G.CreateFrame = originalCreateFrame
            _G.CreateDataProvider = originalCreateDataProvider
            _G.CreateScrollBoxListLinearView = originalCreateView
            _G.ScrollUtil = originalScrollUtil
        end)

        it("SectionList action rows apply icon button textures, click registration, and spacing", function()
            local originalCreateFrame = _G.CreateFrame

            local function attachButtonTextureState(frame, key)
                local texture = createScriptableFrame()
                texture.ClearAllPoints = function() end
                texture.SetAllPoints = function(self, owner)
                    self._allPoints = owner
                end
                texture.SetAlpha = function(self, alpha)
                    self._alpha = alpha
                end
                texture.GetTexture = function(self)
                    return self._texture
                end

                frame["Set" .. key .. "Texture"] = function(self, value)
                    self["_" .. key:lower() .. "TextureValue"] = value
                    texture._texture = value
                end
                frame["Get" .. key .. "Texture"] = function()
                    return texture
                end
            end

            _G.CreateFrame = function(...)
                local frame = originalCreateFrame(...)
                attachButtonTextureState(frame, "Normal")
                attachButtonTextureState(frame, "Pushed")
                attachButtonTextureState(frame, "Disabled")
                frame.CreateFontString = function()
                    local fontString = createScriptableFrame()
                    fontString.SetFontObject = function() end
                    return fontString
                end
                frame.CreateTexture = function()
                    local texture = createScriptableFrame()
                    texture.SetTexture = function(self, value)
                        self._texture = value
                    end
                    texture.GetTexture = function(self)
                        return self._texture
                    end
                    return texture
                end
                frame.SetHighlightTexture = function(self, value, blendMode)
                    self._highlightTextureValue = value
                    self._highlightBlendMode = blendMode
                    self._highlightTexture = self._highlightTexture or createScriptableFrame()
                    self._highlightTexture.ClearAllPoints = function() end
                    self._highlightTexture.SetAllPoints = function(texture, owner)
                        texture._allPoints = owner
                    end
                    self._highlightTexture.SetAlpha = function(texture, alpha)
                        texture._alpha = alpha
                    end
                    self._highlightTexture.GetTexture = function(texture)
                        return texture._texture
                    end
                    self._highlightTexture._texture = value
                end
                frame.GetHighlightTexture = function(self)
                    return self._highlightTexture
                end
                return frame
            end

            local init = SB.SectionList({
                height = 120,
                sections = function()
                    return {
                        {
                            key = "icons",
                            title = "Icons",
                            items = {
                                {
                                    label = "Spell",
                                    icon = 1234,
                                    actions = {
                                        up = {
                                            text = "^",
                                            width = 20,
                                            height = 20,
                                            enabled = false,
                                            buttonTextures = {
                                                normal = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_up_normal",
                                                pushed = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_up_down",
                                            },
                                        },
                                        down = {
                                            text = "v",
                                            width = 20,
                                            height = 20,
                                            enabled = true,
                                            buttonTextures = {
                                                normal = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_down_normal",
                                                pushed = "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_down_down",
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    }
                end,
            })
            local frame = createScriptableFrame()
            frame.Text = createScriptableFrame()
            frame.NewFeature = createScriptableFrame()
            frame.SetShown = function(self, shown)
                self._shown = shown
            end

            init:InitFrame(frame)

            local row = assert(frame._lsbSectionRowPools.icons[1])
            local upButton = assert(row._buttons.up)
            local downButton = assert(row._buttons.down)

            assert.are.equal("", upButton:GetText())
            assert.are.equal(
                "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_up_normal",
                upButton._normalTextureValue
            )
            assert.are.equal(
                "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_up_down",
                upButton._pushedTextureValue
            )
            assert.are.equal(
                "Interface\\AddOns\\EnhancedCooldownManager\\Media\\move_up_normal",
                upButton._disabledTextureValue
            )
            assert.are.equal("Interface\\Buttons\\ButtonHilight-Square", upButton._highlightTextureValue)
            assert.are.equal("ADD", upButton._highlightBlendMode)
            assert.are.equal(0.25, upButton:GetHighlightTexture()._alpha)
            assert.are.equal(0.4, upButton:GetAlpha())
            assert.is_false(upButton._enabled)
            assert.are.same({ "LeftButtonDown" }, upButton._registeredClicks)

            local point, relativeTo, relativePoint, x, y = upButton:GetPoint(1)
            assert.are.equal("RIGHT", point)
            assert.are.equal(row, relativeTo)
            assert.are.equal("RIGHT", relativePoint)
            assert.are.equal(-2, x)
            assert.are.equal(0, y)

            point, relativeTo, relativePoint, x, y = downButton:GetPoint(1)
            assert.are.equal("RIGHT", point)
            assert.are.equal(upButton, relativeTo)
            assert.are.equal("LEFT", relativePoint)
            assert.are.equal(-2, x)
            assert.are.equal(0, y)
            assert.are.same({ "LeftButtonDown" }, downButton._registeredClicks)

            _G.CreateFrame = originalCreateFrame
        end)

        it("SectionList modeInput footers reevaluate dynamic fields in place while typing", function()
            local originalCreateFrame = _G.CreateFrame
            local state = {
                kind = "spell",
                idText = "",
            }

            _G.CreateFrame = function(...)
                local frame = originalCreateFrame(...)
                frame.CreateFontString = function()
                    local fontString = createScriptableFrame()
                    fontString.SetFontObject = function() end
                    return fontString
                end
                frame.CreateTexture = function()
                    local texture = createScriptableFrame()
                    texture.SetTexture = function(self, value)
                        self._texture = value
                    end
                    texture.GetTexture = function(self)
                        return self._texture
                    end
                    return texture
                end
                return frame
            end

            local ok, err = pcall(function()
                local init = SB.SectionList({
                    height = 120,
                    sections = function()
                        return {
                            {
                                key = "dynamic",
                                title = "Dynamic",
                                items = {},
                                footer = {
                                    type = "modeInput",
                                    modeText = function()
                                        return state.kind == "spell" and "Spell" or "Item"
                                    end,
                                    inputText = function()
                                        return state.idText
                                    end,
                                    placeholder = function()
                                        return state.kind == "spell" and "Spell ID" or "Item ID"
                                    end,
                                    previewText = function()
                                        return state.idText ~= "" and (state.kind .. ":" .. state.idText) or ""
                                    end,
                                    submitEnabled = function()
                                        return state.idText ~= ""
                                    end,
                                    onTextChanged = function(text)
                                        state.idText = text
                                    end,
                                    onTabPressed = function()
                                        state.kind = state.kind == "spell" and "item" or "spell"
                                        return true
                                    end,
                                },
                            },
                        }
                    end,
                })
                local frame = createScriptableFrame()
                frame.Text = createScriptableFrame()
                frame.NewFeature = createScriptableFrame()
                frame.SetShown = function(self, shown)
                    self._shown = shown
                end

                init:InitFrame(frame)

                local trailerRow = assert(frame._lsbSectionTrailerRows.dynamic)
                local editBox = assert(trailerRow._editBox)
                editBox:SetFocus()
                trailerRow._lsbHasFocus = true
                editBox:SetText("12345")
                editBox:GetScript("OnTextChanged")(editBox)

                assert.are.equal("12345", state.idText)
                assert.are.equal("spell:12345", trailerRow._previewLabel:GetText())
                assert.is_true(editBox._focused)

                editBox:GetScript("OnTabPressed")()

                assert.are.equal("Item", trailerRow._modeButton:GetText())
                assert.are.equal("Item ID", trailerRow._placeholder:GetText())
                assert.is_true(editBox._focused)
                assert.is_true(editBox._highlighted)
            end)
            _G.CreateFrame = originalCreateFrame
            if not ok then
                error(err, 0)
            end
        end)
    end)

    describe("Custom control integration", function()
        it("passes the actual template name to CreateElementInitializer", function()
            local capturedTemplate
            local settings = Settings
            local origCEI = settings.CreateElementInitializer
            rawset(settings, "CreateElementInitializer", function(template, data)
                capturedTemplate = template
                return origCEI(template, data)
            end)

            SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
            })

            rawset(settings, "CreateElementInitializer", origCEI)
            assert.are.equal("LibLSMSettingsWidgets_FontPickerTemplate", capturedTemplate)
        end)

        it("attaches the setting so InitFrame can retrieve it via GetSetting", function()
            local init, setting = SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
            })

            assert.is_not_nil(init:GetSetting())
            assert.are.equal(setting, init:GetSetting())
        end)

        it("setting reads the current profile value", function()
            local _, setting = SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
            })

            assert.are.equal("Global Font", setting:GetValue())
        end)

        it("setting writes back to the profile", function()
            local _, setting = SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
            })

            setting:SetValue("NewFont")
            assert.are.equal("NewFont", addonNS.Addon.db.profile.global.font)
        end)

        it("initializer data contains name and tooltip", function()
            local init = SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
                tooltip = "Choose a font",
            })

            local data = init:GetData()
            assert.are.equal("Font Picker", data.name)
            assert.are.equal("Choose a font", data.tooltip)
        end)

        it("setting is retrievable so XML mixin Init can access it", function()
            local init, setting = SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
            })

            -- In the real WoW path, the settings framework creates a frame
            -- from the XML template (which applies the mixin and fires OnLoad),
            -- then calls frame:Init(initializer). The mixin's Init calls
            -- initializer:GetSetting() to bind the dropdown. This test verifies
            -- that the setting is attached and accessible on the initializer —
            -- the critical contract that the XML mixin relies on.
            assert.is_not_nil(init:GetSetting())
            assert.are.equal(setting, init:GetSetting())
            assert.are.equal("Global Font", setting:GetValue())
        end)

        it("root:Register dispatches custom type through SB.Custom", function()
            local capturedTemplate
            local settings = Settings
            local origCEI = settings.CreateElementInitializer
            rawset(settings, "CreateElementInitializer", function(template, data)
                capturedTemplate = template
                return origCEI(template, data)
            end)

            SB.GetRoot("TestAddon"):Register({
                sections = {
                    {
                        key = "testCustomSection",
                        name = "Test Custom Section",
                        path = "global",
                        rows = {
                            { id = "testHeader", type = "header", name = "Appearance" },
                            {
                                id = "fontPicker",
                                type = "custom",
                                path = "font",
                                name = "Font",
                                template = "LibLSMSettingsWidgets_FontPickerTemplate",
                            },
                        },
                    },
                },
            })

            rawset(settings, "CreateElementInitializer", origCEI)
            assert.are.equal("LibLSMSettingsWidgets_FontPickerTemplate", capturedTemplate)
        end)

        it("does not wrap or replace InitFrame on the initializer", function()
            local init = SB.Custom({
                path = "global.font",
                name = "Font Picker",
                template = "LibLSMSettingsWidgets_FontPickerTemplate",
            })

            -- A stock SettingsListElementInitializer from the stub has no
            -- InitFrame. If SB.Custom starts injecting one (e.g. for mixin
            -- injection), that's a regression — XML templates handle this.
            assert.is_nil(init.InitFrame)
        end)
    end)

    describe("root declarative API", function()
        it("GetRoot is idempotent and rejects conflicting names", function()
            local sb = createSB2("ROOTAPI1", "Root API")
            local rootA = sb.GetRoot("Root API")
            local rootB = sb.GetRoot("Root API")

            assert.are.equal(rootA, rootB)
            assert.has_error(function()
                sb.GetRoot("Other Root")
            end)
        end)

        it("registers a root page on the root category and rejects a second root page", function()
            local sb = createSB2("ROOTAPI2", "Root API")
            local root = sb.GetRoot("Root API")
            root:Register({
                page = {
                    key = "about",
                    rows = {
                        { type = "info", name = "Version", value = "1.0" },
                    },
                },
            })

            assert.are.equal("Root API", root:GetPage("about"):GetID())

            assert.has_error(function()
                root:Register({
                    page = {
                        key = "second",
                        rows = {
                            { type = "info", name = "Other", value = "2.0" },
                        },
                    },
                })
            end)
        end)

        it("flattens single-page sections and preserves path-bound settings", function()
            local sb = createSB2("ROOTAPI3", "Root API")
            local root = sb.GetRoot("Root API")
            local captured = TestHelpers.CollectSettings(function()
                root:Register({
                    sections = {
                        {
                            key = "general",
                            name = "General",
                            path = "global",
                            rows = {
                                {
                                    type = "checkbox",
                                    path = "hideWhenMounted",
                                    name = "Hide When Mounted",
                                },
                            },
                        },
                    },
                })
            end)

            local page = root:GetSection("general"):GetPage("main")
            local _, setting = next(captured)

            assert.are.equal("Root API.General", page:GetID())
            assert.is_true(setting:GetValue())
            setting:SetValue(false)
            assert.is_false(addonNS.Addon.db.profile.global.hideWhenMounted)
        end)

        it("nests multi-page sections and honors explicit nested display for single-page sections", function()
            local sb = createSB2("ROOTAPI4", "Root API")
            local root = sb.GetRoot("Root API")
            root:Register({
                sections = {
                    {
                        key = "multi",
                        name = "Multi",
                        pages = {
                            { key = "first", name = "First", rows = {} },
                            { key = "second", name = "Second", rows = {} },
                        },
                    },
                    {
                        key = "nested",
                        name = "Nested",
                        display = "nested",
                        rows = {},
                    },
                },
            })

            local second = root:GetSection("multi"):GetPage("second")
            local only = root:GetSection("nested"):GetPage("main")

            assert.are.equal("Root API.Multi.Second", second:GetID())
            assert.are.equal("Root API.Nested.Nested", only:GetID())
        end)

        it("injects page as first arg to onClick callbacks in declarative rows", function()
            local sb = createSB2("ROOTAPI5", "Root API")
            local root = sb.GetRoot("Root API")
            local receivedPage
            root:Register({
                sections = {
                    {
                        key = "clicks",
                        name = "Clicks",
                        rows = {
                            {
                                type = "button",
                                name = "Test",
                                buttonText = "Test",
                                onClick = function(pg) receivedPage = pg end,
                            },
                        },
                    },
                },
            })

            local page = root:GetSection("clicks"):GetPage("main")

            local layout = page._category:GetLayout()
            local inits = layout._initializers
            local buttonInit
            for i = #inits, 1, -1 do
                if inits[i]._type == "button" then
                    buttonInit = inits[i]
                    break
                end
            end
            assert.is_not_nil(buttonInit, "button initializer not found")
            buttonInit._onClick()
            assert.are.equal(page, receivedPage)
        end)

        it("injects page as third arg to onSet callbacks in declarative rows", function()
            local sb = createSB2("ROOTAPI6", "Root API")
            local root = sb.GetRoot("Root API")
            local receivedArgs = {}
            local captured = TestHelpers.CollectSettings(function()
                root:Register({
                    sections = {
                        {
                            key = "onset",
                            name = "OnSet",
                            path = "global",
                            rows = {
                                {
                                    type = "checkbox",
                                    path = "hideWhenMounted",
                                    name = "Hide When Mounted",
                                    onSet = function(value, _, pg)
                                        receivedArgs = { value = value, page = pg }
                                    end,
                                },
                            },
                        },
                    },
                })
            end)

            local page = root:GetSection("onset"):GetPage("main")
            local _, setting = next(captured)

            setting:SetValue(false)
            assert.are.equal(false, receivedArgs.value)
            assert.are.equal(page, receivedArgs.page)
        end)
    end)
end)
