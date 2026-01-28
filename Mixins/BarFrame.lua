-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...

local BarFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.BarFrame = BarFrame
local Module = ns.Mixins.Module
local Util = ns.Util
local LSM = LibStub("LibSharedMedia-3.0", true)
local ECM = ns.Addon
local FONT_CACHE = setmetatable({}, { __mode = "k" })

local function GetPositionMixin()
    assert(ns.Mixins and ns.Mixins.PositionMixin, "PositionMixin required")
    return ns.Mixins.PositionMixin
end

---@class ECMBarFrame : Frame Base bar frame for ECM bars.
---@field Background Texture Background texture.
---@field Border Frame Border frame for optional outline.
---@field StatusBar StatusBar Status bar for value display.
---@field TextFrame Frame|nil Text overlay container.
---@field TextValue FontString|nil Text overlay value.
---@field TicksFrame Frame|nil Tick container frame.
---@field ticks table|nil Tick table for legacy callers.
---@field tickPool table|nil Default tick pool storage.
---@field _lastAnchor Frame Last anchor used for layout.
---@field _lastOffsetX number Last horizontal offset.
---@field _lastOffsetY number Last vertical offset.
---@field _lastMatchAnchorWidth boolean Last match-width flag.
---@field _lastIsIndependent boolean Last independence flag.
---@field _lastHeight number Last applied height.
---@field _lastWidth number Last applied width.
---@field _lastBorderThickness number Last border thickness.
---@field ApplyLayout fun(self: ECMBarFrame, params: table): boolean Applies layout parameters to the bar frame.
---@field InvalidateLayout fun(self: ECMBarFrame): nil Invalidates cached layout state.
---@field SetValue fun(self: ECMBarFrame, minVal: number, maxVal: number, currentVal: number, r: number, g: number, b: number) Sets the status bar value and color.
---@field SetAppearance fun(self: ECMBarFrame, cfg: table|nil, profile: table|nil): string|nil Sets appearance and returns the applied texture.
---@field SetText fun(self: ECMBarFrame, text: string) Sets the text overlay value.
---@field SetTextVisible fun(self: ECMBarFrame, shown: boolean) Sets the text overlay visibility.
---@field EnsureTicks fun(self: ECMBarFrame, count: number, parentFrame: Frame, poolKey: string|nil) Sets up the tick pool size.
---@field HideAllTicks fun(self: ECMBarFrame, poolKey: string|nil) Sets all ticks hidden in the pool.
---@field LayoutResourceTicks fun(self: ECMBarFrame, maxResources: number, color: table|nil, tickWidth: number|nil, poolKey: string|nil) Sets resource divider tick positions.
---@field LayoutValueTicks fun(self: ECMBarFrame, statusBar: StatusBar, ticks: table, maxValue: number, defaultColor: table, defaultWidth: number, poolKey: string|nil) Sets value tick positions.

---@class ECMBarModule : ECMModule Base mixin module for bar-based viewers.
---@field _configKey string Config key for module settings.
---@field _externallyHidden boolean|nil External hidden flag.
---@field _frame ECMBarFrame|nil Cached bar frame.
---@field CreateFrame fun(self: ECMBarModule): ECMBarFrame Creates the bar frame.
---@field GetOrCreateFrame fun(self: ECMBarModule): ECMBarFrame Gets or creates the bar frame.
---@field GetFrame fun(self: ECMBarModule): ECMBarFrame Gets the bar frame.
---@field GetFrameIfShown fun(self: ECMBarModule): ECMBarFrame|nil Gets the bar frame if shown.
---@field SetHidden fun(self: ECMBarModule, hidden: boolean) Sets the hidden state.
---@field IsHidden fun(self: ECMBarModule): boolean Gets whether the module is hidden.

local LAYOUT_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_ENTERING_WORLD",
}

local REFRESH_EVENTS = {
    { event = "UNIT_POWER_UPDATE", handler = "OnUnitPower" },
}

local DEFAULT_HEIGHT = 20
BarFrame.DEFAULT_BAR_WIDTH = 250
BarFrame.DEFAULT_BG_COLOR = { 0.08, 0.08, 0.08, 0.65 }
BarFrame.DEFAULT_STATUSBAR_TEXTURE = "Interface\\TARGETINGFRAME\\UI-StatusBar"
BarFrame.VIEWER_ANCHOR_NAME = "EssentialCooldownViewer"

