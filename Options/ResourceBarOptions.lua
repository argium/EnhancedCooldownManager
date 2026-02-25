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

local function isDeathKnight()
    return ECM.SettingsBuilder.IsPlayerClass(C.CLASS.DEATHKNIGHT)
end

function ResourceBarOptions.RegisterSettings(SB)
    SB.CreateSubcategory("Resource Bar")

    SB.Header("Resource Bar")

    SB.ModuleEnabledCheckbox("ResourceBar", {
        path = "resourceBar.enabled",
        name = "Enable resource bar",
        hidden = isDeathKnight,
    })

    SB.HeightOverrideSlider("resourceBar", { hidden = isDeathKnight })

    SB.Header("Display")

    SB.PathControl({
        type = "checkbox",
        path = "resourceBar.showText",
        name = "Show text",
        tooltip = "Display the current value on the bar.",
        hidden = isDeathKnight,
    })

    SB.Header("Border")
    SB.BorderGroup("resourceBar.border", { hidden = isDeathKnight })

    SB.Header("Font Override")
    SB.FontOverrideGroup("resourceBar", { hidden = isDeathKnight })

    SB.Header("Positioning")
    SB.PositioningGroup("resourceBar", { hidden = isDeathKnight })

    SB.Header("Colors")
    SB.ColorPickerList("resourceBar.colors", RESOURCE_COLOR_DEFS, { hidden = isDeathKnight })
end

ECM.SettingsBuilder.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
