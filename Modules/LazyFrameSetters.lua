-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

--- Lazy: a global table of change-detection-aware setter functions for WoW frames.
--- Each function compares the desired value against a per-frame `__ecm_state`
--- table and only calls the underlying WoW API when the value differs.
---
--- Usage:
---   Lazy.SetHeight(frame, 20)         -- only calls SetHeight if height changed
---   Lazy.ResetState(frame)            -- wipe cache so next call always applies

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

---@class Lazy
Lazy = {}

--- Sets height only if it differs from the cached value.
---@param frame Frame
---@param h number
---@return boolean changed
function Lazy.SetHeight(frame, h)
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
function Lazy.SetWidth(frame, w)
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
function Lazy.SetAlpha(frame, alpha)
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
function Lazy.SetAnchors(frame, anchors)
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
function Lazy.SetBackgroundColor(frame, color)
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
function Lazy.SetVertexColor(frame, texture, cacheKey, color)
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
function Lazy.SetStatusBarTexture(frame, bar, texturePath)
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
function Lazy.SetStatusBarColor(frame, bar, r, g, b, a)
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
function Lazy.SetBorder(frame, borderConfig)
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
function Lazy.SetText(frame, fontString, cacheKey, text)
    local s = get_state(frame)
    if s[cacheKey] == text then return false end
    fontString:SetText(text)
    s[cacheKey] = text
    return true
end

--- Wipes the __ecm_state cache so every Lazy method will re-apply on next call.
---@param frame table Any frame with __ecm_state
function Lazy.ResetState(frame)
    if frame then
        frame.__ecm_state = nil
    end
end
