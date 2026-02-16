-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

--- ECM.FrameUtil: static helper methods for WoW frames.
---
--- Includes:
---   - Buff-bar inspection (GetSpellName, GetIconTexture, etc.)
---   - Change-detection-aware "Lazy" setters that compare desired values
---     against a per-frame `__ecm_state` cache and only call the underlying
---     WoW API when the value actually differs.
---
--- Usage:
---   ECM.FrameUtil.GetSpellName(frame)
---   ECM.FrameUtil.GetIconTexture(frame)
---   ECM.FrameUtil.LazySetHeight(frame, 20)
---   ECM.FrameUtil.LazyResetState(frame)

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

--- Serializes a list of anchor specs into a comparable string key.
--- Each spec is { point, relativeTo, relativePoint, x, y }.
---@param anchors table[] Array of anchor spec tables
---@return string
local function serialize_anchors(anchors)
    local parts = {}
    for i = 1, #anchors do
        local a = anchors[i]
        -- relativeTo: use the frame's name (or its tostring address) for comparison
        local relName = a[2] and (a[2].GetName and a[2]:GetName() or tostring(a[2])) or "nil"
        parts[#parts + 1] = (a[1] or "nil")
            .. ";" .. relName
            .. ";" .. (a[3] or "nil")
            .. ";" .. (a[4] or 0)
            .. ";" .. (a[5] or 0)
    end
    return table.concat(parts, "|")
end

--- Returns (or initializes) the __ecm_state table on a frame.
---@param frame table
---@return table
local function get_state(frame)
    local s = frame.__ecm_state
    if not s then
        s = {}
        frame.__ecm_state = s
    end
    return s
end

--- Sets height only if it differs from the cached value.
---@param frame Frame
---@param h number
---@return boolean changed
function FrameUtil.LazySetHeight(frame, h)
    local s = get_state(frame)
    if s.height == h then return false end
    frame:SetHeight(h)
    s.height = h
    return true
end

--- Sets width only if it differs from the cached value.
---@param frame Frame
---@param w number
---@return boolean changed
function FrameUtil.LazySetWidth(frame, w)
    local s = get_state(frame)
    if s.width == w then return false end
    frame:SetWidth(w)
    s.width = w
    return true
end

--- Sets alpha only if it differs from the cached value.
---@param frame Frame
---@param alpha number
---@return boolean changed
function FrameUtil.LazySetAlpha(frame, alpha)
    local s = get_state(frame)
    if s.alpha == alpha then return false end
    frame:SetAlpha(alpha)
    s.alpha = alpha
    return true
end

--- Clears and re-applies anchor points only if the anchor spec has changed.
--- `anchors` is an array of { point, relativeTo, relativePoint, offsetX, offsetY }.
---@param frame Frame
---@param anchors table[] Array of anchor specifications
---@return boolean changed
function FrameUtil.LazySetAnchors(frame, anchors)
    local s = get_state(frame)
    local key = serialize_anchors(anchors)
    if s.anchors == key then return false end
    frame:ClearAllPoints()
    for i = 1, #anchors do
        local a = anchors[i]
        frame:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)
    end
    s.anchors = key
    return true
end

--- Sets the background color texture only if color has changed.
--- Expects `frame.Background` to be a Texture with `:SetColorTexture()`.
---@param frame Frame
---@param color ECM_Color Table with r, g, b, a fields
---@return boolean changed
function FrameUtil.LazySetBackgroundColor(frame, color)
    local s = get_state(frame)
    if ECM_AreColorsEqual(s.bgColor, color) then return false end
    if frame.Background then
        frame.Background:SetColorTexture(color.r, color.g, color.b, color.a)
    end
    s.bgColor = { r = color.r, g = color.g, b = color.b, a = color.a }
    return true
end

--- Sets vertex color on a texture only if the color has changed.
--- Uses a namespaced cache key so multiple textures can be tracked independently.
---@param frame Frame The frame that owns the state cache
---@param texture Texture The texture object
---@param cacheKey string Unique key for this texture in the state cache
---@param color ECM_Color Table with r, g, b, a fields
---@return boolean changed
function FrameUtil.LazySetVertexColor(frame, texture, cacheKey, color)
    local s = get_state(frame)
    if ECM_AreColorsEqual(s[cacheKey], color) then return false end
    texture:SetVertexColor(color.r, color.g, color.b, color.a)
    s[cacheKey] = { r = color.r, g = color.g, b = color.b, a = color.a }
    return true
end

