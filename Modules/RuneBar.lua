-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local RuneBar = ns.Addon:NewModule("RuneBar")
local ClassUtil = ECM.ClassUtil
local C, FrameMixin = ECM.Constants, ECM.FrameMixin
ns.Addon.RuneBar = RuneBar

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

local function buildRuneStateTables(maxRunes, now)
    local readySet = {}
    local cdLookup = {}

    for i = 1, maxRunes do
        local isReady, remaining, frac = getRuneCooldownState(i, now)
        if isReady then
            readySet[i] = true
        else
            cdLookup[i] = { remaining = remaining, frac = frac }
        end
    end

    return readySet, cdLookup
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
    local specId = GetSpecialization()

    local specColor
    if cfg.useSpecColor then
        if specId == C.DEATHKNIGHT_FROST_SPEC_INDEX then
            specColor = cfg.colorFrost
        elseif specId == C.DEATHKNIGHT_UNHOLY_SPEC_INDEX then
            specColor = cfg.colorUnholy
        else
            specColor = cfg.colorBlood
        end
    end

    -- Blood is the default to match DK class color
    return specColor or cfg.color or ECM.Constants.COLOR_WHITE
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
    local readySet, cdLookup = buildRuneStateTables(maxRunes, now)
    local statesChanged = (bar._lastReadySet == nil) or runeReadyStatesDiffer(bar._lastReadySet, readySet, maxRunes)
    local dimensionsChanged = (bar._lastBarWidth ~= barWidth) or (bar._lastBarHeight ~= barHeight)

    if statesChanged or dimensionsChanged then
        bar._lastReadySet = readySet
        bar._lastBarWidth = barWidth
        bar._lastBarHeight = barHeight

        local readyList = {}
        local cdList = {}
        for i = 1, maxRunes do
            if readySet[i] then
                table.insert(readyList, i)
            else
                table.insert(cdList, { index = i, remaining = cdLookup[i] and cdLookup[i].remaining or math.huge })
            end
        end
        table.sort(cdList, function(a, b)
            return a.remaining < b.remaining
        end)

        bar._displayOrder = {}
        for _, idx in ipairs(readyList) do
            table.insert(bar._displayOrder, idx)
        end
        for _, v in ipairs(cdList) do
            table.insert(bar._displayOrder, v.index)
        end

        local texKey = (moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture)
        local tex = ECM.GetTexture(texKey)

        -- Use same positioning logic as BarMixin tick layout to avoid sub-pixel gaps
        local step = barWidth / maxRunes
        for pos, runeIndex in ipairs(bar._displayOrder) do
            local frag = bar.FragmentedBars[runeIndex]
            if frag then
                frag:SetStatusBarTexture(tex)
                frag:ClearAllPoints()
                local leftX = ECM.PixelSnap((pos - 1) * step)
                local rightX = ECM.PixelSnap(pos * step)
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
end

--- Lightweight per-frame rune value updater.
--- Only updates fill values and colors on existing fragment bars.
--- Triggers a full layout refresh when rune ready/CD states change.
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
    local readySet, cdLookup = buildRuneStateTables(maxRunes, now)

    -- Detect state transitions to trigger full reorder/reposition
    if runeReadyStatesDiffer(frame._lastReadySet, readySet, maxRunes) then
        -- A rune just finished or started CD — trigger full refresh for reorder/reposition
        self:ThrottledUpdateLayout("RuneStateChange")
        return
    end

    -- Fast path: only update fill values and colors, no repositioning
    for i = 1, maxRunes do
        local frag = frags[i]
        if frag then
            applyRuneFragmentVisual(frag, readySet[i], cdLookup[i], color)
        end
    end
end

function RuneBar:CreateFrame()
    -- Create base frame using FrameMixin (not BarMixin, since we manage StatusBar ourselves)
    local frame = ECM.FrameMixin.CreateFrame(self)

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

    ECM.Log(self.Name, "Frame created.")
    return frame
end

function RuneBar:ShouldShow()
    return ClassUtil.IsDeathKnight() and ECM.FrameMixin.ShouldShow(self)
end

function RuneBar:Refresh(why, force)
    if not FrameMixin.Refresh(self, why, force) then
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
    local tex = ECM.GetTexture(texKey)
    ensureFragmentedBars(frame, maxRunes, tex)

    local tickCount = math.max(0, maxRunes - 1)
    self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")

    updateFragmentedRuneDisplay(frame, maxRunes, cfg, globalConfig)
    self:LayoutResourceTicks(maxRunes, C.COLOR_BLACK, 1, "tickPool")

    frame:Show()
    ECM.Log(self.Name, "Refresh complete.")
    return true
end

function RuneBar:OnEnable()
    if not ClassUtil.IsDeathKnight() then
        return
    end

    ECM.BarMixin.AddMixin(self, "RuneBar")
    ECM.RegisterFrame(self)

    if self._valueTicker then
        self._valueTicker:Cancel()
    end
    self._valueTicker = C_Timer.NewTicker(C.DEFAULT_REFRESH_FREQUENCY, function()
        if self:IsEnabled() and self.InnerFrame and self.InnerFrame:IsShown() then
            updateRuneValues(self, self.InnerFrame)
        end
    end)
    self:RegisterEvent("RUNE_POWER_UPDATE", "OnRunePowerUpdate")
end

function RuneBar:OnRunePowerUpdate()
    self:ThrottledUpdateLayout("RUNE_POWER_UPDATE")
end

function RuneBar:OnDisable()
    self:UnregisterAllEvents()

    if self.InnerFrame then
        ECM.UnregisterFrame(self)
    end

    if self._valueTicker then
        self._valueTicker:Cancel()
        self._valueTicker = nil
    end
end
