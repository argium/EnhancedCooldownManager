-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

--- LazyFrameSetters: a mixin that stamps change-detection-aware setter methods
--- onto any WoW frame. Each method compares the desired value against a per-frame
--- `__ecm_state` table and only calls the underlying WoW API when the value differs.
---
--- Usage:
---   ECM_ApplyLazySetters(frame)       -- stamp Lazy* methods + init __ecm_state
---   frame:LazySetHeight(20)           -- only calls SetHeight if height changed
---   ECM_ResetLazyState(frame)         -- wipe cache so next call always applies

local _, ns = ...
local C = ns.Constants

ns.Mixins = ns.Mixins or {}
ns.Mixins.LazyFrameSetters = {}

---@class ECMLazySettable : Frame
---@field GetSpellName fun(self: ECM_BuffBarFrame): string|nil
---@field GetTextureFileID fun(self: ECM_BuffBarFrame): string|nil
---@field LazySetHeight fun(self: ECM_BuffBarFrame, h: number): boolean Sets height only if changed.
---@field LazySetWidth fun(self: ECM_BuffBarFrame, w: number): boolean Sets width only if changed.
---@field LazySetShown fun(self: ECM_BuffBarFrame, shown: boolean): boolean Sets shown state only if changed.
---@field LazySetAlpha fun(self: ECM_BuffBarFrame, alpha: number): boolean Sets alpha only if changed.
---@field LazySetAnchors fun(self: ECM_BuffBarFrame, anchors: table[]): boolean Clears and re-applies anchor points only if changed.
---@field LazySetBackgroundColor fun(self: ECM_BuffBarFrame, color: ECM_Color): boolean Sets background color texture only if changed.
---@field LazySetVertexColor fun(self: ECM_BuffBarFrame, texture: Texture, cacheKey: string, color: ECM_Color): boolean Sets vertex color on a texture only if changed.
---@field LazySetStatusBarTexture fun(self: ECM_BuffBarFrame, bar: StatusBar, texturePath: string): boolean Sets status bar texture only if changed.
---@field LazySetStatusBarColor fun(self: ECM_BuffBarFrame, bar: StatusBar, r: number, g: number, b: number, a: number|nil): boolean Sets status bar color only if changed.
---@field LazySetBorder fun(self: ECM_BuffBarFrame, borderConfig: table): boolean Applies border configuration only if changed.
---@field LazySetText fun(self: ECM_BuffBarFrame, fontString: FontString, cacheKey: string, text: string|nil): boolean Sets text on a FontString only if changed.
---@field ResetLazyMarkers fun(self: ECM_BuffBarFrame): nil Resets all lazy setter state to force re-application on next update.

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
---@param h number
---@return boolean changed
local function LazySetHeight(self, h)
    local s = get_state(self)
    if s.height == h then return false end
    self:SetHeight(h)
    s.height = h
    return true
end

--- Sets width only if it differs from the cached value.
---@param w number
---@return boolean changed
local function LazySetWidth(self, w)
    local s = get_state(self)
    if s.width == w then return false end
    self:SetWidth(w)
    s.width = w
    return true
end

--- Sets shown state only if it differs from the cached value.
---@param shown boolean
---@return boolean changed
local function LazySetShown(self, shown)
    local s = get_state(self)
    if s.shown == shown then return false end
    self:SetShown(shown)
    s.shown = shown
    return true
end

--- Sets alpha only if it differs from the cached value.
---@param alpha number
---@return boolean changed
local function LazySetAlpha(self, alpha)
    local s = get_state(self)
    if s.alpha == alpha then return false end
    self:SetAlpha(alpha)
    s.alpha = alpha
    return true
end

--- Clears and re-applies anchor points only if the anchor spec has changed.
--- `anchors` is an array of { point, relativeTo, relativePoint, offsetX, offsetY }.
---@param anchors table[] Array of anchor specifications
---@return boolean changed
local function LazySetAnchors(self, anchors)
    local s = get_state(self)
    local key = serialize_anchors(anchors)
    if s.anchors == key then return false end
    self:ClearAllPoints()
    for i = 1, #anchors do
        local a = anchors[i]
        self:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)
    end
    s.anchors = key
    return true
