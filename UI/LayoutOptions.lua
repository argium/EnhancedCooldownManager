-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local LayoutOptions = {}
ns.LayoutOptions = LayoutOptions

local function createAnchorModeSpec(name, path, disabled)
    return {
        type = "dropdown",
        path = path,
        name = name,
        desc = L["POSITION_MODE_DESC"],
        values = {
            [C.ANCHORMODE_CHAIN] = L["POSITION_MODE_ATTACHED"],
            [C.ANCHORMODE_DETACHED] = L["POSITION_MODE_DETACHED"],
            [C.ANCHORMODE_FREE] = L["POSITION_MODE_FREE"],
        },
        disabled = disabled,
    }
end

local defaultZero = ns.OptionUtil.CreateDefaultValueTransform(0)
local defaultDetachedGrowDirection = ns.OptionUtil.CreateDefaultValueTransform(C.GROW_DIRECTION_DOWN)
local powerBarDisabled = ns.OptionUtil.GetIsDisabledDelegate("powerBar")
local resourceBarDisabled = ns.OptionUtil.GetIsDisabledDelegate("resourceBar")
local runeBarDisabled = ns.OptionUtil.GetIsDisabledDelegate("runeBar")
local buffBarsDisabled = ns.OptionUtil.GetIsDisabledDelegate("buffBars")

local rows = {
    {
        type = "canvas",
        canvas = ns.OptionUtil.CreatePositioningExamplesCanvas(),
        height = C.POSITION_MODE_EXPLAINER_HEIGHT,
    },
    {
        type = "header",
        name = L["MODULE_LAYOUT_HEADER"],
    },
    createAnchorModeSpec(L["POWER_BAR"], "powerBar.anchorMode", powerBarDisabled),
    createAnchorModeSpec(L["RESOURCE_BAR"], "resourceBar.anchorMode", resourceBarDisabled),
    createAnchorModeSpec(L["RUNE_BAR"], "runeBar.anchorMode", runeBarDisabled),
    createAnchorModeSpec(L["AURA_BARS"], "buffBars.anchorMode", buffBarsDisabled),
    {
        type = "header",
        name = L["POSITION_MODE_ATTACHED"],
    },
    {
        type = "slider",
        path = "global.offsetY",
        name = L["VERTICAL_OFFSET"],
        desc = L["VERTICAL_OFFSET_DESC"],
        min = 0,
        max = 20,
        step = 1,
    },
    {
        type = "slider",
        path = "global.moduleSpacing",
        name = L["VERTICAL_SPACING"],
        desc = L["VERTICAL_SPACING_DESC"],
        min = 0,
        max = 20,
        step = 1,
        getTransform = defaultZero,
    },
    {
        type = "dropdown",
        path = "global.moduleGrowDirection",
        name = L["GROW_DIRECTION"],
        desc = L["GROW_DIRECTION_ATTACHED_DESC"],
        values = {
            [C.GROW_DIRECTION_DOWN] = L["DOWN"],
            [C.GROW_DIRECTION_UP] = L["UP"],
        },
        getTransform = defaultDetachedGrowDirection,
    },
}

for _, row in ipairs(ns.OptionUtil.CreateDetachedStackRows()) do
    rows[#rows + 1] = row
end

LayoutOptions.key = "layout"
LayoutOptions.name = L["LAYOUT_SUBCATEGORY"]
LayoutOptions.path = ""
LayoutOptions.onShow = function()
    ns.Runtime.SetLayoutPreview(true)
end
LayoutOptions.onHide = function()
    ns.Runtime.SetLayoutPreview(false)
end
LayoutOptions.rows = rows
