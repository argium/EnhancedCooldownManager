-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local FrameUtil = ns.FrameUtil
local LibEditMode = LibStub("LibEditMode")

--------------------------------------------------------------------------------
-- Edit Mode
--------------------------------------------------------------------------------

local EditMode = ns.EditMode or {}
EditMode.Lib = LibEditMode
ns.EditMode = EditMode

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
    ns.Runtime.ScheduleLayoutUpdate(0, "EditModeEnter")
end)
LibEditMode:RegisterCallback("exit", function()
    ns.Runtime.ScheduleLayoutUpdate(0, "EditModeExit")
end)
LibEditMode:RegisterCallback("layout", function()
    ns.Runtime.ScheduleLayoutUpdate(0, "EditModeLayout")
end)

--------------------------------------------------------------------------------
-- FrameProto — base frame layer (positioning, visibility, edit mode, config)
--------------------------------------------------------------------------------

---@alias AnchorPoint string

---@class FrameProto : AceModule Frame mixin that owns visibility and config access.
---@field _configKey string|nil Config key for this frame's section.
---@field IsHidden boolean|nil Whether the frame is currently hidden.
---@field InnerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field Name string Name of the frame.

local FrameProto = {}

--- Determine the correct anchor for this specific frame in the fixed order.
--- @param frameName string|nil The name of the current frame, or nil if first in chain.
--- @param anchorMode string|nil The anchor mode to filter by (defaults to ANCHORMODE_CHAIN).
--- @return Frame The frame to anchor to.
--- @return boolean isFirst True if this is the first frame in the chain.
function FrameProto:GetNextChainAnchor(frameName, anchorMode)
    anchorMode = anchorMode or C.ANCHORMODE_CHAIN

    -- Find the ideal position
    local stopIndex = #C.CHAIN_ORDER + 1
    if frameName then
        for i, name in ipairs(C.CHAIN_ORDER) do
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
        local barName = C.CHAIN_ORDER[i]
        local barModule = addon and addon:GetECMModule(barName, true)
        if barModule and barModule:IsEnabled() and barModule:ShouldShow() then
            local moduleConfig = barModule:GetModuleConfig()
            if moduleConfig and moduleConfig.anchorMode == anchorMode and barModule.InnerFrame then
                return barModule.InnerFrame, false
            end
        end
    end

    if anchorMode == C.ANCHORMODE_DETACHED then
        return ns.Runtime.DetachedAnchor or UIParent, true
    end

    return _G["EssentialCooldownViewer"] or UIParent, true
end

function FrameProto:SetHidden(hide)
    self.IsHidden = hide
    if self.InnerFrame then
        -- Hide immediately, but defer showing until the next layout pass to ensure proper anchoring.
        if hide then
            self.InnerFrame:Hide()
        else
            ns.Runtime.RequestLayout("SetHidden")
        end
    end
end

--- Determines whether this frame should be shown at this particular moment. Can be overridden.
function FrameProto:ShouldShow()
    local config = self:GetModuleConfig()
    return not self.IsHidden and (config == nil or config.enabled ~= false)
end

--- Determines whether this module should register its frame with ECM Edit Mode.
--- Modules backed by Blizzard-owned system frames can override this to opt out.
---@return boolean
function FrameProto:ShouldRegisterEditMode()
    return true
end

function FrameProto:CreateFrame()
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local name = "ECM" .. self.Name
    local frame = CreateFrame("Frame", name, UIParent)

    local barHeight = (moduleConfig and moduleConfig.height)
        or (globalConfig and globalConfig.barHeight)
        or C.DEFAULT_BAR_HEIGHT

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
function FrameProto:EnsureFrame()
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
function FrameProto.ChainRightPoint(point, fallback)
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
function FrameProto.NormalizeGrowDirection(direction)
    return direction == C.GROW_DIRECTION_UP and C.GROW_DIRECTION_UP or C.GROW_DIRECTION_DOWN
end

---@param self FrameProto
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
function FrameProto:CalculateLayoutParams()
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
function FrameProto:ApplyFramePosition()
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
    if params.mode == C.ANCHORMODE_FREE then
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
function FrameProto:UpdateLayout(why)
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

    ns.DebugAssert(
        moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor),
        "bgColor not defined in config for frame " .. self.Name
    )
    local bgColor = moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor) or C.DEFAULT_BG_COLOR
    FrameUtil.LazySetBackgroundColor(frame, bgColor)

    self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
    return true
end

--- Handles common refresh logic for FrameProto-derived frames.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @param force boolean|nil Whether to force a refresh, even if the bar is hidden.
--- @return boolean continue True if the frame should continue refreshing, false to skip.
function FrameProto:Refresh(why, force)
    return force or self:ShouldShow()
