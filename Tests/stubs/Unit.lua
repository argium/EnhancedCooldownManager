local Unit = {}

local state = {
    classByUnit = {},
    powerMaxByType = {},
    powerByType = {},
}

function Unit.Reset()
    state.classByUnit = {}
    state.powerMaxByType = {}
    state.powerByType = {}
end

function Unit.SetClass(unit, classToken)
    state.classByUnit[unit or "player"] = classToken
end

function Unit.SetPowerMax(powerType, value)
    state.powerMaxByType[powerType] = value
end

function Unit.SetPower(powerType, value)
    state.powerByType[powerType] = value
end

function Unit.Install()
    _G.UnitClass = function(unit)
        return nil, state.classByUnit[unit or "player"]
    end

    _G.UnitPowerMax = function(_, powerType)
        local value = state.powerMaxByType[powerType]
        if value == nil then
            return 0
        end
        return value
    end

    _G.UnitPower = function(_, powerType)
        return state.powerByType[powerType]
    end
end

Unit.Reset()
return Unit
