-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local L = ECM.L
local FrameUtil = ECM.FrameUtil
local LibEditMode = LibStub("LibEditMode")
local EditMode = ECM.EditMode or {}
EditMode.Lib = LibEditMode
ECM.EditMode = EditMode
local FrameMixin = {}
ECM.FrameMixin = FrameMixin

local FrameMixinProto = setmetatable({}, { __index = ECM.ModuleMixin.Proto })

--- Gets the active Edit Mode layout name.
function EditMode.GetActiveLayoutName()
    return LibEditMode:GetActiveLayoutName()
end

--- Gets a saved Edit Mode position for the active layout.
---@param positions table<string, ECM_EditModePosition>|nil
---@param layoutName string|nil
---@return ECM_EditModePosition
---@return string|nil
function EditMode.GetPosition(positions, layoutName)
    local activeLayoutName = layoutName
    if activeLayoutName == nil then
        activeLayoutName = EditMode.GetActiveLayoutName()
    end

    if type(positions) == "table" then
        local position = activeLayoutName and positions[activeLayoutName]
        if position then
            return position, activeLayoutName
        end
    end

    return { point = C.EDIT_MODE_DEFAULT_POINT, x = 0, y = 0 }, activeLayoutName
end

---@param container table|nil
---@param fieldName string
---@param layoutName string
---@param point string
---@param x number
---@param y number
function EditMode.SavePosition(container, fieldName, layoutName, point, x, y)
    if not container then
        return
    end

    if type(container[fieldName]) ~= "table" then
        container[fieldName] = {}
    end

    container[fieldName][layoutName] = { point = point, x = x, y = y }
end

---@param frame Frame|nil
---@param options table
function EditMode.RegisterFrame(frame, options)
    if not frame then
        return
    end

    local defaultPosition = options.defaultPosition or {
        point = C.EDIT_MODE_DEFAULT_POINT,
        x = 0,
        y = 0,
    }

    frame.editModeName = options.name

    LibEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        options.onPositionChanged(layoutName, point, x, y)
    end, defaultPosition, options.name)

    if options.hideSelection then
        local selections = LibEditMode.frameSelections
        local selection = selections and selections[frame]
        if selection then
            selection:HookScript("OnShow", function(sel)
                if options.hideSelection() then
                    sel:Hide()
                end
            end)
        end
    end

    if options.settings then
        LibEditMode:AddFrameSettings(frame, options.settings)
    end
end

-- Re-apply layout for all registered modules on Edit Mode transitions and layout switches.
-- Runtime.ScheduleLayoutUpdate provides the single deferred escape hatch out of
-- the secure Edit Mode execution context.
LibEditMode:RegisterCallback("enter", function()
    ECM.Runtime.ScheduleLayoutUpdate(0, "EditModeEnter")
end)
LibEditMode:RegisterCallback("exit", function()
    ECM.Runtime.ScheduleLayoutUpdate(0, "EditModeExit")
end)
LibEditMode:RegisterCallback("layout", function()
    ECM.Runtime.ScheduleLayoutUpdate(0, "EditModeLayout")
end)

---@alias AnchorPoint string

---@class FrameMixin : AceModule Frame mixin that owns visibility and config access.
---@field _configKey string|nil Config key for this frame's section.
---@field IsHidden boolean|nil Whether the frame is currently hidden.
---@field InnerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field Name string Name of the frame.

--- Determine the correct anchor for this specific frame in the fixed order.
--- @param frameName string|nil The name of the current frame, or nil if first in chain.
--- @param anchorMode string|nil The anchor mode to filter by (defaults to ANCHORMODE_CHAIN).
--- @return Frame The frame to anchor to.
--- @return boolean isFirst True if this is the first frame in the chain.
function FrameMixinProto:GetNextChainAnchor(frameName, anchorMode)
    anchorMode = anchorMode or ECM.Constants.ANCHORMODE_CHAIN

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
            if moduleConfig and moduleConfig.anchorMode == anchorMode and barModule.InnerFrame then
                return barModule.InnerFrame, false
            end
        end
    end

    if anchorMode == ECM.Constants.ANCHORMODE_DETACHED then
        return ECM.Runtime.DetachedAnchor or UIParent, true
    end

    return _G["EssentialCooldownViewer"] or UIParent, true
end

function FrameMixinProto:SetHidden(hide)
    self.IsHidden = hide
    if self.InnerFrame then
        -- Hide immediately, but defer showing until the next layout pass to ensure proper anchoring.
        if hide then
            self.InnerFrame:Hide()
        else
            self:ThrottledUpdateLayout("SetHidden")
        end
    end
end

--- Determines whether this frame should be shown at this particular moment. Can be overridden.
function FrameMixinProto:ShouldShow()
    local config = self:GetModuleConfig()
    return not self.IsHidden and (config == nil or config.enabled ~= false)
end

--- Determines whether this module should register its frame with ECM Edit Mode.
--- Modules backed by Blizzard-owned system frames can override this to opt out.
---@return boolean
function FrameMixinProto:ShouldRegisterEditMode()
    return true
