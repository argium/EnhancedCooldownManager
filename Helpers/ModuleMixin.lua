-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ModuleMixin = {}
ECM.ModuleMixin = ModuleMixin

local ModuleMixinProto = {}

--- Returns this module's config section (live from AceDB profile).
---@return table|nil
function ModuleMixinProto:GetModuleConfig()
    return ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile[self._configKey]
end

ModuleMixin.Proto = ModuleMixinProto
setmetatable(ModuleMixin, { __index = ModuleMixinProto })
