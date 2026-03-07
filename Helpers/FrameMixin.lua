-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local FrameUtil = ECM.FrameUtil
local FrameMixin = {}
ECM.FrameMixin = FrameMixin

---@alias AnchorPoint string

---@class FrameMixin : AceModule Frame mixin that owns visibility and config access.
---@field _configKey string|nil Config key for this frame's section.
---@field IsHidden boolean|nil Whether the frame is currently hidden.
---@field InnerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field Name string Name of the frame.

--- Determine the correct anchor for this specific frame in the fixed order.
--- @param frameName string|nil The name of the current frame, or nil if first in chain.
--- @return Frame The frame to anchor to.
--- @return boolean isFirst True if this is the first frame in the chain.
function FrameMixin:GetNextChainAnchor(frameName)
    -- Find the ideal position
    local stopIndex = #ECM.Constants.CHAIN_ORDER + 1
    if frameName then
        for i, name in ipairs(ECM.Constants.CHAIN_ORDER) do
            if name == frameName then
                stopIndex = i
                break
            end
        end
    end

    -- Work backwards to identify the first valid frame to anchor to.
    -- Visibility is intentionally not required because layout updates can
    -- occur while frames are transitioning hide/show.
    local addon = ns.Addon
    for i = stopIndex - 1, 1, -1 do
        local barName = ECM.Constants.CHAIN_ORDER[i]
        local barModule = addon and addon:GetECMModule(barName, true)
        if barModule and barModule:IsEnabled() and barModule:ShouldShow() then
            local moduleConfig = barModule:GetModuleConfig()
            if moduleConfig and moduleConfig.anchorMode == ECM.Constants.ANCHORMODE_CHAIN and barModule.InnerFrame then
                ECM.Log(self.Name, "GetNextChainAnchor ".. barName .." <-- " .. (frameName or "nil"))
                return barModule.InnerFrame, false
            end
        end
    end

    -- If none of the preceding frames in the chain are valid, anchor to the viewer as the first.
    ECM.Log(self.Name, "GetNextChainAnchor Viewer <-- " .. (frameName or "nil"))
    return _G["EssentialCooldownViewer"] or UIParent, true
end

function FrameMixin:SetHidden(hide)
    self.IsHidden = hide
end

--- Determines whether this frame should be shown at this particular moment. Can be overridden.
function FrameMixin:ShouldShow()
    local config = self:GetModuleConfig()
    return not self.IsHidden and (config == nil or config.enabled ~= false)
end

function FrameMixin:CreateFrame()
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local name = "ECM" .. self.Name
    local frame = CreateFrame("Frame", name, UIParent)

    local barHeight = (moduleConfig and moduleConfig.height)
        or (globalConfig and globalConfig.barHeight)
        or ECM.Constants.DEFAULT_BAR_HEIGHT

    frame:SetFrameStrata("MEDIUM")
    frame:SetHeight(barHeight)
    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAllPoints(frame)

    -- Optional border frame
    frame.Border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Border:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.Border:Hide()

    return frame
end

---@param point string|nil
---@param fallback string
---@return string
function FrameMixin.ChainRightPoint(point, fallback)
    if point == "TOPLEFT" then
        return "TOPRIGHT"
    end
    if point == "BOTTOMLEFT" then
        return "BOTTOMRIGHT"
    end
    return fallback
end

---@param direction string|nil
---@return string
function FrameMixin.NormalizeGrowDirection(direction)
    return direction == ECM.Constants.GROW_DIRECTION_UP
        and ECM.Constants.GROW_DIRECTION_UP
        or ECM.Constants.GROW_DIRECTION_DOWN
end

--- Default layout parameter calculation for chain/free anchor modes.
--- Modules with custom positioning (e.g. BuffBars) override this.
---@return table params Layout parameters: mode, anchor, isFirst, anchorPoint, anchorRelativePoint, offsetX, offsetY, width, height
function FrameMixin:CalculateLayoutParams()
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()

    if moduleConfig.anchorMode == ECM.Constants.ANCHORMODE_FREE then
        return {
            mode = ECM.Constants.ANCHORMODE_FREE,
            anchor = UIParent,
            isFirst = false,
            anchorPoint = "CENTER",
            anchorRelativePoint = "CENTER",
            offsetX = moduleConfig.offsetX or 0,
            offsetY = moduleConfig.offsetY or ECM.Constants.DEFAULT_FREE_ANCHOR_OFFSET_Y,
            height = moduleConfig.height or globalConfig.barHeight,
            width = moduleConfig.width or globalConfig.barWidth,
        }
    end

    local anchor, isFirst = self:GetNextChainAnchor(self.Name)
    local growsUp = self.NormalizeGrowDirection(globalConfig and globalConfig.moduleGrowDirection) == ECM.Constants.GROW_DIRECTION_UP
    local gap = isFirst and ((globalConfig and globalConfig.offsetY) or 0) or (globalConfig.moduleSpacing or 0)

    return {
        mode = ECM.Constants.ANCHORMODE_CHAIN,
        anchor = anchor,
        isFirst = isFirst,
        anchorPoint = growsUp and "BOTTOMLEFT" or "TOPLEFT",
        anchorRelativePoint = growsUp and "TOPLEFT" or "BOTTOMLEFT",
        offsetX = 0,
        offsetY = growsUp and gap or -gap,
        height = moduleConfig.height or globalConfig.barHeight,
    }
end

