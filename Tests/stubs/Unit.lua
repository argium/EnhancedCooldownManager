local Unit = {}

local state = {
    classByUnit = {},
    powerMaxByType = {},
    powerByType = {},
}

local function ResolvePowerType(powerType)
    if powerType ~= nil then
        return powerType
    end

    if type(_G.UnitPowerType) == "function" then
        local primaryPowerType = _G.UnitPowerType("player")
        if primaryPowerType ~= nil then
            return primaryPowerType
        end
    end

    if _G.Enum and _G.Enum.PowerType and _G.Enum.PowerType.Mana ~= nil then
        return _G.Enum.PowerType.Mana
    end

    return 0
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
    state.powerMaxByType[ResolvePowerType(powerType)] = value
end

function Unit.SetPower(powerType, value)
    state.powerByType[ResolvePowerType(powerType)] = value
end

function Unit.Install()
    _G.UnitClass = function(unit)
        return nil, state.classByUnit[unit or "player"]
    end

    _G.UnitPowerMax = function(_, powerType)
        local value = state.powerMaxByType[ResolvePowerType(powerType)]
        if value == nil then
            return 0
        end
        return value
    end

    _G.UnitPower = function(_, powerType)
        local value = state.powerByType[ResolvePowerType(powerType)]
        if value == nil then
            return 0
        end
        return value
    end
end

Unit.Reset()
return Unit
