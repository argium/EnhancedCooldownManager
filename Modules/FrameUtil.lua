-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local FrameUtil = {}
ECM.FrameUtil = FrameUtil

--- Returns the region at the given index if it exists and matches the expected type.
---@param frame Frame
---@param index number
---@param regionType string
---@return Region|nil
local function TryGetRegion(frame, index, regionType)
    if not frame or not frame.GetRegions then
        return nil
    end

    local region = select(index, frame:GetRegions())
    if region and region.IsObjectType and region:IsObjectType(regionType) then
        return region
    end

    return nil
end

--- Returns the spell name shown on the bar, or nil.
---@param frame ECM_BuffBarMixin
---@return string|nil
function FrameUtil.GetSpellName(frame)
    return frame.Bar.Name and frame.Bar.Name:GetText() or nil
end

--- Returns the icon overlay texture region, or nil.
---@param frame ECM_BuffBarMixin
---@return Texture|nil
function FrameUtil.GetIconOverlay(frame)
    return TryGetRegion(frame.Icon, ECM.Constants.BUFFBARS_ICON_OVERLAY_REGION_INDEX, "Texture")
end

--- Returns the icon texture region, or nil.
---@param frame ECM_BuffBarMixin
---@return Texture|nil
function FrameUtil.GetIconTexture(frame)
    return TryGetRegion(frame.Icon, ECM.Constants.BUFFBARS_ICON_TEXTURE_REGION_INDEX, "Texture")
end

--- Returns the texture file ID of the icon, or nil.
---@param frame ECM_BuffBarMixin
---@return number|nil
function FrameUtil.GetIconTextureFileID(frame)
    local iconTexture = FrameUtil.GetIconTexture(frame)
    return iconTexture and iconTexture.GetTextureFileID and iconTexture:GetTextureFileID() or nil
end

--- Discovers the bar background texture by scanning regions for the known atlas.
--- Caches result on statusBar.__ecmBarBG for subsequent calls.
---@param statusBar any
---@return any barBG The background texture region, or nil
function FrameUtil.GetBarBackground(statusBar)
    if not statusBar or not statusBar.GetRegions then
        return nil
    end

    local cached = statusBar.__ecmBarBG
    if cached and cached.IsObjectType and cached:IsObjectType("Texture") then
        return cached
    end

    for _, region in ipairs({ statusBar:GetRegions() }) do
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas == "UI-HUD-CoolDownManager-Bar-BG" or atlas == "UI-HUD-CooldownManager-Bar-BG" then
                statusBar.__ecmBarBG = region
                return region
            end
        end
    end

    return nil
end

--------------------------------------------------------------------------------
-- Lazy Setters — change-detection-aware frame property setters
--------------------------------------------------------------------------------

--- Compares a frame's live anchor points against the desired anchors.
--- Returns false when the frame does not expose anchor getters.
--- Returns nil when a live anchor component is secret and cannot be compared.
---@param frame Frame
---@param anchors table[] Array of anchors
---@return boolean|nil
local function live_anchors_equal(frame, anchors)
    if not frame or not frame.GetNumPoints or not frame.GetPoint then
        return false
    end

    if frame:GetNumPoints() ~= #anchors then
        return false
    end

    for i = 1, #anchors do
        local want = anchors[i]
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        if issecretvalue(point)
            or issecretvalue(relativeTo)
            or issecretvalue(relativePoint)
            or issecretvalue(x)
            or issecretvalue(y)
        then
            return nil
        end
        if point ~= want[1]
            or relativeTo ~= want[2]
            or relativePoint ~= want[3]
            or (x or 0) ~= (want[4] or 0)
            or (y or 0) ~= (want[5] or 0)
        then
            return false
        end
    end

    return true
end

---@param anchors table[]|nil
---@return table[]|nil
local function clone_anchors(anchors)
    if not anchors then
        return nil
    end

    local out = {}
    for i = 1, #anchors do
        local a = anchors[i]
        out[i] = { a[1], a[2], a[3], a[4] or 0, a[5] or 0 }
    end
    return out
end

---@param lhs table[]|nil
---@param rhs table[]|nil
---@return boolean
local function anchors_equal(lhs, rhs)
    if not lhs or not rhs then
        return false
    end

    if #lhs ~= #rhs then
        return false
    end

    for i = 1, #lhs do
        local a = lhs[i]
        local b = rhs[i]
        if a[1] ~= b[1]
            or a[2] ~= b[2]
            or a[3] ~= b[3]
            or (a[4] or 0) ~= (b[4] or 0)
            or (a[5] or 0) ~= (b[5] or 0)
        then
            return false
        end
    end

    return true
