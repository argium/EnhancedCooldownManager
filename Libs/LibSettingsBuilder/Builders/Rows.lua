-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local foundation = internal.foundation
local interop = internal.interop
local registry = internal.registry
local builders = internal.builders

function builders.checkbox(self, spec)
    registry.validateSpecFields(self, "checkbox", spec)
    local setting, category = registry.makeProxySetting(self, spec, interop.getVarTypeBoolean(), false)
    local initializer = interop.createCheckbox(category, setting, spec.tooltip)
    registry.applyModifiers(self, initializer, spec)
    return initializer, setting
end

function builders.slider(self, spec)
    registry.validateSpecFields(self, "slider", spec)
    local setting, category = registry.makeProxySetting(self, spec, interop.getVarTypeNumber(), 0)
    local initializer = interop.createSlider(
        category,
        setting,
        spec.min,
        spec.max,
        spec.step,
        spec.formatter or foundation.defaultSliderFormatter,
        spec.tooltip
    )
    registry.applyModifiers(self, initializer, spec)
    return initializer, setting
end

function builders.dropdown(self, spec)
    registry.validateSpecFields(self, "dropdown", spec)

    local binding = registry.resolveBinding(self, spec)
    local defaultValue = binding.default
    if spec.getTransform then
        defaultValue = spec.getTransform(defaultValue)
    end

    local varType = spec.varType
        or (type(defaultValue) == "number" and interop.getVarTypeNumber())
        or interop.getVarTypeString()

    local setting, category = registry.makeProxySetting(self, spec, varType, "", binding)
    local function optionsGenerator()
        local container = interop.createDropdownOptionsContainer()
        local values = type(spec.values) == "function" and spec.values() or spec.values
        if values then
            for _, entry in ipairs(foundation.getOrderedValueEntries(values)) do
                container:Add(entry.value, entry.label)
            end
        end
        return container:GetData()
    end
    setting._optionsGen = optionsGenerator

    local initializer = interop.createDropdown(category, setting, optionsGenerator, spec.tooltip)
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
        registry.registerCategoryRefreshable(self, category, initializer)
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
        registry.registerCategoryRefreshable(self, category, initializer)
    end

    registry.applyModifiers(self, initializer, spec)

    return initializer, setting
end

function builders.color(self, spec)
    registry.validateSpecFields(self, "color", spec)

    local variable = registry.makeVarName(self, spec)
    local category = registry.resolveCategory(self, spec)
    local binding = registry.resolveBinding(self, spec)

    local function getter()
        return foundation.colorTableToHex(binding.get())
    end

    local settingRef
    local function setter(hexValue)
        local color = interop.createColorFromHexString(hexValue)
        local value = { r = color.r, g = color.g, b = color.b, a = color.a }
        binding.set(value)
        registry.postSet(self, spec, value, settingRef)
    end

    local defaultHex = foundation.colorTableToHex(binding.default or {})
    local setting = interop.registerProxySetting(
        category,
        variable,
        interop.getVarTypeString(),
        spec.name,
        defaultHex,
        getter,
        setter
    )
    settingRef = setting

    local initializer = interop.createColorSwatchInitializer(category, setting, spec.tooltip)
    registry.applyModifiers(self, initializer, spec)

    return initializer, setting
end

function builders.input(self, spec)
    registry.validateSpecFields(self, "input", spec)

    local setting, category = registry.makeProxySetting(self, spec, interop.getVarTypeString(), "")
    local data = {
        debounce = spec.debounce,
        maxLetters = spec.maxLetters,
        name = spec.name,
        numeric = spec.numeric,
        onTextChanged = spec.onTextChanged,
        resolveText = spec.resolveText,
        setting = setting,
        settingVariable = interop.getSettingVariable(setting),
        tooltip = spec.tooltip,
        width = spec.width,
    }

    local extent = spec.resolveText and 46 or 26
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", data, extent, interop.applyInputRowFrame)
    local originalInitFrame = initializer.InitFrame
    local originalResetter = initializer.Resetter

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        if controlInitializer._lsbActiveFrame then
            interop.applyInputRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
        end
    end

    initializer.InitFrame = function(controlInitializer, frame)
        controlInitializer._lsbActiveFrame = frame
        originalInitFrame(controlInitializer, frame)
        interop.applyInputRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
    end

    initializer.Resetter = function(controlInitializer, frame)
        interop.cancelInputPreviewTimer(frame)
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

    interop.registerInitializer(category, initializer)
    registry.applyModifiers(self, initializer, spec)

    return initializer, setting
end

--- Creates a proxy setting backed by a custom frame template.
--- The template's Init receives initializer data containing {setting, name, tooltip}.
function builders.custom(self, spec)
    registry.validateSpecFields(self, "custom", spec)
    assert(spec.template, "Custom: spec.template is required")

    local setting, category = registry.makeProxySetting(self, spec, spec.varType or interop.getVarTypeString(), "")
    local initializer = interop.createElementInitializer(spec.template, {
        name = spec.name,
        setting = setting,
        tooltip = spec.tooltip,
    })

    initializer:SetSetting(setting)

    interop.registerInitializer(category, initializer)
    registry.applyModifiers(self, initializer, spec)

    return initializer, setting
end
