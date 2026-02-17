-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local ResourceBar = mod:NewModule("ResourceBar", "AceEvent-3.0")
mod.ResourceBar = ResourceBar
ECM.BarMixin.ApplyConfigMixin(ResourceBar, "ResourceBar")

--- Power types that have discrete values and should be displayed using the resource bar.
local discreteResourceTypes = {
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.Maelstrom] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.Essence] = true,
}

local function GetMaelstromWeaponMax()
    if C_SpellBook.IsSpellKnown(ECM.Constants.RESOURCEBAR_RAGING_MAELSTROM_SPELLID) then
        return ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED
    end
    return ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE
end

--- Gets the resource type for the player given their class, spec and current shapeshift form (if applicable).
--- @return string|number|nil resourceType - returns a string for special tracked resources (souls, devourer normal/meta), or a power type enum value for standard resources. Returns nil if no relevant resource type is found for the player's class/spec.
local function GetResourceType()
    local _, class = UnitClass("player")
    local specId = GetSpecialization()

    if class == "DEMONHUNTER" then
        if specId == ECM.Constants.DEMONHUNTER_DEVOURER_SPEC_INDEX then
            local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", ECM.Constants.RESOURCEBAR_VOID_FRAGMENTS_SPELLID)
            if voidFragments then
                return "devourerMeta"
            else
                return "devourerNormal"
            end
        elseif specId == ECM.Constants.DEMONHUNTER_VENGEANCE_SPEC_INDEX then
            return "souls"
        end
    -- Brewmaster Monks don't use discrete resources (Chi), so hide the bar.
    elseif (class == "MONK") and (specId == ECM.Constants.MONK_BREWMASTER_SPEC_INDEX) then
        return nil
    elseif (class == "MAGE") then
        if (specId == ECM.Constants.MAGE_ARCANE_SPEC_INDEX) then
            return Enum.PowerType.ArcaneCharges
        end

        -- Fire/Frost mages don't use a discrete resource tracked by this bar.
        -- Return nil explicitly to make this control flow clear.
        return nil
    else
        for powerType in pairs(discreteResourceTypes) do
            local max = UnitPowerMax("player", powerType)
            if max and max > 0 then
                if class == "DRUID" then
                    local formIndex = GetShapeshiftForm()
                    if formIndex == ECM.Constants.DRUID_CAT_FORM_INDEX then
                        return powerType
                    end
                else
                    return powerType
                end
            end
        end
    end

    return nil
end

--- Returns resource bar values based on class/power type.
---@return number|nil maxResources
---@return number|nil currentValue
local function GetValues()
    local resourceType = GetResourceType()

    -- Demon hunter souls can still be tracked by their aura stacks (thank the lord)
    if resourceType == "souls" then
        -- Vengeance use the same type of soul fragments. The value can be tracked by checking
        -- the number of times spirit bomb can be cast, of all things.
        local count = C_Spell.GetSpellCastCount(ECM.Constants.RESOURCEBAR_SPIRIT_BOMB_SPELLID) or 0
        return ECM.Constants.RESOURCEBAR_VENGEANCE_SOULS_MAX, count
    end

    if resourceType == "devourerNormal" or resourceType == "devourerMeta" then
        -- Devourer is tracked by two spells - one for void meta, and one not.
        local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", ECM.Constants.RESOURCEBAR_VOID_FRAGMENTS_SPELLID)
        local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", ECM.Constants.RESOURCEBAR_COLLAPSING_STAR_SPELLID)
        if collapsingStar then
            return ECM.Constants.RESOURCEBAR_DEVOURER_META_MAX, collapsingStar.applications or 0
        end

        return ECM.Constants.RESOURCEBAR_DEVOURER_NORMAL_MAX, voidFragments and voidFragments.applications or 0
    end

    if resourceType == Enum.PowerType.Maelstrom then
        -- The max can be 5 or 10 depending on talent choices
        local aura = C_UnitAuras.GetUnitAuraBySpellID("player", ECM.Constants.RESOURCEBAR_MAELSTROM_WEAPON_SPELLID)
        local stacks = aura and aura.applications or 0
        return GetMaelstromWeaponMax(), stacks
    end

    ECM_debug_assert(type(resourceType) == "number", "Expected resourceType to be a power type enum value")
    if resourceType then
        local max = UnitPowerMax("player", resourceType) or 0
        local current = UnitPower("player", resourceType) or 0
        return max, current
    end

    return nil, nil
end

--------------------------------------------------------------------------------
-- ModuleMixin/BarMixin Overrides
--------------------------------------------------------------------------------

function ResourceBar:ShouldShow()
    local shouldShow = ECM.BarMixin.ShouldShow(self)

    if not shouldShow then
        return false
    end

    return GetResourceType() ~= nil
end

function ResourceBar:GetStatusBarValues()
    local maxResources, currentValue = GetValues()

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
    local cfg = self:GetModuleConfig()
    local resourceType = GetResourceType()
    local color = cfg.colors and cfg.colors[resourceType]
    ECM_debug_assert(color, "Expected color to be defined for resourceType " .. tostring(resourceType))
    return color or ECM.Constants.COLOR_WHITE
end

function ResourceBar:Refresh(why, force)
    local continue = ECM.BarMixin.Refresh(self, why, force)
    if not continue then
        return false
    end

    -- Handle ticks (Devourer has no ticks, others have dividers)
    local resourceType = GetResourceType()
    local isDevourer = (resourceType == "devourerMeta" or resourceType == "devourerNormal")

    if isDevourer then
        self:HideAllTicks("tickPool")
    else
        local frame = self.InnerFrame
        local maxResources = select(2, self:GetStatusBarValues())
        if maxResources > 1 then
            local tickCount = maxResources - 1
            self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")
            self:LayoutResourceTicks(maxResources, ECM.Constants.COLOR_BLACK, 1, "tickPool")
        else
            self:HideAllTicks("tickPool")
        end
    end

    ECM_log(ECM.Constants.SYS.Styling, self.Name, "Refresh complete.")
    return true
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function ResourceBar:OnEventUpdate(event, ...)
    self:ThrottledUpdateLayout(event or "OnEventUpdate")
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ResourceBar:OnEnable()
    if not self.IsModuleMixin then
        ECM.BarMixin.AddMixin(self, "ResourceBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    self:RegisterEvent("UNIT_AURA", "OnEventUpdate")
    self:RegisterEvent("UNIT_POWER_FREQUENT", "OnEventUpdate")
end

function ResourceBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsModuleMixin and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
end
