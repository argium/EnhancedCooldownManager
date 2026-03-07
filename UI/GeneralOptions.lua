-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local LSMW = LibStub("LibLSMSettingsWidgets-1.0")

local GeneralOptions = {}

function GeneralOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "General",
        path = "global",
        args = {
            -- Visibility
            visHeader = { type = "header", name = "Visibility", order = 10 },
            hideWhenMounted = {
                type = "toggle",
                path = "hideWhenMounted",
                name = "Hide when Mounted",
                desc = "Automatically hide icon and bars while mounted.",
                order = 11,
            },
            hideInRestAreas = {
                type = "toggle",
                path = "hideOutOfCombatInRestAreas",
                name = "Hide in Rest Areas",
                desc = "Automatically hide icon and bars when in rest areas. Bars will reappear if you enter combat.",
                order = 12,
            },
            fade = {
                type = "toggle",
                path = "global.outOfCombatFade.enabled",
                name = "Fade when Out of Combat",
                desc = "Automatically fade bars when out of combat to reduce screen clutter.",
                order = 13,
            },
            fadeOpacity = {
                type = "range",
                path = "global.outOfCombatFade.opacity",
                name = "Out of Combat Opacity",
                desc = "How visible the bars are when faded (0%% = invisible, 100%% = fully visible).",
                min = 0, max = 100, step = 5,
                parent = "fade",
                order = 14,
            },
            fadeExceptInstance = {
                type = "toggle",
                path = "global.outOfCombatFade.exceptInInstance",
                name = "Except Inside Instances",
                parent = "fade",
                order = 15,
            },
            fadeExceptHostile = {
                type = "toggle",
                path = "global.outOfCombatFade.exceptIfTargetCanBeAttacked",
                name = "Except if Target is Hostile",
                parent = "fade",
                order = 16,
            },
            fadeExceptFriendly = {
                type = "toggle",
                path = "global.outOfCombatFade.exceptIfTargetCanBeHelped",
                name = "Except if Target is Friendly",
                parent = "fade",
                order = 17,
            },

            -- Appearance
            appearHeader = { type = "header", name = "Appearance", order = 20 },
            texture = {
                type = "custom",
                path = "texture",
                name = "Bar Texture",
                desc = "Select the texture used for bars.",
                template = LSMW.TEXTURE_PICKER_TEMPLATE,
                order = 21,
            },
            font = {
                type = "custom",
                path = "font",
                name = "Font",
                desc = "Select the font used for bar text.",
                template = LSMW.FONT_PICKER_TEMPLATE,
                order = 22,
            },
            fontSize = {
                type = "range",
                path = "fontSize",
                name = "Font Size",
                min = 6, max = 32, step = 1,
                getTransform = function(value) return value or 11 end,
                order = 23,
            },
            fontOutline = {
                type = "select",
                path = "fontOutline",
                name = "Font Outline",
                values = {
                    NONE = "None",
                    OUTLINE = "Outline",
                    THICKOUTLINE = "Thick Outline",
                    MONOCHROME = "Monochrome",
                },
                order = 24,
            },
            fontShadow = {
                type = "toggle",
                path = "fontShadow",
                name = "Font Shadow",
                desc = "Enable a shadow behind bar text.",
                order = 25,
            },

            -- Layout
            layoutHeader = { type = "header", name = "Layout", order = 30 },
            barHeight = {
                type = "range",
                path = "barHeight",
                name = "Bar Height",
                desc = "Default height for all bars.",
                min = 10, max = 40, step = 1,
                order = 31,
            },
            offsetY = {
                type = "range",
                path = "offsetY",
                name = "Vertical Offset",
                desc = "Vertical gap between the main icons and the first bar.",
                min = 0, max = 20, step = 1,
                order = 32,
            },
            moduleSpacing = {
                type = "range",
                path = "moduleSpacing",
                name = "Vertical Spacing",
                desc = "Vertical spacing between modules. Spacing between buff bars is controlled separately.",
                min = 0, max = 20, step = 1,
                getTransform = function(value) return value or 0 end,
                order = 33,
            },
            growDirection = {
                type = "select",
                path = "moduleGrowDirection",
                name = "Grow Direction",
                desc = "Display bars above or below the cooldown viewer.",
                values = {
                    [C.GROW_DIRECTION_DOWN] = "Down",
                    [C.GROW_DIRECTION_UP] = "Up",
                },
                getTransform = function(value) return value or C.GROW_DIRECTION_DOWN end,
                order = 34,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "General", GeneralOptions)
