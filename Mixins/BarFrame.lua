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

-- local function GetTickPool(self, poolKey)
--     poolKey = poolKey or "tickPool"
--     local pool = self[poolKey]
--     if not pool then
--         pool = {}
--         self[poolKey] = pool
--     end
--     return pool
-- end



--- Adds a text overlay to an existing bar frame.
--- Creates TextFrame container and TextValue FontString.
--- Text methods (SetText, SetTextVisible) are attached to the bar.
---@param bar ECMBarFrame Bar frame to add text overlay to
---@param profile table|nil Profile for font settings
---@return FontString textValue The created FontString
-- function BarFrame.AddTextOverlay(bar, profile)
--     assert(bar, "bar frame required")

--     ---@cast bar ECMBarFrame

--     local textFrame = CreateFrame("Frame", nil, bar)
--     textFrame:SetAllPoints(bar)
--     textFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 10)
--     bar.TextFrame = textFrame

--     local textValue = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
--     textValue:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
--     textValue:SetJustifyH("CENTER")
--     textValue:SetJustifyV("MIDDLE")
--     textValue:SetText("0")
--     bar.TextValue = textValue

--     if profile then
--         BarFrame.ApplyFont(bar.TextValue, profile)
--     end

--     -- Attach text methods

--     --- Sets the text value on a bar with text overlay.
--     ---@param self ECMBarFrame
--     ---@param text string Text to display
--     function bar:SetText(text)
--         if self.TextValue then
--             self.TextValue:SetText(text)
--         end
--     end

--     --- Shows or hides the text overlay.
--     ---@param self ECMBarFrame
--     ---@param shown boolean Whether to show the text
--     function bar:SetTextVisible(shown)
--         if self.TextFrame then
--             self.TextFrame:SetShown(shown)
--         end
--     end

--     return bar.TextValue
-- end

--------------------------------------------------------------------------------
-- Tick Helpers
--------------------------------------------------------------------------------

-- --- Attaches tick functionality to a bar frame.
-- --- Creates the tick container frame if needed.
-- ---@param bar ECMBarFrame Bar frame to attach ticks to
-- ---@return Frame ticksFrame Tick container frame
-- function BarFrame.AttachTicks(bar)
--     assert(bar, "bar frame required")

--     ---@cast bar ECMBarFrame

--     if bar.TicksFrame then
--         return bar.TicksFrame
--     end

--     bar.TicksFrame = CreateFrame("Frame", nil, bar)
--     bar.TicksFrame:SetAllPoints(bar)
--     bar.TicksFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
--     bar.ticks = bar.ticks or {}

--     return bar.TicksFrame
-- end

-- --- Ensures the tick pool has the required number of ticks.
-- --- Creates new ticks as needed, shows required ticks, hides extras.
-- ---@param self ECMBarFrame
-- ---@param count number Number of ticks needed
-- ---@param parentFrame Frame Frame to create ticks on (e.g., bar.StatusBar or bar.TicksFrame)
-- ---@param poolKey string|nil Key for tick pool on bar (default "tickPool")
-- function BarFrame:EnsureTicks(count, parentFrame, poolKey)
--     assert(parentFrame, "parentFrame required for tick creation")

--     local pool = GetTickPool(self, poolKey)

--     for i = 1, count do
--         if not pool[i] then
--             local tick = parentFrame:CreateTexture(nil, "OVERLAY")
--             pool[i] = tick
--         end
--         pool[i]:Show()
--     end

--     for i = count + 1, #pool do
--         local tick = pool[i]
--         if tick then
--             tick:Hide()
--         end
--     end
-- end

-- --- Hides all ticks in the pool.
-- ---@param self ECMBarFrame
-- ---@param poolKey string|nil Key for tick pool (default "tickPool")
-- function BarFrame:HideAllTicks(poolKey)
--     local pool = self[poolKey or "tickPool"]
--     if not pool then
--         return
--     end

--     for i = 1, #pool do
--         pool[i]:Hide()
--     end
-- end

-- --- Positions ticks evenly as resource dividers.
-- --- Used by ResourceBar to show divisions between resources.
-- ---@param self ECMBarFrame
-- ---@param maxResources number Number of resources (ticks = maxResources - 1)
-- ---@param color ECM_Color|table|nil RGBA color (default black)
-- ---@param tickWidth number|nil Width of each tick (default 1)
-- ---@param poolKey string|nil Key for tick pool (default "tickPool")
-- function BarFrame:LayoutResourceTicks(maxResources, color, tickWidth, poolKey)
--     maxResources = tonumber(maxResources) or 0
--     if maxResources <= 1 then
--         self:HideAllTicks(poolKey)
--         return
--     end

--     local barWidth = self:GetWidth()
--     local barHeight = self:GetHeight()
--     if barWidth <= 0 or barHeight <= 0 then
--         return
--     end

--     local pool = self[poolKey or "tickPool"]
--     if not pool then
--         return
--     end

--     color = color or { r = 0, g = 0, b = 0, a = 1 }
--     tickWidth = tickWidth or 1

--     local step = barWidth / maxResources
--     local tr, tg, tb, ta = RequireColor(color, 1)

--     for i = 1, #pool do
--         local tick = pool[i]
--         if tick and tick:IsShown() then
--             tick:ClearAllPoints()
--             local x = Util.PixelSnap(step * i)
--             tick:SetPoint("LEFT", self, "LEFT", x, 0)
--             tick:SetSize(math.max(1, Util.PixelSnap(tickWidth)), barHeight)
--             tick:SetColorTexture(tr, tg, tb, ta)
--         end
--     end
-- end

