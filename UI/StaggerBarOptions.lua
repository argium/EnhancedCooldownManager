-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ns.L
local StaggerBarOptions = {}
ns.StaggerBarOptions = StaggerBarOptions
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("staggerBar")

local rows = {
    {
        type = "checkbox",
        path = "enabled",
        name = L["ENABLE_STAGGER_BAR"],
        onSet = ns.OptionUtil.CreateModuleEnabledHandler("StaggerBar"),
    },
}

for _, row in ipairs(ns.OptionUtil.CreateBarRows(isDisabled, { showText = true, border = false })) do
    rows[#rows + 1] = row
end

-- Always present so the row tracks the live spec; hidden while the player is a
-- Brewmaster Monk. The predicate is re-evaluated on each refresh, so switching
-- specs shows or hides the warning without a stale insert from file-load time.
table.insert(rows, 1, {
    type = "subheader",
    name = L["BREWMASTER_ONLY_WARNING"],
    hidden = function()
        return ns.ClassUtil.IsBrewmasterMonk()
    end,
})

rows[#rows + 1] = {
    id = "colorLabel",
    type = "subheader",
    name = L["COLORS"],
    disabled = isDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "colorLight",
    name = L["STAGGER_LIGHT_COLOR"],
    disabled = isDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "colorModerate",
    name = L["STAGGER_MODERATE_COLOR"],
    disabled = isDisabled,
}
rows[#rows + 1] = {
    type = "color",
    path = "colorHeavy",
    name = L["STAGGER_HEAVY_COLOR"],
    disabled = isDisabled,
}

StaggerBarOptions.key = "staggerBar"
StaggerBarOptions.name = L["STAGGER_BAR"]
StaggerBarOptions.disabled = function()
    return not ns.ClassUtil.IsBrewmasterMonk()
end
StaggerBarOptions.pages = {
    {
        key = "main",
        rows = rows,
    },
}
