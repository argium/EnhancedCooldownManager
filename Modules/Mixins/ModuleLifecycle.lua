local _, ns = ...

local Util = ns.Util

--- ModuleLifecycle mixin: Enable/Disable, throttling, and event helpers.
--- Provides common module lifecycle patterns for bar modules.
local Lifecycle = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.Lifecycle = Lifecycle

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

--- Enables a module: sets _enabled flag, timestamp, registers events.
--- Modules should call this with their specific event configuration.
---@param module table Module to enable (AceModule with RegisterEvent)
---@param moduleName string Module name for logging
---@param events table Event configuration: { { event = "NAME", handler = "method" }, ... }
function Lifecycle.Enable(module, moduleName, events)
    if module._enabled then
        return
    end

    module._enabled = true
    module._lastUpdate = GetTime()

    if events then
        for _, cfg in ipairs(events) do
            module:RegisterEvent(cfg.event, cfg.handler)
        end
    end

    Util.Log(moduleName, "Enabled")
end

--- Disables a module: hides frame, clears _enabled flag, unregisters events.
---@param module table Module to disable (AceModule with UnregisterEvent)
---@param moduleName string Module name for logging
---@param events table Event names to unregister: { "EVENT1", "EVENT2", ... }
function Lifecycle.Disable(module, moduleName, events)
    if module._frame then
        module._frame:Hide()
    end

    if not module._enabled then
        return
    end

    module._enabled = false

    if events then
        for _, eventName in ipairs(events) do
            module:UnregisterEvent(eventName)
        end
    end

    Util.Log(moduleName, "Disabled")
end

--- Standard OnEnable handler: registers layout events and schedules initial UpdateLayout.
---@param module table Module (AceModule with RegisterEvent)
---@param moduleName string Module name for logging
---@param layoutEvents table Layout event names: { "PLAYER_ENTERING_WORLD", ... }
function Lifecycle.OnEnable(module, moduleName, layoutEvents)
    Util.Log(moduleName, "OnEnable - module starting")

    for _, eventName in ipairs(layoutEvents) do
        module:RegisterEvent(eventName, "UpdateLayout")
    end

    C_Timer.After(0.1, function()
        module:UpdateLayout()
    end)
end

--- Standard OnDisable handler: unregisters layout events and calls Disable.
---@param module table Module (AceModule with UnregisterEvent)
---@param moduleName string Module name for logging
---@param layoutEvents table Layout event names to unregister
---@param refreshEvents table Refresh event names to unregister
function Lifecycle.OnDisable(module, moduleName, layoutEvents, refreshEvents)
    Util.Log(moduleName, "OnDisable - module stopping")

    for _, eventName in ipairs(layoutEvents) do
        module:UnregisterEvent(eventName)
    end

    Lifecycle.Disable(module, moduleName, refreshEvents)
end

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
