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

local GetSortedChildren
local GetChildTextureFileID

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
    if not colors.textureMap then
        colors.textureMap = {}
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

--- Returns normalized spell name for a buff bar child, or nil if unavailable.
---@param child ECM_BuffBarChild|nil
---@return string|nil
local function GetChildSpellName(child)
    local bar = child and child.Bar
    if not (bar and bar.Name and bar.Name.GetText) then
        return nil
    end

    local text = bar.Name:GetText()
    if type(canaccessvalue) == "function" and not canaccessvalue(text) then
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

--- Returns the color lookup key for a bar: spell name if known, or textureFileID fallback.
--- When Blizzard marks spell names as secret (via `canaccessvalue`), the icon texture file ID
--- serves as a stable identifier for color customization. textureFileID is a number, creating
--- natural key-type separation from string spell names in perSpell storage.
---@param spellName string|nil
---@param textureFileID number|nil
---@return string|number|nil
local function GetColorKey(spellName, textureFileID)
    return spellName or textureFileID
end

--- Returns color for spell with name spellName for current class/spec, or nil if not set.
---@param spellName string|nil
---@param cfg table|nil
---@return ECM_Color|nil
local function GetSpellColor(spellName, cfg)
    if not cfg or not cfg.colors.perSpell then
        Util.DebugAssert(false, "GetSpellColor called with nil cfg or missing perSpell colors")
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

--- Builds a cache snapshot for current class/spec from current viewer children.
---@param viewer Frame
---@param cfg table|nil
---@return table|nil
local function BuildBarCacheSnapshot(viewer, cfg)
    if not cfg then
        return nil
    end

    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then
        return nil
    end

    local children = GetSortedChildren(viewer, false)
    local nextCache = {}
    local validCount = 0

    -- Store all entries, including those with nil spellName (secret/unavailable names).
    -- textureFileIDs are stored in a separate table (not in cache entries) to prevent
    -- taint propagation from secret spell names to texture IDs.
    local nextTextures = {}
    for index, entry in ipairs(children) do
        local spellName = GetChildSpellName(entry.frame)
        nextCache[index] = {
            spellName = spellName,  -- nil is allowed
            lastSeen = GetTime(),
        }
        nextTextures[index] = GetChildTextureFileID(entry.frame)
        if spellName then
            validCount = validCount + 1
        end
    end

    Util.Log("BuffBars", "BuildBarCacheSnapshot", {
        totalChildren = #children,
        validCount = validCount,
    })

    return {
        classID = classID,
        specID = specID,
        cache = nextCache,
        textures = nextTextures,
        validCount = validCount,
    }
end

