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
    for _, cfg in ipairs(config.refreshEvents) do
        table.insert(refreshEventNames, cfg.event)
    end
    module._lifecycleConfig.refreshEventNames = refreshEventNames

    -- Inject OnEnable method (AceAddon lifecycle hook)
    function module:OnEnable()
        Util.Log(self._lifecycleConfig.name, "OnEnable - module starting")

        if self._enabled then
            return
        end

        self._enabled = true
        self._lastUpdate = GetTime()

        for _, cfg in ipairs(self._lifecycleConfig.refreshEvents) do
            self:RegisterEvent(cfg.event, cfg.handler)
        end

        for _, eventName in ipairs(self._lifecycleConfig.layoutEvents) do
            self:RegisterEvent(eventName, "UpdateLayout")
        end

        -- Register ourselves with the viewer hook to respond to global events
        EnhancedCooldownManager.ViewerHook:RegisterBar(self)

        C_Timer.After(0.1, function()
            self:UpdateLayout()
        end)
    end

    -- Inject SetExternallyHidden method (can be overridden by modules)
    function module:SetExternallyHidden(hidden)
        local wasHidden = self._externallyHidden
        self._externallyHidden = hidden and true or false
        if wasHidden ~= self._externallyHidden then
            Util.Log(config.name, "SetExternallyHidden", { hidden = self._externallyHidden })
        end
        if self._externallyHidden and self._frame then
            self._frame:Hide()
        end
    end

    -- Inject GetFrameIfShown method
    function module:GetFrameIfShown()
        local f = self._frame
        return (not self._externallyHidden and f and f:IsShown()) and f or nil
    end

    -- Inject OnDisable method (AceAddon lifecycle hook)
    function module:OnDisable()
        Util.Log(self._lifecycleConfig.name, "OnDisable - module stopping")

        for _, eventName in ipairs(self._lifecycleConfig.layoutEvents) do
            self:UnregisterEvent(eventName)
        end

        -- Call custom cleanup if provided
        if self._lifecycleConfig.onDisable then
            self._lifecycleConfig.onDisable(self)
        end

        if self._frame then
            self._frame:Hide()
        end

        if not self._enabled then
            return
        end

        self._enabled = false

        for _, eventName in ipairs(self._lifecycleConfig.refreshEventNames) do
            self:UnregisterEvent(eventName)
        end

        Util.Log(self._lifecycleConfig.name, "Disabled")
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
    local now = GetTime()
    local last = module._lastUpdate or 0
    local freq = (profile and profile.updateFrequency) or 0.066

    return (now - last) >= freq
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
