local _, ns = ...

local Util = ns.Util
local LSM = LibStub("LibSharedMedia-3.0", true)

--- BarFrame mixin: Frame creation, layout, appearance, and text overlay.
--- Provides shared frame structure and styling for all bar modules.
--- Methods are attached directly to created frames.
local BarFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.BarFrame = BarFrame

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

BarFrame.DEFAULT_POWER_BAR_HEIGHT = 20
BarFrame.DEFAULT_SEGMENT_BAR_HEIGHT = 13
BarFrame.DEFAULT_BG_COLOR = { 0.08, 0.08, 0.08, 0.65 }
BarFrame.VIEWER_ANCHOR_NAME = "EssentialCooldownViewer"

--------------------------------------------------------------------------------
-- Layout Helpers (module-level)
--------------------------------------------------------------------------------

--- Returns the resolved background color from config or defaults.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return number[] RGBA color array
function BarFrame.GetBgColor(cfg, profile)
    local gbl = profile and profile.global
    return (cfg and cfg.bgColor) or (gbl and gbl.barBgColor) or BarFrame.DEFAULT_BG_COLOR
end

--- Returns the resolved bar height from config or defaults.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@param fallback number|nil Fallback height if nothing is configured
---@return number
function BarFrame.GetBarHeight(cfg, profile, fallback)
    local gbl = profile and profile.global
    local h = (cfg and cfg.height) or (gbl and gbl.barHeight) or (fallback or 20)
    return Util.PixelSnap(h)
end

--- Returns the top gap offset for the first bar anchored to the viewer.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return number
function BarFrame.GetTopGapOffset(cfg, profile)
    local defaultOffset = (profile and profile.offsetY) or 6
    if cfg and cfg.offsetY ~= nil then
        return cfg.offsetY
    end
    return defaultOffset
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param textureOverride string|nil
---@return string
function BarFrame.GetTexture(textureOverride)
    if textureOverride and type(textureOverride) == "string" then
        if LSM and LSM.Fetch then
            local fetched = LSM:Fetch("statusbar", textureOverride, true)
            if fetched then
                return fetched
            end
        end
        if not textureOverride:find("\\") then
            return "Interface\\TARGETINGFRAME\\UI-StatusBar"
        end
        return textureOverride
    end

    if LSM and LSM.Fetch then
        local fetched = LSM:Fetch("statusbar", "Blizzard", true)
        if fetched then
            return fetched
        end
    end

    return "Interface\\TARGETINGFRAME\\UI-StatusBar"
end

--- Returns a font file path (LSM-resolved when available).
---@param fontKey string|nil
---@param fallback string|nil
---@return string
function BarFrame.GetFontPath(fontKey, fallback)
    local fallbackPath = fallback or "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"

    if LSM and LSM.Fetch and fontKey and type(fontKey) == "string" then
        local fetched = LSM:Fetch("font", fontKey, true)
        if fetched then
            return fetched
        end
    end

    return fallbackPath
end

