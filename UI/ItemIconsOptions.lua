-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local L = ECM.L

local ItemIconsOptions = {}
local isDisabled = ECM.OptionUtil.GetIsDisabledDelegate("itemIcons")

function ItemIconsOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = L["ITEM_ICONS"],
        path = "itemIcons",
        args = {
            enabled = {
                type = "toggle",
                path = "enabled",
                name = L["ENABLE_ITEM_ICONS"],
                desc = L["ENABLE_ITEM_ICONS_DESC"],
                order = 0,
                onSet = ECM.OptionUtil.CreateModuleEnabledHandler("ItemIcons"),
            },
            equipmentHeader = {
                type = "header",
                name = L["EQUIPMENT"],
                disabled = isDisabled,
                order = 10,
            },
            showTrinket1 = {
                type = "toggle",
                path = "showTrinket1",
                name = L["SHOW_FIRST_TRINKET"],
                desc = L["SHOW_FIRST_TRINKET_DESC"],
                disabled = isDisabled,
                order = 11,
            },
            showTrinket2 = {
                type = "toggle",
                path = "showTrinket2",
                name = L["SHOW_SECOND_TRINKET"],
                disabled = isDisabled,
                order = 12,
            },
            consumablesHeader = {
                type = "header",
                name = L["CONSUMABLES"],
                disabled = isDisabled,
                order = 20,
            },
            showHealthPotion = {
                type = "toggle",
                path = "showHealthPotion",
                name = L["SHOW_HEALTH_POTIONS"],
                disabled = isDisabled,
                order = 21,
            },
            showCombatPotion = {
                type = "toggle",
                path = "showCombatPotion",
                name = L["SHOW_COMBAT_POTIONS"],
                disabled = isDisabled,
                order = 22,
            },
            showHealthstone = {
                type = "toggle",
                path = "showHealthstone",
                name = L["SHOW_HEALTHSTONE"],
                disabled = isDisabled,
                order = 23,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ItemIcons", ItemIconsOptions)
