-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local FrameUtil = ECM.FrameUtil
local RuneBar = mod:NewModule("RuneBar", "AceEvent-3.0")
mod.RuneBar = RuneBar
ECM.BarMixin.ApplyConfigMixin(RuneBar, "RuneBar")

--- Creates or returns fragmented sub-bars for runes.
---@param bar Frame
---@param maxResources number
---@param moduleConfig table
---@param globalConfig table
local function EnsureFragmentedBars(bar, maxResources, moduleConfig, globalConfig)
    -- Get texture
    local texKey = (moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture)
    local tex = ECM_GetTexture(texKey)

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

--- Updates fragmented rune display (individual bars per rune).
--- Only repositions bars when rune ready states change to avoid flickering.
---@param bar Frame
---@param maxRunes number
---@param moduleConfig table
---@param globalConfig table
local function UpdateFragmentedRuneDisplay(bar, maxRunes, moduleConfig, globalConfig)
    if not GetRuneCooldown then
        return
    end

    if not bar.FragmentedBars then
        return
    end

    local cfg = moduleConfig

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local r, g, b = cfg.color.r, cfg.color.g, cfg.color.b
    local readySet = {}
    local cdLookup = {}
    local now = GetTime()

    for i = 1, maxRunes do
        local start, duration, runeReady = GetRuneCooldown(i)
        if runeReady or not start or start == 0 or not duration or duration == 0 then
            readySet[i] = true
        else
            local elapsed = now - start
            local remaining = math.max(0, duration - elapsed)
            local frac = math.max(0, math.min(1, elapsed / duration))
            cdLookup[i] = { remaining = remaining, frac = frac }
        end
    end

    local statesChanged = not bar._lastReadySet
    if not statesChanged then
        for i = 1, maxRunes do
            if (readySet[i] or false) ~= (bar._lastReadySet[i] or false) then
                statesChanged = true
                break
            end
        end
    end

    if statesChanged then
        bar._lastReadySet = readySet

        local readyList = {}
        local cdList = {}
        for i = 1, maxRunes do
            if readySet[i] then
                table.insert(readyList, i)
            else
                table.insert(cdList, { index = i, remaining = cdLookup[i] and cdLookup[i].remaining or math.huge })
            end
        end
        table.sort(cdList, function(a, b) return a.remaining < b.remaining end)

        bar._displayOrder = {}
        for _, idx in ipairs(readyList) do
            table.insert(bar._displayOrder, idx)
        end
        for _, v in ipairs(cdList) do
            table.insert(bar._displayOrder, v.index)
        end

        local texKey = (cfg and cfg.texture) or (globalConfig and globalConfig.texture)
        local tex = ECM_GetTexture(texKey)

        -- Use same positioning logic as BarMixin tick layout to avoid sub-pixel gaps
        local step = barWidth / maxRunes
        for pos, runeIndex in ipairs(bar._displayOrder) do
            local frag = bar.FragmentedBars[runeIndex]
            if frag then
                frag:SetStatusBarTexture(tex)
                frag:ClearAllPoints()
                local leftX = ECM_PixelSnap((pos - 1) * step)
                local rightX = ECM_PixelSnap(pos * step)
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
            if readySet[i] then
                frag:SetValue(1)
                frag:SetStatusBarColor(r, g, b)
            else
                local cd = cdLookup[i]
                local dim = ECM.Constants.RUNEBAR_CD_DIM_FACTOR
                frag:SetValue(cd and cd.frac or 0)
                frag:SetStatusBarColor(r * dim, g * dim, b * dim)
            end
        end
    end
end

