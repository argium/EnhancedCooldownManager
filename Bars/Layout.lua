-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local LAYOUT_EVENTS = {
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    UNIT_ENTERED_VEHICLE = { delay = 0 },
    UNIT_EXITED_VEHICLE = { delay = 0 },
    VEHICLE_UPDATE = { delay = 0 },
    PLAYER_UPDATE_RESTING = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    PLAYER_ENTERING_WORLD = { delay = 0.4 },
    PLAYER_TARGET_CHANGED = { delay = 0 },
    PLAYER_REGEN_ENABLED = { delay = 0.1, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = 0.1 },
    ZONE_CHANGED = { delay = 0.1 },
    ZONE_CHANGED_INDOORS = { delay = 0.1 },
    UPDATE_SHAPESHIFT_FORM = { delay = 0 },
}

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local _modules = {}
local _globallyHidden = false
local _hideReason = nil
local _desiredAlpha = 1
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _cooldownViewerSettingsHooked = false
local _hookedBlizzardFrames = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Iterates over all Blizzard cooldown viewer frames.
--- @param fn fun(frame: Frame, name: string)
local function ForEachBlizzardFrame(fn)
    for _, name in ipairs(ECM.Constants.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            fn(frame, name)
        end
    end
end

--- Enforces the current desired visibility and alpha on all Blizzard frames.
--- Single enforcement point called from state changes, OnShow hooks, and the
--- watchdog ticker.
local function EnforceBlizzardFrameState()
    local alpha = _desiredAlpha
    ForEachBlizzardFrame(function(frame)
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
    end)
end

--- Hooks a Blizzard frame's OnShow to immediately re-enforce desired state.
--- Provides sub-frame correction when the game externally re-shows a frame.
--- @param frame Frame
--- @param name string
local function HookBlizzardFrame(frame, name)
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
local function HookBlizzardFrames()
    ForEachBlizzardFrame(function(frame, name)
        HookBlizzardFrame(frame, name)
    end)
end

--- Sets the globally hidden state for all frames (ModuleMixins + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
local function SetGloballyHidden(hidden, reason)
    local stateChanged = _globallyHidden ~= hidden or _hideReason ~= reason

    if stateChanged then
        ECM.Log(nil, "SetGloballyHidden " .. (hidden and "HIDDEN" or "VISIBLE") .. (reason and (" due to " .. reason) or ""))
    end

    _globallyHidden = hidden
    _hideReason = reason

    EnforceBlizzardFrameState()

    for _, module in pairs(_modules) do
        module:SetHidden(hidden)
    end
end

--- Applies alpha to all managed frames.
--- @param alpha number
local function SetAlpha(alpha)
    _desiredAlpha = alpha

    EnforceBlizzardFrameState()

    for _, module in pairs(_modules) do
        if module.InnerFrame then
            ECM.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
        end
    end
end

--- Checks all fade and hide conditions and updates global state.
local function UpdateFadeAndHiddenStates()
    local globalConfig = mod.db and mod.db.profile and mod.db.profile.global
    if not globalConfig then
        return
    end

    -- Check CVar first
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        SetGloballyHidden(true, "cvar")
        return
    end

    -- Check mounted or in vehicle
    if globalConfig.hideWhenMounted and (IsMounted() or UnitInVehicle("player")) then
        SetGloballyHidden(true, "mounted")
        return
    end

    if not _inCombat and globalConfig.hideOutOfCombatInRestAreas and IsResting() then
        SetGloballyHidden(true, "rest")
        return
    end

    -- No hide reason, show everything
    SetGloballyHidden(false, nil)

    local alpha = 1
    local fadeConfig = globalConfig.outOfCombatFade
    if not _inCombat and fadeConfig and fadeConfig.enabled then
        local shouldSkipFade = false

        if fadeConfig.exceptInInstance and IsInInstance() then
            shouldSkipFade = true
        end

        local hasLiveTarget = UnitExists("target") and not UnitIsDead("target")

        if not shouldSkipFade and hasLiveTarget and fadeConfig.exceptIfTargetCanBeAttacked and UnitCanAttack("player", "target") then
            shouldSkipFade = true
        end

        if not shouldSkipFade and hasLiveTarget and fadeConfig.exceptIfTargetCanBeHelped and UnitCanAssist("player", "target") then
            shouldSkipFade = true
        end

        if not shouldSkipFade then
            local opacity = fadeConfig.opacity or 100
            alpha = math.max(0, math.min(1, opacity / 100))
        end
    end

    SetAlpha(alpha)
end

local UpdateAllLayouts

--- Hooks CooldownViewerSettings hide to force alpha/layout reapplication.
local function HookCooldownViewerSettings()
    if _cooldownViewerSettingsHooked then
        return
    end

    local settingsFrame = _G.CooldownViewerSettings
    if not settingsFrame then
        return
    end

    settingsFrame:HookScript("OnHide", function()
        UpdateFadeAndHiddenStates()
        UpdateAllLayouts("OnHide:CooldownViewerSettings")
    end)

    _cooldownViewerSettingsHooked = true
    ECM.Log(nil, "Hooked CooldownViewerSettings OnHide")
end

local _chainSet = {}
for _, name in ipairs(ECM.Constants.CHAIN_ORDER) do _chainSet[name] = true end

UpdateAllLayouts = function(reason)
    -- Chain frames must update in deterministic order so downstream bars can
    -- resolve anchors against already-laid-out predecessors.
    for _, moduleName in ipairs(ECM.Constants.CHAIN_ORDER) do
        local module = _modules[moduleName]
        if module then
            module:ThrottledUpdateLayout(reason)
        end
    end

    -- Update all remaining frames (non-chain modules).
    for frameName, module in pairs(_modules) do
        if not _chainSet[frameName] then
            module:ThrottledUpdateLayout(reason)
        end
    end
end

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
--- @param reason string|nil The lifecycle reason (defaults to OPTION_CHANGED)
local function ScheduleLayoutUpdate(delay, reason)
    if _layoutPending then
        return
    end

    _layoutPending = true
    C_Timer.After(delay or 0, function()
        _layoutPending = false
        HookCooldownViewerSettings()
        UpdateFadeAndHiddenStates()
        UpdateAllLayouts(reason)
    end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Registers a ModuleMixin to receive layout update events.
--- @param frame ModuleMixin The frame to register
local function RegisterFrame(frame)
    assert(frame and type(frame) == "table" and frame.IsModuleMixin, "RegisterFrame: invalid ModuleMixin")
    assert(_modules[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")
    _modules[frame.Name] = frame
    ECM.Log(nil, "Frame registered: " .. frame.Name)

    -- Sync current global hidden and alpha state to late-registered frames
    if _globallyHidden then
        frame:SetHidden(true)
    end
    if frame.InnerFrame then
        ECM.FrameUtil.LazySetAlpha(frame.InnerFrame, _desiredAlpha)
    end
end

--- Unregisters a ModuleMixin from layout update events.
--- @param frame ModuleMixin The frame to unregister
local function UnregisterFrame(frame)
    if not frame or type(frame) ~= "table" then
        return
    end

    local name = frame.Name
    if not name or _modules[name] ~= frame then
        return
    end

    _modules[name] = nil

    -- Disabled modules are removed from future layout passes, so hide the
    -- current frame immediately to prevent stale bar visuals from lingering.
    if frame.InnerFrame then
        frame.InnerFrame:Hide()
    end

    ECM.Log(nil, "Frame unregistered: " .. name)
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")

-- Register all layout events
for eventName in pairs(LAYOUT_EVENTS) do
    eventFrame:RegisterEvent(eventName)
end
eventFrame:RegisterEvent("CVAR_UPDATE")

eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    HookCooldownViewerSettings()

    if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then
        return
    end

    -- Handle CVAR_UPDATE specially
    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownViewerEnabled" then
            ScheduleLayoutUpdate(0, "CVAR_UPDATE:cooldownViewerEnabled")
        end
        return
    end

    local config = LAYOUT_EVENTS[event]
    if not config then
        return
    end

    -- Track combat state
    if config.combatChange then
        _inCombat = (event == "PLAYER_REGEN_DISABLED")
    end

    if config.delay and config.delay > 0 then
        C_Timer.After(config.delay, function()
            UpdateFadeAndHiddenStates()
            UpdateAllLayouts(event)
        end)
    else
        UpdateFadeAndHiddenStates()
        UpdateAllLayouts(event)
    end

end)

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

ECM.RegisterFrame = RegisterFrame
ECM.UnregisterFrame = UnregisterFrame
ECM.ScheduleLayoutUpdate = ScheduleLayoutUpdate

--------------------------------------------------------------------------------
-- Watchdog — periodic state enforcement
--
-- Catches cases where the game externally re-shows or resets alpha on Blizzard
-- cooldown viewer frames between layout events. The ticker is lightweight: lazy
-- setters make no-op ticks nearly free (just a comparison per frame).
--------------------------------------------------------------------------------

C_Timer.NewTicker(ECM.Constants.WATCHDOG_INTERVAL, function()
    HookBlizzardFrames()
    HookCooldownViewerSettings()
    EnforceBlizzardFrameState()

    -- Re-enforce alpha on module frames in case of external resets
    local alpha = _desiredAlpha
    for _, module in pairs(_modules) do
        if module.InnerFrame and not module.IsHidden then
            ECM.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
        end
    end
end)
