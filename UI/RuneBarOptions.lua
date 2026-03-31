-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local RuneBarOptions = {}
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("runeBar")

function RuneBarOptions.RegisterSettings(SB)
    local args = ns.OptionUtil.CreateBarArgs(isDisabled, { showText = false, border = false })
    args.dkWarning = {
        type = "subheader",
        name = L["DK_ONLY_WARNING"],
        condition = function()
            return not ns.ClassUtil.IsDeathKnight()
        end,
        order = 0,
    }
    args.enabled = {
        type = "toggle",
        path = "enabled",
        name = L["ENABLE_RUNE_BAR"],
        order = 1,
        onSet = ns.OptionUtil.CreateModuleEnabledHandler("RuneBar"),
    }
    args.colorLabel = { type = "subheader", name = L["COLORS"], disabled = isDisabled, order = 30 }
    args.useSpecColor = {
        type = "checkbox",
        path = "useSpecColor",
        name = L["USE_SPEC_COLOR"],
        desc = L["USE_SPEC_COLOR_DESC"],
        parent = "colorLabel",
        disabled = isDisabled,
        order = 31,
    }
    args.runeColor = {
        type = "color",
        path = "color",
        name = L["RUNE_COLOR"],
        parent = "useSpecColor",
        parentCheck = "notChecked",
        disabled = isDisabled,
        order = 32,
    }
    args.bloodColor = {
        type = "color",
        path = "colorBlood",
        name = L["BLOOD_COLOR"],
        parent = "useSpecColor",
        parentCheck = "checked",
        disabled = isDisabled,
        order = 33,
    }
    args.frostColor = {
        type = "color",
        path = "colorFrost",
        name = L["FROST_COLOR"],
        parent = "useSpecColor",
        parentCheck = "checked",
        disabled = isDisabled,
        order = 34,
    }
    args.unholyColor = {
        type = "color",
        path = "colorUnholy",
        name = L["UNHOLY_COLOR"],
        parent = "useSpecColor",
        parentCheck = "checked",
        disabled = isDisabled,
        order = 35,
    }

    SB.RegisterFromTable({
        name = L["RUNE_BAR"],
        path = "runeBar",
        disabled = function()
            return not ns.ClassUtil.IsDeathKnight()
        end,
        args = args,
    })
end

ns.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
