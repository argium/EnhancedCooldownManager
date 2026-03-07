-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local RuneBarOptions = {}

local function isNotDeathKnight()
    return not ECM.ClassUtil.IsDeathKnight()
end

local function isDisabled()
    return isNotDeathKnight() or not ECM.OptionUtil.GetNestedValue(ns.Addon.db.profile, "runeBar.enabled")
end

function RuneBarOptions.RegisterSettings(SB)
    local args = ECM.OptionUtil.CreateBarArgs(isDisabled, { showText = false, border = false })
    args.dkWarning = { type = "subheader", name = "|cffFF8800These settings are only applicable to Death Knights.|r", condition = isNotDeathKnight, order = 0 }
    args.enabled = {
        type = "toggle", path = "enabled", name = "Enable rune bar",
        order = 1, onSet = ECM.OptionUtil.CreateModuleEnabledHandler("RuneBar"),
    }
    args.colorLabel = { type = "subheader", name = "Colors", disabled = isDisabled, order = 30 }
    args.useSpecColor = { type = "checkbox", path = "useSpecColor", name = "Use specialization color", desc = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.", parent = "colorLabel", disabled = isDisabled, order = 31 }
    args.runeColor = { type = "color", path = "color", name = "Rune color", parent = "useSpecColor", parentCheck = "notChecked", disabled = isDisabled, order = 32 }
    args.bloodColor = { type = "color", path = "colorBlood", name = "Blood color", parent = "useSpecColor", parentCheck = "checked", disabled = isDisabled, order = 33 }
    args.frostColor = { type = "color", path = "colorFrost", name = "Frost color", parent = "useSpecColor", parentCheck = "checked", disabled = isDisabled, order = 34 }
    args.unholyColor = { type = "color", path = "colorUnholy", name = "Unholy color", parent = "useSpecColor", parentCheck = "checked", disabled = isDisabled, order = 35 }

    SB.RegisterFromTable({
        name = "Rune Bar",
        path = "runeBar",
        disabled = isNotDeathKnight,
        args = args,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
