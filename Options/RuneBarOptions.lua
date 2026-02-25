-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local OB = ECM.OptionBuilder

local RuneBarOptions = {}
local DisableUnlessDeathKnight = OB.DisabledUnlessPlayerClass(C.CLASS.DEATHKNIGHT)
local DisableRuneColor = OB.DisabledWhenPathTrue("runeBar.useSpecColor")

local function GenerateRuneBarAppearanceArgs()
    local args = {}
    OB.MergeArgs(args, OB.BuildFontOverrideArgs("runeBar", 10))
    return args
end

local function GenerateRuneBarColorArgs()
    local args = {
        useSpecColorDesc = OB.MakeDescription({
            name = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.",
            order = 1,
        }),
        useSpecColor = OB.MakePathToggle({
            path = "runeBar.useSpecColor",
            name = "Use specialization color",
            order = 2,
            width = "double",
        }),
    }

    OB.MergeArgs(args, OB.BuildPathColorWithReset("color", {
        path = "runeBar.color",
        name = "Rune color",
        order = 3,
        width = "double",
        disabled = DisableRuneColor,
        resetOrder = 4,
        resetDisabled = DisableRuneColor,
    }))

    return args
end

function RuneBarOptions.GetOptionsTable()
    local basicArgs = {
        enabled = OB.BuildModuleEnabledToggle("RuneBar", "runeBar.enabled", "Enable rune bar", 1),
    }
    OB.MergeArgs(basicArgs, OB.BuildHeightOverrideArgs("runeBar", 3))
    OB.MergeArgs(basicArgs, GenerateRuneBarAppearanceArgs())

    return OB.MakeGroup({
        name = "Rune Bar",
        order = 4,
        disabled = DisableUnlessDeathKnight,
        args = {
            runeBarSettings = OB.MakeInlineGroup("Rune Bar", 1, basicArgs),
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("runeBar", 2, {
                widthDesc = "Width when custom positioning is enabled.",
                offsetXDesc = "\nHorizontal offset when custom positioning is enabled.",
                offsetYDesc = "\nVertical offset when custom positioning is enabled.",
            }),
            colorSettings = OB.MakeInlineGroup("Colors", 3, GenerateRuneBarColorArgs()),
        },
    })
end

OB.RegisterSection(ns, "RuneBar", RuneBarOptions)
