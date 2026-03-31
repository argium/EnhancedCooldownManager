-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local FrameUtil = {}
ns.FrameUtil = FrameUtil

--- Returns the region at the given index if it exists and matches the expected type.
---@param frame Frame
---@param index number
---@param regionType string
---@return Region|nil
local function tryGetRegion(frame, index, regionType)
    local region = select(index, frame:GetRegions())
    if region and region.IsObjectType and region:IsObjectType(regionType) then
        return region
    end

    return nil
end

--- Returns the icon overlay texture region, or nil.
---@param frame ECM_BuffBarMixin
---@return Texture|nil
function FrameUtil.GetIconOverlay(frame)
    return tryGetRegion(frame.Icon, ns.Constants.BUFFBARS_ICON_OVERLAY_REGION_INDEX, "Texture")
end

--- Returns the icon texture region, or nil.
---@param frame ECM_BuffBarMixin
---@return Texture|nil
function FrameUtil.GetIconTexture(frame)
    return tryGetRegion(frame.Icon, ns.Constants.BUFFBARS_ICON_TEXTURE_REGION_INDEX, "Texture")
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
---@param statusBar StatusBar|nil
---@return Texture|nil
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
-- Anchor Geometry — shared anchor math used by BarMixin, Migration, Runtime
--------------------------------------------------------------------------------

local C = ns.Constants

--- Splits an anchor name like TOPLEFT into its vertical and horizontal parts.
---@param point string|nil
---@return string|nil, string|nil
function FrameUtil.SplitAnchorName(point)
    if point == nil or point == C.EDIT_MODE_DEFAULT_POINT then
        return nil, nil
    end

    local vertical = point:find("TOP", 1, true) and "TOP" or (point:find("BOTTOM", 1, true) and "BOTTOM" or nil)
    local horizontal = point:find("LEFT", 1, true) and "LEFT" or (point:find("RIGHT", 1, true) and "RIGHT" or nil)
    return vertical, horizontal
end

--- Builds an anchor name from separate vertical and horizontal parts.
---@param vertical string|nil
---@param horizontal string|nil
---@return string
function FrameUtil.BuildAnchorName(vertical, horizontal)
    if not vertical and not horizontal then return C.EDIT_MODE_DEFAULT_POINT end
    if not vertical then return horizontal end
    if not horizontal then return vertical end
    return vertical .. horizontal
end

--- Gets the absolute position of one of the parent frame's anchor points.
--- Example: TOP on UIParent is the middle of the top edge of the screen.
---@param point string|nil
---@param parentWidth number|nil
---@param parentHeight number|nil
---@return number, number
function FrameUtil.GetParentAnchorPosition(point, parentWidth, parentHeight)
    local vertical, horizontal = FrameUtil.SplitAnchorName(point)
    local x = (parentWidth or 0) * 0.5
    local y = (parentHeight or 0) * 0.5

    if horizontal == "LEFT" then
        x = 0
    elseif horizontal == "RIGHT" then
        x = parentWidth or 0
    end

    if vertical == "BOTTOM" then
        y = 0
    elseif vertical == "TOP" then
        y = parentHeight or 0
    end

    return x, y
end

--- Gets a frame's width and height, preferring GetSize when available.
---@param parent Frame|nil
---@return number, number
function FrameUtil.GetParentSize(parent)
    if parent and parent.GetSize then
        local width, height = parent:GetSize()
        if width and height then
            return width, height
        end
    end
    local width = (parent and parent.GetWidth and parent:GetWidth()) or 0
    local height = (parent and parent.GetHeight and parent:GetHeight()) or 0
    return width, height
end

--- Returns the offset from the frame's center to the specified anchor point,
--- given the frame's full width and height.
---@param point string|nil
---@param width number|nil
---@param height number|nil
---@return number, number
function FrameUtil.GetOffsetFromFrameCenter(point, width, height)
    local vertical, horizontal = FrameUtil.SplitAnchorName(point)
    local halfWidth = (width or 0) * 0.5
    local halfHeight = (height or 0) * 0.5

    local x = 0
    if horizontal == "LEFT" then
        x = -halfWidth
    elseif horizontal == "RIGHT" then
        x = halfWidth
    end

    local y = 0
    if vertical == "BOTTOM" then
        y = -halfHeight
    elseif vertical == "TOP" then
        y = halfHeight
    end

    return x, y
