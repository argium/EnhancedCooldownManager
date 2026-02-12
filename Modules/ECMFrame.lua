-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local C = ns.Constants

local ECMFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.ECMFrame = ECMFrame

---@alias AnchorPoint string

---@class ECMFrame : AceModule Frame mixin that owns layout and config access.
---@field _configKey string|nil Config key for this frame's section.
---@field IsHidden boolean|nil Whether the frame is currently hidden.
---@field IsECMFrame boolean True to identify this as an ECMFrame mixin instance.
---@field InnerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field GlobalConfig table|nil Cached reference to the global config section.
---@field ModuleConfig table|nil Cached reference to this module's config section.
---@field Name string  Name of the frame.
---@field GetNextChainAnchor fun(self: ECMFrame, frameName: string|nil): (Frame, boolean) Gets the next valid anchor in the chain.
---@field GetInnerFrame fun(self: ECMFrame): Frame Gets the inner frame.
---@field ShouldShow fun(self: ECMFrame): boolean Determines whether the frame should be shown at this moment.
---@field CreateFrame fun(self: ECMFrame): Frame Creates the inner frame.
---@field SetHidden fun(self: ECMFrame, hide: boolean) Sets whether the frame is hidden.
---@field SetAlpha fun(self: ECMFrame, alpha: number) Sets the alpha of the inner frame.
---@field SetConfig fun(self: ECMFrame, config: table) Sets the config for this frame and caches relevant sections.
---@field CalculateLayoutParams fun(self: ECMFrame): table Calculates layout parameters based on anchor mode and config.
---@field ApplyFramePosition fun(self: ECMFrame, frame: Frame): table|nil Applies layout positioning to the frame based on current config. Returns layout params if shown, nil if hidden.
---@field Refresh fun(self: ECMFrame, why: string|nil, force: boolean|nil): boolean Handles common refresh logic. Returns true if the frame should continue refreshing, false to skip.
---@field ScheduleDebounced fun(self: ECMFrame, flagName: string, callback: function) Schedules a debounced callback. Multiple calls within updateFrequency coalesce into one.
---@field ThrottledRefresh fun(self: ECMFrame, why: string|nil): boolean Rate-limited refresh. Skips if called within updateFrequency window.
---@field UpdateLayout fun(self: ECMFrame, why: string|nil): boolean Updates the visual layout of the frame.
---@field AddMixin fun(target: table, name: string) Adds ECMFrame methods and initializes state on target.
---@field ScheduleLayoutUpdate fun(self: ECMFrame, why: string|nil) Schedules a throttled layout update. Multiple calls within updateFrequency coalesce into one.
---@field LazySetHeight fun(self: ECMFrame, h: number): boolean Sets height only if changed.
---@field LazySetWidth fun(self: ECMFrame, w: number): boolean Sets width only if changed.
---@field LazySetShown fun(self: ECMFrame, shown: boolean): boolean Sets shown state only if changed.
---@field LazySetAlpha fun(self: ECMFrame, alpha: number): boolean Sets alpha only if changed.
---@field LazySetAnchors fun(self: ECMFrame, anchors: table[]): boolean Clears and re-applies anchor points only if changed.
---@field LazySetBackgroundColor fun(self: ECMFrame, color: ECM_Color): boolean Sets background color texture only if changed.
---@field LazySetVertexColor fun(self: ECMFrame, texture: Texture, cacheKey: string, color: ECM_Color): boolean Sets vertex color on a texture only if changed.
---@field LazySetStatusBarTexture fun(self: ECMFrame, bar: StatusBar, texturePath: string): boolean Sets status bar texture only if changed.
---@field LazySetStatusBarColor fun(self: ECMFrame, bar: StatusBar, r: number, g: number, b: number, a: number|nil): boolean Sets status bar color only if changed.
---@field LazySetBorder fun(self: ECMFrame, borderConfig: table): boolean Applies border configuration only if changed.
---@field LazySetText fun(self: ECMFrame, fontString: FontString, cacheKey: string, text: string|nil): boolean Sets text on a FontString only if changed.
---@field ResetLazyMarkers fun(self: ECM_BuffBarFrame): nil Resets all lazy setter state to force re-application on next update.

