local Unit = {}

local state = {
    classByUnit = {},
    powerMaxByType = {},
    powerByType = {},
}

local function resolvePowerType(powerType)
    if powerType ~= nil then return powerType end
    if type(_G.UnitPowerType) == "function" then
        local pt = _G.UnitPowerType("player")
        if pt ~= nil then return pt end
    end
    return _G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.Mana or 0
end

function Unit.Reset()
    state.classByUnit = {}
    state.powerMaxByType = {}
    state.powerByType = {}
end

function Unit.SetClass(unit, classToken)
    state.classByUnit[unit or "player"] = classToken
end

function Unit.SetPowerMax(powerType, value)
    state.powerMaxByType[resolvePowerType(powerType)] = value
end

function Unit.SetPower(powerType, value)
    state.powerByType[resolvePowerType(powerType)] = value
end

function Unit.Install()
    _G.UnitClass = function(unit)
        return nil, state.classByUnit[unit or "player"]
    end

    _G.UnitPowerMax = function(_, powerType)
        return state.powerMaxByType[resolvePowerType(powerType)] or 0
    end

    _G.UnitPower = function(_, powerType)
        return state.powerByType[resolvePowerType(powerType)] or 0
    end
end

Unit.Reset()
return Unit
