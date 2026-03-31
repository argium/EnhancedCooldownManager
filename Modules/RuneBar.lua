-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local RuneBar = ns.Addon:NewModule("RuneBar")
local C = ns.Constants
local FrameUtil = ns.FrameUtil
ns.Addon.RuneBar = RuneBar

local SPEC_COLOR_KEY_BY_SPEC = {
    [C.DEATHKNIGHT_FROST_SPEC_INDEX] = "colorFrost",
    [C.DEATHKNIGHT_UNHOLY_SPEC_INDEX] = "colorUnholy",
    DEFAULT = "colorBlood",
}

local function getRuneCooldownState(index, now)
    local start, duration, runeReady = GetRuneCooldown(index)
    if runeReady or not start or start == 0 or not duration or duration == 0 then
        return true, nil, nil
    end

    local elapsed = now - start
    local remaining = math.max(0, duration - elapsed)
    local frac = math.max(0, math.min(1, elapsed / duration))
    return false, remaining, frac
end

local function buildRuneStateTables(maxRunes, now, readySet, cdLookup)
    wipe(readySet)
    wipe(cdLookup)

    for i = 1, maxRunes do
        local isReady, remaining, frac = getRuneCooldownState(i, now)
        if isReady then
            readySet[i] = true
        else
            cdLookup[i] = { remaining = remaining, frac = frac }
        end
    end
end

local function runeReadyStatesDiffer(lastReadySet, readySet, maxRunes)
    for i = 1, maxRunes do
        if (readySet[i] or false) ~= ((lastReadySet and lastReadySet[i]) or false) then
            return true
        end
    end
    return false
end

local function applyRuneFragmentVisual(frag, isReady, cd, color)
    if isReady then
        frag:SetValue(1)
        frag:SetStatusBarColor(color.r, color.g, color.b)
        return
    end

    frag:SetValue(cd and cd.frac or 0)
    frag:SetStatusBarColor(
        color.r * C.RUNEBAR_CD_DIM_FACTOR,
        color.g * C.RUNEBAR_CD_DIM_FACTOR,
        color.b * C.RUNEBAR_CD_DIM_FACTOR
    )
end

--- Creates or returns fragmented sub-bars for runes.
---@param bar Frame
---@param maxResources number
---@param tex string Texture path
local function ensureFragmentedBars(bar, maxResources, tex)
    for i = 1, maxResources do
        if not bar.FragmentedBars[i] then
            local frag = CreateFrame("StatusBar", nil, bar)
            frag:SetFrameLevel(bar:GetFrameLevel() + 1)
            frag:SetStatusBarTexture(tex)
            frag:SetMinMaxValues(0, 1)
            frag:SetValue(0)
            bar.FragmentedBars[i] = frag
        end
        bar.FragmentedBars[i]:Show()
    end

    for i = maxResources + 1, #bar.FragmentedBars do
        if bar.FragmentedBars[i] then
            bar.FragmentedBars[i]:Hide()
        end
    end
end

local function getColor(cfg)
    if cfg.useSpecColor then
        local specColorKey = SPEC_COLOR_KEY_BY_SPEC[GetSpecialization()] or SPEC_COLOR_KEY_BY_SPEC.DEFAULT
        local specColor = cfg[specColorKey]
        return specColor or cfg.color or C.COLOR_WHITE
    end

    return cfg.color or C.COLOR_WHITE
end