end

--- Rate-limited refresh. Skips if called within updateFrequency window.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @return boolean refreshed True if Refresh() was called
function FrameProto:ThrottledRefresh(why)
    local globalConfig = self:GetGlobalConfig()
    local freq = (globalConfig and globalConfig.updateFrequency) or C.DEFAULT_REFRESH_FREQUENCY
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end
    self:Refresh(why)
    self._lastUpdate = GetTime()
    return true
end

--- Checks if the module is ready for layout updates.
--- @return boolean ready True if the module is ready for updates.
function FrameProto:IsReady()
    return self:IsEnabled()
        and self.InnerFrame ~= nil
        and self:GetGlobalConfig() ~= nil
        and self:GetModuleConfig() ~= nil
end

--- Saves an Edit Mode position for the given layout.
---@param layoutName string Edit Mode layout name.
---@param point string Anchor point (e.g. "CENTER").
---@param x number X offset.
---@param y number Y offset.
function FrameProto:_SaveEditModePosition(layoutName, point, x, y)
    local cfg = self:GetModuleConfig()
    EditMode.SavePosition(cfg, "editModePositions", layoutName, point, x, y)
end

--- Registers this module's frame with Edit Mode for drag positioning.
--- Called once during AddMixin after InnerFrame is created.
--- No-op if InnerFrame is nil (e.g. when the Blizzard viewer hasn't loaded yet).
function FrameProto:_RegisterEditMode()
    local frame = self.InnerFrame
    if not frame or self._editModeRegisteredFrame == frame then
        return
    end

    local module = self
    EditMode.RegisterFrame(frame, {
        name = "ECM: " .. self.Name,
        onPositionChanged = function(layoutName, point, x, y)
            module:_SaveEditModePosition(layoutName, point, x, y)
            ns.Runtime.UpdateLayoutImmediately("EditModeDrag")
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
                        ns.Runtime.UpdateLayoutImmediately("EditModeWidth")
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

--- Returns this module's config section (live from AceDB profile).
---@return table|nil
function FrameProto:GetModuleConfig()
    return ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile[self._configKey]
end

--------------------------------------------------------------------------------
-- BarProto — status bar layer (StatusBar, ticks, text, refresh)
--------------------------------------------------------------------------------

local BarProto = setmetatable({}, { __index = FrameProto })

--- Ensures the tick pool has the required number of ticks.
--- Creates new ticks as needed, shows required ticks, hides extras.
---@param self BarProto
---@param count number Number of ticks needed
---@param parentFrame Frame Frame to create ticks on (e.g., bar.StatusBar or bar.TicksFrame)
---@param poolKey string|nil Key for tick pool on bar (default "tickPool")
function BarProto:EnsureTicks(count, parentFrame, poolKey)
    assert(parentFrame, "parentFrame required for tick creation")

    poolKey = poolKey or "tickPool"
    local pool = self[poolKey]
    if not pool then
        pool = {}
        self[poolKey] = pool
    end

    for i = 1, count do
        if not pool[i] then
            local tick = parentFrame:CreateTexture(nil, "OVERLAY")
            pool[i] = tick
        end
        pool[i]:Show()
    end

    for i = count + 1, #pool do
        local tick = pool[i]
        if tick then
            tick:Hide()
        end
    end
end

--- Hides all ticks in the pool.
---@param self BarProto
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarProto:HideAllTicks(poolKey)
    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    for i = 1, #pool do
        pool[i]:Hide()
    end
end

--- Positions ticks evenly as resource dividers.
--- Used by ResourceBar to show divisions between resources.
---@param self BarProto
---@param maxResources number Number of resources (ticks = maxResources - 1)
---@param color ECM_Color|table|nil RGBA color (default black)
---@param tickWidth number|nil Width of each tick (default 1)
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarProto:LayoutResourceTicks(maxResources, color, tickWidth, poolKey)
    maxResources = tonumber(maxResources) or 0
    if maxResources <= 1 then
        self:HideAllTicks(poolKey)
        return
    end

    local frame = self.InnerFrame
    local barWidth = frame:GetWidth()
    local barHeight = frame:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    color = color or { r = 0, g = 0, b = 0, a = 1 }
    tickWidth = tickWidth or 1

    local step = barWidth / maxResources
    local tr, tg, tb, ta = color.r, color.g, color.b, color.a

    for i = 1, #pool do
        local tick = pool[i]
        if tick and tick:IsShown() then
            tick:ClearAllPoints()
            local x = FrameUtil.PixelSnap(step * i)
            tick:SetPoint("LEFT", frame, "LEFT", x, 0)
            tick:SetSize(math.max(1, FrameUtil.PixelSnap(tickWidth)), barHeight)
            tick:SetColorTexture(tr, tg, tb, ta)
        end
    end
end

--- Positions ticks at specific resource values.
--- Used by PowerBar for breakpoint markers (e.g., energy thresholds).
---@param self BarProto
---@param statusBar StatusBar StatusBar to position ticks on
---@param ticks table Array of tick definitions { { value = number, color = ECM_Color, width = number }, ... }
---@param maxValue number Maximum resource value
---@param defaultColor ECM_Color Default RGBA color
---@param defaultWidth number Default tick width
---@param poolKey string|nil Key for tick pool (default "tickPool")
function BarProto:LayoutValueTicks(statusBar, ticks, maxValue, defaultColor, defaultWidth, poolKey)
    if not statusBar then
        return
    end

    if not ticks or #ticks == 0 or maxValue <= 0 then
        self:HideAllTicks(poolKey)
        return
    end

    local frame = self.InnerFrame
    local barWidth = statusBar:GetWidth()
    local barHeight = frame:GetHeight()
    if barWidth <= 0 or barHeight <= 0 then
        return
    end

    local pool = self[poolKey or "tickPool"]
    if not pool then
        return
    end

    defaultColor = defaultColor or { r = 0, g = 0, b = 0, a = 0.5 }
    defaultWidth = defaultWidth or 1

    for i = 1, #ticks do
        local tick = pool[i]
        local tickData = ticks[i]
        if tick and tickData then
            local value = tickData.value
            if value and value > 0 and value < maxValue then
                local tickColor = tickData.color or defaultColor
                local tickWidthVal = tickData.width or defaultWidth
                local tr, tg, tb = tickColor.r, tickColor.g, tickColor.b
                local ta = tickColor.a or (defaultColor.a or 0.5)

                local x = math.floor((value / maxValue) * barWidth)
                tick:ClearAllPoints()
                tick:SetPoint("LEFT", statusBar, "LEFT", x, 0)
                tick:SetSize(math.max(1, FrameUtil.PixelSnap(tickWidthVal)), barHeight)
                tick:SetColorTexture(tr, tg, tb, ta)
                tick:Show()
            else
                tick:Hide()
            end
        end
    end
end

--- Gets the current value for the bar.
---@return number|nil current
---@return number|nil max
---@return number|nil displayValue
---@return boolean isFraction valueType
function BarProto:GetStatusBarValues()
    ns.DebugAssert(false, "GetStatusBarValues not implemented in derived class")
    return -1, -1, -1, false
end

--- Gets the color for the status bar. Override for custom color logic.
---@return ECM_Color Color table with r, g, b, a fields
function BarProto:GetStatusBarColor()
    local powerType = UnitPowerType("player")
    local moduleConfig = self:GetModuleConfig()
    local color = moduleConfig and moduleConfig.colors and moduleConfig.colors[powerType]
    return color or C.COLOR_WHITE
end

--- Refreshes the bar frame layout and values.
--- @param why string|nil Reason for refresh (for logging/debugging).
--- @param force boolean|nil If true, forces a refresh even if not needed.
--- @return boolean continue True if refresh completed, false if skipped
function BarProto:Refresh(why, force)
    if not FrameProto.Refresh(self, why, force) then
        return false
    end

    local frame = self.InnerFrame
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()

    -- Values: apply min/max before value so startup/transient states do not
    -- render full when current is zero.
    local current, max, displayValue = self:GetStatusBarValues()
    if max == nil then
        max = 1
    end
    if current == nil then
        current = 0
    end

    frame.StatusBar:SetMinMaxValues(0, max)
    frame.StatusBar:SetValue(current)

    -- Text overlay
    local showText = moduleConfig.showText ~= false
    if showText and frame.TextValue then
        frame:SetText(displayValue)

        -- Apply font settings
        FrameUtil.ApplyFont(frame.TextValue, globalConfig, moduleConfig)
    end
    frame:SetTextVisible(showText)

    -- Texture
    local tex = FrameUtil.GetTexture((moduleConfig and moduleConfig.texture) or (globalConfig and globalConfig.texture))
        or C.DEFAULT_STATUSBAR_TEXTURE
    FrameUtil.LazySetStatusBarTexture(frame.StatusBar, tex)

    -- Status bar color
    local statusBarColor = self:GetStatusBarColor()
    FrameUtil.LazySetStatusBarColor(
        frame.StatusBar,
        statusBarColor.r,
        statusBarColor.g,
        statusBarColor.b,
        statusBarColor.a
    )

    frame:Show()

    -- Tick layout: modules return a tick spec, BarProto applies it.
    if self.GetTickSpec then
        local spec = self:GetTickSpec()
        if spec and spec.ticks then
            self:EnsureTicks(#spec.ticks, frame.TicksFrame, "tickPool")
            self:LayoutValueTicks(frame.StatusBar, spec.ticks, spec.maxValue, spec.defaultColor, spec.defaultWidth, "tickPool")
        elseif spec and spec.maxResources then
            self:EnsureTicks(spec.maxResources - 1, frame.TicksFrame, "tickPool")
            self:LayoutResourceTicks(spec.maxResources, spec.color, spec.width, "tickPool")
        else
            self:HideAllTicks("tickPool")
        end
    end

    if ns.IsDebugEnabled() then
        ns.Log(self.Name, "Bar frame refresh complete (" .. (why or "") .. ").")
    end

    return true
end

function BarProto:CreateFrame()
    local frame = FrameProto.CreateFrame(self)

    -- StatusBar for value display
    frame.StatusBar = CreateFrame("StatusBar", nil, frame)
    frame.StatusBar:SetAllPoints(frame)
    frame.StatusBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- TicksFrame for tick marks
    frame.TicksFrame = CreateFrame("Frame", nil, frame)
    frame.TicksFrame:SetAllPoints(frame)
    frame.TicksFrame:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Text overlay for displaying values
    frame.TextFrame = CreateFrame("Frame", nil, frame)
    frame.TextFrame:SetAllPoints(frame)
    frame.TextFrame:SetFrameLevel(frame.StatusBar:GetFrameLevel() + 10)

    frame.TextValue = frame.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.TextValue:SetPoint("CENTER", frame.TextFrame, "CENTER", 0, 0)
    frame.TextValue:SetJustifyH("CENTER")
    frame.TextValue:SetJustifyV("MIDDLE")

    function frame.SetText(_, text)
        frame.TextValue:SetText(text)
    end

    function frame.SetTextVisible(_, shown)
        frame.TextFrame:SetShown(shown)
    end

    ns.Log(self.Name, "Frame created.")
    return frame
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local BarMixin = {}
ns.BarMixin = BarMixin

BarMixin.FrameProto = FrameProto
BarMixin.BarProto = BarProto
setmetatable(BarMixin, { __index = BarProto })

function BarMixin.AssertValid(target)
    assert(target and type(target) == "table", "target is not a table")
    assert(target.Name, "target is missing a Name")
    assert(target.InnerFrame, "target '" .. target.Name .. "' is missing an InnerFrame")
end

--- Applies frame-only mixin (positioning, visibility, edit mode, config access).
--- Used by modules that manage their own inner content (e.g. BuffBars, ExtraIcons).
--- Idempotent — safe to call more than once (no-op after first application).
--- @param target table table to apply the mixin to.
--- @param name string the module name. must be unique.
function BarMixin.AddFrameMixin(target, name)
    assert(target, "target required")
    assert(name, "name required")
    if target._mixinApplied then
        return
    end

    local existingMt = getmetatable(target)
    local existingIndex = existingMt and existingMt.__index

    setmetatable(target, {
        __index = function(_, k)
            local v = FrameProto[k]
            if v ~= nil then
                return v
            end
            if type(existingIndex) == "function" then
                return existingIndex(target, k)
            end
            if type(existingIndex) == "table" then
                return existingIndex[k]
            end
        end,
    })

    target.Name = name
    target._configKey = C.ConfigKeyForModule(name)
    if not target.GetGlobalConfig then
        target.GetGlobalConfig = ns.GetGlobalConfig
    end
    target.IsHidden = false
    target._mixinApplied = true
end

--- Applies bar mixin (frame + StatusBar, ticks, text, refresh).
--- Used by bar modules (PowerBar, ResourceBar, RuneBar).
--- Idempotent — safe to call more than once (no-op after first application).
function BarMixin.AddBarMixin(module, name)
    assert(module, "target required")
    assert(name, "name required")
    if module._mixinApplied then
        return
    end

    local existingMt = getmetatable(module)
    local existingIndex = existingMt and existingMt.__index

    setmetatable(module, {
        __index = function(_, k)
            local v = BarProto[k]
            if v ~= nil then
                return v
            end
            if type(existingIndex) == "function" then
                return existingIndex(module, k)
            end
            if type(existingIndex) == "table" then
                return existingIndex[k]
            end
        end,
    })

    module.Name = name
    module._configKey = C.ConfigKeyForModule(name)
    if not module.GetGlobalConfig then
        module.GetGlobalConfig = ns.GetGlobalConfig
    end
    module.IsHidden = false
    module._mixinApplied = true
    module._lastUpdate = GetTime()
end
