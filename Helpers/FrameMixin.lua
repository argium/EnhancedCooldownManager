-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants
local L = ECM.L
local FrameUtil = ECM.FrameUtil
local LibEQOLEditMode = LibStub("LibEQOLEditMode-1.0")
local EditMode = ECM.EditMode or {}
EditMode.Lib = LibEQOLEditMode
ECM.EditMode = EditMode
local FrameMixin = {}
ECM.FrameMixin = FrameMixin

function EditMode.GetActiveLayoutName()
    return LibEQOLEditMode:GetActiveLayoutName()
end

---@param positions table<string, ECM_EditModePosition>|nil
---@param fallbackKey string|nil
---@param layoutName string|nil
---@return ECM_EditModePosition
---@return string|nil
function EditMode.GetPosition(positions, fallbackKey, layoutName)
    local activeLayoutName = layoutName
    if activeLayoutName == nil then
        activeLayoutName = EditMode.GetActiveLayoutName()
    end

    if type(positions) == "table" then
        local position = activeLayoutName and positions[activeLayoutName]
        if position then
            return position, activeLayoutName
        end

        if fallbackKey and positions[fallbackKey] then
            return positions[fallbackKey], activeLayoutName
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

    frame.editModeName = options.name

    LibEQOLEditMode:AddFrame(frame, function(_, layoutName, point, x, y)
        options.onPositionChanged(layoutName, point, x, y)
    end, {
        allowDrag = options.allowDrag,
        showReset = options.showReset ~= false,
        enableOverlayToggle = options.enableOverlayToggle ~= false,
    })

    if options.hideSelection then
        local selection = LibEQOLEditMode.selectionRegistry[frame]
        if selection then
            selection:HookScript("OnShow", function(sel)
                if options.hideSelection() then
                    sel:Hide()
                end
            end)
        end
    end

    if options.settings then
        LibEQOLEditMode:AddFrameSettings(frame, options.settings)
    end
end

