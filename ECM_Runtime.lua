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
                if frame:IsShown() then
                    frame:Hide()
                    ECM.Log(nil, "Enforced hide on " .. (frame:GetName() or "?"))
                end
            else
                if not frame:IsShown() then
                    frame:Show()
                    ECM.Log(nil, "Enforced show on " .. (frame:GetName() or "?"))
                end
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
    ECM.Log(nil, "Hooked Blizzard frame: " .. name)
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

--- Sets the globally hidden state for all frames (ModuleMixins + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
local function setGloballyHidden(hidden, reason)
    if _globallyHidden ~= hidden then
        ECM.Log(
            nil,
            "SetGloballyHidden " .. (hidden and "HIDDEN" or "VISIBLE") .. (reason and (" due to " .. reason) or "")
        )
    end

    _globallyHidden = hidden

    for _, module in pairs(_modules) do
        module:SetHidden(hidden)
    end
end

--- Applies alpha to all managed frames.
--- @param alpha number
local function setAlpha(alpha)
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

    -- Determine hidden state
    local hidden, reason = false, nil
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        hidden, reason = true, "cvar"
    elseif globalConfig.hideWhenMounted and (IsMounted() or UnitInVehicle("player") or UnitOnTaxi("player")) then
        hidden, reason = true, "mounted"
    elseif not _inCombat and globalConfig.hideOutOfCombatInRestAreas and IsResting() then
        hidden, reason = true, "rest"
    end

    setGloballyHidden(hidden, reason)

    -- Determine alpha (only matters when visible)
    local alpha = 1
    if not hidden then
        local fadeConfig = globalConfig.outOfCombatFade
        if not _inCombat and fadeConfig and fadeConfig.enabled then
            local shouldSkipFade = false

            if fadeConfig.exceptInInstance and IsInInstance() then
                shouldSkipFade = true
            end

            local hasLiveTarget = UnitExists("target") and not UnitIsDead("target")

            if
                not shouldSkipFade
                and hasLiveTarget
                and fadeConfig.exceptIfTargetCanBeAttacked
                and UnitCanAttack("player", "target")
            then
                shouldSkipFade = true
            end

            if
                not shouldSkipFade
                and hasLiveTarget
                and fadeConfig.exceptIfTargetCanBeHelped
                and UnitCanAssist("player", "target")
            then
                shouldSkipFade = true
            end

            if not shouldSkipFade then
                local opacity = fadeConfig.opacity or 100
                alpha = math.max(0, math.min(1, opacity / 100))
            end
        end
    end

    setAlpha(alpha)

    -- Single enforcement pass for Blizzard frames after all state is settled
    enforceBlizzardFrameState()
end

--- Gets the saved detached anchor position for the current or provided layout.
---@param layoutName string|nil
---@return ECM_EditModePosition
local function getDetachedAnchorPosition(layoutName)
    local gc = ECM.GetGlobalConfig()
    return EditMode.GetPosition(gc and gc.detachedAnchorPositions, nil, layoutName)
end

--- Saves the detached anchor position for the given layout.
---@param layoutName string
---@param point string
---@param x number
---@param y number
local function saveDetachedAnchorPosition(layoutName, point, x, y)
    local gc = ECM.GetGlobalConfig()
    EditMode.SavePosition(gc, "detachedAnchorPositions", layoutName, point, x, y)
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
            saveDetachedAnchorPosition(layoutName, point, x, y)
            Runtime.ScheduleLayoutUpdate(0, "DetachedAnchorDrag")
        end,
        allowDrag = true,
        settings = {
            {
                kind = LibEQOLEditMode.SettingType.Slider,
                name = L["WIDTH"],
                get = function()
                    local gc = ECM.GetGlobalConfig()
                    return (gc and gc.detachedBarWidth) or C.DEFAULT_BAR_WIDTH
                end,
                set = function(_, value)
                    local gc = ECM.GetGlobalConfig()
                    if gc then
                        gc.detachedBarWidth = value
                        Runtime.ScheduleLayoutUpdate(0, "DetachedAnchorWidth")
                    end
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
                    local gc = ECM.GetGlobalConfig()
                    return (gc and gc.detachedModuleSpacing) or 0
                end,
                set = function(_, value)
                    local gc = ECM.GetGlobalConfig()
                    if gc then
                        gc.detachedModuleSpacing = value
                        Runtime.ScheduleLayoutUpdate(0, "DetachedAnchorSpacing")
                    end
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
                    local gc = ECM.GetGlobalConfig()
                    return (gc and gc.detachedGrowDirection) or C.GROW_DIRECTION_DOWN
                end,
                set = function(_, value)
                    local gc = ECM.GetGlobalConfig()
                    if gc then
                        gc.detachedGrowDirection = value
                        Runtime.ScheduleLayoutUpdate(0, "DetachedAnchorGrowDirection")
                    end
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
    ECM.FrameUtil.LazySetAnchors(anchor, {
        { pos.point, UIParent, pos.point, pos.x, pos.y },
    })
    _detachedAnchorLayout = layoutName
    return true
end

--- Updates the detached anchor frame's size and visibility.
--- Shows the anchor when any module uses detached mode, hides otherwise.
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
    local gc = ECM.GetGlobalConfig()
    local barWidth = (gc and gc.detachedBarWidth) or C.DEFAULT_BAR_WIDTH
    local spacing = (gc and gc.detachedModuleSpacing) or 0

    if count > 1 then
        totalHeight = totalHeight + (spacing * (count - 1))
    end

    ECM.FrameUtil.LazySetWidth(anchor, barWidth)
    ECM.FrameUtil.LazySetHeight(anchor, math.max(totalHeight, 1))

    -- Apply saved position only when first showing or after a layout switch;
    -- continuous re-application fights with LibEQOL drag state and can reset
    -- the anchor to the default position when the layout name is momentarily
    -- unavailable during edit mode transitions.
    local layoutName = EditMode.GetActiveLayoutName()
    if layoutName and (not anchor:IsShown() or layoutName ~= _detachedAnchorLayout) then
        applyDetachedAnchorPosition(anchor, layoutName)
    end

    if not anchor:IsShown() then
        anchor:Show()
    end
end

local function updateAllLayouts(reason)
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

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
--- @param reason string|nil The lifecycle reason (defaults to OPTION_CHANGED)
function Runtime.ScheduleLayoutUpdate(delay, reason)
    if _layoutPending then
        return
    end

    _layoutPending = true
    C_Timer.After(delay or 0, function()
        _layoutPending = false
        hookCooldownViewerSettings()
        updateFadeAndHiddenStates()
        updateAllLayouts(reason)
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
    hookCooldownViewerSettings()

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

    if config.delay and config.delay > 0 then
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

    if _layoutWatchdogTicker and type(_layoutWatchdogTicker.Cancel) == "function" then
        _layoutWatchdogTicker:Cancel()
    end

    for eventName in pairs(LAYOUT_EVENTS) do
        addon:RegisterEvent(eventName, function(_, ...) handleLayoutEvent(addon, eventName, ...) end)
    end
    addon:RegisterEvent("CVAR_UPDATE", function(_, ...) handleLayoutEvent(addon, "CVAR_UPDATE", ...) end)

    -- Watchdog — catches cases where the game externally re-shows or resets alpha
    -- on Blizzard cooldown viewer frames between layout events.
    _layoutWatchdogTicker = C_Timer.NewTicker(C.WATCHDOG_INTERVAL, function()
        hookBlizzardFrames()
        hookCooldownViewerSettings()
        enforceBlizzardFrameState()

        local alpha = _desiredAlpha
        for _, module in pairs(_modules) do
            if module.InnerFrame and not module.IsHidden then
                ECM.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
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

    if _layoutWatchdogTicker and type(_layoutWatchdogTicker.Cancel) == "function" then
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

    local moduleOrder = {
        C.POWERBAR,
        C.RESOURCEBAR,
        C.RUNEBAR,
        C.BUFFBARS,
        C.ITEMICONS,
    }

    for _, moduleName in ipairs(moduleOrder) do
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
