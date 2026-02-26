-- LibSettingsBuilder: A standalone path-based settings builder for the
-- World of Warcraft Settings API.  Provides proxy controls, composite groups
-- and utility helpers.

local MAJOR, MINOR = "LibSettingsBuilder-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.EMBED_CANVAS_TEMPLATE = "LibSettingsBuilder_EmbedCanvasTemplate"
lib.SUB_HEADER_TEMPLATE = "LibSettingsBuilder_SubHeaderTemplate"

--------------------------------------------------------------------------------
-- SubHeader Mixin (global, shared across all instances)
-- Own mixin instead of SettingsListSectionHeaderMixin so the font object
-- cannot be overridden by Blizzard code.
--------------------------------------------------------------------------------

LibSettingsBuilder_SubHeaderMixin = LibSettingsBuilder_SubHeaderMixin or {}

function LibSettingsBuilder_SubHeaderMixin:Init(initializer)
    local name = initializer:GetData().name
    self.Title:SetText(name)
    self.Title:SetFontObject(GameFontHighlightSmall)
end

--------------------------------------------------------------------------------
-- EmbedCanvas Mixin (global, shared across all instances)
--------------------------------------------------------------------------------

LibSettingsBuilder_EmbedCanvasMixin = LibSettingsBuilder_EmbedCanvasMixin or {}

function LibSettingsBuilder_EmbedCanvasMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)
end

function LibSettingsBuilder_EmbedCanvasMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local canvas = initializer:GetData().canvas
    if not canvas then return end

    canvas:SetParent(self)
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", 0, 0)
    canvas:SetPoint("TOPRIGHT", 0, 0)
    canvas:SetHeight(initializer:GetExtent())
    canvas:Show()
end

--------------------------------------------------------------------------------
-- Slider editable-value hook (global, runs once per lib version)
--------------------------------------------------------------------------------

if not lib._sliderHookInstalled then
    local function setupSliderEditableValue()
        if not SettingsSliderControlMixin then return end

        local function findValueLabel(sliderWithSteppers)
            if sliderWithSteppers._label then return sliderWithSteppers._label end
            if sliderWithSteppers.RightText then return sliderWithSteppers.RightText end
            if sliderWithSteppers.Label then return sliderWithSteppers.Label end
            for i = 1, select("#", sliderWithSteppers:GetRegions()) do
                local region = select(i, sliderWithSteppers:GetRegions())
                if region and region:IsObjectType("FontString") then
                    return region
                end
            end
            return nil
        end

        hooksecurefunc(SettingsSliderControlMixin, "Init", function(self, initializer)
            local sliderWithSteppers = self.SliderWithSteppers
            if not sliderWithSteppers then return end

            local valueLabel = findValueLabel(sliderWithSteppers)
            if not valueLabel then return end

            if not self._lsbValueButton then
                local btn = CreateFrame("Button", nil, sliderWithSteppers)
                btn:SetAllPoints(valueLabel)
                btn:RegisterForClicks("LeftButtonDown")
                self._lsbValueButton = btn

                local editBox = CreateFrame("EditBox", nil, sliderWithSteppers, "InputBoxTemplate")
                editBox:SetAutoFocus(false)
                editBox:SetNumeric(false)
                editBox:SetSize(50, 20)
                editBox:SetPoint("CENTER", valueLabel, "CENTER")
                editBox:SetJustifyH("CENTER")
                editBox:Hide()
                self._lsbEditBox = editBox

                local function hideEditBox()
                    editBox:ClearFocus()
                    editBox:Hide()
                    valueLabel:Show()
                end

                local function applyValue()
                    local text = editBox:GetText()
                    local num = tonumber(text)
                    if num and self._lsbCurrentSetting then
                        local slider = sliderWithSteppers.Slider
                        local min, max = slider:GetMinMaxValues()
                        num = math.max(min, math.min(max, num))
                        local step = slider:GetValueStep()
                        if step and step > 0 then
                            num = math.floor(num / step + 0.5) * step
                        end
                        self._lsbCurrentSetting:SetValue(num)
                    end
                    hideEditBox()
                end

                editBox:SetScript("OnEnterPressed", applyValue)
                editBox:SetScript("OnEscapePressed", hideEditBox)
                editBox:SetScript("OnEditFocusLost", hideEditBox)

                btn:SetScript("OnClick", function()
                    local setting = self._lsbCurrentSetting
                    if not setting then return end
                    editBox:SetText(tostring(setting:GetValue()))
                    valueLabel:Hide()
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:HighlightText()
                end)
            end

            self._lsbCurrentSetting = initializer:GetSetting()
            self._lsbEditBox:Hide()
            valueLabel:Show()
        end)
    end

    setupSliderEditableValue()
    lib._sliderHookInstalled = true