-- Re-apply layout for all registered modules on Edit Mode transitions and layout switches.
-- Deferred via C_Timer to avoid tainting the secure Edit Mode execution context.
LibEQOLEditMode:RegisterCallback("enter", function()
    C_Timer.After(0, function() ECM.Runtime.ScheduleLayoutUpdate(0, "EditModeEnter") end)
end)
LibEQOLEditMode:RegisterCallback("exit", function()
    C_Timer.After(0, function() ECM.Runtime.ScheduleLayoutUpdate(0, "EditModeExit") end)
end)
LibEQOLEditMode:RegisterCallback("layout", function()
    C_Timer.After(0, function() ECM.Runtime.ScheduleLayoutUpdate(0, "EditModeLayout") end)
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
function FrameMixin:GetNextChainAnchor(frameName, anchorMode)
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
                ECM.Log(self.Name, "GetNextChainAnchor " .. barName .. " <-- " .. (frameName or "nil"))
                return barModule.InnerFrame, false
            end
        end
    end

    -- Root anchor depends on the mode being resolved.
    if anchorMode == ECM.Constants.ANCHORMODE_DETACHED then
        ECM.Log(self.Name, "GetNextChainAnchor DetachedAnchor <-- " .. (frameName or "nil"))
        return ECM.Runtime.DetachedAnchor or UIParent, true
    end

    -- If none of the preceding frames in the chain are valid, anchor to the viewer as the first.
    ECM.Log(self.Name, "GetNextChainAnchor Viewer <-- " .. (frameName or "nil"))
    return _G["EssentialCooldownViewer"] or UIParent, true
end

function FrameMixin:SetHidden(hide)
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
function FrameMixin:ShouldShow()
    local config = self:GetModuleConfig()
    return not self.IsHidden and (config == nil or config.enabled ~= false)
end

--- Determines whether this module should register its frame with ECM Edit Mode.
--- Modules backed by Blizzard-owned system frames can override this to opt out.
---@return boolean
function FrameMixin:ShouldRegisterEditMode()
    return true
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
    return direction == C.GROW_DIRECTION_UP and C.GROW_DIRECTION_UP or C.GROW_DIRECTION_DOWN
end

---@param self FrameMixin
---@param globalConfig table
---@param moduleConfig table
---@param mode string
---@return table
local function getStackedLayoutParams(self, globalConfig, moduleConfig, mode)
    local isDetached = mode == C.ANCHORMODE_DETACHED
    if not isDetached then mode = C.ANCHORMODE_CHAIN end

    local anchor, isFirst = self:GetNextChainAnchor(self.Name, mode)

    local directionKey = isDetached and "detachedGrowDirection" or "moduleGrowDirection"
    local growsUp = self.NormalizeGrowDirection(globalConfig and globalConfig[directionKey]) == C.GROW_DIRECTION_UP

    local gap
    if isDetached then
        gap = isFirst and 0 or ((globalConfig and globalConfig.detachedModuleSpacing) or 0)
    else
        gap = isFirst and ((globalConfig and globalConfig.offsetY) or 0) or ((globalConfig and globalConfig.moduleSpacing) or 0)
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
function FrameMixin:CalculateLayoutParams()
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local mode = moduleConfig.anchorMode or C.ANCHORMODE_CHAIN

    if mode == C.ANCHORMODE_FREE then
        local pos = self:GetEditModePosition()
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
    return self:IsEnabled()
        and self.InnerFrame ~= nil
        and self:GetGlobalConfig() ~= nil
        and self:GetModuleConfig() ~= nil
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

--- Gets the saved Edit Mode position for the current layout.
--- Falls back to the migrated position, then CENTER (0, 0).
---@return ECM_EditModePosition
function FrameMixin:GetEditModePosition()
    local cfg = self:GetModuleConfig()
    return EditMode.GetPosition(cfg and cfg.editModePositions, C.EDIT_MODE_MIGRATED_KEY)
end

--- Saves an Edit Mode position for the given layout.
---@param layoutName string Edit Mode layout name.
---@param point string Anchor point (e.g. "CENTER").
---@param x number X offset.
---@param y number Y offset.
function FrameMixin:_SaveEditModePosition(layoutName, point, x, y)
    local cfg = self:GetModuleConfig()
    EditMode.SavePosition(cfg, "editModePositions", layoutName, point, x, y)
end

--- Registers this module's frame with LibEQOL Edit Mode for drag positioning.
--- Called once during AddMixin after InnerFrame is created.
--- No-op if InnerFrame is nil (e.g. when the Blizzard viewer hasn't loaded yet).
function FrameMixin:_RegisterEditMode()
    local frame = self.InnerFrame
    local module = self
    EditMode.RegisterFrame(frame, {
        name = "ECM: " .. self.Name,
        onPositionChanged = function(layoutName, point, x, y)
            module:_SaveEditModePosition(layoutName, point, x, y)
            module:ThrottledUpdateLayout("EditModeDrag")
        end,
        allowDrag = function()
            local cfg = module:GetModuleConfig()
            return cfg and cfg.anchorMode == C.ANCHORMODE_FREE
        end,
        hideSelection = function()
            local cfg = module:GetModuleConfig()
            return cfg and cfg.anchorMode ~= C.ANCHORMODE_FREE
        end,
        settings = {
            {
                kind = LibEQOLEditMode.SettingType.Slider,
                name = L["WIDTH"],
                get = function()
                    local cfg = module:GetModuleConfig()
                    return (cfg and cfg.width) or C.DEFAULT_BAR_WIDTH
                end,
                set = function(_, value)
                    local cfg = module:GetModuleConfig()
                    if cfg then
                        cfg.width = value
                        module:ThrottledUpdateLayout("EditModeWidth")
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
    if target:ShouldRegisterEditMode() then
        target:_RegisterEditMode()
    end
end
