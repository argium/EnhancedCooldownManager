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
    SB.CreateSubcategory("Power Bar")

    SB.ModuleEnabledCheckbox("PowerBar", {
        path = "powerBar.enabled",
        name = "Enable power bar",
    })

    SB.Header("Layout")
    SB.PositioningGroup("powerBar")

    SB.Header("Appearance")
    SB.PathControl({
        type = "checkbox",
        path = "powerBar.showText",
        name = "Show text",
        tooltip = "Display the current value on the bar.",
    })
    SB.PathControl({
        type = "checkbox",
        path = "powerBar.showManaAsPercent",
        name = "Show mana as percent",
        tooltip = "Display mana as percentage instead of raw value.",
    })
    SB.HeightOverrideSlider("powerBar")
    SB.BorderGroup("powerBar.border")
    SB.FontOverrideGroup("powerBar")

    local colorHeading = SB.SubHeader("Colors")
    SB.ColorPickerList("powerBar.colors", POWER_COLOR_DEFS, { parent = colorHeading })

    -- Tick Marks (canvas subcategory)
    ECM.PowerBarTickMarksOptions.RegisterSettings(SB)
end

ECM.SettingsBuilder.RegisterSection(ns, "PowerBar", PowerBarOptions)
