local ADDON_NAME, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

local SegmentBar = EnhancedCooldownManager:NewModule("SegmentBar", "AceEvent-3.0")
EnhancedCooldownManager.SegmentBar = SegmentBar

local WHITE8 = Util.WHITE8 or "Interface\\Buttons\\WHITE8X8"

-- Discrete power types that should be shown as segments
local discretePowerTypes = {
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Essence] = true,
}

local function GetAuraStackCount(spellId)
    spellId = tonumber(spellId)
    if not spellId or spellId <= 0 then
        return 0
    end

    if Util.InSecretRegime() then
        Util.Log("SegmentBar", "GetAuraStackCount unavailable due to secrets.")
        return 0
    end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(spellId)
        if aura then
            return aura.applications or 1
        end
        return 0
    end

    return 0
end

--- Returns fractional rune progress (ready + partial recharge).
---@param maxRunes number
---@return number
local function GetDkRuneProgressValue(maxRunes)
    -- assert that the player is a deathknight
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
    -- Check all discrete power types to find one the player has
    for powerType in pairs(discretePowerTypes) do
        local max = UnitPowerMax("player", powerType)
        if max and max > 0 then
            return powerType
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

    -- Special class-based resources
    if class == "DEATHKNIGHT" or class == "DEMONHUNTER" then
        return true
    end

    -- Frost Mage Icicles
    if class == "MAGE" then
        local specIndex = GetSpecialization()
        local specId = GetSpecializationInfo(specIndex or 0)
        if specId == 64 and not Util.InSecretRegime() then -- Frost Mage, only if we can access auras
            return true
        end
    end

    -- Check for discrete power types
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
        local maxSouls = (cfg and cfg.demonHunterSoulsMax) or 5
        local spellId = cfg and cfg.demonHunterSoulsSpellId
        -- Bypass C_Auras and use C_Spell indirectly get the current count. It's still secret.
        local count = C_Spell.GetSpellCastCount(247454) or 0
        -- if count > maxSouls then
        --     count = maxSouls
        -- end
        return maxSouls, count, "souls"
    end

    -- Special: Frost Mage Icicles (aura-based stacks)
    -- NOTE: This uses AuraUtil.FindAuraBySpellId which will likely break in v12.0 due to secret value restrictions
    if class == "MAGE" then
        local specId = GetSpecializationInfo(GetSpecialization() or 0)
        if specId == 64 then -- Frost Mage
            local maxIcicles = (cfg and cfg.frostMageIciclesMax) or 5
            local spellId = cfg and cfg.frostMageIciclesSpellId
            local count = GetAuraStackCount(spellId)
            if count > maxIcicles then
                count = maxIcicles
            end
            return maxIcicles, count, "icicles"
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

    -- Special string-based kinds with defaults
    local kindColors = {
        souls = { cfg and cfg.colorDemonHunterSouls, 0.64, 0.19, 0.79 },
        runes = { cfg and cfg.colorDkRunes, 0.78, 0.10, 0.22 },
        icicles = { cfg and cfg.colorFrostMageIcicles, 0.41, 0.80, 0.94 },
    }

    local kindEntry = kindColors[kind]
    if kindEntry then
        return ExtractColor(kindEntry[1], kindEntry[2], kindEntry[3], kindEntry[4])
    end

    -- Combo points override
    if kind == Enum.PowerType.ComboPoints and cfg and cfg.colorComboPoints then
        return ExtractColor(cfg.colorComboPoints)
    end

    -- Use powerTypeColors for discrete power types
    if type(kind) == "number" then
        local c = profile.powerTypeColors and profile.powerTypeColors.colors and profile.powerTypeColors.colors[kind]
        if c then
            return ExtractColor(c)
        end
    end

    return 1, 1, 1
end

---@class ECM_SegmentBarFrame : Frame
---@field Background Texture
---@field StatusBar StatusBar
---@field TicksFrame Frame
---@field ticks Texture[]
---@field FragmentedBars StatusBar[]
---@field _lastAnchor Frame|nil
---@field _lastOffsetY number|nil
---@field _lastHeight number|nil
---@field _lastWidth number|nil
---@field _lastTexture string|nil
---@field _maxSegments number|nil
---@field _onUpdateAttached boolean|nil

--- Creates the segment bar frame with all child elements.
---@param frameName string
---@param parent Frame
---@return ECM_SegmentBarFrame
local function CreateSegmentBar(frameName, parent)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.segmentBar

    local bar = CreateFrame("Frame", frameName, parent or UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetHeight(Util.GetBarHeight(cfg, profile, Util.DEFAULT_SEGMENT_BAR_HEIGHT))

    -- Background
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()

    -- StatusBar (for non-fragmented resources like souls)
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)

    -- Apply initial appearance
    Util.ApplyBarAppearance(bar, cfg, profile)

    -- Ticks frame (above status bar)
    bar.TicksFrame = CreateFrame("Frame", nil, bar)
    bar.TicksFrame:SetAllPoints(bar)
    bar.TicksFrame:SetFrameLevel(bar:GetFrameLevel() + 2)

    -- Containers
    bar.ticks = {}
    bar.FragmentedBars = {}

    bar:Hide()
    ---@cast bar ECM_SegmentBarFrame
    return bar
end

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

    -- Hide extra
    for i = maxSegments + 1, #bar.FragmentedBars do
        if bar.FragmentedBars[i] then
            bar.FragmentedBars[i]:Hide()
        end
    end
end

