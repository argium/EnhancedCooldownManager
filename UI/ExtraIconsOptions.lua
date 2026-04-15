-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
StaticPopupDialogs["ECM_CONFIRM_REMOVE_EXTRA_ICON"] =
    ns.OptionUtil.MakeConfirmDialog(L["REMOVE_ENTRY_CONFIRM"])

local ExtraIconsOptions = ns.ExtraIconsOptions or {}
local Util = assert(ns.ExtraIconsOptionsUtil, "ExtraIconsOptionsUtil missing")

ExtraIconsOptions.key = "extraIcons"
ExtraIconsOptions.name = L["EXTRA_ICONS"]

ExtraIconsOptions.pages = {
    {
        key = "main",
        onShow = function()
            ns.Runtime.SetLayoutPreview(true)
            Util.EnsureItemLoadFrame()
        end,
        onHide = function()
            ns.Runtime.SetLayoutPreview(false)
        end,
        rows = {
    {
        id = "enabled", type = "checkbox", path = "enabled",
        name = L["ENABLE_EXTRA_ICONS"], tooltip = L["ENABLE_EXTRA_ICONS_DESC"],
        onSet = function(ctx, value)
            ns.OptionUtil.CreateModuleEnabledHandler("ExtraIcons")(ctx, value)
            ctx.page:Refresh()
        end,
    },
    {
        id = "specialRowsLegend", type = "info", name = "",
        value = L["EXTRA_ICONS_SPECIAL_ROWS_LEGEND"],
        wide = true, multiline = true, height = 24,
    },
    {
        id = "viewers", type = "sectionList", height = Util.VIEWER_COLLECTION_HEIGHT,
        disabled = Util.IsDisabled,
        sections = Util.BuildSections,
        onDefault = Util.ResetToDefaults,
    },
        },
    },
}

ns.ExtraIconsOptions = ExtraIconsOptions
