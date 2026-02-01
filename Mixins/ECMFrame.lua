-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local C = ns.Constants
local Util = ns.Util

local ECMFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.ECMFrame = ECMFrame

-- Owns:
--  The inner frame
--  Layout incl. border.
--  Config access

---@alias AnchorPoint string

---@class ECM_LayoutCache Cached layout state for change detection.
---@field anchor Frame|nil Last anchor frame.
---@field offsetX number|nil Last horizontal offset.
---@field offsetY number|nil Last vertical offset.
---@field width number|nil Last applied width.
---@field height number|nil Last applied height.
---@field anchorPoint AnchorPoint|nil Last anchor point.
---@field anchorRelativePoint AnchorPoint|nil Last relative anchor point.
---@field mode "chain"|"independent"|nil Last positioning mode.
---@field borderEnabled boolean|nil Last border enabled state.
---@field borderThickness number|nil Last border thickness.
---@field borderColor ECM_Color|nil Last border color table.
---@field bgColor ECM_Color|nil Last background color table.

---@class ECMFrame : AceModule Frame mixin that owns layout and config access.
---@field _name string Internal name of the frame.
---@field _config table|nil Reference to the frame's configuration profile section.
---@field _configKey string|nil Config key for this frame's section.
---@field _layoutCache ECM_LayoutCache|nil Cached layout parameters.
---@field _innerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field _hidden boolean|nil Whether the frame is currently hidden.
---@field IsECMFrame boolean True to identify this as an ECMFrame mixin instance.
---@field Name string  Name of the frame.
---@field GetInnerFrame fun(self: ECMFrame): Frame Gets the inner frame.
---@field GetGlobalConfig fun(self: ECMFrame): table Gets the global configuration section.
---@field GetConfigSection fun(self: ECMFrame): table Gets the specific config section for this frame.
---@field ShouldShow fun(self: ECMFrame): boolean Determines whether the frame should be shown at this moment.
---@field CreateFrame fun(self: ECMFrame): Frame Creates the inner frame.
---@field SetHidden fun(self: ECMFrame, hide: boolean) Sets whether the frame is hidden.
---@field UpdateLayout fun(self: ECMFrame): boolean Updates the visual layout of the frame.
---@field AddMixin fun(target: table, name: string) Adds ECMFrame methods and initializes state on target.

--- Determine the correct anchor for this specific frame in the fixed order.
local function GetNextChainAnchor(frameName, config)
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
    -- Valid frames are those that are enabled and visible.
    for i = stopIndex - 1, 1, -1 do
        local barName = C.CHAIN_ORDER[i]
        local barModule = ECM:GetModule(barName, true)
        if barModule and barModule:IsEnabled() then
            local barFrame = barModule:GetInnerFrame()
            if barFrame and barFrame:IsVisible() then
                return barFrame
            end
        end
    end

    -- If none of the preceeding frames in the chain are valid, anchor to the viewer as the first.
    return _G[C.VIEWER] or UIParent
end

function ECMFrame:GetInnerFrame()
    assert(self._innerFrame, "innerFrame not created for frame " .. self.Name)
    return self._innerFrame
end

function ECMFrame:GetIsHidden()
    return self._hidden
end

--- Gets the configuration table for this frame.
--- Asserts if the config has not been set via `AddMixin` or `SetConfig`.
---@return table config The frame's configuration table
function ECMFrame:GetGlobalConfig()
    assert(self._config, "config not set for frame " .. self.Name)
    return self._config[C.CONFIG_SECTION_GLOBAL]
end

--- Gets the specific configuration section for this frame.
---@return table configSection The frame's specific configuration section
function ECMFrame:GetConfigSection()
    assert(self._config, "config not set for frame " .. self.Name)
    assert(self._configKey, "configKey not set for frame " .. self.Name)
    local section = self._config[self._configKey]
    assert(section, "config section '" .. self._configKey .. "' not found for frame " .. self.Name)
    return section
end

function ECMFrame:CreateFrame()
    local globalConfig = self:GetGlobalConfig()
    local configSection = self:GetConfigSection()
    local name = "ECM" .. self.Name
    local frame = CreateFrame("Frame", name, UIParent)

    local barHeight = (configSection and configSection.height)
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

    return frame
end

function ECMFrame:SetHidden(hide)
    self._hidden = hide
end