--- Lightweight per-frame rune value updater.
--- Only updates fill values and colors on existing fragment bars.
--- Triggers a full layout refresh when rune ready/CD states change.
---@param self RuneBar
---@param frame Frame
local function UpdateRuneValues(self, frame)
    if not GetRuneCooldown then
        return
    end

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
    local freq = (globalConfig and globalConfig.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
    if frame._lastValueUpdate and (now - frame._lastValueUpdate) < freq then
        return
    end
    frame._lastValueUpdate = now

    local cfg = self:GetModuleConfig()
    local r, g, b = cfg.color.r, cfg.color.g, cfg.color.b

    -- Detect state transitions to trigger full reorder/reposition
    local stateChanged = false
    for i = 1, maxRunes do
        local start, duration, runeReady = GetRuneCooldown(i)
        local isReady = runeReady or not start or start == 0 or not duration or duration == 0
        local wasReady = frame._lastReadySet and frame._lastReadySet[i]

        if (isReady and true or false) ~= (wasReady and true or false) then
            stateChanged = true
            break
        end
    end

    if stateChanged then
        -- A rune just finished or started CD — trigger full refresh for reorder/reposition
        self:ThrottledUpdateLayout("RuneStateChange")
        return
    end

    -- Fast path: only update fill values and colors, no repositioning
    for i = 1, maxRunes do
        local frag = frags[i]
        if frag then
            local start, duration, runeReady = GetRuneCooldown(i)
            if runeReady or not start or start == 0 or not duration or duration == 0 then
                frag:SetValue(1)
                frag:SetStatusBarColor(r, g, b)
            else
                local elapsed = now - start
                local dim = ECM.Constants.RUNEBAR_CD_DIM_FACTOR
                local frac = math.max(0, math.min(1, elapsed / duration))
                frag:SetValue(frac)
                frag:SetStatusBarColor(r * dim, g * dim, b * dim)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ModuleMixin/BarMixin Overrides
--------------------------------------------------------------------------------

function RuneBar:CreateFrame()
    -- Create base frame using ModuleMixin (not BarMixin, since we manage StatusBar ourselves)
    local frame = ECM.ModuleMixin.CreateFrame(self)

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

    ECM_log(ECM.Constants.SYS.Layout, self.Name, "Frame created.")
    return frame
end

function RuneBar:ShouldShow()
    local _, class = UnitClass("player")
    return ECM.ModuleMixin.ShouldShow(self) and class == "DEATHKNIGHT"
end

function RuneBar:Refresh(why, force)
    local _, class = UnitClass("player")
    assert(class == "DEATHKNIGHT", "RuneBar should only be enabled for Death Knights")

    -- Use BaseRefresh instead of BarMixin.Refresh since we manage
    -- our own fragmented bars and don't use the standard StatusBar
    if not FrameUtil.BaseRefresh(self, why, force) then
        return false
    end

    local cfg = self:GetModuleConfig()
    local globalConfig = self:GetGlobalConfig()
    local frame = self.InnerFrame

    local maxRunes = ECM.Constants.RUNEBAR_MAX_RUNES
    if not maxRunes or maxRunes <= 0 then
        frame:Hide()
        return
    end

    if frame._maxResources ~= maxRunes then
        frame._maxResources = maxRunes
        frame._lastReadySet = nil
        frame._displayOrder = nil
    end

    frame.StatusBar:SetMinMaxValues(0, maxRunes)

    EnsureFragmentedBars(frame, maxRunes, cfg, globalConfig)

    local tickCount = math.max(0, maxRunes - 1)
    self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")

    UpdateFragmentedRuneDisplay(frame, maxRunes, cfg, globalConfig)
    self:LayoutResourceTicks(maxRunes, { r = 0, g = 0, b = 0, a = 1 }, 1, "tickPool")

    frame:Show()
    ECM_log(ECM.Constants.SYS.Styling, self.Name, "Refresh complete.")
    return true
end

function RuneBar:OnEvent(event)
    self:ThrottledUpdateLayout(event, { secondPass = true })
end

function RuneBar:OnEnable()
    if not self.IsModuleMixin then
        ECM.BarMixin.AddMixin(self, "RuneBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then
        return
    end

    -- DK-only: lightweight per-frame rune value updates and power events
    if self.InnerFrame then
        self.InnerFrame:SetScript("OnUpdate", function()
            UpdateRuneValues(self, self.InnerFrame)
        end)
    end
    self:RegisterEvent("RUNE_POWER_UPDATE", "OnRunePowerUpdate")
end

function RuneBar:OnRunePowerUpdate()
    self:ThrottledUpdateLayout("RUNE_POWER_UPDATE")
end

function RuneBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsModuleMixin and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end

    local frame = self.InnerFrame
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
end
