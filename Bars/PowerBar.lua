-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class Frame
---@class FontString
---@class StatusBar : Frame
---@class Enum.PowerType

---@class ECM_PowerBarFrame : Frame
---@field StatusBar StatusBar
---@field TextValue FontString
---@field EnsureTicks fun(self: ECM_PowerBarFrame, count: number, parentFrame: Frame)
---@field HideAllTicks fun(self: ECM_PowerBarFrame)
---@field LayoutValueTicks fun(self: ECM_PowerBarFrame, statusBar: StatusBar, ticks: table, maxValue: number, defaultColor: table, defaultWidth: number)

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local Util = ns.Util

local BarFrame = ns.Mixins.BarFrame
local Module = ns.Mixins.Module

local PowerBar = ECM:NewModule("PowerBar", "AceEvent-3.0")
ECM.PowerBar = PowerBar

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
    local profile = ECM.db and ECM.db.profile
    if not (profile and profile.powerBar and profile.powerBar.enabled) then
        return false
    end

    local _, class = UnitClass("player")
    local powerType = UnitPowerType("player")

    -- Hide mana bar for DPS specs, except mage/warlock/caster-form druid
    local role = GetSpecializationRole(GetSpecialization())
    if role == "DAMAGER" and powerType == Enum.PowerType.Mana then
        local manaClasses = { MAGE = true, WARLOCK = true, DRUID = true }
        return manaClasses[class] or false
    end

    return true
end

--- Returns the tick marks configured for the current class and spec.
---@return ECM_TickMark[]|nil
function PowerBar:GetCurrentTicks()
    local profile = ECM.db and ECM.db.profile
    local ticksCfg = profile and profile.powerBar and profile.powerBar.ticks
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

--- Creates the power bar frame.
---@return ECM_PowerBarFrame
function PowerBar:CreateFrame()
    Util.Log("PowerBar", "Creating frame")

    local profile = ECM.db and ECM.db.profile
    local frame = BarFrame.CreateFrame(self, { withTicks = true })

    -- Add text overlay (PowerBar-specific)
    BarFrame.AddTextOverlay(frame, profile)

    -- Apply initial appearance
    frame:SetAppearance()

    return frame
end

--------------------------------------------------------------------------------
-- Layout and Rendering
--------------------------------------------------------------------------------

--- Updates tick markers on the power bar based on per-class/spec configuration.
---@param bar ECM_PowerBarFrame
---@param resource Enum.PowerType
---@param max number
function PowerBar:UpdateTicks(bar, resource, max)
    local ticks = self:GetCurrentTicks()
    if not ticks or #ticks == 0 then
        bar:HideAllTicks()
        return
    end

    local profile = ECM.db and ECM.db.profile
    local ticksCfg = profile and profile.powerBar and profile.powerBar.ticks
    local defaultColor = ticksCfg and ticksCfg.defaultColor or { 1, 1, 1, 0.8 }
    local defaultWidth = ticksCfg and ticksCfg.defaultWidth or 1

    bar:EnsureTicks(#ticks, bar.StatusBar)
    bar:LayoutValueTicks(bar.StatusBar, ticks, max, defaultColor, defaultWidth)
end

--- Updates values: status bar value, text, colors, ticks.
function PowerBar:Refresh()
    local profile = ECM.db and ECM.db.profile
    local cfg = profile and profile.powerBar
    if self:IsHidden() or not (cfg and cfg.enabled) then
        Util.Log(self:GetName(), "Refresh skipped: bar is hidden or disabled")
        return
    end

    if not ShouldShowPowerBar() then
        Util.Log(self:GetName(), "Refresh skipped: ShouldShowPowerBar returned false")
        if self._frame then
            self._frame:Hide()
        end
        return
    end

    local bar = self._frame
    if not bar then
        Util.Log(self:GetName(), "Refresh skipped: frame not created yet")
        return
    end

    if bar.RefreshAppearance then
        bar:RefreshAppearance()
    end

    local resource = UnitPowerType("player")
    local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)

    if not max then
        Util.Log(self:GetName(), "Refresh skipped:missing max value", { resource = resource })
        bar:Hide()
        return
    end

    current = current or 0
    displayValue = displayValue or 0

    local color = cfg.colors[resource] or {}
    bar:SetValue(0, max, current, color[1] or 1, color[2] or 1, color[3] or 1)

    -- Update text
    if valueType == "percent" then
        bar:SetText(string.format("%.0f%%", displayValue))
    else
        bar:SetText(tostring(displayValue))
    end

    bar:SetTextVisible(cfg.showText ~= false)

    -- Update ticks
    self:UpdateTicks(bar, resource, max)

    bar:Show()

    Util.Log(self:GetName(), "Refreshed", {
        resource = resource,
        max = max,
        current = current,
        displayValue = displayValue,
        valueType = valueType
    })
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function PowerBar:OnUnitPower(_, unit)
    local profile = ECM.db and ECM.db.profile
    if unit ~= "player" or self:IsHidden() or not (profile and profile.powerBar and profile.powerBar.enabled) then
        return
    end

    self:ThrottledRefresh()
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function PowerBar:OnEnable()
    BarFrame.AddMixin(PowerBar, "PowerBar","powerBar", nil, nil)
    Module.OnEnable(self)
end
