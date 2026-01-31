-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local BarFrame = ns.Mixins.BarFrame
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
    local defaultColor = ticksCfg and ticksCfg.defaultColor or { r = 1, g = 1, b = 1, a = 0.8 }
    local defaultWidth = ticksCfg and ticksCfg.defaultWidth or 1

    bar:EnsureTicks(#ticks, bar.StatusBar)
    bar:LayoutValueTicks(bar.StatusBar, ticks, max, defaultColor, defaultWidth)
end

--- Updates values: status bar value, text, colors, ticks.
-- function PowerBar:Refresh()
--     local profile = ECM.db and ECM.db.profile
--     local cfg = profile and profile.powerBar
--     if self:IsHidden() or not (cfg and cfg.enabled) then
--         ECM.Log(self:GetName(), "Refresh skipped: bar is hidden or disabled")
--         return
--     end

--     if not ShouldShowPowerBar() then
--         ECM.Log(self:GetName(), "Refresh skipped: ShouldShowPowerBar returned false")
--         if self._frame then
--             self._frame:Hide()
--         end
--         return
--     end

--     local bar = self._frame
--     if not bar then
--         ECM.Log(self:GetName(), "Refresh skipped: frame not created yet")
--         return
--     end

--     if bar.RefreshAppearance then
--         bar:RefreshAppearance()
--     end

--     local resource = UnitPowerType("player")
--     local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)

--     if not max then
--         ECM.Log(self:GetName(), "Refresh skipped:missing max value", { resource = resource })
--         bar:Hide()
--         return
--     end

--     current = current or 0
--     displayValue = displayValue or 0

--     local color = cfg.colors[resource]
--     local r, g, b = 1, 1, 1
--     if color then
--         r, g, b = color.r, color.g, color.b
--     end
--     bar:SetValue(0, max, current, r, g, b)

--     -- Update text
--     if valueType == "percent" then
--         bar:SetText(string.format("%.0f%%", displayValue))
--     else
--         bar:SetText(tostring(displayValue))
--     end

--     bar:SetTextVisible(cfg.showText ~= false)

--     -- Update ticks
--     -- self:UpdateTicks(bar, resource, max)

--     bar:Show()

--     ECM.Log(self:GetName(), "Refreshed", {
--         resource = resource,
--         max = max,
--         current = current,
--         displayValue = displayValue,
--         valueType = valueType
--     })
-- end

function PowerBar:OnUnitPower(_, unit)
    self:RegisterEvent("UNIT_POWER_UPDATE", "Refresh")
    local profile = ECM.db and ECM.db.profile
    if unit ~= "player" or self:IsHidden() or not (profile and profile.powerBar and profile.powerBar.enabled) then
        return
    end

    self:ThrottledRefresh()
end


function PowerBar:OnEnable()
    BarFrame.AddMixin(PowerBar, "PowerBar")

    -- call parent OnEnable
    BarFrame.OnEnable(self)

    ECM.Log(self.Name, "Enabled")
end

function PowerBar:OnDisable()
    self:UnregisterAllEvents()
    BarFrame.OnDisable(self)
    ECM.Log(self.Name, "Disabled")
end

local REFRESH_EVENTS = {
    { event = "UNIT_POWER_UPDATE", handler = "OnUnitPower" },
}
