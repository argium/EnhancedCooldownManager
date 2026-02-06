-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local Util = ns.Util
local C = ns.Constants

local BarFrame = ns.Mixins.BarFrame
local ECMFrame = ns.Mixins.ECMFrame

local RuneBar = ECM:NewModule("RuneBar", "AceEvent-3.0")
ECM.RuneBar = RuneBar

--------------------------------------------------------------------------------
-- Fragmented Bars (DK Runes - individual bars per rune with recharge timers)
--------------------------------------------------------------------------------

--- Creates or returns fragmented sub-bars for runes.
---@param bar Frame
---@param maxResources number
---@param moduleConfig table
---@param globalConfig table
local function EnsureFragmentedBars(bar, maxResources, moduleConfig, globalConfig)
    -- Get texture
    local texKey = (moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture)
    local tex = Util.GetTexture(texKey)

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
        local tex = Util.GetTexture(texKey)

        -- Use same positioning logic as BarFrame tick layout to avoid sub-pixel gaps
        local step = barWidth / maxRunes
        for pos, runeIndex in ipairs(bar._displayOrder) do
            local frag = bar.FragmentedBars[runeIndex]
            if frag then
                frag:SetStatusBarTexture(tex)
                frag:ClearAllPoints()
                local leftX = Util.PixelSnap((pos - 1) * step)
                local rightX = Util.PixelSnap(pos * step)
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
                frag:SetValue(cd and cd.frac or 0)
                frag:SetStatusBarColor(r * 0.5, g * 0.5, b * 0.5)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- ECMFrame/BarFrame Overrides
--------------------------------------------------------------------------------

function RuneBar:CreateFrame()
    -- Create base frame using ECMFrame (not BarFrame, since we manage StatusBar ourselves)
    local frame = ECMFrame.CreateFrame(self)

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

    -- Attach OnUpdate script for continuous rune updates
    frame:SetScript("OnUpdate", function()
        self:ThrottledRefresh()
    end)

    ECM.Log(self.Name, "RuneBar:CreateFrame", "Success")
    return frame
end

function RuneBar:ShouldShow()
    local config = self.ModuleConfig
    local _, class = UnitClass("player")
    return ECMFrame.ShouldShow(self) and class == "DEATHKNIGHT"
end

function RuneBar:Refresh(force)
    local _, class = UnitClass("player")
    assert(class == "DEATHKNIGHT", "RuneBar should only be enabled for Death Knights")

    -- Use ECMFrame.Refresh instead of BarFrame.Refresh since we manage
    -- our own fragmented bars and don't use the standard StatusBar
    local continue = ECMFrame.Refresh(self, force)
    if not continue then
        Util.Log(self.Name, "RuneBar:Refresh", "Skipping refresh")
        return false
    end

    local cfg = self.ModuleConfig
    local globalConfig = self.GlobalConfig
    local frame = self.InnerFrame

    local maxRunes = C.RUNEBAR_MAX_RUNES
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
    Util.Log(self.Name, "RuneBar:Refresh", {
        maxRunes = maxRunes,
    })
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function RuneBar:OnEnable()
    local _, class = UnitClass("player")
    if class ~= "DEATHKNIGHT" then
        return
    end

    if not self.IsECMFrame then
        BarFrame.AddMixin(self, "RuneBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end
    self:RegisterEvent("RUNE_POWER_UPDATE", "ThrottledRefresh")
end

function RuneBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsECMFrame and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end

    local frame = self.InnerFrame
    if frame then
        frame:SetScript("OnUpdate", nil)
    end
end