end

--- Sets the background color texture only if color has changed.
--- Expects `self.Background` to be a Texture with `:SetColorTexture()`.
---@param color ECM_Color Table with r, g, b, a fields
---@return boolean changed
local function LazySetBackgroundColor(self, color)
    local s = get_state(self)
    if ECM_AreColorsEqual(s.bgColor, color) then return false end
    if self.Background then
        self.Background:SetColorTexture(color.r, color.g, color.b, color.a)
    end
    s.bgColor = { r = color.r, g = color.g, b = color.b, a = color.a }
    return true
end

--- Sets vertex color on a texture only if the color has changed.
--- Uses a namespaced cache key so multiple textures can be tracked independently.
---@param texture Texture The texture object
---@param cacheKey string Unique key for this texture in the state cache
---@param color ECM_Color Table with r, g, b, a fields
---@return boolean changed
local function LazySetVertexColor(self, texture, cacheKey, color)
    local s = get_state(self)
    if ECM_AreColorsEqual(s[cacheKey], color) then return false end
    texture:SetVertexColor(color.r, color.g, color.b, color.a)
    s[cacheKey] = { r = color.r, g = color.g, b = color.b, a = color.a }
    return true
end

--- Sets the status bar texture only if it differs from the cached value.
---@param bar StatusBar The status bar frame
---@param texturePath string Texture path or LSM key
---@return boolean changed
local function LazySetStatusBarTexture(self, bar, texturePath)
    local s = get_state(self)
    if s.statusBarTexture == texturePath then return false end
    bar:SetStatusBarTexture(texturePath)
    s.statusBarTexture = texturePath
    return true
end

--- Sets the status bar color only if RGBA has changed.
---@param bar StatusBar The status bar frame
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number|nil Alpha component (default 1)
---@return boolean changed
local function LazySetStatusBarColor(self, bar, r, g, b, a)
    local s = get_state(self)
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
--- Expects `self.Border` to be a BackdropTemplate frame.
---@param borderConfig table Table with enabled, thickness, color fields
---@return boolean changed
local function LazySetBorder(self, borderConfig)
    local s = get_state(self)
    local border = self.Border
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
---@param fontString FontString The font string to update
---@param cacheKey string Unique key for this text in the state cache
---@param text string|nil The text to set
---@return boolean changed
local function LazySetText(self, fontString, cacheKey, text)
    local s = get_state(self)
    if s[cacheKey] == text then return false end
    fontString:SetText(text)
    s[cacheKey] = text
    return true
end

--- Wipes the __ecm_state cache so every Lazy* method will re-apply on next call.
---@param frame table Any frame that has been given lazy setters
local function ResetLazyState(frame)
    if frame then
        frame.__ecm_state = nil
    end
end

--- The method table to stamp onto frames.
local methods = {
    LazySetHeight = LazySetHeight,
    LazySetWidth = LazySetWidth,
    LazySetShown = LazySetShown,
    LazySetAlpha = LazySetAlpha,
    LazySetAnchors = LazySetAnchors,
    LazySetBackgroundColor = LazySetBackgroundColor,
    LazySetVertexColor = LazySetVertexColor,
    LazySetStatusBarTexture = LazySetStatusBarTexture,
    LazySetStatusBarColor = LazySetStatusBarColor,
    LazySetBorder = LazySetBorder,
    LazySetText = LazySetText,
    ResetLazyMarkers = ResetLazyState
}

--- Stamps Lazy* setter methods onto a frame and initializes its __ecm_state cache.
--- Safe to call multiple times; will not overwrite existing Lazy* methods.
---@param frame table Any WoW frame or frame-like table
function ECM_ApplyLazySetters(frame)
    assert(frame, "frame required")
    if not frame.__ecm_state then
        frame.__ecm_state = {}
    end
    for k, v in pairs(methods) do
        if frame[k] == nil then
            frame[k] = v
        end
    end
end
