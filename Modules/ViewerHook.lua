-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class Frame

---@class ECM_HookedFrame : Frame
---@field _ecmHidden boolean|nil

---@class ECM_BarModule
---@field GetFrame fun(self: ECM_BarModule): Frame
---@field GetFrameIfShown fun(self: ECM_BarModule): Frame|nil
---@field SetHidden fun(self: ECM_BarModule, hidden: boolean)
---@field IsHidden fun(self: ECM_BarModule): boolean
---@field UpdateLayout fun(self: ECM_BarModule)
---@field _name string

local _, ns = ...
local ECM = ns.Addon
local Util = ns.Util

local ViewerHook = ECM:NewModule("ViewerHook", "AceEvent-3.0")
ECM.ViewerHook = ViewerHook

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local COOLDOWN_MANAGER_FRAME_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local COMBAT_FADE_DURATION = 0.15
local REST_HIDE_FADE_DURATION = 0.3

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local _layoutUpdatePending = false
local _lastHiddenState = nil
local _hideReason = nil -- "mounted", "rest", or nil
local _fadingToHidden = false
local _inCombat = InCombatLockdown()
local _lastFadeAlpha = nil
local _registeredBars = {}

--------------------------------------------------------------------------------
-- Frame Iteration Helpers
--------------------------------------------------------------------------------

local function ForEachBlizzardFrame(fn)
    for _, name in ipairs(COOLDOWN_MANAGER_FRAME_NAMES) do
        local frame = _G[name]
        if frame then
            ---@cast frame ECM_HookedFrame
            fn(frame, name)
        end
    end
end

local function ForEachBarModule(fn)
    for _, module in ipairs(_registeredBars) do
        ---@cast module ECM_BarModule
        fn(module, module:GetFrame())
    end
end

--------------------------------------------------------------------------------
-- Combat Fade State
--------------------------------------------------------------------------------

local function GetCombatFadeState()
    local profile = ECM.db and ECM.db.profile
    if not profile or not profile.combatFade or not profile.combatFade.enabled then
        return false, 1
    end

    if _inCombat then
        return false, 1
    end

    if profile.combatFade.exceptInInstance then
        local inInstance, instanceType = IsInInstance()
        local groupInstanceTypes = { party = true, raid = true, arena = true, pvp = true, delve = true }
        if inInstance and groupInstanceTypes[instanceType] then
            return false, 1
        end
    end

    if profile.combatFade.exceptIfTargetCanBeAttacked and UnitExists("target") and UnitCanAttack("player", "target") then
        return false, 1
    end

    local alpha = (profile.combatFade.opacity or 30) / 100
    return true, alpha
end

--------------------------------------------------------------------------------
-- Fade Animation Helpers
--------------------------------------------------------------------------------

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

local function CancelAllFades()
    if not UIFrameFadeRemoveFrame then
        return
    end

    ForEachBlizzardFrame(function(frame)
        UIFrameFadeRemoveFrame(frame)
    end)
    ForEachBarModule(function(_, frame)
        if frame then
            UIFrameFadeRemoveFrame(frame)
        end
    end)
    _fadingToHidden = false
end

local function ApplyCombatFade(targetAlpha, instant)
    if _lastFadeAlpha == targetAlpha then
        return
    end

    Util.Log("ViewerHook", "ApplyCombatFade", { targetAlpha = targetAlpha, instant = instant })
    _lastFadeAlpha = targetAlpha

    local duration = instant and 0 or COMBAT_FADE_DURATION

    ForEachBlizzardFrame(function(frame)
        if not frame._ecmHidden then
            ApplyFrameFade(frame, targetAlpha, duration)
        end
    end)
    ForEachBarModule(function(_, frame)
        if frame and frame:IsShown() then
            ApplyFrameFade(frame, targetAlpha, duration)
        end
    end)
end

--------------------------------------------------------------------------------
-- Hide/Show Logic
--------------------------------------------------------------------------------

local function HideAllFrames()
    ForEachBlizzardFrame(function(frame)
        if frame:IsShown() then
            frame._ecmHidden = true
            frame:Hide()
        end
    end)
    ForEachBarModule(function(module)
        module:SetHidden(true)
    end)
end

local function ShowAllFrames()
    ForEachBlizzardFrame(function(frame)
        if frame._ecmHidden then
            frame._ecmHidden = nil
            frame:Show()
        end
    end)
    ForEachBarModule(function(module)
        module:SetHidden(false)
    end)
end

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

    ForEachBlizzardFrame(function(frame)
        if frame:IsShown() and not frame._ecmHidden then
            framesRemaining = framesRemaining + 1
        end
    end)
    ForEachBarModule(function(module)
        if module:GetFrameIfShown() then
            framesRemaining = framesRemaining + 1
        end
    end)

    if framesRemaining == 0 then
        _fadingToHidden = false
        HideAllFrames()
        if onComplete then
            onComplete()
        end
        return
    end

    local fadeInfo = {
        mode = "OUT",
        timeToFade = duration,
        endAlpha = 0,
        finishedFunc = onFrameFadeComplete,
    }

    ForEachBlizzardFrame(function(frame)
        if frame:IsShown() and not frame._ecmHidden then
            fadeInfo.startAlpha = frame:GetAlpha()
            UIFrameFade(frame, fadeInfo)
        end
    end)
    ForEachBarModule(function(module)
        local frame = module:GetFrameIfShown()
        if frame then
            fadeInfo.startAlpha = frame:GetAlpha()
            UIFrameFade(frame, fadeInfo)
        end
    end)
end

