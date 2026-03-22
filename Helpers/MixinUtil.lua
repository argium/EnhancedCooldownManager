-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

---@class ECM_MixinUtil Shared bootstrapping for the mixin hierarchy.

local MixinUtil = {}
ECM.MixinUtil = MixinUtil

--- Applies a mixin prototype to a target module via metatable chaining.
--- Preserves any existing metatable __index (e.g. AceAddon module tables).
--- Idempotent — second call on the same target is a no-op.
---@param target table The module to apply the mixin to.
---@param proto table The prototype table that provides fallback methods.
---@param name string Unique module name (e.g. "PowerBar").
---@param extraInit fun(target: table)|nil Optional one-time initializer.
function MixinUtil.Apply(target, proto, name, extraInit)
    assert(target, "target required")
    assert(name, "name required")
    if target._mixinApplied then
        return
    end

    local existingMt = getmetatable(target)
    local existingIndex = existingMt and existingMt.__index

    setmetatable(target, {
        __index = function(_, k)
            local v = proto[k]
            if v ~= nil then
                return v
            end
            if type(existingIndex) == "function" then
                return existingIndex(target, k)
            end
            if type(existingIndex) == "table" then
                return existingIndex[k]
            end
        end,
    })

    local C = ECM.Constants
    target.Name = name
    target._configKey = C.ConfigKeyForModule(name)
    if not target.GetGlobalConfig then
        target.GetGlobalConfig = ECM.GetGlobalConfig
    end
    target.IsHidden = false
    target._mixinApplied = true

    if extraInit then
        extraInit(target)
    end
end
