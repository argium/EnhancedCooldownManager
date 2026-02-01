-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

---@class Frame Base UI frame type.

---@class StatusBar : Frame Status bar frame type.

---@class ECM_BuffBarChild : Frame Buff bar child frame.
---@field Bar StatusBar Status bar region for the buff bar.
---@field Icon Frame Icon texture frame.
---@field IconFrame Frame Icon container frame.
---@field IconButton Frame Icon button frame.
---@field __ecmAnchorHooked boolean|nil True when anchor hooks are installed.
---@field __ecmStyled boolean|nil True when ECM styling is applied.

---@class ECM_BuffBarViewer : ECM_PositionedFrame Buff bar viewer frame.
---@field _layoutCache table|nil Cached layout parameters.
---@field ApplyLayout fun(self: ECM_BuffBarViewer, params: table): boolean Applies layout parameters.
---@field InvalidateLayout fun(self: ECM_BuffBarViewer): nil Invalidates cached layout.
---@field __ecmHooked boolean|nil True when viewer hooks are installed.
---@field __ecmLayoutRunning boolean|nil True while ECM layout is running.

---@class ECM_BuffBarsModule : ECMFrame Buff bars module.

local _, ns = ...
local ECM = ns.Addon
local Util = ns.Util
local ECMFrame = ns.Mixins.ECMFrame

-- Helper functions for accessing texture/color utilities
local BarHelpers = {
    GetTexture = function(texKey)
        return Util.GetTexture(texKey)
    end,
    GetBgColor = function(cfg, profile)
        local globalConfig = profile and profile.global
        local bgColor = (cfg and cfg.bgColor) or (globalConfig and globalConfig.barBgColor)
        return bgColor or { r = 0, g = 0, b = 0, a = 1 }
    end,
    ApplyFont = function(fontString, profile)
        if not fontString or not fontString.SetFont then
            return
        end
        local globalConfig = profile and profile.global
        local font = globalConfig and globalConfig.font
        if font then
            fontString:SetFont(font, fontString:GetStringHeight() or 10)
        end
    end,
    GetBarHeight = function(cfg, profile, fallback)
        local gbl = profile and profile.global
        local height = (cfg and cfg.height) or (gbl and gbl.barHeight) or (fallback or 13)
        return Util.PixelSnap(height)
    end,
}

local BuffBars = ECM:NewModule("BuffBars", "AceEvent-3.0")
ECM.BuffBars = BuffBars

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BAR_COLOR = { r = 0.90, g = 0.90, b = 0.90, a = 1 }

