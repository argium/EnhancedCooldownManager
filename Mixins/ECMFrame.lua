-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ECM = ns.Addon
local C = ns.Constants

local ECMFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.ECMFrame = ECMFrame

-- Owns:
--  The inner frame
--  Layout
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

---@class ECMFrame : AceModule Frame mixin that owns layout and config access.
---@field _name string Internal name of the frame.
---@field _config table|nil Reference to the frame's configuration profile section.
---@field _configKey string|nil Config key for this frame's section.
---@field _layoutCache ECM_LayoutCache|nil Cached layout parameters.
---@field _innerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field _hidden boolean|nil Whether the frame is currently hidden.
---@field IsECMFrame boolean True to identify this as an ECMFrame mixin instance.
---@field Name string  Name of the frame.
---@field GetName fun(self: ECMFrame): string Gets the frame name.
---@field GetInnerFrame fun(self: ECMFrame): Frame Gets the inner frame.
---@field GetGlobalConfig fun(self: ECMFrame): table Gets the global configuration section.
---@field GetConfigSection fun(self: ECMFrame): table Gets the specific config section for this frame.
---@field CreateFrame fun(self: ECMFrame): Frame Creates the inner frame.
---@field SetHidden fun(self: ECMFrame, hide: boolean) Sets whether the frame is hidden.
---@field UpdateLayout fun(self: ECMFrame): boolean Updates the visual layout of the frame.
---@field AddMixin fun(target: table, name: string) Adds ECMFrame methods and initializes state on target.


-- --- Returns the top gap offset for the first bar anchored to the viewer.
-- --- Combines profile-level gap (chain offset) with module-level offset.
-- ---@param cfg table|nil Module-specific config
-- ---@param profile table|nil Full profile table
-- ---@return number
-- function BarFrame.GetTopGapOffset(cfg, profile)
--     local profileOffset = (profile and profile.offsetY) or 6
--     local moduleOffset = (cfg and cfg.offsetY) or 0
--     return profileOffset + moduleOffset
-- end



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
        local barModule = ECM:GetModuleByName(barName)
        if barModule and barModule:IsEnabled() then
            local barFrame = barModule:GetBarFrame()
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

    -- Optional border frame (shown when cfg.border.enabled)
    frame.Border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Border:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.Border:Hide()

    return frame
end

function ECMFrame:SetHidden(hide)
    self._hidden = hide
end

function ECMFrame:UpdateLayout()
    local configSection = self:GetConfigSection()
    local mode = configSection.anchorMode
    local frame = self:GetInnerFrame()

    if self._hidden or not (configSection and configSection.enabled) then
        frame:Hide()
        return false
    end

    -- Determine the layout parameters based on the anchor mode. Chain mode will
    -- append this frame to the previous in the chain and inherit its width.
    local anchor, offsetX, offsetY, width, height
    if mode == "chain" then
        anchor = GetNextChainAnchor(self.Name, configSection)
        offsetX = 0
        offsetY = configSection.offsetY and -configSection.offsetY or 0
        height = configSection.height
        width = nil -- Width will be set by anchoring
    elseif mode == "independent" then
        assert(false, "NYI")
    end

    local anchorPoint = "TOPLEFT"
    local anchorRelativePoint = "BOTTOMLEFT"
    local layoutCache = self._layoutCache or {}

    -- Detect whether or not the layout has changed and skip redrawing if not.
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
