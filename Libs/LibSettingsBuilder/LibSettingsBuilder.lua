-- LibSettingsBuilder: A standalone path-based settings builder for the
-- World of Warcraft Settings API.  Provides proxy controls, composite groups
-- and utility helpers.

local MAJOR, MINOR = "LibSettingsBuilder-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

lib.EMBED_CANVAS_TEMPLATE = "LibSettingsBuilder_EmbedCanvasTemplate"
lib.LABEL_TEMPLATE = "LibSettingsBuilder_LabelTemplate"
lib.SCROLL_DROPDOWN_TEMPLATE = "LibSettingsBuilder_ScrollDropdownTemplate"

--------------------------------------------------------------------------------
-- Label Mixin (global, shared across all instances)
-- Own mixin instead of SettingsListSectionHeaderMixin so the font object
-- cannot be overridden by Blizzard code.
--------------------------------------------------------------------------------

LibSettingsBuilder_LabelMixin = LibSettingsBuilder_LabelMixin or {}

function LibSettingsBuilder_LabelMixin:Init(initializer)
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
-- ScrollDropdown Mixin (global, shared across all instances)
-- Minimal scroll-enabled dropdown: SetScrollMode + CreateRadio per option.
-- Unlike LibEQOL's 264-line version, this handles only simple value→label
-- pairs without option normalization, grid modes, or custom generators.
--------------------------------------------------------------------------------

LibSettingsBuilder_ScrollDropdownMixin = CreateFromMixins(SettingsDropdownControlMixin)

function LibSettingsBuilder_ScrollDropdownMixin:OnLoad()
    SettingsDropdownControlMixin.OnLoad(self)
end

function LibSettingsBuilder_ScrollDropdownMixin:Init(initializer)
    if not initializer or not initializer.GetData then return end
    self.initializer = initializer
    self.lsbData = initializer:GetData() or {}
    SettingsDropdownControlMixin.Init(self, initializer)
end

function LibSettingsBuilder_ScrollDropdownMixin:GetSetting()
    if self.initializer and self.initializer.GetSetting then
        return self.initializer:GetSetting()
    end
    return self.lsbData and self.lsbData.setting or nil
end

function LibSettingsBuilder_ScrollDropdownMixin:RefreshDropdownText(value)
    local dropdown = self.Control and self.Control.Dropdown
    if not dropdown then return end

    local setting = self:GetSetting()
    local currentValue = value
    if currentValue == nil and setting and setting.GetValue then
        currentValue = setting:GetValue()
    end

    local values = self.lsbData and self.lsbData.values
    if type(values) == "function" then values = values() end
    local text = values and values[currentValue] or tostring(currentValue or "")

    if dropdown.OverrideText then
        dropdown:OverrideText(text)
    elseif dropdown.SetText then
        dropdown:SetText(text)
    end
end

-- Avoid regenerating the dropdown menu on value changes when using scroll mode.
function LibSettingsBuilder_ScrollDropdownMixin:SetValue(value)
    self:RefreshDropdownText(value)
end

function LibSettingsBuilder_ScrollDropdownMixin:InitDropdown()
    local setting = self:GetSetting()
    local data = self.lsbData or {}
    local scrollHeight = data.scrollHeight or 200

    local dropdown = self.Control and self.Control.Dropdown
    if not dropdown or not setting then return end

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(scrollHeight)

        local values = data.values
        if type(values) == "function" then values = values() end
        if not values then return end

        for optValue, label in pairs(values) do
            rootDescription:CreateRadio(label, function()
                return setting:GetValue() == optValue
            end, function()
                setting:SetValue(optValue)
                self:RefreshDropdownText(optValue)
            end, optValue)
        end
    end)

    self:RefreshDropdownText()
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