local PALETTES = {
    ["Default"] = {
        { r = 0.90, g = 0.90, b = 0.90, a = 1 },
    },
    ["Rainbow"] = {
        { r = 0.95, g = 0.27, b = 0.27, a = 1 }, -- Red
        { r = 0.95, g = 0.65, b = 0.27, a = 1 }, -- Orange
        { r = 0.95, g = 0.95, b = 0.27, a = 1 }, -- Yellow
        { r = 0.27, g = 0.95, b = 0.27, a = 1 }, -- Green
        { r = 0.27, g = 0.65, b = 0.95, a = 1 }, -- Blue
        { r = 0.58, g = 0.27, b = 0.95, a = 1 }, -- Purple
        { r = 0.95, g = 0.27, b = 0.65, a = 1 }, -- Pink
    },
    ["Warm"] = {
        { r = 0.95, g = 0.35, b = 0.25, a = 1 }, -- Red-Orange
        { r = 0.95, g = 0.55, b = 0.25, a = 1 }, -- Orange
        { r = 0.95, g = 0.75, b = 0.30, a = 1 }, -- Golden
        { r = 0.90, g = 0.60, b = 0.40, a = 1 }, -- Tan
    },
    ["Cool"] = {
        { r = 0.25, g = 0.70, b = 0.95, a = 1 }, -- Sky Blue
        { r = 0.30, g = 0.85, b = 0.85, a = 1 }, -- Cyan
        { r = 0.35, g = 0.65, b = 0.90, a = 1 }, -- Ocean Blue
        { r = 0.40, g = 0.55, b = 0.85, a = 1 }, -- Deep Blue
    },
    ["Pastel"] = {
        { r = 0.95, g = 0.75, b = 0.80, a = 1 }, -- Pink
        { r = 0.80, g = 0.85, b = 0.95, a = 1 }, -- Light Blue
        { r = 0.85, g = 0.95, b = 0.80, a = 1 }, -- Light Green
        { r = 0.95, g = 0.90, b = 0.75, a = 1 }, -- Cream
        { r = 0.90, g = 0.80, b = 0.95, a = 1 }, -- Lavender
    },
    ["Neon"] = {
        { r = 1.00, g = 0.10, b = 0.50, a = 1 }, -- Hot Pink
        { r = 0.10, g = 1.00, b = 0.90, a = 1 }, -- Cyan
        { r = 0.90, g = 1.00, b = 0.10, a = 1 }, -- Lime
        { r = 1.00, g = 0.40, b = 0.10, a = 1 }, -- Orange
        { r = 0.50, g = 0.10, b = 1.00, a = 1 }, -- Purple
    },
    ["Earth"] = {
        { r = 0.55, g = 0.45, b = 0.35, a = 1 }, -- Brown
        { r = 0.40, g = 0.60, b = 0.35, a = 1 }, -- Moss Green
        { r = 0.65, g = 0.55, b = 0.40, a = 1 }, -- Sand
        { r = 0.50, g = 0.40, b = 0.30, a = 1 }, -- Dark Earth
    },
}

--- Returns current class ID and spec ID.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    return classID, specID
end

--- Gets the active profile for the module.
---@param module ECM_BuffBarsModule
---@return table|nil profile
local function GetProfile(module)
    if module and module._config then
        return module._config
    end
    return ECM.db and ECM.db.profile
end

--- Ensures nested tables exist for buff bar color storage.
---@param cfg table|nil
local function EnsureColorStorage(cfg)
    if not cfg then
        return
    end

    if not cfg.colors then
        cfg.colors = {
            perBar = {},
            cache = {},
            defaultColor = DEFAULT_BAR_COLOR,
            selectedPalette = nil,
        }
    end

    local colors = cfg.colors
    if not colors.perBar then
        colors.perBar = {}
    end
    if not colors.cache then
        colors.cache = {}
    end
    if not colors.defaultColor then
        colors.defaultColor = DEFAULT_BAR_COLOR
    end
    if colors.selectedPalette == nil then
        colors.selectedPalette = nil
    end
end

