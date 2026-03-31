-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local PowerBar = ns.Addon:NewModule("PowerBar")
local C = ns.Constants
ns.Addon.PowerBar = PowerBar

--- Resolves the effective power type for PowerBar.
--- Elemental Shamans use Maelstrom while other Shaman specs use Mana.
local function getCurrentPowerType()
    local _, class = UnitClass("player")
    local specIndex = GetSpecialization()
    if class == "SHAMAN" and specIndex then
        if specIndex == C.SHAMAN_ELEMENTAL_SPEC_INDEX then
            return Enum.PowerType.Maelstrom
        end
        return Enum.PowerType.Mana
    end
    return UnitPowerType("player")
end

--- Returns a tick spec for BarProto to lay out value-based tick marks.
--- Returns nil when the power max is a secret value or no ticks are configured.
---@return table|nil spec { ticks, maxValue, defaultColor, defaultWidth }
function PowerBar:GetTickSpec()
    local powerType = getCurrentPowerType()
    local max = UnitPowerMax("player", powerType)
    if issecretvalue(max) then return nil end

    local config = self:GetModuleConfig()
    local ticksCfg = config and config.ticks
    if not ticksCfg or not ticksCfg.mappings then return nil end

    local classID = select(3, UnitClass("player"))
    local specIndex = GetSpecialization()
    if not classID or not specIndex then return nil end

    local classMappings = ticksCfg.mappings[classID]
    local ticks = classMappings and classMappings[specIndex]
    if not ticks or #ticks == 0 then return nil end

    return {
        ticks = ticks,
        maxValue = max,
        defaultColor = ticksCfg.defaultColor or C.DEFAULT_POWERBAR_TICK_COLOR,
        defaultWidth = ticksCfg.defaultWidth or 1,
    }
end

function PowerBar:GetStatusBarValues()
    local powerType = getCurrentPowerType()
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
    local powerType = getCurrentPowerType()
    local color = cfg and cfg.colors and cfg.colors[powerType]
    return color or C.COLOR_WHITE
end

function PowerBar:ShouldShow()
    if not ns.BarMixin.FrameProto.ShouldShow(self) then
        return false
    end

    local _, class = UnitClass("player")
    local powerType = getCurrentPowerType()
    if powerType ~= Enum.PowerType.Mana then
        return true
    end

    local role = GetSpecializationRole(GetSpecialization())
    if role == "TANK" then return false end
    if role == "DAMAGER" then return C.POWERBAR_SHOW_MANABAR[class] or false end
    return true
end

function PowerBar:OnUnitPowerUpdate(event, unitID, ...)
    if unitID ~= "player" then
        return
    end

    ns.Runtime.RequestLayout(event or "PowerBar:OnUnitPowerUpdate")
end

function PowerBar:OnInitialize()
    ns.BarMixin.AddBarMixin(self, "PowerBar")
end

function PowerBar:OnEnable()
    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)
    self:RegisterEvent("UNIT_POWER_UPDATE", function(_, ...) self:OnUnitPowerUpdate(...) end)
end

function PowerBar:OnDisable()
    self:UnregisterAllEvents()
    ns.Runtime.UnregisterFrame(self)
end
