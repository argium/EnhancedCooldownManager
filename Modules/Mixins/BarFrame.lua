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
BarFrame.DEFAULT_RESOURCE_BAR_HEIGHT = 13
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

--- Returns the bar height from config or defaults.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@param defaultHeight number Default height if not configured
---@return number
function BarFrame.GetBarHeight(cfg, profile, defaultHeight)
    return Util.PixelSnap(cfg and cfg.height or profile and profile.global and profile.global.barHeight or defaultHeight)
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
--- Chain order: Viewer -> PowerBar -> ResourceBar -> RuneBar.
---@param addon table The EnhancedCooldownManager addon table
---@param excludeModule string|nil Module name to exclude from the chain
---@return Frame anchor The frame to anchor to
---@return boolean isFirstBar True if anchoring directly to the viewer
function BarFrame.GetPreferredAnchor(addon, excludeModule)
    local viewer = BarFrame.GetViewerAnchor()

    local chain = { "PowerBar", "ResourceBar", "RuneBar" }
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

--- Resolves the anchor frame based on anchorMode in config.
---@param addon table The EnhancedCooldownManager addon table
---@param cfg table Module-specific config
---@param moduleName string Module name for chain exclusion
---@return Frame anchor The frame to anchor to
---@return boolean isAnchoredToViewer True if anchoring directly to the viewer (for top gap offset)
function BarFrame.ResolveAnchor(addon, cfg, moduleName)
    local anchorMode = cfg and cfg.anchorMode or "chain"
    if anchorMode == "viewer" then
        return BarFrame.GetViewerAnchor(), true
    else
        return BarFrame.GetPreferredAnchor(addon, moduleName)
    end
end

BarFrame.Helpers = {
    GetBgColor = BarFrame.GetBgColor,
    GetTopGapOffset = BarFrame.GetTopGapOffset,
    GetTexture = BarFrame.GetTexture,
    GetFontPath = BarFrame.GetFontPath,
    ApplyFont = BarFrame.ApplyFont,
    GetBarHeight = BarFrame.GetBarHeight,
    GetViewerAnchor = BarFrame.GetViewerAnchor,
    GetPreferredAnchor = BarFrame.GetPreferredAnchor,
    ResolveAnchor = BarFrame.ResolveAnchor,
}

ns.BarHelpers = BarFrame.Helpers
if ns.Addon then
    ns.Addon.BarHelpers = BarFrame.Helpers
end

--------------------------------------------------------------------------------
-- Frame Creation
--------------------------------------------------------------------------------