--- Gets color from palette for the given bar index.
---@param barIndex number
---@param paletteName string
---@return ECM_Color
local function GetPaletteColor(barIndex, paletteName)
    local palette = PALETTES[paletteName]
    if not palette or #palette == 0 then
        return DEFAULT_BAR_COLOR
    end

    local colorIndex = ((barIndex - 1) % #palette) + 1
    return palette[colorIndex]
end

--- Calculates positioning parameters for BuffBarViewer based on chain/independent mode.
---@param module BuffBars module instance
---@return table params, string mode
local function CalculateBuffBarsLayout(module)
    local cfg = module:GetConfigSection()
    local mode = cfg.anchorMode or "chain"
    local params = {}

    if mode == "chain" then
        -- Chain mode: Find the previous frame in the chain order
        -- BuffBars typically comes after the resource bars, so we need to walk backward
        local anchor = _G["BuffBarCooldownViewer"] -- Fallback

        -- Try to find the previous enabled/visible frame in the chain
        local C = ns.Constants
        if C and C.CHAIN_ORDER then
            local stopIndex = #C.CHAIN_ORDER + 1
            for i, name in ipairs(C.CHAIN_ORDER) do
                if name == "BuffBars" then
                    stopIndex = i
                    break
                end
            end

            for i = stopIndex - 1, 1, -1 do
                local barName = C.CHAIN_ORDER[i]
                local barModule = ECM:GetModule(barName, true)
                if barModule and barModule:IsEnabled() then
                    local barFrame = barModule:GetInnerFrame and barModule:GetInnerFrame()
                    if barFrame and barFrame:IsVisible() then
                        anchor = barFrame
                        break
                    end
                end
            end

            -- If no previous frame, use the viewer as base
            if anchor == _G["BuffBarCooldownViewer"] then
                anchor = _G[C.VIEWER] or UIParent
            end
        end

        params.anchor = anchor
        params.anchorPoint = "TOPLEFT"
        params.relativePoint = "BOTTOMLEFT"
        params.offsetX = 0
        params.offsetY = cfg.offsetY and -cfg.offsetY or 0
    else
        -- Independent mode: use custom anchoring
        params.anchor = UIParent
        params.anchorPoint = cfg.anchorPoint or "CENTER"
        params.relativePoint = cfg.relativePoint or "CENTER"
        params.offsetX = cfg.offsetX or 0
        params.offsetY = cfg.offsetY or 0
        params.width = cfg.width
    end

    return params, mode
end

--- Returns color for bar at index for current class/spec, or palette/default if not set.
---@param barIndex number 1-based index in layout order
---@param cfg table|nil
---@return ECM_Color
local function GetBarColor(barIndex, cfg)
    if not cfg then
        return DEFAULT_BAR_COLOR
    end

    EnsureColorStorage(cfg)

    local classID, specID = GetCurrentClassSpec()
    local colors = cfg.colors.perBar
    if classID and specID and colors[classID] and colors[classID][specID] then
        local c = colors[classID][specID][barIndex]
        if c then
            return c
        end
    end

    local selectedPalette = cfg.colors.selectedPalette
    if selectedPalette and PALETTES[selectedPalette] then
        return GetPaletteColor(barIndex, selectedPalette)
    end

    return cfg.colors.defaultColor or DEFAULT_BAR_COLOR
end

--- Updates bar cache with current bar metadata for Options UI.
---@param barIndex number
---@param spellName string|nil
---@param cfg table|nil
local function UpdateBarCache(barIndex, spellName, cfg)
    if not cfg or not barIndex or barIndex < 1 then
        return
    end

    EnsureColorStorage(cfg)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local cache = cfg.colors.cache
    cache[classID] = cache[classID] or {}
    cache[classID][specID] = cache[classID][specID] or {}

    cache[classID][specID][barIndex] = {
        spellName = spellName,
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
        local viewer = module:GetViewer()
        if viewer and not viewer.__ecmLayoutRunning then
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

--- Applies styling to a single cooldown bar child.
---@param child ECM_BuffBarChild
---@param profile table
---@param barIndex number|nil 1-based index in layout order (for per-bar colors)
local function ApplyCooldownBarStyle(child, profile, barIndex)
    if not (child and child.Bar and profile) then
        return
    end

    local bar = child.Bar
    if not (bar and bar.SetStatusBarTexture) then
        return
    end

    local gbl = profile.global or {}

    local texKey = gbl.texture
    local tex = BarHelpers.GetTexture(texKey)
    bar:SetStatusBarTexture(tex)

    -- Apply bar color from per-bar settings or default
    local cfg = profile.buffBars or {}
    if bar.SetStatusBarColor and barIndex then
        local color = GetBarColor(barIndex, cfg)
        bar:SetStatusBarColor(color.r, color.g, color.b, 1.0)
    end

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
        end
        UpdateBarCache(barIndex, spellName, cfg)
    end

    local bgColor = BarHelpers.GetBgColor(nil, profile)
    local barBG = GetBuffBarBackground(bar)
    if barBG then
        barBG:SetTexture(WHITE8)
        barBG:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        barBG:ClearAllPoints()
        barBG:SetPoint("TOPLEFT", bar, "TOPLEFT")
        barBG:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT")
        barBG:SetDrawLayer("BACKGROUND", 0)
    end

    if bar.Pip then
        bar.Pip:Hide()
        bar.Pip:SetTexture(nil)
    end

    local height = BarHelpers.GetBarHeight(nil, profile, 13)
    if height and height > 0 then
        bar:SetHeight(height)
        child:SetHeight(height)
    end

    local iconFrame = child.Icon or child.IconFrame or child.IconButton

    -- Apply visibility settings from buffBars config (default to shown)
    if iconFrame then
        iconFrame:SetShown(cfg.showIcon ~= false)
    end
    if bar.Name then
        bar.Name:SetShown(cfg.showSpellName ~= false)
    end
    if bar.Duration then
        bar.Duration:SetShown(cfg.showDuration ~= false)
    end

    if iconFrame and height and height > 0 then
        iconFrame:SetSize(height, height)
    end

    BarHelpers.ApplyFont(bar.Name, profile)
    BarHelpers.ApplyFont(bar.Duration, profile)

    if iconFrame then
        iconFrame:ClearAllPoints()
        iconFrame:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end

    bar:ClearAllPoints()
    if iconFrame and iconFrame:IsShown() then
        bar:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 0, 0)
    else
        bar:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
    end
    bar:SetPoint("TOPRIGHT", child, "TOPRIGHT", 0, 0)

    -- Mark as styled
    child.__ecmStyled = true
end

--- Returns the BuffBarCooldownViewer frame.
---@return ECM_BuffBarViewer|nil
function BuffBars:GetViewer()
    return _G["BuffBarCooldownViewer"]
end

--------------------------------------------------------------------------------
-- ECMFrame Overrides
--------------------------------------------------------------------------------

--- Override CreateFrame to return the Blizzard BuffBarCooldownViewer instead of creating a new one.
function BuffBars:CreateFrame()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        Util.Log("BuffBars", "CreateFrame", "BuffBarCooldownViewer not found, creating placeholder")
        -- Fallback: create a placeholder frame if Blizzard viewer doesn't exist
        viewer = CreateFrame("Frame", "ECMBuffBarPlaceholder", UIParent)
        viewer:SetSize(200, 20)
    end
    return viewer
end

--- Override ShouldShow to check buffBars.enabled config.
function BuffBars:ShouldShow()
    local config = self:GetConfigSection()
    return not self._hidden and config.enabled ~= false
end

--- Override UpdateLayout to position the BuffBarViewer and apply styling to children.
function BuffBars:UpdateLayout()
    local viewer = self:GetInnerFrame()
    if not viewer then
        return false
    end

    local globalConfig = self:GetGlobalConfig()
    local cfg = self:GetConfigSection()

    if not self:ShouldShow() then
        Util.Log(self.Name, "BuffBars:UpdateLayout", "ShouldShow returned false, hiding viewer")
        viewer:Hide()
        return false
    end

    -- Calculate positioning parameters
    local params, mode = CalculateBuffBarsLayout(self)

    -- Apply positioning
    viewer:ClearAllPoints()
    if params.width then
        viewer:SetWidth(params.width)
    end
    viewer:SetPoint(params.anchorPoint, params.anchor, params.relativePoint, params.offsetX, params.offsetY)

    -- Style all visible children
    local visibleChildren = GetSortedVisibleChildren(viewer)
    for barIndex, entry in ipairs(visibleChildren) do
        ApplyCooldownBarStyle(entry.frame, ECM.db.profile, barIndex)
        HookChildAnchoring(entry.frame, self)
    end

    -- Layout bars vertically
    self:LayoutBars()

    viewer:Show()
    Util.Log(self.Name, "BuffBars:UpdateLayout", {
        mode = mode,
        childCount = #visibleChildren,
    })

    return true
end

--- Override Refresh to update layout and styling.
function BuffBars:Refresh(force)
    local continue = ECMFrame.Refresh(self, force)
    if not continue then
        return false
    end

    self:UpdateLayout()
end

--- Resets all styled markers so bars get fully re-styled on next update.
function BuffBars:ResetStyledMarkers()
    local viewer = self:GetViewer()
    if not viewer then
        return
    end

    -- Clear anchor cache to force re-anchor
    if viewer.InvalidateLayout then
        viewer:InvalidateLayout()
    else
        viewer._layoutCache = nil
    end

    -- Clear styled markers on all children
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        if child then
            child.__ecmStyled = nil
        end
    end

    -- Clear bar cache for current class/spec so it gets rebuilt fresh.
    -- This ensures the Options UI shows correct spell names after reordering.
    local profile = GetProfile(self)
    local cfg = profile and profile.buffBars
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
        local viewer = self:GetViewer()
        if viewer and viewer:IsShown() then
            self:UpdateLayoutAndRefresh("EditModeExit")
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        -- Re-apply style during edit mode so bars look correct while editing
        self:ScheduleLayoutUpdate()
    end)

    Util.Log("BuffBars", "Hooked EditModeManagerFrame")
