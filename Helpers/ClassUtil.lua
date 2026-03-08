-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local C = ECM.Constants
local ClassUtil = {}
ECM.ClassUtil = ClassUtil

--- Power types that have discrete values and should be displayed using the resource bar.
local discreteResourceTypes = {
    [Enum.PowerType.ArcaneCharges] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.Essence] = true,
}

--- Gets the resource type for the class, spec and current shapeshift form (if applicable).
--- @return string|number|nil resourceType - returns a string for special tracked resources (souls, devourer normal/meta, maelstrom weapon), or a power type enum value for standard resources. Returns nil if no relevant resource type is found for the player's class/spec.
function ClassUtil.GetResourceType(class, specIndex, shapeshiftForm)
    if class == "DEMONHUNTER" then
        if specIndex == C.DEMONHUNTER_DEVOURER_SPEC_INDEX then
            local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_VOID_FRAGMENTS)
            if voidFragments then
                return C.RESOURCEBAR_TYPE_DEVOURER_META
            else
                return C.RESOURCEBAR_TYPE_DEVOURER_NORMAL
            end
        elseif specIndex == C.DEMONHUNTER_VENGEANCE_SPEC_INDEX then
            return C.RESOURCEBAR_TYPE_VENGEANCE_SOULS
        end
    elseif class == "MAGE" then
        if specIndex == C.MAGE_ARCANE_SPEC_INDEX then
            return Enum.PowerType.ArcaneCharges
        end

        if specIndex == C.MAGE_FROST_SPEC_INDEX then
            return C.RESOURCEBAR_TYPE_ICICLES
        end
    elseif class == "SHAMAN" then
        -- Enhancement tracks Maelstrom Weapon stacks (aura-based), not Elemental's Maelstrom power type.
        if specIndex == C.SHAMAN_ENHANCEMENT_SPEC_INDEX then
            return C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON
        end
    elseif class == "MONK" then
        if specIndex == C.MONK_WINDWALKER_SPEC_INDEX then
            return Enum.PowerType.Chi
        end
    else
        for powerType in pairs(discreteResourceTypes) do
            local max = UnitPowerMax("player", powerType)
            if max and max > 0 then
                if class == "DRUID" then
                    if shapeshiftForm == C.DRUID_CAT_FORM_INDEX then
                        return powerType
                    end
                else
                    return powerType
                end
            end
        end
    end
end

--- Gets the resource type for the player given their class, spec and current shapeshift form (if applicable).
--- @return string|number|nil resourceType - returns a string for special tracked resources (souls, devourer normal/meta, maelstrom weapon), or a power type enum value for standard resources. Returns nil if no relevant resource type is found for the player's class/spec.
function ClassUtil.GetPlayerResourceType()
    local _, class = UnitClass("player")
    return ClassUtil.GetResourceType(class, GetSpecialization(), GetShapeshiftForm())
end

--- Gets the max Maelstrom value that can diff based on talents
local function getMaelstromWeaponMax()
    if C_SpellBook.IsSpellKnown(C.RESOURCEBAR_RAGING_MAELSTROM_SPELLID) then
        return C.RESOURCEBAR_MAELSTROM_WEAPON_MAX_TALENTED
    end
    return C.RESOURCEBAR_MAELSTROM_WEAPON_MAX_BASE
end

--- Returns max, current, and a safe discrete count for the given resource type.
--- The 3rd return (safeMax) is always a non-secret number suitable for comparison
--- and arithmetic (e.g., tick layout). For special resource types, max and safeMax
--- are identical constants. For standard power types, max may be secret while
--- safeMax will be nil when the value is tainted.
---@param resourceType string|number|nil
---@return number|nil max
---@return number|nil current
---@return number|nil safeMax Non-secret discrete count for tick layout
function ClassUtil.GetCurrentMaxResourceValues(resourceType)
    -- Demon hunter souls can still be tracked by their aura stacks (thank the lord)
    if resourceType == C.RESOURCEBAR_TYPE_VENGEANCE_SOULS then
        -- Vengeance use the same type of soul fragments. The value can be tracked by checking
        -- the number of times spirit bomb can be cast, of all things.
        local count = C_Spell.GetSpellCastCount(C.RESOURCEBAR_SPIRIT_BOMB_SPELLID) or 0
        return C.RESOURCEBAR_VENGEANCE_SOULS_MAX, count, C.RESOURCEBAR_VENGEANCE_SOULS_MAX
    end

    if resourceType == C.RESOURCEBAR_TYPE_ICICLES then
        local aura = C_UnitAuras.GetUnitAuraBySpellID("player", C.RESOURCEBAR_ICICLES_SPELLID)
        return C.RESOURCEBAR_ICICLES_MAX, aura and aura.applications or 0, C.RESOURCEBAR_ICICLES_MAX
    end

    if resourceType == C.RESOURCEBAR_TYPE_DEVOURER_NORMAL or resourceType == C.RESOURCEBAR_TYPE_DEVOURER_META then
        -- Devourer is tracked by two spells - one for void meta, and one not.
        local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_VOID_FRAGMENTS)
        local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_COLLAPSING_STAR)
        if collapsingStar then
            return C.RESOURCEBAR_DEVOURER_META_MAX, collapsingStar.applications or 0, C.RESOURCEBAR_DEVOURER_META_MAX
        end

        return C.RESOURCEBAR_DEVOURER_NORMAL_MAX, voidFragments and voidFragments.applications or 0, C.RESOURCEBAR_DEVOURER_NORMAL_MAX
    end

    if resourceType == C.RESOURCEBAR_TYPE_MAELSTROM_WEAPON then
        -- The max can be 5 or 10 depending on talent choices
        local aura = C_UnitAuras.GetUnitAuraBySpellID("player", C.SPELLID_MAELSTROM_WEAPON)
        local stacks = aura and aura.applications or 0
        local mwMax = getMaelstromWeaponMax()
        return mwMax, stacks, mwMax
    end

    ECM.DebugAssert(type(resourceType) == "number", "Expected resourceType to be a power type enum value")
    if resourceType then
        local max = UnitPowerMax("player", resourceType)
        local current = UnitPower("player", resourceType)
        local safeMax = issecretvalue(max) and nil or max
        return max, current, safeMax
    end
end

function ClassUtil.IsDeathKnight()
    local _, class = UnitClass("player")
    return class == "DEATHKNIGHT"
end

--- Resolves the effective resource used by PowerBar.
--- Elemental Shamans use Maelstrom while other Shaman specs use Mana.
---@return Enum.PowerType
function ClassUtil.GetCurrentPowerType()
    local _, class = UnitClass("player")
    local specIndex = GetSpecialization()

    if class == "SHAMAN" and specIndex then
        if specIndex == ECM.Constants.SHAMAN_ELEMENTAL_SPEC_INDEX then
            return Enum.PowerType.Maelstrom
        end

        return Enum.PowerType.Mana
    end

    local powerType = UnitPowerType("player")
    return powerType
end
