local CSpellBook = {}

local state = {
    knownSpells = {},
}

function CSpellBook.Reset()
    state.knownSpells = {}
end

function CSpellBook.SetSpellKnown(spellID, isKnown)
    if isKnown then
        state.knownSpells[spellID] = true
    else
        state.knownSpells[spellID] = nil
    end
end

function CSpellBook.Install()
    _G.C_SpellBook = {
        IsSpellKnown = function(spellID)
            return state.knownSpells[spellID] == true
        end,
    }
end

CSpellBook.Reset()
return CSpellBook
