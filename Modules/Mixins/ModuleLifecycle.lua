local _, ns = ...

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
--- Injects Enable, Disable, OnEnable, OnDisable methods onto the module.
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

        C_Timer.After(0.1, function()
            self:UpdateLayout()
        end)
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
-- Layout Preconditions
--------------------------------------------------------------------------------

--- Checks UpdateLayout preconditions and returns config if successful.
--- Handles externally hidden state, addon disabled, module disabled, and shouldShow check.
---@param module table Module with _externallyHidden, _frame, :Disable()
---@param configKey string Config key in profile (e.g., "powerBar")
---@param shouldShowFn function|nil Optional visibility check function
---@param moduleName string Module name for logging
---@return table|nil result { profile, cfg } or nil if should skip
function Lifecycle.CheckLayoutPreconditions(module, configKey, shouldShowFn, moduleName)
    return Util.CheckUpdateLayoutPreconditions(module, configKey, shouldShowFn, moduleName)
end

--------------------------------------------------------------------------------
-- External Visibility
--------------------------------------------------------------------------------

--- Marks a module as externally hidden (e.g., when mounted).
---@param module table Module with _externallyHidden, _frame
---@param hidden boolean Whether hidden externally
---@param moduleName string Module name for logging
function Lifecycle.SetExternallyHidden(module, hidden, moduleName)
    Util.SetExternallyHidden(module, hidden, moduleName)
end

--- Returns the module's frame if it exists and is shown.
---@param module table Module with _externallyHidden, _frame
---@return Frame|nil
function Lifecycle.GetFrameIfShown(module)
    return Util.GetFrameIfShown(module)
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
