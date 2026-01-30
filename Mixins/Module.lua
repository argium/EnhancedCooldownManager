-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local Util = ns.Util
local Module = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.Module = Module

local DEFAULT_REFRESH_FREQUENCY = 0.066

---@class ECMModule
---@field _name string
---@field _config table|nil
---@field _layoutEvents string[]
---@field _refreshEvents RefreshEvent[]
---@field _lastUpdate number|nil
---@field _frame Frame|nil
---@field GetFrame() fun(self: ECMModule): Frame
---@field RegisterEvent fun(self: ECMModule, event: string, handler: string|fun(...))
---@field UnregisterEvent fun(self: ECMModule, event: string)
---@field OnEnable fun(self: ECMModule)
---@field OnDisable fun(self: ECMModule)
---@field _UnregisterEvents fun(self: ECMModule)
---@field UpdateLayout fun(self: ECMModule)
---@field Refresh fun(self: ECMModule)

--- Gets the name of the module.
--- @return string Name of the module
function Module:GetName()
    return self._name or "?"
end

function Module:GetConfig()
    assert(self._config, "config not set for module " .. self:GetName())
    return self._config
end

--- Refreshes the module if enough time has passed since the last update.
--- @return boolean True if refreshed, false if skipped due to throttling
function Module:ThrottledRefresh()
    local profile = ECM.db and ECM.db.profile
    local freq = (profile and profile.updateFrequency) or DEFAULT_REFRESH_FREQUENCY
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end

    self:Refresh()
    self._lastUpdate = GetTime()
    return true
end

function Module:OnEnable()
    self._lastUpdate = GetTime()

    Util.Log(self:GetName(), "Enabled", {
        layoutEvents=self._layoutEvents,
        refreshEvents=self._refreshEvents
    })

    for _, eventConfig in ipairs(self._refreshEvents) do
        self:RegisterEvent(eventConfig.event, eventConfig.handler)
    end

    for _, eventName in ipairs(self._layoutEvents) do
        self:RegisterEvent(eventName, "UpdateLayout")
    end
end

function Module:_UnregisterEvents()
    for _, eventName in ipairs(self._layoutEvents or {}) do
        self:UnregisterEvent(eventName)
    end

    for _, eventConfig in ipairs(self._refreshEvents or {}) do
        self:UnregisterEvent(eventConfig.event)
    end

    Util.Log(self:GetName(), "Events unregistered")
end

function Module:UpdateLayout()
end

function Module:Refresh()
end

function Module:OnConfigChanged()
end

function Module:SetConfig(config)
    assert(config, "config required")
    self._config = config
    self:OnConfigChanged()
end

---@class RefreshEvent
---@field event string Event name
---@field handler string Handler method name

--- Adds the EventListener mixin to the target module.
--- @param target table Module to add the mixin to
--- @param name string Name of the module
--- @param profile table Configuration profile
--- @param layoutEvents string[]|nil List of layout events
--- @param refreshEvents RefreshEvent[]|nil List of refresh events
function Module.AddMixin(target, name, profile, layoutEvents, refreshEvents)
    assert(target, "target required")
    assert(name, "name required")
    assert(profile, "profile required")

    -- Only copy methods that the target doesn't already have.
    -- This preserves module-specific overrides of UpdateLayout, Refresh, etc.
    for k, v in pairs(Module) do
        if type(v) == "function" and target[k] == nil then
            target[k] = v
        end
    end

    target._name = name
    target._layoutEvents = layoutEvents or {}
    target._refreshEvents = refreshEvents or {}
    target._config = profile
end
