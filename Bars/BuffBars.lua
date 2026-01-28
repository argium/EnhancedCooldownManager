-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util
local BarHelpers = EnhancedCooldownManager.BarHelpers
local PositionMixin = ns.Mixins.PositionMixin

---@class Frame
---@class StatusBar : Frame

---@class ECM_BuffBarChild : Frame
---@field Bar StatusBar
---@field Icon Frame
---@field IconFrame Frame
---@field IconButton Frame
---@field __ecmAnchorHooked boolean|nil
---@field __ecmStyled boolean|nil

---@class ECM_BuffBarViewer : Frame
---@field _layoutCache table|nil
---@field ApplyLayout fun(self: ECM_BuffBarViewer, params: table): boolean
---@field InvalidateLayout fun(self: ECM_BuffBarViewer): nil
---@field __ecmHooked boolean|nil
---@field __ecmLayoutRunning boolean|nil

---@class ECM_BuffBarsModule
local BuffBars = EnhancedCooldownManager:NewModule("BuffBars", "AceEvent-3.0")
EnhancedCooldownManager.BuffBars = BuffBars

local WHITE8 = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_BAR_COLOR = { 0.90, 0.90, 0.90 }

local PALETTES = {
    ["Default"] = {
        { 0.90, 0.90, 0.90 },
    },
    ["Rainbow"] = {
        { 0.95, 0.27, 0.27 }, -- Red
        { 0.95, 0.65, 0.27 }, -- Orange
        { 0.95, 0.95, 0.27 }, -- Yellow
        { 0.27, 0.95, 0.27 }, -- Green
        { 0.27, 0.65, 0.95 }, -- Blue
        { 0.58, 0.27, 0.95 }, -- Purple
        { 0.95, 0.27, 0.65 }, -- Pink
    },
    ["Warm"] = {
        { 0.95, 0.35, 0.25 }, -- Red-Orange
        { 0.95, 0.55, 0.25 }, -- Orange
        { 0.95, 0.75, 0.30 }, -- Golden
        { 0.90, 0.60, 0.40 }, -- Tan
    },
    ["Cool"] = {
        { 0.25, 0.70, 0.95 }, -- Sky Blue
        { 0.30, 0.85, 0.85 }, -- Cyan
        { 0.35, 0.65, 0.90 }, -- Ocean Blue
        { 0.40, 0.55, 0.85 }, -- Deep Blue
    },
    ["Pastel"] = {
        { 0.95, 0.75, 0.80 }, -- Pink
        { 0.80, 0.85, 0.95 }, -- Light Blue
        { 0.85, 0.95, 0.80 }, -- Light Green
        { 0.95, 0.90, 0.75 }, -- Cream
        { 0.90, 0.80, 0.95 }, -- Lavender
    },
    ["Neon"] = {
        { 1.00, 0.10, 0.50 }, -- Hot Pink
        { 0.10, 1.00, 0.90 }, -- Cyan
        { 0.90, 1.00, 0.10 }, -- Lime
        { 1.00, 0.40, 0.10 }, -- Orange
        { 0.50, 0.10, 1.00 }, -- Purple
    },
    ["Earth"] = {
        { 0.55, 0.45, 0.35 }, -- Brown
        { 0.40, 0.60, 0.35 }, -- Moss Green
        { 0.65, 0.55, 0.40 }, -- Sand
        { 0.50, 0.40, 0.30 }, -- Dark Earth
    },
}

--- Returns current class ID and spec ID.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    return classID, specID
end

--- Ensures nested tables exist for buffBarColors storage.
---@param profile table
local function EnsureColorStorage(profile)
    if not profile.buffBarColors then
        profile.buffBarColors = {
            colors = {},
            cache = {},
            defaultColor = DEFAULT_BAR_COLOR,
            selectedPalette = nil,
        }
    end
    if not profile.buffBarColors.colors then
        profile.buffBarColors.colors = {}
    end
    if not profile.buffBarColors.cache then
        profile.buffBarColors.cache = {}
    end
    if not profile.buffBarColors.defaultColor then
        profile.buffBarColors.defaultColor = DEFAULT_BAR_COLOR
    end
    if profile.buffBarColors.selectedPalette == nil then
        profile.buffBarColors.selectedPalette = nil
    end
