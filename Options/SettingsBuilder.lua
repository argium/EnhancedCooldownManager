-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local SB = {}
SB._rootCategory = nil
SB._currentSubcategory = nil
SB._subcategories = {}

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

local function getProfile()
    return mod.db and mod.db.profile
end

local function getDefaults()
    return mod.db and mod.db.defaults and mod.db.defaults.profile
end

local function makeVarName(path)
    return "ECM_" .. path:gsub("%.", "_")
end

local function resolveCategory(spec)
    return spec.category or SB._currentSubcategory or SB._rootCategory
end

local function postSet(spec, value)
    if spec.onSet then
        spec.onSet(value)
    end
    if spec.layout ~= false then
        ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
    end
end

local function ApplyModifiers(initializer, spec)
    if not initializer then return end

    if spec.parent then
        local predicate = spec.parentCheck or function()
            local setting = spec.parent:GetSetting()
            return setting and setting:GetValue()
        end
        initializer:SetParentInitializer(spec.parent, predicate)
    end

    if spec.disabled then
        initializer:AddModifyPredicate(function()
            return not spec.disabled()
        end)
    end

    if spec.hidden then
        initializer:AddShownPredicate(function()
            return not spec.hidden()
        end)
    end
end

--------------------------------------------------------------------------------
-- Category management
--------------------------------------------------------------------------------

function SB.CreateRootCategory(name)
    local category = Settings.RegisterVerticalLayoutCategory(name)
    SB._rootCategory = category
    SB._currentSubcategory = nil
    return category
end

function SB.CreateSubcategory(name)
    local subcategory = Settings.RegisterVerticalLayoutSubcategory(SB._rootCategory, name)
    SB._subcategories[name] = subcategory
    SB._currentSubcategory = subcategory
    return subcategory
end

function SB.CreateCanvasSubcategory(frame, name)
    local subcategory = Settings.RegisterCanvasLayoutSubcategory(SB._rootCategory, frame, name)
    SB._subcategories[name] = subcategory
    return subcategory
end

function SB.RegisterCategories()
    if SB._rootCategory then
        Settings.RegisterAddOnCategory(SB._rootCategory)
    end
end

function SB.GetCategoryID()
    return SB._rootCategory and SB._rootCategory:GetID()
end

--------------------------------------------------------------------------------
-- Path-based proxy controls
--------------------------------------------------------------------------------

function SB.PathCheckbox(spec)
    local variable = makeVarName(spec.path)
    local cat = resolveCategory(spec)

    local function getter()
        local val = ECM.OptionUtil.GetNestedValue(getProfile(), spec.path)
        if spec.getTransform then val = spec.getTransform(val) end
        return val
    end

    local function setter(value)
        if spec.setTransform then value = spec.setTransform(value) end
        ECM.OptionUtil.SetNestedValue(getProfile(), spec.path, value)
        postSet(spec, value)
    end

    local default = ECM.OptionUtil.GetNestedValue(getDefaults(), spec.path)
    if spec.getTransform then default = spec.getTransform(default) end

    local setting = Settings.RegisterProxySetting(cat, variable,
        Settings.VarType.Boolean, spec.name, default ~= nil and default or false, getter, setter)

    local initializer = Settings.CreateCheckbox(cat, setting, spec.tooltip)
    ApplyModifiers(initializer, spec)

    return initializer, setting
end

function SB.PathSlider(spec)
    local variable = makeVarName(spec.path)
    local cat = resolveCategory(spec)

    local function getter()
        local val = ECM.OptionUtil.GetNestedValue(getProfile(), spec.path)
        if spec.getTransform then val = spec.getTransform(val) end
        return val
    end

    local function setter(value)
        if spec.setTransform then value = spec.setTransform(value) end
        ECM.OptionUtil.SetNestedValue(getProfile(), spec.path, value)
        postSet(spec, value)
    end

    local default = ECM.OptionUtil.GetNestedValue(getDefaults(), spec.path)
    if spec.getTransform then default = spec.getTransform(default) end

    local setting = Settings.RegisterProxySetting(cat, variable,
        Settings.VarType.Number, spec.name, default or 0, getter, setter)

    local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
    if spec.formatter then
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter)
    end

    local initializer = Settings.CreateSlider(cat, setting, options, spec.tooltip)
    ApplyModifiers(initializer, spec)

    return initializer, setting
