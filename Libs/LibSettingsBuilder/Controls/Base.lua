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
function lib.Checkbox(self, spec)
    internal.validateSpecFields(self, "checkbox", spec)
    local setting, category = internal.makeProxySetting(self, spec, Settings.VarType.Boolean, false)
    local initializer = Settings.CreateCheckbox(category, setting, spec.tooltip)
    internal.applyModifiers(self, initializer, spec)
    return initializer, setting
end

function lib.Slider(self, spec)
    internal.validateSpecFields(self, "slider", spec)
    local setting, category = internal.makeProxySetting(self, spec, Settings.VarType.Number, 0)

    local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter or internal.defaultSliderFormatter)

    local initializer = Settings.CreateSlider(category, setting, options, spec.tooltip)
    internal.applyModifiers(self, initializer, spec)

    return initializer, setting
end

function lib.Dropdown(self, spec)
    internal.validateSpecFields(self, "dropdown", spec)

    local binding = internal.resolveBinding(self, spec)
    local defaultValue = binding.default
    if spec.getTransform then
        defaultValue = spec.getTransform(defaultValue)
    end

    local varType = spec.varType
        or (type(defaultValue) == "number" and Settings.VarType.Number)
        or Settings.VarType.String

    local setting, category = internal.makeProxySetting(self, spec, varType, "", binding)
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
    initializer._lsbData = {
        _lsbKind = "dropdown",
        setting = setting,
        values = spec.values,
        name = spec.name,
        tooltip = spec.tooltip,
    }
    if spec.scrollHeight then
        initializer._lsbData._lsbKind = "scrollDropdown"
        initializer._lsbData.scrollHeight = spec.scrollHeight
        initializer:SetSetting(setting)
        initializer._lsbRefreshFrame = function(frame)
            if frame and frame.RefreshDropdownText then
                frame:RefreshDropdownText()
            end
        end
        internal.registerCategoryRefreshable(self, category, initializer)
    end

    if not initializer:GetSetting() then
        initializer:SetSetting(setting)
    end

    if type(spec.values) == "function" and not initializer._lsbRefreshFrame then
        initializer._lsbRefreshFrame = function(frame)
            if frame and frame.InitDropdown and frame.lsbData and frame.lsbData._lsbKind == "scrollDropdown" then
                frame:InitDropdown(initializer)
            elseif frame and frame.RefreshDropdownText then
                frame:RefreshDropdownText()
            elseif frame and frame.SetValue and setting.GetValue then
                frame:SetValue(setting:GetValue())
            end
        end
        internal.registerCategoryRefreshable(self, category, initializer)
    end

    internal.applyModifiers(self, initializer, spec)

    return initializer, setting
end

function lib.Color(self, spec)
    internal.validateSpecFields(self, "color", spec)

    local variable = internal.makeVarName(self, spec)
    local category = internal.resolveCategory(self, spec)
    local binding = internal.resolveBinding(self, spec)

    local function getter()
        return internal.colorTableToHex(self, binding.get())
    end

    local settingRef
    local function setter(hexValue)
        local color = CreateColorFromHexString(hexValue)
        local value = { r = color.r, g = color.g, b = color.b, a = color.a }
        binding.set(value)
        internal.postSet(self, spec, value, settingRef)
    end

    local defaultHex = internal.colorTableToHex(self, binding.default or {})
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
    internal.applyModifiers(self, initializer, spec)

    return initializer, setting
end

function lib.Input(self, spec)
    internal.validateSpecFields(self, "input", spec)

    local setting, category = internal.makeProxySetting(self, spec, Settings.VarType.String, "")
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
    local initializer = createCustomListRowInitializer("SettingsListElementTemplate", data, extent, applyInputRowFrame)
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
            frame._lsbInputEditBox:ClearFocus()
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
    internal.applyModifiers(self, initializer, spec)

    return initializer, setting
end

--- Creates a proxy setting backed by a custom frame template.
--- The template's Init receives initializer data containing {setting, name, tooltip}.
function lib.Custom(self, spec)
    internal.validateSpecFields(self, "custom", spec)
    assert(spec.template, "Custom: spec.template is required")

    local setting, category = internal.makeProxySetting(self, spec, spec.varType or Settings.VarType.String, "")
    local initializer = Settings.CreateElementInitializer(spec.template, {
        name = spec.name,
        setting = setting,
        tooltip = spec.tooltip,
    })

    initializer:SetSetting(setting)

    Settings.RegisterInitializer(category, initializer)
    internal.applyModifiers(self, initializer, spec)

    return initializer, setting
end