end

--- Gets color from palette for the given bar index.
---@param barIndex number
---@param paletteName string
---@return number r, number g, number b
local function GetPaletteColor(barIndex, paletteName)
    local palette = PALETTES[paletteName]
    if not palette or #palette == 0 then
        return DEFAULT_BAR_COLOR[1], DEFAULT_BAR_COLOR[2], DEFAULT_BAR_COLOR[3]
    end

    local colorIndex = ((barIndex - 1) % #palette) + 1
    local color = palette[colorIndex]
    return color[1], color[2], color[3]
end

--- Returns color for bar at index for current class/spec, or palette/default if not set.
---@param barIndex number 1-based index in layout order
---@param profile table
---@return number r, number g, number b
local function GetBarColor(barIndex, profile)
    if not profile then
        return DEFAULT_BAR_COLOR[1], DEFAULT_BAR_COLOR[2], DEFAULT_BAR_COLOR[3]
    end

    EnsureColorStorage(profile)

    local classID, specID = GetCurrentClassSpec()
    local colors = profile.buffBarColors.colors
    if classID and specID and colors[classID] and colors[classID][specID] then
        local c = colors[classID][specID][barIndex]
        if c then
            return c[1], c[2], c[3]
        end
    end

    local selectedPalette = profile.buffBarColors.selectedPalette
    if selectedPalette and PALETTES[selectedPalette] then
        return GetPaletteColor(barIndex, selectedPalette)
    end

    local dc = profile.buffBarColors.defaultColor or DEFAULT_BAR_COLOR
    return dc[1], dc[2], dc[3]
end

--- Updates bar cache with current bar metadata for Options UI.
---@param barIndex number
---@param spellName string|nil
---@param profile table
local function UpdateBarCache(barIndex, spellName, profile)
    if not profile or not barIndex or barIndex < 1 then
        return
    end

    EnsureColorStorage(profile)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local cache = profile.buffBarColors.cache
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
    if bar.SetStatusBarColor and barIndex then
        local r, g, b = GetBarColor(barIndex, profile)
        bar:SetStatusBarColor(r, g, b, 1.0)
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
        UpdateBarCache(barIndex, spellName, profile)
    end

    local bgColor = BarHelpers.GetBgColor(nil, profile)
    local barBG = GetBuffBarBackground(bar)
    if barBG then
        barBG:SetTexture(WHITE8)
        barBG:SetVertexColor(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] or 1)
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
    local cfg = profile.buffBars or {}
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
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if profile and profile.buffBarColors and profile.buffBarColors.cache then
        local classID, specID = GetCurrentClassSpec()
        if classID and specID then
            local cache = profile.buffBarColors.cache
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
            self:UpdateLayout()
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
        self:UpdateLayout()
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if self._layoutRunning then
            return
        end
        self:ScheduleLayoutUpdate()
    end)

    -- Register for UNIT_AURA to catch buff changes
    if not self._auraEventFrame then
        self._auraEventFrame = CreateFrame("Frame")
        self._auraEventFrame:RegisterEvent("UNIT_AURA")
        self._auraEventFrame:SetScript("OnEvent", function(_, event, unit)
            if unit == "player" then
                self:ScheduleRescan()
            end
        end)
    end

    -- Hook edit mode transitions
    self:HookEditMode()

    Util.Log("BuffBars", "Hooked BuffBarCooldownViewer")
end

--- Schedules a throttled layout update.
function BuffBars:ScheduleLayoutUpdate()
    if self._layoutPending then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    self._layoutPending = true

    assert(profile and profile.updateFrequency, "ECM: profile.updateFrequency missing")

    C_Timer.After(profile.updateFrequency, function()
        self._layoutPending = nil
        local viewer = self:GetViewer()
        if viewer and viewer:IsShown() then
            self:UpdateLayout()
        end
    end)
