-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants

-- Lazily creates the ticks config structure if missing (e.g. empty test profiles)
local function GetTicksConfig()
    local powerBar = mod.db.profile.powerBar
    if powerBar and powerBar.ticks then return powerBar.ticks end

    if not mod.db.profile.powerBar then mod.db.profile.powerBar = {} end
    mod.db.profile.powerBar.ticks = {
        mappings = {},
        defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
        defaultWidth = 1,
    }
    return mod.db.profile.powerBar.ticks
end

local function GetCurrentTicks()
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then return {} end

    local ticksCfg = mod.db.profile.powerBar and mod.db.profile.powerBar.ticks
    if not ticksCfg or not ticksCfg.mappings then return {} end

    local classMappings = ticksCfg.mappings[classID]
    return classMappings and classMappings[specIndex] or {}
end

local function SetCurrentTicks(ticks)
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then return end

    local ticksCfg = GetTicksConfig()
    if not ticksCfg.mappings[classID] then ticksCfg.mappings[classID] = {} end
    ticksCfg.mappings[classID][specIndex] = ticks
end

local function AddTick(value, color, width)
    local ticks = GetCurrentTicks()
    local ticksCfg = GetTicksConfig()
    ticks[#ticks + 1] = {
        value = value,
        color = color or ECM_CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
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

ECM.PowerBarTickMarksStore = {
    GetCurrentTicks = GetCurrentTicks,
    SetCurrentTicks = SetCurrentTicks,
    AddTick = AddTick,
    RemoveTick = RemoveTick,
    UpdateTick = UpdateTick,
    GetDefaultColor = function() return GetTicksConfig().defaultColor end,
    SetDefaultColor = function(color) GetTicksConfig().defaultColor = color end,
    GetDefaultWidth = function() return GetTicksConfig().defaultWidth end,
    SetDefaultWidth = function(width) GetTicksConfig().defaultWidth = width end,
}
