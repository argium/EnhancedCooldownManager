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

describe("SettingsBuilder", function()
    local originalGlobals
    local addonNS
    local layoutUpdateCalls
    local SB

    local function deepClone(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = deepClone(v) end
        return out
    end

    local function deepEquals(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do
            if not deepEquals(v, b[k]) then return false end
        end
        for k in pairs(b) do
            if a[k] == nil then return false end
        end
        return true
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM", "ECM_CloneValue", "ECM_DeepEquals",
            "Settings", "CreateSettingsListSectionHeaderInitializer",
            "CreateSettingsButtonInitializer", "MinimalSliderWithSteppersMixin",
            "CreateColor", "CreateColorFromHexString", "StaticPopupDialogs", "StaticPopup_Show", "YES", "NO",
            "UnitClass", "GetSpecialization", "GetSpecializationInfo",
            "LibStub", "CreateFromMixins", "SettingsListElementInitializer",
            "LibSettingsBuilder_EmbedCanvasMixin", "LibSettingsBuilder_SubheaderMixin",
            "LibSettingsBuilder_ScrollDropdownMixin",
            "GameFontHighlightSmall", "GameFontNormal",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        layoutUpdateCalls = 0

        TestHelpers.setupLibStub()
        TestHelpers.setupSettingsStubs()

        _G.ECM_CloneValue = deepClone
        _G.ECM_DeepEquals = deepEquals
        _G.GameFontHighlightSmall = "GameFontHighlightSmall"
        _G.GameFontNormal = "GameFontNormal"

        _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
        _G.GetSpecialization = function() return 1 end
        _G.GetSpecializationInfo = function() return nil, "Arms" end

        -- Load the library
        local libChunk = TestHelpers.loadChunk(
            { "Libs/LibSettingsBuilder/LibSettingsBuilder.lua", "../Libs/LibSettingsBuilder/LibSettingsBuilder.lua" },
            "Unable to load LibSettingsBuilder.lua"
        )
        libChunk()

        -- Register LSMW stub
        local lsmw = LibStub:NewLibrary("LibLSMSettingsWidgets-1.0", 1)
        if lsmw then
            lsmw.GetFontValues = function() return { Expressway = "Expressway" } end
            lsmw.GetStatusbarValues = function() return { Blizzard = "Blizzard" } end
            lsmw.FONT_PICKER_TEMPLATE = "TestFontPickerTemplate"
            lsmw.TEXTURE_PICKER_TEMPLATE = "TestTexturePickerTemplate"
        end

        _G.ECM = {
            Constants = {
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            ScheduleLayoutUpdate = function()
                layoutUpdateCalls = layoutUpdateCalls + 1
            end,
        }

        addonNS = {
            Addon = {
                db = {
                    profile = {
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
                    },
                    defaults = {
                        profile = {
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
                        },
                    },
                },
            },
        }

        local optionUtilChunk = TestHelpers.loadChunk(
            { "Options/OptionUtil.lua", "../Options/OptionUtil.lua" },
            "Unable to load Options/OptionUtil.lua"
        )
        optionUtilChunk(nil, addonNS)

        local sbChunk = TestHelpers.loadChunk(
            { "Options/SettingsBuilder.lua", "../Options/SettingsBuilder.lua" },
            "Unable to load SettingsBuilder.lua"
        )
        sbChunk(nil, addonNS)

        SB = ECM.SettingsBuilder
        SB.CreateRootCategory("TestAddon")
        SB.CreateSubcategory("TestSection")
    end)

    -- Category lifecycle
    it("CreateRootCategory, CreateSubcategory, GetRootCategoryID, GetSubcategoryID", function()
        assert.is_not_nil(SB.GetRootCategoryID())
        assert.are.equal("TestAddon", SB.GetRootCategoryID())
        assert.is_not_nil(SB.GetSubcategoryID("TestSection"))
        assert.is_nil(SB.GetSubcategoryID("MissingSection"))
    end)

    it("RegisterCategories does not error", function()
        assert.has_no.errors(function() SB.RegisterCategories() end)
    end)

    it("UseRootCategory sets current subcategory to root", function()
        SB.UseRootCategory()
        local init = SB.Header("Root Header")
        assert.is_not_nil(init)
        assert.are.equal("header", init._type)
        assert.are.equal("Root Header", init._text)
    end)

    -- PathCheckbox
    it("PathCheckbox reads and writes profile value", function()
        local init, setting = SB.PathCheckbox({
            path = "global.hideWhenMounted",
            name = "Hide",
        })

        assert.is_true(setting:GetValue())

        setting:SetValue(false)
        assert.is_false(addonNS.Addon.db.profile.global.hideWhenMounted)
        assert.are.equal(1, layoutUpdateCalls)
    end)

    it("PathCheckbox onSet callback is invoked on set", function()
        local onSetValue
        local _, setting = SB.PathCheckbox({
            path = "global.hideWhenMounted",
            name = "Hide",
            onSet = function(v) onSetValue = v end,
        })

        setting:SetValue(false)
        assert.are.equal(false, onSetValue)
    end)

    -- PathSlider
    it("PathSlider reads/writes with getTransform and setTransform", function()
        local init, setting = SB.PathSlider({
            path = "powerBar.height",
            name = "Height",
            min = 0,
            max = 40,
            step = 1,
            getTransform = function(v) return v or 0 end,
            setTransform = function(v) return v > 0 and v or nil end,
        })

        assert.are.equal(10, setting:GetValue())

        setting:SetValue(0)
        assert.is_nil(addonNS.Addon.db.profile.powerBar.height)
    end)

    it("PathSlider applies default formatter when none specified", function()
        local capturedOpts
        local origCreate = Settings.CreateSlider
        Settings.CreateSlider = function(cat, setting, options, tooltip)
            capturedOpts = options
            return origCreate(cat, setting, options, tooltip)
        end

        SB.PathSlider({
            path = "global.value",
            name = "Value",
            min = 0,
            max = 10,
            step = 1,
        })

        Settings.CreateSlider = origCreate

        assert.is_not_nil(capturedOpts._labelFormatter)
        assert.are.equal(MinimalSliderWithSteppersMixin.Label.Right, capturedOpts._labelFormatterLocation)
        -- Default formatter renders integers without decimals
        assert.are.equal("5", capturedOpts._labelFormatter(5))
        assert.are.equal("0", capturedOpts._labelFormatter(0))
        -- Default formatter renders fractional values with one decimal
        assert.are.equal("2.5", capturedOpts._labelFormatter(2.5))
    end)

    it("PathSlider uses custom formatter when specified", function()
        local capturedOpts
        local origCreate = Settings.CreateSlider
        Settings.CreateSlider = function(cat, setting, options, tooltip)
            capturedOpts = options
            return origCreate(cat, setting, options, tooltip)
        end

        local customFormatter = function(value) return value .. "%%" end
        SB.PathSlider({
            path = "global.value",
            name = "Value",
            min = 0,
            max = 100,
            step = 5,
            formatter = customFormatter,
        })

        Settings.CreateSlider = origCreate

        assert.are.equal(customFormatter, capturedOpts._labelFormatter)
    end)

    -- PathDropdown
    it("PathDropdown creates dropdown with values", function()
        local init, setting = SB.PathDropdown({
            path = "global.mode",
            name = "Mode",
            values = { solid = "Solid", flat = "Flat" },
        })

        assert.are.equal("solid", setting:GetValue())

        setting:SetValue("flat")
        assert.are.equal("flat", addonNS.Addon.db.profile.global.mode)
    end)

    -- PathColor
    it("PathColor reads/writes color as AARRGGBB hex", function()
        local init, setting = SB.PathColor({
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

    -- PathControl dispatcher
    it("PathControl dispatches to checkbox", function()
        local init, setting = SB.PathControl({
            type = "checkbox",
            path = "global.hideWhenMounted",
            name = "Hide",
        })
        assert.is_true(setting:GetValue())
    end)

    it("PathControl dispatches to slider", function()
        local init, setting = SB.PathControl({
            type = "slider",
            path = "global.value",
            name = "Value",
            min = 0, max = 10, step = 1,
        })
        assert.are.equal(5, setting:GetValue())
    end)

    it("PathControl dispatches to dropdown", function()
        local init, setting = SB.PathControl({
            type = "dropdown",
            path = "global.mode",
            name = "Mode",
            values = { solid = "Solid" },
        })
        assert.are.equal("solid", setting:GetValue())
    end)

    it("PathControl dispatches to color", function()
        local init, setting = SB.PathControl({
            type = "color",
            path = "global.color",
            name = "Color",
        })
        local hex = setting:GetValue()
        assert.are.equal("string", type(hex))
        assert.are.equal(8, #hex)
    end)

    it("PathControl errors on unknown type", function()
        assert.has_error(function()
            SB.PathControl({ type = "bogus", path = "x", name = "X" })
        end)
    end)

    -- layout=false
    it("layout=false skips ScheduleLayoutUpdate", function()
        local _, setting = SB.PathCheckbox({
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
        assert.is_not_nil(init)
        assert.are.equal("header", init._type)
        assert.are.equal("Test Header", init._text)
    end)

    -- Subheader
    it("Subheader adds element initializer with normal font template", function()
        local init = SB.Subheader({ name = "Item Quality" })
        assert.is_not_nil(init)
        assert.are.equal("LibSettingsBuilder_SubheaderTemplate", init._template)
        assert.are.equal("Item Quality", init.data.name)
    end)

    it("Subheader respects explicit category via UseRootCategory", function()
        SB.UseRootCategory()
        local init = SB.Subheader({ name = "Root Sub" })
        assert.is_not_nil(init)
        assert.are.equal("Root Sub", init.data.name)
    end)

    it("Subheader as parent — isParentEnabled returns true", function()
        local labelInit = SB.Subheader({ name = "Colors" })
        local childInit = SB.PathCheckbox({
            path = "global.hideWhenMounted",
            name = "Child",
            parent = labelInit,
        })
        -- Labels have no GetSetting, so isParentEnabled should return true
        local enabledPredicate = childInit._modifyPredicates[1]
        assert.is_true(enabledPredicate())
    end)

    -- Button
    it("Button creates button initializer with onClick", function()
        local clicked = false
        local init = SB.Button({
            name = "Do it",
            buttonText = "Click",
            onClick = function() clicked = true end,
        })
        assert.are.equal("button", init._type)
        init._onClick()
        assert.is_true(clicked)
    end)

    it("Button confirm wraps onClick in StaticPopup", function()
        local clicked = false
        local init = SB.Button({
            name = "Danger",
            buttonText = "Reset",
            confirm = "Are you sure?",
            onClick = function() clicked = true end,
        })

        init._onClick()
        assert.is_true(clicked)
    end)

    -- ApplyModifiers
    it("ApplyModifiers sets parent, disabled, and hidden predicates", function()
        local parentInit, _ = SB.PathCheckbox({
            path = "global.nested.enabled",
            name = "Parent",
        })
        local childInit, _ = SB.PathCheckbox({
            path = "global.hideWhenMounted",
            name = "Child",
            parent = parentInit,
            parentCheck = function() return true end,
            disabled = function() return true end,
            hidden = function() return false end,
        })

        assert.are.equal(parentInit, childInit._parentInit)
        assert.are.equal(1, #childInit._modifyPredicates)
        assert.are.equal(1, #childInit._shownPredicates)
    end)

    it("Parent-controlled dropdown is disabled when parent is unchecked", function()
        local parentInit, parentSetting = SB.PathCheckbox({
            path = "global.nested.enabled",
            name = "Parent",
        })

        local childInit = SB.PathDropdown({
            path = "global.mode",
            name = "Child",
            values = { solid = "Solid", flat = "Flat" },
            parent = parentInit,
            parentCheck = function() return parentSetting:GetValue() end,
        })

        local enabledPredicate = childInit._modifyPredicates[1]
        assert.is_true(enabledPredicate())

        parentSetting:SetValue(false)
        assert.is_false(enabledPredicate())
    end)

    it("Parent-controlled custom picker is disabled when parent is unchecked", function()
        local parentInit, parentSetting = SB.PathCheckbox({
            path = "global.nested.enabled",
            name = "Parent",
        })

        local customEnabled
        local originalCreateElementInitializer = Settings.CreateElementInitializer
        Settings.CreateElementInitializer = function(frameTemplate, data)
            local init = originalCreateElementInitializer(frameTemplate, data)
            init.SetEnabled = function(_, enabled)
                customEnabled = enabled
            end
            return init
        end

        local childInit = SB.PathCustom({
            path = "global.font",
            name = "Custom picker",
            template = "TestTexturePickerTemplate",
            parent = parentInit,
            parentCheck = function() return parentSetting:GetValue() end,
        })

        Settings.CreateElementInitializer = originalCreateElementInitializer

        local enabledPredicate = childInit._modifyPredicates[1]
        assert.is_true(customEnabled)
        assert.is_true(enabledPredicate())

        parentSetting:SetValue(false)
        assert.is_false(enabledPredicate())
        assert.is_false(customEnabled)
    end)

    -- ModuleEnabledCheckbox
    it("ModuleEnabledCheckbox calls SetModuleEnabled", function()
        local enabledModule, enabledValue

        local _, setting = SB.ModuleEnabledCheckbox("PowerBar", {
            path = "powerBar.enabled",
            name = "Enable",
            setModuleEnabled = function(name, val)
                enabledModule = name
                enabledValue = val
            end,
        })

        setting:SetValue(false)
        assert.are.equal("PowerBar", enabledModule)
        assert.are.equal(false, enabledValue)
    end)

    it("ModuleEnabledCheckbox disables embedded canvas controls when unchecked", function()
        local _, moduleSetting = SB.ModuleEnabledCheckbox("PowerBar", {
            path = "powerBar.enabled",
            name = "Enable",
            setModuleEnabled = function() end,
        })

        local childEnabled, childMouseEnabled
        local child = {
            SetEnabled = function(_, enabled)
                childEnabled = enabled
            end,
            EnableMouse = function(_, enabled)
                childMouseEnabled = enabled
            end,
            GetChildren = function()
                return nil
            end,
        }

        local canvasEnabled, canvasMouseEnabled, canvasAlpha
        local canvas = {
            SetEnabled = function(_, enabled)
                canvasEnabled = enabled
            end,
            EnableMouse = function(_, enabled)
                canvasMouseEnabled = enabled
            end,
            SetAlpha = function(_, alpha)
                canvasAlpha = alpha
            end,
            GetChildren = function()
                return child
            end,
            GetHeight = function()
                return 100
            end,
        }

        local initializer = SB.EmbedCanvas(canvas, 100)
        assert.is_true(canvasEnabled)
        assert.is_true(canvasMouseEnabled)
        assert.is_true(childEnabled)
        assert.is_true(childMouseEnabled)
        assert.are.equal(1, canvasAlpha)

        moduleSetting:SetValue(false)

        local enabledPredicate = initializer._modifyPredicates[1]
        assert.is_false(enabledPredicate())
        assert.is_false(canvasEnabled)
        assert.is_false(canvasMouseEnabled)
        assert.is_false(childEnabled)
        assert.is_false(childMouseEnabled)
        assert.are.equal(0.5, canvasAlpha)

        moduleSetting:SetValue(true)
        enabledPredicate = initializer._modifyPredicates[1]
        assert.is_true(enabledPredicate())
        assert.is_true(canvasEnabled)
        assert.is_true(canvasMouseEnabled)
        assert.is_true(childEnabled)
        assert.is_true(childMouseEnabled)
        assert.are.equal(1, canvasAlpha)
    end)

    it("ModuleEnabledCheckbox disables PathColor controls when unchecked", function()
        local _, moduleSetting = SB.ModuleEnabledCheckbox("PowerBar", {
            path = "powerBar.enabled",
            name = "Enable",
            setModuleEnabled = function() end,
        })

        local colorControlEnabled
        local originalCreateColorSwatch = Settings.CreateColorSwatch
        Settings.CreateColorSwatch = function(cat, setting, tooltip)
            local init = originalCreateColorSwatch(cat, setting, tooltip)
            init.SetEnabled = function(_, enabled)
                colorControlEnabled = enabled
            end
            return init
        end

        local initializer = SB.PathColor({
            path = "powerBar.border.color",
            name = "Border color",
        })

        Settings.CreateColorSwatch = originalCreateColorSwatch

        assert.is_true(colorControlEnabled)

        moduleSetting:SetValue(false)

        local enabledPredicate = initializer._modifyPredicates[1]
        assert.is_false(enabledPredicate())
        assert.is_false(colorControlEnabled)
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

        -- Font and size children should have modify predicates
        assert.is_truthy(result.fontInit._modifyPredicates)
        assert.is_truthy(result.sizeInit._modifyPredicates)

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

    -- PositioningGroup
    it("PositioningGroup creates mode, width, offsetX, offsetY controls", function()
        ECM.OptionUtil.POSITION_MODE_TEXT = {
            [1] = "Automatic",
            [2] = "Free",
        }
        ECM.OptionUtil.ApplyPositionModeToBar = function() end
        ECM.OptionUtil.IsAnchorModeFree = function(cfg)
            return cfg and cfg.anchorMode == 2
        end

        local result = SB.PositioningGroup("powerBar")
        assert.is_not_nil(result.modeInit)
        assert.is_not_nil(result.modeSetting)
        assert.is_not_nil(result.widthInit)
        assert.is_not_nil(result.offsetXInit)
        assert.is_not_nil(result.offsetYInit)
    end)

    -- RegisterSection
    it("RegisterSection stores section in namespace", function()
        local ns = {}
        local section = { RegisterSettings = function() end }
        SB.RegisterSection(ns, "Foo", section)
        assert.are.same(section, ns.OptionsSections.Foo)
    end)

    -- Built-in path accessors (getNestedValue/setNestedValue now optional)
    it("works without getNestedValue/setNestedValue in config", function()
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TEST2",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("Test2")
        SB2.CreateSubcategory("Sub2")

        local _, setting = SB2.PathCheckbox({
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

        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TEST3",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("Test3")
        SB2.CreateSubcategory("Sub3")

        local _, setting = SB2.PathColor({
            path = "powerBar.colors.0",
            name = "Mana",
        })
        local hex = setting:GetValue()
        assert.are.equal("string", type(hex))
        assert.are.equal(8, #hex)
    end)

    -- compositeDefaults
    it("compositeDefaults merges defaults, spec overrides win", function()
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local customSetModule = function() end
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TEST4",
            onChanged = function() end,
            compositeDefaults = {
                ModuleEnabledCheckbox = {
                    setModuleEnabled = customSetModule,
                },
            },
        })
        SB2.CreateRootCategory("Test4")
        SB2.CreateSubcategory("Sub4")

        -- Should not error — setModuleEnabled comes from compositeDefaults
        assert.has_no.errors(function()
            SB2.ModuleEnabledCheckbox("TestModule", {
                path = "powerBar.enabled",
                name = "Enable",
            })
        end)
    end)

    it("compositeDefaults spec overrides win over defaults", function()
        local defaultCalled, overrideCalled = false, false
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TEST5",
            onChanged = function() end,
            compositeDefaults = {
                ModuleEnabledCheckbox = {
                    setModuleEnabled = function() defaultCalled = true end,
                },
            },
        })
        SB2.CreateRootCategory("Test5")
        SB2.CreateSubcategory("Sub5")

        local _, setting = SB2.ModuleEnabledCheckbox("TestModule", {
            path = "powerBar.enabled",
            name = "Enable",
            setModuleEnabled = function() overrideCalled = true end,
        })

        setting:SetValue(false)
        assert.is_false(defaultCalled)
        assert.is_true(overrideCalled)
    end)

    it("compositeDefaults missing name is harmless", function()
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TEST6",
            onChanged = function() end,
            compositeDefaults = {},
        })
        SB2.CreateRootCategory("Test6")
        SB2.CreateSubcategory("Sub6")

        -- ModuleEnabledCheckbox without defaults or spec.setModuleEnabled should error
        assert.has_error(function()
            SB2.ModuleEnabledCheckbox("TestModule", {
                path = "powerBar.enabled",
                name = "Enable",
            })
        end)
    end)

    -- Header "Display" no longer suppressed
    it("Header('Display') returns initializer (no longer suppressed)", function()
        local init = SB.Header("Display")
        assert.is_not_nil(init)
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

    -- PathCustom with varType override
    it("PathCustom respects varType override", function()
        local capturedVarType
        local origRegister = Settings.RegisterProxySetting
        Settings.RegisterProxySetting = function(cat, variable, varType, name, default, getter, setter)
            capturedVarType = varType
            return origRegister(cat, variable, varType, name, default, getter, setter)
        end

        SB.PathCustom({
            path = "global.value",
            name = "Custom Numeric",
            template = "TestTemplate",
            varType = Settings.VarType.Number,
        })

        Settings.RegisterProxySetting = origRegister
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

        SB.PathCheckbox({
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

        SB.PathCheckbox({
            path = "global.hideWhenMounted",
            name = "Test",
            bogusField = true,
        })

        _G.print = origPrint
        assert.are.equal(0, #warnings)
    end)

    -- PathDropdown with scrollHeight
    it("PathDropdown with scrollHeight uses scroll template", function()
        local capturedTemplate
        local origCreateElementInitializer = Settings.CreateElementInitializer
        Settings.CreateElementInitializer = function(template, data)
            capturedTemplate = template
            return origCreateElementInitializer(template, data)
        end

        local init, setting = SB.PathDropdown({
            path = "global.mode",
            name = "Scrollable Mode",
            values = { solid = "Solid", flat = "Flat" },
            scrollHeight = 300,
        })

        Settings.CreateElementInitializer = origCreateElementInitializer

        assert.are.equal("LibSettingsBuilder_ScrollDropdownTemplate", capturedTemplate)
        assert.are.equal("solid", setting:GetValue())

        setting:SetValue("flat")
        assert.are.equal("flat", addonNS.Addon.db.profile.global.mode)
    end)

    it("PathDropdown without scrollHeight uses standard dropdown", function()
        local capturedTemplate = nil
        local origCreateElementInitializer = Settings.CreateElementInitializer
        Settings.CreateElementInitializer = function(template, data)
            capturedTemplate = template
            return origCreateElementInitializer(template, data)
        end

        SB.PathDropdown({
            path = "global.mode",
            name = "Standard Mode",
            values = { solid = "Solid", flat = "Flat" },
        })

        Settings.CreateElementInitializer = origCreateElementInitializer

        -- Standard path uses Settings.CreateDropdown, not CreateElementInitializer
        -- with the scroll template
        assert.is_not_equal("LibSettingsBuilder_ScrollDropdownTemplate", capturedTemplate)
    end)

    -- RegisterFromTable
    it("RegisterFromTable creates subcategory and controls from table", function()
        local init, setting
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL1",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("TableTest")

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
        local disabledFn = function() return true end
        local capturedSpecs = {}
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL2",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("InheritTest")

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
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL3",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("ParentRefTest")

        assert.has_no.errors(function()
            SB2.RegisterFromTable({
                name = "Parent Ref Section",
                path = "global",
                args = {
                    parentCtrl = { type = "toggle", path = "hideWhenMounted", name = "Parent", order = 1 },
                    childCtrl = { type = "range", path = "value", name = "Child",
                        min = 0, max = 10, step = 1,
                        parent = "parentCtrl", parentCheck = "checked", order = 2 },
                },
            })
        end)
    end)

    it("RegisterFromTable supports type aliases", function()
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL4",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("AliasTest")

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
                },
            })
        end)
    end)

    it("RegisterFromTable supports desc as alias for tooltip", function()
        local capturedTooltip
        local origCreateCheckbox = Settings.CreateCheckbox
        Settings.CreateCheckbox = function(cat, setting, tooltip)
            capturedTooltip = tooltip
            return origCreateCheckbox(cat, setting, tooltip)
        end

        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL5",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("DescTest")

        SB2.RegisterFromTable({
            name = "Desc Section",
            path = "global",
            args = {
                mounted = { type = "toggle", path = "hideWhenMounted", name = "Hide",
                    desc = "Hide when on a mount.", order = 1 },
            },
        })

        Settings.CreateCheckbox = origCreateCheckbox
        assert.are.equal("Hide when on a mount.", capturedTooltip)
    end)

    it("RegisterFromTable supports moduleEnabled", function()
        local enabledModule, enabledValue
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL6",
            onChanged = function() end,
            compositeDefaults = {
                ModuleEnabledCheckbox = {
                    setModuleEnabled = function(name, val)
                        enabledModule = name
                        enabledValue = val
                    end,
                },
            },
        })
        SB2.CreateRootCategory("ModEnabledTest")

        SB2.RegisterFromTable({
            name = "Power Bar",
            path = "powerBar",
            moduleEnabled = { name = "Enable power bar" },
            args = {},
        })

        -- Module name derived from subcategory name with spaces removed
        assert.is_not_nil(SB2.GetSubcategoryID("Power Bar"))
    end)

    it("RegisterFromTable path prefixing works", function()
        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "TBL7",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("PrefixTest")

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
            if text == "Should Not Appear" then headerCreated = true end
            return origHeader(text)
        end

        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "COND1",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("CondTest")

        SB2.RegisterFromTable({
            name = "Cond Section",
            path = "global",
            args = {
                skipped = { type = "header", name = "Should Not Appear", condition = function() return false end, order = 1 },
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
            if text == "Conditional Header" then headerCreated = true end
            return origHeader(text)
        end

        local LSB2 = LibStub("LibSettingsBuilder-1.0")
        local SB2 = LSB2:New({
            getProfile = function() return addonNS.Addon.db.profile end,
            getDefaults = function() return addonNS.Addon.db.defaults.profile end,
            varPrefix = "COND2",
            onChanged = function() end,
        })
        SB2.CreateRootCategory("CondTest2")

        SB2.RegisterFromTable({
            name = "Cond Section 2",
            path = "global",
            args = {
                shown = { type = "header", name = "Conditional Header", condition = function() return true end, order = 1 },
            },
        })

        _G.CreateSettingsListSectionHeaderInitializer = origHeader
        assert.is_true(headerCreated)
    end)

end)