end

---@param color ECM_Color|nil
---@param r number|nil
---@param g number|nil
---@param b number|nil
---@param a number|nil
---@return boolean
local function color_equals_rgba(color, r, g, b, a)
    if not color then
        return false
    end
    return color.r == r and color.g == g and color.b == b and color.a == (a or 1)
end

--- Reads a texture color via available getters. Returns nil if unavailable.
---@param texture Texture|nil
---@return number|nil, number|nil, number|nil, number|nil
local function get_texture_color(texture)
    if not texture then
        return nil, nil, nil, nil
    end

    if texture.GetColorTexture then
        local r, g, b, a = texture:GetColorTexture()
        if r ~= nil then
            return r, g, b, a
        end
    end

    if texture.GetVertexColor then
        return texture:GetVertexColor()
    end

    return nil, nil, nil, nil
end

--- Reads status bar texture value (path/file id) from the underlying texture.
---@param bar StatusBar|nil
---@return any|nil
local function get_statusbar_texture_value(bar)
    if not bar or not bar.GetStatusBarTexture then
        return nil
    end

    local tex = bar:GetStatusBarTexture()
    if tex and tex.GetTexture then
        return tex:GetTexture()
    end

    return nil
end

--- Sets height only if it differs from the current value.
---@param frame Frame
---@param h number
---@return boolean changed
function FrameUtil.LazySetHeight(frame, h)
    if frame.GetHeight and frame:GetHeight() == h then
        return false
    end
    frame:SetHeight(h)
    return true
end

--- Sets width only if it differs from the current value.
---@param frame Frame
---@param w number
---@return boolean changed
function FrameUtil.LazySetWidth(frame, w)
    if frame.GetWidth and frame:GetWidth() == w then
        return false
    end
    frame:SetWidth(w)
    return true
end

--- Sets alpha only if it differs from the current value.
---@param frame Frame
---@param alpha number
---@return boolean changed
function FrameUtil.LazySetAlpha(frame, alpha)
    if frame.GetAlpha and frame:GetAlpha() == alpha then
        return false
    end
    frame:SetAlpha(alpha)
    return true
end

--- Clears and re-applies anchor points only if the anchors has changed.
--- `anchors` is an array of { point, relativeTo, relativePoint, offsetX, offsetY }.
---@param frame Frame
---@param anchors table[] Array of anchors
---@return boolean changed
function FrameUtil.LazySetAnchors(frame, anchors)
    local liveEqual = live_anchors_equal(frame, anchors)
    if liveEqual == true then
        if not anchors_equal(frame.__ecmAnchorCache, anchors) then
            frame.__ecmAnchorCache = clone_anchors(anchors)
        end
        return false
    end

    -- Some Blizzard frames return secret point strings from GetPoint(). We cannot
    -- safely compare those in tainted code, so fall back to our last applied anchors.
    if liveEqual == nil and anchors_equal(frame.__ecmAnchorCache, anchors) then
        return false
    end
    frame:ClearAllPoints()
    for i = 1, #anchors do
        local a = anchors[i]
        frame:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)
    end
    frame.__ecmAnchorCache = clone_anchors(anchors)
    return true
end

--- Sets the background color texture only if color has changed.
--- Expects `frame.Background` to be a Texture with `:SetColorTexture()`.
---@param frame Frame
---@param color ECM_Color Table with r, g, b, a fields
---@return boolean changed
function FrameUtil.LazySetBackgroundColor(frame, color)
    local background = frame.Background
    if not background then
        return false
    end

    local r, g, b, a = get_texture_color(background)
    if color_equals_rgba(color, r, g, b, a) then
        return false
    end

    background:SetColorTexture(color.r, color.g, color.b, color.a)
    return true
end

--- Sets vertex color on a texture only if the color has changed.
---@param frame Frame Unused; retained for API compatibility
---@param texture Texture The texture object
---@param cacheKey string Unused; retained for API compatibility
---@param color ECM_Color Table with r, g, b, a fields
---@return boolean changed
function FrameUtil.LazySetVertexColor(frame, texture, cacheKey, color)
    local r, g, b, a = get_texture_color(texture)
    if color_equals_rgba(color, r, g, b, a) then
        return false
    end
    texture:SetVertexColor(color.r, color.g, color.b, color.a)
    return true
end

--- Sets the status bar texture only if it differs from the current value.
---@param frame Frame Unused; retained for API compatibility
---@param bar StatusBar The status bar frame
---@param texturePath string Texture path or LSM key
---@return boolean changed
function FrameUtil.LazySetStatusBarTexture(frame, bar, texturePath)
    local currentTexture = get_statusbar_texture_value(bar)
    if currentTexture ~= nil and currentTexture == texturePath then
        return false
    end
    bar:SetStatusBarTexture(texturePath)
    return true
