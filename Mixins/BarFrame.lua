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
local FONT_CACHE = setmetatable({}, { __mode = "k" })

-- owns:
--  StatusBar
--  Appearance (bg color, texture)
--  Text overlay
--  Tick marks

local function GetTickPool(self, poolKey)
    poolKey = poolKey or "tickPool"
    local pool = self[poolKey]
    if not pool then
        pool = {}
        self[poolKey] = pool
    end
    return pool
end

--- Applies font settings to a FontString.
---@param fontString FontString
---@param profile table|nil Full profile table
function BarFrame.ApplyFont(fontString, profile)
    if not fontString then
        return
    end

    local gbl = profile and profile.global
    local fontPath = BarFrame.GetFontPath(gbl and gbl.font)
    local fontSize = (gbl and gbl.fontSize) or 11
    local fontOutline = (gbl and gbl.fontOutline) or "OUTLINE"

    if fontOutline == "NONE" then
        fontOutline = ""
    end

    local hasShadow = gbl and gbl.fontShadow
    local fontKey = table.concat({ fontPath, tostring(fontSize), fontOutline, tostring(hasShadow) }, "|")
    if FONT_CACHE[fontString] == fontKey then
        return
    end
    FONT_CACHE[fontString] = fontKey

    fontString:SetFont(fontPath, fontSize, fontOutline)

    if hasShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end


function BarFrame:SetValue(minVal, maxVal, currentVal, r, g, b)
    Util.Log(self.Name, "SetValue", {
        minVal = minVal,
        maxVal = maxVal,
        currentVal = currentVal,
        color = { r = r, g = g, b = b, a = 1 }
    })
    self.StatusBar:SetMinMaxValues(minVal, maxVal)
    self.StatusBar:SetValue(currentVal)
    self.StatusBar:SetStatusBarColor(r, g, b)
end

function BarFrame:RefreshAppearance()
    local globalConfig = self:GetTextGetGlobalConfig()
    local cfg = self:GetConfigSection()
    local frame = self:GetInnerFrame()

    -- Update the background color
    ---@type ECM_Color|nil
    local bgColor = (cfg and cfg.bgColor) or (globalConfig and globalConfig.barBgColor)
    assert(bgColor, "bgColor not defined in config for frame " .. self.Name)

    if frame.Background and frame.Background.SetColorTexture then
        frame.Background:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    end

    -- Update the texture (if it changed)
    local tex = Util.GetTexture((cfg and cfg.texture) or (globalConfig and globalConfig.texture))
    if frame.StatusBar and frame.StatusBar.SetStatusBarTexture then
        frame.StatusBar:SetStatusBarTexture(tex)
    end

    -- TODO: move to ECMFrame.
    --
    -- Update the border
    -- local border = frame.Border
    -- local borderCfg = cfg and cfg.border
    -- if border and borderCfg and borderCfg.enabled then
    --     local thickness = borderCfg.thickness or 1
    --     local color = borderCfg.color or { r = 1, g = 1, b = 1, a = 1 }
    --     local borderR, borderG, borderB, borderA = RequireColor(color, 1)
    --     if self._lastBorderThickness ~= thickness then
    --         border:SetBackdrop({
    --             edgeFile = "Interface\\Buttons\\WHITE8X8",
    --             edgeSize = thickness,
    --         })
    --         self._lastBorderThickness = thickness
    --     end
    --     border:ClearAllPoints()
    --     border:SetPoint("TOPLEFT", -thickness, thickness)
    --     border:SetPoint("BOTTOMRIGHT", thickness, -thickness)
    --     border:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
    --     border:Show()
    -- elseif border then
    --     border:Hide()
    -- end

    local logR, logG, logB, logA = RequireColor(bgColor, 1)
    Util.Log(self.Name, "SetAppearance", {
        textureOverride = (cfg and cfg.texture) or (globalConfig and globalConfig.texture),
        texture = tex,
        bgColor = table.concat({ tostring(logR), tostring(logG), tostring(logB), tostring(logA) }, ","),
        border = border and borderCfg and borderCfg.enabled
    })

    return tex