--- Determine the correct anchor for this specific frame in the fixed order.
--- @param frameName string|nil The name of the current frame, or nil if first in chain.
--- @return Frame The frame to anchor to.
--- @return boolean isFirst True if this is the first frame in the chain.
function ECMFrame:GetNextChainAnchor(frameName)
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
    -- Valid frames are those that are enabled, should be shown, in chain mode,
    -- and have an inner frame available. Visibility is intentionally not required
    -- because layout updates can occur while frames are transitioning hide/show.
    local debugCandidates = {}
    for i = stopIndex - 1, 1, -1 do
        local barName = C.CHAIN_ORDER[i]
        local barModule = ECM:GetModule(barName, true)
        local isEnabled = barModule and barModule:IsEnabled() or false
        local shouldShow = barModule and barModule:ShouldShow() or false
        local moduleConfig = barModule and barModule.ModuleConfig
        local isChainMode = moduleConfig and moduleConfig.anchorMode == C.ANCHORMODE_CHAIN
        local barFrame = barModule and barModule.InnerFrame
        local hasFrame = barFrame ~= nil
        local isVisible = barFrame and barFrame:IsVisible() or false

        debugCandidates[#debugCandidates + 1] = {
            barName = barName,
            isEnabled = isEnabled,
            shouldShow = shouldShow,
            isChainMode = isChainMode,
            hasFrame = hasFrame,
            isVisible = isVisible,
        }

        if isEnabled and shouldShow and isChainMode and hasFrame then
            ECM_log(C.SYS.Layout, self.Name, "GetNextChainAnchor selected", {
                frameName = frameName,
                stopIndex = stopIndex,
                selected = barName,
                selectedVisible = isVisible,
                candidates = debugCandidates,
            })
            return barFrame, false
        end
    end

    -- If none of the preceeding frames in the chain are valid, anchor to the viewer as the first.
    ECM_log(C.SYS.Layout, self.Name, "GetNextChainAnchor fallthrough; treating as first anchor", {
        frameName = frameName,
        stopIndex = stopIndex,
        selected = "EssentialCooldownViewer",
        candidates = debugCandidates,
    })
    return _G["EssentialCooldownViewer"] or UIParent, true
end

function ECMFrame:SetHidden(hide)
    self.IsHidden = hide
end

function ECMFrame:SetAlpha(alpha)
    if self.InnerFrame then
        self.InnerFrame:SetAlpha(alpha)
    end
end

function ECMFrame:SetConfig(config)
    assert(config, "config required")
    self.GlobalConfig = config and config[C.CONFIG_SECTION_GLOBAL]
    self.ModuleConfig = config and config[self._configKey]
end

--- Calculates layout parameters based on anchor mode. Override for custom positioning logic.
---@return table params Layout parameters: mode, anchor, isFirst, anchorPoint, anchorRelativePoint, offsetX, offsetY, width, height
function ECMFrame:CalculateLayoutParams()
    local globalConfig = self.GlobalConfig
    local moduleConfig = self.ModuleConfig
    local mode = moduleConfig.anchorMode

    local params = { mode = mode }

    if mode == C.ANCHORMODE_CHAIN then
        local anchor, isFirst = self:GetNextChainAnchor(self.Name)
        params.anchor = anchor
        params.isFirst = isFirst
        params.anchorPoint = "TOPLEFT"
        params.anchorRelativePoint = "BOTTOMLEFT"
        params.offsetX = 0
        params.offsetY = (isFirst and -globalConfig.offsetY) or 0
        params.height = moduleConfig.height or globalConfig.barHeight
        params.width = nil -- Width set by dual-point anchoring
    elseif mode == C.ANCHORMODE_FREE then
        params.anchor = UIParent
        params.isFirst = false
        params.anchorPoint = "CENTER"
        params.anchorRelativePoint = "CENTER"
        params.offsetX = moduleConfig.offsetX or 0
        params.offsetY = moduleConfig.offsetY or C.DEFAULT_FREE_ANCHOR_OFFSET_Y
        params.height = moduleConfig.height or globalConfig.barHeight
        params.width = moduleConfig.width or globalConfig.barWidth
    end

    return params
end

function ECMFrame:CreateFrame()
    local globalConfig = self.GlobalConfig
    local moduleConfig = self.ModuleConfig
    local name = "ECM" .. self.Name
    local frame = CreateFrame("Frame", name, UIParent)

    local barHeight = (moduleConfig and moduleConfig.height)
        or (globalConfig and globalConfig.barHeight)
        or C.DEFAULT_BAR_HEIGHT

    frame:SetFrameStrata("MEDIUM")
    frame:SetHeight(barHeight)
    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAllPoints()

    -- Optional border frame
    frame.Border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Border:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.Border:Hide()

    ECM_ApplyLazySetters(frame)

    return frame
end

--- Applies positioning to a frame based on layout parameters.
--- Handles ShouldShow check, layout calculation, and anchor positioning.
--- Uses LazySetAnchors for change detection when available.
--- @param frame Frame The frame to position
--- @return table|nil params Layout params if shown, nil if hidden
function ECMFrame:ApplyFramePosition(frame)
    if not self:ShouldShow() then
        frame:Hide()
        return nil
    end

    local params = self:CalculateLayoutParams()
    local mode = params.mode
    local anchor = params.anchor
    local offsetX, offsetY = params.offsetX, params.offsetY
    local anchorPoint = params.anchorPoint
    local anchorRelativePoint = params.anchorRelativePoint

    local anchors
    if mode == C.ANCHORMODE_CHAIN then
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

    frame:LazySetAnchors(anchors)

    return params
