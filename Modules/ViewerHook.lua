local _, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

local ViewerHook = EnhancedCooldownManager:NewModule("ViewerHook", "AceEvent-3.0")
EnhancedCooldownManager.ViewerHook = ViewerHook

local COOLDOWN_MANAGER_FRAME_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local COMBAT_FADE_DURATION = 0.15
local REST_HIDE_FADE_DURATION = 0.3

local _layoutUpdatePending = false
local _lastHiddenState = nil
local _hideReason = nil -- "mounted", "rest", or nil
local _fadingToHidden = false -- true while fade-to-hide animation is in progress
local _inCombat = InCombatLockdown()
local _lastFadeAlpha = nil
local _registeredBars = {}

-- Forward declaration
local GetCombatFadeState

--- Cancels any in-progress fade animations on all frames.
local function CancelAllFades()
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and UIFrameFadeRemoveFrame then
            UIFrameFadeRemoveFrame(frame)
        end
    end
    for _, module in ipairs(_registeredBars) do
        local frame = module:GetFrame()
        if frame and UIFrameFadeRemoveFrame then
            UIFrameFadeRemoveFrame(frame)
        end
    end
    _fadingToHidden = false
end

--- Actually hides all frames (called after fade completes or immediately for instant hide).
local function HideAllFrames()
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() then
            frame._ecmHidden = true
            frame:Hide()
        end
    end
    for _, module in ipairs(_registeredBars) do
        module:SetExternallyHidden(true)
    end
end

--- Actually shows all frames (called before fade-in or immediately for instant show).
local function ShowAllFrames()
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and frame._ecmHidden then
            frame._ecmHidden = nil
            frame:Show()
        end
    end
    for _, module in ipairs(_registeredBars) do
        module:SetExternallyHidden(false)
    end
end

--- Fades all frames to 0 alpha, then hides them.
---@param duration number Fade duration in seconds
---@param onComplete function|nil Optional callback when fade completes
local function ApplyFadeToHidden(duration, onComplete)
    _fadingToHidden = true
    local framesRemaining = 0

    local function onFrameFadeComplete()
        framesRemaining = framesRemaining - 1
        if framesRemaining <= 0 then
            _fadingToHidden = false
            HideAllFrames()
            if onComplete then
                onComplete()
            end
        end
    end

    -- Count frames to fade
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() and not frame._ecmHidden then
            framesRemaining = framesRemaining + 1
        end
    end
    for _, module in ipairs(_registeredBars) do
        local frame = module:GetFrameIfShown()
        if frame then
            framesRemaining = framesRemaining + 1
        end
    end

    if framesRemaining == 0 then
        _fadingToHidden = false
        HideAllFrames()
        if onComplete then
            onComplete()
        end
        return
    end

    -- Fade Blizzard frames
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() and not frame._ecmHidden then
            local fadeInfo = {
                mode = "OUT",
                timeToFade = duration,
                startAlpha = frame:GetAlpha(),
                endAlpha = 0,
                finishedFunc = onFrameFadeComplete,
            }
            UIFrameFade(frame, fadeInfo)
        end
    end

    -- Fade ECM module frames
    for _, module in ipairs(_registeredBars) do
        local frame = module:GetFrameIfShown()
        if frame then
            local fadeInfo = {
                mode = "OUT",
                timeToFade = duration,
                startAlpha = frame:GetAlpha(),
                endAlpha = 0,
                finishedFunc = onFrameFadeComplete,
            }
            UIFrameFade(frame, fadeInfo)
        end
    end
end