end

function SB.PathDropdown(spec)
    local variable = makeVarName(spec.path)
    local cat = resolveCategory(spec)

    local function getter()
        local val = ECM.OptionUtil.GetNestedValue(getProfile(), spec.path)
        if spec.getTransform then val = spec.getTransform(val) end
        return val
    end

    local function setter(value)
        if spec.setTransform then value = spec.setTransform(value) end
        ECM.OptionUtil.SetNestedValue(getProfile(), spec.path, value)
        postSet(spec, value)
    end

    local default = ECM.OptionUtil.GetNestedValue(getDefaults(), spec.path)
    if spec.getTransform then default = spec.getTransform(default) end

    local varType = type(default) == "number"
        and Settings.VarType.Number
        or Settings.VarType.String

    local setting = Settings.RegisterProxySetting(cat, variable,
        varType, spec.name, default or "", getter, setter)

    local function optionsGenerator()
        local container = Settings.CreateControlTextContainer()
        local values = type(spec.values) == "function" and spec.values() or spec.values
        if values then
            for value, label in pairs(values) do
                container:Add(value, label)
            end
        end
        return container:GetData()
    end

    local initializer = Settings.CreateDropdown(cat, setting, optionsGenerator, spec.tooltip)
    ApplyModifiers(initializer, spec)

    return initializer, setting
end

function SB.PathColor(spec)
    local variable = makeVarName(spec.path)
    local cat = resolveCategory(spec)

    local function getter()
        local tbl = ECM.OptionUtil.GetNestedValue(getProfile(), spec.path)
        if not tbl then return CreateColor(1, 1, 1, 1) end
        return CreateColor(tbl.r or 1, tbl.g or 1, tbl.b or 1, tbl.a or 1)
    end

    local function setter(value)
        local tbl = { r = value.r, g = value.g, b = value.b, a = value.a }
        ECM.OptionUtil.SetNestedValue(getProfile(), spec.path, tbl)
        postSet(spec, tbl)
    end

    local defaultTbl = ECM.OptionUtil.GetNestedValue(getDefaults(), spec.path) or {}
    local defaultColor = CreateColor(
        defaultTbl.r or 1, defaultTbl.g or 1, defaultTbl.b or 1, defaultTbl.a or 1)

    local setting = Settings.RegisterProxySetting(cat, variable,
        Settings.VarType.Number, spec.name, defaultColor, getter, setter)

    local initializer = Settings.CreateColorSwatch(cat, setting, spec.tooltip)
    ApplyModifiers(initializer, spec)

    return initializer, setting
end

--- Unified path-based proxy control. Dispatches to the appropriate path
--- control factory based on `spec.type`.
---@param spec table Control specification; MUST contain a `type` field.
---   type = "checkbox" | "slider" | "dropdown" | "color"
function SB.PathControl(spec)
    local controlType = spec.type
    if controlType == "checkbox" then
        return SB.PathCheckbox(spec)
    elseif controlType == "slider" then
        return SB.PathSlider(spec)
    elseif controlType == "dropdown" then
        return SB.PathDropdown(spec)
    elseif controlType == "color" then
        return SB.PathColor(spec)
    else
        error("SB.PathControl: unknown type '" .. tostring(controlType) .. "'")
    end
end

--------------------------------------------------------------------------------
-- Composite builders
--------------------------------------------------------------------------------

function SB.ModuleEnabledCheckbox(moduleName, spec)
    local originalOnSet = spec.onSet
    local merged = {}
    for k, v in pairs(spec) do merged[k] = v end
    merged.onSet = function(value)
        ECM.OptionUtil.SetModuleEnabled(moduleName, value)
        if originalOnSet then originalOnSet(value) end
    end
    return SB.PathCheckbox(merged)
end

function SB.HeightOverrideSlider(sectionPath, spec)
    spec = spec or {}
    return SB.PathSlider({
        path = sectionPath .. ".height",
        name = spec.name or "Height Override",
        tooltip = spec.tooltip or "Override the default bar height. Set to 0 to use the global default.",
        min = spec.min or 0,
        max = spec.max or 40,
        step = spec.step or 1,
        category = spec.category,
        parent = spec.parent,
        parentCheck = spec.parentCheck,
        disabled = spec.disabled,
        hidden = spec.hidden,
        getTransform = function(value) return value or 0 end,
        setTransform = function(value) return value > 0 and value or nil end,
    })