end

function ECMFrame:UpdateLayout(why)
    local globalConfig = self.GlobalConfig
    local moduleConfig = self.ModuleConfig
    local frame = self.InnerFrame
    local borderConfig = moduleConfig.border

    -- Apply positioning and get params (returns nil if frame should be hidden)
    local params = self:ApplyFramePosition(frame)
    if not params then
        return false
    end

    local anchor = params.anchor
    local isFirst = params.isFirst
    local width = params.width
    local height = params.height

    -- Apply dimensions via lazy setters (no-ops when unchanged)
    local heightChanged = height and frame:LazySetHeight(height) or false
    local widthChanged = width and frame:LazySetWidth(width) or false

    -- Apply border via lazy setter
    local borderChanged = false
    if borderConfig then
        borderChanged = frame:LazySetBorder(borderConfig)
    end

    -- Apply background color via lazy setter
    ECM_debug_assert(moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor), "bgColor not defined in config for frame " .. self.Name)
    local bgColor = moduleConfig.bgColor or (globalConfig and globalConfig.barBgColor) or C.DEFAULT_BG_COLOR
    local bgColorChanged = frame:LazySetBackgroundColor(bgColor)

    ECM_log(C.SYS.Layout, self.Name, "ECMFrame UpdateLayout complete (" .. (why or "") .. ")", {
        anchor = anchor:GetName(),
        isFirst = isFirst,
        widthChanged = widthChanged,
        width = width,
        heightChanged = heightChanged,
        height = height,
        borderChanged = borderChanged,
        borderEnabled = borderConfig and borderConfig.enabled,
        borderThickness = borderConfig and borderConfig.thickness,
        borderColor = borderConfig and borderConfig.color,
        bgColorChanged = bgColorChanged,
        bgColor = bgColor,
    })

    self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
    return true
end

--- Determines whether this frame should be shown at this particular moment. Can be overridden.
function ECMFrame:ShouldShow()
    local config = self.ModuleConfig
    return not self.IsHidden and (config == nil or config.enabled ~= false)
end

--- Handles common refresh logic for ECMFrame-derived frames.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @param force boolean|nil Whether to force a refresh, even if the bar is hidden.
--- @return boolean continue True if the frame should continue refreshing, false to skip.
function ECMFrame:Refresh(why, force)
    if not force and not self:ShouldShow() then
        -- ECM_log(self.Name, "ECMFrame:Refresh", "Frame is hidden or disabled, skipping refresh (" .. (why or "") .. ")")
        return false
    end

    return true
end

--- Schedules a debounced callback. Multiple calls within updateFrequency coalesce into one.
---@param flagName string Key for the pending flag on self
---@param callback function Function to call after delay
function ECMFrame:ScheduleDebounced(flagName, callback)
    if self[flagName] then
        return
    end
    self[flagName] = true

    local freq = self.GlobalConfig and self.GlobalConfig.updateFrequency or C.DEFAULT_REFRESH_FREQUENCY
    C_Timer.After(freq, function()
        self[flagName] = nil
        callback()
    end)
end

--- Rate-limited refresh. Skips if called within updateFrequency window.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @return boolean refreshed True if Refresh() was called
function ECMFrame:ThrottledRefresh(why)
    local config = self.GlobalConfig
    local freq = (config and config.updateFrequency) or C.DEFAULT_REFRESH_FREQUENCY
    if GetTime() - (self._lastUpdate or 0) < freq then
        return false
    end
    self:Refresh(why)
    self._lastUpdate = GetTime()
    return true
end

--- Schedules a throttled layout update. Multiple calls within updateFrequency coalesce into one.
--- This is the canonical way to request layout updates from event handlers or callbacks.
function ECMFrame:ScheduleLayoutUpdate(why)
    self:ScheduleDebounced("_layoutPending", function()
        self:UpdateLayout(why)
    end)
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ECMFrame.AddMixin(target, name)
    assert(target, "target required")
    assert(name, "name required")

    -- Only copy methods that the target doesn't already have.
    for k, v in pairs(ECMFrame) do
        if type(v) == "function" and target[k] == nil then
            target[k] = v
        end
    end

    local configRoot = ECM.db and ECM.db.profile
    target.Name = name
    target._configKey = name:sub(1,1):lower() .. name:sub(2) -- camelCase-ish
    target.IsHidden = false
    target.InnerFrame = target:CreateFrame()
    target.IsECMFrame = true
    target:SetConfig(configRoot)

    -- Registering this frame allows us to receive layout update events such as global hideWhenMounted.
    ECM.RegisterFrame(target)

    C_Timer.After(0, function()
        target:UpdateLayout("AddMixin")
    end)
end
