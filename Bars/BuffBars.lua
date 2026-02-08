-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local Util = ns.Util
local C = ns.Constants

local ECMFrame = ns.Mixins.ECMFrame

local BuffBars = ECM:NewModule("BuffBars", "AceEvent-3.0")
ECM.BuffBars = BuffBars

---@class ECM_BuffBarsModule : ECMFrame

---@class ECM_BuffBarChild : Frame
---@field __ecmAnchorHooked boolean
---@field __ecmStyled boolean

-- Helper functions for accessing texture/color utilities
local BarHelpers = {
    GetTexture = function(texKey)
        return Util.GetTexture(texKey)
    end,
    GetBgColor = function(moduleConfig, globalConfig)
        local bgColor = (moduleConfig and moduleConfig.bgColor) or (globalConfig and globalConfig.barBgColor)
        return bgColor or C.COLOR_BLACK
    end,
    ApplyFont = function(fontString, globalConfig)
        if not fontString then
            return
        end
        Util.ApplyFont(fontString, globalConfig)
    end,
    GetBarHeight = function(moduleConfig, globalConfig, fallback)
        local height = (moduleConfig and moduleConfig.height) or (globalConfig and globalConfig.barHeight) or (fallback or 13)
        return Util.PixelSnap(height)
    end,
    GetBarWidth = function(moduleConfig, globalConfig, fallback)
        local width = (moduleConfig and moduleConfig.width) or (globalConfig and globalConfig.barWidth) or (fallback or 300)
        return Util.PixelSnap(width)
    end,
}

--- Returns current class ID and spec ID.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    return classID, specID
end

--- Ensures nested tables exist for buff bar color storage.
---@param cfg table|nil
local function EnsureColorStorage(cfg)
    if not cfg then
        return
    end

    if not cfg.colors then
        cfg.colors = {
            perSpell = {},
            cache = {},
            defaultColor = C.BUFFBARS_DEFAULT_COLOR,
        }
    end

    local colors = cfg.colors
    if not colors.perSpell then
        colors.perSpell = {}
    end
    if not colors.cache then
        colors.cache = {}
    end
    if not colors.defaultColor then
        colors.defaultColor = C.BUFFBARS_DEFAULT_COLOR
    end
end

--- Gets color context for current class/spec.
---@param module ECM_BuffBarsModule
---@return table|nil cfg, number|nil classID, number|nil specID
local function GetColorContext(module)
    local cfg = module.ModuleConfig
    if not cfg then
        return nil, nil, nil
    end
    local classID, specID = GetCurrentClassSpec()
    return cfg, classID, specID
end

--- Returns cached color for bar at index for current class/spec, or default if not set.
---@param barIndex number 1-based index in layout order
---@param cfg table|nil
---@return ECM_Color
local function GetCachedBarColor(barIndex, cfg)
    if not cfg then
        return C.BUFFBARS_DEFAULT_COLOR
    end

    local classID, specID = GetCurrentClassSpec()
    local cache = cfg.colors.cache
    if classID and specID and cache[classID] and cache[classID][specID] and cache[classID][specID][barIndex] then
        local c = cache[classID][specID][barIndex].color
        if c then
            return c
        end
    end

    return cfg.colors.defaultColor or C.BUFFBARS_DEFAULT_COLOR
end

--- Returns color for spell with name spellName for current class/spec, or nil if not set.
---@param spellName string
---@param cfg table|nil
---@return ECM_Color
local function GetSpellColor(spellName, cfg)
    if not cfg or not cfg.colors.perSpell then
        return C.BUFFBARS_DEFAULT_COLOR
    end

    local classID, specID = GetCurrentClassSpec()
    local colors = cfg.colors.perSpell
    if classID and specID and colors[classID] and colors[classID][specID] then
        local c = colors[classID][specID][spellName]
        if c then
            return c
        end
    end

    return nil
end

--- Updates bar cache with current bar metadata for Options UI.
---@param barIndex number
---@param spellName string|nil
---@param cfg table|nil
local function UpdateBarCache(barIndex, spellName, cfg)
    if not cfg or not barIndex or barIndex < 1 then
        return
    end

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local cache = cfg.colors.cache

    if cache[classID] and cache[classID][specID] and cache[classID][specID][barIndex] and not spellName then
        -- if this bar is already cached and we aren't able to get the spellName then exit
        -- we don't want to overwrite a value by mistake
        return
    end

    cache[classID] = cache[classID] or {}
    cache[classID][specID] = cache[classID][specID] or {}

    local spellColor = GetSpellColor(spellName or C.BUFFBARS_DEFAULT_SPELLNAME, cfg)
    cache[classID][specID][barIndex] = {
        color = spellColor,
        spellName = spellName or C.BUFFBARS_DEFAULT_SPELLNAME,
        lastSeen = GetTime(),
    }
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

