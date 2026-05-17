-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local ExternalBarsOptions = {}
ns.ExternalBarsOptions = ExternalBarsOptions

local SpellColorsPage = ns.SpellColorsPage
local isModuleDisabled = ns.OptionUtil.GetIsDisabledDelegate(C.SCOPE_EXTERNALBARS)
local layoutMovedButton = ns.OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton
layoutMovedButton.id = "layoutMovedButton"

local rows = {
    {
        id = "enabled",
        type = "checkbox",
        path = "enabled",
        name = L["ENABLE_EXTERNAL_BARS"],
        tooltip = L["ENABLE_EXTERNAL_BARS_DESC"],
        onSet = ns.OptionUtil.CreateModuleEnabledHandler("ExternalBars", L["DISABLE_EXTERNAL_BARS_RELOAD"]),
    },

    layoutMovedButton,
}

for _, row in ipairs(ns.OptionUtil.CreateAuraBarModuleRows(isModuleDisabled, {
    {
        id = "hideOriginalIcons",
        type = "checkbox",
        path = "hideOriginalIcons",
        name = L["HIDE_ORIGINAL_ICONS"],
        tooltip = L["HIDE_ORIGINAL_ICONS_DESC"],
        disabled = isModuleDisabled,
    },
})) do
    rows[#rows + 1] = row
end

function ExternalBarsOptions.OnInitialize()
    SpellColorsPage:RegisterSection({
        key = C.SCOPE_EXTERNALBARS,
        label = L["EXTERNAL_BARS"],
        scope = C.SCOPE_EXTERNALBARS,
        isDisabledDelegate = SpellColorsPage:CreateSectionDisabledDelegate(C.SCOPE_EXTERNALBARS),
        ownerModuleName = "ExternalBars",
    })
end

ExternalBarsOptions.key = "externalBars"
ExternalBarsOptions.name = L["EXTERNAL_BARS"]
ExternalBarsOptions.pages = {
    {
        key = "main",
        rows = rows,
    },
}
