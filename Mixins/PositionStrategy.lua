-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class ECM_LayoutParams Layout parameters for frame positioning.
---@field anchor Frame Anchor frame to position relative to.
---@field offsetX number Horizontal offset from anchor.
---@field offsetY number Vertical offset from anchor.
---@field width number|nil Explicit width (nil = inherit from anchor).
---@field height number|nil Explicit height (nil = skip height application).
---@field anchorPoint AnchorPoint Point on the frame to attach.
---@field anchorRelativePoint AnchorPoint Point on the anchor to attach to.
---@field matchAnchorWidth boolean True to match anchor width using dual-point anchoring.
---@field mode "chain"|"independent" Positioning mode identifier.


---@class ECM_PositionedFrame : Frame Frame with layout methods attached via PositionMixin.
---@field _layoutCache ECM_LayoutCache|nil Cached layout parameters.
---@field ApplyLayout fun(self: ECM_PositionedFrame, params: ECM_LayoutParams, cache?: ECM_LayoutCache): boolean Applies layout parameters.
---@field InvalidateLayout fun(self: ECM_PositionedFrame, cache?: ECM_LayoutCache) Clears cached layout state.

---@class ECMPositionedModule : ECMModule Module with position calculation support.
---@field _configKey string Configuration key for module settings.
---@field GetConfig fun(self: ECMPositionedModule): table Gets the profile configuration.
---@field GetName fun(self: ECMPositionedModule): string Gets the module name.
---@field GetFrameIfShown fun(self: ECMPositionedModule): ECM_PositionedFrame|nil Gets the frame if visible.

---@class PositionMixin Mixin providing frame positioning strategies for bar modules.
---@field CaptureCurrentTopOffset fun(frame: ECM_PositionedFrame): number, number Captures current offsets for a frame.
---@field AttachTo fun(frame: ECM_PositionedFrame) Attaches layout methods to a frame.
---@field InvalidateLayout fun(frame: ECM_PositionedFrame, cache?: ECM_LayoutCache) Clears cached layout state.
---@field ApplyLayout fun(frame: ECM_PositionedFrame, params: ECM_LayoutParams, cache?: ECM_LayoutCache): boolean Applies layout parameters.
---@field CalculateLayout fun(module: ECMPositionedModule): ECM_LayoutParams, "chain"|"independent" Calculates layout for a bar module.
---@field CalculateBuffBarsLayout fun(cfg: table, profile: table): ECM_LayoutParams, "chain"|"independent" Calculates layout for BuffBars viewer.

local _, ns = ...
local ECM = ns.Addon
local Util = ns.Util
local PositionMixin = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.PositionMixin = PositionMixin
ns.Mixins.PositionStrategy = PositionMixin

local CHAIN_ORDER = { "PowerBar", "ResourceBar", "RuneBar" }

local function GetBarFrame()
    assert(ns.Mixins and ns.Mixins.BarFrame, "BarFrame mixin required")
    return ns.Mixins.BarFrame
end

--- Calculates the anchor frame for a bar module in chain mode.
--- Chain order: Viewer -> PowerBar -> ResourceBar -> RuneBar.
--- When moduleName is nil, returns the bottom-most visible bar (for BuffBars).
---@param addon table The EnhancedCooldownManager addon table
---@param moduleName string|nil Module name to find anchor for (nil = append to bottom)
---@return Frame anchor The frame to anchor to
---@return boolean isFirstInChain True if anchoring directly to the viewer
local function ResolveChainAnchor(addon, moduleName)
    assert(addon, "addon required")
    local profile = addon.db and addon.db.profile
    assert(profile, "profile required")

    local BarFrame = GetBarFrame()
    local viewer = BarFrame.GetViewerAnchor()

    local stopIndex = #CHAIN_ORDER + 1
    if moduleName then
        for i, name in ipairs(CHAIN_ORDER) do
            if name == moduleName then
                stopIndex = i
                break
            end
        end
    end

    local lastVisible
    for i = 1, stopIndex - 1 do
        local modName = CHAIN_ORDER[i]
        local mod = addon[modName]
        if mod then
            local configKey = mod._configKey
            local cfg = configKey and profile[configKey]
            local isIndependent = cfg and cfg.anchorMode == "independent"
            if not isIndependent then
                if mod.GetFrameIfShown then
                    local f = mod:GetFrameIfShown()
                    if f then
                        lastVisible = f
                    end
                else
                    Util.Log("PositionStrategy", "Chain module missing GetFrameIfShown", { module = modName })
                end
            end
        end
    end

    if lastVisible then
        return lastVisible, false
    end

    return viewer, true
