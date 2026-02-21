-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local C = ECM.Constants
local ClassUtil = {}
ECM.ClassUtil = ClassUtil

--- Gets the resource type for the class, spec and current shapeshift form (if applicable).
--- @return string|number|nil resourceType - returns a string for special tracked resources (souls, devourer normal/meta), or a power type enum value for standard resources. Returns nil if no relevant resource type is found for the player's class/spec.
function ClassUtil.GetResourceType(class, specIndex, shapeshiftForm)
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

    local CLASS = C.CLASS

    if class == CLASS.DEMONHUNTER then
        if specIndex == C.DEMONHUNTER_DEVOURER_SPEC_INDEX then
            local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_VOID_FRAGMENTS)
            if voidFragments then
                return "devourerMeta"
            else
                return "devourerNormal"
            end
        elseif specIndex == C.DEMONHUNTER_VENGEANCE_SPEC_INDEX then
            return "souls"
        end
    -- Brewmaster Monks don't use discrete resources (Chi), so hide the bar.
    elseif (class == CLASS.MONK) and (specIndex == C.MONK_BREWMASTER_SPEC_INDEX) then
        return nil
    elseif (class == CLASS.MAGE) then
        if (specIndex == C.MAGE_ARCANE_SPEC_INDEX) then
            return Enum.PowerType.ArcaneCharges
        end

        -- Fire/Frost mages don't use a discrete resource tracked by this bar.
        -- Return nil explicitly to make this control flow clear.
        return nil
    else
        for powerType in pairs(discreteResourceTypes) do
            local max = UnitPowerMax("player", powerType)
            if max and max > 0 then
                if class == CLASS.DRUID then
                    if shapeshiftForm == C.DRUID_CAT_FORM_INDEX then
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

--- Gets the resource type for the player given their class, spec and current shapeshift form (if applicable).
--- @return string|number|nil resourceType - returns a string for special tracked resources (souls, devourer normal/meta), or a power type enum value for standard resources. Returns nil if no relevant resource type is found for the player's class/spec.
function ClassUtil.GetPlayerResourceType()
    local _, class = UnitClass("player")
    return ClassUtil.GetResourceType(class, GetSpecialization(), GetShapeshiftForm())
end

--- Gets the max Maelstrom value that can diff based on talents
local function GetMaelstromWeaponMax()
    if C_SpellBook.IsSpellKnown(C.RESOURCEBAR_RAGING_MAELSTROM_SPELLID) then
        return C.RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED
    end
    return C.RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE
end

function ClassUtil.GetCurrentMaxResourceValues(resourceType)
    -- Demon hunter souls can still be tracked by their aura stacks (thank the lord)
    if resourceType == "souls" then
        -- Vengeance use the same type of soul fragments. The value can be tracked by checking
        -- the number of times spirit bomb can be cast, of all things.
        local count = C_Spell.GetSpellCastCount(C.RESOURCEBAR_SPIRIT_BOMB_SPELLID) or 0
        return C.RESOURCEBAR_VENGEANCE_SOULS_MAX, count
    end

    if resourceType == "devourerNormal" or resourceType == "devourerMeta" then
        -- Devourer is tracked by two spells - one for void meta, and one not.
        local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_VOID_FRAGMENTS)
        local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_COLLAPSING_STAR)
        if collapsingStar then
            return C.RESOURCEBAR_DEVOURER_META_MAX, collapsingStar.applications or 0
        end

        return C.RESOURCEBAR_DEVOURER_NORMAL_MAX, voidFragments and voidFragments.applications or 0
    end

    if resourceType == Enum.PowerType.Maelstrom then
        -- The max can be 5 or 10 depending on talent choices
        local aura = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_MAELSTROM_WEAPON)
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