end

function SB.FontOverrideGroup(sectionPath, spec)
    spec = spec or {}
    local overridePath = sectionPath .. ".overrideFont"

    local enabledInit, enabledSetting = SB.PathCheckbox({
        path = overridePath,
        name = spec.enabledName or "Override font",
        tooltip = spec.enabledTooltip or "Override the global font settings for this module.",
        category = spec.category,
        parent = spec.parent,
        parentCheck = spec.parentCheck,
        disabled = spec.disabled,
        hidden = spec.hidden,
        getTransform = function(value) return value == true end,
    })

    local fontInit = SB.PathDropdown({
        path = sectionPath .. ".font",
        name = spec.fontName or "Font",
        tooltip = spec.fontTooltip,
        category = spec.category,
        values = spec.fontValues or ECM.SharedMediaOptions.GetFontValues,
        parent = enabledInit,
        parentCheck = function() return enabledSetting:GetValue() end,
        disabled = spec.disabled,
        hidden = spec.hidden,
        getTransform = function(value)
            return value
                or ECM.OptionUtil.GetNestedValue(getProfile(), "global.font")
                or "Expressway"
        end,
    })

    local sizeInit = SB.PathSlider({
        path = sectionPath .. ".fontSize",
        name = spec.sizeName or "Font Size",
        tooltip = spec.sizeTooltip,
        category = spec.category,
        min = spec.sizeMin or 6,
        max = spec.sizeMax or 32,
        step = spec.sizeStep or 1,
        parent = enabledInit,
        parentCheck = function() return enabledSetting:GetValue() end,
        disabled = spec.disabled,
        hidden = spec.hidden,
        getTransform = function(value)
            return value
                or ECM.OptionUtil.GetNestedValue(getProfile(), "global.fontSize")
                or 11
        end,
    })

    return {
        enabledInit = enabledInit,
        enabledSetting = enabledSetting,
        fontInit = fontInit,
        sizeInit = sizeInit,
    }
end

function SB.BorderGroup(borderPath, spec)
    spec = spec or {}

    local enabledInit, enabledSetting = SB.PathCheckbox({
        path = borderPath .. ".enabled",
        name = spec.enabledName or "Show border",
        tooltip = spec.enabledTooltip,
        category = spec.category,
        parent = spec.parent,
        parentCheck = spec.parentCheck,
        disabled = spec.disabled,
        hidden = spec.hidden,
    })

    local thicknessInit = SB.PathSlider({
        path = borderPath .. ".thickness",
        name = spec.thicknessName or "Border width",
        tooltip = spec.thicknessTooltip,
        category = spec.category,
        min = spec.thicknessMin or 1,
        max = spec.thicknessMax or 10,
        step = spec.thicknessStep or 1,
        parent = enabledInit,
        parentCheck = function() return enabledSetting:GetValue() end,
        disabled = spec.disabled,
        hidden = spec.hidden,
    })

    local colorInit = SB.PathColor({
        path = borderPath .. ".color",
        name = spec.colorName or "Border color",
        tooltip = spec.colorTooltip,
        category = spec.category,
        hasAlpha = true,
        parent = enabledInit,
        parentCheck = function() return enabledSetting:GetValue() end,
        disabled = spec.disabled,
        hidden = spec.hidden,
    })

    return {
        enabledInit = enabledInit,
        enabledSetting = enabledSetting,
        thicknessInit = thicknessInit,
        colorInit = colorInit,
    }
end

