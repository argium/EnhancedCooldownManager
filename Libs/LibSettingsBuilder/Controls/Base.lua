-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local createCustomListRowInitializer = internal.createCustomListRowInitializer
local getOrderedValueEntries = internal.getOrderedValueEntries
local getSettingVariable = internal.getSettingVariable
local applyInputRowEnabledState = internal.applyInputRowEnabledState
local applyInputRowFrame = internal.applyInputRowFrame
local cancelInputPreviewTimer = internal.cancelInputPreviewTimer
local BuilderMixin = internal.BuilderMixin

function BuilderMixin:Checkbox(spec)
    self:_validateSpecFields("checkbox", spec)
    local setting, category = self:_makeProxySetting(spec, Settings.VarType.Boolean, false)
    local initializer = Settings.CreateCheckbox(category, setting, spec.tooltip)
    self:_applyModifiers(initializer, spec)
    return initializer, setting
end

function BuilderMixin:Slider(spec)
    self:_validateSpecFields("slider", spec)
    local setting, category = self:_makeProxySetting(spec, Settings.VarType.Number, 0)

    local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter or self._defaultSliderFormatter)

    local initializer = Settings.CreateSlider(category, setting, options, spec.tooltip)
    self:_applyModifiers(initializer, spec)

    return initializer, setting
end

function BuilderMixin:Dropdown(spec)
    self:_validateSpecFields("dropdown", spec)

    local binding = self:_resolveBinding(spec)
    local defaultValue = binding.default
    if spec.getTransform then
        defaultValue = spec.getTransform(defaultValue)
    end

    local varType = spec.varType
        or (type(defaultValue) == "number" and Settings.VarType.Number)
        or Settings.VarType.String

    local setting, category = self:_makeProxySetting(spec, varType, "", binding)
    local function optionsGenerator()
        local container = Settings.CreateControlTextContainer()
        local values = type(spec.values) == "function" and spec.values() or spec.values
        if values then
            for _, entry in ipairs(getOrderedValueEntries(values)) do
                container:Add(entry.value, entry.label)
            end
        end
        return container:GetData()
    end
    setting._optionsGen = optionsGenerator

    local initializer = Settings.CreateDropdown(category, setting, optionsGenerator, spec.tooltip)
    if spec.scrollHeight then
        initializer._lsbData = {
            _lsbKind = "scrollDropdown",
            setting = setting,
            values = spec.values,
            scrollHeight = spec.scrollHeight,
            name = spec.name,
            tooltip = spec.tooltip,
        }
        if initializer.SetSetting then
            initializer:SetSetting(setting)
        end
        initializer._lsbRefreshFrame = function(frame)
            if frame and frame.RefreshDropdownText then
                frame:RefreshDropdownText()
            end
        end
        self:_registerCategoryRefreshable(category, initializer)
    end

    if initializer.SetSetting and (not initializer.GetSetting or not initializer:GetSetting()) then
        initializer:SetSetting(setting)
    end

    if type(spec.values) == "function" and not initializer._lsbRefreshFrame then
        initializer._lsbRefreshFrame = function(frame)
            if frame and frame.InitDropdown then
                frame:InitDropdown(initializer)
            elseif frame and frame.SetValue and setting.GetValue then
                frame:SetValue(setting:GetValue())
            end
        end
        self:_registerCategoryRefreshable(category, initializer)
    end

    if not initializer.GetSetting then
        initializer.GetSetting = function()
            return setting
        end
    end

    self:_applyModifiers(initializer, spec)

    return initializer, setting
end

function BuilderMixin:Color(spec)
    self:_validateSpecFields("color", spec)

    local variable = self:_makeVarName(spec)
    local category = self:_resolveCategory(spec)
    local binding = self:_resolveBinding(spec)

    local function getter()
        return self:_colorTableToHex(binding.get())
    end

    local settingRef
    local function setter(hexValue)
        local color = CreateColorFromHexString(hexValue)
        local value = { r = color.r, g = color.g, b = color.b, a = color.a }
        binding.set(value)
        self:_postSet(spec, value, settingRef)
    end

    local defaultHex = self:_colorTableToHex(binding.default or {})
    local setting = Settings.RegisterProxySetting(
        category,
        variable,
        Settings.VarType.String,
        spec.name,
        defaultHex,
        getter,
        setter
    )
    settingRef = setting

    local initializer = Settings.CreateColorSwatch(category, setting, spec.tooltip)
    self:_applyModifiers(initializer, spec)

    return initializer, setting
end

function BuilderMixin:Input(spec)
    self:_validateSpecFields("input", spec)

    local setting, category = self:_makeProxySetting(spec, Settings.VarType.String, "")
    local data = {
        debounce = spec.debounce,
        maxLetters = spec.maxLetters,
        name = spec.name,
        numeric = spec.numeric,
        onTextChanged = spec.onTextChanged,
        resolveText = spec.resolveText,
        setting = setting,
        settingVariable = getSettingVariable(setting),
        tooltip = spec.tooltip,
        width = spec.width,
    }

    local extent = spec.resolveText and 46 or 26
    local initializer = createCustomListRowInitializer(internal.INPUTROW_TEMPLATE, data, extent, applyInputRowFrame)
    local originalInitFrame = initializer.InitFrame
    local originalResetter = initializer.Resetter

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        if controlInitializer._lsbActiveFrame then
            applyInputRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
        end
    end

    initializer.InitFrame = function(controlInitializer, frame)
        controlInitializer._lsbActiveFrame = frame
        originalInitFrame(controlInitializer, frame)
        applyInputRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
    end

    initializer.Resetter = function(controlInitializer, frame)
        cancelInputPreviewTimer(frame)
        if frame and frame._lsbInputEditBox then
            if frame._lsbInputEditBox.ClearFocus then
                frame._lsbInputEditBox:ClearFocus()
            end
            frame._lsbInputEditBox._lsbOwnerFrame = nil
        end
        frame._lsbInputData = nil
        frame._lsbInputSetting = nil
        if controlInitializer._lsbActiveFrame == frame then
            controlInitializer._lsbActiveFrame = nil
        end
        originalResetter(controlInitializer, frame)
    end

    Settings.RegisterInitializer(category, initializer)
    self:_applyModifiers(initializer, spec)

    return initializer, setting
end

--- Creates a proxy setting backed by a custom frame template.
--- The template's Init receives initializer data containing {setting, name, tooltip}.
function BuilderMixin:Custom(spec)
    self:_validateSpecFields("custom", spec)
    assert(spec.template, "Custom: spec.template is required")

    local setting, category = self:_makeProxySetting(spec, spec.varType or Settings.VarType.String, "")
    local initializer = Settings.CreateElementInitializer(spec.template, {
        name = spec.name,
        tooltip = spec.tooltip,
    })

    if initializer.SetSetting then
        initializer:SetSetting(setting)
    end

    Settings.RegisterInitializer(category, initializer)
    self:_applyModifiers(initializer, spec)

    return initializer, setting
end
