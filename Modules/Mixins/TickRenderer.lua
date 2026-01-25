local _, ns = ...

local Util = ns.Util

--- TickRenderer mixin: Tick pooling and positioning.
--- Handles segment dividers (SegmentBar) and value ticks (PowerBar).
--- Methods are attached directly to bars via AttachTo().
local TickRenderer = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.TickRenderer = TickRenderer

--- Attaches tick functionality to a bar frame.
--- Creates TicksFrame container and attaches tick methods to the bar.
---@param bar Frame Bar frame to attach tick functionality to
function TickRenderer.AttachTo(bar)
    assert(bar, "bar frame required")

    -- Create ticks frame container
    bar.TicksFrame = CreateFrame("Frame", nil, bar)
    bar.TicksFrame:SetAllPoints(bar)
    bar.TicksFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.ticks = {}

    --- Ensures the tick pool has the required number of ticks.
    --- Creates new ticks as needed, shows required ticks, hides extras.
    ---@param self Frame
    ---@param count number Number of ticks needed
    ---@param parentFrame Frame Frame to create ticks on (e.g., bar.StatusBar or bar.TicksFrame)
    ---@param poolKey string|nil Key for tick pool on bar (default "tickPool")
    function bar:EnsureTicks(count, parentFrame, poolKey)
        assert(parentFrame, "parentFrame required for tick creation")

        poolKey = poolKey or "tickPool"
        self[poolKey] = self[poolKey] or {}
        local pool = self[poolKey]

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
    ---@param self Frame
    ---@param poolKey string|nil Key for tick pool (default "tickPool")
    function bar:HideAllTicks(poolKey)
        poolKey = poolKey or "tickPool"
        local pool = self[poolKey]
        if not pool then
            return
        end

        for _, tick in ipairs(pool) do
            tick:Hide()
        end
    end

    --- Positions ticks evenly as segment dividers.
    --- Used by SegmentBar to show divisions between segments.
    ---@param self Frame
    ---@param maxSegments number Number of segments (ticks = maxSegments - 1)
    ---@param color table|nil RGBA color { r, g, b, a } (default black)
    ---@param tickWidth number|nil Width of each tick (default 1)
    ---@param poolKey string|nil Key for tick pool (default "tickPool")
    function bar:LayoutSegmentTicks(maxSegments, color, tickWidth, poolKey)
        maxSegments = tonumber(maxSegments) or 0
        if maxSegments <= 1 then
            self:HideAllTicks(poolKey)
            return
        end

        local barWidth = self:GetWidth()
        local barHeight = self:GetHeight()
        if barWidth <= 0 or barHeight <= 0 then
            return
        end

        poolKey = poolKey or "tickPool"
        local pool = self[poolKey]
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
                tick:SetPoint("LEFT", self, "LEFT", x, 0)
                tick:SetSize(math.max(1, Util.PixelSnap(tickWidth)), barHeight)
                tick:SetColorTexture(tr, tg, tb, ta)
            end
        end
    end

    --- Positions ticks at specific resource values.
    --- Used by PowerBar for breakpoint markers (e.g., energy thresholds).
    ---@param self Frame
    ---@param statusBar StatusBar StatusBar to position ticks on
    ---@param ticks table Array of tick definitions { { value = number, color = {r,g,b,a}, width = number }, ... }
    ---@param maxValue number Maximum resource value
    ---@param defaultColor table Default RGBA color
    ---@param defaultWidth number Default tick width
    ---@param poolKey string|nil Key for tick pool (default "tickPool")
    function bar:LayoutValueTicks(statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey)
        if not statusBar then
            return
        end

        if not ticks or #ticks == 0 or maxValue <= 0 then
            self:HideAllTicks(poolKey)
            return
        end

        local barWidth = statusBar:GetWidth()
        local barHeight = self:GetHeight()
        if barWidth <= 0 or barHeight <= 0 then
            return
        end

        poolKey = poolKey or "tickPool"
        local pool = self[poolKey]
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
end