end

--- Hooks the BuffBarCooldownViewer for automatic updates.
function BuffBars:HookViewer()
    local viewer = self:GetViewer()
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
        self:UpdateLayoutAndRefresh("ViewerOnShow")
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

--- Schedules a throttled layout update.
function BuffBars:ScheduleLayoutUpdate()
    if self._layoutPending then
        return
    end

    local profile = GetProfile(self)
    self._layoutPending = true

    assert(profile and profile.updateFrequency, "ECM: profile.updateFrequency missing")

    C_Timer.After(profile.updateFrequency, function()
        self._layoutPending = nil
        local viewer = self:GetViewer()
        if viewer and viewer:IsShown() then
            self:UpdateLayoutAndRefresh("ScheduleLayoutUpdate")
        end
    end)
end

--- Schedules a throttled rescan for new/changed bars.
function BuffBars:ScheduleRescan()
    if self._rescanPending then
        return
    end

    local profile = GetProfile(self)
    self._rescanPending = true

    assert(profile and profile.updateFrequency, "ECM: profile.updateFrequency missing")

    C_Timer.After(profile.updateFrequency, function()
        self._rescanPending = nil
        local viewer = self:GetViewer()
        if viewer and viewer:IsShown() then
            self:RescanBars()
        end
    end)
end

