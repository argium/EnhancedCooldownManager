-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local POWER_COLOR_DEFS = {
    { key = Enum.PowerType.Mana,       name = "Mana" },
    { key = Enum.PowerType.Rage,       name = "Rage" },
    { key = Enum.PowerType.Focus,      name = "Focus" },
    { key = Enum.PowerType.Energy,     name = "Energy" },
    { key = Enum.PowerType.RunicPower, name = "Runic Power" },
    { key = Enum.PowerType.LunarPower, name = "Lunar Power" },
    { key = Enum.PowerType.Maelstrom,  name = "Maelstrom" },
    { key = Enum.PowerType.Insanity,   name = "Insanity" },
    { key = Enum.PowerType.Fury,       name = "Fury" },
}


local PowerBarOptions = {}
local isDisabled = ECM.OptionUtil.GetIsDisabledDelegate("powerBar")

function PowerBarOptions.RegisterSettings(SB)
    local args = ECM.OptionUtil.CreateBarArgs(isDisabled)
    args.enabled = {
        type = "toggle", path = "enabled", name = "Enable power bar",
        order = 0, onSet = ECM.OptionUtil.CreateModuleEnabledHandler("PowerBar"),
    }
    args.showManaAsPercent = {
        type = "toggle", path = "showManaAsPercent", name = "Show mana as percent",
        desc = "Display mana as percentage instead of raw value.",
        disabled = isDisabled, order = 22,
    }
    args.colors = { type = "colorList", path = "colors", label = "Colors", defs = POWER_COLOR_DEFS, disabled = isDisabled, order = 30 }

    SB.RegisterFromTable({ name = "Power Bar", path = "powerBar", args = args })
    ECM.PowerBarTickMarksOptions.RegisterSettings(SB)
end

ECM.SettingsBuilder.RegisterSection(ns, "PowerBar", PowerBarOptions)
