local _, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

local COOLDOWN_MANAGER_FRAME_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local COMBAT_FADE_DURATION = 0.15

local _layoutUpdatePending = false
local _lastHiddenState = nil
local _inCombat = InCombatLockdown()
local _lastFadeAlpha = nil

local function SetHidden(hidden)
    -- Log only when state changes
    if _lastHiddenState ~= hidden then
        Util.Log("ViewerHook", "SetHidden", { hidden = hidden })
        _lastHiddenState = hidden
    end

    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame then
            if hidden then
                if frame:IsShown() then
                    frame._ecmHidden = true
                    frame:Hide()
                end
            elseif frame._ecmHidden then
                frame._ecmHidden = nil
                frame:Show()
            end
        end
    end

    EnhancedCooldownManager.PowerBars:SetExternallyHidden(hidden)
    EnhancedCooldownManager.SegmentBar:SetExternallyHidden(hidden)
end

--- Checks if combat fade should be applied based on config and instance type.
---@return boolean shouldFade, number alpha
local function GetCombatFadeState()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile or not profile.combatFade or not profile.combatFade.enabled then
        return false, 1
    end

    -- If in combat, always show at full opacity
    if _inCombat then
        return false, 1
    end

    -- Check instance exception
    if profile.combatFade.exceptInInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "arena" or instanceType == "pvp") then
            return false, 1
        end
    end

    -- Out of combat and should fade
    local alpha = (profile.combatFade.opacity or 30) / 100
    return true, alpha
end

--- Applies fade animation to a single frame.
---@param frame Frame|nil Frame to fade
---@param targetAlpha number Target alpha value (0-1)
---@param duration number Animation duration in seconds
local function ApplyFrameFade(frame, targetAlpha, duration)
    if not frame then
        return
    end

    if duration > 0 and UIFrameFadeIn and UIFrameFadeOut then
        if targetAlpha < 1 then
            UIFrameFadeOut(frame, duration, frame:GetAlpha(), targetAlpha)
        else
            UIFrameFadeIn(frame, duration, frame:GetAlpha(), targetAlpha)
        end
    else
        frame:SetAlpha(targetAlpha)
    end
end

--- Applies combat fade to all cooldown viewer frames and ECM bars.
---@param targetAlpha number Target alpha value (0-1)
---@param instant boolean|nil If true, skip animation
local function ApplyCombatFade(targetAlpha, instant)
    if _lastFadeAlpha == targetAlpha then
        return
    end

    Util.Log("ViewerHook", "ApplyCombatFade", { targetAlpha = targetAlpha, instant = instant })
    _lastFadeAlpha = targetAlpha

    local duration = instant and 0 or COMBAT_FADE_DURATION

    -- Fade Blizzard frames
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and not frame._ecmHidden then
            ApplyFrameFade(frame, targetAlpha, duration)
        end
    end

    -- Fade ECM module frames (use public GetFrame() method)
    local powerBarFrame = EnhancedCooldownManager.PowerBars and EnhancedCooldownManager.PowerBars:GetFrame()
    if powerBarFrame and powerBarFrame:IsShown() then
        ApplyFrameFade(powerBarFrame, targetAlpha, duration)
    end

    local segmentBarFrame = EnhancedCooldownManager.SegmentBar and EnhancedCooldownManager.SegmentBar:GetFrame()
    if segmentBarFrame and segmentBarFrame:IsShown() then
        ApplyFrameFade(segmentBarFrame, targetAlpha, duration)
    end
end

--- Updates combat fade state based on current conditions.
local function UpdateCombatFade()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return
    end

    -- If externally hidden (mounted), don't apply fade
    if _lastHiddenState then
        _lastFadeAlpha = nil -- Reset so fade reapplies when unhidden
        return
    end

    local _, targetAlpha = GetCombatFadeState()
    ApplyCombatFade(targetAlpha, false)
end

local function UpdateLayoutInternal()
    if not _G["EssentialCooldownViewer"] then
        Util.Log("ViewerHook", "UpdateLayoutInternal skipped - no EssentialCooldownViewer")
        return
    end

    -- Hide if Cooldown Manager CVar is disabled
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden (cooldownViewerEnabled CVar disabled)")
        SetHidden(true)
        return
    end

    -- Hide/show based on mounted state
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local hidden = profile and profile.hideWhenMounted and IsMounted()
    SetHidden(hidden)

    if hidden then
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden (mounted)")
        return
    end

    Util.Log("ViewerHook", "UpdateLayoutInternal - triggering module layouts")

    EnhancedCooldownManager.PowerBars:UpdateLayout()
    EnhancedCooldownManager.SegmentBar:UpdateLayout()
    EnhancedCooldownManager.BuffBars:UpdateLayout()
    EnhancedCooldownManager.ProcOverlay:UpdateLayout()

    -- BuffBarCooldownViewer children can be re-created/re-anchored during zone transitions.
    -- A small delay ensures Blizzard frames have settled before we style them.
    C_Timer.After(0.1, function()
        EnhancedCooldownManager.BuffBars:UpdateLayout()
    end)

    -- Apply combat fade after layout updates
    UpdateCombatFade()
end

local function ScheduleLayoutUpdate(delay)
    if _layoutUpdatePending then
        return
    end
    _layoutUpdatePending = true
    C_Timer.After(delay or 0, function()
        _layoutUpdatePending = false
        UpdateLayoutInternal()
    end)
end

-- Event handling configuration: maps events to their delay and whether to reset BuffBars
local EVENT_CONFIG = {
    -- Immediate updates (no delay, no reset)
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    -- Delayed updates with BuffBars reset (zone/world transitions)
    PLAYER_ENTERING_WORLD = { delay = 0.4, resetBuffBars = true },
    PLAYER_REGEN_ENABLED = { delay = 0.4, resetBuffBars = true, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = 0.3, resetBuffBars = true },
    ZONE_CHANGED = { delay = 0.3, resetBuffBars = true },
    ZONE_CHANGED_INDOORS = { delay = 0.3, resetBuffBars = true },
}

local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(_, event, arg1)
    -- CVAR_UPDATE is special: only handle cooldownManager changes
    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownManager" then
            Util.Log("ViewerHook", "OnEvent", { event = event, arg1 = arg1 })
            ScheduleLayoutUpdate(0)
        end
        return
    end

    local config = EVENT_CONFIG[event]
    if not config then
        return
    end

    Util.Log("ViewerHook", "OnEvent", { event = event, arg1 = arg1 })

    -- Track combat state for combat fade feature
    if config.combatChange then
        local wasInCombat = _inCombat
        _inCombat = (event == "PLAYER_REGEN_DISABLED")

        if wasInCombat ~= _inCombat then
            Util.Log("ViewerHook", "CombatStateChanged", { inCombat = _inCombat })
            -- For entering combat, update fade immediately
            if _inCombat then
                UpdateCombatFade()
            end
        end
    end

    if config.delay > 0 then
        C_Timer.After(config.delay, function()
            if config.resetBuffBars then
                EnhancedCooldownManager.BuffBars:ResetStyledMarkers()
            end
            ScheduleLayoutUpdate(0)
        end)
    else
        ScheduleLayoutUpdate(0)
    end
end)

for event in pairs(EVENT_CONFIG) do
    f:RegisterEvent(event)
end
f:RegisterEvent("CVAR_UPDATE")

-- Export for Options.lua to call when settings change
ns.UpdateCombatFade = UpdateCombatFade
