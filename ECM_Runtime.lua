-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
ECM = ECM or {}
assert(ECM.Constants, "ECM_Constants.lua must be loaded before ECM_Runtime.lua")
assert(ECM.FrameMixin, "FrameMixin.lua must be loaded before ECM_Runtime.lua")
assert(ECM.EditMode, "ECM.EditMode must be initialized before ECM_Runtime.lua")
assert(ns.Addon, "ECM.lua must be loaded before ECM_Runtime.lua")

local C = ECM.Constants
local L = ECM.L
local EditMode = ECM.EditMode
local LibEQOLEditMode = EditMode.Lib
local Runtime = {}
ECM.Runtime = Runtime

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
local _detachedAnchorLayout = nil

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
                ECM.FrameUtil.LazySetAlpha(frame, alpha)
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
            ECM.FrameUtil.LazySetAlpha(self, _desiredAlpha)
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

--- Sets the globally hidden state for all frames (ModuleMixins + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
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
            ECM.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
        end
    end
end

--- Checks all fade and hide conditions and updates global state.
local function updateFadeAndHiddenStates()
    local globalConfig = ECM.GetGlobalConfig()
    if not globalConfig then
        return
    end

    -- Force-show while edit mode or the Layout options preview is active so the
    -- user can see and position modules without hide/fade interference.
    if LibEQOLEditMode:IsInEditMode() or _layoutPreviewActive then
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
            local skipFade = (fadeConfig.exceptInInstance and IsInInstance())
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

--- Gets the saved detached anchor position for a layout.
--- If no layout name is provided, this uses the current active Edit Mode layout.
---@param layoutName string|nil
---@return ECM_EditModePosition
local function getDetachedAnchorPosition(layoutName)
    local gc = ECM.GetGlobalConfig()
    return EditMode.GetPosition(gc and gc.detachedAnchorPositions, layoutName)
end

--- Saves the detached anchor position for a specific layout.
---@param layoutName string
---@param point string
---@param x number
---@param y number
local function saveDetachedAnchorPosition(layoutName, point, x, y)
    local gc = ECM.GetGlobalConfig()
    EditMode.SavePosition(gc, "detachedAnchorPositions", layoutName, point, x, y)
end

local FU = ECM.FrameUtil
local splitAnchorName = FU.SplitAnchorName
local buildAnchorName = FU.BuildAnchorName
local convertOffsetToAnchor = FU.ConvertOffsetToAnchor

---@param key string
---@param defaultValue any
---@return any
local function getDetachedConfigValue(key, defaultValue)
    local gc = ECM.GetGlobalConfig()
    local value = gc and gc[key]
    if value == nil then
        return defaultValue
    end
    return value
end

---@param key string
---@param value any
---@param updateReason string
local function setDetachedConfigValue(key, value, updateReason)
    local gc = ECM.GetGlobalConfig()
    if not gc then
        return
    end

    gc[key] = value
    Runtime.UpdateLayoutImmediately(updateReason)
end

--- Returns whether detached stacks are configured to grow upward.
---@return boolean
local function detachedAnchorGrowsUp()
    return getDetachedConfigValue("detachedGrowDirection", C.GROW_DIRECTION_DOWN) == C.GROW_DIRECTION_UP
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
---@return string, number, number
local function normalizeDetachedPositionToGrowEdge(point, x, y, width, height)
    local sourcePoint = point or C.EDIT_MODE_DEFAULT_POINT
    local _, horizontal = splitAnchorName(sourcePoint)
    local targetVertical = detachedAnchorGrowsUp() and "BOTTOM" or "TOP"
    local targetPoint = buildAnchorName(targetVertical, horizontal)
    local offsetX, offsetY = convertOffsetToAnchor(sourcePoint, targetPoint, x or 0, y or 0, width, height, UIParent)
    return targetPoint, offsetX, offsetY
end

--- Creates and registers the detached anchor frame with LibEQOL.
local function ensureDetachedAnchor()
    if _detachedAnchor then
        return _detachedAnchor
    end

    local frame = CreateFrame("Frame", "ECMDetachedAnchor", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(C.DEFAULT_BAR_WIDTH, 1)
    ECM.FrameUtil.LazySetAnchors(frame, {
        { C.EDIT_MODE_DEFAULT_POINT, UIParent, C.EDIT_MODE_DEFAULT_POINT, 0, 0 },
    })
    frame:Hide()
    _detachedAnchor = frame
    Runtime.DetachedAnchor = frame

    EditMode.RegisterFrame(frame, {
        name = "ECM: Detached Anchor",
        onPositionChanged = function(layoutName, point, x, y)
            -- Edit Mode reports the drop position using the detached box's
            -- current anchor. We immediately rewrite that position to the
            -- detached stack's stable grow edge so later height changes do not
            -- make the stack appear to move.
            local normalizedPoint, normalizedX, normalizedY =
                normalizeDetachedPositionToGrowEdge(point, x, y, frame:GetWidth(), frame:GetHeight())
            saveDetachedAnchorPosition(layoutName, normalizedPoint, normalizedX, normalizedY)
            Runtime.UpdateLayoutImmediately("DetachedAnchorDrag")
        end,
        allowDrag = true,
        settings = {
            {
                kind = LibEQOLEditMode.SettingType.Slider,
                name = L["WIDTH"],
                get = function()
                    return getDetachedConfigValue("detachedBarWidth", C.DEFAULT_BAR_WIDTH)
                end,
                set = function(_, value)
                    setDetachedConfigValue("detachedBarWidth", value, "DetachedAnchorWidth")
                end,
                default = C.DEFAULT_BAR_WIDTH,
                minValue = 100,
                maxValue = 600,
                valueStep = 1,
                allowInput = true,
            },
            {
                kind = LibEQOLEditMode.SettingType.Slider,
                name = L["SPACING"],
                get = function()
                    return getDetachedConfigValue("detachedModuleSpacing", 0)
                end,
                set = function(_, value)
                    setDetachedConfigValue("detachedModuleSpacing", value, "DetachedAnchorSpacing")
                end,
                default = 0,
                minValue = 0,
                maxValue = 20,
                valueStep = 1,
                allowInput = true,
            },
            {
                kind = LibEQOLEditMode.SettingType.Dropdown,
                name = L["GROW_DIRECTION"],
                get = function()
                    return getDetachedConfigValue("detachedGrowDirection", C.GROW_DIRECTION_DOWN)
                end,
                set = function(_, value)
                    setDetachedConfigValue("detachedGrowDirection", value, "DetachedAnchorGrowDirection")
                end,
                values = {
                    { label = L["DOWN"], value = C.GROW_DIRECTION_DOWN },
                    { label = L["UP"], value = C.GROW_DIRECTION_UP },
                },
            },
        },
    })

    ECM.Log(nil, "Detached anchor created and registered with edit mode")
    return frame
end

---@return number
---@return number
local function getDetachedAnchorMetrics()
    local totalHeight = 0
    local count = 0

    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local barModule = ns.Addon and ns.Addon:GetECMModule(moduleName, true)
        if barModule and barModule:IsEnabled() and barModule:ShouldShow() then
            local mc = barModule:GetModuleConfig()
            if mc and mc.anchorMode == C.ANCHORMODE_DETACHED and barModule.InnerFrame then
                local h = barModule.InnerFrame:GetHeight()
                if h and h > 0 then
                    totalHeight = totalHeight + h
                    count = count + 1
                end
            end
        end
    end

    return totalHeight, count
end

---@param anchor Frame
---@param layoutName string|nil
---@return boolean
local function applyDetachedAnchorPosition(anchor, layoutName)
    if not layoutName then
        return false
    end

    local pos = getDetachedAnchorPosition(layoutName)
    local point, x, y =
        normalizeDetachedPositionToGrowEdge(pos.point, pos.x, pos.y, anchor:GetWidth(), anchor:GetHeight())
    ECM.FrameUtil.LazySetAnchors(anchor, {
        { point, UIParent, point, x, y },
    })
    _detachedAnchorLayout = layoutName
    return true
end

--- Ensures the detached anchor exists and is already positioned for the active
--- layout before detached modules calculate their own anchors.
---@return Frame|nil
local function prepareDetachedAnchorForLayout()
    local _, count = getDetachedAnchorMetrics()
    if count == 0 then
        return nil
    end

    local anchor = ensureDetachedAnchor()
    local barWidth = getDetachedConfigValue("detachedBarWidth", C.DEFAULT_BAR_WIDTH)
    ECM.FrameUtil.LazySetWidth(anchor, barWidth)

    local layoutName = EditMode.GetActiveLayoutName()
    -- Detached modules ask for their root anchor during this same layout pass.
    -- If the detached anchor is still using the wrong layout position here,
    -- every detached child will calculate its own position from stale data.
    if layoutName and (not anchor:IsShown() or layoutName ~= _detachedAnchorLayout) then
        applyDetachedAnchorPosition(anchor, layoutName)
    end

    if not anchor:IsShown() then
        anchor:Show()
    end

    return anchor
end

--- Updates the detached anchor's size and visibility to match the current set
--- of shown detached modules.
local function updateDetachedAnchorSize()
    local totalHeight, count = getDetachedAnchorMetrics()
    if count == 0 then
        if _detachedAnchor and _detachedAnchor:IsShown() then
            _detachedAnchor:Hide()
        end
        _detachedAnchorLayout = nil
        return
    end

    local anchor = ensureDetachedAnchor()
    local barWidth = getDetachedConfigValue("detachedBarWidth", C.DEFAULT_BAR_WIDTH)
    local spacing = getDetachedConfigValue("detachedModuleSpacing", 0)

    if count > 1 then
        totalHeight = totalHeight + (spacing * (count - 1))
    end

    ECM.FrameUtil.LazySetWidth(anchor, barWidth)
    ECM.FrameUtil.LazySetHeight(anchor, math.max(totalHeight, 1))

    -- Apply the position again after width/height are final.
    --
    -- This matters for two cases:
    -- - older saved data may still have been recorded from the centre;
    -- - the current detached stack may have changed height because modules were
    --   shown, hidden, enabled, or disabled.
    --
    -- Re-running the conversion with the final size keeps the visible anchored
    -- edge consistent for the current layout.
    local layoutName = EditMode.GetActiveLayoutName()
    if layoutName then
        applyDetachedAnchorPosition(anchor, layoutName)
    end

    if not anchor:IsShown() then
        anchor:Show()
    end
end

local function updateAllLayouts(reason)
    prepareDetachedAnchorForLayout()

    -- Chain frames update in deterministic order so downstream bars can
    -- resolve anchors against already-laid-out predecessors.
    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local module = _modules[moduleName]
        if module then
            module:ThrottledUpdateLayout(reason)
        end
    end

    for frameName, module in pairs(_modules) do
        if not _chainSet[frameName] then
            module:ThrottledUpdateLayout(reason)
        end
    end

    updateDetachedAnchorSize()
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
    ECM.Log(nil, "Hooked CooldownViewerSettings OnHide")
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
    ECM.Log(nil, "Layout preview " .. (active and "ON" or "OFF"))
    updateFadeAndHiddenStates()
    Runtime.ScheduleLayoutUpdate(0, active and "LayoutPreviewOn" or "LayoutPreviewOff")
end

--- Shared layout execution: hooks deferred frames, updates visibility, runs layout.
local function executeLayout(reason)
    _layoutPending = false
    hookCooldownViewerSettings()
    updateFadeAndHiddenStates()
    updateAllLayouts(reason)
end

--- Runs a layout update synchronously (no timer batching).
--- Use for Edit Mode drag where 1-frame latency is noticeable.
--- @param reason string|nil The lifecycle reason.
function Runtime.UpdateLayoutImmediately(reason)
    executeLayout(reason)
end

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
--- @param reason string|nil The lifecycle reason (defaults to OPTION_CHANGED)
function Runtime.ScheduleLayoutUpdate(delay, reason)
    if _layoutPending then
        return
    end

    _layoutPending = true
    C_Timer.After(delay or 0, function()
        executeLayout(reason)
    end)
end

--- Registers a FrameMixin to receive layout update events.
--- @param frame FrameMixin The frame to register
function Runtime.RegisterFrame(frame)
    ECM.FrameMixin.AssertValid(frame)
    assert(_modules[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")

    _modules[frame.Name] = frame
    frame:SetHidden(_globallyHidden)
    ECM.FrameUtil.LazySetAlpha(frame.InnerFrame, _desiredAlpha)
    ECM.Log(nil, "Frame registered: " .. frame.Name)
end

--- Unregisters a FrameMixin from layout update events.
--- @param frame FrameMixin The frame to unregister
function Runtime.UnregisterFrame(frame)
    ECM.FrameMixin.AssertValid(frame)
    assert(_modules[frame.Name] ~= nil, "UnregisterFrame: frame with name '" .. frame.Name .. "' is not registered")

    local name = frame.Name
    _modules[name] = nil
    frame:SetHidden(true)
    ECM.Log(nil, "Frame unregistered: " .. name)
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
            updateFadeAndHiddenStates()
            updateAllLayouts(event)
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
        addon:RegisterEvent(eventName, function(_, ...)
            handleLayoutEvent(addon, eventName, ...)
        end)
    end
    addon:RegisterEvent("CVAR_UPDATE", function(_, ...)
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
                ECM.FrameUtil.LazySetAlpha(module.InnerFrame, _desiredAlpha)
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
