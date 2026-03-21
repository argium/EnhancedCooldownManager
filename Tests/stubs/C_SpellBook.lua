local CSpellBook = {}

local state = {
    knownSpells = {},
    spellsInSpellBook = {},
}

function CSpellBook.Reset()
    state.knownSpells = {}
    state.spellsInSpellBook = {}
end

function CSpellBook.SetSpellKnown(spellID, isKnown)
    state.knownSpells[spellID] = isKnown or nil
end

function CSpellBook.SetSpellInSpellBook(spellID, isInBook)
    state.spellsInSpellBook[spellID] = isInBook or nil
end

function CSpellBook.Install()
    _G.C_SpellBook = {
        IsSpellKnown = function(spellID)
            return state.knownSpells[spellID] == true
        end,
        IsSpellInSpellBook = function(spellID)
            return state.spellsInSpellBook[spellID] == true
        end,
    }
end

CSpellBook.Reset()
return CSpellBook
