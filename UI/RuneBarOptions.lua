-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local RuneBarOptions = {}
ns.RuneBarOptions = RuneBarOptions
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("runeBar")
local function isUseSpecColorDisabled()
    local runeBar = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.runeBar
    return isDisabled() or not (runeBar and runeBar.useSpecColor)
end

local function isSingleRuneColorDisabled()
    local runeBar = ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.runeBar
    return isDisabled() or (runeBar and runeBar.useSpecColor) == true
end

local rows = {
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

if not ns.IsDeathKnight() then
    table.insert(rows, 1, {
        type = "subheader",
        name = L["DK_ONLY_WARNING"],
    })
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
    tooltip = L["USE_SPEC_COLOR_DESC"],
    disabled = isDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "color",
    name = L["RUNE_COLOR"],
    disabled = isSingleRuneColorDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "colorBlood",
    name = L["BLOOD_COLOR"],
    disabled = isUseSpecColorDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "colorFrost",
    name = L["FROST_COLOR"],
    disabled = isUseSpecColorDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "colorUnholy",
    name = L["UNHOLY_COLOR"],
    disabled = isUseSpecColorDisabled,
}

RuneBarOptions.key = "runeBar"
RuneBarOptions.name = L["RUNE_BAR"]
RuneBarOptions.disabled = function()
    return not ns.IsDeathKnight()
end
RuneBarOptions.pages = {
    {
        key = "main",
        rows = rows,
    },
}
