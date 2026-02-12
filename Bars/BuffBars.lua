-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local C = ns.Constants

local ECMFrame = ns.Mixins.ECMFrame
local BBC = ns.BuffBarColors

local BuffBars = ECM:NewModule("BuffBars", "AceEvent-3.0")
ECM.BuffBars = BuffBars

---@class ECM_BuffBarFrame : Frame
---@field __ecmBuffBarFrame boolean
---@field Bar StatusBar
---@field DebuffBorder any
---@field Icon Frame

local function get_children_ordered(viewer)
    local result = {}
    for insertOrder, child in ipairs({ viewer:GetChildren() }) do
        if child and child.Bar then
            local top = child.GetTop and child:GetTop()
            result[#result + 1] = { frame = child, top = top, order = insertOrder }
        end
    end

    -- Sort top-to-bottom (highest Y first). Use insertion order as tiebreaker
    -- when Y positions are equal or nil (bars not yet positioned by Blizzard).
    table.sort(result, function(a, b)
        local aTop = a.top or 0
        local bTop = b.top or 0
        if aTop ~= bTop then
            return aTop > bTop
        end
        return a.order < b.order
    end)

    return result
end

local function hook_child_frame(child, module)
    if child.__ecmBuffBarFrame then
        return
    end
    child.__ecmBuffBarFrame = true

    -- Stamp lazy setters on the child frame and its Bar sub-frame
    ECM_ApplyLazySetters(child)
    ECM_ApplyLazySetters(child.Bar)
    ECM_ApplyLazySetters(child.Bar.Name)
    ECM_ApplyLazySetters(child.Bar.Duration)
    ECM_ApplyLazySetters(child.Bar.Pip)
    ECM_ApplyLazySetters(child.DebuffBorder)
    ECM_ApplyLazySetters(child.Icon)
    ECM_ApplyLazySetters(child.Icon.Applications)

    -- Hook SetPoint to detect when Blizzard re-anchors this child
    hooksecurefunc(child, "SetPoint", function()
        -- module:ScheduleLayoutUpdate("SetPoint")
    end)

    -- Hook OnShow to ensure newly shown bars get positioned
    child:HookScript("OnShow", function()
        module:ScheduleLayoutUpdate("OnShow")
    end)

    child:HookScript("OnHide", function()
        module:ScheduleLayoutUpdate("OnHide")
    end)

    child.GetSpellName = function(self)
        return self.Bar.Name and self.Bar.Name:GetText() or nil
    end

    child.GetTextureFileID = function(self)
        local iconTexture = self.Icon and self.Icon.GetTexture and self.Icon:GetTexture()
        if iconTexture and iconTexture.GetTexture then
            return iconTexture:GetTexture()
        end
        return nil
    end

end

--- Applies all sizing, styling, visibility, and anchoring to a single buff bar
--- child frame. Lazy setters ensure no-ops when values haven't changed.
---@param frame ECM_BuffBarFrame
---@param config table Module config
---@param globalConfig table Global config
---@param barIndex number Index of the bar (for logging)
local function style_child_frame(frame, config, globalConfig, barIndex)
    if not (frame and frame.__ecmBuffBarFrame) then
        ECM_debug_assert(false, "Attempted to style a child frame that is not a BuffBarFrame", { frame = frame })
        return
    end

    local bar = frame.Bar
    local iconFrame = frame.Icon
    local barBG = bar.BarBG
    -- DevTool:AddData(frame)
    -- DevTool:AddData(iconFrame.Applications)

    -- frame
    --  - Bar
    --     - Name
    --     - Duration
    --     - Pip
    --     - BarBG
    --  - Icon
    --    - Applications
    --  - DebuffBorder

    --------------------------------------------------------------------------
    -- Heights
    --------------------------------------------------------------------------
    local height = (config and config.height) or (globalConfig and globalConfig.barHeight) or 15
    if height > 0 then
        frame:LazySetHeight(height)
        bar:LazySetHeight(height)
        if iconFrame then
            iconFrame:LazySetHeight(height)
            iconFrame:LazySetWidth(height)
        end
    end

    --------------------------------------------------------------------------
    -- Pip — always hidden
    --------------------------------------------------------------------------
    bar.Pip:Hide()
    bar.Pip:SetTexture(nil)

    --------------------------------------------------------------------------
    -- Bar background (BarBG texture)
    --------------------------------------------------------------------------
    local bgColor = (config and config.bgColor) or (globalConfig and globalConfig.barBgColor) or C.COLOR_BLACK
    barBG:SetTexture(C.FALLBACK_TEXTURE)
    frame:LazySetVertexColor(barBG, "barBgColor", bgColor)
    barBG:ClearAllPoints()
    barBG:SetPoint("TOPLEFT", frame, "TOPLEFT")
    barBG:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    barBG:SetDrawLayer("BACKGROUND", 0)

    --------------------------------------------------------------------------
    -- StatusBar texture & color
    --------------------------------------------------------------------------
    local textureName = globalConfig and globalConfig.texture
    local texture = ECM_GetTexture(textureName)
    bar:LazySetStatusBarTexture(bar, texture)

    local barColor = BBC.GetColorForBar(frame)
    if barColor then
        bar:LazySetStatusBarColor(bar, barColor.r, barColor.g, barColor.b, 1.0)
    end

    --------------------------------------------------------------------------
    -- Fonts (before visibility/positioning — font changes affect layout)
    --------------------------------------------------------------------------
    ECM_ApplyFont(bar.Name)
    ECM_ApplyFont(bar.Duration)

    --------------------------------------------------------------------------
    -- Icon anchor
    --------------------------------------------------------------------------
    if iconFrame then
        iconFrame:LazySetAnchors({
            { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
        })
    end

    --------------------------------------------------------------------------
    -- Visibility — icon, name, duration, debuff border, applications
    --------------------------------------------------------------------------
    local showIcon = config and config.showIcon ~= false
    if iconFrame then
        iconFrame:LazySetShown(showIcon)
        local iconTexture = frame:GetTextureFileID()
        if iconTexture and iconTexture.SetShown then
            iconTexture:SetShown(showIcon)
        end
        local iconOverlay = select(C.BUFFBARS_ICON_OVERLAY_REGION_INDEX, iconFrame:GetRegions())
        if iconOverlay and iconOverlay.SetShown then
            iconOverlay:SetShown(showIcon)
        end
    end

    local iconAlpha = showIcon and 1 or 0
    if frame.DebuffBorder then
        frame.DebuffBorder:LazySetAlpha(iconAlpha)
    end
    if iconFrame.Applications then
        iconFrame.Applications:LazySetAlpha(iconAlpha)
    end

    local showSpellName = config and config.showSpellName ~= false
    local showDuration = config and config.showDuration ~= false
    if bar.Name then
        bar.Name:LazySetShown(showSpellName)
    end
    if bar.Duration then
        bar.Duration:LazySetShown(showDuration)
    end

    --------------------------------------------------------------------------
    -- Bar anchors (relative to icon visibility)
    --------------------------------------------------------------------------
    local iconVisible = iconFrame and iconFrame:IsShown()
    if iconVisible then
        bar:LazySetAnchors({
            { "TOPLEFT", iconFrame, "TOPRIGHT", 0, 0 },
            { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 },
        })
    else
        bar:LazySetAnchors({
            { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
            { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 },
        })
    end

    --------------------------------------------------------------------------
    -- Name
    --------------------------------------------------------------------------
    bar.Name:LazySetAnchors({
        { "LEFT", bar, "LEFT", C.BUFFBARS_TEXT_PADDING, 0 },
        { "RIGHT", bar, "RIGHT", -C.BUFFBARS_TEXT_PADDING, 0 },
    })

    if bar.Duration then
        bar.Duration:LazySetAnchors({
            { "RIGHT", bar, "RIGHT", -C.BUFFBARS_TEXT_PADDING, 0 },
        })
    end

    ECM_log(C.SYS.Styling, C.BUFFBARS, "Applied style to bar", {
        barIndex = barIndex,
        height = height,
        pipHidden = true,
        pipTexture = nil,
        barBgColor = (barBG and ((config and config.bgColor) or (globalConfig and globalConfig.barBgColor) or C.COLOR_BLACK)) or nil,
        barBgTexture = barBG and C.FALLBACK_TEXTURE or nil,
        barBgLayer = barBG and "BACKGROUND" or nil,
        barBgSubLayer = barBG and 0 or nil,
        textureName = textureName,
        statusBarTexture = texture,
        statusBarColor = barColor,
        showIcon = showIcon,
        showSpellName = showSpellName,
        showDuration = showDuration,
        iconAlpha = iconAlpha,
        iconVisible = iconVisible,
        iconShown = iconFrame and iconFrame:IsShown() or false,
        iconSize = iconVisible and (iconFrame:GetHeight() or frame:GetHeight() or 0) or 0,
        debuffBorderAlpha = frame.DebuffBorder and iconAlpha or nil,
        applicationsAlpha = iconFrame.Applications and iconAlpha or nil,
        nameShown = showSpellName,
        durationShown = showDuration,
        nameLeftInset = C.BUFFBARS_TEXT_PADDING,
        nameRightPadding = C.BUFFBARS_TEXT_PADDING,
        barAnchorMode = iconVisible and "icon" or "frame",
    })
end


--- Positions all bar children in a vertical stack, preserving edit mode order.
local function layout_bars(self)
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return
    end

    self._layoutRunning = true

    local children = get_children_ordered(viewer)
    local prev

    for _, entry in ipairs(children) do
        local child = entry.frame
        if child:IsShown() then
            if not prev then
                child:LazySetAnchors({
                    { "TOPLEFT", viewer, "TOPLEFT", 0, 0 },
                    { "TOPRIGHT", viewer, "TOPRIGHT", 0, 0 },
                })
            else
                child:LazySetAnchors({
                    { "TOPLEFT", prev, "BOTTOMLEFT", 0, 0 },
                    { "TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0 },
                })
            end
            prev = child
        end
    end

    ECM_log(C.SYS.Layout, C.BUFFBARS, "LayoutBars complete. Found: " .. #children .. " visible bars.")

    self._layoutRunning = nil
end

--------------------------------------------------------------------------------
-- ECMFrame Overrides
--------------------------------------------------------------------------------

--- Override to support custom anchor points in free mode.
---@return table params Layout parameters
function BuffBars:CalculateLayoutParams()
    local globalConfig = self.GlobalConfig
    local cfg = self.ModuleConfig
    local mode = cfg and cfg.anchorMode or C.ANCHORMODE_CHAIN

    local params = { mode = mode }

    if mode == C.ANCHORMODE_CHAIN then
        local anchor, isFirst = self:GetNextChainAnchor(C.BUFFBARS)
        params.anchor = anchor
        params.isFirst = isFirst
        params.anchorPoint = "TOPLEFT"
        params.anchorRelativePoint = "BOTTOMLEFT"
        params.offsetX = 0
        params.offsetY = (isFirst and -(globalConfig and globalConfig.offsetY or 0)) or 0
    else
        -- Free mode: BuffBars supports custom anchor points from config
        params.anchor = UIParent
        params.isFirst = false
        params.anchorPoint = cfg.anchorPoint or "CENTER"
        params.anchorRelativePoint = cfg.relativePoint or "CENTER"
        params.offsetX = cfg.offsetX or 0
        params.offsetY = cfg.offsetY or 0
        params.width = cfg.width
    end

    return params
end

--- Override CreateFrame to return the Blizzard BuffBarCooldownViewer instead of creating a new one.
function BuffBars:CreateFrame()
    return _G["BuffBarCooldownViewer"]
end

--- Override UpdateLayout to position the BuffBarViewer and apply styling to children.
function BuffBars:UpdateLayout(why)
    local viewer = self.InnerFrame
    local globalConfig = self.GlobalConfig
    local cfg = self.ModuleConfig

    if not self:ShouldShow() then
        viewer:Hide()
        return false
    end

    -- Only apply anchoring in chain mode; free mode is handled by Blizzard's edit mode
    local params = self:CalculateLayoutParams()
    if params.mode == C.ANCHORMODE_CHAIN then
        viewer:LazySetAnchors({
            { "TOPLEFT", params.anchor, "BOTTOMLEFT", params.offsetX, params.offsetY },
            { "TOPRIGHT", params.anchor, "BOTTOMRIGHT", params.offsetX, params.offsetY },
        })
    elseif params.mode == C.ANCHORMODE_FREE then
        local width = (cfg and cfg.width) or (globalConfig and globalConfig.barWidth) or 300

        if width and width > 0 then
            viewer:LazySetWidth(width)
        end
    end

    -- Style all visible children (lazy setters make redundant calls no-ops)
    local visibleChildren = get_children_ordered(viewer)
    for barIndex, entry in ipairs(visibleChildren) do
        hook_child_frame(entry.frame, self)
        style_child_frame(entry.frame, cfg, globalConfig, barIndex)
    end

    layout_bars(self)
    viewer:Show()
    ECM_log(C.SYS.Layout, C.BUFFBARS, "UpdateLayout (" .. (why or "") .. ")", {
        mode = params.mode,
        childCount = #visibleChildren,
        viewerWidth = params.width or -1,
        anchor = params.anchor and params.anchor:GetName() or "nil",
        anchorPoint = params.anchorPoint,
        anchorRelativePoint = params.anchorRelativePoint,
        offsetX = params.offsetX,
        offsetY = params.offsetY,
    })
    return true
end

--------------------------------------------------------------------------------
-- Helper Methods
--------------------------------------------------------------------------------

--- Resets all styled markers so bars get fully re-styled on next update.
function BuffBars:ResetStyledMarkers()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return
    end

    -- Clear lazy state on all children to force full re-style
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        child:ResetLazyMarkers()
        if child.Bar then
            child.Bar:ResetLazyMarkers()
        end
    end

end

--- Hooks the BuffBarCooldownViewer for automatic updates.
function BuffBars:HookViewer()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return
    end

    if self._viewerHooked then
        return
    end
    self._viewerHooked = true

    ECM_ApplyLazySetters(viewer)

    -- Hook OnShow for initial layout
    viewer:HookScript("OnShow", function(f)
        self:UpdateLayout("OnShow")
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if self._layoutRunning then
            return
        end
        self:ScheduleLayoutUpdate("OnSizeChanged")
    end)

    -- Hook edit mode transitions
    self:HookEditMode()

    ECM_log(C.SYS.Core, self.Name, "Hooked BuffBarCooldownViewer")
end

--- Hooks EditModeManagerFrame to re-apply layout on exit.
function BuffBars:HookEditMode()
    if self._editModeHooked then
        return
    end

    if not EditModeManagerFrame then
        return
    end

    self._editModeHooked = true

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        self:ResetStyledMarkers()
        if ECM.RefreshBuffBarDiscovery then
            ECM.RefreshBuffBarDiscovery("edit_mode_exit")
        end

        -- Edit mode exit is infrequent, so perform an immediate restyle pass.
        local viewer = _G["BuffBarCooldownViewer"]
        if viewer and viewer:IsShown() then
            self:UpdateLayout("ExitEditMode")
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        -- Re-apply style during edit mode so bars look correct while editing
        self:ScheduleLayoutUpdate("EnterEditMode")
    end)

    ECM_log(C.SYS.Core, self.Name, "Hooked EditModeManagerFrame")
end

function BuffBars:OnUnitAura(_, unit)
    if unit == "player" then
        self:ScheduleLayoutUpdate("OnUnitAura")
    end
end

function BuffBars:OnEnable()
    if not self.IsECMFrame then
        ECMFrame.AddMixin(self, "BuffBars")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    self:RegisterEvent("UNIT_AURA", "OnUnitAura")

    -- Hook the viewer and edit mode after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookViewer()
        self:HookEditMode()
        self:ScheduleLayoutUpdate("OnEnable")
    end)

    ECM_log(C.SYS.Core, self.Name, "OnEnable - module enabled")
end

function BuffBars:OnDisable()
    self:UnregisterAllEvents()
    if self.IsECMFrame and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
    ECM_log(C.SYS.Core, self.Name, "OnDisable - module disabled")
end
