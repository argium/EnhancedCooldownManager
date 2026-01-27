-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

--- ModuleLifecycle mixin: Enable/Disable, throttling, and event helpers.
--- Provides common module lifecycle patterns for bar modules.
local Lifecycle = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.Lifecycle = Lifecycle

--------------------------------------------------------------------------------
-- Module Setup (configures and injects lifecycle methods)
--------------------------------------------------------------------------------

--- Configures a module with lifecycle event handling.
--- Injects OnEnable, OnDisable, SetExternallyHidden, GetFrameIfShown methods onto the module.
--- Modules must define their own UpdateLayout method.
---@param module table AceModule to configure
---@param config table Configuration table with:
---   - name: string - Module name for logging
---   - layoutEvents: string[] - Events that trigger UpdateLayout
---   - refreshEvents: table[] - Events that trigger refresh: { { event = "NAME", handler = "method" }, ... }
---   - onDisable: function|nil - Optional cleanup callback called before standard disable
function Lifecycle.Setup(module, config)
    assert(config.name, "Lifecycle.Setup requires config.name")
    assert(config.layoutEvents, "Lifecycle.Setup requires config.layoutEvents")
    assert(config.refreshEvents, "Lifecycle.Setup requires config.refreshEvents")

    -- Store config for later use
    module._lifecycleConfig = config

    -- Build refresh event names list for unregistration
    local refreshEventNames = {}
    for i = 1, #config.refreshEvents do
        refreshEventNames[i] = config.refreshEvents[i].event
    end
    module._lifecycleConfig.refreshEventNames = refreshEventNames

    -- Inject OnEnable method (AceAddon lifecycle hook)
    function module:OnEnable()
        local cfg = self._lifecycleConfig
        Util.Log(cfg.name, "OnEnable - module starting")

        self._lastUpdate = GetTime()

        for _, eventConfig in ipairs(cfg.refreshEvents) do
            self:RegisterEvent(eventConfig.event, eventConfig.handler)
        end

        for _, eventName in ipairs(cfg.layoutEvents) do
            self:RegisterEvent(eventName, "UpdateLayout")
        end

        -- Register ourselves with the viewer hook to respond to global events
        EnhancedCooldownManager.ViewerHook:RegisterBar(self)

        EnhancedCooldownManager.ViewerHook:ScheduleLayoutUpdate(0.1)
    end

    -- Inject SetExternallyHidden method (can be overridden by modules)
    function module:SetExternallyHidden(hidden)
        local isHidden = not not hidden
        if self._externallyHidden ~= isHidden then
            self._externallyHidden = isHidden
            Util.Log(config.name, "SetExternallyHidden", { hidden = self._externallyHidden })
        end
        if self._externallyHidden and self._frame then
            self._frame:Hide()
        end
    end

    -- Inject GetFrameIfShown method
    function module:GetFrameIfShown()
        local f = self._frame
        if self._externallyHidden or not f or not f:IsShown() then
            return nil
        end
        return f
    end

    -- Inject OnDisable method (AceAddon lifecycle hook)
    function module:OnDisable()
        local cfg = self._lifecycleConfig
        Util.Log(cfg.name, "OnDisable - module stopping")

        for _, eventName in ipairs(cfg.layoutEvents) do
            self:UnregisterEvent(eventName)
        end

        -- Call custom cleanup if provided
        if cfg.onDisable then
            cfg.onDisable(self)
        end

        local frame = self._frame
        if frame then
            frame:Hide()
        end

        for _, eventName in ipairs(cfg.refreshEventNames) do
            self:UnregisterEvent(eventName)
        end

        Util.Log(cfg.name, "Disabled")
    end
end

--------------------------------------------------------------------------------
-- Throttled Refresh
--------------------------------------------------------------------------------

--- Checks if enough time has passed for a throttled refresh.
--- Uses profile.updateFrequency as the throttle interval.
---@param module table Module with _lastUpdate field
---@param profile table Profile with updateFrequency
---@return boolean shouldRefresh True if enough time has passed
function Lifecycle.ShouldRefresh(module, profile)
    local freq = (profile and profile.updateFrequency) or 0.066
    return (GetTime() - (module._lastUpdate or 0)) >= freq
end

--- Marks the module as having just refreshed.
---@param module table Module with _lastUpdate field
function Lifecycle.MarkRefreshed(module)
    module._lastUpdate = GetTime()
end

--- Performs a throttled refresh: checks timing and calls refreshFn if appropriate.
---@param module table Module with _lastUpdate, _externallyHidden
---@param profile table Profile with updateFrequency
---@param refreshFn function Function to call for refresh (receives module as arg)
---@return boolean didRefresh True if refresh was performed
function Lifecycle.ThrottledRefresh(module, profile, refreshFn)
    if module._externallyHidden then
        return false
    end

    if not Lifecycle.ShouldRefresh(module, profile) then
        return false
    end

    refreshFn(module)
    Lifecycle.MarkRefreshed(module)
    return true
end