--- Applies font settings to a FontString.
---@param fontString FontString
---@param profile table|nil Full profile table
function BarFrame.ApplyFont(fontString, profile)
    if not fontString or not fontString.SetFont then
        return
    end

    local gbl = profile and profile.global
    local fontPath = BarFrame.GetFontPath(gbl and gbl.font)
    local fontSize = (gbl and gbl.fontSize) or 11
    local fontOutline = (gbl and gbl.fontOutline) or "OUTLINE"

    fontString:SetFont(fontPath, fontSize, fontOutline ~= "NONE" and fontOutline or "")

    if fontString.SetShadowOffset then
        if gbl and gbl.fontShadow then
            fontString:SetShadowColor(0, 0, 0, 1)
            fontString:SetShadowOffset(1, -1)
        else
            fontString:SetShadowOffset(0, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Anchor Helpers
--------------------------------------------------------------------------------

--- Returns the base viewer anchor frame (even if it's currently hidden).
---@return Frame
function BarFrame.GetViewerAnchor()
    local f = _G[BarFrame.VIEWER_ANCHOR_NAME]
    return (f and f:GetPoint(1)) and f or UIParent
end

--- Returns the bottom-most visible ECM bar frame for anchoring.
--- Chain order: Viewer -> PowerBar -> SegmentBar -> RuneBar.
---@param addon table The EnhancedCooldownManager addon table
---@param excludeModule string|nil Module name to exclude from the chain
---@return Frame anchor The frame to anchor to
---@return boolean isFirstBar True if anchoring directly to the viewer
function BarFrame.GetPreferredAnchor(addon, excludeModule)
    local viewer = BarFrame.GetViewerAnchor()

    local chain = { "PowerBars", "SegmentBar", "RuneBar" }
    local bottomMost = nil

    for _, modName in ipairs(chain) do
        if modName ~= excludeModule then
            local mod = addon[modName]
            if mod and mod.GetFrameIfShown then
                local f = mod:GetFrameIfShown()
                if f then
                    bottomMost = f
                end
            end
        end
    end

    if bottomMost then
        return bottomMost, false
    end

    return viewer, true
end

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

--- Creates a base resource bar frame with Background and StatusBar.
--- Modules can add additional elements (text, ticks, fragments) after creation.
--- Core methods (SetValue, ApplyAppearance) are attached directly to the bar.
---@param frameName string Unique frame name
---@param parent Frame Parent frame (typically UIParent)
---@param defaultHeight number Default bar height
---@return Frame bar The created bar frame with .Background and .StatusBar
function BarFrame.Create(frameName, parent, defaultHeight)
    assert(type(frameName) == "string", "frameName must be a string")

    local bar = CreateFrame("Frame", frameName, parent or UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetHeight(Util.PixelSnap(defaultHeight or 20))

    -- Background texture
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()

    -- StatusBar for value display
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)

    -- Attach methods directly to bar

    --- Updates the StatusBar value and color.
    ---@param self Frame
    ---@param minVal number Minimum value
    ---@param maxVal number Maximum value
    ---@param currentVal number Current value
    ---@param r number Red component (0-1)
    ---@param g number Green component (0-1)
    ---@param b number Blue component (0-1)
    function bar:SetValue(minVal, maxVal, currentVal, r, g, b)
        self.StatusBar:SetMinMaxValues(minVal, maxVal)
        self.StatusBar:SetValue(currentVal)
        self.StatusBar:SetStatusBarColor(r, g, b)
    end

    --- Applies appearance settings (background color, statusbar texture) to a bar.
    ---@param self Frame
    ---@param cfg table|nil Module-specific config
    ---@param profile table|nil Full profile
    ---@return string|nil texture The applied texture path
    function bar:ApplyAppearance(cfg, profile)
        local bgColor = BarFrame.GetBgColor(cfg, profile)
        if self.Background and self.Background.SetColorTexture then
            self.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
        end

        local gbl = profile and profile.global
        local tex = BarFrame.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))
        if self.StatusBar and self.StatusBar.SetStatusBarTexture then
            self.StatusBar:SetStatusBarTexture(tex)
        end

        return tex
    end

    --- Applies layout (anchor, position, size) only if changed.
    --- Caches layout state to avoid unnecessary frame updates.
    ---@param self Frame
    ---@param anchor Frame Frame to anchor to
    ---@param offsetY number Vertical offset from anchor
    ---@param height number Desired bar height
    ---@param width number|nil Desired bar width when not matching anchor
    ---@param matchAnchorWidth boolean|nil When true, match anchor width via left/right points
    function bar:ApplyLayout(anchor, offsetY, height, width, matchAnchorWidth)
        local shouldMatchWidth = matchAnchorWidth ~= false

        if self._lastAnchor ~= anchor or self._lastOffsetY ~= offsetY or self._lastMatchAnchorWidth ~= shouldMatchWidth then
            self:ClearAllPoints()
            if shouldMatchWidth then
                self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
                self:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offsetY)
            else
                self:SetPoint("TOP", anchor, "BOTTOM", 0, offsetY)
            end
            self._lastAnchor = anchor
            self._lastOffsetY = offsetY
            self._lastMatchAnchorWidth = shouldMatchWidth
        end

        if self._lastHeight ~= height then
            self:SetHeight(height)
            self._lastHeight = height
        end

        if not shouldMatchWidth and width ~= nil and self._lastWidth ~= width then
            self:SetWidth(width)
            self._lastWidth = width
        elseif shouldMatchWidth then
            self._lastWidth = nil
        end
    end

    --- Applies layout (position, size) and appearance (background, texture) in one call.
    --- Consolidates common UpdateLayout logic for all bar modules.
    ---@param self Frame
    ---@param anchor Frame Frame to anchor to
    ---@param offsetY number Vertical offset from anchor
    ---@param cfg table Module-specific config
    ---@param profile table Full profile
    ---@param defaultHeight number Default bar height if not configured
    ---@return string|nil texture The applied texture path
    function bar:ApplyLayoutAndAppearance(anchor, offsetY, cfg, profile, defaultHeight)
        local desiredHeight = BarFrame.GetBarHeight(cfg, profile, defaultHeight)
        local widthCfg = profile.width or {}
        local desiredWidth = widthCfg.value or 330
        local matchAnchorWidth = widthCfg.auto ~= false

        self:ApplyLayout(anchor, offsetY, desiredHeight, desiredWidth, matchAnchorWidth)

        local tex = self:ApplyAppearance(cfg, profile)
        self._lastTexture = tex

        return tex
    end

    bar:Hide()
    return bar
end

--- Adds a text overlay to an existing bar frame.
--- Creates TextFrame container and TextValue FontString.
--- Text methods (SetText, SetTextVisible) are attached to the bar.
---@param bar Frame Bar frame to add text overlay to
---@param profile table|nil Profile for font settings
---@return FontString textValue The created FontString
function BarFrame.AddTextOverlay(bar, profile)
    assert(bar, "bar frame required")

    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 10)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", 0, 0)
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetJustifyV("MIDDLE")
    bar.TextValue:SetText("0")

    if profile then
        BarFrame.ApplyFont(bar.TextValue, profile)
    end

    -- Attach text methods

    --- Sets the text value on a bar with text overlay.
    ---@param self Frame
    ---@param text string Text to display
    function bar:SetText(text)
        if self.TextValue then
            self.TextValue:SetText(text)
        end
    end

    --- Shows or hides the text overlay.
    ---@param self Frame
    ---@param shown boolean Whether to show the text
    function bar:SetTextVisible(shown)
        if self.TextFrame then
            self.TextFrame:SetShown(shown)
        end
    end

    return bar.TextValue
end
