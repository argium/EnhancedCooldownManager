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
                if frame.IsShown and frame:IsShown() then
                    frame._ecmHidden = true
                    pcall(frame.Hide, frame)
                end
            elseif frame._ecmHidden then
                frame._ecmHidden = nil
                pcall(frame.Show, frame)
            end
        end
    end

    assert(EnhancedCooldownManager.PowerBars, "ECM: PowerBars module missing")
    assert(EnhancedCooldownManager.SegmentBar, "ECM: SegmentBar module missing")
    EnhancedCooldownManager.PowerBars:SetExternallyHidden(hidden)
    EnhancedCooldownManager.SegmentBar:SetExternallyHidden(hidden)
end

local function UpdateLayoutInternal()
    local EssentialCooldownViewer = _G["EssentialCooldownViewer"]
    if not EssentialCooldownViewer then
        Util.Log("ViewerHook", "UpdateLayoutInternal skipped - no EssentialCooldownViewer")
        return
    end

    -- Hide if Cooldown Manager CVar is disabled
    local cooldownViewerEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled")
    if not cooldownViewerEnabled then
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden (cooldownViewerEnabled CVar disabled)")
        SetHidden(true)
        return
    end

    -- Hide/show based on mounted state
    local hidden = false
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if profile and profile.hideWhenMounted then
        hidden = IsMounted()
    end
    SetHidden(hidden)

    if hidden then
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden (mounted)")
        return
    end

    Util.Log("ViewerHook", "UpdateLayoutInternal - triggering module layouts")

    -- Trigger layout updates on ECM-managed bars
    assert(EnhancedCooldownManager.PowerBars, "ECM: PowerBars module missing")
    assert(EnhancedCooldownManager.SegmentBar, "ECM: SegmentBar module missing")
    assert(EnhancedCooldownManager.BuffBars, "ECM: BuffBars module missing")
    assert(EnhancedCooldownManager.ProcOverlay, "ECM: ProcOverlay module missing")

    EnhancedCooldownManager.PowerBars:UpdateLayout()
    EnhancedCooldownManager.SegmentBar:UpdateLayout()

    -- BuffBarCooldownViewer children can be re-created/re-anchored during zone transitions.
    -- A small delay ensures Blizzard frames have settled before we style them.
    EnhancedCooldownManager.BuffBars:UpdateLayout()
    C_Timer.After(0.1, function()
        EnhancedCooldownManager.BuffBars:UpdateLayout()
    end)

    -- ProcOverlay needs to run after buff icons are visible
    EnhancedCooldownManager.ProcOverlay:UpdateLayout()
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

local f = CreateFrame("Frame")
local function OnEvent(_, event, arg1)
    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownManager" then
            -- Only log the CVAR_UPDATE events we care about.
            Util.Log("ViewerHook", "OnEvent", { event = event, arg1 = arg1 })
            ScheduleLayoutUpdate(0)
        end
        return
    end

    Util.Log("ViewerHook", "OnEvent", { event = event, arg1 = arg1 })

    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        ScheduleLayoutUpdate(0)
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
        C_Timer.After(0.4, function()
            -- Reset BuffBars markers on world entry (hearthing, portals, loading screens)
            -- to force re-anchor since Blizzard may have repositioned frames.
            EnhancedCooldownManager.BuffBars:ResetStyledMarkers()
            ScheduleLayoutUpdate(0)
        end)
        return
    end

    if event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        C_Timer.After(0.3, function()
            -- Reset BuffBars markers to force re-anchor after zone transition.
            -- Blizzard repositions frames during zone changes, so our cached anchor
            -- positions become stale even though the anchor frame reference is the same.
            EnhancedCooldownManager.BuffBars:ResetStyledMarkers()
            ScheduleLayoutUpdate(0)
        end)
        return
    end
end

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")
f:RegisterEvent("ZONE_CHANGED")
f:RegisterEvent("ZONE_CHANGED_INDOORS")
f:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
f:RegisterEvent("CVAR_UPDATE")
f:SetScript("OnEvent", OnEvent)
