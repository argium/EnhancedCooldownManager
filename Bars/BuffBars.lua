-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local Util = ns.Util
local C = ns.Constants
local SecretedStore = ns.SecretedStore

local ECMFrame = ns.Mixins.ECMFrame
local BuffBarColors = ns.BuffBarColors

local BuffBars = ECM:NewModule("BuffBars", "AceEvent-3.0")
ECM.BuffBars = BuffBars

---@class ECM_BuffBarsModule : ECMFrame

---@class ECM_BuffBarChild : Frame
---@field __ecmAnchorHooked boolean
---@field __ecmStyled boolean

local function GetTexture(texKey)
    return Util.GetTexture(texKey)
end

local function GetBgColor(moduleConfig, globalConfig)
    local bgColor = (moduleConfig and moduleConfig.bgColor) or (globalConfig and globalConfig.barBgColor)
    return bgColor or C.COLOR_BLACK
end

local function ApplyBarFont(fontString, globalConfig)
    if not fontString then
        return
    end
    Util.ApplyFont(fontString, globalConfig)
end

local function GetBarHeight(moduleConfig, globalConfig, fallback)
    local height = (moduleConfig and moduleConfig.height) or (globalConfig and globalConfig.barHeight) or (fallback or 13)
    return Util.PixelSnap(height)
end

local function GetBarWidth(moduleConfig, globalConfig, fallback)
    local width = (moduleConfig and moduleConfig.width) or (globalConfig and globalConfig.barWidth) or (fallback or 300)
    return Util.PixelSnap(width)
end

--- Returns normalized spell name for a buff bar child, or nil if unavailable.
---@param child ECM_BuffBarChild|nil
---@return string|nil
local function GetChildSpellName(child)
    local bar = child and child.Bar
    if not (bar and bar.Name and bar.Name.GetText) then
        return nil
    end

    local text = bar.Name:GetText()
    if SecretedStore and SecretedStore.IsSecretValue and SecretedStore.IsSecretValue(text) then
        Util.Log("BuffBars", "GetChildSpellName", {
            message = "Spell name is secret",
            childName = child:GetName() or "nil",
        })
        return nil
    end

    if type(text) ~= "string" then
        return nil
    end

    if text == "" then
        return nil
    end

    return text
end

local function GetBuffBarBackground(statusBar)
    if not statusBar or not statusBar.GetRegions then
        return nil
    end

    local cached = statusBar.__ecmBarBG
    if cached and cached.IsObjectType and cached:IsObjectType("Texture") then
        return cached
    end

    for _, region in ipairs({ statusBar:GetRegions() }) do
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas == "UI-HUD-CoolDownManager-Bar-BG" or atlas == "UI-HUD-CooldownManager-Bar-BG" then
                statusBar.__ecmBarBG = region
                return region
            end
        end
    end

    return nil
end

--- Gets a deterministic icon region by index.
---@param iconFrame Frame|nil
---@param index number
---@return Texture|nil
local function GetIconRegion(iconFrame, index)
    if not iconFrame or not iconFrame.GetRegions then
        return nil
    end

    local region = select(index, iconFrame:GetRegions())
    if region and region.IsObjectType and region:IsObjectType("Texture") then
        return region
    end

    return nil
end

---@param iconFrame Frame|nil
---@return Texture|nil
local function GetBuffBarIconTexture(iconFrame)
    return GetIconRegion(iconFrame, C.BUFFBARS_ICON_TEXTURE_REGION_INDEX)
end

---@param iconFrame Frame|nil
---@return Texture|nil
local function GetBuffBarIconOverlay(iconFrame)
    return GetIconRegion(iconFrame, C.BUFFBARS_ICON_OVERLAY_REGION_INDEX)
end

---@param child ECM_BuffBarChild
---@return Frame|nil
local function GetBuffBarIconFrame(child)
    return child and child.Icon or nil
end

--- Returns the icon texture file ID for a buff bar child, or nil if unavailable.
--- Used as a stable secondary identifier when the spell name is secret.
---@param child ECM_BuffBarChild|nil
---@return number|nil
local function GetChildTextureFileID(child)
    local iconFrame = GetBuffBarIconFrame(child)
    if not iconFrame then
        return nil
    end
    local iconTexture = GetBuffBarIconTexture(iconFrame)
    if not (iconTexture and iconTexture.GetTextureFileID) then
        return nil
    end
    return iconTexture:GetTextureFileID()
end

