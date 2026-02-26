-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ItemIconsOptions = {}

local function isDisabled()
    return not ECM.OptionUtil.GetNestedValue(ns.Addon.db.profile, "itemIcons.enabled")
end

function ItemIconsOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Item Icons",
        path = "itemIcons",
        args = {
            enabled = {
                type = "toggle",
                path = "enabled",
                name = "Enable item icons",
                desc = "Display icons for equipped on-use trinkets and select consumables to the right of utility cooldowns.",
                order = 0,
                onSet = function(value) ECM.OptionUtil.SetModuleEnabled("ItemIcons", value) end,
            },
            equipmentHeader = {
                type = "header",
                name = "Equipment",
                disabled = isDisabled,
                order = 10,
            },
            showTrinket1 = {
                type = "toggle",
                path = "showTrinket1",
                name = "Show first trinket",
                desc = "Display icons for usable equipment. Trinkets without an on-use effect are never shown.",
                disabled = isDisabled,
                order = 11,
            },
            showTrinket2 = {
                type = "toggle",
                path = "showTrinket2",
                name = "Show second trinket",
                disabled = isDisabled,
                order = 12,
            },
            consumablesHeader = {
                type = "header",
                name = "Consumables",
                disabled = isDisabled,
                order = 20,
            },
            showHealthPotion = {
                type = "toggle",
                path = "showHealthPotion",
                name = "Show health potions",
                disabled = isDisabled,
                order = 21,
            },
            showCombatPotion = {
                type = "toggle",
                path = "showCombatPotion",
                name = "Show combat potions",
                disabled = isDisabled,
                order = 22,
            },
            showHealthstone = {
                type = "toggle",
                path = "showHealthstone",
                name = "Show healthstone",
                disabled = isDisabled,
                order = 23,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ItemIcons", ItemIconsOptions)
