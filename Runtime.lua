-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
assert(ns.Constants, "Constants.lua must be loaded before Runtime.lua")
assert(ns.BarMixin, "BarMixin.lua must be loaded before Runtime.lua")
assert(ns.EditMode, "BarMixin.lua must initialize EditMode before Runtime.lua")
assert(ns.Addon, "ECM.lua must be loaded before Runtime.lua")

local C = ns.Constants
local L = ns.L
local EditMode = ns.EditMode
local LibEditMode = EditMode.Lib
local Runtime = {}
ns.Runtime = Runtime

--------------------------------------------------------------------------------
-- Layout — global visibility, fade, Blizzard frame enforcement, event dispatch
--------------------------------------------------------------------------------

local LAYOUT_EVENTS = {
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    UNIT_ENTERED_VEHICLE = { delay = 0 },
    UNIT_EXITED_VEHICLE = { delay = 0 },
    VEHICLE_UPDATE = { delay = 0 },
    PLAYER_UPDATE_RESTING = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    PLAYER_ENTERING_WORLD = { delay = C.LAYOUT_ENTERING_WORLD_DELAY },
    PLAYER_TARGET_CHANGED = { delay = 0 },
    PLAYER_REGEN_ENABLED = { delay = C.LAYOUT_COMBAT_END_DELAY, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = C.LAYOUT_ZONE_CHANGE_DELAY },
    ZONE_CHANGED = { delay = C.LAYOUT_ZONE_CHANGE_DELAY },
    ZONE_CHANGED_INDOORS = { delay = C.LAYOUT_ZONE_CHANGE_DELAY },
    UPDATE_SHAPESHIFT_FORM = { delay = 0 },
}

local _modules = {}
local _globallyHidden = false
local _desiredAlpha = 1
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _layoutPendingDelay = nil
local _layoutPendingTimer = nil
local _layoutEventsEnabled = false
local _layoutWatchdogTicker = nil
local _cooldownViewerSettingsHooked = false
local _layoutPreviewActive = false
local _hookedBlizzardFrames = {}
local _watchdogSetupComplete = false

local _chainSet = {}
for _, name in ipairs(C.CHAIN_ORDER) do
    _chainSet[name] = true
end

local _detachedAnchor = nil
local _detachedAnchorMetrics = nil

--- Enforces the current desired visibility and alpha on all Blizzard frames.
--- Single enforcement point called from state changes, OnShow hooks, and the
--- watchdog ticker.
local function enforceBlizzardFrameState()
    local alpha = _desiredAlpha
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            if _globallyHidden then
                if frame:IsShown() then frame:Hide() end
            else
                if not frame:IsShown() then frame:Show() end
                ns.FrameUtil.LazySetAlpha(frame, alpha)
            end
        end
    end
end

--- Hooks a Blizzard frame's OnShow to immediately re-enforce desired state.
--- Provides sub-frame correction when the game externally re-shows a frame.
--- @param frame Frame
--- @param name string
local function hookBlizzardFrame(frame, name)
    if _hookedBlizzardFrames[name] then
        return
    end

    frame:HookScript("OnShow", function(self)
        if _globallyHidden then
            self:Hide()
        else
            ns.FrameUtil.LazySetAlpha(self, _desiredAlpha)
        end
    end)

    _hookedBlizzardFrames[name] = true
end

--- Attempts to hook OnShow on all known Blizzard cooldown viewer frames.
--- Frames may be created lazily; called periodically to catch latecomers.
local function hookBlizzardFrames()
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            hookBlizzardFrame(frame, name)
        end
    end
end

--- Checks whether all one-time watchdog setup targets have been handled.
local function tryCompleteWatchdogSetup()
    if not _cooldownViewerSettingsHooked then return end
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        if not _hookedBlizzardFrames[name] then return end
    end
    _watchdogSetupComplete = true
end