--- Returns visible bar children sorted by Y position (top to bottom) to preserve edit mode order.
--- GetChildren() returns in creation order, not visual order, so we must sort by position.
---@param viewer Frame The BuffBarCooldownViewer frame
---@param onlyVisible boolean|nil If true, only include visible children
---@return table[] Array of {frame, top, order} sorted top-to-bottom
local function GetSortedChildren(viewer, onlyVisible)
    local result = {}

    for insertOrder, child in ipairs({ viewer:GetChildren() }) do
        if child and child.Bar and (not onlyVisible or child:IsShown()) then
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

--- Hooks a child frame to re-layout when Blizzard changes its anchors.
---@param child ECM_BuffBarChild
---@param module ECM_BuffBarsModule
local function HookChildAnchoring(child, module)
    if child.__ecmAnchorHooked then
        return
    end
    child.__ecmAnchorHooked = true

    -- Hook SetPoint to detect when Blizzard re-anchors this child
    hooksecurefunc(child, "SetPoint", function()
        -- Only re-layout if we're not already running a layout
        local viewer = _G[C.VIEWER_BUFFBAR]
        if viewer and not module._layoutRunning then
            module:ScheduleLayoutUpdate()
        end
    end)

    -- Hook OnShow to ensure newly shown bars get positioned
    child:HookScript("OnShow", function()
        module:ScheduleLayoutUpdate()
    end)

    child:HookScript("OnHide", function()
        module:ScheduleLayoutUpdate()
    end)
end

---@param child ECM_BuffBarChild
---@param iconFrame Frame|nil
---@param iconHeight number|nil
local function ApplyStatusBarAnchors(child, iconFrame, iconHeight)
    local bar = child and child.Bar
    if not (bar and child) then
        return
    end

    bar:ClearAllPoints()
    if iconFrame and iconFrame:IsShown() then
        bar:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 0, 0)
    else
        bar:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end
    bar:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, 0)
end

---@param child ECM_BuffBarChild
---@param iconFrame Frame|nil
---@param iconHeight number|nil
local function ApplyBarNameInset(child, iconFrame, iconHeight)
    local bar = child and child.Bar
    if not (bar and bar.Name) then
        return
    end

    local leftInset = C.BUFFBARS_TEXT_PADDING
    if iconFrame and iconFrame:IsShown() then
        local resolvedIconHeight = iconHeight
        if not resolvedIconHeight or resolvedIconHeight <= 0 then
            resolvedIconHeight = iconFrame:GetHeight() or 0
        end
        leftInset = resolvedIconHeight + C.BUFFBARS_TEXT_PADDING
    end

    bar.Name:ClearAllPoints()
    bar.Name:SetPoint("LEFT", bar, "LEFT", leftInset, 0)
    if bar.Duration and bar.Duration:IsShown() then
        bar.Name:SetPoint("RIGHT", bar.Duration, "LEFT", -C.BUFFBARS_TEXT_PADDING, 0)
    else
        bar.Name:SetPoint("RIGHT", bar, "RIGHT", -C.BUFFBARS_TEXT_PADDING, 0)
    end
end

---@param child ECM_BuffBarChild
---@param moduleConfig table
local function ApplyVisibilitySettings(child, moduleConfig)
    if not (child and child.Bar) then
        return
    end

    -- Apply visibility settings from buffBars config (default to shown)
    local showIcon = moduleConfig and moduleConfig.showIcon ~= false
    local iconFrame = GetBuffBarIconFrame(child)
    if iconFrame then
        iconFrame:SetShown(showIcon)
        local iconTexture = GetBuffBarIconTexture(iconFrame)

        if iconTexture and iconTexture.SetShown then
            iconTexture:SetShown(showIcon)
        end

        local iconOverlay = GetBuffBarIconOverlay(iconFrame)
        if iconOverlay and iconOverlay.SetShown then
            iconOverlay:SetShown(showIcon)
        end
    end

    local alpha = showIcon and 1 or 0
    if child.DebuffBorder then
        child.DebuffBorder:SetAlpha(alpha)
    end

    if child.Applications then
        child.Applications:SetAlpha(alpha)
    end

    local bar = child.Bar
    if bar.Name then
        bar.Name:SetShown(moduleConfig and moduleConfig.showSpellName ~= false)
    end
    if bar.Duration then
        bar.Duration:SetShown(moduleConfig and moduleConfig.showDuration ~= false)
    end

    ApplyStatusBarAnchors(child, iconFrame, nil)
    ApplyBarNameInset(child, iconFrame, nil)
end