end

---@param cfg table|nil
---@param profile table
---@param anchor Frame
---@param isFirstInChain boolean
---@return ECM_LayoutParams
local function BuildChainLayoutParams(cfg, profile, anchor, isFirstInChain)
    local BarFrame = GetBarFrame()
    return {
        anchor = anchor,
        offsetX = 0,
        offsetY = isFirstInChain and -BarFrame.GetTopGapOffset(cfg, profile) or -((cfg and cfg.offsetY) or 0),
        width = nil,
        height = BarFrame.GetBarHeight(cfg, profile),
        anchorPoint = "TOPLEFT",
        anchorRelativePoint = "BOTTOMLEFT",
        matchAnchorWidth = true,
        mode = "chain",
    }
end

---@param cfg table|nil
---@param profile table
---@return ECM_LayoutParams
local function BuildIndependentLayoutParams(cfg, profile)
    assert(Util and Util.PixelSnap, "Util.PixelSnap required")
    local BarFrame = GetBarFrame()
    return {
        anchor = UIParent,
        offsetX = (cfg and cfg.offsetX) or 0,
        offsetY = (cfg and cfg.offsetY) or 0,
        width = Util.PixelSnap((cfg and cfg.width) or BarFrame.DEFAULT_BAR_WIDTH),
        height = BarFrame.GetBarHeight(cfg, profile),
        anchorPoint = "CENTER",
        anchorRelativePoint = "CENTER",
        matchAnchorWidth = false,
        mode = "independent",
    }
end

---@param cfg table|nil
---@param profile table
---@return ECM_LayoutParams
local function BuildBuffBarsIndependentParams(cfg, profile)
    assert(Util and Util.PixelSnap, "Util.PixelSnap required")
    local BarFrame = GetBarFrame()
    return {
        anchor = UIParent,
        offsetX = (cfg and cfg.offsetX) or 0,
        offsetY = (cfg and cfg.offsetY) or 0,
        width = Util.PixelSnap((cfg and cfg.width) or BarFrame.DEFAULT_BAR_WIDTH),
        height = nil,
        anchorPoint = "TOP",
        anchorRelativePoint = "TOP",
        matchAnchorWidth = false,
        mode = "independent",
    }
end

--- Captures the current top-anchored offsets for a frame relative to UIParent.
---@param frame ECM_PositionedFrame
---@return number offsetX, number offsetY
function PositionMixin.CaptureCurrentTopOffset(frame)
    assert(frame, "frame required")
    local top = frame:GetTop()
    local centerX = frame:GetCenter()
    local parentCenterX = UIParent:GetCenter()
    local parentTop = UIParent:GetTop()

    if top and centerX and parentCenterX and parentTop then
        return centerX - parentCenterX, top - parentTop
    end

    return 0, 0
end

--- Attaches layout methods and cache to a frame.
---@param frame ECM_PositionedFrame
function PositionMixin.AttachTo(frame)
    assert(frame, "frame required")
    if not frame._layoutCache then
        frame._layoutCache = {}
    end
    frame.ApplyLayout = PositionMixin.ApplyLayout
    frame.InvalidateLayout = PositionMixin.InvalidateLayout
end

--- Clears cached layout state for a frame.
---@param frame ECM_PositionedFrame
function PositionMixin.InvalidateLayout(frame, cache)
    assert(frame, "frame required")

    if cache ~= nil then
        assert(type(cache) == "table", "cache must be a table when provided")
        for k in pairs(cache) do
            cache[k] = nil
        end
        return
    end

    frame._layoutCache = {}
end

