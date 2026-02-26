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

    -- Basic Settings
    SB.Header("Power Bar")

    SB.ModuleEnabledCheckbox("PowerBar", {
        path = "powerBar.enabled",
        name = "Enable power bar",
    })

    SB.HeightOverrideSlider("powerBar")

    -- Display
    SB.Header("Display")

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

    -- Border
    SB.Header("Border")
    SB.BorderGroup("powerBar.border")

    -- Font
    SB.Header("Font")
    SB.FontOverrideGroup("powerBar")

    -- Positioning
    SB.Header("Positioning")
    SB.PositioningGroup("powerBar")

    -- Colors
    SB.Header("Colors")
    SB.ColorPickerList("powerBar.colors", POWER_COLOR_DEFS)

    -- Tick Marks (canvas subcategory)
    ECM.PowerBarTickMarksOptions.RegisterSettings(SB)
end

ECM.SettingsBuilder.RegisterSection(ns, "PowerBar", PowerBarOptions)
