-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local LayoutOptions = {}

local function createAnchorModeSpec(name, path, order, disabled)
    return {
        type = "select",
        path = path,
        name = name,
        desc = C.POSITION_MODE_DESC,
        values = {
            [C.ANCHORMODE_CHAIN] = C.POSITION_MODE_AUTOMATIC_LABEL,
            [C.ANCHORMODE_DETACHED] = C.POSITION_MODE_DETACHED_LABEL,
            [C.ANCHORMODE_FREE] = C.POSITION_MODE_FREE_LABEL,
        },
        disabled = disabled,
        order = order,
    }
end

function LayoutOptions.RegisterSettings(SB)
    local powerBarDisabled = ECM.OptionUtil.GetIsDisabledDelegate("powerBar")
    local resourceBarDisabled = ECM.OptionUtil.GetIsDisabledDelegate("resourceBar")
    local runeBarDisabled = ECM.OptionUtil.GetIsDisabledDelegate("runeBar")
    local buffBarsDisabled = ECM.OptionUtil.GetIsDisabledDelegate("buffBars")

    SB.RegisterFromTable({
        name = C.LAYOUT_SUBCATEGORY,
        onShow = function() ECM.SetLayoutPreview(true) end,
        onHide = function() ECM.SetLayoutPreview(false) end,
        args = {
            positioningExamples = {
                type = "canvas",
                canvas = ECM.OptionUtil.CreatePositioningExamplesCanvas(),
                height = C.POSITION_MODE_EXPLAINER_HEIGHT,
                order = 0,
            },

            moduleHeader = { type = "header", name = C.MODULE_LAYOUT_HEADER, order = 10 },
            powerBarMode = createAnchorModeSpec("Power Bar", "powerBar.anchorMode", 11, powerBarDisabled),
            resourceBarMode = createAnchorModeSpec("Resource Bar", "resourceBar.anchorMode", 12, resourceBarDisabled),
            runeBarMode = createAnchorModeSpec("Rune Bar", "runeBar.anchorMode", 13, runeBarDisabled),
            buffBarsMode = createAnchorModeSpec("Aura Bars", "buffBars.anchorMode", 14, buffBarsDisabled),

            attachedHeader = { type = "header", name = C.AUTOMATIC_LABEL, order = 20 },
            -- TODO: add description
            offsetY = {
                type = "range",
                path = "global.offsetY",
                name = "Vertical Offset",
                desc = "Vertical gap between the main cooldown icons and the first attached bar.",
                min = 0,
                max = 20,
                step = 1,
                order = 21,
            },
            moduleSpacing = {
                type = "range",
                path = "global.moduleSpacing",
                name = "Vertical Spacing",
                desc = "Vertical spacing between attached modules. Spacing between aura bars is controlled separately.",
                min = 0,
                max = 20,
                step = 1,
                getTransform = function(value)
                    return value or 0
                end,
                order = 22,
            },
            moduleGrowDirection = {
                type = "select",
                path = "global.moduleGrowDirection",
                name = "Grow Direction",
                desc = "Whether the attached stack grows above or below the main cooldown icons.",
                values = {
                    [C.GROW_DIRECTION_DOWN] = "Down",
                    [C.GROW_DIRECTION_UP] = "Up",
                },
                getTransform = function(value)
                    return value or C.GROW_DIRECTION_DOWN
                end,
                order = 23,
            },

            detachedHeader = { type = "header", name = C.DETACHED_AUTOMATIC_HEADER, order = 30 },
            -- TODO: add description
            detachedBarWidth = {
                type = "range",
                path = "global.detachedBarWidth",
                name = C.WIDTH_SETTING_NAME,
                desc = C.DETACHED_WIDTH_DESC,
                min = 100,
                max = 600,
                step = 1,
                getTransform = function(value)
                    return value or C.DEFAULT_BAR_WIDTH
                end,
                order = 31,
            },
            detachedModuleSpacing = {
                type = "range",
                path = "global.detachedModuleSpacing",
                name = C.SPACING_SETTING_NAME,
                desc = C.DETACHED_SPACING_DESC,
                min = 0,
                max = 20,
                step = 1,
                getTransform = function(value)
                    return value or 0
                end,
                order = 32,
            },
            detachedGrowDirection = {
                type = "select",
                path = "global.detachedGrowDirection",
                name = C.GROW_DIRECTION_SETTING_NAME,
                desc = C.DETACHED_GROW_DIRECTION_DESC,
                values = {
                    [C.GROW_DIRECTION_DOWN] = "Down",
                    [C.GROW_DIRECTION_UP] = "Up",
                },
                getTransform = function(value)
                    return value or C.GROW_DIRECTION_DOWN
                end,
                order = 33,
            },

        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, C.LAYOUT_SUBCATEGORY, LayoutOptions)
