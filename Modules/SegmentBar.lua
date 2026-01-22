local ADDON_NAME, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

-- Mixins
local BarFrame = ns.Mixins.BarFrame
local Lifecycle = ns.Mixins.Lifecycle
local TickRenderer = ns.Mixins.TickRenderer

local SegmentBar = EnhancedCooldownManager:NewModule("SegmentBar", "AceEvent-3.0")
EnhancedCooldownManager.SegmentBar = SegmentBar

--------------------------------------------------------------------------------
-- Domain Logic (module-specific value/config handling)
--------------------------------------------------------------------------------

-- Discrete power types that should be shown as segments
local discretePowerTypes = {
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Essence] = true,
}

--- Returns fractional rune progress (ready + partial recharge).
---@param maxRunes number
---@return number
local function GetDkRuneProgressValue(maxRunes)
    maxRunes = tonumber(maxRunes) or 6
    if not GetRuneCooldown then
        return 0
    end

    local sum = 0
    local now = GetTime()

    for i = 1, maxRunes do
        local start, duration, runeReady = GetRuneCooldown(i)
        if runeReady or (not start or start == 0) or (not duration or duration == 0) then
            sum = sum + 1
        else
            local elapsed = now - (tonumber(start) or now)
            local dur = tonumber(duration) or 0
            if dur > 0 then
                local pct = math.max(0, math.min(1, elapsed / dur))
                sum = sum + pct
            end
        end
    end

    return sum
end

--- Returns the discrete power type for the current player, if any.
---@return Enum.PowerType|nil powerType
local function GetDiscretePowerType()
    local _, class = UnitClass("player")

    for powerType in pairs(discretePowerTypes) do
        local max = UnitPowerMax("player", powerType)
        if max and max > 0 then
            if class == "DRUID" then
                local formIndex = GetShapeshiftForm()
                if formIndex == 2 then
                    return powerType
                end
            else
                return powerType
            end
        end
    end
    return nil
end

local function ShouldShowSegmentBar()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile or profile.enabled == false then
        return false
    end

    local cfg = profile.segmentBar
    if not (cfg and cfg.enabled) then
        return false
    end

    local _, class = UnitClass("player")

    if class == "DEATHKNIGHT" or class == "DEMONHUNTER" then
        return true
    end

    local discretePower = GetDiscretePowerType()
    Util.Log("SegmentBar", "ShouldShowSegmentBar - discrete power fallback", { discretePower = discretePower })
    return discretePower ~= nil
end

--- Returns segment bar values based on class/power type.
---@param profile table
---@return number|nil maxSegments
---@return number|nil currentValue
---@return Enum.PowerType|string|nil kind
local function GetSegmentBarValues(profile)
    local cfg = profile and profile.segmentBar
    local _, class = UnitClass("player")

    -- Special: DK Runes (has partial recharge display)
    if class == "DEATHKNIGHT" then
        local maxRunes = (cfg and cfg.deathKnightRunesMax) or 6
        local v = GetDkRuneProgressValue(maxRunes)
        return maxRunes, v, "runes"
    end

    -- Special: DH Souls (aura-based stacks)
    if class == "DEMONHUNTER" then
        if GetSpecialization() == 3 then
            local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", 1225789)
            local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", 1227702)
            if collapsingStar then
                return 6, collapsingStar.applications / 5, "souls"
            end
            if voidFragments then
                return 7, voidFragments.applications / 5, "souls"
            end
            return nil, nil, nil
        else
            local maxSouls = (cfg and cfg.demonHunterSoulsMax) or 5
            local count = C_Spell.GetSpellCastCount(247454) or 0
            return maxSouls, count, "souls"
        end
    end

    -- Generic discrete power types
    local powerType = GetDiscretePowerType()
    if powerType then
        local max = UnitPowerMax("player", powerType) or 0
        local current = UnitPower("player", powerType) or 0
        return max, current, powerType
    end

    return nil, nil, nil
end

--- Extracts RGB from a color table or returns fallback.
local function ExtractColor(c, fallbackR, fallbackG, fallbackB)
    if type(c) == "table" then
        return c[1] or 1, c[2] or 1, c[3] or 1
    end
    return fallbackR or 1, fallbackG or 1, fallbackB or 1
end

--- Returns the color for the segment bar based on kind (string or power type).
---@param profile table
---@param kind string|Enum.PowerType
---@return number r, number g, number b
local function GetSegmentBarColor(profile, kind)
    local cfg = profile and profile.segmentBar

    local kindColors = {
        souls = { cfg and cfg.colorDemonHunterSouls, 0.64, 0.19, 0.79 },
        runes = { cfg and cfg.colorDkRunes, 0.78, 0.10, 0.22 },
    }

    local kindEntry = kindColors[kind]
    if kindEntry then
        return ExtractColor(kindEntry[1], kindEntry[2], kindEntry[3], kindEntry[4])
    end

    if kind == Enum.PowerType.ComboPoints and cfg and cfg.colorComboPoints then
        return ExtractColor(cfg.colorComboPoints)
    end

    if type(kind) == "number" then
        local c = profile.powerTypeColors and profile.powerTypeColors.colors and profile.powerTypeColors.colors[kind]
        if c then
            return ExtractColor(c)
        end
    end

    return 1, 1, 1
