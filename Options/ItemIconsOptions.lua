-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local C = ns.Constants
local ItemIcons = ECM.ItemIcons
local OptionHelpers = ECM.OptionHelpers


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
            return OptionHelpers.IsOptionsDisabled(self)
        end,
        get = function()
            return OptionHelpers.GetOptionValue(self, key, true)
        end,
        set = function(_, val)
            local moduleConfig = self:GetModuleConfig()
            if moduleConfig then
                moduleConfig[key] = val
            end
            ECM.ScheduleLayoutUpdate(0)
        end,
    }
end

--- Builds Item Icons basic settings options.
---@return table
function ItemIcons:GetBasicOptionsArgs()
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
                return OptionHelpers.GetOptionValue(self, "enabled", true)
            end,
            set = function(_, val)
                local moduleConfig = self:GetModuleConfig()
                if moduleConfig then
                    moduleConfig.enabled = val
                end

                if val then
                    if not self:IsEnabled() then
                        ECM:EnableModule(C.ITEMICONS)
                    end
                else
                    if self:IsEnabled() then
                        ECM:DisableModule(C.ITEMICONS)
                    end
                end

                ECM.ScheduleLayoutUpdate(0)
            end,
        },
    }
end

--- Builds Item Icons item toggles options.
---@return table
function ItemIcons:GetEquipmentOptionsArgs()
    return {
        description = {
            type = "description",
            name = "Display icons for usable equipment. Trinkets without an on-use effect are never shown.",
            order = 0,
            fontSize = "medium",
        },
        showTrinket1 = BuildModuleToggleOption(self, "showTrinket1", "Show first trinket", 1),
        showTrinket2 = BuildModuleToggleOption(self, "showTrinket2", "Show second trinket", 2),
    }
end

--- Builds Item Icons consumable toggles options.
---@return table
function ItemIcons:GetConsumableOptionsArgs()
    return {
        description = {
            type = "description",
            name = "Display icons for selected consumables. If there are multiple valid items in a category, the most powerful item is shown first, followed by the highest quality item.",
            order = 0,
            fontSize = "medium",
        },
        showHealthPotion = BuildModuleToggleOption(self, "showHealthPotion", "Show health potions", 1),
        showCombatPotion = BuildModuleToggleOption(self, "showCombatPotion", "Show combat potions", 2),
        showHealthstone = BuildModuleToggleOption(self, "showHealthstone", "Show healthstone", 3),
    }
end

--- Builds the Item Icons options group.
---@return table itemIconsOptions AceConfig group for Item Icons section.
function ItemIcons:GetOptionsTable()
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
                args = self:GetBasicOptionsArgs(),
            },
            equipmentSettings = {
                type = "group",
                name = "Equipment",
                inline = true,
                order = 2,
                args = self:GetEquipmentOptionsArgs(),
            },
            consumableSettings = {
                type = "group",
                name = "Consumables",
                inline = true,
                order = 3,
                args = self:GetConsumableOptionsArgs(),
            },
        },
    }
end