--- Applies positioning to a frame based on layout parameters.
--- Handles ShouldShow check, layout calculation, and anchor positioning.
---@return table|nil params Layout params if shown, nil if hidden
function FrameMixin:ApplyFramePosition()
    local frame = self.InnerFrame
    if not self:ShouldShow() then
        frame:Hide()
        return nil
    end

    -- Re-show after a prior hide. Cannot defer to Refresh() because
    -- ThrottledRefresh may suppress the call during rapid transitions.
    if not frame:IsShown() then
        frame:Show()
    end

    local params = self:CalculateLayoutParams()
    local anchors
    if params.mode == ECM.Constants.ANCHORMODE_CHAIN then
        local lp = params.anchorPoint or "TOPLEFT"
        local lr = params.anchorRelativePoint or "BOTTOMLEFT"
        anchors = {
            { lp, params.anchor, lr, params.offsetX, params.offsetY },
            { self.ChainRightPoint(lp, "TOPRIGHT"), params.anchor, self.ChainRightPoint(lr, "BOTTOMRIGHT"), params.offsetX, params.offsetY },
        }
    else
        assert(params.anchor ~= nil, "anchor required for free anchor mode")
        anchors = {
            { params.anchorPoint, params.anchor, params.anchorRelativePoint, params.offsetX, params.offsetY },
        }
    end

    FrameUtil.LazySetAnchors(frame, anchors)
    return params
end

--- Standard layout pass: positioning, dimensions, border, background color.
--- Calls self:ThrottledRefresh at the end to update values.
---@param why string|nil
---@return boolean
function FrameMixin:UpdateLayout(why)
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local frame = self.InnerFrame
    local borderConfig = moduleConfig.border

    local params = self:ApplyFramePosition()
    if not params then
        return false
    end

    if params.height then
        FrameUtil.LazySetHeight(frame, params.height)
    end

    if params.width then
        FrameUtil.LazySetWidth(frame, params.width)
    end

    if borderConfig then
        FrameUtil.LazySetBorder(frame, borderConfig)
    end

    ECM.DebugAssert(moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor), "bgColor not defined in config for frame " .. self.Name)
    local bgColor = moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor) or ECM.Constants.DEFAULT_BG_COLOR
    FrameUtil.LazySetBackgroundColor(frame, bgColor)

    self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
    return true
end

--- Handles common refresh logic for FrameMixin-derived frames.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @param force boolean|nil Whether to force a refresh, even if the bar is hidden.
--- @return boolean continue True if the frame should continue refreshing, false to skip.
function FrameMixin:Refresh(why, force)
    return force or self:ShouldShow()
end

--- Rate-limited refresh. Skips if called within updateFrequency window.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @return boolean refreshed True if Refresh() was called
function FrameMixin:ThrottledRefresh(why)
    local globalConfig = self:GetGlobalConfig()
    local freq = (globalConfig and globalConfig.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end
    self:Refresh(why)
    self._lastUpdate = GetTime()
    return true
end

--- Checks if the module is ready for layout updates.
--- @return boolean ready True if the module is ready for updates.
function FrameMixin:IsReady()
    return self:IsEnabled() and self.InnerFrame ~= nil
        and self:GetGlobalConfig() ~= nil and self:GetModuleConfig() ~= nil
end

--- Internal: checks readiness and runs the coalesced layout update.
local function updateLayoutDeferred(self)
    if not self:IsReady() then
        ECM.Log(self.Name, "Layout update skipped (not ready)")
        self._updateLayoutPending = false
        self._pendingWhy = nil
        return
    end

    -- Clear pending state to allow re-entry.
    local why = self._pendingWhy
    self._updateLayoutPending = false
    self._pendingWhy = nil

    self:UpdateLayout(why)

    -- Schedule second-pass if requested.
    if self._secondPassPending then
        self._secondPassPending = false
        C_Timer.After(ECM.Constants.LIFECYCLE_SECOND_PASS_DELAY, function()
            self:ThrottledUpdateLayout("SecondPass")
        end)
    end
end

--- Requests a layout update for this module.
--- @param reason string Debug trace string identifying the caller.
--- @param opts table|nil Optional parameters: { secondPass = boolean }
function FrameMixin:ThrottledUpdateLayout(reason, opts)
    ECM.DebugAssert(reason, "ThrottledUpdateLayout: reason is required")

    -- Bail immediately if the module is disabled.
    if self.IsEnabled and not self:IsEnabled() then
        return
    end

    -- Request second-pass if needed.
    if opts and opts.secondPass then
        self._secondPassPending = true
    end

    -- Keep the first reason that triggered this batch for tracing.
    -- Queue exactly once if not already queued.
    if not self._updateLayoutPending then
        self._pendingWhy = reason
        self._updateLayoutPending = true
        C_Timer.After(0, function()
            updateLayoutDeferred(self)
        end)
    end
end

function FrameMixin.AssertValid(target)
    assert(target and type(target) == "table", "target is not a table")
    assert(target.Name, "target is missing a Name")
    assert(target.InnerFrame, "target '" .. target.Name .. "' is missing an InnerFrame")
end

--- Applies the frame and common module mixins to the target.
--- @param target table table to apply the mixin to.
--- @param name string the module name. must be unique.
function FrameMixin.AddMixin(target, name)
    ECM.ModuleMixin.AddMixin(target, name)

    for k, v in pairs(FrameMixin) do
        if type(v) == "function" and target[k] == nil then
            target[k] = v
        end
    end

    if not target.InnerFrame then
        target.InnerFrame = target:CreateFrame()
    end

    target.IsHidden = false
end
