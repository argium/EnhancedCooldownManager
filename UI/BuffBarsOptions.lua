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

SpellColorsPage.RegisterSection({
    key = C.SCOPE_BUFFBARS,
    label = L["AURA_BARS"],
    scope = C.SCOPE_BUFFBARS,
    isDisabledDelegate = SpellColorsPage.CreateSectionDisabledDelegate(C.SCOPE_BUFFBARS, "BuffBars"),
    ownerModuleName = "BuffBars",
})

local defaultZero = ns.OptionUtil.CreateDefaultValueTransform(0)
local layoutMovedButton = ns.OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton
layoutMovedButton.id = "layoutMovedButton"

BuffBarsOptions.key = "buffBars"
BuffBarsOptions.name = L["AURA_BARS"]
BuffBarsOptions.pages = {
    {
        key = "main",
        rows = {
            {
                id = "enabled",
                type = "checkbox",
                path = "enabled",
                name = L["ENABLE_AURA_BARS"],
                tooltip = L["ENABLE_AURA_BARS_DESC"],
                onSet = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", L["DISABLE_AURA_BARS_RELOAD"]),
            },

            layoutMovedButton,

            -- Appearance
            { id = "appearanceHeader", type = "header", name = L["APPEARANCE"], disabled = isBuffBarsDisabled },
            {
                id = "showIcon",
                type = "checkbox",
                path = "showIcon",
                name = L["SHOW_ICON"],
                disabled = isBuffBarsDisabled,
            },
            {
                id = "showSpellName",
                type = "checkbox",
                path = "showSpellName",
                name = L["SHOW_SPELL_NAME"],
                disabled = isBuffBarsDisabled,
            },
            {
                id = "showDuration",
                type = "checkbox",
                path = "showDuration",
                name = L["SHOW_REMAINING_DURATION"],
                disabled = isBuffBarsDisabled,
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
                disabled = isBuffBarsDisabled,
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
                disabled = isBuffBarsDisabled,
                getTransform = defaultZero,
            },
            (function()
                local row = ns.OptionUtil.CreateFontOverrideRow(isBuffBarsDisabled)
                row.id = "fontOverride"
                return row
            end)(),
        },
    },
}

BuffBarsOptions._BuildSpellColorRows = SpellColorsPage._BuildSpellColorRows
BuffBarsOptions._CollectIncompleteSpellColorRows = SpellColorsPage._CollectIncompleteSpellColorRows
BuffBarsOptions._GetSpellColorsPageState = SpellColorsPage._GetSpellColorsPageState
BuffBarsOptions._BuildSpellColorKeyTooltipLines = SpellColorsPage._BuildSpellColorKeyTooltipLines
