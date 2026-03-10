-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local RESOURCE_COLOR_DEFS = {
    { key = C.RESOURCEBAR_TYPE_VENGEANCE_SOULS, name = "Soul Fragments (Demon Hunter)" },
    { key = C.RESOURCEBAR_TYPE_DEVOURER_NORMAL, name = "Soul Fragments (Devourer)" },
    { key = C.RESOURCEBAR_TYPE_DEVOURER_META, name = "Void Fragments (Devourer)" },
    { key = C.RESOURCEBAR_TYPE_ICICLES, name = "Icicles (Frost Mage)" },
    { key = Enum.PowerType.ArcaneCharges, name = "Arcane Charges" },
    { key = Enum.PowerType.Chi, name = "Chi" },
    { key = Enum.PowerType.ComboPoints, name = "Combo Points" },
    { key = Enum.PowerType.Essence, name = "Essence" },
    { key = Enum.PowerType.HolyPower, name = "Holy Power" },
    { key = C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON, name = "Maelstrom Weapon (Enhancement)" },
    { key = Enum.PowerType.SoulShards, name = "Soul Shards" },
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
        name = "Enable resource bar",
        order = 0,
        onSet = ECM.OptionUtil.CreateModuleEnabledHandler("ResourceBar"),
    }
    local maxColorDefs = {}
    for _, def in ipairs(RESOURCE_COLOR_DEFS) do
        if C.RESOURCEBAR_MAX_COLOR_TYPES[def.key] then
            maxColorDefs[#maxColorDefs + 1] = {
                key = def.key,
                name = def.name,
                tooltip = "Use an alternate color when this resource is at its maximum value.",
            }
        end
    end

    args.colors = {
        type = "colorList",
        path = "colors",
        label = "Colors",
        defs = RESOURCE_COLOR_DEFS,
        disabled = isDisabled,
        order = 30,
    }
    args.maxColorsEnabled = {
        type = "toggleList",
        path = "maxColorsEnabled",
        label = "Use alternate color when capped",
        defs = maxColorDefs,
        disabled = isDisabled,
        order = 31,
    }
    args.maxColors = {
        type = "colorList",
        path = "maxColors",
        label = "Alternate Colors",
        defs = maxColorDefs,
        disabled = isDisabled,
        order = 32,
    }

    SB.RegisterFromTable({
        name = "Resource Bar",
        path = "resourceBar",
        disabled = ECM.ClassUtil.IsDeathKnight,
        args = args,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