end

--- Converts offsets from one anchor reference to another without changing the
--- frame's visual position on its parent (anchor-only, no frame dimensions).
---@param point string|nil
---@param relativePoint string|nil
---@param x number|nil
---@param y number|nil
---@param parent Frame|nil
---@return string point
---@return number x
---@return number y
function FrameUtil.NormalizePosition(point, relativePoint, x, y, parent)
    local normalizedPoint = point or C.EDIT_MODE_DEFAULT_POINT
    local normalizedRelativePoint = relativePoint or normalizedPoint
    local normalizedX = x or 0
    local normalizedY = y or 0

    if normalizedPoint == normalizedRelativePoint then
        return normalizedPoint, normalizedX, normalizedY
    end

    local parentWidth, parentHeight = FrameUtil.GetParentSize(parent or UIParent)
    local sourceAnchorX, sourceAnchorY =
        FrameUtil.GetParentAnchorPosition(normalizedRelativePoint, parentWidth, parentHeight)
    local targetAnchorX, targetAnchorY =
        FrameUtil.GetParentAnchorPosition(normalizedPoint, parentWidth, parentHeight)

    return normalizedPoint,
        normalizedX + sourceAnchorX - targetAnchorX,
        normalizedY + sourceAnchorY - targetAnchorY
end

--- Converts offsets from one anchor reference to another, accounting for both
--- the parent anchor difference and the frame's own dimensions.
---@param sourcePoint string
---@param targetPoint string
---@param x number
---@param y number
---@param width number|nil
---@param height number|nil
---@param parent Frame|nil
---@return number, number
function FrameUtil.ConvertOffsetToAnchor(sourcePoint, targetPoint, x, y, width, height, parent)
    if sourcePoint == targetPoint then
        return x, y
    end

    local parentWidth, parentHeight = FrameUtil.GetParentSize(parent or UIParent)
    local srcAnchorX, srcAnchorY = FrameUtil.GetParentAnchorPosition(sourcePoint, parentWidth, parentHeight)
    local tgtAnchorX, tgtAnchorY = FrameUtil.GetParentAnchorPosition(targetPoint, parentWidth, parentHeight)
    local srcOffsetX, srcOffsetY = FrameUtil.GetOffsetFromFrameCenter(sourcePoint, width, height)
    local tgtOffsetX, tgtOffsetY = FrameUtil.GetOffsetFromFrameCenter(targetPoint, width, height)

    return x + srcAnchorX - tgtAnchorX - srcOffsetX + tgtOffsetX,
        y + srcAnchorY - tgtAnchorY - srcOffsetY + tgtOffsetY
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
local function liveAnchorsEqual(frame, anchors)
    if not frame or not frame.GetNumPoints or not frame.GetPoint then
        return false
    end

    if frame:GetNumPoints() ~= #anchors then
        return false
    end

    for i = 1, #anchors do
        local want = anchors[i]
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(i)
        if
            issecretvalue(point)
            or issecretvalue(relativeTo)
            or issecretvalue(relativePoint)
            or issecretvalue(x)
            or issecretvalue(y)
        then
            return nil
        end
        if
            point ~= want[1]
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
local function cloneAnchors(anchors)
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
local function anchorsEqual(lhs, rhs)
    if not lhs or not rhs then
        return false
    end

    if #lhs ~= #rhs then
        return false
    end

    for i = 1, #lhs do
        local a = lhs[i]
        local b = rhs[i]
        if a[1] ~= b[1] or a[2] ~= b[2] or a[3] ~= b[3] or (a[4] or 0) ~= (b[4] or 0) or (a[5] or 0) ~= (b[5] or 0) then
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
local function colorEqualsRgba(color, r, g, b, a)
    if not color then
        return false
    end
    return color.r == r and color.g == g and color.b == b and color.a == (a or 1)
end

--- Reads a texture color via available getters. Returns nil if unavailable.
---@param texture Texture|nil
---@return number|nil, number|nil, number|nil, number|nil
local function getTextureColor(texture)
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
---@param bar StatusBar
---@return any|nil
local function getStatusbarTextureValue(bar)
    local tex = bar:GetStatusBarTexture()
    return tex and tex:GetTexture() or nil
end

