-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, _ = ...
local C = ECM.Constants
local OB = ECM.OptionBuilder

local function GetStore()
    return ECM.PowerBarTickMarksStore
end

local function GenerateTickArgs()
    local args = {}
    local store = GetStore()
    local ticks = store.GetCurrentTicks()

    for i, tick in ipairs(ticks) do
        local orderBase = i * 10

        args["tickHeader" .. i] = OB.MakeHeader({
            name = "Tick " .. i,
            order = orderBase,
        })

        args["tickValue" .. i] = OB.MakeControl({
            type = "range",
            name = "Value",
            desc = "Resource value at which to display this tick mark.",
            order = orderBase + 1,
            width = 1.2,
            min = 1,
            max = 200,
            step = 1,
            get = function()
                local current = store.GetCurrentTicks()
                return current[i] and current[i].value or 50
            end,
            set = function(_, val)
                store.UpdateTick(i, "value", val)
            end,
            notify = true,
        })

        args["tickWidth" .. i] = OB.MakeControl({
            type = "range",
            name = "Width",
            desc = "Width of the tick mark in pixels.",
            order = orderBase + 2,
            width = 0.8,
            min = 1,
            max = 5,
            step = 1,
            get = function()
                local current = store.GetCurrentTicks()
                return current[i] and current[i].width or store.GetDefaultWidth()
            end,
            set = function(_, val)
                store.UpdateTick(i, "width", val)
            end,
            notify = true,
        })

        args["tickColor" .. i] = OB.MakeControl({
            type = "color",
            name = "Color",
            desc = "Color of this tick mark.",
            order = orderBase + 3,
            width = 0.6,
            hasAlpha = true,
            get = function()
                local current = store.GetCurrentTicks()
                local c = current[i] and current[i].color or store.GetDefaultColor()
                return c.r or 0, c.g or 0, c.b or 0, c.a or 0.5
            end,
            set = function(_, r, g, b, a)
                store.UpdateTick(i, "color", { r = r, g = g, b = b, a = a })
            end,
            notify = true,
        })

        args["tickRemove" .. i] = OB.MakeActionButton({
            name = "X",
            desc = "Remove this tick mark.",
            order = orderBase + 4,
            width = 0.3,
            confirm = true,
            confirmText = "Remove tick mark at value " .. (tick.value or "?") .. "?",
            func = function()
                store.RemoveTick(i)
            end,
            notify = true,
        })
    end

    return args
end

local function GetOptionsGroup()
    local store = GetStore()

    return OB.MakeInlineGroup("", 42, {
        description = OB.MakeDescription({
            name = "Tick marks allow you to place markers at specific values on the power bar. This can be useful for tracking when you will have enough power to cast important abilities.\n\n"
                .. "These settings are saved per class and specialization.\n\n",
            order = 2,
            fontSize = "medium",
        }),
        currentSpec = OB.MakeDescription({
            name = function()
                local _, _, className, specName = ECM.OptionUtil.GetCurrentClassSpec()
                return "|cff00ff00Current: " .. (className or "Unknown") .. " " .. specName .. "|r"
            end,
            order = 3,
        }),
        spacer1 = OB.MakeSpacer(4),
        defaultColor = OB.MakeControl({
            type = "color",
            name = "Default color",
            desc = "Default color for new tick marks.",
            order = 10,
            width = "normal",
            hasAlpha = true,
            get = function()
                local c = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
                return c.r or 0, c.g or 0, c.b or 0, c.a or 0.5
            end,
            set = function(_, r, g, b, a)
                store.SetDefaultColor({ r = r, g = g, b = b, a = a })
            end,
        }),
        defaultWidth = OB.MakeControl({
            type = "range",
            name = "Default width",
            desc = "Default width for new tick marks.",
            order = 11,
            width = "normal",
            min = 1,
            max = 5,
            step = 1,
            get = function()
                return store.GetDefaultWidth() or 1
            end,
            set = function(_, val)
                store.SetDefaultWidth(val)
            end,
        }),
        spacer2 = OB.MakeSpacer(19),
        tickCount = OB.MakeDescription({
            name = function()
                local ticks = store.GetCurrentTicks()
                local count = #ticks
                if count == 0 then
                    return "|cffaaaaaa(No tick marks configured for this spec)|r"
                end
                return string.format("|cff888888%d tick mark(s) configured|r", count)
            end,
            order = 21,
        }),
        addTick = OB.MakeActionButton({
            name = "Add Tick Mark",
            desc = "Add a new tick mark for the current spec.",
            order = 22,
            width = "normal",
            func = function()
                store.AddTick(50, nil, nil)
            end,
            notify = true,
        }),
        spacer3 = OB.MakeSpacer(23),
        ticks = OB.MakeInlineGroup("", 30, GenerateTickArgs()),
        spacer4 = OB.MakeSpacer(90),
        clearAll = OB.MakeActionButton({
            name = "Clear All Ticks",
            desc = "Remove all tick marks for the current spec.",
            order = 100,
            width = "normal",
            confirm = true,
            confirmText = "Are you sure you want to remove all tick marks for this spec?",
            disabled = function()
                return #store.GetCurrentTicks() == 0
            end,
            func = function()
                store.SetCurrentTicks({})
            end,
            notify = true,
        }),
    })
end

ECM.PowerBarTickMarksOptions = {
    GetOptionsGroup = GetOptionsGroup,
}
