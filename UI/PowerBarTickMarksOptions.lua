-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local PowerBarTickMarksOptions = ns.PowerBarTickMarksOptions or {}

ns.PowerBarTickMarksOptions = PowerBarTickMarksOptions

local function getPowerBarConfig()
    local profile = ns.Addon.db.profile
    local powerBar = profile.powerBar
    if not powerBar then
        powerBar = {}
        profile.powerBar = powerBar
    end
    return powerBar
end

local function getTicksConfig()
    local powerBar = getPowerBarConfig()
    local ticks = powerBar.ticks
    if not ticks then
        ticks = {
            mappings = {},
            defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
            defaultWidth = 1,
        }
        powerBar.ticks = ticks
    end
    return ticks
end

local function getCurrentTicks()
    local classID, specIndex = ns.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return {}
    end
    local classMappings = getTicksConfig().mappings[classID]
    return classMappings and classMappings[specIndex] or {}
end

local function setCurrentTicks(ticks)
    local classID, specIndex = ns.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return
    end
    local ticksCfg = getTicksConfig()
    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        classMappings = {}
        ticksCfg.mappings[classID] = classMappings
    end
    classMappings[specIndex] = ticks
end

local function addTick(value, color, width)
    local ticks = getCurrentTicks()
    local ticksCfg = getTicksConfig()
    ticks[#ticks + 1] = {
        value = value,
        color = color or ns.CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
    setCurrentTicks(ticks)
end

local function removeTick(index)
    local ticks = getCurrentTicks()
    if not ticks[index] then
        return
    end
    table.remove(ticks, index)
    setCurrentTicks(ticks)
end

local function updateTick(index, field, value)
    local ticks = getCurrentTicks()
    if not ticks[index] then
        return
    end
    ticks[index][field] = value
    setCurrentTicks(ticks)
end

local function getDefaultColor()
    return getTicksConfig().defaultColor
end

local function setDefaultColor(color)
    getTicksConfig().defaultColor = color
end

local function getDefaultWidth()
    return getTicksConfig().defaultWidth
end

local function setDefaultWidth(width)
    getTicksConfig().defaultWidth = width
end

local registeredPage
function PowerBarTickMarksOptions.SetRegisteredPage(page)
    registeredPage = page
end

local function refreshPage()
    if registeredPage then
        registeredPage:Refresh()
    end
end

local function getValueSliderRange(currentValue)
    for _, tier in ipairs(C.VALUE_SLIDER_TIERS) do
        if currentValue <= tier.ceiling then
            return tier.ceiling, tier.step
        end
    end
    local last = C.VALUE_SLIDER_TIERS[#C.VALUE_SLIDER_TIERS]
    return math.ceil(currentValue / last.step) * last.step, last.step
end

local function scheduleUpdate()
    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
end

local function buildTickCollectionItems()
    local ticks = getCurrentTicks()
    local items = {}

    for index, tick in ipairs(ticks) do
        items[#items + 1] = {
            label = string.format(L["TICK_N"], index),
            fields = {
                {
                    value = tick.value or 50,
                    min = 1,
                    max = 200,
                    step = 1,
                    sliderWidth = 150,
                    valueWidth = 50,
                    editWidth = 60,
                    getRange = function(_, targetValue)
                        local ceiling, step = getValueSliderRange(math.max(1, targetValue or tick.value or 50))
                        return 1, ceiling, step
                    end,
                    onValueChanged = function(rounded)
                        updateTick(index, "value", rounded)
                        scheduleUpdate()
                        refreshPage()
                    end,
                },
                {
                    value = tick.width or getDefaultWidth(),
                    min = 1,
                    max = 5,
                    step = 1,
                    sliderWidth = 90,
                    valueWidth = 18,
                    editWidth = 34,
                    onValueChanged = function(rounded)
                        updateTick(index, "width", rounded)
                        scheduleUpdate()
                        refreshPage()
                    end,
                },
            },
            color = {
                value = tick.color or getDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR,
                onClick = function()
                    local current = tick.color or getDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
                    ns.OptionUtil.OpenColorPicker(current, true, function(color)
                        updateTick(index, "color", color)
                        scheduleUpdate()
                        refreshPage()
                    end)
                end,
            },
            remove = {
                text = L["REMOVE"],
                onClick = function()
                    removeTick(index)
                    scheduleUpdate()
                    refreshPage()
                end,
            },
        }
    end

    return items
end

PowerBarTickMarksOptions.key = "tickMarks"
PowerBarTickMarksOptions.name = "Tick Marks"
PowerBarTickMarksOptions.rows = {
    {
        id = "description",
        type = "info",
        name = "",
        value = L["TICK_MARKS_DESC"],
        wide = true,
        multiline = true,
        height = 36,
    },
    {
        id = "defaultColor",
        type = "color",
        key = "tickMarksDefaultColor",
        name = L["DEFAULT_COLOR"],
        default = C.DEFAULT_POWERBAR_TICK_COLOR,
        get = function()
            return getDefaultColor()
        end,
        set = function(color)
            setDefaultColor(color)
        end,
        onSet = function(ctx)
            ctx.page:Refresh()
        end,
    },
    {
        id = "defaultWidth",
        type = "slider",
        key = "tickMarksDefaultWidth",
        name = L["DEFAULT_WIDTH"],
        default = 1,
        min = 1,
        max = 5,
        step = 1,
        get = function()
            return getDefaultWidth()
        end,
        set = function(width)
            setDefaultWidth(width)
        end,
        onSet = function(ctx)
            ctx.page:Refresh()
        end,
    },
    {
        id = "addTick",
        type = "button",
        name = L["ADD_TICK_MARK"],
        buttonText = L["ADD"],
        onClick = function(ctx)
            addTick(50, nil, nil)
            scheduleUpdate()
            ctx.page:Refresh()
        end,
    },
    {
        id = "tickCollection",
        type = "list",
        variant = "editor",
        height = 320,
        rowHeight = 34,
        items = buildTickCollectionItems,
    },
}
