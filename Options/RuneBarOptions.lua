-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local OB = ECM.OptionBuilder

local RuneBarOptions = {}
local DisableUnlessDeathKnight = OB.DisabledUnlessPlayerClass(C.CLASS.DEATHKNIGHT)
local DisableRuneColor = OB.DisabledWhenPathTrue("runeBar.useSpecColor")

function RuneBarOptions.GetOptionsTable()
    local basicArgs = {
        enabled = OB.BuildModuleEnabledToggle("RuneBar", "runeBar.enabled", "Enable rune bar", 2),
        spacer1 = OB.MakeSpacer(20),
        useSpecColorDesc = OB.MakeDescription({
            name = "\nUse your current specialization's color for the rune bar. If disabled, you can set a custom color below.",
            order = 30,
        }),
        useSpecColor = OB.MakePathToggle({
            path = "runeBar.useSpecColor",
            name = "Use specialization color",
            order = 31,
            width = "full",
        }),
    }
    OB.MergeArgs(basicArgs, OB.BuildHeightOverrideArgs("runeBar", 3))
    OB.MergeArgs(basicArgs, OB.BuildPathColorWithReset("color", {
        path = "runeBar.color",
        name = "Rune color",
        order = 32,
        width = "double",
        disabled = DisableRuneColor,
        resetOrder = 33,
        resetDisabled = DisableRuneColor,
    }))

    return OB.MakeGroup({
        name = "Rune Bar",
        order = 4,
        disabled = DisableUnlessDeathKnight,
        args = {
            basicSettings = OB.MakeInlineGroup("Basic Settings", 1, basicArgs),
            positioningSettings = ECM.OptionUtil.MakePositioningGroup("runeBar", 3, {
                widthDesc = "Width when custom positioning is enabled.",
                offsetXDesc = "\nHorizontal offset when custom positioning is enabled.",
                offsetYDesc = "\nVertical offset when custom positioning is enabled.",
            }),
        },
    })
end

OB.RegisterSection(ns, "RuneBar", RuneBarOptions)
