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
    local _, classToken = UnitClass("player")
    return classToken == C.CLASS.DEATHKNIGHT
end

local function isDisabled()
    return isDeathKnight() or not ECM.OptionUtil.GetNestedValue(ns.Addon.db.profile, "resourceBar.enabled")
end

function ResourceBarOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Resource Bar",
        path = "resourceBar",
        disabled = isDeathKnight,
        args = {
            enabled         = { type = "toggle", path = "enabled", name = "Enable resource bar", order = 0, onSet = function(value) ECM.OptionUtil.SetModuleEnabled("ResourceBar", value) end },
            layoutHeader    = { type = "header", name = "Layout", disabled = isDisabled, order = 1 },
            positioning     = { type = "positioning", disabled = isDisabled, order = 2 },
            appearHeader    = { type = "header", name = "Appearance", disabled = isDisabled, order = 3 },
            showText        = { type = "toggle", path = "showText", name = "Show text", desc = "Display the current value on the bar.", disabled = isDisabled, order = 4 },
            heightOverride  = { type = "heightOverride", disabled = isDisabled, order = 5 },
            border          = { type = "border", path = "border", disabled = isDisabled, order = 6 },
            fontOverride    = { type = "fontOverride", disabled = isDisabled, order = 7 },
            colors          = { type = "colorList", defs = RESOURCE_COLOR_DEFS, label = "Colors", path = "colors", disabled = isDisabled, order = 8 },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ResourceBar", ResourceBarOptions)