local function GetConfigSection(config, configKey)
    assert(config, "config required")
    assert(configKey, "configKey required")
    return config[configKey]
end

-- Layout Helpers (module-level)

local function FetchLSM(mediaType, key)
    if LSM and LSM.Fetch and key and type(key) == "string" then
        return LSM:Fetch(mediaType, key, true)
    end
    return nil
end

local function GetTickPool(self, poolKey)
    poolKey = poolKey or "tickPool"
    local pool = self[poolKey]
    if not pool then
        pool = {}
        self[poolKey] = pool
    end
    return pool
end

--- Returns the resolved background color from config or defaults.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return number[] RGBA color array
function BarFrame.GetBgColor(cfg, profile)
    local gbl = profile and profile.global
    return (cfg and cfg.bgColor) or (gbl and gbl.barBgColor) or BarFrame.DEFAULT_BG_COLOR
end

--- Returns the top gap offset for the first bar anchored to the viewer.
--- Combines profile-level gap (chain offset) with module-level offset.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return number
function BarFrame.GetTopGapOffset(cfg, profile)
    local profileOffset = (profile and profile.offsetY) or 6
    local moduleOffset = (cfg and cfg.offsetY) or 0
    return profileOffset + moduleOffset
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param textureOverride string|nil
---@return string
function BarFrame.GetTexture(textureOverride)
    if textureOverride and type(textureOverride) == "string" then
        local fetched = FetchLSM("statusbar", textureOverride)
        if fetched then
            return fetched
        end
        if not textureOverride:find("\\") then
            return BarFrame.DEFAULT_STATUSBAR_TEXTURE
        end
        return textureOverride
    end

    return FetchLSM("statusbar", "Blizzard") or BarFrame.DEFAULT_STATUSBAR_TEXTURE
end

--- Returns a font file path (LSM-resolved when available).
---@param fontKey string|nil
---@param fallback string|nil
---@return string
function BarFrame.GetFontPath(fontKey, fallback)
    local fallbackPath = fallback or "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"

    return FetchLSM("font", fontKey) or fallbackPath
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

--- Returns the bar height from config or defaults.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return number
function BarFrame.GetBarHeight(cfg, profile)
    local gbl = profile and profile.global
    local height = (cfg and cfg.height) or (gbl and gbl.barHeight) or DEFAULT_HEIGHT
    return Util.PixelSnap(height)
end

--------------------------------------------------------------------------------
-- Anchor Helpers
--------------------------------------------------------------------------------

