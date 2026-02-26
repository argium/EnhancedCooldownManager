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
            "LibSettingsBuilder_EmbedCanvasMixin",
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

    -- ColorPickerList
    it("ColorPickerList creates color swatches for each definition", function()
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
        assert.are.equal(100, results[1].initializer._lsbColorPickerWidth)
        assert.is_true(results[1].initializer._lsbAlignName)
        assert.are.equal(100, results[2].initializer._lsbColorPickerWidth)
        assert.is_true(results[2].initializer._lsbAlignName)
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

    -- IsPlayerClass
    it("IsPlayerClass checks UnitClass token", function()
        assert.is_true(SB.IsPlayerClass("WARRIOR"))
        assert.is_false(SB.IsPlayerClass("DEATHKNIGHT"))
    end)
end)
