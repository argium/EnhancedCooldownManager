local ADDON_NAME, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

-- Mixins
local BarFrame = ns.Mixins.BarFrame
local Lifecycle = ns.Mixins.Lifecycle
local TickRenderer = ns.Mixins.TickRenderer

local PowerBars = EnhancedCooldownManager:NewModule("PowerBars", "AceEvent-3.0")
EnhancedCooldownManager.PowerBars = PowerBars

--------------------------------------------------------------------------------
-- Domain Logic (module-specific value/config handling)
--------------------------------------------------------------------------------

--- Returns max/current/display values for primary resource formatting.
---@param resource Enum.PowerType|nil
---@param cfg table|nil
---@return number|nil max
---@return number|nil current
---@return number|nil displayValue
---@return string|nil valueType
local function GetPrimaryResourceValue(resource, cfg)
    if not resource then
        return nil, nil, nil, nil
    end

    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)

    if cfg and cfg.showManaAsPercent and resource == Enum.PowerType.Mana then
        return max, current, UnitPowerPercent("player", resource, false, CurveConstants.ScaleTo100), "percent"
    end

    return max, current, current, "number"
end


local function ShouldShowPowerBar()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not (profile and profile.powerBar and profile.powerBar.enabled) then
        return false
    end

    local _, class = UnitClass("player")
    local powerType = UnitPowerType("player")

    -- Hide mana bar for DPS specs, except mage/warlock/caster-form druid
    local role = GetSpecializationRole(GetSpecialization())
    if role == "DAMAGER" and powerType == Enum.PowerType.Mana then
        return class == "MAGE" or class == "WARLOCK" or class == "DRUID"
    end

    return true
end

--- Returns the tick marks configured for the current class and spec.
---@return ECM_TickMark[]|nil
function PowerBars:GetCurrentTicks()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local ticksCfg = profile and profile.powerBarTicks
    if not ticksCfg or not ticksCfg.mappings then
        return nil
    end

    local classID = select(3, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    if not classID or not specID then
        return nil
    end

    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        return nil
    end

    return classMappings[specID]
end

--------------------------------------------------------------------------------
-- Frame Management (uses BarFrame mixin)
--------------------------------------------------------------------------------

--- Marks the power bar as externally hidden (e.g., via ViewerHook).
---@param hidden boolean
function PowerBars:SetExternallyHidden(hidden)
    Lifecycle.SetExternallyHidden(self, hidden, "PowerBars")
end

--- Returns or creates the power bar frame.
---@return ECM_PowerBarFrame
function PowerBars:GetFrame()
    if self._frame then
        return self._frame
    end

    Util.Log("PowerBars", "Creating frame")

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile

    -- Create base bar with Background + StatusBar
    self._frame = BarFrame.Create(
        ADDON_NAME .. "PowerBar",
        UIParent,
        Util.DEFAULT_POWER_BAR_HEIGHT
    )

    -- Add text overlay (PowerBar-specific)
    BarFrame.AddTextOverlay(self._frame, profile)

    -- Apply initial appearance
    BarFrame.ApplyAppearance(self._frame, profile and profile.powerBar, profile)

    return self._frame
end

--- Returns the frame only if currently shown.
---@return ECM_PowerBarFrame|nil
function PowerBars:GetFrameIfShown()
    return Lifecycle.GetFrameIfShown(self)
end

--------------------------------------------------------------------------------
-- Layout and Rendering
--------------------------------------------------------------------------------

--- Updates tick markers on the power bar based on per-class/spec configuration.
---@param bar ECM_PowerBarFrame
---@param resource Enum.PowerType
---@param max number
function PowerBars:UpdateTicks(bar, resource, max)
    local ticks = self:GetCurrentTicks()
    if not ticks or #ticks == 0 then
        TickRenderer.HideAllTicks(bar)
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local ticksCfg = profile and profile.powerBarTicks
    local defaultColor = ticksCfg and ticksCfg.defaultColor or { 0, 0, 0, 0.5 }
    local defaultWidth = ticksCfg and ticksCfg.defaultWidth or 1

    TickRenderer.EnsureTicks(bar, #ticks, bar.StatusBar)
    TickRenderer.LayoutValueTicks(bar, bar.StatusBar, ticks, max, defaultColor, defaultWidth)
end

--- Updates layout: positioning, sizing, anchoring, appearance.
function PowerBars:UpdateLayout()
    local result = Lifecycle.CheckLayoutPreconditions(self, "powerBar", ShouldShowPowerBar, "PowerBars")
    if not result then
        return
    end

    self:Enable()

    local profile, cfg = result.profile, result.cfg
    local bar = self:GetFrame()
    local anchor = Util.GetViewerAnchor()

    local desiredHeight = Util.GetBarHeight(cfg, profile, Util.DEFAULT_POWER_BAR_HEIGHT)
    local desiredOffsetY = -Util.GetTopGapOffset(cfg, profile)
    local widthCfg = profile.width or {}
    local desiredWidth = widthCfg.value or 330
    local matchAnchorWidth = widthCfg.auto ~= false

    Util.ApplyLayoutIfChanged(bar, anchor, desiredOffsetY, desiredHeight, desiredWidth, matchAnchorWidth)

    -- Update appearance (background, texture)
    local tex = BarFrame.ApplyAppearance(bar, cfg, profile)
    bar._lastTexture = tex

    -- Update font
    Util.ApplyFont(bar.TextValue, profile)

    Util.Log("PowerBars", "UpdateLayout complete", {
        anchorName = anchor.GetName and anchor:GetName() or "unknown",
        height = desiredHeight,
        offsetY = desiredOffsetY
    })

    bar:Show()
    self:Refresh()
end

--- Updates values: status bar value, text, colors, ticks.
function PowerBars:Refresh()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.powerBar
    if self._externallyHidden or not (cfg and cfg.enabled) then
        return
    end

    if not ShouldShowPowerBar() then
        if self._frame then
            self._frame:Hide()
        end
        return
    end

    local bar = self._frame
    if not bar then
        return
    end

    local resource = UnitPowerType("player")
    local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)

    if not max then
        bar:Hide()
        return
    end

    current = current or 0
    displayValue = displayValue or 0

    BarFrame.SetValue(bar, 0, max, current, cfg.colors[resource][1] or 1, cfg.colors[resource][2] or 1, cfg.colors[resource][3] or 1)

    -- Update text
    if valueType == "percent" then
        BarFrame.SetText(bar, string.format("%.0f%%", displayValue))
    else
        BarFrame.SetText(bar, tostring(displayValue))
    end

    BarFrame.SetTextVisible(bar, cfg.showText ~= false)

    -- Update ticks
    self:UpdateTicks(bar, resource, max)

    bar:Show()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function PowerBars:OnUnitPower(_, unit)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if unit ~= "player" or self._externallyHidden or not (profile and profile.powerBar and profile.powerBar.enabled) then
        return
    end

    Lifecycle.ThrottledRefresh(self, profile, function(mod)
        mod:Refresh()
    end)
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

Lifecycle.Setup(PowerBars, {
    name = "PowerBars",
    layoutEvents = {
        "PLAYER_SPECIALIZATION_CHANGED",
        "UPDATE_SHAPESHIFT_FORM",
        "PLAYER_ENTERING_WORLD",
    },
    refreshEvents = {
        { event = "UNIT_POWER_UPDATE", handler = "OnUnitPower" },
    },
})