--- Sets the globally hidden state for all frames (FrameProto + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
local function setGloballyHidden(hidden)
    if _globallyHidden == hidden then return end
    _globallyHidden = hidden
    for _, module in pairs(_modules) do
        module:SetHidden(hidden)
    end
end

--- Applies alpha to all managed frames.
--- @param alpha number
local function setAlpha(alpha)
    if _desiredAlpha == alpha then return end
    _desiredAlpha = alpha
    for _, module in pairs(_modules) do
        if module.InnerFrame then
            ns.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
        end
    end
end

--- Checks whether the player is in instance-like content for fade exceptions.
--- Delves are treated as instances for this purpose.
---@return boolean
local function isInInstanceContext()
    return IsInInstance() or IsDelveInProgress()
end

--- Checks all fade and hide conditions and updates global state.
local function updateFadeAndHiddenStates()
    local globalConfig = ns.GetGlobalConfig()
    if not globalConfig then
        return
    end

    -- Force-show while edit mode or the Layout options preview is active so the
    -- user can see and position modules without hide/fade interference.
    if LibEditMode:IsInEditMode() or _layoutPreviewActive then
        setGloballyHidden(false)
        setAlpha(1)
        enforceBlizzardFrameState()
        return
    end

    local hidden = not C_CVar.GetCVarBool("cooldownViewerEnabled")
        or (globalConfig.hideWhenMounted and (IsMounted() or UnitInVehicle("player") or UnitOnTaxi("player")))
        or (not _inCombat and globalConfig.hideOutOfCombatInRestAreas and IsResting())

    setGloballyHidden(hidden)

    -- Determine alpha (only matters when visible)
    local alpha = 1
    if not hidden then
        local fadeConfig = globalConfig.outOfCombatFade
        if not _inCombat and fadeConfig and fadeConfig.enabled then
            local hasLiveTarget = UnitExists("target") and not UnitIsDead("target")
            local skipFade = (fadeConfig.exceptInInstance and isInInstanceContext())
                or (hasLiveTarget and fadeConfig.exceptIfTargetCanBeAttacked and UnitCanAttack("player", "target"))
                or (hasLiveTarget and fadeConfig.exceptIfTargetCanBeHelped and UnitCanAssist("player", "target"))

            if not skipFade then
                alpha = math.max(0, math.min(1, (fadeConfig.opacity or 100) / 100))
            end
        end
    end

    setAlpha(alpha)
    enforceBlizzardFrameState()
end

local FU = ns.FrameUtil
local splitAnchorName = FU.SplitAnchorName
local buildAnchorName = FU.BuildAnchorName
local convertOffsetToAnchor = FU.ConvertOffsetToAnchor

local function invalidateDetachedAnchorMetrics()
    _detachedAnchorMetrics = nil
end

-- Detached stacks are more stable if their saved position is based on the edge
-- they grow from, rather than the centre of the full stack.
--
-- That means:
-- - grow down stacks are saved from their top edge;
-- - grow up stacks are saved from their bottom edge.
--
-- With that rule, the "anchored" edge stays fixed even if the total stack
-- height changes after reloads or after modules appear/disappear.
--- Rewrites a detached position so it is saved from the stack's stable grow
--- edge rather than from the middle of the detached stack.
---@param point string|nil
---@param x number|nil
---@param y number|nil
---@param width number|nil
---@param height number|nil
---@param growsUp boolean
---@return string, number, number
local function normalizeDetachedPositionToGrowEdge(point, x, y, width, height, growsUp)
    local sourcePoint = point or C.EDIT_MODE_DEFAULT_POINT
    local _, horizontal = splitAnchorName(sourcePoint)
    local targetVertical = growsUp and "BOTTOM" or "TOP"
    local targetPoint = buildAnchorName(targetVertical, horizontal)
    local offsetX, offsetY = convertOffsetToAnchor(sourcePoint, targetPoint, x or 0, y or 0, width, height, UIParent)
    return targetPoint, offsetX, offsetY
end

--- Creates and registers the detached anchor frame with Edit Mode.
local function ensureDetachedAnchor()
    if _detachedAnchor then
        return _detachedAnchor
    end

    local frame = CreateFrame("Frame", "ECMDetachedAnchor", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(C.DEFAULT_BAR_WIDTH, 1)
    ns.FrameUtil.LazySetAnchors(frame, {
        { C.EDIT_MODE_DEFAULT_POINT, UIParent, C.EDIT_MODE_DEFAULT_POINT, 0, 0 },
    })
    frame:Hide()
    _detachedAnchor = frame
    Runtime.DetachedAnchor = frame

    EditMode.RegisterFrame(frame, {
        name = "ECM: Detached Anchor",
        onPositionChanged = function(layoutName, point, x, y)
            local gc = ns.GetGlobalConfig()
            ns.DebugAssert(gc, "Detached anchor drag requires global config")
            local growsUp = (gc.detachedGrowDirection or C.GROW_DIRECTION_DOWN) == C.GROW_DIRECTION_UP
            -- Edit Mode reports the drop position using the detached box's
            -- current anchor. We immediately rewrite that position to the
            -- detached stack's stable grow edge so later height changes do not
            -- make the stack appear to move.
            local normalizedPoint, normalizedX, normalizedY =
                normalizeDetachedPositionToGrowEdge(point, x, y, frame:GetWidth(), frame:GetHeight(), growsUp)
            EditMode.SavePosition(gc, "detachedAnchorPositions", layoutName, normalizedPoint, normalizedX, normalizedY)
            Runtime.UpdateLayoutImmediately("DetachedAnchorDrag")
        end,
        settings = {
            {
                kind = LibEditMode.SettingType.Slider,
                name = L["WIDTH"],
                get = function()
                    local gc = ns.GetGlobalConfig()
                    return gc and gc.detachedBarWidth or C.DEFAULT_BAR_WIDTH
                end,
                set = function(_, value)
                    local gc = ns.GetGlobalConfig()
                    ns.DebugAssert(gc, "Detached anchor width requires global config")
                    gc.detachedBarWidth = value
                    invalidateDetachedAnchorMetrics()
                    Runtime.UpdateLayoutImmediately("DetachedAnchorWidth")
                end,
                default = C.DEFAULT_BAR_WIDTH,
                minValue = 100,
                maxValue = 600,
                valueStep = 1,
                allowInput = true,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = L["SPACING"],
                get = function()
                    local gc = ns.GetGlobalConfig()
                    return gc and gc.detachedModuleSpacing or 0
                end,
                set = function(_, value)
                    local gc = ns.GetGlobalConfig()
                    ns.DebugAssert(gc, "Detached anchor spacing requires global config")
                    gc.detachedModuleSpacing = value
                    invalidateDetachedAnchorMetrics()
                    Runtime.UpdateLayoutImmediately("DetachedAnchorSpacing")
                end,
                default = 0,
                minValue = 0,
                maxValue = 20,
                valueStep = 1,
                allowInput = true,
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = L["GROW_DIRECTION"],
                get = function()
                    local gc = ns.GetGlobalConfig()
                    return gc and gc.detachedGrowDirection or C.GROW_DIRECTION_DOWN
                end,
                set = function(_, value)
                    local gc = ns.GetGlobalConfig()
                    ns.DebugAssert(gc, "Detached anchor grow direction requires global config")
                    gc.detachedGrowDirection = value
                    Runtime.UpdateLayoutImmediately("DetachedAnchorGrowDirection")
                end,
                values = {
                    { text = L["DOWN"], value = C.GROW_DIRECTION_DOWN },
                    { text = L["UP"], value = C.GROW_DIRECTION_UP },
                },
            },
        },
    })

    ns.Log(nil, "Detached anchor created and registered with edit mode")
    return frame
end

---@return { count: number, totalHeight: number }
local function getDetachedAnchorMetrics()
    local metrics = _detachedAnchorMetrics
    if metrics then
        return metrics
    end

    local totalHeight = 0
    local count = 0

    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local barModule = ns.Addon and ns.Addon:GetECMModule(moduleName, true)
        if barModule and barModule:IsEnabled() and barModule:ShouldShow() then
            local mc = barModule:GetModuleConfig()
            local frame = barModule.InnerFrame
            if mc and mc.anchorMode == C.ANCHORMODE_DETACHED and frame then
                count = count + 1
                local h = frame:GetHeight()
                if h and h > 0 then
                    totalHeight = totalHeight + h
                end
            end
        end
    end

    local gc = ns.GetGlobalConfig()
    local spacing = gc and gc.detachedModuleSpacing or 0
    if count > 1 then
        totalHeight = totalHeight + (spacing * (count - 1))
    end

    metrics = {
        count = count,
        totalHeight = totalHeight,
    }
    _detachedAnchorMetrics = metrics
    return metrics
end

---@param anchor Frame
---@param layoutName string|nil
---@param positions table<string, ECM_EditModePosition>|nil
---@param growsUp boolean
local function applyDetachedAnchorPosition(anchor, layoutName, positions, growsUp)
    if not layoutName then
        return
    end

    local pos = EditMode.GetPosition(positions, layoutName)
    local point, x, y =
        normalizeDetachedPositionToGrowEdge(pos.point, pos.x, pos.y, anchor:GetWidth(), anchor:GetHeight(), growsUp)
    ns.FrameUtil.LazySetAnchors(anchor, {
        { point, UIParent, point, x, y },
    })
end

--- Ensures the detached anchor matches the current detached layout state before
--- detached modules calculate their own anchors.
---@return Frame|nil
local function updateDetachedAnchorLayout()
    local metrics = getDetachedAnchorMetrics()
    if metrics.count == 0 then
        if _detachedAnchor and _detachedAnchor:IsShown() then
            _detachedAnchor:Hide()
        end
        return nil
    end

    local anchor = ensureDetachedAnchor()
    local gc = ns.GetGlobalConfig()
    local barWidth = gc and gc.detachedBarWidth or C.DEFAULT_BAR_WIDTH
    local growsUp = (gc and gc.detachedGrowDirection or C.GROW_DIRECTION_DOWN) == C.GROW_DIRECTION_UP

    ns.FrameUtil.LazySetWidth(anchor, barWidth)
    ns.FrameUtil.LazySetHeight(anchor, math.max(metrics.totalHeight, 1))

    local layoutName = EditMode.GetActiveLayoutName()
    if layoutName then
        applyDetachedAnchorPosition(anchor, layoutName, gc and gc.detachedAnchorPositions, growsUp)
    end

    if not anchor:IsShown() then
        anchor:Show()
    end

    return anchor
end

local function updateAllLayouts(reason)
    invalidateDetachedAnchorMetrics()
    updateDetachedAnchorLayout()

    -- Chain frames update in deterministic order so downstream bars can
    -- resolve anchors against already-laid-out predecessors.
    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local module = _modules[moduleName]
        if module and module:IsReady() then
            module:UpdateLayout(reason)
        end
    end

    for frameName, module in pairs(_modules) do
        if not _chainSet[frameName] and module:IsReady() then
            module:UpdateLayout(reason)
        end
    end
end

--- Hooks CooldownViewerSettings hide to force alpha/layout reapplication.
local function hookCooldownViewerSettings()
    if _cooldownViewerSettingsHooked then
        return
    end

    local settingsFrame = _G.CooldownViewerSettings
    if not settingsFrame then
        return
    end

    settingsFrame:HookScript("OnHide", function()
        updateFadeAndHiddenStates()
        updateAllLayouts("OnHide:CooldownViewerSettings")
    end)

    _cooldownViewerSettingsHooked = true
    ns.Log(nil, "Hooked CooldownViewerSettings OnHide")
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Sets or clears the layout preview override.
--- When active, hide-when-mounted, hide-in-rest, and out-of-combat fade are bypassed.
---@param active boolean
function Runtime.SetLayoutPreview(active)
    active = active == true
    if _layoutPreviewActive == active then
        return
    end
    _layoutPreviewActive = active
    ns.Log(nil, "Layout preview " .. (active and "ON" or "OFF"))
    updateFadeAndHiddenStates()
    Runtime.ScheduleLayoutUpdate(0, active and "LayoutPreviewOn" or "LayoutPreviewOff")
end

--- Shared layout execution: hooks deferred frames, updates visibility, runs layout.
local function executeLayout(reason)
    _layoutPending = false
    _layoutPendingDelay = nil
    _layoutPendingTimer = nil
    hookCooldownViewerSettings()
    updateFadeAndHiddenStates()
    updateAllLayouts(reason)
end

--- Runs a layout update synchronously (no timer batching).
--- Use for Edit Mode drag where 1-frame latency is noticeable.
--- @param reason string|nil The lifecycle reason.
function Runtime.UpdateLayoutImmediately(reason)
    invalidateDetachedAnchorMetrics()
    executeLayout(reason)
end

local _requestPending = false
local _requestReason = nil
local _requestSecondPass = false

--- Requests a deferred layout pass for all registered modules.
--- Coalesces multiple requests within the same frame into one pass.
--- @param reason string Debug trace string identifying the caller.
--- @param opts table|nil Optional parameters: { secondPass = boolean }
function Runtime.RequestLayout(reason, opts)
    if opts and opts.secondPass then
        _requestSecondPass = true
    end
    if _requestPending then
        return
    end
    _requestReason = reason
    _requestPending = true
    C_Timer.After(0, function()
        local why = _requestReason
        local needSecondPass = _requestSecondPass
        _requestPending = false
        _requestReason = nil
        _requestSecondPass = false
        executeLayout(why)
        if needSecondPass then
            C_Timer.After(C.LIFECYCLE_SECOND_PASS_DELAY, function()
                if _requestPending or _layoutPending then
                    return
                end
                executeLayout("SecondPass")
            end)
        end
    end)
end

--- Requests a refresh (values only, no geometry) for a single module.
--- @param module table The module to refresh.
--- @param reason string Debug trace string.
function Runtime.RequestRefresh(module, reason)
    if module and module.ThrottledRefresh then
        module:ThrottledRefresh(reason)
    end
end

--- Schedules a layout update after a delay (debounced).
--- A later call with a shorter delay supersedes an earlier pending timer.
--- @param delay number Delay in seconds
--- @param reason string|nil The lifecycle reason (defaults to OPTION_CHANGED)
function Runtime.ScheduleLayoutUpdate(delay, reason)
    local waitTime = delay or 0

    -- Skip if already pending with an equal or shorter delay
    if _layoutPending and _layoutPendingDelay ~= nil and _layoutPendingDelay <= waitTime then
        return
    end

    -- Cancel the existing timer if we're superseding it
    if _layoutPendingTimer and _layoutPendingTimer.Cancel then
        _layoutPendingTimer:Cancel()
    end

    invalidateDetachedAnchorMetrics()
    _layoutPending = true
    _layoutPendingDelay = waitTime
    _layoutPendingTimer = C_Timer.NewTimer(waitTime, function()
        executeLayout(reason)
    end)
end

--- Registers a module frame to receive layout update events.
--- @param frame FrameProto The frame to register
function Runtime.RegisterFrame(frame)
    ns.BarMixin.AssertValid(frame)
    assert(_modules[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")

    invalidateDetachedAnchorMetrics()
    _modules[frame.Name] = frame
    frame:SetHidden(_globallyHidden)
    ns.FrameUtil.LazySetAlpha(frame.InnerFrame, _desiredAlpha)
    ns.Log(nil, "Frame registered: " .. frame.Name)
end

--- Unregisters a module frame from layout update events.
--- @param frame FrameProto The frame to unregister
function Runtime.UnregisterFrame(frame)
    ns.BarMixin.AssertValid(frame)
    assert(_modules[frame.Name] ~= nil, "UnregisterFrame: frame with name '" .. frame.Name .. "' is not registered")

    local name = frame.Name
    invalidateDetachedAnchorMetrics()
    _modules[name] = nil
    frame:SetHidden(true)
    ns.Log(nil, "Frame unregistered: " .. name)
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

--- Handles a layout-triggering event, updating combat state and scheduling layout.
---@param addon table The AceAddon instance (self from the event handler)
---@param event string
---@param arg1 any
local function handleLayoutEvent(_addon, event, arg1)
    if not _watchdogSetupComplete then
        hookCooldownViewerSettings()
        tryCompleteWatchdogSetup()
    end

    if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and Runtime.OnCombatEnd then
        Runtime.OnCombatEnd()
    end

    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownViewerEnabled" then
            updateFadeAndHiddenStates()
            Runtime.ScheduleLayoutUpdate(0, "CVAR_UPDATE:cooldownViewerEnabled")
        end
        return
    end

    local config = LAYOUT_EVENTS[event]
    if not config then
        return
    end

    if config.combatChange then
        _inCombat = (event == "PLAYER_REGEN_DISABLED")
    end

    if config.delay > 0 then
        C_Timer.After(config.delay, function()
            executeLayout(event)
        end)
        return
    end

    updateFadeAndHiddenStates()
    updateAllLayouts(event)
end

local function enableLayoutEvents(addon)
    if _layoutEventsEnabled then
        return
    end

    _layoutEventsEnabled = true

    if _layoutWatchdogTicker then
        _layoutWatchdogTicker:Cancel()
    end

    for eventName in pairs(LAYOUT_EVENTS) do
        addon:RegisterEvent(eventName, function(_, _event, ...)
            handleLayoutEvent(addon, eventName, ...)
        end)
    end
    addon:RegisterEvent("CVAR_UPDATE", function(_, _event, ...)
        handleLayoutEvent(addon, "CVAR_UPDATE", ...)
    end)

    -- Watchdog — catches cases where the game externally re-shows or resets alpha
    -- on Blizzard cooldown viewer frames between layout events.
    _layoutWatchdogTicker = C_Timer.NewTicker(C.WATCHDOG_INTERVAL, function()
        if not _watchdogSetupComplete then
            hookBlizzardFrames()
            hookCooldownViewerSettings()
            tryCompleteWatchdogSetup()
        end
        enforceBlizzardFrameState()

        for _, module in pairs(_modules) do
            if module.InnerFrame and not module.IsHidden then
                ns.FrameUtil.LazySetAlpha(module.InnerFrame, _desiredAlpha)
            end
        end
    end)
end

local function disableLayoutEvents(addon)
    if not _layoutEventsEnabled then
        return
    end

    _layoutEventsEnabled = false

    for eventName in pairs(LAYOUT_EVENTS) do
        addon:UnregisterEvent(eventName)
    end
    addon:UnregisterEvent("CVAR_UPDATE")

    if _layoutWatchdogTicker then
        _layoutWatchdogTicker:Cancel()
    end
    _layoutWatchdogTicker = nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- Enables the runtime: enables/disables modules per config and starts layout events.
---@param addon table The AceAddon instance
function Runtime.Enable(addon)
    local profile = addon.db and addon.db.profile

    for _, moduleName in ipairs(C.MODULE_ORDER) do
        local configKey = C.MODULE_CONFIG_KEYS[moduleName]
        local moduleConfig = profile and profile[configKey]
        local shouldEnable = (not moduleConfig) or (moduleConfig.enabled ~= false)
        if shouldEnable then
            addon:EnableModule(moduleName)
        else
            addon:DisableModule(moduleName)
        end
    end

    enableLayoutEvents(addon)
end

--- Disables the runtime: stops layout events.
---@param addon table The AceAddon instance
function Runtime.Disable(addon)
    disableLayoutEvents(addon)
end