end

--- Schedules a throttled rescan for new/changed bars.
function BuffBars:ScheduleRescan()
    if self._rescanPending then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
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

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile

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

--- Updates layout: positioning, sizing, anchoring, appearance.
function BuffBars:UpdateLayout()
    local viewer = self:GetViewer()
    if not viewer then
        Util.Log("BuffBars", "UpdateLayout skipped - no viewer")
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile.buffBars or {}
    self._viewerLayoutCache = self._viewerLayoutCache or {}

    local params, anchorMode = PositionMixin.CalculateBuffBarsLayout(cfg, profile)

    local preservePosition = anchorMode == "independent"
        and self._viewerLayoutCache.lastMode == "chain"

    if preservePosition then
        local preservedX, preservedY = PositionMixin.CaptureCurrentTopOffset(viewer)
        params.offsetX = preservedX
        params.offsetY = preservedY
    end

    PositionMixin.ApplyLayout(viewer, params, self._viewerLayoutCache)

    -- Hook all children for anchor change detection
    for _, child in ipairs({ viewer:GetChildren() }) do
        if child and child.Bar then
            HookChildAnchoring(child, self)
        end
    end

    -- Style visible bars in sorted order so bar indices match display order
    local visibleChildren = GetSortedVisibleChildren(viewer)

    for barIndex, entry in ipairs(visibleChildren) do
        ApplyCooldownBarStyle(entry.frame, profile, barIndex)
    end

    self:LayoutBars()

    Util.Log("BuffBars", "UpdateLayout complete", {
        anchorMode = anchorMode,
        width = params.width or nil,
        offsetY = params.offsetY,
        visibleCount = #visibleChildren,
    })
end

--- Returns cached bars for current class/spec for Options UI.
---@return table<number, ECM_BarCacheEntry> bars Indexed by bar position
function BuffBars:GetCachedBars()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return {}
    end

    EnsureColorStorage(profile)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return {}
    end

    local cache = profile.buffBarColors.cache
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
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return
    end

    EnsureColorStorage(profile)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local colors = profile.buffBarColors.colors
    colors[classID] = colors[classID] or {}
    colors[classID][specID] = colors[classID][specID] or {}
    colors[classID][specID][barIndex] = { r, g, b }

    Util.Log("BuffBars", "SetBarColor", { barIndex = barIndex, r = r, g = g, b = b })

    self:ResetStyledMarkers()
    self:ScheduleLayoutUpdate()
end

--- Resets color for bar at index to default.
---@param barIndex number
function BuffBars:ResetBarColor(barIndex)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return
    end

    EnsureColorStorage(profile)

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return
    end

    local colors = profile.buffBarColors.colors
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
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    return GetBarColor(barIndex, profile)
end

--- Checks if bar at index has a custom color set.
---@param barIndex number
---@return boolean
function BuffBars:HasCustomBarColor(barIndex)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile or not profile.buffBarColors or not profile.buffBarColors.colors then
        return false
    end

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return false
    end

    local colors = profile.buffBarColors.colors
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
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return
    end

    EnsureColorStorage(profile)
    profile.buffBarColors.selectedPalette = paletteName

    if applyToAllBars then
        local classID, specID = GetCurrentClassSpec()
        if classID and specID then
            local colors = profile.buffBarColors.colors
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
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return nil
    end

    EnsureColorStorage(profile)
    return profile.buffBarColors.selectedPalette
end

function BuffBars:OnEnable()
    Util.Log("BuffBars", "OnEnable - module starting")

    C_Timer.After(0.1, function()
        self:HookViewer()
        self:HookEditMode()
        self:UpdateLayout()
    end)
end

function BuffBars:OnDisable()
    Util.Log("BuffBars", "OnDisable - module stopping")
    if self._auraEventFrame then
        self._auraEventFrame:UnregisterAllEvents()
    end
end
