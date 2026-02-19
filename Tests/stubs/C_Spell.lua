local CSpell = {}

local state = {
    castCountBySpellID = {},
}

function CSpell.Reset()
    state.castCountBySpellID = {}
end

function CSpell.SetSpellCastCount(spellID, count)
    state.castCountBySpellID[spellID] = count
end

function CSpell.Install()
    _G.C_Spell = {
        GetSpellCastCount = function(spellID)
            return state.castCountBySpellID[spellID]
        end,
    }
end

CSpell.Reset()
return CSpell
