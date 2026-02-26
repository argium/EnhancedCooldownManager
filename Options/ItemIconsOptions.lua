-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ItemIconsOptions = {}

function ItemIconsOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Item Icons",
        path = "itemIcons",
        moduleEnabled = {
            name = "Enable item icons",
            desc = "Display icons for equipped on-use trinkets and select consumables to the right of utility cooldowns.",
        },
        args = {
            equipmentHeader = {
                type = "header",
                name = "Equipment",
                order = 10,
            },
            showTrinket1 = {
                type = "toggle",
                path = "showTrinket1",
                name = "Show first trinket",
                desc = "Display icons for usable equipment. Trinkets without an on-use effect are never shown.",
                order = 11,
            },
            showTrinket2 = {
                type = "toggle",
                path = "showTrinket2",
                name = "Show second trinket",
                order = 12,
            },
            consumablesHeader = {
                type = "header",
                name = "Consumables",
                order = 20,
            },
            showHealthPotion = {
                type = "toggle",
                path = "showHealthPotion",
                name = "Show health potions",
                order = 21,
            },
            showCombatPotion = {
                type = "toggle",
                path = "showCombatPotion",
                name = "Show combat potions",
                order = 22,
            },
            showHealthstone = {
                type = "toggle",
                path = "showHealthstone",
                name = "Show healthstone",
                order = 23,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ItemIcons", ItemIconsOptions)
