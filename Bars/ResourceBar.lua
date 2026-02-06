-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local Util = ns.Util

local C = ns.Constants
local BarFrame = ns.Mixins.BarFrame

local ResourceBar = ECM:NewModule("ResourceBar", "AceEvent-3.0")
ECM.ResourceBar = ResourceBar

--- Power types that have discrete values and should be displayed using the resource bar.
local discreteResourceTypes = {
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.Essence] = true,
}

-- Gets the resource type for the player given their class, spec and current shapeshift form (if applicable).
---@return Enum.PowerType|nil powerType The current resource type, or nil if none.
local function GetActiveDiscreteResourceType()
    local _, class = UnitClass("player")

    for powerType in pairs(discreteResourceTypes) do
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

--- Returns resource bar values based on class/power type.
---@return number|nil maxResources
---@return number|nil currentValue
---@return Enum.PowerType|string|nil kind
---@return boolean|nil isVoidMeta
local function GetValues(moduleConfig)
    local _, class = UnitClass("player")

    -- Demon hunter souls can still be tracked by their aura stacks (thank the lord)
    if class == "DEMONHUNTER" then
        if GetSpecialization() == C.DEMONHUNTER_DEVOURER_SPEC_INDEX then
            -- Devourer is tracked by two spells - one for void meta, and one not.
            local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", C.RESOURCEBAR_VOID_FRAGMENTS_SPELLID)
            local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", C.RESOURCEBAR_COLLAPSING_STAR_SPELLID)
            if collapsingStar then
                -- return 6, (collapsingStar.applications or 0) / 5, "souls", true
                return 30, collapsingStar.applications or 0, "devourerMeta", true
            end

            return 35, voidFragments and voidFragments.applications or 0, "devourerNormal", false
            -- return 7, (voidFragments.applications or 0) / 5, "souls", false
        elseif GetSpecialization() == C.DEMONHUNTER_VENGEANCE_SPEC_INDEX then
            -- Vengeance use the same type of soul fragments. The value can be tracked by checking
            -- the number of times spirit bomb can be cast, of all things.
            local count = C_Spell.GetSpellCastCount(C.RESOURCEBAR_SPIRIT_BOMB_SPELLID) or 0
            return C.RESOURCEBAR_VENGEANCE_SOULS_MAX, count, "souls", nil
        end

        -- Not displaying anything for havoc currently.
    else
        -- Everything else
        local powerType = GetActiveDiscreteResourceType()
        if powerType then
            local max = UnitPowerMax("player", powerType) or 0
            local current = UnitPower("player", powerType) or 0
            return max, current, powerType, nil
        end
    end

    return nil, nil, nil, nil
end

--------------------------------------------------------------------------------
-- ECMFrame/BarFrame Overrides
--------------------------------------------------------------------------------

function ResourceBar:ShouldShow()
    local shouldShow = BarFrame.ShouldShow(self)

    if not shouldShow then
        return false
    end

    local _, class = UnitClass("player")
    local specId =  GetSpecialization()

    if (class == "DEMONHUNTER") and (specId == C.DEMONHUNTER_DEVOURER_SPEC_INDEX or specId == C.DEMONHUNTER_VENGEANCE_SPEC_INDEX) then
         return true
    end

    local discreteResource = GetActiveDiscreteResourceType()
    return discreteResource ~= nil
end

function ResourceBar:GetStatusBarValues()
    local maxResources, currentValue, kind, isVoidMeta = GetValues(self.ModuleConfig)

    if not maxResources or maxResources <= 0 then
        return 0, 1, 0, false
    end

    currentValue = currentValue or 0
    return currentValue, maxResources, currentValue, false
end

--- Gets the color for the resource bar based on resource type.
--- Handles DH souls (Vengeance, Devourer normal/meta).
---@return ECM_Color
function ResourceBar:GetStatusBarColor()
    local cfg = self.ModuleConfig
    local _, _, kind = GetValues(cfg)
    local color = cfg.colors and cfg.colors[kind]
    return color or C.COLOR_WHITE
end

function ResourceBar:Refresh(force)
    local continue = BarFrame.Refresh(self, force)
    if not continue then
        return false
    end

    -- Handle ticks (Devourer has no ticks, others have dividers)
    local _, _, kind = GetValues(self.ModuleConfig)
    local isDevourer = (kind == "devourerMeta" or kind == "devourerNormal")

    if isDevourer then
        self:HideAllTicks("tickPool")
    else
        local frame = self.InnerFrame
        local maxResources = select(2, self:GetStatusBarValues())
        if maxResources > 1 then
            local tickCount = maxResources - 1
            self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")
            self:LayoutResourceTicks(maxResources, C.COLOR_BLACK, 1, "tickPool")
        else
            self:HideAllTicks("tickPool")
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ResourceBar:OnEnable()
    if not self.IsECMFrame then
        BarFrame.AddMixin(self, "ResourceBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    self:RegisterEvent("UNIT_AURA", "ThrottledRefresh")
    self:RegisterEvent("UNIT_POWER_FREQUENT", "ThrottledRefresh")
end

function ResourceBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsECMFrame and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
end
