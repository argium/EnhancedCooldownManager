-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local ItemIconsOptions = {}
mod.ItemIconsOptions = ItemIconsOptions

--- Builds a standard Item Icons module toggle option.
---@param self ECM_ItemIconsModule
---@param key string
---@param label string
---@param order number
---@return table
local function BuildModuleToggleOption(self, key, label, order)
    return {
        type = "toggle",
        name = label,
        order = order,
        width = "full",
        disabled = function()
            return ECM.OptionUtil.IsOptionsDisabled(self)
        end,
        get = function()
            return ECM.OptionUtil.GetOptionValue(self, key, true)
        end,
        set = function(_, val)
            local moduleConfig = mod.ItemIcons:GetModuleConfig()
            if moduleConfig then
                moduleConfig[key] = val
            end
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end,
    }
end

--- Builds Item Icons basic settings options.
---@return table
function ItemIconsOptions.GetBasicOptionsArgs()
    return {
        description = {
            type = "description",
            name = "Display icons for equipped on-use trinkets and select consumables to the right of utility cooldowns.",
            order = 0,
            fontSize = "medium",
        },
        enabled = {
            type = "toggle",
            name = "Enable item icons",
            order = 1,
            width = "full",
            get = function()
                return ECM.OptionUtil.GetOptionValue(mod.ItemIcons, "enabled", true)
            end,
            set = function(_, val)
                local moduleConfig = mod.ItemIcons:GetModuleConfig()
                if moduleConfig then
                    moduleConfig.enabled = val
                end

                if val then
                    if not mod.ItemIcons:IsEnabled() then
                        mod:EnableModule(ECM.Constants.ITEMICONS)
                    end
                else
                    if mod.ItemIcons:IsEnabled() then
                        mod:DisableModule(ECM.Constants.ITEMICONS)
                    end
                end

                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end,
        },
    }
end

--- Builds Item Icons item toggles options.
---@return table
function ItemIconsOptions.GetEquipmentOptionsArgs()
    return {
        description = {
            type = "description",
            name = "Display icons for usable equipment. Trinkets without an on-use effect are never shown.",
            order = 0,
            fontSize = "medium",
        },
        showTrinket1 = BuildModuleToggleOption(mod.ItemIcons, "showTrinket1", "Show first trinket", 1),
        showTrinket2 = BuildModuleToggleOption(mod.ItemIcons, "showTrinket2", "Show second trinket", 2),
    }
end

--- Builds Item Icons consumable toggles options.
---@return table
function ItemIconsOptions.GetConsumableOptionsArgs()
    return {
        description = {
            type = "description",
            name = "Display icons for selected consumables. If there are multiple valid items in a category, the most powerful item is shown first, followed by the highest quality item.",
            order = 0,
            fontSize = "medium",
        },
        showHealthPotion = BuildModuleToggleOption(mod.ItemIcons, "showHealthPotion", "Show health potions", 1),
        showCombatPotion = BuildModuleToggleOption(mod.ItemIcons, "showCombatPotion", "Show combat potions", 2),
        showHealthstone = BuildModuleToggleOption(mod.ItemIcons, "showHealthstone", "Show healthstone", 3),
    }
end

--- Builds the Item Icons options group.
---@return table itemIconsOptions AceConfig group for Item Icons section.
function ItemIconsOptions.GetOptionsTable()
    return {
        type = "group",
        name = "Item Icons",
        order = 6,
        args = {
            basicSettings = {
                type = "group",
                name = "Basic Settings",
                inline = true,
                order = 1,
                args = ItemIconsOptions.GetBasicOptionsArgs(),
            },
            equipmentSettings = {
                type = "group",
                name = "Equipment",
                inline = true,
                order = 2,
                args = ItemIconsOptions.GetEquipmentOptionsArgs(),
            },
            consumableSettings = {
                type = "group",
                name = "Consumables",
                inline = true,
                order = 3,
                args = ItemIconsOptions.GetConsumableOptionsArgs(),
            },
        },
    }
end
