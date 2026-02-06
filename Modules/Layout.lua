-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local C = ns.Constants
local Util = ns.Util

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

local _ecmFrames = {}
local _globallyHidden = false
local _hideReason = nil
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _lastAlpha = 1

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Iterates over all Blizzard cooldown viewer frames.
--- @param fn fun(frame: Frame, name: string)
local function ForEachBlizzardFrame(fn)
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            fn(frame, name)
        end
    end
end

--- Sets the globally hidden state for all frames (ECMFrames + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
local function SetGloballyHidden(hidden, reason)
    if _globallyHidden == hidden and _hideReason == reason then
        return
    end

    Util.Log("Layout", "SetGloballyHidden", { hidden = hidden, reason = reason })

    _globallyHidden = hidden
    _hideReason = reason

    -- Hide/show Blizzard frames
    ForEachBlizzardFrame(function(frame, name)
        if hidden then
            if frame:IsShown() then
                frame:Hide()
            end
        else
            frame:Show()
        end
    end)

    -- Hide/show ECMFrames
    for _, ecmFrame in pairs(_ecmFrames) do
        ecmFrame:SetHidden(hidden)
    end
end


local function SetAlpha(alpha)
    if _lastAlpha == alpha then
        return
    end

    ForEachBlizzardFrame(function(frame)
        frame:SetAlpha(alpha)
    end)

    for _, ecmFrame in pairs(_ecmFrames) do
        ecmFrame.InnerFrame:SetAlpha(alpha)
    end

    _lastAlpha = alpha
end

--- Checks all fade and hide conditions and updates global state.
local function UpdateFadeAndHiddenStates()
    local globalConfig = ECM.db and ECM.db.profile and ECM.db.profile.global
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

        if fadeConfig.exceptInInstance then
            local inInstance, instanceType = IsInInstance()
            if inInstance and C.GROUP_INSTANCE_TYPES[instanceType] then
                shouldSkipFade = true
            end
        end

        if not shouldSkipFade and fadeConfig.exceptIfTargetCanBeAttacked and UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") then
            shouldSkipFade = true
        end

        if not shouldSkipFade then
            local opacity = fadeConfig.opacity or 100
            alpha = math.max(0, math.min(1, opacity / 100))
        end
    end

    SetAlpha(alpha)
end

--- Calls UpdateLayout on all registered ECMFrames.
local function UpdateAllLayouts()
    local updated = {}

    -- Chain frames must update in deterministic order so downstream bars can
    -- resolve anchors against already-laid-out predecessors.
    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local ecmFrame = _ecmFrames[moduleName]
        if ecmFrame then
            ecmFrame:UpdateLayout()
            updated[moduleName] = true
        end
    end

    -- Update all remaining frames (non-chain modules).
    for frameName, ecmFrame in pairs(_ecmFrames) do
        if not updated[frameName] then
            ecmFrame:UpdateLayout()
        end
    end
end

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
local function ScheduleLayoutUpdate(delay)
    if _layoutPending then
        return
    end

    _layoutPending = true
    C_Timer.After(delay or 0, function()
        _layoutPending = false
        UpdateFadeAndHiddenStates()
        UpdateAllLayouts()
    end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Registers an ECMFrame to receive layout update events.
--- @param frame ECMFrame The frame to register
local function RegisterFrame(frame)
    assert(frame and type(frame) == "table" and frame.IsECMFrame, "RegisterFrame: invalid ECMFrame")
    assert(_ecmFrames[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")
    _ecmFrames[frame.Name] = frame
    ECM.Log("Layout", "Frame registered", frame.Name)
end

--- Unregisters an ECMFrame from layout update events.
--- @param frame ECMFrame The frame to unregister
local function UnregisterFrame(frame)
    if not frame or type(frame) ~= "table" then
        return
    end

    local name = frame.Name
    if not name or _ecmFrames[name] ~= frame then
        return
    end

    _ecmFrames[name] = nil
    ECM.Log("Layout", "Frame unregistered", name)
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
    if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then
        return
    end

    -- Handle CVAR_UPDATE specially
    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownViewerEnabled" then
            ScheduleLayoutUpdate(0)
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

    -- Schedule update with delay
    if config.delay and config.delay > 0 then
        C_Timer.After(config.delay, function()
            UpdateFadeAndHiddenStates()
            UpdateAllLayouts()
        end)
    else
        UpdateFadeAndHiddenStates()
        UpdateAllLayouts()
    end
end)

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

ECM.RegisterFrame = RegisterFrame
ECM.UnregisterFrame = UnregisterFrame
ECM.ScheduleLayoutUpdate = ScheduleLayoutUpdate
