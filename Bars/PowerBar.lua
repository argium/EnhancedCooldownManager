-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local C = ns.Constants

local BarFrame = ns.Mixins.BarFrame

local PowerBar = ECM:NewModule("PowerBar", "AceEvent-3.0")
ECM.PowerBar = PowerBar

--- Returns the tick marks configured for the current class and spec.
---@return ECM_TickMark[]|nil
function PowerBar:GetCurrentTicks()
    local config = self.ModuleConfig
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

    local config = self.ModuleConfig
    local ticksCfg = config and config.ticks
    local defaultColor = ticksCfg and ticksCfg.defaultColor or { r = 1, g = 1, b = 1, a = 0.8 }
    local defaultWidth = ticksCfg and ticksCfg.defaultWidth or 1

    -- Create tick textures on TicksFrame, but position them relative to StatusBar
    self:EnsureTicks(#ticks, frame.TicksFrame, "tickPool")
    self:LayoutValueTicks(frame.StatusBar, ticks, max, defaultColor, defaultWidth, "tickPool")
end

--------------------------------------------------------------------------------
-- ECMFrame/BarFrame Overrides
--------------------------------------------------------------------------------

function PowerBar:GetStatusBarValues()
    local resource = UnitPowerType("player")
    local current = UnitPower("player", resource)
    local max = UnitPowerMax("player", resource)
    local cfg = self.ModuleConfig

    if cfg and cfg.showManaAsPercent and resource == Enum.PowerType.Mana then
        return current, max, UnitPowerPercent("player", resource, false, CurveConstants.ScaleTo100), true
    end

    return current, max, current, false
end

function PowerBar:Refresh(force)
    local result = BarFrame.Refresh(self, force)
    if not result then
        return false
    end

    -- Update ticks specific to PowerBar
    local frame = self.InnerFrame
    local resource = UnitPowerType("player")
    local max = UnitPowerMax("player", resource)
    self:UpdateTicks(frame, resource, max)

    return true
end


function PowerBar:ShouldShow()
    local show = BarFrame.ShouldShow(self)
    if show then
        local _, class = UnitClass("player")
        local powerType = UnitPowerType("player")

        -- Hide mana bar for DPS specs, except mage/warlock/caster-form druid
        local role = GetSpecializationRole(GetSpecialization())
        if role == "DAMAGER" and powerType == Enum.PowerType.Mana then
            return C.POWERBAR_SHOW_MANABAR[class] or false
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

    self:ThrottledRefresh()
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function PowerBar:OnEnable()
    if not self.IsECMFrame then
        BarFrame.AddMixin(self, "PowerBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    BarFrame.OnEnable(self)
    self:RegisterEvent("UNIT_POWER_FREQUENT", "OnUnitPowerUpdate")
    ECM.Log(self.Name, "PowerBar:Enabled")
end

function PowerBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsECMFrame and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
    BarFrame.OnDisable(self)
    ECM.Log(self.Name, "PowerBar:Disabled")
end