--- Applies styling to a single cooldown bar child.
---@param child ECM_BuffBarChild
---@param moduleConfig table
---@param globalConfig table
---@param barIndex number|nil 1-based index in current layout order (metadata/logging only)
local function ApplyCooldownBarStyle(child, moduleConfig, globalConfig, barIndex)
    if not (child and child.Bar) then
        return
    end

    local bar = child.Bar
    if not (bar and bar.SetStatusBarTexture) then
        return
    end

    local texKey = globalConfig and globalConfig.texture
    local tex = GetTexture(texKey)
    bar:SetStatusBarTexture(tex)

    -- Resolve the color lookup key: spell name if available, otherwise the icon
    -- texture file ID as a stable fallback for bars with secret/unavailable names.
    if bar.SetStatusBarColor then
        local spellName = GetChildSpellName(child)
        local colorKey = BuffBarColors.GetColorKey(spellName, GetChildTextureFileID(child))
        local r, g, b = BuffBarColors.GetSpellColor(colorKey)
        bar:SetStatusBarColor(r, g, b, 1.0)
    end

    local bgColor = GetBgColor(moduleConfig, globalConfig)
    local barBG = GetBuffBarBackground(bar)
    if barBG then
        barBG:SetTexture(C.FALLBACK_TEXTURE)
        barBG:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        barBG:ClearAllPoints()
        barBG:SetPoint("TOPLEFT", child, "TOPLEFT")
        barBG:SetPoint("BOTTOMRIGHT", child, "BOTTOMRIGHT")
        barBG:SetDrawLayer("BACKGROUND", 0)
    end

    if bar.Pip then
        bar.Pip:Hide()
        bar.Pip:SetTexture(nil)
    end

    local height = GetBarHeight(moduleConfig, globalConfig, 13)
    if height and height > 0 then
        bar:SetHeight(height)
        child:SetHeight(height)
    end

    local iconFrame = GetBuffBarIconFrame(child)

    -- Apply visibility settings (extracted to separate function for frequent reapplication)
    ApplyVisibilitySettings(child, moduleConfig)

    if iconFrame and height and height > 0 then
        iconFrame:SetSize(height, height)
    end

    ApplyBarFont(bar.Name, globalConfig)
    ApplyBarFont(bar.Duration, globalConfig)

    if iconFrame then
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end

    ApplyStatusBarAnchors(child, iconFrame, height)

    -- Keep the bar/background full-width (under icon), but inset spell text when icon is shown.
    ApplyBarNameInset(child, iconFrame, height)

    -- Mark as styled
    child.__ecmStyled = true

    Util.Log("BuffBars", "Applied style to bar", {
        barIndex = barIndex,
        showIcon = moduleConfig and moduleConfig.showIcon ~= false,
        showSpellName = moduleConfig and moduleConfig.showSpellName ~= false,
        showDuration = moduleConfig and moduleConfig.showDuration ~= false,
        height = height,
    })
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
    local viewer = _G[C.VIEWER_BUFFBAR]
    if not viewer then
        Util.Log("BuffBars", "CreateFrame", "BuffBarCooldownViewer not found, creating placeholder")
        -- Fallback: create a placeholder frame if Blizzard viewer doesn't exist
        viewer = CreateFrame("Frame", "ECMBuffBarPlaceholder", UIParent)
        viewer:SetSize(200, 20)
    end
    return viewer
end

