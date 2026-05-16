-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local BuffBarsOptions = {}
ns.BuffBarsOptions = BuffBarsOptions

local SpellColorsPage = ns.SpellColorsPage
local isBuffBarsDisabled = ns.OptionUtil.GetIsDisabledDelegate(C.SCOPE_BUFFBARS)

local layoutMovedButton = ns.OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton
layoutMovedButton.id = "layoutMovedButton"

local rows = {
    {
        id = "enabled",
        type = "checkbox",
        path = "enabled",
        name = L["ENABLE_AURA_BARS"],
        tooltip = L["ENABLE_AURA_BARS_DESC"],
        onSet = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", L["DISABLE_AURA_BARS_RELOAD"]),
    },

    layoutMovedButton,
}

for _, row in ipairs(ns.OptionUtil.CreateAuraBarModuleRows(isBuffBarsDisabled)) do
    rows[#rows + 1] = row
end

function BuffBarsOptions.OnInitialize()
    SpellColorsPage:RegisterSection({
        key = C.SCOPE_BUFFBARS,
        label = L["AURA_BARS"],
        scope = C.SCOPE_BUFFBARS,
        isDisabledDelegate = SpellColorsPage:CreateSectionDisabledDelegate(C.SCOPE_BUFFBARS),
        ownerModuleName = "BuffBars",
    })
end

BuffBarsOptions.key = "buffBars"
BuffBarsOptions.name = L["AURA_BARS"]
BuffBarsOptions.pages = {
    {
        key = "main",
        rows = rows,
    },
}
