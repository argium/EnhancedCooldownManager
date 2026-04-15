-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local COLOR_WHITE_HEX = C.COLOR_WHITE_HEX or "FFFFFF"

local function createResourceColorName(className, label)
    local color = (C.CLASS_COLORS and C.CLASS_COLORS[className]) or COLOR_WHITE_HEX
    local icon = className and ("|A:classicon-" .. string.lower(className) .. ":14:14|a ") or ""
    return icon .. "|cff" .. color .. label .. "|r"
end

local RESOURCE_COLOR_DEFS = {
    {
        key = C.RESOURCEBAR_TYPE_VENGEANCE_SOULS,
        name = createResourceColorName("DEMONHUNTER", L["RESOURCE_SOUL_FRAGMENTS_DH"]),
    },
    {
        key = C.RESOURCEBAR_TYPE_DEVOURER_NORMAL,
        name = createResourceColorName("DEMONHUNTER", L["RESOURCE_SOUL_FRAGMENTS_DEVOURER"]),
    },
    {
        key = C.RESOURCEBAR_TYPE_DEVOURER_META,
        name = createResourceColorName("DEMONHUNTER", L["RESOURCE_VOID_FRAGMENTS_DEVOURER"]),
    },
    {
        key = C.RESOURCEBAR_TYPE_ICICLES,
        name = createResourceColorName("MAGE", L["RESOURCE_ICICLES"]),
    },
    -- {
    --     -- Secret 2026/03
    --     key = Enum.PowerType.ArcaneCharges,
    --     name = createResourceColorName("MAGE", L["RESOURCE_ARCANE_CHARGES"]),
    -- },
    {
        key = Enum.PowerType.Chi,
        name = createResourceColorName("MONK", L["RESOURCE_CHI"]),
    },
    {
        key = Enum.PowerType.ComboPoints,
        name = createResourceColorName("ROGUE", L["RESOURCE_COMBO_POINTS"]),
    },
    {
        key = Enum.PowerType.Essence,
        name = createResourceColorName("EVOKER", L["RESOURCE_ESSENCE"]),
    },
    {
        key = Enum.PowerType.HolyPower,
        name = createResourceColorName("PALADIN", L["RESOURCE_HOLY_POWER"]),
    },
    {
        key = C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON,
        name = createResourceColorName("SHAMAN", L["RESOURCE_MAELSTROM_WEAPON"]),
    },
    {
        key = Enum.PowerType.SoulShards,
        name = createResourceColorName("WARLOCK", L["RESOURCE_SOUL_SHARDS"]),
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
ResourceBarOptions.disabled = ns.IsDeathKnight
ResourceBarOptions.rows = rows
