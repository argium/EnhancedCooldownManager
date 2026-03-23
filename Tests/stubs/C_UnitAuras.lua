-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local CUnitAuras = {}

local state = {
    auraBySpellID = {},
}

function CUnitAuras.Reset()
    state.auraBySpellID = {}
end

function CUnitAuras.SetAura(spellID, aura)
    state.auraBySpellID[spellID] = aura
end

function CUnitAuras.Install()
    _G.C_UnitAuras = {
        GetUnitAuraBySpellID = function(_, spellID)
            return state.auraBySpellID[spellID]
        end,
    }
end

CUnitAuras.Reset()
return CUnitAuras
