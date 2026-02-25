-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local OB = ECM.OptionBuilder

local RESOURCE_COLOR_DEFS = {
    { key = "souls", name = "Soul Fragments (Demon Hunter)" },
    { key = "devourerNormal", name = "Souls Fragments (Devourer)" },
    { key = "devourerMeta", name = "Void Fragments (Devourer)" },
    { key = Enum.PowerType.ArcaneCharges, name = "Arcane Charges" },
    { key = Enum.PowerType.Chi, name = "Chi" },
    { key = Enum.PowerType.ComboPoints, name = "Combo Points" },
    { key = Enum.PowerType.Essence, name = "Essence" },
    { key = Enum.PowerType.HolyPower, name = "Holy Power" },
    { key = C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON, name = "Maelstrom Weapon (Enhancement)" },
    { key = Enum.PowerType.SoulShards, name = "Soul Shards" },
}

local function GenerateResourceColorArgs()
    local args = {
        colorsSpacer = OB.MakeSpacer(4),
        colorsDescription = OB.MakeDescription({
            name = "Customize the color of each resource type. Colors only apply to the relevant class/spec.",
            fontSize = "medium",
            order = 5,
        }),
    }

    OB.MergeArgs(args, OB.BuildBorderArgs("resourceBar.border", 1))
    OB.MergeArgs(args, OB.BuildColorPickerList("resourceBar.colors", RESOURCE_COLOR_DEFS, 10))

    return args
end

local ResourceBarOptions = {}
local DisableForDeathKnight = OB.DisabledIfPlayerClass(C.CLASS.DEATHKNIGHT)

function ResourceBarOptions.GetOptionsTable()
    local basicArgs = {
        enabled = OB.BuildModuleEnabledToggle("ResourceBar", "resourceBar.enabled", "Enable resource bar", 1),
        showTextDesc = OB.MakeDescription({
            name = "Display the current value on the bar.",
            order = 2,
        }),
        showText = OB.MakePathToggle({
            path = "resourceBar.showText",
            name = "Show text",
            order = 3,
            width = "full",
        }),
    }
    OB.MergeArgs(basicArgs, OB.BuildHeightOverrideArgs("resourceBar", 4))
    OB.MergeArgs(basicArgs, OB.BuildFontOverrideArgs("resourceBar", 7))

    return OB.MakeGroup({
        name = "Resource Bar",
        order = 3,
        disabled = DisableForDeathKnight,
        args = {
            basicSettings = OB.MakeInlineGroup("Basic Settings", 1, basicArgs),
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("resourceBar", 2),
            resourceColors = OB.MakeInlineGroup("Display Options", 3, GenerateResourceColorArgs()),
        },
    })
end

OB.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
