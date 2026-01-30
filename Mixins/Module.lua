-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local Util = ns.Util

---@class ModuleMixin : ECMModule
local Module = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.Module = Module

--- Default update frequency in seconds (~15 FPS)
local DEFAULT_REFRESH_FREQUENCY = 0.066

---@class RefreshEvent
---@field event string WoW event name to listen for
---@field handler string Name of the handler method on the module

---@class ECMModule : AceModule
---@field _name string Internal name of the module
---@field _config table|nil Reference to the module's configuration profile section
---@field _layoutEvents string[] List of WoW events that trigger layout updates
---@field _refreshEvents RefreshEvent[] List of events and handlers for refresh triggers
---@field _lastUpdate number|nil Timestamp of the last throttled refresh
---@field _frame Frame|nil The module's main display frame
---@field RegisterEvent fun(self: ECMModule, event: string, handler: string|fun(self: ECMModule, event: string, ...: any)) Registers an event handler (from AceEvent)
---@field UnregisterEvent fun(self: ECMModule, event: string) Unregisters an event handler (from AceEvent)

--- Gets the name of the module.
---@return string name Name of the module, or "?" if not set
function Module:GetName()
    return self._name or "?"
end

--- Gets the configuration table for this module.
--- Asserts if the config has not been set via `AddMixin` or `SetConfig`.
---@return table config The module's configuration table
function Module:GetConfig()
    assert(self._config, "config not set for module " .. self:GetName())
    return self._config
end

--- Refreshes the module if enough time has passed since the last update.
--- Uses the global `updateFrequency` setting to throttle refresh calls.
---@return boolean refreshed True if Refresh() was called, false if skipped due to throttling
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

--- Called when the module is enabled.
--- Registers all configured layout and refresh events.
function Module:OnEnable()
    assert(self._layoutEvents, "layoutEvents not set for module " .. self:GetName())
    assert(self._refreshEvents, "refreshEvents not set for module " .. self:GetName())

    self._lastUpdate = GetTime()

    for _, eventConfig in ipairs(self._refreshEvents) do
        self:RegisterEvent(eventConfig.event, eventConfig.handler)
    end

    for _, eventName in ipairs(self._layoutEvents) do
        self:RegisterEvent(eventName, "UpdateLayout")
    end

    Util.Log(self:GetName(), "Enabled", {
        layoutEvents=self._layoutEvents,
        refreshEvents=self._refreshEvents
    })
end

--- Called when the module is disabled.
--- Unregisters all layout and refresh events.
function Module:OnDisable()
    assert(self._layoutEvents, "layoutEvents not set for module " .. self:GetName())
    assert(self._refreshEvents, "refreshEvents not set for module " .. self:GetName())

    for _, eventName in ipairs(self._layoutEvents) do
        self:UnregisterEvent(eventName)
    end

    for _, eventConfig in ipairs(self._refreshEvents) do
        self:UnregisterEvent(eventConfig.event)
    end

    Util.Log(self:GetName(), "Disabled", {
        layoutEvents=self._layoutEvents,
        refreshEvents=self._refreshEvents
    })
end

--- Updates the visual layout of the module.
--- Override this method in concrete modules to handle layout changes.
function Module:UpdateLayout()
end

--- Refreshes the module's display state.
--- Override this method in concrete modules to update visual state.
function Module:Refresh()
end

--- Called when the module's configuration has changed.
--- Override this method to respond to configuration updates.
function Module:OnConfigChanged()
end

--- Sets the configuration table for this module.
---@param config table The configuration table to use
function Module:SetConfig(config)
    assert(config, "config required")
    self._config = config
    self:OnConfigChanged()
end

--- Applies the Module mixin to a target table.
--- Copies all mixin methods that the target doesn't already have,
--- preserving module-specific overrides of UpdateLayout, Refresh, etc.
---@param target table Module table to add the mixin to
---@param name string Name of the module
---@param profile table Configuration profile table
---@param layoutEvents? string[] List of WoW events that trigger layout updates
---@param refreshEvents? RefreshEvent[] List of refresh event configurations
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
