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
    args.colors = {
        type = "colorList",
        defs = RESOURCE_COLOR_DEFS,
        label = "Colors",
        path = "colors",
        disabled = isDisabled,
        order = 30,
    }

    SB.RegisterFromTable({
        name = "Resource Bar",
        path = "resourceBar",
        disabled = ECM.ClassUtil.IsDeathKnight,
        args = args,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
