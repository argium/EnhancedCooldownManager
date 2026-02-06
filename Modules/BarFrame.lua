-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...

local BarFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.BarFrame = BarFrame
local ECM = ns.Addon
local ECMFrame = ns.Mixins.ECMFrame
local Util = ns.Util
local C = ns.Constants

-- owns:
--  StatusBar
--  Appearance (bg color, texture)
--  Text overlay
--  Tick marks

--------------------------------------------------------------------------------
-- Tick Helpers
--------------------------------------------------------------------------------

local function GetTickPool(self, poolKey)
    poolKey = poolKey or "tickPool"
    local pool = self[poolKey]
    if not pool then
        pool = {}
        self[poolKey] = pool
    end
    return pool
end

--- Ensures the tick pool has the required number of ticks.
--- Creates new ticks as needed, shows required ticks, hides extras.
---@param self ECMBarFrame
---@param count number Number of ticks needed
---@param parentFrame Frame Frame to create ticks on (e.g., bar.StatusBar or bar.TicksFrame)
---@param poolKey string|nil Key for tick pool on bar (default "tickPool")
function BarFrame:EnsureTicks(count, parentFrame, poolKey)
    assert(parentFrame, "parentFrame required for tick creation")

    local pool = GetTickPool(self, poolKey)

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
---@param self ECMBarFrame
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarFrame:HideAllTicks(poolKey)
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
---@param self ECMBarFrame
---@param maxResources number Number of resources (ticks = maxResources - 1)
---@param color ECM_Color|table|nil RGBA color (default black)
---@param tickWidth number|nil Width of each tick (default 1)
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarFrame:LayoutResourceTicks(maxResources, color, tickWidth, poolKey)
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
            local x = Util.PixelSnap(step * i)
            tick:SetPoint("LEFT", frame, "LEFT", x, 0)
            tick:SetSize(math.max(1, Util.PixelSnap(tickWidth)), barHeight)
            tick:SetColorTexture(tr, tg, tb, ta)
        end
    end
end

--- Positions ticks at specific resource values.
--- Used by PowerBar for breakpoint markers (e.g., energy thresholds).
---@param self ECMBarFrame
---@param statusBar StatusBar StatusBar to position ticks on
---@param ticks table Array of tick definitions { { value = number, color = ECM_Color, width = number }, ... }
---@param maxValue number Maximum resource value
---@param defaultColor ECM_Color Default RGBA color
---@param defaultWidth number Default tick width
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarFrame:LayoutValueTicks(statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey)
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
                tick:SetSize(math.max(1, Util.PixelSnap(tickWidthVal)), barHeight)
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
function BarFrame:GetStatusBarValues()
    Util.DebugAssert(false, "GetStatusBarValues not implemented in derived class")
    return -1, -1, -1, false
end

--- Gets the color for the status bar. Override for custom color logic.
---@return ECM_Color Color table with r, g, b, a fields
function BarFrame:GetStatusBarColor()
    local resource = UnitPowerType("player")
    local color = self.ModuleConfig and self.ModuleConfig.colors and self.ModuleConfig.colors[resource]
    return color or C.COLOR_WHITE
end

--------------------------------------------------------------------------------
-- ECMFrame Overrides
--------------------------------------------------------------------------------

function BarFrame:ShouldShow()
    -- Pass through so derived classes don't have to override ECMFrame
    return ECMFrame.ShouldShow(self)
end

--- Refreshes the bar frame layout and values.
---@param force boolean|nil If true, forces a refresh even if not needed.
---@return boolean continue True if refresh completed, false if skipped
function BarFrame:Refresh(force)
    local continue = ECMFrame.Refresh(self, force)
    if not continue then
        -- Util.Log(self.Name, "BarFrame:Refresh", "Skipping refresh")
        return false
    end
    Util.Log(self.Name, "BarFrame:Refresh", "Start")

    local frame = self.InnerFrame
    local globalConfig = self.GlobalConfig
    local moduleConfig = self.ModuleConfig

    -- Values: apply min/max before value so startup/transient states do not
    -- render full when current is zero.
    local current, max, displayValue, isFraction = self:GetStatusBarValues()
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
        Util.ApplyFont(frame.TextValue, globalConfig)
    end
    frame:SetTextVisible(showText)

    -- Texture
    local tex = Util.GetTexture((moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture)) or C.DEFAULT_STATUSBAR_TEXTURE
    frame.StatusBar:SetStatusBarTexture(tex)

    -- Status bar color
    local statusBarColor = self:GetStatusBarColor()
    frame.StatusBar:SetStatusBarColor(statusBarColor.r, statusBarColor.g, statusBarColor.b, statusBarColor.a)

    frame:Show()
    -- Util.Log(self.Name, "BarFrame:Refresh", {
    --     current = current,
    --     max = max,
    --     displayValue = displayValue,
    --     isFraction = isFraction,
    --     showText = showText,
    --     texture = tex,
    --     statusBarColor = statusBarColor,
    -- })

    return true
end

--------------------------------------------------------------------------------
-- Layout and Refresh
--------------------------------------------------------------------------------

function BarFrame:CreateFrame()
    local frame = ECMFrame.CreateFrame(self)

    -- StatusBar for value display
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints()
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

    -- Attach text methods to the frame
    function frame:SetText(text)
        if self.TextValue then
            self.TextValue:SetText(text)
        end
    end

    function frame:SetTextVisible(shown)
        if self.TextFrame then
            self.TextFrame:SetShown(shown)
        end
    end

    ECM.Log(self.Name, "BarFrame:CreateFrame", "Success")
    return frame
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function BarFrame:OnEnable()
end

function BarFrame:OnDisable()
end

function BarFrame.AddMixin(module, name)
    assert(module, "module required")
    assert(name, "name required")

    -- Copy BarFrame methods to module if not already defined
    for k, v in pairs(BarFrame) do
        if type(v) == "function" and module[k] == nil then
            module[k] = v
        end
    end

    ECMFrame.AddMixin(module, name)
    module._lastUpdate = GetTime()
end