--- Returns visible bar children sorted by Y position (top to bottom) to preserve edit mode order.
--- GetChildren() returns in creation order, not visual order, so we must sort by position.
---@param viewer Frame The BuffBarCooldownViewer frame
---@return table[] Array of {frame, top, order} sorted top-to-bottom
local function GetSortedVisibleChildren(viewer)
    local result = {}

    for insertOrder, child in ipairs({ viewer:GetChildren() }) do
        if child and child.Bar and child:IsShown() then
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

--- Enforces visibility settings for icon, spell name, and duration.
--- This must be called frequently because Blizzard resets these when cooldowns update.
---@param child ECM_BuffBarChild
---@param moduleConfig table
local function HideIconGlows(child)
    if not child then
        return
    end

    local iconFrame = GetBuffBarIconFrame(child)
    local function HideFrame(frame)
        if frame and frame.Hide then
            frame:Hide()
        end
    end

    -- Keep this list explicit and ordered for deterministic behavior.
    HideFrame(child.PandemicGlow)
    HideFrame(child.IconGlow)
    HideFrame(child.Glow)
    HideFrame(child.SpellActivationAlert)
    HideFrame(child.spellActivationAlert)

    if iconFrame then
        HideFrame(iconFrame.PandemicGlow)
        HideFrame(iconFrame.IconGlow)
        HideFrame(iconFrame.Glow)
        HideFrame(iconFrame.SpellActivationAlert)
        HideFrame(iconFrame.spellActivationAlert)

        local overlay = GetBuffBarIconOverlay(iconFrame)
        if overlay and overlay.Hide then
            overlay:Hide()
        end
    end
end

---@param child ECM_BuffBarChild
---@param moduleConfig table
local ApplyStatusBarAnchors
local ApplyBarNameInset

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

    if not showIcon then
        HideIconGlows(child)
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

---@param child ECM_BuffBarChild
---@param iconFrame Frame|nil
---@param iconHeight number|nil
ApplyStatusBarAnchors = function(child, iconFrame, iconHeight)
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
ApplyBarNameInset = function(child, iconFrame, iconHeight)
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

--- Applies styling to a single cooldown bar child.
---@param child ECM_BuffBarChild
---@param moduleConfig table
---@param globalConfig table
---@param barIndex number|nil 1-based index in layout order (for per-bar colors)
local function ApplyCooldownBarStyle(child, moduleConfig, globalConfig, barIndex)
    if not (child and child.Bar) then
        return
    end

    local bar = child.Bar
    if not (bar and bar.SetStatusBarTexture) then
        return
    end

    local texKey = globalConfig and globalConfig.texture
    local tex = BarHelpers.GetTexture(texKey)
    bar:SetStatusBarTexture(tex)

    -- Update bar cache for Options UI (extract spell name safely)
    -- NOTE: Spell names from GetText() can be secret values - cannot compare them
    if barIndex then
        local spellName = nil
        if bar.Name and bar.Name.GetText then
            local ok, text = pcall(bar.Name.GetText, bar.Name)
            -- Check if we can access the value before using it
            if ok and text and (type(canaccessvalue) ~= "function" or canaccessvalue(text)) then
                spellName = text
            end

            UpdateBarCache(barIndex, spellName, moduleConfig)
        end
    end

    -- Apply bar color from per-bar settings or default
    if bar.SetStatusBarColor and barIndex then
        local color = GetCachedBarColor(barIndex, moduleConfig)
        bar:SetStatusBarColor(color.r, color.g, color.b, 1.0)
    end

    local bgColor = BarHelpers.GetBgColor(moduleConfig, globalConfig)
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

    local height = BarHelpers.GetBarHeight(moduleConfig, globalConfig, 13)
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

    BarHelpers.ApplyFont(bar.Name, globalConfig)
    BarHelpers.ApplyFont(bar.Duration, globalConfig)

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

    -- Check visibility first
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
        local width = BarHelpers.GetBarWidth(cfg, globalConfig, 300)

        if width and width > 0 then
            viewer:SetWidth(width)
        end
    end

    -- Style all visible children (skip already-styled unless markers were reset)
    local visibleChildren = GetSortedVisibleChildren(viewer)
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

    local visibleChildren = GetSortedVisibleChildren(viewer)
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
        if child then
            child.__ecmStyled = nil
        end
    end

    -- Clear bar cache for current class/spec so it gets rebuilt fresh.
    -- This ensures the Options UI shows correct spell names after reordering.
    local cfg = self.ModuleConfig
    if cfg and cfg.colors and cfg.colors.cache then
        local classID, specID = GetCurrentClassSpec()
        if classID and specID then
            local cache = cfg.colors.cache
            if cache[classID] then
                cache[classID][specID] = {}
            end
        end
    end
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
        -- Use immediate update (not scheduled) so the cache is rebuilt before
        -- the user opens Options. Edit mode exit is infrequent, so no throttling needed.
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
-- Options UI / Color Management
--------------------------------------------------------------------------------