end

--------------------------------------------------------------------------------
-- Fragmented Bars (DK Runes - module-specific, too specialized for mixin)
--------------------------------------------------------------------------------

--- Creates or returns fragmented sub-bars for runes.
---@param bar ECM_SegmentBarFrame
---@param maxSegments number
local function EnsureFragmentedBars(bar, maxSegments)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.segmentBar
    local gbl = profile and profile.global
    local tex = Util.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))

    for i = 1, maxSegments do
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

    for i = maxSegments + 1, #bar.FragmentedBars do
        if bar.FragmentedBars[i] then
            bar.FragmentedBars[i]:Hide()
        end
    end
end

--- Updates fragmented rune display (individual bars per rune).
--- Only repositions bars when rune ready states change to avoid flickering.
---@param bar ECM_SegmentBarFrame
---@param maxRunes number
local function UpdateFragmentedRuneDisplay(bar, maxRunes)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    bar.StatusBar:SetAlpha(0)

    local r, g, b = GetSegmentBarColor(profile, "runes")

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

        local cfg = profile and profile.segmentBar
        local gbl = profile and profile.global
        local tex = Util.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))
        local baseWidth = math.floor(barWidth / maxRunes)
        local remainingWidth = barWidth - (baseWidth * maxRunes)

        for pos, runeIndex in ipairs(bar._displayOrder) do
            local frag = bar.FragmentedBars[runeIndex]
            if frag then
                frag:SetStatusBarTexture(tex)
                frag:ClearAllPoints()
                local x = (pos - 1) * baseWidth
                local w = (pos == maxRunes) and (baseWidth + remainingWidth) or baseWidth
                frag:SetSize(w, barHeight)
                frag:SetPoint("LEFT", bar, "LEFT", x, 0)
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

--- Returns the base viewer anchor frame.
---@return Frame|nil
function SegmentBar:GetViewerAnchor()
    return Util.GetViewerAnchor()
end

--- Computes the preferred anchor for SegmentBar.
---@return Frame anchor
---@return boolean isFirstBar
function SegmentBar:GetPreferredAnchor()
    return Util.GetPreferredAnchor(EnhancedCooldownManager, "SegmentBar")
end

--- Returns or creates the segment bar frame.
---@return ECM_SegmentBarFrame
function SegmentBar:GetFrame()
    if self._frame then
        return self._frame
    end

    Util.Log("SegmentBar", "Creating frame")

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile

    -- Create base bar with Background + StatusBar
    self._frame = BarFrame.Create(
        ADDON_NAME .. "SegmentBar",
        UIParent,
        Util.DEFAULT_SEGMENT_BAR_HEIGHT
    )

    -- Add ticks frame for segment dividers
    BarFrame.AddTicksFrame(self._frame)

    -- Initialize fragmented bars container
    self._frame.FragmentedBars = {}

    -- Apply initial appearance
    BarFrame.ApplyAppearance(self._frame, profile and profile.segmentBar, profile)

    return self._frame
end

--- Marks the segment bar as externally hidden.
---@param hidden boolean
function SegmentBar:SetExternallyHidden(hidden)
    Lifecycle.SetExternallyHidden(self, hidden, "SegmentBar")
end

--- Returns the frame only if currently shown.
---@return ECM_SegmentBarFrame|nil
function SegmentBar:GetFrameIfShown()
    return Lifecycle.GetFrameIfShown(self)
end

--------------------------------------------------------------------------------
-- Layout and Rendering
--------------------------------------------------------------------------------

