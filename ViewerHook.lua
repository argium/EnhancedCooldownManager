local _, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

local COOLDOWN_MANAGER_FRAME_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local _layoutUpdatePending = false

local _lastHiddenState = nil

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
    PLAYER_REGEN_ENABLED = { delay = 0.4, resetBuffBars = true },
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