--- Rebuilds the bar cache for the current class/spec from current viewer children.
--- Scans both shown and hidden bars. If no valid bars are found, keeps existing cache.
---@param viewer Frame
---@param moduleConfig table
---@return boolean updated
local function RefreshBarCache(viewer, moduleConfig)
    local snapshot = BuildBarCacheSnapshot(viewer, moduleConfig)
    if not snapshot then
        return false
    end

    if not next(snapshot.cache) then
        Util.Log("BuffBars", "RefreshBarCache", {
            message = "No children at all; preserving existing cache",
            classID = snapshot.classID,
            specID = snapshot.specID,
        })
        return false
    end

    local cache = moduleConfig.colors.cache
    cache[snapshot.classID] = cache[snapshot.classID] or {}

    local textureMap = moduleConfig.colors.textureMap
    textureMap[snapshot.classID] = textureMap[snapshot.classID] or {}

    -- Texture file ID resolution and color migration:
    -- textureFileIDs are stored in a separate table (textureMap) from cache entries
    -- to prevent taint propagation from secret spell names to texture IDs.
    -- 1. Build textureFileID → spellName mapping from old textureMap + old cache
    -- 2. Resolve nil spellNames in new cache via textureFileID lookup
    -- 3. Migrate perSpell colors from textureFileID (number) key to resolved spell name
    local oldCache = cache[snapshot.classID][snapshot.specID]
    local oldTextures = textureMap[snapshot.classID] and textureMap[snapshot.classID][snapshot.specID]
    if oldCache and oldTextures then
        local texIdToName = {}
        for index, entry in pairs(oldCache) do
            local texId = oldTextures[index]
            if entry.spellName and texId then
                texIdToName[texId] = entry.spellName
            end
        end
        Util.Log("BuffBars", "RefreshBarCache", {
            message = "Built textureFileID to spellName mapping from old cache",
            mappingCount = #texIdToName,
            map = texIdToName,
        })

        local perSpell = moduleConfig.colors.perSpell
        local classSpells = perSpell and perSpell[snapshot.classID]
        local specSpells = classSpells and classSpells[snapshot.specID]

        for index, newEntry in pairs(snapshot.cache) do
            local newTexId = snapshot.textures[index]
            if not newEntry.spellName and newTexId then
                if issecrettable(texIdToName) or issecretvalue(newTexId) then
                    Util.Log("BuffBars", "RefreshBarCache", {
                        message = "Cannot resolve spell name due to secret value",
                        textureFileID = newTexId,
                    })
                    return false
                end
                local resolvedName = texIdToName[newTexId]
                if resolvedName then
                    Util.Log("BuffBars", "RefreshBarCache", {
                        message = "Resolved spell name from texture ID",
                        resolvedName = resolvedName,
                        textureFileID = newTexId,
                    })
                    newEntry.spellName = resolvedName
                end
            end

            -- Migrate colors from textureFileID key to real spell name
            if specSpells and newEntry.spellName and newTexId then
                if specSpells[newTexId] and specSpells[newEntry.spellName] == nil then
                    Util.Log("BuffBars", "RefreshBarCache", {
                        message = "Migrating color from texture ID to resolved spell name",
                        spellName = newEntry.spellName,
                        textureFileID = newTexId,
                    })
                    specSpells[newEntry.spellName] = specSpells[newTexId]
                end
                specSpells[newTexId] = nil
            end
        end
    end

    Util.Log("BuffBars", "RefreshBarCache", {
        message = "Updating bar cache with new snapshot",
        current = cache[snapshot.classID] and cache[snapshot.classID][snapshot.specID] or "nil",
        new = snapshot.cache,
    })

    cache[snapshot.classID][snapshot.specID] = snapshot.cache
    textureMap[snapshot.classID][snapshot.specID] = snapshot.textures
    return true
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
GetChildTextureFileID = function(child)
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
GetSortedChildren = function(viewer, onlyVisible)
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

--- Enforces visibility settings for icon, spell name, and duration.
--- This must be called frequently because Blizzard resets these when cooldowns update.
---@param child ECM_BuffBarChild
---@param moduleConfig table
local function HidePandemicGlows(child)
    if not child then
        return
    end

    -- Hide() doesn't work because Blizzard keeps showing it again
    if child.DebuffBorder then
        child.DebuffBorder:SetAlpha(0)
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
        HidePandemicGlows(child)
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
    local tex = BarHelpers.GetTexture(texKey)
    bar:SetStatusBarTexture(tex)

    -- Resolve the color lookup key: spell name if available, otherwise the icon
    -- texture file ID as a stable fallback for bars with secret/unavailable names.
    if bar.SetStatusBarColor then
        local spellName = GetChildSpellName(child)
        local colorKey = GetColorKey(spellName, GetChildTextureFileID(child))
        local color = GetSpellColor(colorKey, moduleConfig) or moduleConfig.colors.defaultColor or C.BUFFBARS_DEFAULT_COLOR
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

    -- Refresh cache independently from visibility so options can discover bars in hidden states.
    RefreshBarCache(viewer, cfg)

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

--- Public helper for options and hooks to rebuild bar metadata cache.
function BuffBars:RefreshBarCache()
    local viewer = self.InnerFrame
    local cfg = self.ModuleConfig
    if not (viewer and cfg and cfg.colors and cfg.colors.cache) then
        return false
    end

    return RefreshBarCache(viewer, cfg)
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

--- Returns cached texture file IDs for current class/spec for Options UI.
--- Stored separately from cache entries to avoid taint propagation.
---@return table<number, number> textures Indexed by bar position, values are texture file IDs
function BuffBars:GetCachedTextures()
    local cfg, classID, specID = GetColorContext(self)
    if not cfg or not classID or not specID then
        return {}
    end

    local textureMap = cfg.colors.textureMap
    if textureMap and textureMap[classID] and textureMap[classID][specID] then
        return textureMap[classID][specID]
    end

    return {}
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