function SB.ColorPickerList(basePath, defs, spec)
    spec = spec or {}
    local results = {}

    for _, def in ipairs(defs) do
        local path = basePath .. "." .. tostring(def.key)
        local init, setting = SB.PathColor({
            path = path,
            name = def.name,
            tooltip = def.tooltip,
            category = spec.category,
            hasAlpha = def.hasAlpha,
            parent = spec.parent,
            parentCheck = spec.parentCheck,
            disabled = spec.disabled,
            hidden = spec.hidden,
        })
        results[#results + 1] = { key = def.key, initializer = init, setting = setting }
    end

    return results
end

function SB.PositioningGroup(configPath, spec)
    spec = spec or {}

    local modeInit, modeSetting = SB.PathDropdown({
        path = configPath .. ".anchorMode",
        name = spec.modeName or "Position Mode",
        tooltip = spec.modeTooltip,
        category = spec.category,
        values = ECM.OptionUtil.POSITION_MODE_TEXT,
        parent = spec.parent,
        parentCheck = spec.parentCheck,
        disabled = spec.disabled,
        hidden = spec.hidden,
        onSet = function(value)
            ECM.OptionUtil.ApplyPositionModeToBar(
                ECM.OptionUtil.GetNestedValue(getProfile(), configPath), value)
        end,
    })

    local function isFreeMode()
        return ECM.OptionUtil.IsAnchorModeFree(
            ECM.OptionUtil.GetNestedValue(getProfile(), configPath))
    end

    local widthInit = SB.PathSlider({
        path = configPath .. ".width",
        name = spec.widthName or "Width",
        tooltip = spec.widthTooltip or "Width when free positioning is enabled.",
        category = spec.category,
        min = spec.widthMin or 100,
        max = spec.widthMax or 600,
        step = spec.widthStep or 1,
        parent = modeInit,
        parentCheck = isFreeMode,
        disabled = spec.disabled,
        hidden = spec.hidden,
        getTransform = function(value)
            return value or ECM.Constants.DEFAULT_BAR_WIDTH
        end,
    })

    local offsetXInit
    if spec.includeOffsetX ~= false then
        offsetXInit = SB.PathSlider({
            path = configPath .. ".offsetX",
            name = spec.offsetXName or "Offset X",
            tooltip = spec.offsetXTooltip or "Horizontal offset when free positioning is enabled.",
            category = spec.category,
            min = -800,
            max = 800,
            step = 1,
            parent = modeInit,
            parentCheck = isFreeMode,
            disabled = spec.disabled,
            hidden = spec.hidden,
            getTransform = function(value) return value or 0 end,
            setTransform = function(value) return value ~= 0 and value or nil end,
        })
    end

    local offsetYInit = SB.PathSlider({
        path = configPath .. ".offsetY",
        name = spec.offsetYName or "Offset Y",
        tooltip = spec.offsetYTooltip or "Vertical offset when free positioning is enabled.",
        category = spec.category,
        min = -800,
        max = 800,
        step = 1,
        parent = modeInit,
        parentCheck = isFreeMode,
        disabled = spec.disabled,
        hidden = spec.hidden,
        getTransform = function(value) return value or 0 end,
        setTransform = function(value) return value ~= 0 and value or nil end,
    })

    return {
        modeInit = modeInit,
        modeSetting = modeSetting,
        widthInit = widthInit,
        offsetXInit = offsetXInit,
        offsetYInit = offsetYInit,
    }
end

--------------------------------------------------------------------------------
-- Utility helpers
--------------------------------------------------------------------------------

function SB.Header(text, category)
    local cat = category or SB._currentSubcategory or SB._rootCategory
    local layout = cat:GetLayout()
    local initializer = CreateSettingsListSectionHeaderInitializer(text)
    layout:AddInitializer(initializer)
    return initializer
end

function SB.Button(spec)
    local cat = spec.category or SB._currentSubcategory or SB._rootCategory

    local onClick = spec.onClick
    if spec.confirm then
        local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
        local originalClick = onClick
        onClick = function()
            StaticPopupDialogs["ECM_SETTINGS_CONFIRM"] = {
                text = confirmText,
                button1 = YES,
                button2 = NO,
                OnAccept = originalClick,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
            StaticPopup_Show("ECM_SETTINGS_CONFIRM")
        end
    end

    local layout = cat:GetLayout()
    local initializer = CreateSettingsButtonInitializer(
        spec.name, spec.buttonText or spec.name, onClick, spec.tooltip, true)
    layout:AddInitializer(initializer)
    ApplyModifiers(initializer, spec)

    return initializer
end

--- Helper to determine if the player is a specific class.
function SB.IsPlayerClass(classToken)
    local _, className = UnitClass("player")
    return className == classToken
end

--- Section registration helper (for page modules to register themselves with Options.lua).
function SB.RegisterSection(nsTable, key, section)
    nsTable.OptionsSections = nsTable.OptionsSections or {}
    nsTable.OptionsSections[key] = section
    return section
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

ECM.SettingsBuilder = SB
