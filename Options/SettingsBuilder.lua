-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local LSB = LibStub("LibSettingsBuilder-1.0")
local LSMW = LibStub("LibLSMSettingsWidgets-1.0", true)

--------------------------------------------------------------------------------
-- Create builder instance with addon-specific configuration
--------------------------------------------------------------------------------

local SB = LSB:New({
    getProfile = function() return mod.db and mod.db.profile end,
    getDefaults = function() return mod.db and mod.db.defaults and mod.db.defaults.profile end,
    varPrefix = "ECM",
    onChanged = function(spec, value)
        if spec.layout ~= false then
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    getNestedValue = function(tbl, path)
        return ECM.OptionUtil.GetNestedValue(tbl, path)
    end,
    setNestedValue = function(tbl, path, value)
        return ECM.OptionUtil.SetNestedValue(tbl, path, value)
    end,
})

--------------------------------------------------------------------------------
-- Wrap composite builders to inject addon-specific defaults
--------------------------------------------------------------------------------

local _libModuleEnabledCheckbox = SB.ModuleEnabledCheckbox
SB.ModuleEnabledCheckbox = function(moduleName, spec)
    local merged = {}
    if spec then for k, v in pairs(spec) do merged[k] = v end end
    merged.setModuleEnabled = merged.setModuleEnabled or function(name, enabled)
        return ECM.OptionUtil.SetModuleEnabled(name, enabled)
    end
    return _libModuleEnabledCheckbox(moduleName, merged)
end

local _libFontOverrideGroup = SB.FontOverrideGroup
SB.FontOverrideGroup = function(sectionPath, spec)
    local merged = {}
    if spec then for k, v in pairs(spec) do merged[k] = v end end
    merged.fontValues = merged.fontValues or (LSMW and LSMW.GetFontValues)
    merged.fontFallback = merged.fontFallback or function()
        local profile = mod.db and mod.db.profile
        return profile and ECM.OptionUtil.GetNestedValue(profile, "global.font") or "Expressway"
    end
    merged.fontSizeFallback = merged.fontSizeFallback or function()
        local profile = mod.db and mod.db.profile
        return profile and ECM.OptionUtil.GetNestedValue(profile, "global.fontSize") or 11
    end
    merged.fontTemplate = merged.fontTemplate or (LSMW and LSMW.FONT_PICKER_TEMPLATE)
    return _libFontOverrideGroup(sectionPath, merged)
end

local _libPositioningGroup = SB.PositioningGroup
SB.PositioningGroup = function(configPath, spec)
    local merged = {}
    if spec then for k, v in pairs(spec) do merged[k] = v end end
    merged.positionModes = merged.positionModes or ECM.OptionUtil.POSITION_MODE_TEXT
    merged.isAnchorModeFree = merged.isAnchorModeFree or function(cfg)
        return ECM.OptionUtil.IsAnchorModeFree(cfg)
    end
    merged.applyPositionMode = merged.applyPositionMode or function(cfg, mode)
        return ECM.OptionUtil.ApplyPositionModeToBar(cfg, mode)
    end
    merged.defaultBarWidth = merged.defaultBarWidth or ECM.Constants.DEFAULT_BAR_WIDTH
    return _libPositioningGroup(configPath, merged)
end

--------------------------------------------------------------------------------
-- Export
--------------------------------------------------------------------------------

ECM.SettingsBuilder = SB

ECM.SharedMediaOptions = LSMW and {
    GetFontValues = LSMW.GetFontValues,
    GetStatusbarValues = LSMW.GetStatusbarValues,
    FONT_PICKER_TEMPLATE = LSMW.FONT_PICKER_TEMPLATE,
    TEXTURE_PICKER_TEMPLATE = LSMW.TEXTURE_PICKER_TEMPLATE,
} or {
    GetFontValues = function() return {} end,
    GetStatusbarValues = function() return {} end,
}