--- Sets height only if it differs from the current value.
---@param frame Frame
---@param h number
---@return boolean changed
function FrameUtil.LazySetHeight(frame, h)
    if frame:GetHeight() == h then
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
    if frame:GetWidth() == w then
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
    if frame:GetAlpha() == alpha then
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
    local liveEqual = liveAnchorsEqual(frame, anchors)
    if liveEqual == true then
        if not anchorsEqual(frame.__ecmAnchorCache, anchors) then
            frame.__ecmAnchorCache = cloneAnchors(anchors)
        end
        return false
    end

    -- Some Blizzard frames return secret point strings from GetPoint(). We cannot
    -- safely compare those in tainted code, so fall back to our last applied anchors.
    if liveEqual == nil and anchorsEqual(frame.__ecmAnchorCache, anchors) then
        return false
    end
    frame:ClearAllPoints()
    for i = 1, #anchors do
        local a = anchors[i]
        frame:SetPoint(a[1], a[2], a[3], a[4] or 0, a[5] or 0)
    end
    frame.__ecmAnchorCache = cloneAnchors(anchors)
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

    local r, g, b, a = getTextureColor(background)
    if colorEqualsRgba(color, r, g, b, a) then
        return false
    end

    background:SetColorTexture(color.r, color.g, color.b, color.a)
    return true
end

--- Sets the status bar texture only if it differs from the current value.
---@param bar StatusBar The status bar frame
---@param texturePath string Texture path or LSM key
---@return boolean changed
function FrameUtil.LazySetStatusBarTexture(bar, texturePath)
    local currentTexture = getStatusbarTextureValue(bar)
    if currentTexture == texturePath then
        return false
    end
    bar:SetStatusBarTexture(texturePath)
    return true
end

--- Sets the status bar color only if RGBA has changed.
---@param bar StatusBar The status bar frame
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number|nil Alpha component (default 1)
---@return boolean changed
function FrameUtil.LazySetStatusBarColor(bar, r, g, b, a)
    a = a or 1
    local cr, cg, cb, ca = bar:GetStatusBarColor()
    if cr == r and cg == g and cb == b and (ca or 1) == a then
        return false
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
    if not border then
        return false
    end

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
        if
            liveEnabled == true
            and liveThickness == thickness
            and ns.ColorUtil.AreEqual(borderConfig.color, liveColor)
        then
            return false
        end
    else
        if liveEnabled == false then
            return false
        end
    end

    if borderConfig.enabled then
        border:Show()
        ns.DebugAssert(borderConfig.thickness, "border thickness required when enabled")
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
            borderConfig.color.r,
            borderConfig.color.g,
            borderConfig.color.b,
            borderConfig.color.a
        )
    else
        border:Hide()
    end

    return true
end

--------------------------------------------------------------------------------
-- Texture, font, and pixel utilities
--------------------------------------------------------------------------------

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local function getLsmMedia(mediaType, key)
    if LSM and key then
        return LSM:Fetch(mediaType, key, true)
    end
end

function FrameUtil.GetTexture(texture)
    local fetched = texture and getLsmMedia("statusbar", texture)
    if fetched then return fetched end
    if texture and texture:find("\\") then return texture end
    return getLsmMedia("statusbar", "Blizzard") or C.DEFAULT_STATUSBAR_TEXTURE
end

function FrameUtil.ApplyFont(fontString, globalConfig, moduleConfig)
    local config = globalConfig or ns.GetGlobalConfig()
    local useModuleOverride = moduleConfig and moduleConfig.overrideFont
    local fontPath = getLsmMedia("font", (useModuleOverride and moduleConfig.font) or (config and config.font))
        or C.DEFAULT_FONT
    local fontSize = (useModuleOverride and moduleConfig.fontSize)
        or (config and config.fontSize)
        or C.DEFAULT_FONT_SIZE
    local fontOutline = (config and config.fontOutline)

    if fontOutline == "NONE" then
        fontOutline = ""
    end

    local hasShadow = config and config.fontShadow

    ns.DebugAssert(fontPath, "Font path cannot be nil")
    ns.DebugAssert(fontSize, "Font size cannot be nil")
    ns.DebugAssert(fontOutline, "Font outline cannot be nil")

    fontString:SetFont(fontPath, fontSize, fontOutline)

    if hasShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

function FrameUtil.PixelSnap(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
end
