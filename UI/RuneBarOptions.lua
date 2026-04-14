-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local RuneBarOptions = {}
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("runeBar")

function RuneBarOptions.RegisterSettings(SB)
    local rows = {
        {
            type = "subheader",
            name = L["DK_ONLY_WARNING"],
            condition = function()
                return not ns.IsDeathKnight()
            end,
        },
        {
            type = "checkbox",
            path = "enabled",
            name = L["ENABLE_RUNE_BAR"],
            onSet = ns.OptionUtil.CreateModuleEnabledHandler("RuneBar"),
        },
    }

    for _, row in ipairs(ns.OptionUtil.CreateBarRows(isDisabled, { showText = false, border = false })) do
        rows[#rows + 1] = row
    end

    rows[#rows + 1] = {
        id = "colorLabel",
        type = "subheader",
        name = L["COLORS"],
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        id = "useSpecColor",
        type = "checkbox",
        path = "useSpecColor",
        name = L["USE_SPEC_COLOR"],
        desc = L["USE_SPEC_COLOR_DESC"],
        parent = "colorLabel",
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        type = "color",
        path = "color",
        name = L["RUNE_COLOR"],
        parent = "useSpecColor",
        parentCheck = "notChecked",
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        type = "color",
        path = "colorBlood",
        name = L["BLOOD_COLOR"],
        parent = "useSpecColor",
        parentCheck = "checked",
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        type = "color",
        path = "colorFrost",
        name = L["FROST_COLOR"],
        parent = "useSpecColor",
        parentCheck = "checked",
        disabled = isDisabled,
    }
    rows[#rows + 1] = {
        type = "color",
        path = "colorUnholy",
        name = L["UNHOLY_COLOR"],
        parent = "useSpecColor",
        parentCheck = "checked",
        disabled = isDisabled,
    }

    SB.RegisterPage({
        name = L["RUNE_BAR"],
        path = "runeBar",
        disabled = function()
            return not ns.IsDeathKnight()
        end,
        rows = rows,
    })
end

ns.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
