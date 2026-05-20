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
local builders = internal.builders

function builders.checkbox(spec)
    local initializer = interop.createCheckbox(spec.category, spec.setting, spec.tooltip)
    return { initializer = initializer, setting = spec.setting }
end

function builders.slider(spec)
    local initializer = interop.createSlider(
        spec.category,
        spec.setting,
        spec.min,
        spec.max,
        spec.step,
        spec.formatter or foundation.defaultSliderFormatter,
        spec.tooltip
    )
    return { initializer = initializer, setting = spec.setting }
end

function builders.dropdown(spec)
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
    spec.setting._optionsGen = optionsGenerator

    local initializer = interop.createDropdown(spec.category, spec.setting, optionsGenerator, spec.tooltip)
    interop.configureDropdownInitializer(initializer, spec.setting, spec)
    return {
        initializer = initializer,
        setting = spec.setting,
        refreshable = spec.scrollHeight ~= nil or type(spec.values) == "function",
    }
end

function builders.color(spec)
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        name = spec.name,
        setting = spec.setting,
        settingVariable = interop.getSettingVariable(spec.setting),
        tooltip = spec.tooltip,
    }, 26, interop.applyColorRowFrame)
    interop.configureColorInitializer(initializer, spec.setting)
    return { initializer = initializer, setting = spec.setting, registration = "category" }
end

function builders.input(spec)
    local data = {
        debounce = spec.debounce,
        maxLetters = spec.maxLetters,
        name = spec.name,
        numeric = spec.numeric,
        onTextChanged = spec.onTextChanged,
        resolveText = spec.resolveText,
        setting = spec.setting,
        settingVariable = interop.getSettingVariable(spec.setting),
        tooltip = spec.tooltip,
        width = spec.width,
    }

    local extent = spec.resolveText and 46 or 26
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", data, extent, interop.applyInputRowFrame)
    interop.configureInputInitializer(initializer)
    return { initializer = initializer, setting = spec.setting, registration = "category" }
end

function builders.registered(spec)
    local descriptor = lib._registeredRowTypes[spec.type]
    assert(descriptor, "Registered row type '" .. tostring(spec.type) .. "' is not available")

    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        name = spec.name,
        setting = spec.setting,
        settingVariable = interop.getSettingVariable(spec.setting),
        tooltip = spec.tooltip,
    }, descriptor.extent or 26, descriptor.applyFrame, descriptor.resetFrame)

    interop.setInitializerSetting(initializer, spec.setting)
    if descriptor.configureInitializer then
        descriptor.configureInitializer(initializer, spec.setting, spec)
    end
    return { initializer = initializer, setting = spec.setting, registration = "category" }
end