--- Ensures tick textures exist for segment divisions.
---@param bar ECM_SegmentBarFrame
---@param maxSegments number
local function EnsureTicks(bar, maxSegments)
    local needed = math.max(0, (tonumber(maxSegments) or 0) - 1)

    for i = 1, needed do
        if not bar.ticks[i] then
            local t = bar.TicksFrame:CreateTexture(nil, "OVERLAY")
            t:SetTexture(WHITE8)
            bar.ticks[i] = t
        end
        bar.ticks[i]:Show()
    end

    for i = needed + 1, #bar.ticks do
        if bar.ticks[i] then
            bar.ticks[i]:Hide()
        end
    end
end

--- Positions ticks evenly across the bar.
---@param bar ECM_SegmentBarFrame
---@param maxSegments number
local function LayoutTicks(bar, maxSegments)
    maxSegments = tonumber(maxSegments) or 0
    if maxSegments <= 1 then
        for _, t in ipairs(bar.ticks) do
            t:Hide()
        end
        return
    end

    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if width <= 0 or height <= 0 then
        return
    end

    local step = width / maxSegments
    local tr, tg, tb, ta = 0, 0, 0, 1

    for i, t in ipairs(bar.ticks) do
        if t:IsShown() then
            t:ClearAllPoints()
            local x = Util.PixelSnap(step * i)
            t:SetPoint("LEFT", bar, "LEFT", x, 0)
            t:SetSize(math.max(1, Util.PixelSnap(1)), height)
            t:SetVertexColor(tr, tg, tb, ta)
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

    -- Hide main status bar when using fragmented display
    bar.StatusBar:SetAlpha(0)

    -- Get color
    local r, g, b = GetSegmentBarColor(profile, "runes")

    -- Collect rune states
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

    -- Check if ready states changed
    local statesChanged = not bar._lastReadySet
    if not statesChanged then
        for i = 1, maxRunes do
            if (readySet[i] or false) ~= (bar._lastReadySet[i] or false) then
                statesChanged = true
                break
            end
        end
    end

    -- Reposition bars only when ready states change
    if statesChanged then
        bar._lastReadySet = readySet

        -- Build display order: ready first, then recharging sorted by time
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

        -- Apply positions
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

    -- Update values and colors every tick (no repositioning)
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
    self._frame = CreateSegmentBar(ADDON_NAME .. "SegmentBar", UIParent)
    return self._frame
end

--- Marks the segment bar as externally hidden.
---@param hidden boolean
function SegmentBar:SetExternallyHidden(hidden)
    Util.SetExternallyHidden(self, hidden, "SegmentBar")
end

--- Returns the frame only if currently shown.
---@return ECM_SegmentBarFrame|nil
function SegmentBar:GetFrameIfShown()
    return Util.GetFrameIfShown(self)
end

--- Updates layout: positioning, sizing, anchoring, appearance.
function SegmentBar:UpdateLayout()
    local result = Util.CheckUpdateLayoutPreconditions(self, "segmentBar", ShouldShowSegmentBar, "SegmentBar")
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

    Util.ApplyLayoutIfChanged(bar, anchor, desiredOffsetY, desiredHeight)

    -- Update appearance (background, texture)
    local tex = Util.ApplyBarAppearance(bar, cfg, profile)
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
        -- Reset cached state so display will reinitialize
        bar._lastReadySet = nil
        bar._displayOrder = nil
    else
        -- Hide fragmented bars for non-rune types
        for _, frag in ipairs(bar.FragmentedBars) do
            frag:Hide()
        end
        bar.StatusBar:SetAlpha(1)
    end

    EnsureTicks(bar, maxSegments)

    Util.Log("SegmentBar", "UpdateLayout complete", {
        anchorName = anchor.GetName and anchor:GetName() or "unknown",
        height = desiredHeight,
        maxSegments = maxSegments,
        kind = tostring(kind)
    })

    bar:Show()
    LayoutTicks(bar, maxSegments)

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

    LayoutTicks(bar, maxSegments)
end

function SegmentBar:OnUpdateThrottled()
    if self._externallyHidden then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not (profile and profile.segmentBar and profile.segmentBar.enabled) then
        return
    end

    local now = GetTime()
    local last = self._lastUpdate or 0
    local freq = profile.updateFrequency or 0.066

    if now - last >= freq then
        self:Refresh()
        self._lastUpdate = now
    end
end

-- Event handler for UNIT_POWER_UPDATE and UNIT_AURA (player-only)
function SegmentBar:OnUnitEvent(event, unit)
    if unit == "player" then
        self:OnUpdateThrottled()
    end
end

function SegmentBar:Enable()
    if self._enabled then
        return
    end
    self._enabled = true
    self._lastUpdate = GetTime()

    self:RegisterEvent("RUNE_POWER_UPDATE", "OnUpdateThrottled")
    self:RegisterEvent("RUNE_TYPE_UPDATE", "OnUpdateThrottled")
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitEvent")
    self:RegisterEvent("UNIT_AURA", "OnUnitEvent")
    Util.Log("SegmentBar", "Enabled - registered events")
end

function SegmentBar:Disable()
    if self._frame then
        if self._frame._onUpdateAttached then
            self._frame._onUpdateAttached = nil
            self._frame:SetScript("OnUpdate", nil)
        end
        self._frame:Hide()
    end

    if not self._enabled then
        return
    end
    self._enabled = false

    self:UnregisterEvent("RUNE_POWER_UPDATE")
    self:UnregisterEvent("RUNE_TYPE_UPDATE")
    self:UnregisterEvent("UNIT_POWER_UPDATE")
    self:UnregisterEvent("UNIT_AURA")
    Util.Log("SegmentBar", "Disabled - unregistered events")
end

function SegmentBar:OnEnable()
    Util.Log("SegmentBar", "OnEnable - module starting")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "UpdateLayout")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateLayout")

    C_Timer.After(0.1, function()
        self:UpdateLayout()
    end)
end

function SegmentBar:OnDisable()
    Util.Log("SegmentBar", "OnDisable - module stopping")
    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:Disable()
end
