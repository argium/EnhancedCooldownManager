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
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _lastAlpha = 1

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

--- Sets the globally hidden state for all frames (ModuleMixins + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
local function SetGloballyHidden(hidden, reason)
    local stateChanged = _globallyHidden ~= hidden or _hideReason ~= reason

    if stateChanged then
        ECM_log(ECM.Constants.SYS.Layout, nil, "SetGloballyHidden " .. (hidden and "HIDDEN" or "VISIBLE") .. (reason and (" due to " .. reason) or ""))
    end

    _globallyHidden = hidden
    _hideReason = reason

    -- Always enforce Blizzard frame state; the game may re-show them externally
    ForEachBlizzardFrame(function(frame, name)
        if hidden then
            if frame:IsShown() then
                frame:Hide()
            end
        else
            frame:Show()
        end
    end)

    -- Hide/show ModuleMixins
    for _, module in pairs(_modules) do
        module:SetHidden(hidden)
    end
end


local function SetAlpha(alpha)
    if _lastAlpha == alpha then
        return
    end

    ForEachBlizzardFrame(function(frame)
        frame:SetAlpha(alpha)
    end)

    for _, module in pairs(_modules) do
        --- @type ModuleMixin
        module:SetAlpha(alpha)
    end

    _lastAlpha = alpha
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

local _chainSet = {}
for _, name in ipairs(ECM.Constants.CHAIN_ORDER) do _chainSet[name] = true end

local function UpdateAllLayouts(reason)
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
    ECM_log(ECM.Constants.SYS.Layout, nil, "Frame registered: " .. frame.Name)

    -- Sync current global hidden/alpha state to late-registered frames
    if _globallyHidden then
        frame:SetHidden(true)
    end
    if _lastAlpha ~= 1 then
        frame:SetAlpha(_lastAlpha)
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
    ECM_log(ECM.Constants.SYS.Layout, nil, "Frame unregistered: " .. name)
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