end

--- Sets the status bar color only if RGBA has changed.
---@param frame Frame Unused; retained for API compatibility
---@param bar StatusBar The status bar frame
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number|nil Alpha component (default 1)
---@return boolean changed
function FrameUtil.LazySetStatusBarColor(frame, bar, r, g, b, a)
    a = a or 1
    if bar.GetStatusBarColor then
        local cr, cg, cb, ca = bar:GetStatusBarColor()
        if cr == r and cg == g and cb == b and (ca or 1) == a then
            return false
        end
    end
    bar:SetStatusBarColor(r, g, b, a)
    return true
end

--- Applies border configuration (enabled, thickness, color) only if changed.
--- Expects `frame.Border` to be a BackdropTemplate frame.
---@param frame Frame
---@param borderConfig table Table with enabled, thickness, color fields
---@return boolean changed
function FrameUtil.LazySetBorder(frame, borderConfig)
    local border = frame.Border
    if not border then return false end

    local thickness = borderConfig.thickness or 1
    local liveEnabled = border.IsShown and border:IsShown() or nil
    local liveThickness = nil
    if border.GetBackdrop then
        local backdrop = border:GetBackdrop()
        if backdrop and backdrop.edgeSize ~= nil then
            liveThickness = backdrop.edgeSize
        end
    end
    local liveColor = nil
    if border.GetBackdropBorderColor then
        local r, g, b, a = border:GetBackdropBorderColor()
        if r ~= nil then
            liveColor = { r = r, g = g, b = b, a = a or 1 }
        end
    end

    if borderConfig.enabled then
        if liveEnabled == true and liveThickness == thickness and ECM_AreColorsEqual(borderConfig.color, liveColor) then
            return false
        end
    else
        if liveEnabled == false then
            return false
        end
    end

    if borderConfig.enabled then
        border:Show()
        ECM_debug_assert(borderConfig.thickness, "border thickness required when enabled")
        if liveThickness ~= thickness then
            border:SetBackdrop({
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = thickness,
            })
        end
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", -thickness, thickness)
        border:SetPoint("BOTTOMRIGHT", thickness, -thickness)
        border:SetBackdropBorderColor(
            borderConfig.color.r, borderConfig.color.g,
            borderConfig.color.b, borderConfig.color.a
        )
    else
        border:Hide()
    end

    return true
end

--- Sets text on a FontString only if it differs from the current value.
---@param frame Frame Unused; retained for API compatibility
---@param fontString FontString The font string to update
---@param cacheKey string Unused; retained for API compatibility
---@param text string|nil The text to set
---@return boolean changed
function FrameUtil.LazySetText(frame, fontString, cacheKey, text)
    if fontString.GetText and fontString:GetText() == text then
        return false
    end
    fontString:SetText(text)
    return true
end

--------------------------------------------------------------------------------
-- Layout & Refresh Utilities
--
-- Stateless functions that implement layout, refresh, and throttle logic.
-- ModuleMixin provides thin overrideable wrappers; modules may also call these
-- directly when they need explicit control (e.g. custom UpdateLayout overrides).
--------------------------------------------------------------------------------

--- Default layout parameter calculation for chain/free anchor modes.
--- Modules with custom positioning (e.g. BuffBars) override the ModuleMixin wrapper
--- rather than calling this directly.
---@param self ModuleMixin
---@return table params
function FrameUtil.CalculateLayoutParams(self)
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local mode = moduleConfig.anchorMode

    local params = { mode = mode }

    if mode == ECM.Constants.ANCHORMODE_CHAIN then
        local anchor, isFirst = self:GetNextChainAnchor(self.Name)
        local moduleSpacing = globalConfig.moduleSpacing or 0
        params.anchor = anchor
        params.isFirst = isFirst
        params.anchorPoint = "TOPLEFT"
        params.anchorRelativePoint = "BOTTOMLEFT"
        params.offsetX = 0
        params.offsetY = (isFirst and -globalConfig.offsetY) or -moduleSpacing
        params.height = moduleConfig.height or globalConfig.barHeight
        params.width = nil -- Width set by dual-point anchoring
    elseif mode == ECM.Constants.ANCHORMODE_FREE then
        params.anchor = UIParent
        params.isFirst = false
        params.anchorPoint = "CENTER"
        params.anchorRelativePoint = "CENTER"
        params.offsetX = moduleConfig.offsetX or 0
        params.offsetY = moduleConfig.offsetY or ECM.Constants.DEFAULT_FREE_ANCHOR_OFFSET_Y
        params.height = moduleConfig.height or globalConfig.barHeight
        params.width = moduleConfig.width or globalConfig.barWidth
    end

    return params
