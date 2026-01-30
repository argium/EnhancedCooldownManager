

---@class FrameLayoutMixin Mixin providing frame positioning strategies for bar modules.
---@field AttachTo fun(frame: ECM_TrackedFrame) Attaches layout methods to a frame.
---@field ApplyLayout fun(frame: ECM_TrackedFrame, params: ECM_LayoutParams, cache?: ECM_LayoutCache): boolean Applies layout parameters.

---@class ECM_LayoutCache Cached layout state for change detection.
---@field anchor Frame|nil Last anchor frame.
---@field offsetX number|nil Last horizontal offset.
---@field offsetY number|nil Last vertical offset.
---@field width number|nil Last applied width.
---@field height number|nil Last applied height.
---@field anchorPoint AnchorPoint|nil Last anchor point.
---@field anchorRelativePoint AnchorPoint|nil Last relative anchor point.
---@field mode "chain"|"independent"|nil Last positioning mode.

---@class ECM_TrackedFrame : Frame
---@field _layoutCache ECM_LayoutCache|nil Cached layout parameters.


local _, ns = ...
local ECM = ns.Addon
local Util = ns.Util
local FrameLayoutMixin = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.FrameLayoutMixin = FrameLayoutMixin

--- Applies layout parameters to a frame, caching state to reduce updates.
---@param frame ECM_TrackedFrame
---@param anchor Frame The anchor frame to attach to.
---@param offsetX number Horizontal offset from the anchor point.
---@param offsetY number Vertical offset from the anchor point.
---@param width number|nil Width to set on the frame, or nil to skip.
---@param height number|nil Height to set on the frame, or nil to skip.
---@param anchorPoint AnchorPoint|nil Anchor point on the frame (default "TOPLEFT").
---@param anchorRelativePoint AnchorPoint|nil Relative point on the anchor (default "BOTTOMLEFT").
---@param mode "chain"|"independent"|nil Positioning mode identifier.
---@return boolean changed True if layout changed
function FrameLayoutMixin.ApplyLayout(frame, anchor, offsetX, offsetY, width, height, anchorPoint, anchorRelativePoint, mode)
    assert(frame, "frame required")
    assert(anchor, "anchor required")

    offsetX = offsetX or 0
    offsetY = offsetY or 0
    anchorPoint = anchorPoint or "TOPLEFT"
    anchorRelativePoint = anchorRelativePoint or "BOTTOMLEFT"
    local layoutCache = frame._layoutCache or {}

    local layoutChanged = layoutCache.anchor ~= anchor
        or layoutCache.offsetX ~= offsetX
        or layoutCache.offsetY ~= offsetY
        or layoutCache.anchorPoint ~= anchorPoint
        or layoutCache.anchorRelativePoint ~= anchorRelativePoint
        or layoutCache.mode ~= mode

    if layoutChanged then
        frame:ClearAllPoints()
        if mode == "chain" then
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", offsetX, offsetY)
            frame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", offsetX, offsetY)
        else
            assert(anchor ~= nil, "anchor required for independent mode")
            frame:SetPoint(anchorPoint, anchor, anchorRelativePoint, offsetX, offsetY)
        end

        layoutCache.anchor = anchor
        layoutCache.offsetX = offsetX
        layoutCache.offsetY = offsetY
        layoutCache.anchorPoint = anchorPoint
        layoutCache.anchorRelativePoint = anchorRelativePoint
        layoutCache.mode = mode
    end

    if height and layoutCache.height ~= height then
        frame:SetHeight(height)
        layoutCache.height = height
        layoutChanged = true
    elseif height == nil then
        layoutCache.height = nil
    end

    if width and layoutCache.width ~= width then
        frame:SetWidth(width)
        layoutCache.width = width
        layoutChanged = true
    elseif width == nil then
        layoutCache.width = nil
    end

    return layoutChanged
end

--- Attaches layout methods and cache to a frame.
---@param frame ECM_TrackedFrame|Frame
function FrameLayoutMixin.AttachTo(frame)
    assert(frame, "frame required")
    if not frame._layoutCache then
        frame._layoutCache = {}
    end
    frame.ApplyLayout = FrameLayoutMixin.ApplyLayout
    frame.InvalidateLayout = FrameLayoutMixin.InvalidateLayout
end