--- Returns the base viewer anchor frame (even if it's currently hidden).
---@return Frame
function BarFrame.GetViewerAnchor()
    local viewer = _G[BarFrame.VIEWER_ANCHOR_NAME]
    if viewer then
        return viewer
    end
    return UIParent
end

--- Updates the StatusBar value and color.
---@param self ECMBarFrame
---@param minVal number Minimum value
---@param maxVal number Maximum value
---@param currentVal number Current value
---@param r number Red component (0-1)
---@param g number Green component (0-1)
---@param b number Blue component (0-1)
function BarFrame:SetValue(minVal, maxVal, currentVal, r, g, b)
    Util.Log(self:GetName(), "SetValue", {
        minVal = minVal,
        maxVal = maxVal,
        currentVal = currentVal,
        color = { r, g, b }
    })
    self.StatusBar:SetMinMaxValues(minVal, maxVal)
    self.StatusBar:SetValue(currentVal)
    self.StatusBar:SetStatusBarColor(r, g, b)
end

--- Applies appearance settings (background color, statusbar texture) to a bar.
---@param self ECMBarFrame
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile
---@return string|nil texture The applied texture path
function BarFrame:SetAppearance(cfg, profile)
    local bgColor = BarFrame.GetBgColor(cfg, profile)
    if self.Background and self.Background.SetColorTexture then
        self.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    local gbl = profile and profile.global
    local tex = BarFrame.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))
    if self.StatusBar and self.StatusBar.SetStatusBarTexture then
        self.StatusBar:SetStatusBarTexture(tex)
    end

    local border = self.Border
    local borderCfg = cfg and cfg.border
    if border and borderCfg and borderCfg.enabled then
        local thickness = borderCfg.thickness or 1
        local color = borderCfg.color or {}
        if self._lastBorderThickness ~= thickness then
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = thickness,
            })
            self._lastBorderThickness = thickness
        end
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", -thickness, thickness)
        border:SetPoint("BOTTOMRIGHT", thickness, -thickness)
        border:SetBackdropBorderColor(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
        border:Show()
    elseif border then
        border:Hide()
    end

    Util.Log(self:GetName(), "SetAppearance", {
        textureOverride = (cfg and cfg.texture) or (gbl and gbl.texture),
        texture = tex,
        bgColor = bgColor[1] .. "," .. bgColor[2] .. "," .. bgColor[3] .. "," .. (bgColor[4] or 1),
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
function BarFrame.AddTextOverlay(bar, profile)
    assert(bar, "bar frame required")

    ---@cast bar ECMBarFrame

    local textFrame = CreateFrame("Frame", nil, bar)
    textFrame:SetAllPoints(bar)
    textFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 10)
    bar.TextFrame = textFrame

    local textValue = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    textValue:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    textValue:SetJustifyH("CENTER")
    textValue:SetJustifyV("MIDDLE")
    textValue:SetText("0")
    bar.TextValue = textValue

    if profile then
        BarFrame.ApplyFont(bar.TextValue, profile)
    end

    -- Attach text methods

    --- Sets the text value on a bar with text overlay.
    ---@param self ECMBarFrame
    ---@param text string Text to display
    function bar:SetText(text)
        if self.TextValue then
            self.TextValue:SetText(text)
        end
    end

    --- Shows or hides the text overlay.
    ---@param self ECMBarFrame
    ---@param shown boolean Whether to show the text
    function bar:SetTextVisible(shown)
        if self.TextFrame then
            self.TextFrame:SetShown(shown)
        end
    end

    return bar.TextValue
end

--------------------------------------------------------------------------------
-- Tick Helpers
--------------------------------------------------------------------------------

--- Attaches tick functionality to a bar frame.
--- Creates the tick container frame if needed.
---@param bar ECMBarFrame Bar frame to attach ticks to
---@return Frame ticksFrame Tick container frame
function BarFrame.AttachTicks(bar)
    assert(bar, "bar frame required")

    ---@cast bar ECMBarFrame

    if bar.TicksFrame then
        return bar.TicksFrame
    end

    bar.TicksFrame = CreateFrame("Frame", nil, bar)
    bar.TicksFrame:SetAllPoints(bar)
    bar.TicksFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.ticks = bar.ticks or {}

    return bar.TicksFrame
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
---@param color table|nil RGBA color { r, g, b, a } (default black)
---@param tickWidth number|nil Width of each tick (default 1)
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarFrame:LayoutResourceTicks(maxResources, color, tickWidth, poolKey)
    maxResources = tonumber(maxResources) or 0
    if maxResources <= 1 then
        self:HideAllTicks(poolKey)
        return
    end

    local barWidth = self:GetWidth()
    local barHeight = self:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    color = color or { 0, 0, 0, 1 }
    tickWidth = tickWidth or 1

    local step = barWidth / maxResources
    local tr, tg, tb, ta = color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1

    for i = 1, #pool do
        local tick = pool[i]
        if tick and tick:IsShown() then
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
---@param self ECMBarFrame
---@param statusBar StatusBar StatusBar to position ticks on
---@param ticks table Array of tick definitions { { value = number, color = {r,g,b,a}, width = number }, ... }
---@param maxValue number Maximum resource value
---@param defaultColor table Default RGBA color
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

    local barWidth = statusBar:GetWidth()
    local barHeight = self:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    defaultColor = defaultColor or { 0, 0, 0, 0.5 }
    defaultWidth = defaultWidth or 1

    for i = 1, #ticks do
        local tick = pool[i]
        local tickData = ticks[i]
        if tick and tickData then
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

function BarFrame:SetHidden(hidden)
    local isHidden = not not hidden
    if self._externallyHidden ~= isHidden then
        self._externallyHidden = isHidden
        Util.Log(self:GetName(), "SetHidden", { hidden = self._externallyHidden })
    end

    assert(self._frame, "SetHidden requires frame; missing frame is a bug")
    if isHidden then
        self._frame:Hide()
    else
        self:UpdateLayout()
    end
end

function BarFrame:IsHidden()
    if not self._frame then
        return true
    end
    if self._externallyHidden then
        return true
    end
    return not self._frame:IsShown()
end

function BarFrame:GetFrameIfShown()
    local f = self._frame
    if not f or self._externallyHidden or not f:IsShown() then
        return nil
    end
    return f
end

function BarFrame:GetFrame()
    if not self._frame then
        self._frame = self:CreateFrame()
    end
    return self._frame
end

function BarFrame:OnConfigChanged(_)
    self:UpdateLayout()
end

function BarFrame:OnDisable()
    self._frame:Hide()
end

function BarFrame:UpdateLayout(why)
    local profile = self:GetConfig()
    local cfg = GetConfigSection(profile, self._configKey)
    local frame = self:GetFrame()

    local PositionMixin = GetPositionMixin()
    local params, anchorMode = PositionMixin.CalculateLayout(self)
    Util.Log(self:GetName(), "Applying layout", {
        why = why,
        anchorMode = anchorMode,
        width = params.width or "auto",
    })

    frame:ApplyLayout(params)
    frame:SetAppearance(cfg, profile)
    if frame.TextValue then
        BarFrame.ApplyFont(frame.TextValue, profile)
    end

    if self._externallyHidden then
        return
    end

    if cfg and cfg.enabled == false then
        frame:Hide()
        return
    end

    frame:Show()
    self:Refresh()
end

function BarFrame:CreateFrame(opts)
    local profile = self:GetConfig()
    local cfg = GetConfigSection(profile, self._configKey)
    local name = "ECM" .. self:GetName()
    local frame = CreateFrame("Frame", name, UIParent)

    frame:SetFrameStrata("MEDIUM")
    local barHeight = BarFrame.GetBarHeight(cfg, profile)
    frame:SetHeight(barHeight)

    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAllPoints()

    -- Optional border frame (shown when cfg.border.enabled)
    frame.Border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Border:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.Border:Hide()

    -- StatusBar for value display
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints()
    frame.StatusBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    local PositionMixin = GetPositionMixin()
    PositionMixin.AttachTo(frame)

    frame.SetValue = BarFrame.SetValue
    frame.SetAppearance = BarFrame.SetAppearance
    frame.EnsureTicks = BarFrame.EnsureTicks
    frame.HideAllTicks = BarFrame.HideAllTicks
    frame.LayoutResourceTicks = BarFrame.LayoutResourceTicks
    frame.LayoutValueTicks = BarFrame.LayoutValueTicks
    frame.AttachTicks = BarFrame.AttachTicks

    if opts and type(opts) == "table" and opts.withTicks then
        BarFrame.AttachTicks(frame)
    end

    return frame
end

function BarFrame.AddMixin(module, name, configKey, extraLayoutEvents, extraRefreshEvents)
    local layoutEvents = Util.Concat(LAYOUT_EVENTS, extraLayoutEvents or {})
    local refreshEvents = Util.Concat(REFRESH_EVENTS, extraRefreshEvents or {})

    Module.AddMixin(
        module,
        name,
        ECM.db and ECM.db.profile,
        layoutEvents,
        refreshEvents)

    module.OnConfigChanged = BarFrame.OnConfigChanged
    module.UpdateLayout = BarFrame.UpdateLayout
    module.GetFrameIfShown = BarFrame.GetFrameIfShown
    module.GetOrCreateFrame = BarFrame.GetOrCreateFrame
    module.GetFrame = BarFrame.GetFrame
    module.SetHidden = BarFrame.SetHidden
    module.IsHidden = BarFrame.IsHidden
    module.OnDisable = BarFrame.OnDisable
    if not module.CreateFrame then
        module.CreateFrame = BarFrame.CreateFrame
    end

    module._configKey = configKey

    -- Register ourselves with the viewer hook to respond to global events
    ECM.ViewerHook:RegisterBar(module)
end