--- Updates fragmented rune display (individual bars per rune).
--- Only repositions bars when rune ready states change to avoid flickering.
---@param bar Frame
---@param maxRunes number
---@param moduleConfig table
---@param globalConfig table
local function updateFragmentedRuneDisplay(bar, maxRunes, moduleConfig, globalConfig)
    if not GetRuneCooldown then
        return
    end

    if not bar.FragmentedBars then
        return
    end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local now = GetTime()
    local color = getColor(moduleConfig)

    -- Reuse per-bar tables to avoid per-call allocation
    bar._readySet = bar._readySet or {}
    bar._cdLookup = bar._cdLookup or {}
    local readySet, cdLookup = bar._readySet, bar._cdLookup
    buildRuneStateTables(maxRunes, now, readySet, cdLookup)

    local statesChanged = (bar._lastReadySet == nil) or runeReadyStatesDiffer(bar._lastReadySet, readySet, maxRunes)
    local dimensionsChanged = (bar._lastBarWidth ~= barWidth) or (bar._lastBarHeight ~= barHeight)

    if statesChanged or dimensionsChanged then
        -- Snapshot ready state for next comparison
        bar._lastReadySet = bar._lastReadySet or {}
        wipe(bar._lastReadySet)
        for i = 1, maxRunes do
            bar._lastReadySet[i] = readySet[i]
        end
        bar._lastBarWidth = barWidth
        bar._lastBarHeight = barHeight

        -- Build display order: ready runes first, then cooldown runes sorted by remaining
        bar._displayOrder = bar._displayOrder or {}
        wipe(bar._displayOrder)
        local orderLen = 0

        -- Collect cooldown runes and sort by remaining time
        bar._cdSortBuf = bar._cdSortBuf or {}
        wipe(bar._cdSortBuf)
        local cdLen = 0
        for i = 1, maxRunes do
            if readySet[i] then
                orderLen = orderLen + 1
                bar._displayOrder[orderLen] = i
            else
                cdLen = cdLen + 1
                bar._cdSortBuf[cdLen] = i
            end
        end
        table.sort(bar._cdSortBuf, function(a, b)
            local ra = cdLookup[a] and cdLookup[a].remaining or math.huge
            local rb = cdLookup[b] and cdLookup[b].remaining or math.huge
            return ra < rb
        end)
        for j = 1, cdLen do
            orderLen = orderLen + 1
            bar._displayOrder[orderLen] = bar._cdSortBuf[j]
        end

        local texKey = (moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture)
        local tex = FrameUtil.GetTexture(texKey)

        -- Use same positioning logic as BarMixin tick layout to avoid sub-pixel gaps
        local step = barWidth / maxRunes
        for pos, runeIndex in ipairs(bar._displayOrder) do
            local frag = bar.FragmentedBars[runeIndex]
            if frag then
                frag:SetStatusBarTexture(tex)
                frag:ClearAllPoints()
                local leftX = FrameUtil.PixelSnap((pos - 1) * step)
                local rightX = FrameUtil.PixelSnap(pos * step)
                local w = rightX - leftX
                frag:SetSize(w, barHeight)
                frag:SetPoint("LEFT", bar, "LEFT", leftX, 0)
                frag:SetMinMaxValues(0, 1)
                frag:Show()
            end
        end
    end

    for i = 1, maxRunes do
        local frag = bar.FragmentedBars[i]
        if frag then
            applyRuneFragmentVisual(frag, readySet[i], cdLookup[i], color)
        end
    end

    return next(cdLookup) ~= nil
end

--- Lightweight per-frame rune value updater.
--- Only updates fill values and colors on existing fragment bars.
--- Triggers a full layout refresh when rune ready/CD states change.
--- Self-stops the animation ticker when all runes are ready.
---@param self RuneBar
---@param frame Frame
local function updateRuneValues(self, frame)
    local frags = frame.FragmentedBars
    if not frags then
        return
    end

    local maxRunes = frame._maxResources
    if not maxRunes or maxRunes <= 0 then
        return
    end

    -- Throttle to updateFrequency to match existing refresh cadence
    local now = GetTime()
    local globalConfig = self:GetGlobalConfig()
    local freq = (globalConfig and globalConfig.updateFrequency) or C.DEFAULT_REFRESH_FREQUENCY
    if frame._lastValueUpdate and (now - frame._lastValueUpdate) < freq then
        return
    end
    frame._lastValueUpdate = now

    local cfg = self:GetModuleConfig()
    local color = getColor(cfg)

    frame._readySet = frame._readySet or {}
    frame._cdLookup = frame._cdLookup or {}
    local readySet, cdLookup = frame._readySet, frame._cdLookup
    buildRuneStateTables(maxRunes, now, readySet, cdLookup)

    -- Detect state transitions to trigger full reorder/reposition
    if runeReadyStatesDiffer(frame._lastReadySet, readySet, maxRunes) then
        -- A rune just finished or started CD — trigger full refresh for reorder/reposition
        ns.Runtime.RequestLayout("RuneBar:RuneStateChange")
        return
    end

    -- Fast path: only update fill values and colors, no repositioning
    for i = 1, maxRunes do
        local frag = frags[i]
        if frag then
            applyRuneFragmentVisual(frag, readySet[i], cdLookup[i], color)
        end
    end

    -- Stop the animation ticker when all runes are ready
    if next(cdLookup) == nil then
        self:_StopAnimationTicker()
    end