end

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

function BarFrame:GetText()
    return nil
end

--- Gets the current value for the bar.
---@return number|nil max
---@return number|nil current
---@return number|nil displayValue
---@return string|nil valueType
function BarFrame:GetValue()
    return nil, nil, nil, nil
end

--- Refreshes the frame if enough time has passed since the last update.
--- Uses the global `updateFrequency` setting to throttle refresh calls.
---@return boolean refreshed True if Refresh() was called, false if skipped due to throttling
function BarFrame:ThrottledRefresh()
    local config = self.GetGlobalConfig()
    local freq = (config and tonumber(config.updateFrequency)) or C.Defaults.global.updateFrequency
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end

    self:Refresh()
    self._lastUpdate = GetTime()
    return true
end


function BarFrame:Refresh(event, unitID, powerType)
    if unitID ~= "player" then
        return
    end

    ---@type ECM_BarConfigBase
    local configSection = self:GetConfigSection()

    local frame = self:GetInnerFrame()
    local resource = UnitPowerType("player")

    ---@type ECM_Color|nil
    local color = configSection and configSection.colors[resource]
    assert(color, "color not defined in config for frame " .. self.Name)
    local max, current, displayValue, valueType = GetValue(resource, configSection)

    if valueType == "percent" then
        frame:SetText(string.format("%.0f%%", displayValue))
    else
        frame:SetText(tostring(displayValue))
    end

    Util.Log(self:GetName(), "Refresh", {
        resource = resource,
        max = max,
        current = current,
        displayValue = displayValue,
        valueType = valueType,
        text = frame:GetText()
    })

    self.StatusBar:SetMinMaxValues(0, max)
    self.StatusBar:SetValue(current)
    self.StatusBar:SetStatusBarColor(color.r, color.g, color.b)

    frame:SetTextVisible(configSection.showText ~= false)
    frame:Show()

    self:RefreshAppearance()

    Util.Log(self:GetName(), "Refreshed")
end

function BarFrame:CreateFrame()
    local frame = ECMFrame.CreateFrame(self)

    -- StatusBar for value display
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints()
    frame.StatusBar:SetFrameLevel(frame:GetFrameLevel() + 1)
    Util.Log(self.Name, "CreateFrame", "Success")
    return frame
end

function BarFrame:OnEnable()
    ECMFrame.AddMixin(self, "PowerBar")

    self:RegisterEvent("UNIT_POWER_UPDATE", "Refresh")

    Util.Log(self.Name, "Enabled")
end

function BarFrame:OnDisable()
    self:UnregisterAllEvents()
    Util.Log(self.Name, "Disabled")
end

function BarFrame.AddMixin(module, name)
    assert(module, "module required")
    assert(name, "name required")
    ECMFrame.AddMixin(module, name)

    -- Register refresh events
    module:RegisterEvent("UNIT_POWER_UPDATE", "ThrottledRefresh")
    module._lastUpdate = GetTime()

    Util.Log(module.Name, "Enabled", {
        layoutEvents = module._layoutEvents,
        refreshEvents = module._refreshEvents
    })



    -- module.OnConfigChanged = BarFrame.OnConfigChanged
    -- module.UpdateLayout = BarFrame.UpdateLayout
    -- module.GetFrameIfShown = BarFrame.GetFrameIfShown
    -- module.GetOrCreateFrame = BarFrame.GetOrCreateFrame
    -- module.GetFrame = BarFrame.GetFrame
    -- module.SetHidden = BarFrame.SetHidden
    -- module.IsHidden = BarFrame.IsHidden
    -- module.OnDisable = BarFrame.OnDisable
    -- if not module.CreateFrame then
    --     module.CreateFrame = BarFrame.CreateFrame
    -- end
end
