-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants

local ItemIconsOptions = {}

function ItemIconsOptions.RegisterSettings(SB)
    SB.CreateSubcategory("Item Icons")

    SB.Header("Item Icons")

    SB.PathControl({
        type = "checkbox",
        path = "itemIcons.enabled",
        name = "Enable item icons",
        tooltip = "Display icons for equipped on-use trinkets and select consumables to the right of utility cooldowns.",
        onSet = function(value)
            if value then
                if not mod.ItemIcons:IsEnabled() then
                    mod:EnableModule(C.ITEMICONS)
                end
            else
                if mod.ItemIcons:IsEnabled() then
                    mod:DisableModule(C.ITEMICONS)
                end
            end
        end,
    })

    -- Equipment
    SB.Header("Equipment")

    SB.PathControl({
        type = "checkbox",
        path = "itemIcons.showTrinket1",
        name = "Show first trinket",
        tooltip = "Display icons for usable equipment. Trinkets without an on-use effect are never shown.",
    })

    SB.PathControl({
        type = "checkbox",
        path = "itemIcons.showTrinket2",
        name = "Show second trinket",
    })

    -- Consumables
    SB.Header("Consumables")

    SB.PathControl({
        type = "checkbox",
        path = "itemIcons.showHealthPotion",
        name = "Show health potions",
    })

    SB.PathControl({
        type = "checkbox",
        path = "itemIcons.showCombatPotion",
        name = "Show combat potions",
    })

    SB.PathControl({
        type = "checkbox",
        path = "itemIcons.showHealthstone",
        name = "Show healthstone",
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "ItemIcons", ItemIconsOptions)
