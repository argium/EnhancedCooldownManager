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
    [Enum.PowerType.Essence] = true,
}

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
    local cfg = profile.segmentBar
    local _, class = UnitClass("player")
    local discretePower = GetDiscretePowerType()
    return cfg and cfg.enabled and (class == "DEMONHUNTER" or discretePower ~= nil)
end

--- Returns segment bar values based on class/power type.
---@param profile table
---@return number|nil maxSegments
---@return number|nil currentValue
---@return Enum.PowerType|string|nil kind
local function GetValues(profile)
    local cfg = profile and profile.segmentBar
    local _, class = UnitClass("player")

    -- Special: DH Souls (aura-based stacks)
    if class == "DEMONHUNTER" then
        if GetSpecialization() == 3 then
            -- Devourer is tracked by two spells. One is while not in void meta, and the second is while in it.
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
            -- Havoc and vengeance use the same type of soul fragments
            local maxSouls = (cfg and cfg.demonHunterSoulsMax) or 5
            local count = C_Spell.GetSpellCastCount(247454) or 0
            return maxSouls, count, "souls"
        end
    end

    -- Everything else that's supported is a first-class resource
    local powerType = GetDiscretePowerType()
    if powerType then
        local max = UnitPowerMax("player", powerType) or 0
        local current = UnitPower("player", powerType) or 0
        return max, current, powerType
    end

    return nil, nil, nil
end

--------------------------------------------------------------------------------
-- Frame Management (uses BarFrame mixin)
--------------------------------------------------------------------------------

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
    local anchor, isFirstBar = Util.GetPreferredAnchor(EnhancedCooldownManager, "SegmentBar")
    local viewer = Util.GetViewerAnchor()

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
    local maxSegments, currentValue, kind = GetValues(profile)
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

    self:Refresh()
end

--- Updates values: status bar value, colors.
function SegmentBar:Refresh()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.segmentBar
    if self._externallyHidden or not (cfg and cfg.enabled) then
        return
    end

    if not ShouldShowSegmentBar() then
        return
    end

    local bar = self._frame
    if not bar then
        return
    end

    local maxSegments, currentValue, kind = GetValues(profile)
    if not maxSegments or maxSegments <= 0 then
        return
    end

    bar.StatusBar:SetValue(currentValue or 0)
    bar.StatusBar:SetStatusBarColor(cfg.colors[kind][1] or 1, cfg.colors[kind][2] or 1, cfg.colors[kind][3] or 1)

    TickRenderer.LayoutSegmentTicks(bar, maxSegments, { 0, 0, 0, 1 }, 1, "ticks")
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function SegmentBar:OnUpdateThrottled()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if self._externallyHidden or not (profile and profile.segmentBar and profile.segmentBar.enabled) then
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

Lifecycle.Setup(SegmentBar, {
    name = "SegmentBar",
    layoutEvents = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "PLAYER_ENTERING_WORLD",
        "UPDATE_SHAPESHIFT_FORM",
    },
    refreshEvents = {
        { event = "UNIT_POWER_UPDATE", handler = "OnUnitEvent" },
        { event = "UNIT_AURA", handler = "OnUnitEvent" },
    },
})