end

--------------------------------------------------------------------------------
-- Factory
--------------------------------------------------------------------------------

--- Create a new SettingsBuilder instance.
---@param config table
---   Required fields:
---     getProfile     function() -> table
---     getDefaults    function() -> table
---     varPrefix      string            e.g. "ECM"
---     onChanged      function(spec, value) called after each setter
---     getNestedValue function(tbl, path) -> any
---     setNestedValue function(tbl, path, value)
---@return table builder instance with the full SB API
function lib:New(config)
    assert(config.getProfile, "LibSettingsBuilder: getProfile is required")
    assert(config.getDefaults, "LibSettingsBuilder: getDefaults is required")
    assert(config.varPrefix, "LibSettingsBuilder: varPrefix is required")
    assert(config.onChanged, "LibSettingsBuilder: onChanged is required")
    assert(config.getNestedValue, "LibSettingsBuilder: getNestedValue is required")
    assert(config.setNestedValue, "LibSettingsBuilder: setNestedValue is required")

    local SB = {}
    SB._rootCategory = nil
    SB._rootCategoryName = nil
    SB._currentSubcategory = nil
    SB._subcategories = {}
    SB._subcategoryNames = {}
    SB._layouts = {}
    SB._firstHeaderAdded = {}
    SB._pageEnabledSetting = nil

    SB.EMBED_CANVAS_TEMPLATE = lib.EMBED_CANVAS_TEMPLATE
    SB.SUB_HEADER_TEMPLATE = lib.SUB_HEADER_TEMPLATE

    ----------------------------------------------------------------------------
    -- Internal helpers
    ----------------------------------------------------------------------------

    local function defaultSliderFormatter(value)
        if value == math.floor(value) then
            return tostring(math.floor(value))
        end
        return string.format("%.1f", value)
    end

    local function getProfile()
        return config.getProfile()
    end

    local function getDefaults()
        return config.getDefaults()
    end

    local function makeVarName(path)
        return config.varPrefix .. "_" .. path:gsub("%.", "_")
    end

    local function resolveCategory(spec)
        return spec.category or SB._currentSubcategory or SB._rootCategory
    end

    local function postSet(spec, value)
        if spec.onSet then
            spec.onSet(value)
        end
        config.onChanged(spec, value)
    end

    local function setCanvasInteractive(frame, enabled)
        if frame.SetEnabled then
            frame:SetEnabled(enabled)
        end
        if frame.EnableMouse then
            frame:EnableMouse(enabled)
        end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do
                setCanvasInteractive(child, enabled)
            end
        end
    end

    local function isParentEnabled(spec)
        if not spec.parent then
            return true
        end

        if spec.parentCheck then
            return spec.parentCheck()
        end

        local setting = spec.parent:GetSetting()
        return setting and setting:GetValue()
    end

    local function isControlEnabled(spec)
        if SB._pageEnabledSetting and not spec._isModuleEnabled then
            if not SB._pageEnabledSetting:GetValue() then return false end
        end
        if spec.disabled and spec.disabled() then return false end
        return isParentEnabled(spec)
    end

    local function setInitializerInteractive(initializer, enabled)
        if initializer and initializer.SetEnabled then
            initializer:SetEnabled(enabled)
        end
    end

    local function applyCanvasState(canvas, enabled)
        if canvas.SetAlpha then
            canvas:SetAlpha(enabled and 1 or 0.5)
        end
        setCanvasInteractive(canvas, enabled)
    end

    local function applyModifiers(initializer, spec)
        if not initializer then return end

        if (SB._pageEnabledSetting and not spec._isModuleEnabled) or spec.disabled or spec.canvas or spec.parent then
            initializer:AddModifyPredicate(function()
                local enabled = isControlEnabled(spec)
                setInitializerInteractive(initializer, enabled)
                if spec.canvas then
                    applyCanvasState(spec.canvas, enabled)
                end
                return enabled
            end)

            local enabled = isControlEnabled(spec)
            setInitializerInteractive(initializer, enabled)
            if spec.canvas then
                applyCanvasState(spec.canvas, enabled)
            end
        end

        if spec.parent then
            local predicate = function()
                return isParentEnabled(spec)
            end
            initializer:SetParentInitializer(spec.parent, predicate)
        end

        if spec.hidden then
            initializer:AddShownPredicate(function()
                return not spec.hidden()
            end)
        end
    end

    local function colorTableToHex(tbl)
        if not tbl then return "FFFFFFFF" end
        return string.format("%02X%02X%02X%02X",
            math.floor((tbl.a or 1) * 255 + 0.5),
            math.floor((tbl.r or 1) * 255 + 0.5),
            math.floor((tbl.g or 1) * 255 + 0.5),
            math.floor((tbl.b or 1) * 255 + 0.5))
    end

    ----------------------------------------------------------------------------
    -- Category management
    ----------------------------------------------------------------------------

    function SB.CreateRootCategory(name)
        local category, layout = Settings.RegisterVerticalLayoutCategory(name)
        SB._rootCategory = category
        SB._rootCategoryName = name
        SB._layouts[category] = layout
        SB._currentSubcategory = nil
        SB._firstHeaderAdded = {}
        SB._pageEnabledSetting = nil
        return category
    end

    function SB.UseRootCategory()
        SB._currentSubcategory = SB._rootCategory
    end

    function SB.CreateSubcategory(name)
        local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(SB._rootCategory, name)
        SB._subcategories[name] = subcategory
        SB._subcategoryNames[subcategory] = name
        SB._layouts[subcategory] = layout
        SB._currentSubcategory = subcategory
        SB._pageEnabledSetting = nil
        return subcategory
    end

    function SB.CreateCanvasSubcategory(frame, name, parentCategory)
        local parent = parentCategory or SB._rootCategory
        local subcategory, layout = Settings.RegisterCanvasLayoutSubcategory(parent, frame, name)
        SB._subcategories[name] = subcategory
        SB._layouts[subcategory] = layout
        return subcategory
    end

    function SB.RegisterCategories()
        if SB._rootCategory then
            Settings.RegisterAddOnCategory(SB._rootCategory)
        end
    end

    function SB.GetRootCategoryID()
        return SB._rootCategory and SB._rootCategory:GetID()
    end

    function SB.GetSubcategoryID(name)
        local category = SB._subcategories[name]
        if not category then
            return nil
        end
        if type(category) == "table" and type(category.GetID) == "function" then
            return category:GetID()
        end
        return category
    end

    ----------------------------------------------------------------------------
    -- Path-based proxy controls
    ----------------------------------------------------------------------------

    function SB.PathCheckbox(spec)
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local val = config.getNestedValue(getProfile(), spec.path)
            if spec.getTransform then val = spec.getTransform(val) end
            return val
        end

        local function setter(value)
            if spec.setTransform then value = spec.setTransform(value) end
            config.setNestedValue(getProfile(), spec.path, value)
            postSet(spec, value)
        end

        local default = config.getNestedValue(getDefaults(), spec.path)
        if spec.getTransform then default = spec.getTransform(default) end

        local setting = Settings.RegisterProxySetting(cat, variable,
            Settings.VarType.Boolean, spec.name, default ~= nil and default or false, getter, setter)

        local initializer = Settings.CreateCheckbox(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.PathSlider(spec)
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local val = config.getNestedValue(getProfile(), spec.path)
            if spec.getTransform then val = spec.getTransform(val) end
            return val
        end

        local function setter(value)
            if spec.setTransform then value = spec.setTransform(value) end
            config.setNestedValue(getProfile(), spec.path, value)
            postSet(spec, value)
        end

        local default = config.getNestedValue(getDefaults(), spec.path)
        if spec.getTransform then default = spec.getTransform(default) end

        local setting = Settings.RegisterProxySetting(cat, variable,
            Settings.VarType.Number, spec.name, default or 0, getter, setter)

        local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter or defaultSliderFormatter)

        local initializer = Settings.CreateSlider(cat, setting, options, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.PathDropdown(spec)
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local val = config.getNestedValue(getProfile(), spec.path)
            if spec.getTransform then val = spec.getTransform(val) end
            return val
        end

        local function setter(value)
            if spec.setTransform then value = spec.setTransform(value) end
            config.setNestedValue(getProfile(), spec.path, value)
            postSet(spec, value)
        end

        local default = config.getNestedValue(getDefaults(), spec.path)
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
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.PathColor(spec)
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local tbl = config.getNestedValue(getProfile(), spec.path)
            return colorTableToHex(tbl)
        end

        local function setter(hexValue)
            local color = CreateColorFromHexString(hexValue)
            local tbl = { r = color.r, g = color.g, b = color.b, a = color.a }
            config.setNestedValue(getProfile(), spec.path, tbl)
            postSet(spec, tbl)
        end

        local defaultTbl = config.getNestedValue(getDefaults(), spec.path) or {}
        local defaultHex = colorTableToHex(defaultTbl)

        local setting = Settings.RegisterProxySetting(cat, variable,
            Settings.VarType.String, spec.name, defaultHex, getter, setter)

        local initializer = Settings.CreateColorSwatch(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    --- Creates a proxy setting backed by a custom frame template.
    --- The template's Init receives initializer data containing {setting, name, tooltip}.
    function SB.PathCustom(spec)
        assert(spec.template, "PathCustom: spec.template is required")
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local val = config.getNestedValue(getProfile(), spec.path)
            if spec.getTransform then val = spec.getTransform(val) end
            return val
        end

        local function setter(value)
            if spec.setTransform then value = spec.setTransform(value) end
            config.setNestedValue(getProfile(), spec.path, value)
            postSet(spec, value)
        end

        local default = config.getNestedValue(getDefaults(), spec.path)
        if spec.getTransform then default = spec.getTransform(default) end

        local setting = Settings.RegisterProxySetting(cat, variable,
            Settings.VarType.String, spec.name, default or "", getter, setter)

        local initializer = Settings.CreateElementInitializer(spec.template,
            { name = spec.name, tooltip = spec.tooltip })
        if initializer.SetSetting then
            initializer:SetSetting(setting)
        end

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    --- Unified path-based proxy control. Dispatches to the appropriate factory
    --- based on `spec.type`.
    ---   type = "checkbox" | "slider" | "dropdown" | "color" | "custom"
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
        elseif controlType == "custom" then
            return SB.PathCustom(spec)
        else
            error("PathControl: unknown type '" .. tostring(controlType) .. "'")
        end
    end

    ----------------------------------------------------------------------------
    -- Composite builders
    ----------------------------------------------------------------------------

    --- Module-level enabled checkbox. Requires spec.setModuleEnabled.
    function SB.ModuleEnabledCheckbox(moduleName, spec)
        assert(spec.setModuleEnabled, "ModuleEnabledCheckbox: spec.setModuleEnabled is required")
        local setModuleEnabled = spec.setModuleEnabled
        local originalOnSet = spec.onSet
        local merged = {}
        for k, v in pairs(spec) do merged[k] = v end
        merged._isModuleEnabled = true
        merged.onSet = function(value)
            setModuleEnabled(moduleName, value)
            if originalOnSet then originalOnSet(value) end
        end
        local init, setting = SB.PathCheckbox(merged)
        SB._pageEnabledSetting = setting
        return init, setting
    end

    function SB.SetPageEnabledSetting(setting)
        SB._pageEnabledSetting = setting
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

    --- Font override group.
    --- Optional spec fields:
    ---   fontValues        function() -> table     (choices for the dropdown)
    ---   fontFallback      function() -> string    (fallback font name)
    ---   fontSizeFallback  function() -> number    (fallback font size)
    ---   fontTemplate      string                  (custom template for the font picker)
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

        local fontSpec = {
            path = sectionPath .. ".font",
            name = spec.fontName or "Font",
            tooltip = spec.fontTooltip,
            category = spec.category,
            values = spec.fontValues,
            parent = enabledInit,
            parentCheck = function() return enabledSetting:GetValue() end,
            disabled = spec.disabled,
            hidden = spec.hidden,
            getTransform = function(value)
                if value then return value end
                if spec.fontFallback then return spec.fontFallback() end
                return nil
            end,
        }

        local fontInit
        if spec.fontTemplate then
            fontSpec.template = spec.fontTemplate
            fontInit = SB.PathCustom(fontSpec)
        else
            fontInit = SB.PathDropdown(fontSpec)
        end

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
                if value then return value end
                if spec.fontSizeFallback then return spec.fontSizeFallback() end
                return 11
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

    --- Positioning group.
    --- Required spec fields:
    ---   positionModes     table         value → label map
    ---   isAnchorModeFree  function(cfg) -> bool
    --- Optional spec fields:
    ---   applyPositionMode function(cfg, mode)
    ---   defaultBarWidth   number (default 250)
    function SB.PositioningGroup(configPath, spec)
        spec = spec or {}
        assert(spec.positionModes, "PositioningGroup: spec.positionModes is required")
        assert(spec.isAnchorModeFree, "PositioningGroup: spec.isAnchorModeFree is required")

        local modeInit, modeSetting = SB.PathDropdown({
            path = configPath .. ".anchorMode",
            name = spec.modeName or "Position Mode",
            tooltip = spec.modeTooltip,
            category = spec.category,
            values = spec.positionModes,
            parent = spec.parent,
            parentCheck = spec.parentCheck,
            disabled = spec.disabled,
            hidden = spec.hidden,
            onSet = function(value)
                if spec.applyPositionMode then
                    spec.applyPositionMode(
                        config.getNestedValue(getProfile(), configPath), value)
                end
            end,
        })

        local function isFreeMode()
            return spec.isAnchorModeFree(
                config.getNestedValue(getProfile(), configPath))
        end

        local defaultBarWidth = spec.defaultBarWidth or 250

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
                return value or defaultBarWidth
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

    ----------------------------------------------------------------------------
    -- Utility helpers
    ----------------------------------------------------------------------------

    function SB.Header(text, category)
        if text == "Display" then return nil end

        local cat = category or SB._currentSubcategory or SB._rootCategory

        if not SB._firstHeaderAdded[cat] then
            SB._firstHeaderAdded[cat] = true
            local catName = SB._subcategoryNames[cat] or (cat == SB._rootCategory and SB._rootCategoryName)
            if catName and text == catName then return nil end
        end

        local layout = SB._layouts[cat]
        local initializer = CreateSettingsListSectionHeaderInitializer(text)
        layout:AddInitializer(initializer)
        return initializer
    end

    function SB.SubHeader(text, category)
        local cat = category or SB._currentSubcategory or SB._rootCategory
        local layout = SB._layouts[cat]
        local initializer = Settings.CreateElementInitializer(lib.SUB_HEADER_TEMPLATE, { name = text })
        layout:AddInitializer(initializer)
        return initializer
    end

    function SB.EmbedCanvas(canvas, height, spec)
        spec = spec or {}
        local cat = spec.category or SB._currentSubcategory or SB._rootCategory

        local modifiers = {}
        for k, v in pairs(spec) do
            modifiers[k] = v
        end
        modifiers.canvas = canvas

        local initializer = Settings.CreateElementInitializer(lib.EMBED_CANVAS_TEMPLATE,
            { canvas = canvas })
        local extent = height or canvas:GetHeight()
        initializer.GetExtent = function() return extent end

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, modifiers)

        return initializer
    end

    function SB.Button(spec)
        local cat = spec.category or SB._currentSubcategory or SB._rootCategory

        local onClick = spec.onClick
        if spec.confirm then
            local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
            local originalClick = onClick
            onClick = function()
                StaticPopupDialogs["LSB_SETTINGS_CONFIRM"] = {
                    text = confirmText,
                    button1 = YES,
                    button2 = NO,
                    OnAccept = originalClick,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("LSB_SETTINGS_CONFIRM")
            end
        end

        local layout = SB._layouts[cat]
        local initializer = CreateSettingsButtonInitializer(
            spec.name, spec.buttonText or spec.name, onClick, spec.tooltip, true)
        layout:AddInitializer(initializer)
        applyModifiers(initializer, spec)

        return initializer
    end

    function SB.RegisterSection(nsTable, key, section)
        nsTable.OptionsSections = nsTable.OptionsSections or {}
        nsTable.OptionsSections[key] = section
        return section
    end

    return SB
end
