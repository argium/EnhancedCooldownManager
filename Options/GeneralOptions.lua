-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants
local OB = ECM.OptionBuilder

local function IsCombatFadeDisabled()
    local db = mod.db
    return not (db and db.profile and db.profile.global and db.profile.global.outOfCombatFade
        and db.profile.global.outOfCombatFade.enabled)
end

local GeneralOptions = {}

function GeneralOptions.GetOptionsTable()
    local basicArgs = {
        hideWhenMountedDesc = OB.MakeDescription({
            name = "Automatically hide icons and bars when mounted or in a vehicle, and show them when dismounted or out of vehicle.",
            order = 3,
        }),
        hideWhenMounted = OB.MakePathToggle({
            path = "global.hideWhenMounted",
            name = "Hide when mounted or in vehicle",
            order = 4,
            width = "full",
        }),
        hideOutOfCombatInRestAreas = OB.MakePathToggle({
            path = "global.hideOutOfCombatInRestAreas",
            name = "Always hide when out of combat in rest areas",
            order = 6,
            width = "full",
        }),
    }
    OB.MergeArgs(basicArgs, OB.BuildPathSelectWithReset("texture", {
        path = "global.texture",
        name = "Bar Texture",
        order = 8,
        width = "double",
        dialogControl = "LSM30_Statusbar",
        values = ECM.SharedMediaOptions.GetStatusbarValues,
        resetOrder = 9,
    }))
    OB.MergeArgs(basicArgs, OB.BuildPathSelectWithReset("font", {
        path = "global.font",
        name = "Font",
        order = 10,
        dialogControl = "LSM30_Font",
        values = ECM.SharedMediaOptions.GetFontValues,
        resetOrder = 12,
    }))
    OB.MergeArgs(basicArgs, OB.BuildPathRangeWithReset("fontSize", {
        path = "global.fontSize",
        name = "Font Size",
        order = 14,
        min = 6,
        max = 32,
        step = 1,
        getTransform = function(value)
            return value or 11
        end,
        resetOrder = 15,
    }))

    local layoutArgs = {
        offsetYDesc = OB.MakeDescription({
            name = "Vertical gap between the main icons and the first bar.",
            order = 1,
        }),
        moduleSpacingDesc = OB.MakeDescription({
            name = "\nAdds vertical spacing between modules. Spacing between individual buff bars is configured separately in their options.",
            order = 4,
        }),
        moduleGrowDirectionDesc = OB.MakeDescription({
            name = "\nChoose whether chained modules stack below or above the cooldown viewer.",
            order = 7,
        }),
    }
    OB.MergeArgs(layoutArgs, OB.BuildPathRangeWithReset("offsetY", {
        path = "global.offsetY",
        name = "Vertical Offset",
        order = 2,
        min = 0,
        max = 20,
        step = 1,
        resetOrder = 3,
    }))
    OB.MergeArgs(layoutArgs, OB.BuildPathRangeWithReset("moduleSpacing", {
        path = "global.moduleSpacing",
        name = "Vertical Spacing",
        order = 5,
        min = 0,
        max = 20,
        step = 1,
        getTransform = function(value)
            return value or 0
        end,
        resetOrder = 6,
    }))
    OB.MergeArgs(layoutArgs, OB.BuildPathSelectWithReset("moduleGrowDirection", {
        path = "global.moduleGrowDirection",
        name = "Module Grow Direction",
        order = 8,
        width = "double",
        values = {
            [C.GROW_DIRECTION_DOWN] = "Down",
            [C.GROW_DIRECTION_UP] = "Up",
        },
        getTransform = function(value)
            return value or C.GROW_DIRECTION_DOWN
        end,
        resetOrder = 9,
    }))

    local combatFadeArgs = {
        combatFadeEnabledDesc = OB.MakeDescription({
            name = "Automatically fade bars when out of combat to reduce screen clutter.",
            order = 1,
            fontSize = "medium",
        }),
        combatFadeEnabled = OB.MakePathToggle({
            path = "global.outOfCombatFade.enabled",
            name = "Fade when out of combat",
            order = 2,
            width = "full",
        }),
        combatFadeOpacityDesc = OB.MakeDescription({
            name = "\nHow visible the bars are when faded (0% = invisible, 100% = fully visible).",
            order = 3,
        }),
        spacer2 = OB.MakeSpacer(6),
        combatFadeExceptionsDesc = OB.MakeDescription({
            name = "\nExceptions to combat fading. If any of the enabled exceptions apply, bars will not fade even if you're out of combat.",
            order = 7,
        }),
        combatFadeExceptInInstance = OB.MakePathToggle({
            path = "global.outOfCombatFade.exceptInInstance",
            name = "Except inside instances",
            order = 8,
            width = "full",
            disabled = IsCombatFadeDisabled,
        }),
        exceptIfTargetCanBeAttackedEnabled = OB.MakePathToggle({
            path = "global.outOfCombatFade.exceptIfTargetCanBeAttacked",
            name = "Except when your current target can be attacked",
            order = 10,
            width = "full",
            disabled = IsCombatFadeDisabled,
        }),
        exceptIfTargetCanBeHelpedEnabled = OB.MakePathToggle({
            path = "global.outOfCombatFade.exceptIfTargetCanBeHelped",
            name = "Except when your current target can be helped",
            order = 11,
            width = "full",
            disabled = IsCombatFadeDisabled,
        }),
    }
    OB.MergeArgs(combatFadeArgs, OB.BuildPathRangeWithReset("combatFadeOpacity", {
        path = "global.outOfCombatFade.opacity",
        name = "Out of combat opacity",
        order = 4,
        width = "double",
        min = 0,
        max = 100,
        step = 5,
        disabled = IsCombatFadeDisabled,
        resetOrder = 5,
        resetDisabled = IsCombatFadeDisabled,
    }))

    return OB.MakeGroup({
        name = "General",
        order = 1,
        args = {
            generalSettings = OB.MakeInlineGroup("General Settings", 1, basicArgs),
            layoutSettings = OB.MakeInlineGroup("Layout", 2, layoutArgs),
            combatFadeSettings = OB.MakeInlineGroup("Combat Fade", 4, combatFadeArgs),
        },
    })
end

OB.RegisterSection(ns, "General", GeneralOptions)
