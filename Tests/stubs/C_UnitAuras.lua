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
