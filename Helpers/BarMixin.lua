-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local FrameUtil = ECM.FrameUtil
local BarMixin = {}
ECM.BarMixin = BarMixin

local BarMixinProto = setmetatable({}, { __index = ECM.FrameMixin.Proto })

--------------------------------------------------------------------------------
-- Tick Helpers
--------------------------------------------------------------------------------

--- Ensures the tick pool has the required number of ticks.
--- Creates new ticks as needed, shows required ticks, hides extras.
---@param self BarMixin
---@param count number Number of ticks needed
---@param parentFrame Frame Frame to create ticks on (e.g., bar.StatusBar or bar.TicksFrame)
---@param poolKey string|nil Key for tick pool on bar (default "tickPool")
function BarMixinProto:EnsureTicks(count, parentFrame, poolKey)
    assert(parentFrame, "parentFrame required for tick creation")

    poolKey = poolKey or "tickPool"
    local pool = self[poolKey]
    if not pool then
        pool = {}
        self[poolKey] = pool
    end

    for i = 1, count do
        if not pool[i] then
            local tick = parentFrame:CreateTexture(nil, "OVERLAY")
            pool[i] = tick
        end
        pool[i]:Show()
    end

    for i = count + 1, #pool do
        local tick = pool[i]
        if tick then
            tick:Hide()
        end
    end
end

--- Hides all ticks in the pool.
---@param self BarMixin
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarMixinProto:HideAllTicks(poolKey)
    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    for i = 1, #pool do
        pool[i]:Hide()
    end
end

--- Positions ticks evenly as resource dividers.
--- Used by ResourceBar to show divisions between resources.
---@param self BarMixin
---@param maxResources number Number of resources (ticks = maxResources - 1)
---@param color ECM_Color|table|nil RGBA color (default black)
---@param tickWidth number|nil Width of each tick (default 1)
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarMixinProto:LayoutResourceTicks(maxResources, color, tickWidth, poolKey)
    maxResources = tonumber(maxResources) or 0
    if maxResources <= 1 then
        self:HideAllTicks(poolKey)
        return
    end

    local frame = self.InnerFrame
    local barWidth = frame:GetWidth()
    local barHeight = frame:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    color = color or { r = 0, g = 0, b = 0, a = 1 }
    tickWidth = tickWidth or 1

    local step = barWidth / maxResources
    local tr, tg, tb, ta = color.r, color.g, color.b, color.a

    for i = 1, #pool do
        local tick = pool[i]
        if tick and tick:IsShown() then
            tick:ClearAllPoints()
            local x = ECM.PixelSnap(step * i)
            tick:SetPoint("LEFT", frame, "LEFT", x, 0)
            tick:SetSize(math.max(1, ECM.PixelSnap(tickWidth)), barHeight)
            tick:SetColorTexture(tr, tg, tb, ta)
        end
    end
end

--- Positions ticks at specific resource values.
--- Used by PowerBar for breakpoint markers (e.g., energy thresholds).
---@param self BarMixin
---@param statusBar StatusBar StatusBar to position ticks on
---@param ticks table Array of tick definitions { { value = number, color = ECM_Color, width = number }, ... }
---@param maxValue number Maximum resource value
---@param defaultColor ECM_Color Default RGBA color
---@param defaultWidth number Default tick width
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarMixinProto:LayoutValueTicks(statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey)
    if not statusBar then
        return
    end

    if not ticks or #ticks == 0 or maxValue <= 0 then
        self:HideAllTicks(poolKey)
        return
    end

    local frame = self.InnerFrame
    local barWidth = statusBar:GetWidth()
    local barHeight = frame:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    defaultColor = defaultColor or { r = 0, g = 0, b = 0, a = 0.5 }
    defaultWidth = defaultWidth or 1

    for i = 1, #ticks do
        local tick = pool[i]
        local tickData = ticks[i]
        if tick and tickData then
            local value = tickData.value
            if value and value > 0 and value < maxValue then
                local tickColor = tickData.color or defaultColor
                local tickWidthVal = tickData.width or defaultWidth
                local tr, tg, tb = tickColor.r, tickColor.g, tickColor.b
                local ta = tickColor.a or (defaultColor.a or 0.5)

                local x = math.floor((value / maxValue) * barWidth)
                tick:ClearAllPoints()
                tick:SetPoint("LEFT", statusBar, "LEFT", x, 0)
                tick:SetSize(math.max(1, ECM.PixelSnap(tickWidthVal)), barHeight)
                tick:SetColorTexture(tr, tg, tb, ta)
                tick:Show()
            else
                tick:Hide()
            end
        end
    end
