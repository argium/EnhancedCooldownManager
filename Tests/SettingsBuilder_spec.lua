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
            "CreateColor", "StaticPopupDialogs", "StaticPopup_Show", "YES", "NO",
            "UnitClass", "GetSpecialization", "GetSpecializationInfo",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        layoutUpdateCalls = 0

        TestHelpers.setupSettingsStubs()

        _G.ECM_CloneValue = deepClone
        _G.ECM_DeepEquals = deepEquals

        _G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
        _G.GetSpecialization = function() return 1 end
        _G.GetSpecializationInfo = function() return nil, "Arms" end

        _G.ECM = {
            Constants = {
                ANCHORMODE_CHAIN = 1,
                ANCHORMODE_FREE = 2,
                DEFAULT_BAR_WIDTH = 300,
            },
            SharedMediaOptions = {
                GetFontValues = function()
                    return { Expressway = "Expressway" }
                end,
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

        local settingsBuilderChunk = TestHelpers.loadChunk(
            { "Options/SettingsBuilder.lua", "../Options/SettingsBuilder.lua" },
            "Unable to load Options/SettingsBuilder.lua"
        )
        settingsBuilderChunk(nil, addonNS)

        SB = ECM.SettingsBuilder
        SB.CreateRootCategory("TestAddon")
        SB.CreateSubcategory("TestSection")
    end)

    -- Category lifecycle
    it("CreateRootCategory, CreateSubcategory, GetCategoryID", function()
        assert.is_not_nil(SB.GetCategoryID())
        assert.are.equal("TestAddon", SB.GetCategoryID())
    end)

    it("RegisterCategories does not error", function()
        assert.has_no.errors(function() SB.RegisterCategories() end)
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
    it("PathColor reads/writes color via CreateColor", function()
        local init, setting = SB.PathColor({
            path = "global.color",
            name = "Color",
        })

        local c = setting:GetValue()
        assert.are.equal(0.1, c.r)
        assert.are.equal(0.2, c.g)
        assert.are.equal(0.3, c.b)

        setting:SetValue(CreateColor(0.4, 0.5, 0.6, 1))
        assert.are.same({ r = 0.4, g = 0.5, b = 0.6, a = 1 }, addonNS.Addon.db.profile.global.color)
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
        local c = setting:GetValue()
        assert.are.equal(0.1, c.r)
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

    -- ModuleEnabledCheckbox
    it("ModuleEnabledCheckbox calls SetModuleEnabled", function()
        local enabledModule, enabledValue
        ECM.OptionUtil.SetModuleEnabled = function(name, val)
            enabledModule = name
            enabledValue = val
        end

        local _, setting = SB.ModuleEnabledCheckbox("PowerBar", {
            path = "powerBar.enabled",
            name = "Enable",
        })

        setting:SetValue(false)
        assert.are.equal("PowerBar", enabledModule)
        assert.are.equal(false, enabledValue)
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
