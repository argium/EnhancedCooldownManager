-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local OB = ECM.OptionBuilder

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

local function GeneratePowerBarAppearanceArgs()
    local args = {
        showTextDesc = OB.MakeDescription({
            name = "Display the current value on the bar.",
            order = 10,
        }),
        showText = OB.MakePathToggle({
            path = "powerBar.showText",
            name = "Show text",
            order = 11,
            width = "double",
        }),
        showManaAsPercentDesc = OB.MakeDescription({
            name = "\nDisplay mana as percentage instead of raw value.",
            order = 12,
        }),
        showManaAsPercent = OB.MakePathToggle({
            path = "powerBar.showManaAsPercent",
            name = "Show mana as percent",
            order = 13,
            width = "double",
        }),
    }

    OB.MergeArgs(args, OB.MakeSpacer(19))
    OB.MergeArgs(args, OB.BuildBorderArgs("powerBar.border", 20))
    OB.MergeArgs(args, OB.MakeSpacer(29))
    OB.MergeArgs(args, OB.BuildFontOverrideArgs("powerBar", 30))

    return args
end

local function GeneratePowerBarColorArgs()
    local args = {
        colorsDescription = OB.MakeDescription({
            name = "Customize the color of each primary resource type.",
            fontSize = "medium",
            order = 1,
        }),
    }

    OB.MergeArgs(args, OB.BuildColorPickerList("powerBar.colors", POWER_COLOR_DEFS, 2))
    return args
end

local PowerBarOptions = {}

function PowerBarOptions.GetOptionsTable()
    local tickMarks = ECM.PowerBarTickMarksOptions.GetOptionsGroup()
    tickMarks.name = "Tick Marks"
    tickMarks.inline = true
    tickMarks.order = 4

    local basicArgs = {
        enabled = OB.BuildModuleEnabledToggle("PowerBar", "powerBar.enabled", "Enable power bar", 1),
    }
    OB.MergeArgs(basicArgs, OB.BuildHeightOverrideArgs("powerBar", 3))
    OB.MergeArgs(basicArgs, GeneratePowerBarAppearanceArgs())

    return OB.MakeGroup({
        name = "Power Bar",
        order = 2,
        args = {
            powerBarSettings = OB.MakeInlineGroup("Power Bar", 1, basicArgs),
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("powerBar", 2),
            colorSettings = OB.MakeInlineGroup("Colors", 3, GeneratePowerBarColorArgs()),
            tickMarks = tickMarks,
        },
    })
end

OB.RegisterSection(ns, "PowerBar", PowerBarOptions)