end

--- Gets the current value for the bar.
---@return number|nil current
---@return number|nil max
---@return number|nil displayValue
---@return boolean isFraction valueType
function BarMixinProto:GetStatusBarValues()
    ECM.DebugAssert(false, "GetStatusBarValues not implemented in derived class")
    return -1, -1, -1, false
end

--- Gets the color for the status bar. Override for custom color logic.
---@return ECM_Color Color table with r, g, b, a fields
function BarMixinProto:GetStatusBarColor()
    local powerType = UnitPowerType("player")
    local moduleConfig = self:GetModuleConfig()
    local color = moduleConfig and moduleConfig.colors and moduleConfig.colors[powerType]
    return color or ECM.Constants.COLOR_WHITE
end

--- Refreshes the bar frame layout and values.
--- @param why string|nil Reason for refresh (for logging/debugging).
--- @param force boolean|nil If true, forces a refresh even if not needed.
--- @return boolean continue True if refresh completed, false if skipped
function BarMixinProto:Refresh(why, force)
    -- call the frame mixin to check pre-conditions
    if not ECM.FrameMixin.Proto.Refresh(self, why, force) then
        return false
    end

    local frame = self.InnerFrame
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()

    -- Values: apply min/max before value so startup/transient states do not
    -- render full when current is zero.
    local current, max, displayValue = self:GetStatusBarValues()
    if max == nil then
        max = 1
    end
    if current == nil then
        current = 0
    end

    frame.StatusBar:SetMinMaxValues(0, max)
    frame.StatusBar:SetValue(current)

    -- Text overlay
    local showText = moduleConfig.showText ~= false
    if showText and frame.TextValue then
        frame:SetText(displayValue)

        -- Apply font settings
        ECM.ApplyFont(frame.TextValue, globalConfig, moduleConfig)
    end
    frame:SetTextVisible(showText)

    -- Texture
    local tex = ECM.GetTexture((moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture))
        or ECM.Constants.DEFAULT_STATUSBAR_TEXTURE
    FrameUtil.LazySetStatusBarTexture(frame.StatusBar, tex)

    -- Status bar color
    local statusBarColor = self:GetStatusBarColor()
    FrameUtil.LazySetStatusBarColor(
        frame.StatusBar,
        statusBarColor.r,
        statusBarColor.g,
        statusBarColor.b,
        statusBarColor.a
    )

    frame:Show()

    if ECM.IsDebugEnabled() then
        ECM.Log(self.Name, "Bar frame refresh complete (" .. (why or "") .. ").")
    end

    -- Hook: modules override _OnBarRefreshed for post-refresh logic
    -- (e.g. tick layout) without needing to manually call super.
    if self._OnBarRefreshed then
        self:_OnBarRefreshed(why)
    end

    return true
end

function BarMixinProto:CreateFrame()
    local frame = ECM.FrameMixin.Proto.CreateFrame(self)

    -- StatusBar for value display
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints(frame)
    frame.StatusBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- TicksFrame for tick marks
    frame.TicksFrame = CreateFrame("Frame", nil, frame)
    frame.TicksFrame:SetAllPoints(frame)
    frame.TicksFrame:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Text overlay for displaying values
    frame.TextFrame = CreateFrame("Frame", nil, frame)
    frame.TextFrame:SetAllPoints(frame)
    frame.TextFrame:SetFrameLevel(frame.StatusBar:GetFrameLevel() + 10)

    frame.TextValue = frame.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.TextValue:SetPoint("CENTER", frame.TextFrame, "CENTER", 0, 0)
    frame.TextValue:SetJustifyH("CENTER")
    frame.TextValue:SetJustifyV("MIDDLE")

    function frame.SetText(_, text)
        frame.TextValue:SetText(text)
    end

    function frame.SetTextVisible(_, shown)
        frame.TextFrame:SetShown(shown)
    end

    ECM.Log(self.Name, "Frame created.")
    return frame
end

BarMixin.Proto = BarMixinProto
setmetatable(BarMixin, { __index = BarMixinProto })

--- Applies bar, frame, and common module mixins to the target via metatable.
--- Idempotent — safe to call more than once (no-op after first application).
function BarMixin.AddMixin(module, name)
    ECM.MixinUtil.Apply(module, BarMixinProto, name, function(target)
        target._lastUpdate = GetTime()
    end)
end