--- Rescans and styles any unstyled bars.
function BuffBars:RescanBars()
    local viewer = self:GetViewer()
    if not viewer then
        return
    end

    local profile = GetProfile(self)

    -- Hook all children for anchor change detection
    for _, child in ipairs({ viewer:GetChildren() }) do
        if child and child.Bar then
            HookChildAnchoring(child, self)
        end
    end

    -- Style unstyled bars in sorted order
    local visibleChildren = GetSortedVisibleChildren(viewer)
    local newBarsFound = false

    for barIndex, entry in ipairs(visibleChildren) do
        if not entry.frame.__ecmStyled then
            ApplyCooldownBarStyle(entry.frame, profile, barIndex)
            newBarsFound = true
        end
    end

    if newBarsFound then
        self:LayoutBars()
    end
end

--- Positions all bar children in a vertical stack, preserving edit mode order.
function BuffBars:LayoutBars()
    local viewer = self:GetViewer()
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

--- Legacy method for compatibility - now delegates to UpdateLayout.
---@param why string
function BuffBars:UpdateLayoutAndRefresh(why)
    Util.Log("BuffBars", "UpdateLayoutAndRefresh (legacy)", { why = why })
    self:UpdateLayout()
end

--- Returns cached bars for current class/spec for Options UI.
---@return table<number, ECM_BarCacheEntry> bars Indexed by bar position
function BuffBars:GetCachedBars()
    local profile = GetProfile(self)
    if not profile then
        return {}
    end

    local cfg = profile.buffBars
    EnsureColorStorage(cfg)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return {}
    end

    local cache = cfg.colors.cache
    if cache[classID] and cache[classID][specID] then
        return cache[classID][specID]
    end

    return {}
end

