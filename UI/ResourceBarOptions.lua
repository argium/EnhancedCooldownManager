-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local COLOR_WHITE_HEX = C.COLOR_WHITE_HEX or "FFFFFF"
local RESOURCE_ICON_SIZE = 14
local RESOURCE_ICON_SLOTS = 2
-- Transparent texture slot for right-aligning rows with fewer class icons.
local EMPTY_RESOURCE_ICON =
    "|TInterface\\Common\\spacer:"
    .. RESOURCE_ICON_SIZE
    .. ":"
    .. RESOURCE_ICON_SIZE
    .. "|t"

local function createResourceColorName(colorClassName, label, iconClasses)
    local color = (C.CLASS_COLORS and C.CLASS_COLORS[colorClassName]) or COLOR_WHITE_HEX
    local icons = {}
    local iconCount = math.min(#iconClasses, RESOURCE_ICON_SLOTS)
    local padding = math.max(0, RESOURCE_ICON_SLOTS - iconCount)
    local startIndex = math.max(1, #iconClasses - RESOURCE_ICON_SLOTS + 1)

    for _ = 1, padding do
        icons[#icons + 1] = EMPTY_RESOURCE_ICON
    end

    for i = startIndex, #iconClasses do
        local iconClass = string.lower(iconClasses[i])
        icons[#icons + 1] = "|A:classicon-" .. iconClass .. ":" .. RESOURCE_ICON_SIZE .. ":" .. RESOURCE_ICON_SIZE .. "|a"
    end

    return table.concat(icons, " ") .. " |cff" .. color .. label .. "|r"
end

local RESOURCE_COLOR_DEFS = {
    {
        key = C.RESOURCEBAR_TYPE_VENGEANCE_SOULS,
        name = createResourceColorName("DEMONHUNTER", L["RESOURCE_SOUL_FRAGMENTS_DH"], { "DEMONHUNTER" }),
    },
    {
        key = C.RESOURCEBAR_TYPE_DEVOURER_NORMAL,
        name = createResourceColorName("DEMONHUNTER", L["RESOURCE_SOUL_FRAGMENTS_DEVOURER"], { "DEMONHUNTER" }),
    },
    {
        key = C.RESOURCEBAR_TYPE_DEVOURER_META,
        name = createResourceColorName("DEMONHUNTER", L["RESOURCE_VOID_FRAGMENTS_DEVOURER"], { "DEMONHUNTER" }),
    },
    {
        key = C.RESOURCEBAR_TYPE_ICICLES,
        name = createResourceColorName("MAGE", L["RESOURCE_ICICLES"], { "MAGE" }),
    },
    {
        key = Enum.PowerType.Chi,
        name = createResourceColorName("MONK", L["RESOURCE_CHI"], { "MONK" }),
    },
    {
        key = Enum.PowerType.ComboPoints,
        name = createResourceColorName("ROGUE", L["RESOURCE_COMBO_POINTS"], { "DRUID", "ROGUE" }),
    },
    {
        key = Enum.PowerType.Essence,
        name = createResourceColorName("EVOKER", L["RESOURCE_ESSENCE"], { "EVOKER" }),
    },
    {
        key = Enum.PowerType.HolyPower,
        name = createResourceColorName("PALADIN", L["RESOURCE_HOLY_POWER"], { "PALADIN" }),
    },
    {
        key = C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON,
        name = createResourceColorName("SHAMAN", L["RESOURCE_MAELSTROM_WEAPON"], { "SHAMAN" }),
    },
    {
        key = Enum.PowerType.SoulShards,
        name = createResourceColorName("WARLOCK", L["RESOURCE_SOUL_SHARDS"], { "WARLOCK" }),
    },
}

local ResourceBarOptions = {}
ns.ResourceBarOptions = ResourceBarOptions
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("resourceBar")

local rows = {
    {
        type = "checkbox",
        path = "enabled",
        name = L["ENABLE_RESOURCE_BAR"],
        onSet = ns.OptionUtil.CreateModuleEnabledHandler("ResourceBar"),
    },
}
local maxColorDefs = {}
for _, def in ipairs(RESOURCE_COLOR_DEFS) do
    if C.RESOURCEBAR_MAX_COLOR_TYPES[def.key] then
        maxColorDefs[#maxColorDefs + 1] = {
            key = def.key,
            name = def.name,
            tooltip = L["ALTERNATE_COLOR_TOOLTIP"],
        }
    end
end

for _, row in ipairs(ns.OptionUtil.CreateBarRows(isDisabled)) do
    rows[#rows + 1] = row
end

rows[#rows + 1] = { type = "header", name = L["COLORS"], disabled = isDisabled }
rows[#rows + 1] = {
    type = "colorList",
    path = "colors",
    label = L["RESOURCE_TYPES"],
    defs = RESOURCE_COLOR_DEFS,
    disabled = isDisabled,
}
rows[#rows + 1] = {
    type = "checkboxList",
    path = "maxColorsEnabled",
    label = L["USE_ALTERNATE_COLOR_WHEN_CAPPED"],
    defs = maxColorDefs,
    disabled = isDisabled,
}
rows[#rows + 1] = {
    type = "colorList",
    path = "maxColors",
    label = L["ALTERNATE_COLORS"],
    defs = maxColorDefs,
    disabled = isDisabled,
}

ResourceBarOptions.key = "resourceBar"
ResourceBarOptions.name = L["RESOURCE_BAR"]
ResourceBarOptions.disabled = ns.ClassUtil.IsDeathKnight
ResourceBarOptions.pages = {
    {
        key = "main",
        rows = rows,
    },
}