--------------------------------------------------------------------------------
-- Built-in dot-path table accessors (used when config doesn't provide them)
--------------------------------------------------------------------------------

local function defaultGetNestedValue(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then return nil end
        current = current[tonumber(segment) or segment]
    end
    return current
end

local function defaultSetNestedValue(tbl, path, value)
    local keys = {}
    for segment in path:gmatch("[^.]+") do keys[#keys + 1] = tonumber(segment) or segment end
    local current = tbl
    for i = 1, #keys - 1 do
        if current[keys[i]] == nil then current[keys[i]] = {} end
        current = current[keys[i]]
    end
    current[keys[#keys]] = value
end

--- Create a new SettingsBuilder instance.
---@param config table
---   Required fields:
---     getProfile     function() -> table
---     getDefaults    function() -> table
---     varPrefix      string            e.g. "ECM"
---     onChanged      function(spec, value) called after each setter
---   Optional fields:
---     getNestedValue function(tbl, path) -> any   (default: built-in dot-path with tonumber)
---     setNestedValue function(tbl, path, value)    (default: built-in dot-path with tonumber)
---     compositeDefaults table keyed by composite function name
---@return table builder instance with the full SB API
function lib:New(config)
    assert(config.getProfile, "LibSettingsBuilder: getProfile is required")
    assert(config.getDefaults, "LibSettingsBuilder: getDefaults is required")
    assert(config.varPrefix, "LibSettingsBuilder: varPrefix is required")
    assert(config.onChanged, "LibSettingsBuilder: onChanged is required")

    config.getNestedValue = config.getNestedValue or defaultGetNestedValue
    config.setNestedValue = config.setNestedValue or defaultSetNestedValue

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
    SB.LABEL_TEMPLATE = lib.LABEL_TEMPLATE
    SB.SCROLL_DROPDOWN_TEMPLATE = lib.SCROLL_DROPDOWN_TEMPLATE

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

    local function getNestedValue(tbl, path)
        return config.getNestedValue(tbl, path)
    end

    local function setNestedValue(tbl, path, value)
        return config.setNestedValue(tbl, path, value)
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

    --- Consolidates the getter/setter/default/transform/register boilerplate
    --- shared by PathCheckbox, PathSlider, PathDropdown, and PathCustom.
    local function makeProxySetting(spec, varType, defaultFallback)
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local val = getNestedValue(getProfile(), spec.path)
            if spec.getTransform then val = spec.getTransform(val) end
            return val
        end

        local function setter(value)
            if spec.setTransform then value = spec.setTransform(value) end
            setNestedValue(getProfile(), spec.path, value)
            postSet(spec, value)
        end

        local default = getNestedValue(getDefaults(), spec.path)
        if spec.getTransform then default = spec.getTransform(default) end

        local setting = Settings.RegisterProxySetting(cat, variable,
            varType, spec.name, default ~= nil and default or defaultFallback, getter, setter)

        return setting, cat
    end

    --- Copies inherited modifier keys from a composite spec onto a child spec
    --- when the child hasn't set them explicitly.
    local MODIFIER_KEYS = { "category", "parent", "parentCheck", "disabled", "hidden", "layout" }
    local function propagateModifiers(target, source)
        for _, key in ipairs(MODIFIER_KEYS) do
            if target[key] == nil then target[key] = source[key] end
        end
    end

    --- Merges compositeDefaults for the given composite function name onto spec.
    --- Spec values win over defaults.
    local function mergeCompositeDefaults(functionName, spec)
        local defaults = config.compositeDefaults and config.compositeDefaults[functionName]
        if not defaults then return spec or {} end
        local merged = {}
        for k, v in pairs(defaults) do merged[k] = v end
        if spec then for k, v in pairs(spec) do merged[k] = v end end
        return merged
    end

    ----------------------------------------------------------------------------
    -- Debug spec validation (active only when LSB_DEBUG is truthy)
    ----------------------------------------------------------------------------

    local COMMON_SPEC_FIELDS = {
        path = true, name = true, tooltip = true, category = true,
        onSet = true, getTransform = true, setTransform = true,
        parent = true, parentCheck = true, disabled = true, hidden = true,
        layout = true, _isModuleEnabled = true, type = true, desc = true,
    }

    local EXTRA_FIELDS_BY_TYPE = {
        checkbox = {},
        slider = { min = true, max = true, step = true, formatter = true },
        dropdown = { values = true, scrollHeight = true },
        color = {},
        custom = { template = true, varType = true },
    }

    local function validateSpecFields(controlType, spec)
        if not LSB_DEBUG then return end
        local allowed = EXTRA_FIELDS_BY_TYPE[controlType]
        if not allowed then return end
        for key in pairs(spec) do
            if not COMMON_SPEC_FIELDS[key] and not allowed[key] then
                print("|cffFF8800LibSettingsBuilder WARNING:|r Unknown spec field '"
                    .. tostring(key) .. "' on " .. controlType
                    .. " control '" .. tostring(spec.name or spec.path) .. "'")
            end
        end
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

        if not spec.parent.GetSetting then return true end
        local setting = spec.parent:GetSetting()
        if not setting then return true end
        return setting:GetValue()
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
        validateSpecFields("checkbox", spec)
        local setting, cat = makeProxySetting(spec, Settings.VarType.Boolean, false)
        local initializer = Settings.CreateCheckbox(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)
        return initializer, setting
    end

    function SB.PathSlider(spec)
        validateSpecFields("slider", spec)
        local setting, cat = makeProxySetting(spec, Settings.VarType.Number, 0)

        local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter or defaultSliderFormatter)

        local initializer = Settings.CreateSlider(cat, setting, options, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.PathDropdown(spec)
        validateSpecFields("dropdown", spec)
        local cat = resolveCategory(spec)
        local default = getNestedValue(getDefaults(), spec.path)
        if spec.getTransform then default = spec.getTransform(default) end

        local varType = type(default) == "number"
            and Settings.VarType.Number
            or Settings.VarType.String

        local setting = makeProxySetting(spec, varType, "")

        if spec.scrollHeight then
            -- Scroll-enabled dropdown using the built-in scroll template
            local initializer = Settings.CreateElementInitializer(
                lib.SCROLL_DROPDOWN_TEMPLATE,
                { setting = setting, values = spec.values, scrollHeight = spec.scrollHeight,
                  name = spec.name, tooltip = spec.tooltip })
            if initializer.SetSetting then
                initializer:SetSetting(setting)
            end
            Settings.RegisterInitializer(cat, initializer)
            applyModifiers(initializer, spec)
            return initializer, setting
        end

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
        validateSpecFields("color", spec)
        local variable = makeVarName(spec.path)
        local cat = resolveCategory(spec)

        local function getter()
            local tbl = getNestedValue(getProfile(), spec.path)
            return colorTableToHex(tbl)
        end

        local function setter(hexValue)
            local color = CreateColorFromHexString(hexValue)
            local tbl = { r = color.r, g = color.g, b = color.b, a = color.a }
            setNestedValue(getProfile(), spec.path, tbl)
            postSet(spec, tbl)
        end

        local defaultTbl = getNestedValue(getDefaults(), spec.path) or {}
        local defaultHex = colorTableToHex(defaultTbl)

        local setting = Settings.RegisterProxySetting(cat, variable,
            Settings.VarType.String, spec.name, defaultHex, getter, setter)

        -- Note: Settings.CreateColorSwatch does not support a hasAlpha parameter.
        -- Alpha channel selection is not available through the Blizzard Settings API.
        local initializer = Settings.CreateColorSwatch(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    --- Creates a proxy setting backed by a custom frame template.
    --- The template's Init receives initializer data containing {setting, name, tooltip}.
    function SB.PathCustom(spec)
        validateSpecFields("custom", spec)
        assert(spec.template, "PathCustom: spec.template is required")
        local setting, cat = makeProxySetting(spec, spec.varType or Settings.VarType.String, "")

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

    --- Module-level enabled checkbox. Requires spec.setModuleEnabled (can come from compositeDefaults).
    function SB.ModuleEnabledCheckbox(moduleName, spec)
        spec = mergeCompositeDefaults("ModuleEnabledCheckbox", spec)
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
        local childSpec = {
            path = sectionPath .. ".height",
            name = spec.name or "Height Override",
            tooltip = spec.tooltip or "Override the default bar height. Set to 0 to use the global default.",
            min = spec.min or 0,
            max = spec.max or 40,
            step = spec.step or 1,
            getTransform = function(value) return value or 0 end,
            setTransform = function(value) return value > 0 and value or nil end,
        }
        propagateModifiers(childSpec, spec)
        return SB.PathSlider(childSpec)
    end

    --- Font override group.
    --- Optional spec fields:
    ---   fontValues        function() -> table     (choices for the dropdown)
    ---   fontFallback      function() -> string    (fallback font name)
    ---   fontSizeFallback  function() -> number    (fallback font size)
    ---   fontTemplate      string                  (custom template for the font picker)
    function SB.FontOverrideGroup(sectionPath, spec)
        spec = mergeCompositeDefaults("FontOverrideGroup", spec)
        local overridePath = sectionPath .. ".overrideFont"

        local enabledSpec = {
            path = overridePath,
            name = spec.enabledName or "Override font",
            tooltip = spec.enabledTooltip or "Override the global font settings for this module.",
            getTransform = function(value) return value == true end,
        }
        propagateModifiers(enabledSpec, spec)
        local enabledInit, enabledSetting = SB.PathCheckbox(enabledSpec)

        local fontSpec = {
            path = sectionPath .. ".font",
            name = spec.fontName or "Font",
            tooltip = spec.fontTooltip,
            values = spec.fontValues,
            parent = enabledInit,
            parentCheck = function() return enabledSetting:GetValue() end,
            getTransform = function(value)
                if value then return value end
                if spec.fontFallback then return spec.fontFallback() end
                return nil
            end,
        }
        propagateModifiers(fontSpec, spec)

        local fontInit
        if spec.fontTemplate then
            fontSpec.template = spec.fontTemplate
            fontInit = SB.PathCustom(fontSpec)
        else
            fontInit = SB.PathDropdown(fontSpec)
        end

        local sizeSpec = {
            path = sectionPath .. ".fontSize",
            name = spec.sizeName or "Font Size",
            tooltip = spec.sizeTooltip,
            min = spec.sizeMin or 6,
            max = spec.sizeMax or 32,
            step = spec.sizeStep or 1,
            parent = enabledInit,
            parentCheck = function() return enabledSetting:GetValue() end,
            getTransform = function(value)
                if value then return value end
                if spec.fontSizeFallback then return spec.fontSizeFallback() end
                return 11
            end,
        }
        propagateModifiers(sizeSpec, spec)
        local sizeInit = SB.PathSlider(sizeSpec)

        return {
            enabledInit = enabledInit,
            enabledSetting = enabledSetting,
            fontInit = fontInit,
            sizeInit = sizeInit,
        }
    end

    function SB.BorderGroup(borderPath, spec)
        spec = spec or {}

        local enabledSpec = {
            path = borderPath .. ".enabled",
            name = spec.enabledName or "Show border",
            tooltip = spec.enabledTooltip,
        }
        propagateModifiers(enabledSpec, spec)
        local enabledInit, enabledSetting = SB.PathCheckbox(enabledSpec)

        local thicknessSpec = {
            path = borderPath .. ".thickness",
            name = spec.thicknessName or "Border width",
            tooltip = spec.thicknessTooltip,
            min = spec.thicknessMin or 1,
            max = spec.thicknessMax or 10,
            step = spec.thicknessStep or 1,
            parent = enabledInit,
            parentCheck = function() return enabledSetting:GetValue() end,
        }
        propagateModifiers(thicknessSpec, spec)
        local thicknessInit = SB.PathSlider(thicknessSpec)

        local colorSpec = {
            path = borderPath .. ".color",
            name = spec.colorName or "Border color",
            tooltip = spec.colorTooltip,
            parent = enabledInit,
            parentCheck = function() return enabledSetting:GetValue() end,
        }
        propagateModifiers(colorSpec, spec)
        local colorInit = SB.PathColor(colorSpec)

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
            local childSpec = {
                path = basePath .. "." .. tostring(def.key),
                name = def.name,
                tooltip = def.tooltip,
            }
            propagateModifiers(childSpec, spec)
            local init, setting = SB.PathColor(childSpec)
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
        spec = mergeCompositeDefaults("PositioningGroup", spec)
        assert(spec.positionModes, "PositioningGroup: spec.positionModes is required")
        assert(spec.isAnchorModeFree, "PositioningGroup: spec.isAnchorModeFree is required")

        local modeSpec = {
            path = configPath .. ".anchorMode",
            name = spec.modeName or "Position Mode",
            tooltip = spec.modeTooltip,
            values = spec.positionModes,
            onSet = function(value)
                if spec.applyPositionMode then
                    spec.applyPositionMode(
                        getNestedValue(getProfile(), configPath), value)
                end
            end,
        }
        propagateModifiers(modeSpec, spec)
        local modeInit, modeSetting = SB.PathDropdown(modeSpec)

        local function isFreeMode()
            return spec.isAnchorModeFree(
                getNestedValue(getProfile(), configPath))
        end

        local defaultBarWidth = spec.defaultBarWidth or 250

        local widthSpec = {
            path = configPath .. ".width",
            name = spec.widthName or "Width",
            tooltip = spec.widthTooltip or "Width when free positioning is enabled.",
            min = spec.widthMin or 100,
            max = spec.widthMax or 600,
            step = spec.widthStep or 1,
            parent = modeInit,
            parentCheck = isFreeMode,
            getTransform = function(value)
                return value or defaultBarWidth
            end,
        }
        propagateModifiers(widthSpec, spec)
        local widthInit = SB.PathSlider(widthSpec)

        local offsetXInit
        if spec.includeOffsetX ~= false then
            local offsetXSpec = {
                path = configPath .. ".offsetX",
                name = spec.offsetXName or "Offset X",
                tooltip = spec.offsetXTooltip or "Horizontal offset when free positioning is enabled.",
                min = -800,
                max = 800,
                step = 1,
                parent = modeInit,
                parentCheck = isFreeMode,
                getTransform = function(value) return value or 0 end,
                setTransform = function(value) return value ~= 0 and value or nil end,
            }
            propagateModifiers(offsetXSpec, spec)
            offsetXInit = SB.PathSlider(offsetXSpec)
        end

        local offsetYSpec = {
            path = configPath .. ".offsetY",
            name = spec.offsetYName or "Offset Y",
            tooltip = spec.offsetYTooltip or "Vertical offset when free positioning is enabled.",
            min = -800,
            max = 800,
            step = 1,
            parent = modeInit,
            parentCheck = isFreeMode,
            getTransform = function(value) return value or 0 end,
            setTransform = function(value) return value ~= 0 and value or nil end,
        }
        propagateModifiers(offsetYSpec, spec)
        local offsetYInit = SB.PathSlider(offsetYSpec)

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

    function SB.Label(spec)
        local cat = resolveCategory(spec)
        local layout = SB._layouts[cat]
        local initializer = Settings.CreateElementInitializer(lib.LABEL_TEMPLATE, { name = spec.name })
        layout:AddInitializer(initializer)
        applyModifiers(initializer, spec)
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

    ----------------------------------------------------------------------------
    -- Table-driven registration (AceConfig-inspired)
    ----------------------------------------------------------------------------

    local TYPE_ALIASES = {
        toggle = "checkbox",
        range = "slider",
        select = "dropdown",
        execute = "button",
        description = "label",
    }

    local COMPOSITE_TYPES = {
        moduleEnabled = true,
        positioning = true,
        border = true,
        fontOverride = true,
        heightOverride = true,
        colorList = true,
    }

    --- Walks an AceConfig-inspired option table and calls the imperative API.
    --- Supports property inheritance (disabled, hidden), path prefixing,
    --- parent references by key, type aliases, and LSB composite types.
    function SB.RegisterFromTable(tbl)
        assert(tbl.name, "RegisterFromTable: tbl.name is required")

        SB.CreateSubcategory(tbl.name)

        local groupPath = tbl.path or ""

        local function resolvePath(entryPath)
            if not entryPath then return groupPath end
            if entryPath:find("%.") or groupPath == "" then return entryPath end
            return groupPath .. "." .. entryPath
        end

        -- Handle moduleEnabled
        if tbl.moduleEnabled then
            local meSpec = {}
            for k, v in pairs(tbl.moduleEnabled) do meSpec[k] = v end
            meSpec.path = meSpec.path or (groupPath ~= "" and (groupPath .. ".enabled") or "enabled")
            if tbl.disabled then meSpec.disabled = meSpec.disabled or tbl.disabled end
            if tbl.hidden then meSpec.hidden = meSpec.hidden or tbl.hidden end
            local moduleName = tbl.moduleName or tbl.name:gsub("%s", "")
            SB.ModuleEnabledCheckbox(moduleName, meSpec)
        end

        if not tbl.args then return end

        -- Sort entries by order field
        local sorted = {}
        for key, entry in pairs(tbl.args) do
            entry._key = key
            sorted[#sorted + 1] = entry
        end
        table.sort(sorted, function(a, b)
            return (a.order or 100) < (b.order or 100)
        end)

        -- Registry for created initializers/settings (for parent refs by key)
        local created = {}

        for _, entry in ipairs(sorted) do
            local entryType = TYPE_ALIASES[entry.type] or entry.type

            -- Skip entry if condition function returns false
            local shouldProcess = true
            if entry.condition ~= nil then
                if type(entry.condition) == "function" then
                    shouldProcess = entry.condition()
                else
                    shouldProcess = entry.condition
                end
            end

            if shouldProcess then
                -- Build spec with inherited properties
                local spec = {}
                for k, v in pairs(entry) do
                    if k ~= "type" and k ~= "order" and k ~= "_key" and k ~= "defs" and k ~= "label" and k ~= "condition" then
                        spec[k] = v
                    end
                end

                -- Alias desc → tooltip
                if spec.desc and not spec.tooltip then
                    spec.tooltip = spec.desc
                    spec.desc = nil
                end

                -- Inherit disabled/hidden from group
                if tbl.disabled and spec.disabled == nil then spec.disabled = tbl.disabled end
                if tbl.hidden and spec.hidden == nil then spec.hidden = tbl.hidden end

                -- Resolve parent string references
                if type(spec.parent) == "string" then
                    local ref = created[spec.parent]
                    if ref then
                        spec.parent = ref.initializer

                        -- Shortcut parentCheck values
                        if spec.parentCheck == "checked" then
                            local refSetting = ref.setting
                            spec.parentCheck = function() return refSetting:GetValue() end
                        elseif spec.parentCheck == "notChecked" then
                            local refSetting = ref.setting
                            spec.parentCheck = function() return not refSetting:GetValue() end
                        end
                    end
                end

                local init, setting

                if entryType == "header" then
                    init = SB.Header(spec.name)

                elseif entryType == "label" then
                    init = SB.Label(spec)

                elseif entryType == "button" then
                    init = SB.Button(spec)

                elseif entryType == "positioning" then
                    local result = SB.PositioningGroup(resolvePath(entry.path), spec)
                    init = result.modeInit
                    setting = result.modeSetting

                elseif entryType == "border" then
                    local result = SB.BorderGroup(resolvePath(entry.path), spec)
                    init = result.enabledInit
                    setting = result.enabledSetting

                elseif entryType == "fontOverride" then
                    local result = SB.FontOverrideGroup(resolvePath(entry.path), spec)
                    init = result.enabledInit
                    setting = result.enabledSetting

                elseif entryType == "heightOverride" then
                    init, setting = SB.HeightOverrideSlider(resolvePath(entry.path), spec)

                elseif entryType == "colorList" then
                    local defs = entry.defs or {}
                    if entry.label then
                        local labelInit = SB.Label({ name = entry.label, disabled = spec.disabled, hidden = spec.hidden })
                        spec.parent = spec.parent or labelInit
                    end
                    local results = SB.ColorPickerList(resolvePath(entry.path), defs, spec)
                    if results[1] then
                        init = results[1].initializer
                        setting = results[1].setting
                    end

                elseif entryType == "checkbox" or entryType == "slider"
                    or entryType == "dropdown" or entryType == "color"
                    or entryType == "custom" then
                    spec.path = resolvePath(entry.path or spec.path)
                    spec.type = entryType
                    init, setting = SB.PathControl(spec)

                end

                created[entry._key] = { initializer = init, setting = setting }
            end
        end
    end

    function SB.RegisterSection(nsTable, key, section)
        nsTable.OptionsSections = nsTable.OptionsSections or {}
        nsTable.OptionsSections[key] = section
        return section
    end

    return SB
end