--- Shows all frames at 0 alpha, then fades them to the target alpha.
---@param duration number Fade duration in seconds
---@param targetAlpha number Target alpha value (0-1)
local function ApplyFadeFromHidden(duration, targetAlpha)
    -- Show frames at 0 alpha first
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and frame._ecmHidden then
            frame._ecmHidden = nil
            frame:SetAlpha(0)
            frame:Show()
        end
    end
    for _, module in ipairs(_registeredBars) do
        local frame = module:GetFrame()
        if frame then
            frame:SetAlpha(0)
        end
        module:SetExternallyHidden(false)
    end

    -- Fade in to target alpha
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame and frame:IsShown() then
            local fadeInfo = {
                mode = "IN",
                timeToFade = duration,
                startAlpha = 0,
                endAlpha = targetAlpha,
            }
            UIFrameFade(frame, fadeInfo)
        end
    end
    for _, module in ipairs(_registeredBars) do
        local frame = module:GetFrameIfShown()
        if frame then
            local fadeInfo = {
                mode = "IN",
                timeToFade = duration,
                startAlpha = 0,
                endAlpha = targetAlpha,
            }
            UIFrameFade(frame, fadeInfo)
        end
    end
end

--- Sets hidden state for all frames, with optional fade animation.
---@param hidden boolean Whether to hide or show frames
---@param options table|nil { fadeOut = bool, fadeIn = bool, duration = number, reason = string }
local function SetHidden(hidden, options)
    options = options or {}
    local reason = options.reason
    local duration = options.duration or 0

    -- Cancel any in-progress fades when state changes
    if _fadingToHidden or _lastHiddenState ~= hidden then
        CancelAllFades()
    end

    -- Log only when state changes
    if _lastHiddenState ~= hidden then
        Util.Log("ViewerHook", "SetHidden", {
            hidden = hidden,
            reason = reason,
            fadeOut = options.fadeOut,
            fadeIn = options.fadeIn,
            duration = duration,
        })
    end

    local prevHideReason = _hideReason

    if hidden then
        _hideReason = reason
        _lastHiddenState = true

        if options.fadeOut and duration > 0 then
            ApplyFadeToHidden(duration)
        else
            HideAllFrames()
        end
    else
        _hideReason = nil
        _lastHiddenState = false

        -- Determine target alpha for fade-in (respect combat fade state)
        local _, targetAlpha = GetCombatFadeState()
        _lastFadeAlpha = targetAlpha

        if options.fadeIn and duration > 0 then
            ApplyFadeFromHidden(duration, targetAlpha)
        else
            ShowAllFrames()
            -- Set correct alpha immediately
            for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
                local frame = _G[name]
                if frame then
                    frame:SetAlpha(targetAlpha)
                end
            end
            for _, module in ipairs(_registeredBars) do
                local frame = module:GetFrame()
                if frame then
                    frame:SetAlpha(targetAlpha)
                end
            end
        end
    end
end

--- Checks if combat fade should be applied based on config and instance type.
---@return boolean shouldFade, number alpha
GetCombatFadeState = function()
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
        local groupInstanceTypes = { party = true, raid = true, arena = true, pvp = true }
        if inInstance and groupInstanceTypes[instanceType] then
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

    -- Fade ECM module frames
    for _, module in ipairs(_registeredBars) do
        local frame = module and module:GetFrame()
        if frame and frame:IsShown() then
            ApplyFrameFade(frame, targetAlpha, duration)
        end
    end
end

