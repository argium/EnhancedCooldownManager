-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local RuneBarOptions = {}

local function isNotDeathKnight()
    local _, classToken = UnitClass("player")
    return classToken ~= C.CLASS.DEATHKNIGHT
end

local function isDisabled()
    return isNotDeathKnight() or not ECM.OptionUtil.GetNestedValue(ns.Addon.db.profile, "runeBar.enabled")
end

function RuneBarOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Rune Bar",
        path = "runeBar",
        disabled = isNotDeathKnight,
        args = {
            dkWarning = { type = "header", name = "|cffFF8800These settings are only applicable to Death Knights.|r", condition = isNotDeathKnight, order = 0 },
            enabled = { type = "toggle", path = "enabled", name = "Enable rune bar", order = 1, onSet = function(value) ECM.OptionUtil.SetModuleEnabled("RuneBar", value) end },
            layoutHeader = { type = "header", name = "Layout", disabled = isDisabled, order = 10 },
            positioning = { type = "positioning", disabled = isDisabled, order = 11 },
            appearanceHeader = { type = "header", name = "Appearance", disabled = isDisabled, order = 20 },
            heightOverride = { type = "heightOverride", disabled = isDisabled, order = 21 },
            fontOverride = { type = "fontOverride", disabled = isDisabled, order = 22 },
            colorLabel = { type = "subheader", name = "Colors", disabled = isDisabled, order = 30 },
            useSpecColor = { type = "checkbox", path = "useSpecColor", name = "Use specialization color", desc = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.", parent = "colorLabel", disabled = isDisabled, order = 31 },
            runeColor = { type = "color", path = "color", name = "Rune color", parent = "useSpecColor", parentCheck = "notChecked", disabled = isDisabled, order = 32 },
            bloodColor = { type = "color", path = "colorBlood", name = "Blood color", parent = "useSpecColor", parentCheck = "checked", disabled = isDisabled, order = 33 },
            frostColor = { type = "color", path = "colorFrost", name = "Frost color", parent = "useSpecColor", parentCheck = "checked", disabled = isDisabled, order = 34 },
            unholyColor = { type = "color", path = "colorUnholy", name = "Unholy color", parent = "useSpecColor", parentCheck = "checked", disabled = isDisabled, order = 35 },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
