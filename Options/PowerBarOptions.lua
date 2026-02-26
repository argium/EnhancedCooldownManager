-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local POWER_COLOR_DEFS = {
    { key = Enum.PowerType.Mana, name = "Mana" },
    { key = Enum.PowerType.Rage, name = "Rage" },
    { key = Enum.PowerType.Focus, name = "Focus" },
    { key = Enum.PowerType.Energy, name = "Energy" },
    { key = Enum.PowerType.RunicPower, name = "Runic Power" },
    { key = Enum.PowerType.LunarPower, name = "Lunar Power" },
    { key = Enum.PowerType.Maelstrom, name = "Maelstrom" },
    { key = Enum.PowerType.Insanity, name = "Insanity" },
    { key = Enum.PowerType.Fury, name = "Fury" },
}

local PowerBarOptions = {}

function PowerBarOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Power Bar",
        path = "powerBar",
        moduleEnabled = { name = "Enable power bar" },
        args = {
            layoutHeader     = { type = "header", name = "Layout", order = 10 },
            positioning      = { type = "positioning", order = 11 },
            appearanceHeader = { type = "header", name = "Appearance", order = 20 },
            showText         = { type = "toggle", path = "showText", name = "Show text", desc = "Display the current value on the bar.", order = 21 },
            showManaAsPercent = { type = "toggle", path = "showManaAsPercent", name = "Show mana as percent", desc = "Display mana as percentage instead of raw value.", order = 22 },
            height           = { type = "heightOverride", order = 23 },
            border           = { type = "border", path = "border", order = 24 },
            font             = { type = "fontOverride", order = 25 },
            colors           = { type = "colorList", path = "colors", label = "Colors", defs = POWER_COLOR_DEFS, order = 30 },
        },
    })

    -- Tick Marks (canvas subcategory)
    ECM.PowerBarTickMarksOptions.RegisterSettings(SB)
end

ECM.SettingsBuilder.RegisterSection(ns, "PowerBar", PowerBarOptions)