--- Returns cached bars for current class/spec for Options UI.
---@return table<number, ECM_BarCacheEntry> bars Indexed by bar position
function BuffBars:GetCachedBars()
    local cfg, classID, specID = GetColorContext(self)
    if not cfg or not classID or not specID then
        return {}
    end

    local cache = cfg.colors.cache
    if cache[classID] and cache[classID][specID] then
        return cache[classID][specID]
    end

    return {}
end

--- Rebuilds current class/spec cache from the viewer's existing children.
--- Useful for Options refresh when a full layout pass is not available.
---@return boolean rebuilt True when at least one bar was cached
function BuffBars:RebuildCacheFromViewer()
    local viewer = _G[C.VIEWER_BUFFBAR]
    if not viewer then
        return false
    end

    local cfg = self.ModuleConfig
    if not cfg or not cfg.colors then
        return false
    end

    local rebuilt = false
    local children = { viewer:GetChildren() }
    local barIndex = 1
    for _, child in ipairs(children) do
        if child and child:IsVisible() then
            local spellName
            local textObj = child.GetText and child:GetText()
            if textObj and textObj.GetText then
                local ok, text = pcall(textObj.GetText, textObj)
                if ok and text and (type(canaccessvalue) ~= "function" or canaccessvalue(text)) then
                    spellName = text
                end
            end

            UpdateBarCache(barIndex, spellName, cfg)
            rebuilt = true
            barIndex = barIndex + 1
        end
    end

    return rebuilt
end

--- Returns configured spell colors for current class/spec for Options UI.
---@return table<string, ECM_Color> per-spell colors Indexed by spell name
function BuffBars:GetSpellSettings()
    local cfg, classID, specID = GetColorContext(self)
    if not cfg or not classID or not specID then
        return {}
    end

    local cache = cfg.colors.perSpell
    if cache[classID] and cache[classID][specID] then
        return cache[classID][specID]
    end

    return {}
end

--- Sets color for named spell for current class/spec.
---@param spellName string
---@param r number
---@param g number
---@param b number
function BuffBars:SetSpellColor(spellName, r, g, b)
    local cfg, classID, specID = GetColorContext(self)
    if not cfg or not classID or not specID then
        return
    end

    local colors = cfg.colors.perSpell
    colors[classID] = colors[classID] or {}
    colors[classID][specID] = colors[classID][specID] or {}
    colors[classID][specID][spellName] = { r = r, g = g, b = b, a = 1 }

    Util.Log("BuffBars", "SetSpellColor", { spellName = spellName, r = r, g = g, b = b })

    self:ResetStyledMarkers()
    self:ScheduleLayoutUpdate()
end

--- Resets color for named spell to default.
---@param spellName string
function BuffBars:ResetSpellColor(spellName)
    local cfg, classID, specID = GetColorContext(self)
    if not cfg or not classID or not specID then
        return
    end

    local colors = cfg.colors.perSpell
    if colors[classID] and colors[classID][specID] then
        colors[classID][specID][spellName] = nil
    end

    Util.Log("BuffBars", "ResetSpellColor", { spellName = spellName })

    -- Refresh bars to apply default color
    self:ResetStyledMarkers()
    self:ScheduleLayoutUpdate()
end

--- Returns color for named spell (wrapper for Options UI).
---@param spellName string
---@return number r, number g, number b
function BuffBars:GetSpellColor(spellName)
    local cfg = self.ModuleConfig
    local color = GetSpellColor(spellName, cfg) or cfg.colors.defaultColor or C.BUFFBARS_DEFAULT_COLOR

    return color.r, color.g, color.b
end

--- Checks if a named spell has a custom color set.
---@param spellName string
---@return boolean
function BuffBars:HasCustomSpellColor(spellName)
    local cfg, classID, specID = GetColorContext(self)
    if not cfg or not classID or not specID then
        return false
    end

    local spells = cfg.colors.perSpell
    return spells[classID] and spells[classID][specID] and spells[classID][specID][spellName] ~= nil
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
        EnsureColorStorage(self.ModuleConfig)
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