--- Override UpdateLayout to position the BuffBarViewer and apply styling to children.
function BuffBars:UpdateLayout()
    local viewer = self.InnerFrame
    if not viewer then
        return false
    end

    local globalConfig = self.GlobalConfig
    local cfg = self.ModuleConfig

    -- Check visibility
    if not self:ShouldShow() then
        -- Util.Log(self.Name, "BuffBars:UpdateLayout", "ShouldShow returned false, hiding viewer")
        viewer:Hide()
        return false
    end

    local params = self:CalculateLayoutParams()

    -- Only apply anchoring in chain mode; free mode is handled by Blizzard's edit mode
    if params.mode == C.ANCHORMODE_CHAIN then
        viewer:ClearAllPoints()
        viewer:SetPoint("TOPLEFT", params.anchor, "BOTTOMLEFT", params.offsetX, params.offsetY)
        viewer:SetPoint("TOPRIGHT", params.anchor, "BOTTOMRIGHT", params.offsetX, params.offsetY)
    elseif params.mode == C.ANCHORMODE_FREE then
        local width = GetBarWidth(cfg, globalConfig, 300)

        if width and width > 0 then
            viewer:SetWidth(width)
        end
    end

    -- Style all visible children (skip already-styled unless markers were reset)
    local visibleChildren = GetSortedChildren(viewer, true)
    for barIndex, entry in ipairs(visibleChildren) do
        if not entry.frame.__ecmStyled then
            ApplyCooldownBarStyle(entry.frame, cfg, globalConfig, barIndex)
        else
            -- Always reapply visibility settings because Blizzard resets them on cooldown updates
            ApplyVisibilitySettings(entry.frame, cfg)
        end
        HookChildAnchoring(entry.frame, self)
    end

    -- Layout bars vertically
    self:LayoutBars()

    viewer:Show()
    Util.Log(self.Name, "BuffBars:UpdateLayout", {
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

--- Positions all bar children in a vertical stack, preserving edit mode order.
function BuffBars:LayoutBars()
    local viewer = _G[C.VIEWER_BUFFBAR]
    if not viewer then
        return
    end

    self._layoutRunning = true

    local visibleChildren = GetSortedChildren(viewer, true)
    local prev

    for _, entry in ipairs(visibleChildren) do
        local child = entry.frame
        child:ClearAllPoints()
        if not prev then
            child:SetPoint("TOPLEFT", viewer, "TOPLEFT", 0, 0)
            child:SetPoint("TOPRIGHT", viewer, "TOPRIGHT", 0, 0)
        else
            child:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, 0)
            child:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0)
        end
        prev = child
    end

    Util.Log("BuffBars", "LayoutBars complete", { visibleCount = #visibleChildren })

    self._layoutRunning = nil
end

--- Resets all styled markers so bars get fully re-styled on next update.
function BuffBars:ResetStyledMarkers()
    local viewer = _G[C.VIEWER_BUFFBAR]
    if not viewer then
        return
    end

    -- Clear anchor cache to force re-anchor
    viewer._layoutCache = nil

    -- Clear styled markers on all children
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        if child and child.__ecmStyled then
            Util.Log("BuffBars", "ResetStyledMarkers", {
                message = "Clearing styled marker for child",
                childName = child:GetName() or "nil",
            })
            child.__ecmStyled = nil
        end
    end

end

--- Scans the viewer's children and returns entries used by Layout discovery scanning.
---@return table[] scanEntries Array of { spellName, textureFileID }
function BuffBars:CollectScanEntries()
    local viewer = self.InnerFrame
    if not viewer then
        return {}
    end

    local children = GetSortedChildren(viewer, false)
    local scanEntries = {}
    for _, entry in ipairs(children) do
        scanEntries[#scanEntries + 1] = {
            spellName = GetChildSpellName(entry.frame),
            textureFileID = GetChildTextureFileID(entry.frame),
        }
    end
    return scanEntries
end

--- Hooks the BuffBarCooldownViewer for automatic updates.
function BuffBars:HookViewer()
    local viewer = _G[C.VIEWER_BUFFBAR]
    if not viewer then
        return
    end

    self._viewerLayoutCache = self._viewerLayoutCache or {}

    if self._viewerHooked then
        return
    end
    self._viewerHooked = true

    -- Hook OnShow for initial layout
    viewer:HookScript("OnShow", function(f)
        self:UpdateLayout()
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if self._layoutRunning then
            return
        end
        self:ScheduleLayoutUpdate()
    end)

    -- Hook edit mode transitions
    self:HookEditMode()

    Util.Log("BuffBars", "Hooked BuffBarCooldownViewer")
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
        local viewer = _G[C.VIEWER_BUFFBAR]
        if viewer and viewer:IsShown() then
            self:UpdateLayout()
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        -- Re-apply style during edit mode so bars look correct while editing
        self:ScheduleLayoutUpdate()
    end)

    Util.Log("BuffBars", "Hooked EditModeManagerFrame")
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function BuffBars:OnUnitAura(_, unit)
    if unit == "player" then
        self:ScheduleLayoutUpdate()
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function BuffBars:OnEnable()
    if not self.IsECMFrame then
        ECMFrame.AddMixin(self, "BuffBars")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    -- Register events with dedicated handlers
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")

    -- Hook the viewer and edit mode after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookViewer()
        self:HookEditMode()
        self:ScheduleLayoutUpdate()
    end)

    Util.Log("BuffBars", "OnEnable - module enabled")
end

function BuffBars:OnDisable()
    self:UnregisterAllEvents()
    if self.IsECMFrame and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
    Util.Log("BuffBars", "Disabled")
end
