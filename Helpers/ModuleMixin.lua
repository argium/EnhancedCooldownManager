-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ModuleMixin = {}
ECM.ModuleMixin = ModuleMixin

--- Returns the global config section (live from AceDB profile).
---@return table|nil
function ModuleMixin:GetGlobalConfig()
    return ns.Addon.db and ns.Addon.db.profile
        and ns.Addon.db.profile[ECM.Constants.CONFIG_SECTION_GLOBAL]
end

--- Returns this module's config section (live from AceDB profile).
---@return table|nil
function ModuleMixin:GetModuleConfig()
    return ns.Addon.db and ns.Addon.db.profile
        and ns.Addon.db.profile[self._configKey]
end

--- Applies common module methods (name, config) to the target.
--- Presumes that there is configuration section for the module that is keyed by the camel-case
--- version of the name.
--- @param target table table to apply the mixin to.
--- @param name string the module name. must be unique.
function ModuleMixin.AddMixin(target, name)
    assert(target, "target required")
    assert(name, "name required")

    -- Only copy methods that the target doesn't already have.
    for k, v in pairs(ModuleMixin) do
        if type(v) == "function" and target[k] == nil then
            target[k] = v
        end
    end

    target.Name = name
    target._configKey = name:sub(1,1):lower() .. name:sub(2) -- camelCase-ish
end
