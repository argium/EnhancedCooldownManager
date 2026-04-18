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
local defaultZero = ns.OptionUtil.CreateDefaultValueTransform(0)
local layoutMovedButton = ns.OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton
layoutMovedButton.id = "layoutMovedButton"

SpellColorsPage.RegisterSection({
    key = C.SCOPE_EXTERNALBARS,
    label = L["EXTERNAL_BARS"],
    scope = C.SCOPE_EXTERNALBARS,
    isDisabledDelegate = SpellColorsPage.CreateSectionDisabledDelegate(C.SCOPE_EXTERNALBARS, "ExternalBars"),
    ownerModuleName = "ExternalBars",
})

ExternalBarsOptions.key = "externalBars"
ExternalBarsOptions.name = L["EXTERNAL_BARS"]
ExternalBarsOptions.pages = {
    {
        key = "main",
        rows = {
            {
                id = "enabled",
                type = "checkbox",
                path = "enabled",
                name = L["ENABLE_EXTERNAL_BARS"],
                tooltip = L["ENABLE_EXTERNAL_BARS_DESC"],
                onSet = ns.OptionUtil.CreateModuleEnabledHandler("ExternalBars", L["DISABLE_EXTERNAL_BARS_RELOAD"]),
            },

            layoutMovedButton,

            { id = "appearanceHeader", type = "header", name = L["APPEARANCE"], disabled = isModuleDisabled },
            {
                id = "hideOriginalIcons",
                type = "checkbox",
                path = "hideOriginalIcons",
                name = L["HIDE_ORIGINAL_ICONS"],
                tooltip = L["HIDE_ORIGINAL_ICONS_DESC"],
                disabled = isModuleDisabled,
            },
            {
                id = "showIcon",
                type = "checkbox",
                path = "showIcon",
                name = L["SHOW_ICON"],
                disabled = isModuleDisabled,
            },
            {
                id = "showSpellName",
                type = "checkbox",
                path = "showSpellName",
                name = L["SHOW_SPELL_NAME"],
                disabled = isModuleDisabled,
            },
            {
                id = "showDuration",
                type = "checkbox",
                path = "showDuration",
                name = L["SHOW_REMAINING_DURATION"],
                disabled = isModuleDisabled,
            },
            {
                id = "height",
                type = "slider",
                path = "height",
                name = L["HEIGHT_OVERRIDE"],
                tooltip = L["HEIGHT_OVERRIDE_DESC"],
                min = 0,
                max = 40,
                step = 1,
                disabled = isModuleDisabled,
                getTransform = defaultZero,
                setTransform = function(value)
                    return value > 0 and value or nil
                end,
            },
            {
                id = "verticalSpacing",
                type = "slider",
                path = "verticalSpacing",
                name = L["AURA_VERTICAL_SPACING"],
                tooltip = L["AURA_VERTICAL_SPACING_DESC"],
                min = 0,
                max = 20,
                step = 1,
                disabled = isModuleDisabled,
                getTransform = defaultZero,
            },
            (function()
                local row = ns.OptionUtil.CreateFontOverrideRow(isModuleDisabled)
                row.id = "fontOverride"
                return row
            end)(),
        },
    },
}