local function UpdateLayoutInternal()
    if not _G["EssentialCooldownViewer"] then
        Util.Log("ViewerHook", "UpdateLayoutInternal skipped - no EssentialCooldownViewer")
        return
    end

    -- Hide if Cooldown Manager CVar is disabled
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden (cooldownViewerEnabled CVar disabled)")
        SetHidden(true, { reason = "cvar" })
        return
    end

    -- Hide/show based on mounted state or rest-area out-of-combat rule
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local hideWhenMounted = profile and profile.hideWhenMounted and IsMounted()
    local hideWhenRestingOutOfCombat = profile
        and profile.hideOutOfCombatInRestAreas
        and (not _inCombat)
        and IsResting()

    -- Determine hide state and fade behavior
    if hideWhenMounted then
        -- Mounted: instant hide, takes priority
        SetHidden(true, { reason = "mounted" })
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden", { mounted = true })
        return
    elseif hideWhenRestingOutOfCombat then
        -- Rest area + out of combat: fade out
        SetHidden(true, {
            fadeOut = true,
            duration = REST_HIDE_FADE_DURATION,
            reason = "rest",
        })
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden", { restOutOfCombat = true })
        return
    elseif _lastHiddenState then
        -- Unhiding: determine fade duration based on previous hide reason and current state
        local fadeDuration = 0
        local shouldFadeIn = false

        if _hideReason == "rest" then
            -- Was hidden due to rest: use rest duration if still in rest area (leaving rest),
            -- or combat duration if combat started
            if _inCombat then
                fadeDuration = COMBAT_FADE_DURATION
            else
                fadeDuration = REST_HIDE_FADE_DURATION
            end
            shouldFadeIn = true
        elseif _hideReason == "mounted" then
            -- Was hidden due to mount: instant show
            shouldFadeIn = false
        end

        SetHidden(false, {
            fadeIn = shouldFadeIn,
            duration = fadeDuration,
        })
    end

    Util.Log("ViewerHook", "UpdateLayoutInternal - triggering module layouts")

    for _, module in ipairs(_registeredBars) do
        module:UpdateLayout()
    end

    -- BuffBarCooldownViewer children can be re-created/re-anchored during zone transitions.
    -- A small delay ensures Blizzard frames have settled before we style them.
    -- C_Timer.After(0.1, function()
    --     EnhancedCooldownManager.BuffBars:UpdateLayout()
    -- end)

    -- Apply combat fade after layout updates
    ViewerHook:UpdateCombatFade()
end


-- Event handling configuration: maps events to their delay and whether to reset BuffBars
local EVENT_CONFIG = {
    -- Immediate updates (no delay, no reset)
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    PLAYER_UPDATE_RESTING = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    -- Delayed updates with BuffBars reset (zone/world transitions)
    PLAYER_LEVEL_UP = { delay = 1, resetBuffBars = true },
    PLAYER_ENTERING_WORLD = { delay = 0.4, resetBuffBars = true },
    PLAYER_REGEN_ENABLED = { delay = 0.1, resetBuffBars = true, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = 0.1, resetBuffBars = true },
    ZONE_CHANGED = { delay = 0.1, resetBuffBars = true },
    ZONE_CHANGED_INDOORS = { delay = 0.1, resetBuffBars = true },
}

function ViewerHook:OnEvent(event, arg1)
    -- CVAR_UPDATE is special: only handle cooldownManager changes
    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownManager" then
            Util.Log("ViewerHook", "OnEvent", { event = event, arg1 = arg1 })
            self:ScheduleLayoutUpdate(0)
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
                self:UpdateCombatFade()
            end
        end
    end

    local function doUpdate()
        if config.resetBuffBars then
            EnhancedCooldownManager.BuffBars:ResetStyledMarkers()
        end
        ViewerHook:ScheduleLayoutUpdate(0)
    end

    if config.delay > 0 then
        C_Timer.After(config.delay, doUpdate)
    else
        doUpdate()
    end
end

function ViewerHook:OnEnable()
    for event in pairs(EVENT_CONFIG) do
        self:RegisterEvent(event, "OnEvent")
    end
    self:RegisterEvent("CVAR_UPDATE", "OnEvent")
end

function ViewerHook:OnDisable()
    self:UnregisterAllEvents()
end

--- Updates combat fade state based on current conditions.
function ViewerHook:UpdateCombatFade()
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

function ViewerHook:ScheduleLayoutUpdate(delay)
    if _layoutUpdatePending then
        return
    end
    _layoutUpdatePending = true
    C_Timer.After(delay or 0, function()
        _layoutUpdatePending = false
        UpdateLayoutInternal()
    end)
end

function ViewerHook:RegisterBar(module)
    Util.Log("ViewerHook", "RegisterBar", { module = module._lifecycleConfig.name })
    table.insert(_registeredBars, module)
end