--- Sets color for bar at index for current class/spec.
---@param barIndex number
---@param r number
---@param g number
---@param b number
function BuffBars:SetBarColor(barIndex, r, g, b)
    local profile = GetProfile(self)
    if not profile then
        return
    end

    local cfg = profile.buffBars
    EnsureColorStorage(cfg)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local colors = cfg.colors.perBar
    colors[classID] = colors[classID] or {}
    colors[classID][specID] = colors[classID][specID] or {}
    colors[classID][specID][barIndex] = { r = r, g = g, b = b, a = 1 }

    Util.Log("BuffBars", "SetBarColor", { barIndex = barIndex, r = r, g = g, b = b })

    self:ResetStyledMarkers()
    self:ScheduleLayoutUpdate()
end

--- Resets color for bar at index to default.
---@param barIndex number
function BuffBars:ResetBarColor(barIndex)
    local profile = GetProfile(self)
    if not profile then
        return
    end

    local cfg = profile.buffBars
    EnsureColorStorage(cfg)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local colors = cfg.colors.perBar
    if colors[classID] and colors[classID][specID] then
        colors[classID][specID][barIndex] = nil
    end

    Util.Log("BuffBars", "ResetBarColor", { barIndex = barIndex })

    -- Refresh bars to apply default color
    self:ResetStyledMarkers()
    self:ScheduleLayoutUpdate()
end

--- Returns color for bar at index (wrapper for Options UI).
---@param barIndex number
---@return number r, number g, number b
function BuffBars:GetBarColor(barIndex)
    local profile = GetProfile(self)
    local cfg = profile and profile.buffBars
    local color = GetBarColor(barIndex, cfg)
    return color.r, color.g, color.b
end

--- Checks if bar at index has a custom color set.
---@param barIndex number
---@return boolean
function BuffBars:HasCustomBarColor(barIndex)
    local profile = GetProfile(self)
    local cfg = profile and profile.buffBars
    if not cfg or not cfg.colors or not cfg.colors.perBar then
        return false
    end

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return false
    end

    local colors = cfg.colors.perBar
    return colors[classID] and colors[classID][specID] and colors[classID][specID][barIndex] ~= nil
end

--- Returns all available palette names.
---@return table<string, string>
function BuffBars:GetPaletteNames()
    local names = {}
    for name in pairs(PALETTES) do
        names[name] = name
    end
    return names
end

--- Sets the selected palette and optionally applies it to all bars.
---@param paletteName string|nil
---@param applyToAllBars boolean
function BuffBars:SetSelectedPalette(paletteName, applyToAllBars)
    local profile = GetProfile(self)
    if not profile then
        return
    end

    local cfg = profile.buffBars
    EnsureColorStorage(cfg)
    cfg.colors.selectedPalette = paletteName

    if applyToAllBars then
        local classID, specID = GetCurrentClassSpec()
        if classID and specID then
            local colors = cfg.colors.perBar
            if colors[classID] and colors[classID][specID] then
                colors[classID][specID] = {}
            end
        end
    end

    Util.Log("BuffBars", "SetSelectedPalette", { palette = paletteName, applyToAll = applyToAllBars })

    self:ResetStyledMarkers()
    self:ScheduleLayoutUpdate()
end

--- Gets the currently selected palette name.
---@return string|nil
function BuffBars:GetSelectedPalette()
    local profile = GetProfile(self)
    if not profile then
        return nil
    end

    local cfg = profile.buffBars
    EnsureColorStorage(cfg)
    return cfg.colors.selectedPalette
end

function BuffBars:OnUnitAura(_, unit)
    if unit == "player" then
        self:ScheduleRescan()
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function BuffBars:OnEnable()
    ECMFrame.AddMixin(self, "BuffBars")

    -- Register events with dedicated handlers
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")

    -- Hook the viewer and edit mode after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookViewer()
        self:HookEditMode()
        self:UpdateLayout()
    end)

    Util.Log("BuffBars", "OnEnable - module enabled")
end

function BuffBars:OnDisable()
    self:UnregisterAllEvents()
    Util.Log("BuffBars", "Disabled")
end