end

function FrameMixinProto:CreateFrame()
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

--- Creates the InnerFrame (if not already present) and registers Edit Mode.
--- Call this in OnEnable after AddMixin to separate object construction from frame creation.
function FrameMixinProto:EnsureFrame()
    if not self.InnerFrame then
        self.InnerFrame = self:CreateFrame()
    end
    if self:ShouldRegisterEditMode() and self._editModeRegisteredFrame ~= self.InnerFrame then
        self:_RegisterEditMode()
    end
end

---@param point string|nil
---@param fallback string
---@return string
function FrameMixinProto.ChainRightPoint(point, fallback)
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
function FrameMixinProto.NormalizeGrowDirection(direction)
    return direction == C.GROW_DIRECTION_UP and C.GROW_DIRECTION_UP or C.GROW_DIRECTION_DOWN
end

---@param self FrameMixin
---@param globalConfig table
---@param moduleConfig table
---@param mode string
---@return table
local function getStackedLayoutParams(self, globalConfig, moduleConfig, mode)
    local isDetached = mode == C.ANCHORMODE_DETACHED
    if not isDetached then
        mode = C.ANCHORMODE_CHAIN
    end

    local anchor, isFirst = self:GetNextChainAnchor(self.Name, mode)

    local directionKey = isDetached and "detachedGrowDirection" or "moduleGrowDirection"
    local growsUp = self.NormalizeGrowDirection(globalConfig and globalConfig[directionKey]) == C.GROW_DIRECTION_UP

    local gap
    if isDetached then
        gap = isFirst and 0 or ((globalConfig and globalConfig.detachedModuleSpacing) or 0)
    else
        gap = isFirst and ((globalConfig and globalConfig.offsetY) or 0)
            or ((globalConfig and globalConfig.moduleSpacing) or 0)
    end

    local anchorPoint = growsUp and "BOTTOMLEFT" or "TOPLEFT"
    -- Detached first module anchors inside its container; all other cases anchor outside the predecessor.
    local flippedPoint = growsUp and "TOPLEFT" or "BOTTOMLEFT"
    local anchorRelativePoint = (isDetached and isFirst) and anchorPoint or flippedPoint

    return {
        mode = mode,
        anchor = anchor,
        isFirst = isFirst,
        anchorPoint = anchorPoint,
        anchorRelativePoint = anchorRelativePoint,
        offsetX = 0,
        offsetY = growsUp and gap or -gap,
        height = moduleConfig.height or globalConfig.barHeight,
    }
end

--- Default layout parameter calculation for chain/detached/free anchor modes.
--- Modules with custom positioning (e.g. BuffBars) override this.
---@return table params Layout parameters: mode, anchor, isFirst, anchorPoint, anchorRelativePoint, offsetX, offsetY, width, height
function FrameMixinProto:CalculateLayoutParams()
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local mode = moduleConfig.anchorMode or C.ANCHORMODE_CHAIN

    if mode == C.ANCHORMODE_FREE then
        local pos = EditMode.GetPosition(moduleConfig and moduleConfig.editModePositions)
        return {
            mode = C.ANCHORMODE_FREE,
            anchor = UIParent,
            isFirst = false,
            anchorPoint = pos.point,
            anchorRelativePoint = pos.point,
            offsetX = pos.x,
            offsetY = pos.y,
            height = moduleConfig.height or globalConfig.barHeight,
            width = moduleConfig.width or globalConfig.barWidth,
        }
    end

    return getStackedLayoutParams(self, globalConfig, moduleConfig, mode)
end

--- Applies positioning to a frame based on layout parameters.
--- Handles ShouldShow check, layout calculation, and anchor positioning.
---@return table|nil params Layout params if shown, nil if hidden
function FrameMixinProto:ApplyFramePosition()
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
    if params.mode == ECM.Constants.ANCHORMODE_FREE then
        assert(params.anchor ~= nil, "anchor required for free anchor mode")
        anchors = {
            { params.anchorPoint, params.anchor, params.anchorRelativePoint, params.offsetX, params.offsetY },
        }
    else
        -- Chain and detached both use 2-point anchoring
        local lp = params.anchorPoint or "TOPLEFT"
        local lr = params.anchorRelativePoint or "BOTTOMLEFT"
        anchors = {
            { lp, params.anchor, lr, params.offsetX, params.offsetY },
            {
                self.ChainRightPoint(lp, "TOPRIGHT"),
                params.anchor,
                self.ChainRightPoint(lr, "BOTTOMRIGHT"),
                params.offsetX,
                params.offsetY,
            },
        }
    end

    FrameUtil.LazySetAnchors(frame, anchors)
    return params
end

--- Standard layout pass: positioning, dimensions, border, background color.
--- Calls self:ThrottledRefresh at the end to update values.
---@param why string|nil
---@return boolean
function FrameMixinProto:UpdateLayout(why)
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

    ECM.DebugAssert(
        moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor),
        "bgColor not defined in config for frame " .. self.Name
    )
    local bgColor = moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor) or ECM.Constants.DEFAULT_BG_COLOR
    FrameUtil.LazySetBackgroundColor(frame, bgColor)

    self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
    return true
