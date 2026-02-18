-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local PowerBar = mod:NewModule("PowerBar", "AceEvent-3.0")
mod.PowerBar = PowerBar
ECM.BarMixin.ApplyConfigMixin(PowerBar, "PowerBar")

--- Returns the tick marks configured for the current class and spec.
---@return ECM_TickMark[]|nil
function PowerBar:GetCurrentTicks()
    local config = self:GetModuleConfig()
    local ticksCfg = config and config.ticks
    if not ticksCfg or not ticksCfg.mappings then
        return nil
    end

    local classID = select(3, UnitClass("player"))
    local specIndex = GetSpecialization()
    if not classID or not specIndex then
        return nil
    end

    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        return nil
    end

    return classMappings[specIndex]
end

--- Updates tick markers on the power bar based on per-class/spec configuration.
---@param frame Frame The inner frame containing StatusBar and TicksFrame
---@param resource Enum.PowerType Current power type
---@param max number Maximum power value
function PowerBar:UpdateTicks(frame, resource, max)
    local ticks = self:GetCurrentTicks()
    if not ticks or #ticks == 0 then
        self:HideAllTicks("tickPool")
        return
    end

    local config = self:GetModuleConfig()
    local ticksCfg = config and config.ticks
    local defaultColor = ticksCfg and ticksCfg.defaultColor or ECM.Constants.DEFAULT_POWERBAR_TICK_COLOR
    local defaultWidth = ticksCfg and ticksCfg.defaultWidth or 1

    -- Create tick textures on TicksFrame, but position them relative to StatusBar
    self:EnsureTicks(#ticks, frame.TicksFrame, "tickPool")
    self:LayoutValueTicks(frame.StatusBar, ticks, max, defaultColor, defaultWidth, "tickPool")
end

--------------------------------------------------------------------------------
-- ModuleMixin/BarMixin Overrides
--------------------------------------------------------------------------------

function PowerBar:GetStatusBarValues()
    local resource = UnitPowerType("player")
    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    local cfg = self:GetModuleConfig()

    if cfg and cfg.showManaAsPercent and resource == Enum.PowerType.Mana then
        return current, max, string.format("%.0f%%", UnitPowerPercent("player", resource, false, CurveConstants.ScaleTo100)), true
    end

    return current, max, current, false
end

function PowerBar:Refresh(why, force)
    local result = ECM.BarMixin.Refresh(self, why, force)
    if not result then
        return false
    end

    -- Update ticks specific to PowerBar
    local frame = self.InnerFrame
    local resource = UnitPowerType("player")
    local max = UnitPowerMax("player", resource)
    self:UpdateTicks(frame, resource, max)

    ECM_log(ECM.Constants.SYS.Styling, self.Name, "Refresh complete (" .. (why or "") .. ")")
    return true
end

function PowerBar:ShouldShow()
    local show = ECM.BarMixin.ShouldShow(self)
    if show then
        local _, class = UnitClass("player")
        local powerType = UnitPowerType("player")

        -- Hide mana bar for DPS specs (except mage/warlock/druid) and all tank specs
        local role = GetSpecializationRole(GetSpecialization())
        if powerType == Enum.PowerType.Mana then
            if role == "TANK" then
                return false
            elseif role == "DAMAGER" then
                return ECM.Constants.POWERBAR_SHOW_MANABAR[class] or false
            end
        end

        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function PowerBar:OnUnitPowerUpdate(event, unitID, ...)
    if unitID and unitID ~= "player" then
        return
    end

    self:ThrottledUpdateLayout(event or "OnUnitPowerUpdate")
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function PowerBar:OnEnable()
    if not self.IsModuleMixin then
        ECM.BarMixin.AddMixin(self, "PowerBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    self:RegisterEvent("UNIT_POWER_FREQUENT", "OnUnitPowerUpdate")
    ECM_log(ECM.Constants.SYS.Core, self.Name, "Enabled")
end

function PowerBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsModuleMixin and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
    ECM_log(ECM.Constants.SYS.Core, self.Name, "Disabled")
end