--- Updates layout: positioning, sizing, anchoring, appearance.
function SegmentBar:UpdateLayout()
    local result = Lifecycle.CheckLayoutPreconditions(self, "segmentBar", ShouldShowSegmentBar, "SegmentBar")
    if not result then
        Util.Log("SegmentBar", "UpdateLayout - preconditions failed")
        return
    end

    Util.Log("SegmentBar", "UpdateLayout - preconditions passed")

    self:Enable()

    local profile, cfg = result.profile, result.cfg
    local bar = self:GetFrame()
    local anchor, isFirstBar = self:GetPreferredAnchor()
    local viewer = Util.GetViewerAnchor() or UIParent

    local desiredHeight = Util.GetBarHeight(cfg, profile, Util.DEFAULT_SEGMENT_BAR_HEIGHT)
    local desiredOffsetY = isFirstBar and anchor == viewer
        and -Util.GetTopGapOffset(cfg, profile)
        or 0
    local widthCfg = profile.width or {}
    local desiredWidth = widthCfg.value or 330
    local matchAnchorWidth = widthCfg.auto ~= false

    Util.ApplyLayoutIfChanged(bar, anchor, desiredOffsetY, desiredHeight, desiredWidth, matchAnchorWidth)

    -- Update appearance (background, texture)
    local tex = BarFrame.ApplyAppearance(bar, cfg, profile)
    bar._lastTexture = tex

    -- Get segment info
    local maxSegments, currentValue, kind = GetSegmentBarValues(profile)
    Util.Log("SegmentBar", "UpdateLayout - GetSegmentBarValues", {
        maxSegments = maxSegments,
        currentValue = currentValue,
        kind = kind
    })
    if not maxSegments or maxSegments <= 0 then
        Util.Log("SegmentBar", "UpdateLayout - hiding (no segments)")
        bar:Hide()
        return
    end

    bar._maxSegments = maxSegments
    bar.StatusBar:SetMinMaxValues(0, maxSegments)

    -- Set up fragmented bars for runes
    if kind == "runes" then
        EnsureFragmentedBars(bar, maxSegments)
        bar._lastReadySet = nil
        bar._displayOrder = nil
    else
        for _, frag in ipairs(bar.FragmentedBars) do
            frag:Hide()
        end
        bar.StatusBar:SetAlpha(1)
    end

    -- Set up ticks using TickRenderer
    local tickCount = math.max(0, maxSegments - 1)
    TickRenderer.EnsureTicks(bar, tickCount, bar.TicksFrame, "ticks")

    Util.Log("SegmentBar", "UpdateLayout complete", {
        anchorName = anchor.GetName and anchor:GetName() or "unknown",
        height = desiredHeight,
        maxSegments = maxSegments,
        kind = tostring(kind)
    })

    bar:Show()
    TickRenderer.LayoutSegmentTicks(bar, maxSegments, { 0, 0, 0, 1 }, 1, "ticks")

    -- Set up OnUpdate for DK runes
    if kind == "runes" then
        if not bar._onUpdateAttached then
            bar._onUpdateAttached = true
            bar:SetScript("OnUpdate", function()
                SegmentBar:OnUpdateThrottled()
            end)
        end
    else
        if bar._onUpdateAttached then
            bar._onUpdateAttached = nil
            bar:SetScript("OnUpdate", nil)
        end
    end

    self:Refresh()
end

--- Updates values: status bar value, colors.
function SegmentBar:Refresh()
    if self._externallyHidden then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not (profile and profile.segmentBar and profile.segmentBar.enabled) then
        return
    end

    if not ShouldShowSegmentBar() then
        return
    end

    local bar = self._frame
    if not bar then
        return
    end

    local maxSegments, currentValue, kind = GetSegmentBarValues(profile)
    if not maxSegments or maxSegments <= 0 then
        return
    end

    if kind == "runes" then
        UpdateFragmentedRuneDisplay(bar, maxSegments)
    else
        bar.StatusBar:SetValue(currentValue or 0)
        local r, g, b = GetSegmentBarColor(profile, kind)
        bar.StatusBar:SetStatusBarColor(r, g, b)
    end

    TickRenderer.LayoutSegmentTicks(bar, maxSegments, { 0, 0, 0, 1 }, 1, "ticks")
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function SegmentBar:OnUpdateThrottled()
    if self._externallyHidden then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not (profile and profile.segmentBar and profile.segmentBar.enabled) then
        return
    end

    Lifecycle.ThrottledRefresh(self, profile, function(mod)
        mod:Refresh()
    end)
end

function SegmentBar:OnUnitEvent(event, unit)
    if unit == "player" then
        self:OnUpdateThrottled()
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

local LAYOUT_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_ENTERING_WORLD",
    "UPDATE_SHAPESHIFT_FORM",
}

local REFRESH_EVENTS = {
    { event = "RUNE_POWER_UPDATE", handler = "OnUpdateThrottled" },
    { event = "RUNE_TYPE_UPDATE", handler = "OnUpdateThrottled" },
    { event = "UNIT_POWER_UPDATE", handler = "OnUnitEvent" },
    { event = "UNIT_AURA", handler = "OnUnitEvent" },
}

local REFRESH_EVENT_NAMES = {
    "RUNE_POWER_UPDATE",
    "RUNE_TYPE_UPDATE",
    "UNIT_POWER_UPDATE",
    "UNIT_AURA",
}

function SegmentBar:Enable()
    Lifecycle.Enable(self, "SegmentBar", REFRESH_EVENTS)
end

function SegmentBar:Disable()
    if self._frame then
        if self._frame._onUpdateAttached then
            self._frame._onUpdateAttached = nil
            self._frame:SetScript("OnUpdate", nil)
        end
    end

    Lifecycle.Disable(self, "SegmentBar", REFRESH_EVENT_NAMES)
end

function SegmentBar:OnEnable()
    Lifecycle.OnEnable(self, "SegmentBar", LAYOUT_EVENTS)
end

function SegmentBar:OnDisable()
    Lifecycle.OnDisable(self, "SegmentBar", LAYOUT_EVENTS, REFRESH_EVENT_NAMES)
end