--- Creates a base resource bar frame with Background and StatusBar.
--- Modules can add additional elements (text, ticks, fragments) after creation.
--- Core methods (SetValue, SetAppearance) are attached directly to the bar.
---@param frameName string Unique frame name
---@param parent Frame Parent frame (typically UIParent)
---@param defaultHeight number Default bar height
---@return Frame bar The created bar frame with .Background and .StatusBar
function BarFrame.Create(frameName, parent, defaultHeight)
    assert(type(frameName) == "string", "frameName must be a string")

    local bar = CreateFrame("Frame", frameName, parent or UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetHeight(Util.PixelSnap(defaultHeight or 20))

    -- Store default height for ApplyConfig to use
    bar._defaultHeight = defaultHeight or BarFrame.DEFAULT_RESOURCE_BAR_HEIGHT

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
    function bar:SetAppearance(cfg, profile)
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
    ---@param anchor Frame Frame to anchor to (for vertical position)
    ---@param offsetX number|nil Horizontal offset (default 0)
    ---@param offsetY number Vertical offset from anchor
    ---@param height number Desired bar height
    ---@param width number|nil Desired bar width. If nil, width matches viewer width.
    function bar:SetLayout(anchor, offsetX, offsetY, height, width)
        local shouldMatchWidth = width == nil
        offsetX = offsetX or 0

        if self._lastAnchor ~= anchor
                or self._lastOffsetX ~= offsetX
                or self._lastOffsetY ~= offsetY
                or self._lastMatchAnchorWidth ~= shouldMatchWidth then
            self:ClearAllPoints()
            if shouldMatchWidth then
                self:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", offsetX, offsetY)
                self:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", offsetX, offsetY)
            else
                self:SetPoint("TOP", anchor, "BOTTOM", offsetX, offsetY)
            end
            self._lastAnchor = anchor
            self._lastOffsetX = offsetX
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

    --- Applies complete configuration from profile.
    --- Handles preconditions internally - no coupling to Lifecycle.
    ---@param self Frame Bar instance
    ---@param module table Module reference
    ---@return boolean success True if layout applied, false if preconditions failed
    function bar:ApplyConfig(module)
        local addon = ns.Addon
        local barConfig = module._barConfig
        local configKey = barConfig.configKey

        -- 1. Check preconditions (moved from Lifecycle)
        local profile = addon and addon.db and addon.db.profile
        if not profile then
            Util.Log(barConfig.name, "ApplyConfig skipped - no profile")
            return false
        end

        if module._externallyHidden then
            self:Hide()
            return false
        end

        local cfg = profile[configKey]
        if not (cfg and cfg.enabled) then
            module:Disable()
            return false
        end

        if barConfig.shouldShow and not barConfig.shouldShow() then
            self:Hide()
            Util.Log(barConfig.name, "ApplyConfig skipped - shouldShow returned false")
            return false
        end

        -- 2. Calculate anchor (reads cfg.anchorMode)
        local anchor, isAnchoredToViewer = BarFrame.ResolveAnchor(addon, cfg, barConfig.name)

        -- 3. Calculate offsets
        local viewer = BarFrame.GetViewerAnchor()
        local offsetY = (isAnchoredToViewer and anchor == viewer) and -BarFrame.GetTopGapOffset(cfg, profile) or 0
        local offsetX = (cfg and cfg.offsetX) or 0

        -- 4. Calculate dimensions (uses stored defaultHeight)
        local height = BarFrame.GetBarHeight(cfg, profile, self._defaultHeight)
        local widthCfg = profile.width or {}
        local width = nil
        if widthCfg.auto == false then
            width = Util.PixelSnap(widthCfg.value or 200)
        end

        Util.Log(barConfig.name, "Applying layout", {
            anchor = anchor:GetName() or tostring(anchor),
            offsetX = offsetX,
            offsetY = offsetY,
            height = height,
            width = width or "auto",
        })

        -- 5. Apply layout and appearance
        self:SetLayout(anchor, offsetX, offsetY, height, width)
        self:SetAppearance(cfg, profile)

        -- 6. Call module override if defined
        if module.OnLayoutComplete then
            local shouldContinue = module:OnLayoutComplete(self, cfg, profile)
            if shouldContinue == false then
                return false
            end
        end

        return true
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

--------------------------------------------------------------------------------
-- Module Setup (orchestrates Lifecycle + bar-specific config)
--------------------------------------------------------------------------------

--- Sets up a bar module with UpdateLayout and integrates with Lifecycle.
---@param module table AceModule to configure
---@param config table Configuration:
---   - configKey: string - Profile config key (e.g., "powerBar")
---   - shouldShow: function|nil - Visibility check
---   - name: string - Module name for logging
---   - layoutEvents: string[] - Events that trigger UpdateLayout
---   - refreshEvents: table[] - Events that trigger refresh
---   - onDisable: function|nil - Optional cleanup
function BarFrame.Setup(module, config)
    local Lifecycle = ns.Mixins.Lifecycle

    -- 1. Call Lifecycle.Setup for generic event handling
    Lifecycle.Setup(module, {
        name = config.name,
        layoutEvents = config.layoutEvents,
        refreshEvents = config.refreshEvents,
        onDisable = config.onDisable,
    })

    -- 2. Store bar-specific config on module
    module._barConfig = {
        configKey = config.configKey,
        shouldShow = config.shouldShow,
        name = config.name,
    }

    -- 3. Inject bar-specific UpdateLayout
    function module:UpdateLayout()
        self:Enable()
        local bar = self:GetFrame()
        local success = bar:ApplyConfig(self)
        if success then
            bar:Show()
            self:Refresh()
        end
    end
end
