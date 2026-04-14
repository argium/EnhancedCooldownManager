-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local store = ns.PowerBarTickMarksStore or {}
local PowerBarTickMarksOptions = ns.PowerBarTickMarksOptions or {}

ns.PowerBarTickMarksStore = store
ns.PowerBarTickMarksOptions = PowerBarTickMarksOptions

local function getPowerBarConfig()
    local profile = ns.Addon.db.profile
    local powerBar = profile.powerBar
    if powerBar then
        return powerBar
    end

    powerBar = {}
    profile.powerBar = powerBar
    return powerBar
end

local function getTicksConfig()
    local powerBar = getPowerBarConfig()
    if powerBar.ticks then
        return powerBar.ticks
    end

    powerBar.ticks = {
        mappings = {},
        defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
        defaultWidth = 1,
    }
    return powerBar.ticks
end

function store.GetCurrentTicks()
    local classID, specIndex = ns.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return {}
    end
    local mappings = getTicksConfig().mappings
    local classMappings = mappings and mappings[classID]
    return classMappings and classMappings[specIndex] or {}
end

function store.SetCurrentTicks(ticks)
    local classID, specIndex = ns.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then
        return
    end
    local ticksCfg = getTicksConfig()
    if not ticksCfg.mappings[classID] then
        ticksCfg.mappings[classID] = {}
    end
    ticksCfg.mappings[classID][specIndex] = ticks
end

function store.AddTick(value, color, width)
    local ticks = store.GetCurrentTicks()
    local ticksCfg = getTicksConfig()
    ticks[#ticks + 1] = {
        value = value,
        color = color or ns.CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
    store.SetCurrentTicks(ticks)
end

function store.RemoveTick(index)
    local ticks = store.GetCurrentTicks()
    if not ticks[index] then
        return
    end
    table.remove(ticks, index)
    store.SetCurrentTicks(ticks)
end

function store.UpdateTick(index, field, value)
    local ticks = store.GetCurrentTicks()
    if not ticks[index] then
        return
    end
    ticks[index][field] = value
    store.SetCurrentTicks(ticks)
end

function store.GetDefaultColor()
    return getTicksConfig().defaultColor
end

function store.SetDefaultColor(color)
    getTicksConfig().defaultColor = color
end

function store.GetDefaultWidth()
    return getTicksConfig().defaultWidth
end

function store.SetDefaultWidth(width)
    getTicksConfig().defaultWidth = width
end

StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"] = ns.OptionUtil.MakeConfirmDialog(L["TICK_MARKS_CLEAR_CONFIRM"])

local function getValueSliderRange(currentValue)
    for _, tier in ipairs(C.VALUE_SLIDER_TIERS) do
        if currentValue <= tier.ceiling then
            return tier.ceiling, tier.step
        end
    end
    local last = C.VALUE_SLIDER_TIERS[#C.VALUE_SLIDER_TIERS]
    return math.ceil(currentValue / last.step) * last.step, last.step
end

function PowerBarTickMarksOptions.RegisterSettings(SB, parentCategory)
    local categoryName = "Tick Marks"
    local category

    local function refreshCategory()
        if category then
            SB.RefreshCategory(category)
        else
            SB.RefreshCategory(categoryName)
        end
    end

    local function scheduleUpdate()
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    end

    local function clearAllTicks()
        store.SetCurrentTicks({})
        scheduleUpdate()
        refreshCategory()
    end

    local function getTickSummary()
        local _, _, localisedClassName, specName, className = ns.OptionUtil.GetCurrentClassSpec()
        local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
        local classSpecLabel = "|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown")
        local ticks = store.GetCurrentTicks()
        local count = #ticks
        if count == 0 then
            return string.format(L["NO_TICK_MARKS"], classSpecLabel)
        end
        return string.format(L["TICK_COUNT"], classSpecLabel, count)
    end

    local function buildTickCollectionItems()
        local ticks = store.GetCurrentTicks()
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
                            store.UpdateTick(index, "value", rounded)
                            scheduleUpdate()
                            refreshCategory()
                        end,
                    },
                    {
                        value = tick.width or store.GetDefaultWidth(),
                        min = 1,
                        max = 5,
                        step = 1,
                        sliderWidth = 90,
                        valueWidth = 18,
                        editWidth = 34,
                        onValueChanged = function(rounded)
                            store.UpdateTick(index, "width", rounded)
                            scheduleUpdate()
                            refreshCategory()
                        end,
                    },
                },
                color = {
                    value = tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR,
                    onClick = function()
                        local current = tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
                        ns.OptionUtil.OpenColorPicker(current, true, function(color)
                            store.UpdateTick(index, "color", color)
                            scheduleUpdate()
                            refreshCategory()
                        end)
                    end,
                },
                remove = {
                    text = L["REMOVE"],
                    onClick = function()
                        store.RemoveTick(index)
                        scheduleUpdate()
                        refreshCategory()
                    end,
                },
            }
        end

        return items
    end

    SB.RegisterPage({
        name = categoryName,
        parentCategory = parentCategory,
        rows = {
            {
                id = "tickMarksPageActions",
                type = "pageActions",
                name = categoryName,
                actions = {
                    {
                        text = SETTINGS_DEFAULTS,
                        width = 100,
                        enabled = function()
                            return #store.GetCurrentTicks() > 0
                        end,
                        onClick = function()
                            StaticPopup_Show("ECM_CONFIRM_CLEAR_TICKS", nil, nil, {
                                onAccept = clearAllTicks,
                            })
                        end,
                    },
                },
            },
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
                id = "summary",
                type = "info",
                name = "",
                value = getTickSummary,
                wide = true,
                multiline = true,
                height = 28,
            },
            {
                id = "defaultColor",
                type = "color",
                key = "tickMarksDefaultColor",
                name = L["DEFAULT_COLOR"],
                default = C.DEFAULT_POWERBAR_TICK_COLOR,
                get = function()
                    return store.GetDefaultColor()
                end,
                set = function(color)
                    store.SetDefaultColor(color)
                end,
                onSet = function()
                    refreshCategory()
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
                    return store.GetDefaultWidth()
                end,
                set = function(width)
                    store.SetDefaultWidth(width)
                end,
                onSet = function()
                    refreshCategory()
                end,
            },
            {
                id = "addTick",
                type = "button",
                name = L["ADD_TICK_MARK"],
                buttonText = L["ADD"],
                onClick = function()
                    store.AddTick(50, nil, nil)
                    scheduleUpdate()
                    refreshCategory()
                end,
            },
            {
                id = "tickCollection",
                type = "list",
                variant = "editor",
                height = 320,
                rowHeight = C.SCROLL_ROW_HEIGHT_WITH_CONTROLS,
                items = buildTickCollectionItems,
            },
        },
    })

    category = SB.GetSubcategory(categoryName)
end