end

function RuneBar:CreateFrame()
    -- Create base frame using FrameProto (not BarProto, since we manage StatusBar ourselves)
    local frame = ns.BarMixin.FrameProto.CreateFrame(self)

    -- Add StatusBar for value display (but we'll use fragmented bars)
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints()
    frame.StatusBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- TicksFrame for tick marks
    frame.TicksFrame = CreateFrame("Frame", nil, frame)
    frame.TicksFrame:SetAllPoints(frame)
    frame.TicksFrame:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- FragmentedBars for individual rune display
    frame.FragmentedBars = {}

    ns.Log(self.Name, "Frame created.")
    return frame
end

function RuneBar:ShouldShow()
    return ns.IsDeathKnight() and ns.BarMixin.FrameProto.ShouldShow(self)
end

function RuneBar:Refresh(why, force)
    if not ns.BarMixin.FrameProto.Refresh(self, why, force) then
        return false
    end

    local cfg = self:GetModuleConfig()
    local globalConfig = self:GetGlobalConfig()
    local frame = self.InnerFrame
    local maxRunes = C.RUNEBAR_MAX_RUNES

    if frame._maxResources ~= maxRunes then
        frame._maxResources = maxRunes
        frame._lastReadySet = nil
        frame._displayOrder = nil
    end

    frame.StatusBar:SetMinMaxValues(0, maxRunes)

    local texKey = (cfg and cfg.texture) or (globalConfig and globalConfig.texture)
    local tex = FrameUtil.GetTexture(texKey)
    ensureFragmentedBars(frame, maxRunes, tex)

    local tickCount = math.max(0, maxRunes - 1)
    self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")

    updateFragmentedRuneDisplay(frame, maxRunes, cfg, globalConfig)
    self:LayoutResourceTicks(maxRunes, C.COLOR_BLACK, 1, "tickPool")

    -- Start animation ticker if any rune is on cooldown (derived from layout pass)
    if frame._cdLookup and next(frame._cdLookup) ~= nil then
        self:_StartAnimationTicker()
    end

    frame:Show()
    ns.Log(self.Name, "Refresh complete.")
    return true
end

--- Starts the cooldown animation ticker if not already running.
function RuneBar:_StartAnimationTicker()
    if self._valueTicker then
        return
    end
    self._valueTicker = C_Timer.NewTicker(C.DEFAULT_REFRESH_FREQUENCY, function()
        if self:IsEnabled() and self.InnerFrame and self.InnerFrame:IsShown() then
            updateRuneValues(self, self.InnerFrame)
        end
    end)
end

--- Stops the cooldown animation ticker.
function RuneBar:_StopAnimationTicker()
    if self._valueTicker then
        self._valueTicker:Cancel()
        self._valueTicker = nil
    end
end

function RuneBar:OnInitialize()
    ns.BarMixin.AddBarMixin(self, "RuneBar")
end

function RuneBar:OnEnable()
    if not ns.IsDeathKnight() then
        return
    end

    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)

    self:RegisterEvent("RUNE_POWER_UPDATE", function(_, ...) self:OnRunePowerUpdate(...) end)
end

function RuneBar:OnRunePowerUpdate()
    self:_StartAnimationTicker()
    ns.Runtime.RequestLayout("RuneBar:RUNE_POWER_UPDATE")
end

function RuneBar:OnDisable()
    self:UnregisterAllEvents()

    if self.InnerFrame then
        ns.Runtime.UnregisterFrame(self)
    end

    self:_StopAnimationTicker()
end
