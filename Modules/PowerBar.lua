-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local PowerBar = ns.Addon:NewModule("PowerBar", "AceEvent-3.0")
ns.Addon.PowerBar = PowerBar

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
---@param powerType Enum.PowerType Current power type
---@param max number Maximum power value
function PowerBar:UpdateTicks(frame, powerType, max)
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

function PowerBar:GetStatusBarValues()
    local powerType = ECM.ClassUtil.GetCurrentPowerType()
    local current = UnitPower("player", powerType)
    local max = UnitPowerMax("player", powerType)
    local cfg = self:GetModuleConfig()

    if cfg and cfg.showManaAsPercent and powerType == Enum.PowerType.Mana then
        return current,
            max,
            string.format("%.0f%%", UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100)),
            true
    end

    return current, max, current, false
end

function PowerBar:GetStatusBarColor()
    local cfg = self:GetModuleConfig()
    local powerType = ECM.ClassUtil.GetCurrentPowerType()
    local color = cfg and cfg.colors and cfg.colors[powerType]
    return color or ECM.Constants.COLOR_WHITE
end

function PowerBar:Refresh(why, force)
    local result = ECM.BarMixin.Refresh(self, why, force)
    if not result then
        return false
    end

    -- Update ticks specific to PowerBar (skip when max is a secret value)
    local frame = self.InnerFrame
    local powerType = ECM.ClassUtil.GetCurrentPowerType()
    local max = UnitPowerMax("player", powerType)
    if not issecretvalue(max) then
        self:UpdateTicks(frame, powerType, max)
    else
        self:HideAllTicks("tickPool")
    end

    ECM.Log(self.Name, "Refresh complete (" .. (why or "") .. ")")
    return true
end

function PowerBar:ShouldShow()
    local show = ECM.FrameMixin.ShouldShow(self)
    if show then
        local _, class = UnitClass("player")
        local powerType = ECM.ClassUtil.GetCurrentPowerType()

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

function PowerBar:OnUnitPowerUpdate(event, unitID, ...)
    if unitID ~= "player" then
        return
    end

    self:ThrottledUpdateLayout(event or "OnUnitPowerUpdate")
end

function PowerBar:OnEnable()
    ECM.BarMixin.AddMixin(self, "PowerBar")
    ECM.RegisterFrame(self)
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitPowerUpdate")
end

function PowerBar:OnDisable()
    self:UnregisterAllEvents()
    ECM.UnregisterFrame(self)
end
