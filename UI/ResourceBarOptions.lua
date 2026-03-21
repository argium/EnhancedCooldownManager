-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local L = ECM.L

local RESOURCE_COLOR_DEFS = {
    { key = C.RESOURCEBAR_TYPE_VENGEANCE_SOULS, name = L["RESOURCE_SOUL_FRAGMENTS_DH"] },
    { key = C.RESOURCEBAR_TYPE_DEVOURER_NORMAL, name = L["RESOURCE_SOUL_FRAGMENTS_DEVOURER"] },
    { key = C.RESOURCEBAR_TYPE_DEVOURER_META, name = L["RESOURCE_VOID_FRAGMENTS_DEVOURER"] },
    { key = C.RESOURCEBAR_TYPE_ICICLES, name = L["RESOURCE_ICICLES"] },
    { key = Enum.PowerType.ArcaneCharges, name = L["RESOURCE_ARCANE_CHARGES"] },
    { key = Enum.PowerType.Chi, name = L["RESOURCE_CHI"] },
    { key = Enum.PowerType.ComboPoints, name = L["RESOURCE_COMBO_POINTS"] },
    { key = Enum.PowerType.Essence, name = L["RESOURCE_ESSENCE"] },
    { key = Enum.PowerType.HolyPower, name = L["RESOURCE_HOLY_POWER"] },
    { key = C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON, name = L["RESOURCE_MAELSTROM_WEAPON"] },
    { key = Enum.PowerType.SoulShards, name = L["RESOURCE_SOUL_SHARDS"] },
}

local ResourceBarOptions = {}

local function isDisabled()
    return ECM.ClassUtil.IsDeathKnight()
        or not ECM.OptionUtil.GetNestedValue(ns.Addon.db.profile, "resourceBar.enabled")
end

function ResourceBarOptions.RegisterSettings(SB)
    local args = ECM.OptionUtil.CreateBarArgs(isDisabled)
    args.enabled = {
        type = "toggle",
        path = "enabled",
        name = L["ENABLE_RESOURCE_BAR"],
        order = 0,
        onSet = ECM.OptionUtil.CreateModuleEnabledHandler("ResourceBar"),
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

    args.colors = {
        type = "colorList",
        path = "colors",
        label = L["COLORS"],
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
        disabled = ECM.ClassUtil.IsDeathKnight,
        args = args,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