local function ApplyFadeFromHidden(duration, targetAlpha)
    ForEachBlizzardFrame(function(frame)
        if frame._ecmHidden then
            frame._ecmHidden = nil
            frame:SetAlpha(0)
            frame:Show()
        end
    end)
    ForEachBarModule(function(module, frame)
        if frame then
            frame:SetAlpha(0)
        end
        module:SetHidden(false)
    end)

    local fadeInfo = {
        mode = "IN",
        timeToFade = duration,
        startAlpha = 0,
        endAlpha = targetAlpha,
    }

    ForEachBlizzardFrame(function(frame)
        if frame:IsShown() then
            UIFrameFade(frame, fadeInfo)
        end
    end)
    ForEachBarModule(function(module)
        local frame = module:GetFrameIfShown()
        if frame then
            UIFrameFade(frame, fadeInfo)
        end
    end)
end

local function SetHidden(hidden, options)
    options = options or {}
    local reason = options.reason
    local duration = options.duration or 0

    if _fadingToHidden or _lastHiddenState ~= hidden then
        CancelAllFades()
    end

    if _lastHiddenState ~= hidden then
        Util.Log("ViewerHook", "SetHidden", {
            hidden = hidden,
            reason = reason,
            fadeOut = options.fadeOut,
            fadeIn = options.fadeIn,
            duration = duration,
        })
    end

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

        local _, targetAlpha = GetCombatFadeState()
        _lastFadeAlpha = targetAlpha

        if options.fadeIn and duration > 0 then
            ApplyFadeFromHidden(duration, targetAlpha)
        else
            ShowAllFrames()
            ForEachBlizzardFrame(function(frame)
                frame:SetAlpha(targetAlpha)
            end)
            ForEachBarModule(function(_, frame)
                if frame then
                    frame:SetAlpha(targetAlpha)
                end
            end)
        end
    end
end

--------------------------------------------------------------------------------
-- Layout Update
--------------------------------------------------------------------------------

local function UpdateLayoutInternal()
    if not _G["EssentialCooldownViewer"] then
        Util.Log("ViewerHook", "UpdateLayoutInternal skipped - no EssentialCooldownViewer")
        return
    end

    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden (cooldownViewerEnabled CVar disabled)")
        SetHidden(true, { reason = "cvar" })
        return
    end

    local profile = ECM.db and ECM.db.profile
    local hideWhenMounted = profile and profile.hideWhenMounted and IsMounted()
    local hideWhenRestingOutOfCombat = profile
        and profile.hideOutOfCombatInRestAreas
        and (not _inCombat)
        and IsResting()

    if hideWhenMounted then
        SetHidden(true, { reason = "mounted" })
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden", { mounted = true })
        return
    elseif hideWhenRestingOutOfCombat then
        SetHidden(true, { fadeOut = true, duration = REST_HIDE_FADE_DURATION, reason = "rest" })
        Util.Log("ViewerHook", "UpdateLayoutInternal - hidden", { restOutOfCombat = true })
        return
    elseif _lastHiddenState then
        local fadeDuration = 0
        local shouldFadeIn = false

        if _hideReason == "rest" then
            fadeDuration = _inCombat and COMBAT_FADE_DURATION or REST_HIDE_FADE_DURATION
            shouldFadeIn = true
        end

        SetHidden(false, { fadeIn = shouldFadeIn, duration = fadeDuration })
    end

    local registeredBarNames = {}
    for _, module in ipairs(_registeredBars) do
        if module and module.GetName then
            table.insert(registeredBarNames, module:GetName())
        else
            table.insert(registeredBarNames, tostring(module))
        end
    end

    Util.Log("ViewerHook", "UpdateLayoutInternal - triggering module layouts", { bars = registeredBarNames })

    for _, module in ipairs(_registeredBars) do
        module:UpdateLayout()
    end

    -- Update BuffBars after bar chain so it repositions when bars above it change
    local BuffBars = ECM.BuffBars
    if BuffBars and BuffBars.UpdateLayout then
        BuffBars:UpdateLayout()
    end

    ViewerHook:UpdateCombatFade()
end

--------------------------------------------------------------------------------
-- Event Configuration
--------------------------------------------------------------------------------

local EVENT_CONFIG = {
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    PLAYER_UPDATE_RESTING = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    PLAYER_LEVEL_UP = { delay = 1, resetBuffBars = true },
    PLAYER_ENTERING_WORLD = { delay = 0.4, resetBuffBars = true },
    PLAYER_TARGET_CHANGED = { delay = 0 },
    PLAYER_REGEN_ENABLED = { delay = 0.1, resetBuffBars = true, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = 0.1, resetBuffBars = true },
    ZONE_CHANGED = { delay = 0.1, resetBuffBars = true },
    ZONE_CHANGED_INDOORS = { delay = 0.1, resetBuffBars = true },
}

--------------------------------------------------------------------------------
-- Module Methods
--------------------------------------------------------------------------------

function ViewerHook:OnEvent(event, arg1)
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

    if config.combatChange then
        local wasInCombat = _inCombat
        _inCombat = (event == "PLAYER_REGEN_DISABLED")

        if wasInCombat ~= _inCombat then
            Util.Log("ViewerHook", "CombatStateChanged", { inCombat = _inCombat })
            if _inCombat then
                self:UpdateCombatFade()
            end
        end
    end

    local function doUpdate()
        if config.resetBuffBars then
            ECM.BuffBars:ResetStyledMarkers()
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

function ViewerHook:UpdateCombatFade()
    local profile = ECM.db and ECM.db.profile
    if not profile then
        return
    end

    if _lastHiddenState then
        _lastFadeAlpha = nil
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
    Util.Log("ViewerHook", "RegisterBar", { module = module:GetName() })
    for _, existing in ipairs(_registeredBars) do
        if existing == module then
            return
        end
    end
    table.insert(_registeredBars, module)
    ECM.ViewerHook:ScheduleLayoutUpdate(0.1)
end