--- Sets the status bar texture only if it differs from the cached value.
---@param frame Frame The frame that owns the state cache
---@param bar StatusBar The status bar frame
---@param texturePath string Texture path or LSM key
---@return boolean changed
function FrameUtil.LazySetStatusBarTexture(frame, bar, texturePath)
    local s = get_state(frame)
    if s.statusBarTexture == texturePath then return false end
    bar:SetStatusBarTexture(texturePath)
    s.statusBarTexture = texturePath
    return true
end

--- Sets the status bar color only if RGBA has changed.
---@param frame Frame The frame that owns the state cache
---@param bar StatusBar The status bar frame
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number|nil Alpha component (default 1)
---@return boolean changed
function FrameUtil.LazySetStatusBarColor(frame, bar, r, g, b, a)
    local s = get_state(frame)
    a = a or 1
    local cached = s.statusBarColor
    if cached and cached[1] == r and cached[2] == g and cached[3] == b and cached[4] == a then
        return false
    end
    bar:SetStatusBarColor(r, g, b, a)
    s.statusBarColor = { r, g, b, a }
    return true
end

--- Applies border configuration (enabled, thickness, color) only if changed.
--- Expects `frame.Border` to be a BackdropTemplate frame.
---@param frame Frame
---@param borderConfig table Table with enabled, thickness, color fields
---@return boolean changed
function FrameUtil.LazySetBorder(frame, borderConfig)
    local s = get_state(frame)
    local border = frame.Border
    if not border then return false end

    local changed = borderConfig.enabled ~= s.borderEnabled
        or borderConfig.thickness ~= s.borderThickness
        or not ECM_AreColorsEqual(borderConfig.color, s.borderColor)

    if not changed then return false end

    local thickness = borderConfig.thickness or 1
    if borderConfig.enabled then
        border:Show()
        ECM_debug_assert(borderConfig.thickness, "border thickness required when enabled")
        if s.borderThickness ~= thickness then
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

    s.borderEnabled = borderConfig.enabled
    s.borderThickness = thickness
    s.borderColor = borderConfig.color
    return true
end

--- Sets text on a FontString only if it differs from the cached value.
---@param frame Frame The frame that owns the state cache
---@param fontString FontString The font string to update
---@param cacheKey string Unique key for this text in the state cache
---@param text string|nil The text to set
---@return boolean changed
function FrameUtil.LazySetText(frame, fontString, cacheKey, text)
    local s = get_state(frame)
    if s[cacheKey] == text then return false end
    fontString:SetText(text)
    s[cacheKey] = text
    return true
end

--- Wipes the __ecm_state cache so every Lazy method will re-apply on next call.
---@param frame table Any frame with __ecm_state
function FrameUtil.LazyResetState(frame)
    if frame then
        frame.__ecm_state = nil
    end
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
        params.anchor = anchor
        params.isFirst = isFirst
        params.anchorPoint = "TOPLEFT"
        params.anchorRelativePoint = "BOTTOMLEFT"
        params.offsetX = 0
        params.offsetY = (isFirst and -globalConfig.offsetY) or 0
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

    local anchor = params.anchor
    local isFirst = params.isFirst
    local width = params.width
    local height = params.height

    -- Apply dimensions via lazy setters (no-ops when unchanged)
    local heightChanged = height and FrameUtil.LazySetHeight(frame, height) or false
    local widthChanged = width and FrameUtil.LazySetWidth(frame, width) or false

    -- Apply border via lazy setter
    local borderChanged = false
    if borderConfig then
        borderChanged = FrameUtil.LazySetBorder(frame, borderConfig)
    end

    -- Apply background color via lazy setter
    ECM_debug_assert(moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor), "bgColor not defined in config for frame " .. self.Name)
    local bgColor = moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor) or ECM.Constants.DEFAULT_BG_COLOR
    local bgColorChanged = FrameUtil.LazySetBackgroundColor(frame, bgColor)

    -- ECM_log(ECM.Constants.SYS.Layout, self.Name, "ApplyStandardLayout complete (" .. (why or "") .. ")", {
    --     anchor = anchor:GetName(),
    --     isFirst = isFirst,
    --     widthChanged = widthChanged,
    --     width = width,
    --     heightChanged = heightChanged,
    --     height = height,
    --     borderChanged = borderChanged,
    --     borderEnabled = borderConfig and borderConfig.enabled,
    --     borderThickness = borderConfig and borderConfig.thickness,
    --     borderColor = borderConfig and borderConfig.color,
    --     bgColorChanged = bgColorChanged,
    --     bgColor = bgColor,
    -- })

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
