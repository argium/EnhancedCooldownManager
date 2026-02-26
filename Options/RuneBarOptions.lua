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

function RuneBarOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Rune Bar",
        path = "runeBar",
        disabled = isNotDeathKnight,
        moduleEnabled = { name = "Enable rune bar" },
        args = {
            dkWarning = { type = "header", name = "|cffFF8800These settings are only applicable to Death Knights.|r", condition = isNotDeathKnight, order = 1 },
            layoutHeader = { type = "header", name = "Layout", order = 10 },
            positioning = { type = "positioning", order = 11 },
            appearanceHeader = { type = "header", name = "Appearance", order = 20 },
            heightOverride = { type = "heightOverride", order = 21 },
            fontOverride = { type = "fontOverride", order = 22 },
            colorLabel = { type = "label", name = "Colors", order = 30 },
            useSpecColor = { type = "checkbox", path = "useSpecColor", name = "Use specialization color", desc = "Use your current specialization's color for the rune bar. If disabled, you can set a custom color below.", parent = "colorLabel", order = 31 },
            runeColor = { type = "color", path = "color", name = "Rune color", parent = "useSpecColor", parentCheck = "notChecked", order = 32 },
            bloodColor = { type = "color", path = "colorBlood", name = "Blood color", parent = "useSpecColor", parentCheck = "checked", order = 33 },
            frostColor = { type = "color", path = "colorFrost", name = "Frost color", parent = "useSpecColor", parentCheck = "checked", order = 34 },
            unholyColor = { type = "color", path = "colorUnholy", name = "Unholy color", parent = "useSpecColor", parentCheck = "checked", order = 35 },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "RuneBar", RuneBarOptions)