--- Applies layout parameters to a frame, caching state to reduce updates.
---@param frame ECM_PositionedFrame
---@param params ECM_LayoutParams
---@return boolean changed True if layout changed
function PositionMixin.ApplyLayout(frame, params, cache)
    assert(frame, "frame required")
    assert(params, "layout params required")
    assert(params.anchor, "layout params missing anchor")

    if cache ~= nil then
        assert(type(cache) == "table", "cache must be a table when provided")
    end

    local layoutCache = cache or frame._layoutCache
    if not layoutCache then
        layoutCache = {}
        if not cache then
            frame._layoutCache = layoutCache
        end
    elseif not cache and frame._layoutCache ~= layoutCache then
        frame._layoutCache = layoutCache
    end

    local offsetX = params.offsetX or 0
    local offsetY = params.offsetY or 0

    local layoutChanged = layoutCache.anchor ~= params.anchor
        or layoutCache.offsetX ~= offsetX
        or layoutCache.offsetY ~= offsetY
        or layoutCache.matchAnchorWidth ~= params.matchAnchorWidth
        or layoutCache.anchorPoint ~= params.anchorPoint
        or layoutCache.anchorRelativePoint ~= params.anchorRelativePoint

    if layoutChanged then
        frame:ClearAllPoints()
        if params.matchAnchorWidth then
            frame:SetPoint("TOPLEFT", params.anchor, "BOTTOMLEFT", offsetX, offsetY)
            frame:SetPoint("TOPRIGHT", params.anchor, "BOTTOMRIGHT", offsetX, offsetY)
        else
            frame:SetPoint(params.anchorPoint, params.anchor, params.anchorRelativePoint, offsetX, offsetY)
        end

        layoutCache.anchor = params.anchor
        layoutCache.offsetX = offsetX
        layoutCache.offsetY = offsetY
        layoutCache.matchAnchorWidth = params.matchAnchorWidth
        layoutCache.anchorPoint = params.anchorPoint
        layoutCache.anchorRelativePoint = params.anchorRelativePoint
    end

    if params.height and layoutCache.height ~= params.height then
        frame:SetHeight(params.height)
        layoutCache.height = params.height
        layoutChanged = true
    elseif params.height == nil then
        layoutCache.height = nil
    end

    if params.width and layoutCache.width ~= params.width then
        frame:SetWidth(params.width)
        layoutCache.width = params.width
        layoutChanged = true
    elseif params.width == nil then
        layoutCache.width = nil
    end

    if params.mode then
        layoutCache.lastMode = params.mode
    end

    return layoutChanged
end

--- Calculates layout params for a bar module based on its config.
---@param module ECMPositionedModule
---@return ECM_LayoutParams params
---@return "chain"|"independent" anchorMode
function PositionMixin.CalculateLayout(module)
    assert(module, "module required")
    assert(module._configKey, "module missing _configKey")

    local profile = module:GetConfig() or (ECM.db and ECM.db.profile)
    assert(profile, "profile required")
    local cfg = profile[module._configKey]

    local anchorMode = (cfg and cfg.anchorMode) or "chain"
    if anchorMode == "independent" then
        return BuildIndependentLayoutParams(cfg, profile), anchorMode
    end

    local anchor, isFirstInChain = ResolveChainAnchor(ECM, module:GetName())
    return BuildChainLayoutParams(cfg, profile, anchor, isFirstInChain), anchorMode
end

--- Calculates layout params for the BuffBarCooldownViewer.
---@param cfg table
---@param profile table
---@return ECM_LayoutParams params
---@return "chain"|"independent" anchorMode
function PositionMixin.CalculateBuffBarsLayout(cfg, profile)
    assert(profile, "profile required")

    local anchorMode = (cfg and cfg.anchorMode) or "chain"
    if anchorMode == "independent" then
        return BuildBuffBarsIndependentParams(cfg, profile), anchorMode
    end

    local anchor, isFirstInChain = ResolveChainAnchor(ECM, nil)
    local params = BuildChainLayoutParams(cfg, profile, anchor, isFirstInChain)

    -- BuffBarCooldownViewer is a container whose height is determined by its children.
    -- Avoid forcing a fixed bar height.
    params.height = nil

    return params, anchorMode
end
