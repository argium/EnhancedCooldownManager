-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class Frame
---@class StatusBar : Frame
---@class Enum.PowerType

---@class ECM_ResourceBarFrame : Frame
---@field StatusBar StatusBar
---@field TicksFrame Frame
---@field EnsureTicks fun(self: ECM_ResourceBarFrame, count: number, parentFrame: Frame, poolKey: string|nil)
---@field LayoutResourceTicks fun(self: ECM_ResourceBarFrame, maxResources: number, color: table|nil, tickWidth: number|nil, poolKey: string|nil)

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local Util = ns.Util

-- Mixins
local BarFrame = ns.Mixins.BarFrame

local ResourceBar = ECM:NewModule("ResourceBar", "AceEvent-3.0")
ECM.ResourceBar = ResourceBar

local C_SPECID_DH_HAVOC = 1
local C_SPECID_DH_DEVOURER = 3

--------------------------------------------------------------------------------
-- Domain Logic (module-specific value/config handling)
--------------------------------------------------------------------------------

-- Discrete power types that should be shown as resources
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

local function ShouldShowResourceBar()
    local profile = ECM.db and ECM.db.profile
    local cfg = profile and profile.resourceBar
    local _, class = UnitClass("player")
    local discretePower = GetDiscretePowerType()
    return cfg and cfg.enabled and ((class == "DEMONHUNTER" and GetSpecialization() ~= C_SPECID_DH_HAVOC) or discretePower ~= nil)
end

--- Returns resource bar values based on class/power type.
---@param profile table
---@return number|nil maxResources
---@return number|nil currentValue
---@return Enum.PowerType|string|nil kind
local function GetValues(profile)
    local cfg = profile and profile.resourceBar
    local _, class = UnitClass("player")

    -- Special: DH Souls (aura-based stacks)
    if class == "DEMONHUNTER" then
        if GetSpecialization() == C_SPECID_DH_DEVOURER then
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

--- Creates the resource bar frame.
---@return ECM_ResourceBarFrame
function ResourceBar:CreateFrame()
    Util.Log("ResourceBar", "Creating frame")

    local profile = ECM.db and ECM.db.profile
    local frame = BarFrame.CreateFrame(self, { withTicks = true })

    frame:SetAppearance()

    return frame
end


--------------------------------------------------------------------------------
-- Layout and Rendering
--------------------------------------------------------------------------------


--- Updates values: status bar value, colors.
function ResourceBar:Refresh()
    local profile = ECM.db and ECM.db.profile
    local cfg = profile and profile.resourceBar
    if self:IsHidden() or not (cfg and cfg.enabled) then
        return
    end

    if not ShouldShowResourceBar() then
        if self._frame then
            self._frame:Hide()
        end
        return
    end

    local bar = self._frame
    if not bar then
        return
    end

    if bar.RefreshAppearance then
        bar:RefreshAppearance()
    end

    local maxResources, currentValue, kind = GetValues(profile)
    if not maxResources or maxResources <= 0 then
        bar:Hide()
        return
    end

    currentValue = currentValue or 0

    local color = (cfg.colors and cfg.colors[kind]) or {}
    bar:SetValue(0, maxResources, currentValue, color[1] or 1, color[2] or 1, color[3] or 1)

    local tickCount = math.max(0, maxResources - 1)
    bar:EnsureTicks(tickCount, bar.TicksFrame, "ticks")
    bar:LayoutResourceTicks(maxResources, { 0, 0, 0, 1 }, 1, "ticks")

    bar:Show()
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function ResourceBar:OnUnitPower(_, unit)
    local profile = ECM.db and ECM.db.profile
    if unit ~= "player" or self:IsHidden() or not (profile and profile.resourceBar and profile.resourceBar.enabled) then
        return
    end

    self:ThrottledRefresh()
end

function ResourceBar:OnUnitEvent(_, unit)
    local profile = ECM.db and ECM.db.profile
    if unit ~= "player" or self:IsHidden() or not (profile and profile.resourceBar and profile.resourceBar.enabled) then
        return
    end

    self:ThrottledRefresh()
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ResourceBar:OnEnable()
    BarFrame.AddMixin(
        ResourceBar,
        "ResourceBar",
        "resourceBar",
        nil,
        {
            { event = "UNIT_AURA", handler = "OnUnitEvent" },
        }
    )
end
