-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

local LSB = LibStub("LibSettingsBuilder-1.0")
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

local SB = LSB:New({
    getProfile = function() return mod.db and mod.db.profile end,
    getDefaults = function() return mod.db and mod.db.defaults and mod.db.defaults.profile end,
    getNestedValue = ECM.OptionUtil.GetNestedValue,
    setNestedValue = ECM.OptionUtil.SetNestedValue,
    varPrefix = "ECM",
    onChanged = function(spec)
        if spec.layout ~= false then
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end,
    compositeDefaults = {
        FontOverrideGroup = {
            fontValues = LSMW.GetFontValues,
            fontFallback = function()
                local profile = mod.db and mod.db.profile
                return profile and ECM.OptionUtil.GetNestedValue(profile, "global.font") or "Expressway"
            end,
            fontSizeFallback = function()
                local profile = mod.db and mod.db.profile
                return profile and ECM.OptionUtil.GetNestedValue(profile, "global.fontSize") or 11
            end,
            fontTemplate = LSMW.FONT_PICKER_TEMPLATE,
        },
        PositioningGroup = {
            positionModes = ECM.OptionUtil.POSITION_MODE_TEXT,
            isAnchorModeFree = ECM.OptionUtil.IsAnchorModeFree,
            applyPositionMode = ECM.OptionUtil.ApplyPositionModeToBar,
            defaultBarWidth = ECM.Constants.DEFAULT_BAR_WIDTH,
        },
    },
})

ECM.SettingsBuilder = SB