end

--- Handles common refresh logic for FrameMixin-derived frames.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @param force boolean|nil Whether to force a refresh, even if the bar is hidden.
--- @return boolean continue True if the frame should continue refreshing, false to skip.
function FrameMixinProto:Refresh(why, force)
    return force or self:ShouldShow()
end

--- Rate-limited refresh. Skips if called within updateFrequency window.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @return boolean refreshed True if Refresh() was called
function FrameMixinProto:ThrottledRefresh(why)
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
function FrameMixinProto:IsReady()
    return self:IsEnabled()
        and self.InnerFrame ~= nil
        and self:GetGlobalConfig() ~= nil
        and self:GetModuleConfig() ~= nil
end

--- Internal: checks readiness and runs the coalesced layout update.
local function updateLayoutDeferred(self)
    if not self._updateLayoutPending then
        return
    end

    if not self:IsReady() then
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
            if self.IsEnabled and not self:IsEnabled() then
                return
            end
            if self._updateLayoutPending then
                return
            end

            -- The second-pass timer already deferred out of the original
            -- layout batch, so run it directly unless a newer batch won the race.
            self._pendingWhy = "SecondPass"
            self._updateLayoutPending = true
            updateLayoutDeferred(self)
        end)
    end
end

--- Runs a layout update synchronously, bypassing the C_Timer batch.
--- Use for Edit Mode drag where 1-frame latency is noticeable.
--- @param reason string Debug trace string identifying the caller.
function FrameMixinProto:UpdateLayoutImmediately(reason)
    if self.IsEnabled and not self:IsEnabled() then
        return
    end
    if not self:IsReady() then
        return
    end
    self._updateLayoutPending = false
    self._pendingWhy = nil
    self:UpdateLayout(reason)
end

--- Requests a layout update for this module.
--- @param reason string Debug trace string identifying the caller.
--- @param opts table|nil Optional parameters: { secondPass = boolean }
function FrameMixinProto:ThrottledUpdateLayout(reason, opts)
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

--- Saves an Edit Mode position for the given layout.
---@param layoutName string Edit Mode layout name.
---@param point string Anchor point (e.g. "CENTER").
---@param x number X offset.
---@param y number Y offset.
function FrameMixinProto:_SaveEditModePosition(layoutName, point, x, y)
    local cfg = self:GetModuleConfig()
    EditMode.SavePosition(cfg, "editModePositions", layoutName, point, x, y)
end

--- Registers this module's frame with Edit Mode for drag positioning.
--- Called once during AddMixin after InnerFrame is created.
--- No-op if InnerFrame is nil (e.g. when the Blizzard viewer hasn't loaded yet).
function FrameMixinProto:_RegisterEditMode()
    local frame = self.InnerFrame
    if not frame or self._editModeRegisteredFrame == frame then
        return
    end

    local module = self
    EditMode.RegisterFrame(frame, {
        name = "ECM: " .. self.Name,
        onPositionChanged = function(layoutName, point, x, y)
            module:_SaveEditModePosition(layoutName, point, x, y)
            module:UpdateLayoutImmediately("EditModeDrag")
        end,
        hideSelection = function()
            local cfg = module:GetModuleConfig()
            return cfg and cfg.anchorMode ~= C.ANCHORMODE_FREE
        end,
        settings = {
            {
                kind = LibEditMode.SettingType.Slider,
                name = L["WIDTH"],
                get = function()
                    local cfg = module:GetModuleConfig()
                    return (cfg and cfg.width) or C.DEFAULT_BAR_WIDTH
                end,
                set = function(_, value)
                    local cfg = module:GetModuleConfig()
                    if cfg then
                        cfg.width = value
                        module:UpdateLayoutImmediately("EditModeWidth")
                    end
                end,
                default = C.DEFAULT_BAR_WIDTH,
                minValue = 100,
                maxValue = 600,
                valueStep = 1,
                allowInput = true,
                hidden = function()
                    local cfg = module:GetModuleConfig()
                    return cfg and cfg.anchorMode == C.ANCHORMODE_DETACHED
                end,
            },
        },
    })

    self._editModeRegisteredFrame = frame
end

FrameMixin.Proto = FrameMixinProto
setmetatable(FrameMixin, { __index = FrameMixinProto })

function FrameMixin.AssertValid(target)
    assert(target and type(target) == "table", "target is not a table")
    assert(target.Name, "target is missing a Name")
    assert(target.InnerFrame, "target '" .. target.Name .. "' is missing an InnerFrame")
end

--- Applies the frame and common module mixins to the target via metatable.
--- Idempotent — safe to call more than once (no-op after first application).
--- @param target table table to apply the mixin to.
--- @param name string the module name. must be unique.
function FrameMixin.AddMixin(target, name)
    ECM.MixinUtil.Apply(target, FrameMixinProto, name)
end
