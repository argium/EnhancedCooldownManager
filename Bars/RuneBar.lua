-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class Frame
---@class StatusBar : Frame

---@class ECM_RuneBarFrame : Frame
---@field StatusBar StatusBar
---@field TicksFrame Frame
---@field FragmentedBars table
---@field _lastReadySet table|nil
---@field _displayOrder table|nil
---@field _maxResources number|nil
---@field _onUpdateAttached boolean|nil
---@field EnsureTicks fun(self: ECM_RuneBarFrame, count: number, parentFrame: Frame, poolKey: string|nil)
---@field LayoutResourceTicks fun(self: ECM_RuneBarFrame, maxResources: number, color: table|nil, tickWidth: number|nil, poolKey: string|nil)

local ADDON_NAME, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

-- Mixins
local BarFrame = ns.Mixins.BarFrame

local RuneBar = EnhancedCooldownManager:NewModule("RuneBar", "AceEvent-3.0")
EnhancedCooldownManager.RuneBar = RuneBar

--------------------------------------------------------------------------------
-- Domain Logic (DK rune-specific value/config handling)
--------------------------------------------------------------------------------

local function ShouldShowRuneBar()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.runeBar
    local _, class = UnitClass("player")
    return cfg and cfg.enabled and class == "DEATHKNIGHT"
end

--- Returns rune bar values.
---@param profile table
---@return number maxRunes
---@return number currentValue
---@return string kind
local function GetResourceValue(profile)
    local cfg = profile and profile.runeBar
    local maxRunes = (cfg and cfg.max)
    assert(maxRunes ~= nil, "Expected max config to be present.")
    assert(type(maxRunes) == "number", "Expected max to be a number.")

    local current = 0
    local now = GetTime()

    for i = 1, maxRunes do
        local start, duration, runeReady = GetRuneCooldown(i)
        if runeReady or not start or start == 0 or not duration or duration == 0 then
            current = current + 1
        else
            local elapsed = now - (tonumber(start) or now)
            local dur = tonumber(duration) or 0
            if dur > 0 then
                local pct = math.max(0, math.min(1, elapsed / dur))
                current = current + pct
            end
        end
    end

    return maxRunes, current, "runes"
end

--------------------------------------------------------------------------------
-- Fragmented Bars (DK Runes - individual bars per rune with recharge timers)
--------------------------------------------------------------------------------

--- Creates or returns fragmented sub-bars for runes.
---@param bar ECM_RuneBarFrame
---@param maxResources number
local function EnsureFragmentedBars(bar, maxResources)
    ---@cast bar ECM_RuneBarFrame
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.runeBar
    local gbl = profile and profile.global
    local tex = BarFrame.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))

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
---@param bar ECM_RuneBarFrame
---@param maxRunes number
local function UpdateFragmentedRuneDisplay(bar, maxRunes)
    ---@cast bar ECM_RuneBarFrame
    if not GetRuneCooldown then
        return
    end

    if not bar.FragmentedBars then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.runeBar

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    bar.StatusBar:SetAlpha(0)

    local r, g, b = cfg.color[1], cfg.color[2], cfg.color[3]
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

        local gbl = profile and profile.global
        local tex = BarFrame.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))

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
-- Frame Management (uses BarFrame mixin)
--------------------------------------------------------------------------------

--- Creates the rune bar frame.
---@return ECM_RuneBarFrame
function RuneBar:CreateFrame()
    Util.Log("RuneBar", "Creating frame")

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local frame = BarFrame.CreateFrame(self, { withTicks = true })

    frame.FragmentedBars = {}

    frame:SetAppearance()

    if not frame._onUpdateAttached then
        frame._onUpdateAttached = true
        frame:SetScript("OnUpdate", function()
            RuneBar:OnUpdateThrottled()
        end)
    end

    return frame
end


--------------------------------------------------------------------------------
-- Layout and Rendering
--------------------------------------------------------------------------------


--- Updates values: rune status and colors.
function RuneBar:Refresh()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.runeBar
    if self:IsHidden() or not (cfg and cfg.enabled) then
        return
    end

    if not ShouldShowRuneBar() then
        if self._frame then
            self._frame:Hide()
        end
        return
    end

    local bar = self._frame
    if not bar then
        return
    end

    if bar.RefreshAppearance then
        bar:RefreshAppearance()
    end

    local maxRunes = GetResourceValue(profile)
    if not maxRunes or maxRunes <= 0 then
        bar:Hide()
        return
    end

    if bar._maxResources ~= maxRunes then
        bar._maxResources = maxRunes
        bar._lastReadySet = nil
        bar._displayOrder = nil
    end

    bar.StatusBar:SetMinMaxValues(0, maxRunes)

    EnsureFragmentedBars(bar, maxRunes)

    local tickCount = math.max(0, maxRunes - 1)
    bar:EnsureTicks(tickCount, bar.TicksFrame, "ticks")

    UpdateFragmentedRuneDisplay(bar, maxRunes)
    bar:LayoutResourceTicks(maxRunes, { 0, 0, 0, 1 }, 1, "ticks")

    bar:Show()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function RuneBar:OnUpdateThrottled()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if self:IsHidden() or not (profile and profile.runeBar and profile.runeBar.enabled) then
        return
    end

    self:ThrottledRefresh()
end

function RuneBar:OnUnitPower(_, unit)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if unit ~= "player" or self:IsHidden() or not (profile and profile.runeBar and profile.runeBar.enabled) then
        return
    end

    self:OnUpdateThrottled()
end

function RuneBar:OnUnitEvent(_, unit)
    if unit == "player" then
        self:OnUpdateThrottled()
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function RuneBar:OnDisable()
    local frame = self._frame
    if frame and frame._onUpdateAttached then
        frame._onUpdateAttached = nil
        frame:SetScript("OnUpdate", nil)
    end
end

function RuneBar:OnEnable()
    BarFrame.AddMixin(
        RuneBar,
        "RuneBar",
        "runeBar",
        nil,
        {
            { event = "RUNE_POWER_UPDATE", handler = "OnUpdateThrottled" },
            { event = "RUNE_TYPE_UPDATE", handler = "OnUpdateThrottled" },
        }
    )
end