function ECMFrame:UpdateLayout()
    local globalConfig = self:GetGlobalConfig()
    local configSection = self:GetConfigSection()
    local mode = configSection.anchorMode
    local frame = self:GetInnerFrame()
    local borderConfig = configSection.border

    if not self:ShouldShow() then
        Util.Log(self.Name, "ECMFrame:UpdateLayout", "ShouldShow returned false, hiding frame")
        frame:Hide()
        return false
    end

    -- Determine the layout parameters based on the anchor mode. Chain mode will
    -- append this frame to the previous in the chain and inherit its width.
    local anchor, offsetX, offsetY, width, height
    if mode == "chain" then
        anchor = GetNextChainAnchor(self.Name, configSection)
        offsetX = 0
        offsetY = (configSection.offsetY and -configSection.offsetY) or -globalConfig.offsetY
        height = configSection.height or globalConfig.barHeight
        width = nil -- Width will be set by anchoring
    elseif mode == "independent" then
        assert(false, "NYI")
    end

    local anchorPoint = "TOPLEFT"
    local anchorRelativePoint = "BOTTOMLEFT"
    local layoutCache = self._layoutCache or {}

    -- Skip positioning and anchor updates if nothing has changed since last time.
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

    local heightChanged = height and layoutCache.height ~= height
    if heightChanged then
        frame:SetHeight(height)
        layoutCache.height = height
        layoutChanged = true
    elseif height == nil then
        layoutCache.height = nil
    end

    local widthChanged = width and layoutCache.width ~= width
    if widthChanged then
        frame:SetWidth(width)
        layoutCache.width = width
        layoutChanged = true
    elseif width == nil then
        layoutCache.width = nil
    end

    local borderChanged = nil
    if borderConfig then
        borderChanged = borderConfig.enabled ~= layoutCache.borderEnabled
            or borderConfig.thickness ~= layoutCache.borderThickness
            or not Util.AreColorsEqual(borderConfig.color, layoutCache.borderColor)

        -- Update the border (nil-safe for frames without borders)
        local border = frame.Border
        if border and borderChanged then
            if borderConfig.enabled then
                border:Show()
                ECM.DebugAssert(borderConfig.thickness, "border thickness required when enabled")
                local thickness = borderConfig.thickness or 1
                if layoutCache.borderThickness ~= thickness then
                    border:SetBackdrop({
                        edgeFile = "Interface\\Buttons\\WHITE8X8",
                        edgeSize = thickness,
                    })
                end
                border:ClearAllPoints()
                border:SetPoint("TOPLEFT", -thickness, thickness)
                border:SetPoint("BOTTOMRIGHT", thickness, -thickness)
                border:SetBackdropBorderColor(borderConfig.color.r, borderConfig.color.g, borderConfig.color.b, borderConfig.color.a)
                border:Show()

                -- Update cached avlues
                layoutCache.borderEnabled = true
                layoutCache.borderThickness = thickness
                layoutCache.borderColor = borderConfig.color
            else
                border:Hide()
            end
        end
    end

    ECM.DebugAssert(configSection.bgColor or (globalConfig and globalConfig.barBgColor), "bgColor not defined in config for frame " .. self.Name)
    local bgColor = configSection.bgColor or (globalConfig and globalConfig.barBgColor) or C.DEFAULT_BG_COLOR
    local bgColorChanged = not Util.AreColorsEqual(bgColor, layoutCache.bgColor)

    if bgColorChanged and frame.Background then
        frame.Background:SetColorTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        layoutCache.bgColor = bgColor
    end

    ECM.Log(self.Name, "ECMFrame:UpdateLayout", {
        layoutChanged = layoutChanged,
        anchor = anchor:GetName(),
        offsetX = offsetX,
        offsetY = offsetY,
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

    self:Refresh()
    return true
end

--- Determines whether this frame should be shown at this particular moment. Can be overridden.
function ECMFrame:ShouldShow()
    local config = self:GetConfigSection()
    return not self._hidden and not (config and config.rd == false)
end

--- Handles common refresh logic for ECMFrame-derived frames.
--- @param force boolean|nil Whether to force a refresh, bypassing throttling and state checks.
--- @return boolean continue True if the frame should continue refreshing, false to skip.
function ECMFrame:Refresh(force)
    if force then
        return true
    end

    local config = self:GetConfigSection()
    if self._hidden or not (config and config.enabled) then
        Util.Log(self.Name, "ECMFrame:Refresh", "Frame is hidden or disabled, skipping refresh")
        return false
    end

    return true
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
    target._config = configRoot
    target._configKey = name:sub(1,1):lower() .. name:sub(2) -- camelCase-ish
    target._layoutCache = {}
    target._hidden = false
    target._innerFrame = target:CreateFrame()
    target.IsECMFrame = true

    -- Registering this frame allows us to receive layout update events such as global hideWhenMounted.
    ECM.RegisterFrame(target)

    C_Timer.After(0, function()
        target:UpdateLayout()
    end)
end
