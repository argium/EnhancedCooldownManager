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
--- Injects OnEnable, OnDisable, SetExternallyHidden, GetFrameIfShown methods onto the module.
--- Optionally injects a default UpdateLayout if configKey is provided.
--- Modules can override any injected method by saving the base method before defining their own.
---@param module table AceModule to configure
---@param config table Configuration table with:
---   - name: string - Module name for logging
---   - layoutEvents: string[] - Events that trigger UpdateLayout
---   - refreshEvents: table[] - Events that trigger refresh: { { event = "NAME", handler = "method" }, ... }
---   - onDisable: function|nil - Optional cleanup callback called before standard disable
---   - configKey: string|nil - Profile config key (e.g., "powerBar"). If provided, injects default UpdateLayout
---   - shouldShow: function|nil - Visibility check function, used with configKey
---   - defaultHeight: number|nil - Default bar height, used with configKey
---   - anchorMode: string|nil - "viewer" (always viewer) or "chain" (GetPreferredAnchor). Default "chain"
---   - onLayoutSetup: function|nil - Hook called after layout: onLayoutSetup(module, bar, cfg, profile)
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

    -- Inject default UpdateLayout if configKey is provided
    if config.configKey then
        function module:UpdateLayout()
            local BarFrame = ns.Mixins.BarFrame
            local result = Lifecycle.CheckLayoutPreconditions(self, config.configKey, config.shouldShow, config.name)
            if not result then
                return
            end

            self:Enable()

            local profile, cfg = result.profile, result.cfg
            local bar = self:GetFrame()

            -- Calculate anchor based on anchorMode
            local anchor, isFirstBar
            if config.anchorMode == "viewer" then
                anchor = BarFrame.GetViewerAnchor()
                isFirstBar = true
            else
                anchor, isFirstBar = BarFrame.GetPreferredAnchor(ns.Addon, config.name)
            end

            -- Calculate offsetY
            local viewer = BarFrame.GetViewerAnchor()
            local offsetY = (isFirstBar and anchor == viewer) and -BarFrame.GetTopGapOffset(cfg, profile) or 0

            -- Apply layout and appearance
            local defaultHeight = config.defaultHeight or BarFrame.DEFAULT_SEGMENT_BAR_HEIGHT
            bar:ApplyLayoutAndAppearance(anchor, offsetY, cfg, profile, defaultHeight)

            -- Call module-specific setup hook if provided
            -- Hook can return false to abort (e.g., if no valid data)
            if config.onLayoutSetup then
                local shouldContinue = config.onLayoutSetup(self, bar, cfg, profile)
                if shouldContinue == false then
                    return
                end
            end

            bar:Show()
            self:Refresh()
        end
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
    local addon = ns.Addon
    local profile = addon and addon.db and addon.db.profile
    if not profile then
        Util.Log(moduleName, "UpdateLayout skipped - no profile")
        return nil
    end

    if module._externallyHidden then
        Util.Log(moduleName, "UpdateLayout skipped - externally hidden")
        if module._frame then
            module._frame:Hide()
        end
        return nil
    end

    local cfg = profile[configKey]
    if not (cfg and cfg.enabled) then
        Util.Log(moduleName, "UpdateLayout - " .. configKey .. " disabled in config")
        module:Disable()
        return nil
    end

    if shouldShowFn and not shouldShowFn() then
        Util.Log(moduleName, "UpdateLayout - shouldShow returned false")
        if module._frame then
            module._frame:Hide()
        end
        return nil
    end

    return { profile = profile, cfg = cfg }
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
