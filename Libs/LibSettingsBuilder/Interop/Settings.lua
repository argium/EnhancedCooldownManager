-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local interop = lib._internal.interop

function interop.createRootCategory(name)
    local category, layout = Settings.RegisterVerticalLayoutCategory(name)
    return category, layout
end

function interop.createSubcategory(parent, name)
    local subcategory, layout = Settings.RegisterVerticalLayoutSubcategory(parent, name)
    return subcategory, layout
end

function interop.registerAddOnCategory(category)
    Settings.RegisterAddOnCategory(category)
end

function interop.registerInitializer(category, initializer)
    Settings.RegisterInitializer(category, initializer)
end

function interop.addLayoutInitializer(layout, initializer)
    layout:AddInitializer(initializer)
end

function interop.registerProxySetting(category, variable, varType, name, defaultValue, getter, setter)
    local setting = Settings.RegisterProxySetting(category, variable, varType, name, defaultValue, getter, setter)
    setting._lsbVariable = variable
    return setting
end

function interop.getVarTypeBoolean()
    return Settings.VarType.Boolean
end

function interop.getVarTypeNumber()
    return Settings.VarType.Number
end

function interop.getVarTypeString()
    return Settings.VarType.String
end

function interop.createCheckbox(category, setting, tooltip)
    return Settings.CreateCheckbox(category, setting, tooltip)
end

function interop.createSlider(category, setting, minValue, maxValue, step, formatter, tooltip)
    local options = Settings.CreateSliderOptions(minValue, maxValue, step or 1)
    options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
    return Settings.CreateSlider(category, setting, options, tooltip)
end

function interop.createDropdown(category, setting, optionsGenerator, tooltip)
    return Settings.CreateDropdown(category, setting, optionsGenerator, tooltip)
end

function interop.createDropdownOptionsContainer()
    return Settings.CreateControlTextContainer()
end

function interop.createColorFromHexString(hexValue)
    return CreateColorFromHexString(hexValue)
end

function interop.createColorSwatchInitializer(category, setting, tooltip)
    return Settings.CreateColorSwatch(category, setting, tooltip)
end

function interop.createElementInitializer(template, data)
    return Settings.CreateElementInitializer(template, data)
end

function interop.createCallbackHandleContainer()
    return Settings and Settings.CreateCallbackHandleContainer and Settings.CreateCallbackHandleContainer() or nil
end

function interop.createSectionHeaderInitializer(name)
    return CreateSettingsListSectionHeaderInitializer(name)
end

function interop.createButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)
    return CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)
end
