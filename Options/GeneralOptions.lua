-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

local GeneralOptions = {}

function GeneralOptions.RegisterSettings(SB)
    SB.UseRootCategory()

    -- General Settings
    SB.Header("General Settings")

    SB.PathControl({
        type = "checkbox",
        path = "global.hideWhenMounted",
        name = "Hide when mounted or in vehicle",
        tooltip = "Automatically hide icons and bars when mounted or in a vehicle, and show them when dismounted.",
    })

    SB.PathControl({
        type = "checkbox",
        path = "global.hideOutOfCombatInRestAreas",
        name = "Always hide when out of combat in rest areas",
    })

    SB.PathControl({
        type = "custom",
        template = LSMW.TEXTURE_PICKER_TEMPLATE,
        path = "global.texture",
        name = "Bar Texture",
        tooltip = "Select the texture used for bars.",
    })

    SB.PathControl({
        type = "custom",
        template = LSMW.FONT_PICKER_TEMPLATE,
        path = "global.font",
        name = "Font",
        tooltip = "Select the font used for bar text.",
    })

    SB.PathControl({
        type = "slider",
        path = "global.fontSize",
        name = "Font Size",
        min = 6,
        max = 32,
        step = 1,
        getTransform = function(value) return value or 11 end,
    })

    SB.PathControl({
        type = "dropdown",
        path = "global.fontOutline",
        name = "Font Outline",
        values = {
            NONE = "None",
            OUTLINE = "Outline",
            THICKOUTLINE = "Thick Outline",
            MONOCHROME = "Monochrome",
        },
    })

    SB.PathControl({
        type = "checkbox",
        path = "global.fontShadow",
        name = "Font Shadow",
        tooltip = "Enable a shadow behind bar text.",
    })

    -- Layout
    SB.Header("Layout")

    SB.PathControl({
        type = "slider",
        path = "global.barHeight",
        name = "Bar Height",
        tooltip = "Default height for all bars.",
        min = 10,
        max = 40,
        step = 1,
    })

    SB.PathControl({
        type = "slider",
        path = "global.offsetY",
        name = "Vertical Offset",
        tooltip = "Vertical gap between the main icons and the first bar.",
        min = 0,
        max = 20,
        step = 1,
    })

    SB.PathControl({
        type = "slider",
        path = "global.moduleSpacing",
        name = "Module Spacing",
        tooltip = "Vertical spacing between modules. Spacing between individual buff bars is configured separately.",
        min = 0,
        max = 20,
        step = 1,
        getTransform = function(value) return value or 0 end,
    })

    SB.PathControl({
        type = "dropdown",
        path = "global.moduleGrowDirection",
        name = "Module Grow Direction",
        tooltip = "Choose whether chained modules stack below or above the cooldown viewer.",
        values = {
            [C.GROW_DIRECTION_DOWN] = "Down",
            [C.GROW_DIRECTION_UP] = "Up",
        },
        getTransform = function(value) return value or C.GROW_DIRECTION_DOWN end,
    })

    -- Combat Fade
    SB.Header("Combat Fade")

    local fadeInit = SB.PathControl({
        type = "checkbox",
        path = "global.outOfCombatFade.enabled",
        name = "Fade when out of combat",
        tooltip = "Automatically fade bars when out of combat to reduce screen clutter.",
    })

    SB.PathControl({
        type = "slider",
        path = "global.outOfCombatFade.opacity",
        name = "Out of combat opacity",
        tooltip = "How visible the bars are when faded (0%% = invisible, 100%% = fully visible).",
        min = 0,
        max = 100,
        step = 5,
        parent = fadeInit,
    })

    SB.PathControl({
        type = "checkbox",
        path = "global.outOfCombatFade.exceptInInstance",
        name = "Except inside instances",
        parent = fadeInit,
    })

    SB.PathControl({
        type = "checkbox",
        path = "global.outOfCombatFade.exceptIfTargetCanBeAttacked",
        name = "Except when your current target can be attacked",
        parent = fadeInit,
    })

    SB.PathControl({
        type = "checkbox",
        path = "global.outOfCombatFade.exceptIfTargetCanBeHelped",
        name = "Except when your current target can be helped",
        parent = fadeInit,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "General", GeneralOptions)
