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
local isDisabled = function() return not ECM.OptionUtil.GetNestedValue(ns.Addon.db.profile, "powerBar.enabled") end

function PowerBarOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Power Bar",
        path = "powerBar",
        args = {
            enabled           = { type = "toggle", path = "enabled", name = "Enable power bar", order = 0, onSet = function(value) ECM.OptionUtil.SetModuleEnabled("PowerBar", value) end },
            layoutHeader      = { type = "header", name = "Layout", disabled = isDisabled, order = 10 },
            positioning       = { type = "positioning", disabled = isDisabled, order = 11 },
            appearanceHeader  = { type = "header", name = "Appearance", disabled = isDisabled, order = 20 },
            showText          = { type = "toggle", path = "showText", name = "Show text", desc = "Display the current value on the bar.", disabled = isDisabled, order = 21 },
            showManaAsPercent = { type = "toggle", path = "showManaAsPercent", name = "Show mana as percent", desc = "Display mana as percentage instead of raw value.", disabled = isDisabled, order = 22 },
            height            = { type = "heightOverride", disabled = isDisabled, order = 23 },
            border            = { type = "border", path = "border", disabled = isDisabled, order = 24 },
            font              = { type = "fontOverride", disabled = isDisabled, order = 25 },
            colors            = { type = "colorList", path = "colors", label = "Colors", defs = POWER_COLOR_DEFS, disabled = isDisabled, order = 30 },
        },
    })

    -- Tick Marks (canvas subcategory)
    ECM.PowerBarTickMarksOptions.RegisterSettings(SB)
end

ECM.SettingsBuilder.RegisterSection(ns, "PowerBar", PowerBarOptions)