-- --- Positions ticks at specific resource values.
-- --- Used by PowerBar for breakpoint markers (e.g., energy thresholds).
-- ---@param self ECMBarFrame
-- ---@param statusBar StatusBar StatusBar to position ticks on
-- ---@param ticks table Array of tick definitions { { value = number, color = ECM_Color, width = number }, ... }
-- ---@param maxValue number Maximum resource value
-- ---@param defaultColor ECM_Color Default RGBA color
-- ---@param defaultWidth number Default tick width
-- ---@param poolKey string|nil Key for tick pool (default "tickPool")
-- function BarFrame:LayoutValueTicks(statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey)
--     if not statusBar then
--         return
--     end

--     if not ticks or #ticks == 0 or maxValue <= 0 then
--         self:HideAllTicks(poolKey)
--         return
--     end

--     local barWidth = statusBar:GetWidth()
--     local barHeight = self:GetHeight()
--     if barWidth <= 0 or barHeight <= 0 then
--         return
--     end

--     local pool = self[poolKey or "tickPool"]
--     if not pool then
--         return
--     end

--     defaultColor = defaultColor or { r = 0, g = 0, b = 0, a = 0.5 }
--     defaultWidth = defaultWidth or 1

--     for i = 1, #ticks do
--         local tick = pool[i]
--         local tickData = ticks[i]
--         if tick and tickData then
--             local value = tickData.value
--             if value and value > 0 and value < maxValue then
--                 local tickColor = tickData.color or defaultColor
--                 local tickWidthVal = tickData.width or defaultWidth
--                 local tr, tg, tb, ta = RequireColor(tickColor, defaultColor.a or 0.5)

--                 local x = math.floor((value / maxValue) * barWidth)
--                 tick:ClearAllPoints()
--                 tick:SetPoint("LEFT", statusBar, "LEFT", x, 0)
--                 tick:SetSize(math.max(1, Util.PixelSnap(tickWidthVal)), barHeight)
--                 tick:SetColorTexture(tr, tg, tb, ta)
--                 tick:Show()
--             else
--                 tick:Hide()
--             end
--         end
--     end
-- end

--- Gets the color for the player's resource from config.
--- @param configSection table|nil Configuration section for the bar
--- @return ECM_Color Color table
local function GetColorForPlayerResource(configSection)
    local resource = UnitPowerType("player")
    local color = configSection and configSection.colors[resource]
    Util.DebugAssert(color, "Color for resource " .. tostring(resource) .. " not defined in config")
    return color or C.COLOR_WHITE
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

--- Refreshes the frame if enough time has passed since the last update.
--- Uses the global `updateFrequency` setting to throttle refresh calls.
---@return boolean refreshed True if Refresh() was called, false if skipped due to throttling
function BarFrame:ThrottledRefresh()
    -- TODO: should this move into ECMFrame?
    local config = self:GetGlobalConfig()
    local freq = (config and config.updateFrequency and tonumber(config.updateFrequency)) or C.Defaults.global.updateFrequency
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end

    self:Refresh()
    self._lastUpdate = GetTime()
    return true
end

function BarFrame:Refresh(force)  -- TODO: Refresh needs to be decoupled from the event handler. The check below is for the Power Bar, too.
    local continue = ECMFrame.Refresh(self)
    if not continue or unitID ~= "player" then
        Util.Log(self.Name, "BarFrame:Refresh", "Skipping refresh due to event/unitID", { event = event, unitID = unitID })
        return false
    end
    Util.Log(self.Name, "BarFrame:Refresh", "Starting refresh")

    local frame = self:GetInnerFrame()
    local globalConfig = self:GetGlobalConfig()
    local configSection = self:GetConfigSection()

    -- Values
    local current, max, displayValue, isFraction = self:GetStatusBarValues()
    frame.StatusBar:SetValue(current)
    frame.StatusBar:SetMinMaxValues(0, max)

    -- Text
    if isFraction then
        frame:SetText(string.format("%.0f%%", displayValue))
    else
        frame:SetText(tostring(displayValue))
    end
    frame:SetTextVisible(configSection.showText ~= false)

    -- TODO: apply font

    -- Texture
    -- TODO: create a better mixin for tracking changes on frames
    local tex = Util.GetTexture((configSection and configSection.texture) or (globalConfig and globalConfig.texture)) or C.DEFAULT_STATUSBAR_TEXTURE
    frame.StatusBar:SetStatusBarTexture(tex)

    -- TODO: segments

    -- Status bar color
    local statusBarColor = GetColorForPlayerResource(configSection)
    frame.StatusBar:SetStatusBarColor(statusBarColor.r, statusBarColor.g, statusBarColor.b)

    frame:Show()
    ECM.Log(self:GetName(), "BarFrame:Refresh", {
        current = current,
        max = max,
        displayValue = displayValue,
        isFraction = isFraction,
        texture = tex,
        color = statusBarColor,
    })
end

function BarFrame:CreateFrame()
    local frame = ECMFrame.CreateFrame(self)

    -- StatusBar for value display
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints()
    frame.StatusBar:SetFrameLevel(frame:GetFrameLevel() + 1)
    ECM.Log(self.Name, "BarFrame:CreateFrame", "Success")
    return frame
end

function BarFrame:ShouldShow()
    -- Pass through so derived classes don't have to override ECMFrame
    return ECMFrame.ShouldShow(self)
end

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
