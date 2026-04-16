-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local function callBuilder(builder, methodName, ...)
    return lib[methodName](builder, ...)
end

function lib:HeightOverrideSlider(sectionPath, spec)
    spec = spec or {}
    local childSpec = {
        path = sectionPath .. ".height",
        name = spec.name or "Height Override",
        tooltip = spec.tooltip or "Override the default bar height. Set to 0 to use the global default.",
        min = spec.min or 0,
        max = spec.max or 40,
        step = spec.step or 1,
        getTransform = function(value)
            return value or 0
        end,
        setTransform = function(value)
            return value > 0 and value or nil
        end,
    }
    self:_propagateModifiers(childSpec, spec)
    return callBuilder(self, "Slider", childSpec)
end

--- Font override group.
--- Optional spec fields:
---   fontValues        function() -> table     (choices for the dropdown)
---   fontFallback      function() -> string    (fallback font name)
---   fontSizeFallback  function() -> number    (fallback font size)
---   fontTemplate      string                  (custom template for the font picker)
function lib:FontOverrideGroup(sectionPath, spec)
    spec = spec or {}
    local overridePath = sectionPath .. ".overrideFont"

    local enabledSpec = {
        path = overridePath,
        name = spec.enabledName or "Override font",
        tooltip = spec.enabledTooltip or "Override the global font settings for this module.",
        getTransform = function(value)
            return value == true
        end,
    }
    self:_propagateModifiers(enabledSpec, spec)
    local enabledInit, enabledSetting = callBuilder(self, "Checkbox", enabledSpec)

    local outerDisabled = spec.disabled
    local function isOverrideDisabled()
        if outerDisabled and outerDisabled() then
            return true
        end
        return not enabledSetting:GetValue()
    end

    local fontSpec = {
        path = sectionPath .. ".font",
        name = spec.fontName or "Font",
        tooltip = spec.fontTooltip,
        values = spec.fontValues,
        disabled = isOverrideDisabled,
        getTransform = function(value)
            if value then
                return value
            end
            if spec.fontFallback then
                return spec.fontFallback()
            end
            return nil
        end,
    }
    self:_propagateModifiers(fontSpec, spec)

    local fontInit
    if spec.fontTemplate then
        fontSpec.template = spec.fontTemplate
        fontInit = callBuilder(self, "Custom", fontSpec)
    else
        fontInit = callBuilder(self, "Dropdown", fontSpec)
    end

    local sizeSpec = {
        path = sectionPath .. ".fontSize",
        name = spec.sizeName or "Font Size",
        tooltip = spec.sizeTooltip,
        min = spec.sizeMin or 6,
        max = spec.sizeMax or 32,
        step = spec.sizeStep or 1,
        disabled = isOverrideDisabled,
        getTransform = function(value)
            if value then
                return value
            end
            if spec.fontSizeFallback then
                return spec.fontSizeFallback()
            end
            return 11
        end,
    }
    self:_propagateModifiers(sizeSpec, spec)
    local sizeInit = callBuilder(self, "Slider", sizeSpec)

    return {
        enabledInit = enabledInit,
        enabledSetting = enabledSetting,
        fontInit = fontInit,
        sizeInit = sizeInit,
    }
end

function lib:BorderGroup(borderPath, spec)
    spec = spec or {}

    local enabledSpec = {
        path = borderPath .. ".enabled",
        name = spec.enabledName or "Show border",
        tooltip = spec.enabledTooltip,
    }
    self:_propagateModifiers(enabledSpec, spec)
    local enabledInit, enabledSetting = callBuilder(self, "Checkbox", enabledSpec)

    local thicknessSpec = {
        path = borderPath .. ".thickness",
        name = spec.thicknessName or "Border width",
        tooltip = spec.thicknessTooltip,
        min = spec.thicknessMin or 1,
        max = spec.thicknessMax or 10,
        step = spec.thicknessStep or 1,
        _parentInitializer = enabledInit,
        _parentPredicate = function()
            return enabledSetting:GetValue()
        end,
    }
    self:_propagateModifiers(thicknessSpec, spec)
    local thicknessInit = callBuilder(self, "Slider", thicknessSpec)

    local colorSpec = {
        path = borderPath .. ".color",
        name = spec.colorName or "Border color",
        tooltip = spec.colorTooltip,
        _parentInitializer = enabledInit,
        _parentPredicate = function()
            return enabledSetting:GetValue()
        end,
    }
    self:_propagateModifiers(colorSpec, spec)
    local colorInit = callBuilder(self, "Color", colorSpec)

    return {
        enabledInit = enabledInit,
        enabledSetting = enabledSetting,
        thicknessInit = thicknessInit,
        colorInit = colorInit,
    }
end