end

--- Applies positioning to a frame based on layout parameters.
--- Handles ShouldShow check, layout calculation, and anchor positioning.
---@param self ModuleMixin
---@param frame Frame The frame to position
---@return table|nil params Layout params if shown, nil if hidden
function FrameUtil.ApplyFramePosition(self, frame)
    if not self:ShouldShow() then
        frame:Hide()
        return nil
    end

    -- Ensure the frame is visible. ApplyFramePosition hides the frame when
    -- ShouldShow() returns false, so we must re-show it here. This cannot
    -- be deferred to Refresh() because ThrottledRefresh may suppress the
    -- call, leaving the frame hidden after a quick hide→show transition
    -- (e.g. rapid mount/dismount).
    if not frame:IsShown() then
        frame:Show()
    end

    local params = self:CalculateLayoutParams()
    local mode = params.mode
    local anchor = params.anchor
    local offsetX, offsetY = params.offsetX, params.offsetY
    local anchorPoint = params.anchorPoint
    local anchorRelativePoint = params.anchorRelativePoint

    local anchors
    if mode == ECM.Constants.ANCHORMODE_CHAIN then
        anchors = {
            { "TOPLEFT", anchor, "BOTTOMLEFT", offsetX, offsetY },
            { "TOPRIGHT", anchor, "BOTTOMRIGHT", offsetX, offsetY },
        }
    else
        assert(anchor ~= nil, "anchor required for free anchor mode")
        anchors = {
            { anchorPoint, anchor, anchorRelativePoint, offsetX, offsetY },
        }
    end

    FrameUtil.LazySetAnchors(frame, anchors)

    return params
end

--- Standard layout pass: positioning, dimensions, border, background color.
--- Calls self:ThrottledRefresh at the end to update values.
---@param self ModuleMixin
---@param why string|nil
---@return boolean
function FrameUtil.ApplyStandardLayout(self, why)
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local frame = self.InnerFrame
    local borderConfig = moduleConfig.border

    -- Apply positioning and get params (returns nil if frame should be hidden)
    local params = FrameUtil.ApplyFramePosition(self, frame)
    if not params then
        return false
    end

    local width = params.width
    local height = params.height

    -- Apply dimensions via lazy setters (no-ops when unchanged)
    if height then
        FrameUtil.LazySetHeight(frame, height)
    end
    if width then
        FrameUtil.LazySetWidth(frame, width)
    end

    -- Apply border via lazy setter
    if borderConfig then
        FrameUtil.LazySetBorder(frame, borderConfig)
    end

    -- Apply background color via lazy setter
    ECM_debug_assert(moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor), "bgColor not defined in config for frame " .. self.Name)
    local bgColor = moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor) or ECM.Constants.DEFAULT_BG_COLOR
    FrameUtil.LazySetBackgroundColor(frame, bgColor)

    self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
    return true
end

--- Base refresh guard. Returns true if the module should continue refreshing.
---@param self ModuleMixin
---@param why string|nil
---@param force boolean|nil
---@return boolean
function FrameUtil.BaseRefresh(self, why, force)
    if not force and not self:ShouldShow() then
        return false
    end
    return true
end

--- Schedules a debounced callback. Multiple calls within updateFrequency coalesce into one.
---@param self ModuleMixin
---@param flagName string Key for the pending flag on self
---@param callback function Function to call after delay
function FrameUtil.ScheduleDebounced(self, flagName, callback)
    if self[flagName] then
        return
    end
    self[flagName] = true

    local globalConfig = self:GetGlobalConfig()
    local freq = globalConfig and globalConfig.updateFrequency or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
    C_Timer.After(freq, function()
        self[flagName] = nil
        callback()
    end)
end

--- Rate-limited refresh. Skips if called within updateFrequency window.
---@param self ModuleMixin
---@param why string|nil
---@return boolean refreshed True if Refresh() was called
function FrameUtil.ThrottledRefresh(self, why)
    local globalConfig = self:GetGlobalConfig()
    local freq = (globalConfig and globalConfig.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end
    self:Refresh(why)
    self._lastUpdate = GetTime()
    return true
end

--- Schedules a throttled layout update via debounced callback.
---@param self ModuleMixin
---@param why string|nil
function FrameUtil.ScheduleLayoutUpdate(self, why)
    FrameUtil.ScheduleDebounced(self, "_layoutPending", function()
        self:UpdateLayout(why)
    end)
end
