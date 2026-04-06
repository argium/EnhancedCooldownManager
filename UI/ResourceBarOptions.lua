-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local COLOR_WHITE_HEX = C.COLOR_WHITE_HEX or "FFFFFF"
local RESOURCE_ICON_SIZE = 14
local RESOURCE_ICON_SLOTS = 2
local EMPTY_RESOURCE_ICON = "|TInterface\\Buttons\\WHITE8X8:14:14:0:0:8:8:0:0:0:0|t"

local function createResourceClassIcon(className)
    return "|A:classicon-" .. string.lower(className) .. ":" .. RESOURCE_ICON_SIZE .. ":" .. RESOURCE_ICON_SIZE .. "|a"
end

local function createResourceColorName(colorClassName, label, iconClasses)
    local color = (C.CLASS_COLORS and C.CLASS_COLORS[colorClassName]) or COLOR_WHITE_HEX
    local prefix = ""
    local padding = RESOURCE_ICON_SLOTS - #iconClasses

    for _ = 1, padding do
        prefix = prefix .. EMPTY_RESOURCE_ICON
    end

    for _, className in ipairs(iconClasses) do
        prefix = prefix .. createResourceClassIcon(className)
    end

    return prefix .. " |cff" .. color .. label .. "|r"
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
    -- {
    --     -- Secret 2026/03
    --     key = Enum.PowerType.ArcaneCharges,
    --     name = createResourceColorName("MAGE", L["RESOURCE_ARCANE_CHARGES"]),
    -- },
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
local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("resourceBar")

function ResourceBarOptions.RegisterSettings(SB)
    local args = ns.OptionUtil.CreateBarArgs(isDisabled)
    args.enabled = {
        type = "toggle",
        path = "enabled",
        name = L["ENABLE_RESOURCE_BAR"],
        order = 0,
        onSet = ns.OptionUtil.CreateModuleEnabledHandler("ResourceBar"),
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

    args.colorsHeader = { type = "header", name = L["COLORS"], disabled = isDisabled, order = 29 }

    args.colors = {
        type = "colorList",
        path = "colors",
        label = L["RESOURCE_TYPES"],
        defs = RESOURCE_COLOR_DEFS,
        disabled = isDisabled,
        order = 30,
    }
    args.maxColorsEnabled = {
        type = "toggleList",
        path = "maxColorsEnabled",
        label = L["USE_ALTERNATE_COLOR_WHEN_CAPPED"],
        defs = maxColorDefs,
        disabled = isDisabled,
        order = 31,
    }
    args.maxColors = {
        type = "colorList",
        path = "maxColors",
        label = L["ALTERNATE_COLORS"],
        defs = maxColorDefs,
        disabled = isDisabled,
        order = 32,
    }

    SB.RegisterFromTable({
        name = L["RESOURCE_BAR"],
        path = "resourceBar",
        disabled = ns.IsDeathKnight,
        args = args,
    })
end

    ns.SettingsBuilder.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
