-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local L = ECM.L

local LayoutOptions = {}

local function createAnchorModeSpec(name, path, order, disabled)
    return {
        type = "select",
        path = path,
        name = name,
        desc = L["POSITION_MODE_DESC"],
        values = {
            [C.ANCHORMODE_CHAIN] = L["POSITION_MODE_ATTACHED"],
            [C.ANCHORMODE_DETACHED] = L["POSITION_MODE_DETACHED"],
            [C.ANCHORMODE_FREE] = L["POSITION_MODE_FREE"],
        },
        disabled = disabled,
        order = order,
    }
end

function LayoutOptions.RegisterSettings(SB)
    local defaultZero = ECM.OptionUtil.CreateDefaultValueTransform(0)
    local defaultDetachedGrowDirection = ECM.OptionUtil.CreateDefaultValueTransform(C.GROW_DIRECTION_DOWN)
    local powerBarDisabled = ECM.OptionUtil.GetIsDisabledDelegate("powerBar")
    local resourceBarDisabled = ECM.OptionUtil.GetIsDisabledDelegate("resourceBar")
    local runeBarDisabled = ECM.OptionUtil.GetIsDisabledDelegate("runeBar")
    local buffBarsDisabled = ECM.OptionUtil.GetIsDisabledDelegate("buffBars")

    local args = {
        positioningExamples = {
            type = "canvas",
            canvas = ECM.OptionUtil.CreatePositioningExamplesCanvas(),
            height = C.POSITION_MODE_EXPLAINER_HEIGHT,
            order = 0,
        },

        moduleHeader = { type = "header", name = L["MODULE_LAYOUT_HEADER"], order = 10 },
        powerBarMode = createAnchorModeSpec(L["POWER_BAR"], "powerBar.anchorMode", 11, powerBarDisabled),
        resourceBarMode = createAnchorModeSpec(L["RESOURCE_BAR"], "resourceBar.anchorMode", 12, resourceBarDisabled),
        runeBarMode = createAnchorModeSpec(L["RUNE_BAR"], "runeBar.anchorMode", 13, runeBarDisabled),
        buffBarsMode = createAnchorModeSpec(L["AURA_BARS"], "buffBars.anchorMode", 14, buffBarsDisabled),

        attachedHeader = { type = "header", name = L["POSITION_MODE_ATTACHED"], order = 20 },
        offsetY = {
            type = "range",
            path = "global.offsetY",
            name = L["VERTICAL_OFFSET"],
            desc = L["VERTICAL_OFFSET_DESC"],
            min = 0,
            max = 20,
            step = 1,
            order = 21,
        },
        moduleSpacing = {
            type = "range",
            path = "global.moduleSpacing",
            name = L["VERTICAL_SPACING"],
            desc = L["VERTICAL_SPACING_DESC"],
            min = 0,
            max = 20,
            step = 1,
            getTransform = defaultZero,
            order = 22,
        },
        moduleGrowDirection = {
            type = "select",
            path = "global.moduleGrowDirection",
            name = L["GROW_DIRECTION"],
            desc = L["GROW_DIRECTION_ATTACHED_DESC"],
            values = {
                [C.GROW_DIRECTION_DOWN] = L["DOWN"],
                [C.GROW_DIRECTION_UP] = L["UP"],
            },
            getTransform = defaultDetachedGrowDirection,
            order = 23,
        },
    }

    for key, spec in pairs(ECM.OptionUtil.CreateDetachedStackArgs()) do
        args[key] = spec
    end

    SB.RegisterFromTable({
        name = L["LAYOUT_SUBCATEGORY"],
        onShow = function()
            ECM.Runtime.SetLayoutPreview(true)
        end,
        onHide = function()
            ECM.Runtime.SetLayoutPreview(false)
        end,
        args = args,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "Layout", LayoutOptions)
