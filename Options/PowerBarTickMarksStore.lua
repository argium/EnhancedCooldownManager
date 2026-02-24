-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants

local function EnsureTicksConfig()
    local db = mod.db
    db.profile = db.profile or {}
    db.profile.powerBar = db.profile.powerBar or {}

    local powerBarCfg = db.profile.powerBar
    if not powerBarCfg.ticks then
        powerBarCfg.ticks = {
            mappings = {},
            defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
            defaultWidth = 1,
        }
    end

    local ticksCfg = powerBarCfg.ticks
    if not ticksCfg.mappings then
        ticksCfg.mappings = {}
    end
    if ticksCfg.defaultColor == nil then
        ticksCfg.defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR
    end
    if ticksCfg.defaultWidth == nil then
        ticksCfg.defaultWidth = 1
    end

    return ticksCfg
end

local function GetCurrentClassSpecIds()
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return nil, nil
    end

    return classID, specIndex
end

local function GetCurrentTicks()
    local db = mod.db
    local classID, specIndex = GetCurrentClassSpecIds()
    if not classID or not specIndex then
        return {}
    end

    local ticksCfg = db.profile.powerBar and db.profile.powerBar.ticks
    if not ticksCfg or not ticksCfg.mappings then
        return {}
    end

    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        return {}
    end

    return classMappings[specIndex] or {}
end

local function SetCurrentTicks(ticks)
    local classID, specIndex = GetCurrentClassSpecIds()
    if not classID or not specIndex then
        return
    end

    local ticksCfg = EnsureTicksConfig()
    if not ticksCfg.mappings[classID] then
        ticksCfg.mappings[classID] = {}
    end

    ticksCfg.mappings[classID][specIndex] = ticks
end

local function AddTick(value, color, width)
    local ticks = GetCurrentTicks()
    local ticksCfg = EnsureTicksConfig()

    local newTick = {
        value = value,
        color = color or ECM_CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
    table.insert(ticks, newTick)
    SetCurrentTicks(ticks)
end

local function RemoveTick(index)
    local ticks = GetCurrentTicks()
    if ticks[index] then
        table.remove(ticks, index)
        SetCurrentTicks(ticks)
    end
end

local function UpdateTick(index, field, value)
    local ticks = GetCurrentTicks()
    if ticks[index] then
        ticks[index][field] = value
        SetCurrentTicks(ticks)
    end
end

local function GetDefaultColor()
    return EnsureTicksConfig().defaultColor
end

local function SetDefaultColor(color)
    EnsureTicksConfig().defaultColor = color
end

local function GetDefaultWidth()
    return EnsureTicksConfig().defaultWidth
end

local function SetDefaultWidth(width)
    EnsureTicksConfig().defaultWidth = width
end

ECM.PowerBarTickMarksStore = {
    GetCurrentTicks = GetCurrentTicks,
    SetCurrentTicks = SetCurrentTicks,
    AddTick = AddTick,
    RemoveTick = RemoveTick,
    UpdateTick = UpdateTick,
    GetDefaultColor = GetDefaultColor,
    SetDefaultColor = SetDefaultColor,
    GetDefaultWidth = GetDefaultWidth,
    SetDefaultWidth = SetDefaultWidth,
}
