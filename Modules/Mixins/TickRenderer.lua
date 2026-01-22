local _, ns = ...

local Util = ns.Util

--- TickRenderer mixin: Tick pooling and positioning.
--- Handles segment dividers (SegmentBar) and value ticks (PowerBar).
local TickRenderer = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.TickRenderer = TickRenderer

--- Ensures the tick pool has the required number of ticks.
--- Creates new ticks as needed, shows required ticks, hides extras.
---@param bar Frame Bar frame to manage ticks on
---@param count number Number of ticks needed
---@param parentFrame Frame Frame to create ticks on (e.g., bar.StatusBar or bar.TicksFrame)
---@param poolKey string|nil Key for tick pool on bar (default "tickPool")
function TickRenderer.EnsureTicks(bar, count, parentFrame, poolKey)
    assert(bar, "bar frame required")
    assert(parentFrame, "parentFrame required for tick creation")

    poolKey = poolKey or "tickPool"
    bar[poolKey] = bar[poolKey] or {}
    local pool = bar[poolKey]

    -- Create/show required ticks
    for i = 1, count do
        if not pool[i] then
            local tick = parentFrame:CreateTexture(nil, "OVERLAY")
            pool[i] = tick
        end
        pool[i]:Show()
    end

    -- Hide extra ticks
    for i = count + 1, #pool do
        if pool[i] then
            pool[i]:Hide()
        end
    end
end

--- Hides all ticks in the pool.
---@param bar Frame Bar frame with tick pool
---@param poolKey string|nil Key for tick pool (default "tickPool")
function TickRenderer.HideAllTicks(bar, poolKey)
    if not bar then
        return
    end

    poolKey = poolKey or "tickPool"
    local pool = bar[poolKey]
    if not pool then
        return
    end

    for _, tick in ipairs(pool) do
        tick:Hide()
    end
end

--- Positions ticks evenly as segment dividers.
--- Used by SegmentBar to show divisions between segments.
---@param bar Frame Bar frame with tick pool
---@param maxSegments number Number of segments (ticks = maxSegments - 1)
---@param color table|nil RGBA color { r, g, b, a } (default black)
---@param tickWidth number|nil Width of each tick (default 1)
---@param poolKey string|nil Key for tick pool (default "tickPool")
function TickRenderer.LayoutSegmentTicks(bar, maxSegments, color, tickWidth, poolKey)
    if not bar then
        return
    end

    maxSegments = tonumber(maxSegments) or 0
    if maxSegments <= 1 then
        TickRenderer.HideAllTicks(bar, poolKey)
        return
    end

    local barWidth = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    poolKey = poolKey or "tickPool"
    local pool = bar[poolKey]
    if not pool then
        return
    end

    color = color or { 0, 0, 0, 1 }
    tickWidth = tickWidth or 1

    local step = barWidth / maxSegments
    local tr, tg, tb, ta = color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1

    for i, tick in ipairs(pool) do
        if tick:IsShown() then
            tick:ClearAllPoints()
            local x = Util.PixelSnap(step * i)
            tick:SetPoint("LEFT", bar, "LEFT", x, 0)
            tick:SetSize(math.max(1, Util.PixelSnap(tickWidth)), barHeight)
            tick:SetColorTexture(tr, tg, tb, ta)
        end
    end
end

--- Positions ticks at specific resource values.
--- Used by PowerBar for breakpoint markers (e.g., energy thresholds).
---@param bar Frame Bar frame with tick pool
---@param statusBar StatusBar StatusBar to position ticks on
---@param ticks table Array of tick definitions { { value = number, color = {r,g,b,a}, width = number }, ... }
---@param maxValue number Maximum resource value
---@param defaultColor table Default RGBA color
---@param defaultWidth number Default tick width
---@param poolKey string|nil Key for tick pool (default "tickPool")
function TickRenderer.LayoutValueTicks(bar, statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey)
    if not bar or not statusBar then
        return
    end

    if not ticks or #ticks == 0 or maxValue <= 0 then
        TickRenderer.HideAllTicks(bar, poolKey)
        return
    end

    local barWidth = statusBar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    poolKey = poolKey or "tickPool"
    local pool = bar[poolKey]
    if not pool then
        return
    end

    defaultColor = defaultColor or { 0, 0, 0, 0.5 }
    defaultWidth = defaultWidth or 1

    for i, tickData in ipairs(ticks) do
        local tick = pool[i]
        if tick then
            local value = tickData.value
            if value and value > 0 and value < maxValue then
                local tickColor = tickData.color or defaultColor
                local tickWidthVal = tickData.width or defaultWidth

                local x = math.floor((value / maxValue) * barWidth)
                tick:ClearAllPoints()
                tick:SetPoint("LEFT", statusBar, "LEFT", x, 0)
                tick:SetSize(math.max(1, Util.PixelSnap(tickWidthVal)), barHeight)
                tick:SetColorTexture(
                    tickColor[1] or 0,
                    tickColor[2] or 0,
                    tickColor[3] or 0,
                    tickColor[4] or 0.5
                )
                tick:Show()
            else
                tick:Hide()
            end
        end
    end
end
