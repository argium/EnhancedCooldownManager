-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L

local POWER_COLOR_DEFS = {
    { key = Enum.PowerType.Mana, name = L["POWER_MANA"] },
    { key = Enum.PowerType.Rage, name = L["POWER_RAGE"] },
    { key = Enum.PowerType.Focus, name = L["POWER_FOCUS"] },
    { key = Enum.PowerType.Energy, name = L["POWER_ENERGY"] },
    { key = Enum.PowerType.RunicPower, name = L["POWER_RUNIC_POWER"] },
    { key = Enum.PowerType.LunarPower, name = L["POWER_LUNAR_POWER"] },
    { key = Enum.PowerType.Maelstrom, name = L["POWER_MAELSTROM"] },
    { key = Enum.PowerType.Insanity, name = L["POWER_INSANITY"] },
    { key = Enum.PowerType.Fury, name = L["POWER_FURY"] },
}

local PowerBarOptions = {}
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("powerBar")

function PowerBarOptions.RegisterSettings(SB)
    local rows = {
        {
            type = "checkbox",
            path = "enabled",
            name = L["ENABLE_POWER_BAR"],
            onSet = ns.OptionUtil.CreateModuleEnabledHandler("PowerBar"),
        },
    }

    for _, row in ipairs(ns.OptionUtil.CreateBarRows(isDisabled)) do
        rows[#rows + 1] = row
    end

    rows[#rows + 1] = {
        type = "checkbox",
        path = "showManaAsPercent",
        name = L["SHOW_MANA_AS_PERCENT"],
        desc = L["SHOW_MANA_AS_PERCENT_DESC"],
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        type = "colorList",
        path = "colors",
        label = L["COLORS"],
        defs = POWER_COLOR_DEFS,
        disabled = isDisabled,
    }

    SB.RegisterPage({ name = L["POWER_BAR"], path = "powerBar", rows = rows })
    ns.PowerBarTickMarksOptions.RegisterSettings(SB, SB._currentSubcategory)
end

ns.SettingsBuilder.RegisterSection(ns, "PowerBar", PowerBarOptions)
