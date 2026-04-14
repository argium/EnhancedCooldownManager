-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local BarMixin = ns.BarMixin
local ExtraIcons = ns.Addon:NewModule("ExtraIcons")
ns.Addon.ExtraIcons = ExtraIcons

---@class ECM_ExtraIconsModule : ECM_FrameProto

---@class ECM_IconData
---@field itemId number|nil Item ID.
---@field spellId number|nil Spell ID (for spell-kind entries).
---@field texture string|number Icon texture.
---@field slotId number|nil Inventory slot ID (equipSlot only).

---@class ECM_ExtraIcon : Button
---@field slotId number|nil Inventory slot ID this icon represents (equipSlot only).
---@field itemId number|nil Item ID this icon represents (bag items only).
---@field spellId number|nil Spell ID this icon represents (spell entries only).
---@field Icon Texture The icon texture.
---@field Cooldown Cooldown The cooldown overlay frame.

local BUILTIN_STACKS = ns.Constants.BUILTIN_STACKS
local SUPPRESS_IN_RATED_PVP = {
    combatPotions = true,
    healthPotions = true,
}

--- Viewer registry mapping viewer keys to their Blizzard frame globals.
local VIEWER_REGISTRY = {
    utility = { blizzFrameKey = "UtilityCooldownViewer" },
    main    = { blizzFrameKey = "EssentialCooldownViewer" },
}

local VIEWER_ORDER = { "main", "utility" }

local function cacheOriginalPoint(viewerState, blizzFrame)
    if viewerState.originalPoint or not blizzFrame then
        return
    end

    local point, relativeTo, relativePoint, x, y = blizzFrame:GetPoint()
    viewerState.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
end

local function applyViewerPoint(viewerState, blizzFrame, offsetX)
    local point = viewerState and viewerState.originalPoint
    if not point or not blizzFrame then
        return
    end

    blizzFrame:ClearAllPoints()
    blizzFrame:SetPoint(point[1], point[2], point[3], point[4] + (offsetX or 0), point[5])
end

--------------------------------------------------------------------------------
-- Resolver Functions
--------------------------------------------------------------------------------

local function isRatedPvPMap()
    local pvp = C_PvP
    return pvp and type(pvp.IsRatedMap) == "function" and pvp.IsRatedMap() or false
end

--- Checks if an equipment slot has an on-use effect.
---@param slotId number Inventory slot ID.
---@return ECM_IconData|nil iconData Icon data if on-use, nil otherwise.
local function getEquipSlotData(slotId)
    local itemId = GetInventoryItemID("player", slotId)
    if not itemId then
        return nil
    end

    local _, spellId = C_Item.GetItemSpell(itemId)
    if not spellId then
        return nil
    end

    local texture = GetInventoryItemTexture("player", slotId)
    if not texture then
        return nil
    end

    return {
        itemId = itemId,
        texture = texture,
        slotId = slotId,
    }
end

--- Returns the first item from a priority list that exists in the player's bags.
---@param ids { itemID: number, quality: number|nil }[] Array of priority entries.
---@return ECM_IconData|nil iconData Icon data if found, nil otherwise.
local function getBestConsumable(ids)
    for _, entry in ipairs(ids) do
        local itemId = entry.itemID or entry.itemId
        if itemId and C_Item.GetItemCount(itemId) > 0 then
            local texture = C_Item.GetItemIconByID(itemId)
            if texture then
                return {
                    itemId = itemId,
                    texture = texture,
                }
            end
        end
    end
    return nil
end

--- Returns the first known spell from an ID list.
---@param ids { spellId: number }[]|number[] Array of spell entries or raw IDs.
---@return ECM_IconData|nil iconData Icon data if found, nil otherwise.
local function isKnownSpell(spellId)
    if not spellId then
        return false
    end

    return C_SpellBook.IsSpellKnown(spellId)
end

local function getSpellData(ids)
    for _, entry in ipairs(ids) do
        local spellId = type(entry) == "table" and entry.spellId or entry
        if isKnownSpell(spellId) then
            local texture = C_Spell.GetSpellTexture(spellId)
            if texture then
                return {
                    spellId = spellId,
                    texture = texture,
                }
            end
        end
    end
    return nil
end

--- Resolves a single config entry to displayable icon data.
---@param entry table A config entry with stackKey or kind+ids/slotId.
---@return ECM_IconData|nil iconData Resolved icon data, or nil if unavailable.
local function resolveEntry(entry)
    local kind, slotId, ids

    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then
            return nil
        end
        if SUPPRESS_IN_RATED_PVP[entry.stackKey] and isRatedPvPMap() then
            return nil
        end
        kind = stack.kind
        slotId = stack.slotId
        ids = stack.ids
    else
        kind = entry.kind
        slotId = entry.slotId
        ids = entry.ids
    end

    if kind == "equipSlot" then
        return getEquipSlotData(slotId)
    elseif kind == "item" then
        return ids and getBestConsumable(ids)
    elseif kind == "spell" then
        return ids and getSpellData(ids)
    end
    return nil
end

--- Resolves all entries for a viewer into an ordered array of icon data.
---@param entries table[] Config entries for one viewer.
---@return ECM_IconData[] items Array of resolved icon data (skipping nil results).
local _resolvedItems = {}

local function resolveViewerEntries(entries)
    wipe(_resolvedItems)
    for _, entry in ipairs(entries) do
        local data = not entry.disabled and resolveEntry(entry) or nil
        if data then
            _resolvedItems[#_resolvedItems + 1] = data
        end
    end
    return _resolvedItems
end

--------------------------------------------------------------------------------
-- Icon Creation and Cooldown
--------------------------------------------------------------------------------

--- Creates a single extra icon frame styled like cooldown viewer icons.
---@param parent Frame Parent frame to attach to.
---@param size number Icon size in pixels.
---@return ECM_ExtraIcon icon The created icon frame.
local function createExtraIcon(parent, size)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(size, size)

    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetPoint("CENTER")
    icon.Icon:SetSize(size, size)

    icon.Mask = icon:CreateMaskTexture()
    icon.Mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
    icon.Mask:SetPoint("CENTER")
    icon.Mask:SetSize(size, size)
    icon.Icon:AddMaskTexture(icon.Mask)

    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints()
    icon.Cooldown:SetDrawEdge(true)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 0, 0, 0, 0.2)
    icon.Cooldown:SetEdgeTexture([[Interface\Cooldown\UI-HUD-ActionBar-SecondaryCooldown]])

    icon.Border = icon:CreateTexture(nil, "OVERLAY")
    icon.Border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
    icon.Border:SetPoint("CENTER")
    icon.Border:SetSize(size * ns.Constants.EXTRA_ICON_BORDER_SCALE, size * ns.Constants.EXTRA_ICON_BORDER_SCALE)

    icon.Shadow = icon:CreateTexture(nil, "OVERLAY")
    icon.Shadow:SetAtlas("UI-CooldownManager-OORshadow")
    icon.Shadow:SetAllPoints()
    icon.Shadow:Hide()

    return icon
end

--- Updates the cooldown display on an extra icon.
---@param icon ECM_ExtraIcon The icon to update.
local function updateIconCooldown(icon)
    if icon.spellId then
        local cdInfo = C_Spell.GetSpellCooldown(icon.spellId)
        if cdInfo and cdInfo.isOnGCD then
            icon.Cooldown:SetCooldown(0, 0)
            return
        end
        -- Charge spells: show per-charge timer so the icon appears ready while
        -- charges remain.  maxCharges must be >1; single-charge spells report
        -- zero-span from GetSpellChargeDuration.
        local chargesInfo = C_Spell.GetSpellCharges(icon.spellId)
        local isCharge = chargesInfo and chargesInfo.maxCharges and chargesInfo.maxCharges > 1
        local durObj = isCharge
            and C_Spell.GetSpellChargeDuration(icon.spellId)
            or  C_Spell.GetSpellCooldownDuration(icon.spellId)
        if durObj then
            icon.Cooldown:SetCooldown(0, 0)
            icon.Cooldown:SetCooldownFromDurationObject(durObj)
        else
            icon.Cooldown:Clear()
        end
    elseif icon.slotId then
        local start, duration, enable = GetInventoryItemCooldown("player", icon.slotId)
        if enable == 1 and duration > 0 then
            icon.Cooldown:SetCooldown(start, duration)
        else
            icon.Cooldown:Clear()
        end
    elseif icon.itemId then
        local start, duration, enable = C_Item.GetItemCooldown(icon.itemId)
        if enable and duration > 0 then
            icon.Cooldown:SetCooldown(start, duration)
        else
            icon.Cooldown:Clear()
        end
    end
end

--- Gets cooldown number font info from a Blizzard cooldown viewer icon.
--- Caches the result on the viewer to avoid per-layout child scans.
---@param viewer Frame
---@return string|nil fontPath, number|nil fontSize, string|nil fontFlags
local function getSiblingCooldownNumberFont(viewer)
    local cached = viewer.__ecmCDFont
    if cached then
        return cached[1], cached[2], cached[3]
    end

    for _, child in ipairs({ viewer:GetChildren() }) do
        local cooldown = child.Cooldown
        if cooldown and cooldown.GetRegions then
            local region = cooldown:GetRegions()
            if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetFont then
                local fontPath, fontSize, fontFlags = region:GetFont()
                if fontPath and fontSize then
                    viewer.__ecmCDFont = { fontPath, fontSize, fontFlags }
                    return fontPath, fontSize, fontFlags
                end
            end
        end
    end
end

--- Applies cooldown number font settings to one icon.
---@param icon ECM_ExtraIcon
---@param fontPath string
---@param fontSize number
---@param fontFlags string|nil
local function applyCooldownNumberFont(icon, fontPath, fontSize, fontFlags)
    local region = icon.Cooldown:GetRegions()
    if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetFont then
        region:SetFont(fontPath, fontSize, fontFlags)
    end
end

--- Ensures the viewer's icon pool has at least `needed` icons.
---@param viewerState table Per-viewer state with .container and .iconPool.
---@param needed number Required pool size.
local function ensurePoolSize(viewerState, needed)
    local pool = viewerState.iconPool
    local existing = #pool
    if needed <= existing then
        return
    end
    local size = ns.Constants.DEFAULT_EXTRA_ICON_SIZE
    for i = existing + 1, needed do
        pool[i] = createExtraIcon(viewerState.container, size)
    end
end

--------------------------------------------------------------------------------
-- Module Methods
--------------------------------------------------------------------------------

--- Creates the invisible parent frame and per-viewer containers.
---@return Frame parent The parent frame.
function ExtraIcons:CreateFrame()
    local parent = CreateFrame("Frame", "ECMExtraIcons", UIParent)
    parent:SetFrameStrata("MEDIUM")
    parent:SetSize(1, 1)

    self._viewers = {}
    for viewerKey in pairs(VIEWER_REGISTRY) do
        local container = CreateFrame("Frame", "ECMExtraIcons_" .. viewerKey, parent)
        container:SetFrameStrata("MEDIUM")
        container:SetSize(1, 1)

        local anchorFrame = CreateFrame("Frame", "ECMExtraIcons_" .. viewerKey .. "Anchor", parent)
        anchorFrame:SetFrameStrata("MEDIUM")
        anchorFrame:SetSize(1, 1)
        anchorFrame:Hide()

        self._viewers[viewerKey] = {
            anchorFrame = anchorFrame,
            container = container,
            iconPool = {},
            originalPoint = nil,
            hooked = false,
        }
    end

    return parent
end

--- Override ShouldShow to check module enabled state and at least one viewer visible.
---@return boolean shouldShow Whether we should attempt layout.
function ExtraIcons:ShouldShow()
    if not BarMixin.FrameProto.ShouldShow(self) then
        return false
    end
    for _, reg in pairs(VIEWER_REGISTRY) do
        local blizzFrame = _G[reg.blizzFrameKey]
        if blizzFrame and blizzFrame:IsShown() then
            return true
        end
    end
    return false
end

--- Updates a viewer's logical anchor frame.
--- The main viewer uses this so chained ECM modules can inherit the combined
--- width of Blizzard icons plus any appended extra icons.
---@param viewerKey string
---@param blizzFrame Frame|nil
---@param rightFrame Frame|nil
function ExtraIcons:_updateViewerAnchor(viewerKey, blizzFrame, rightFrame)
    local vs = self._viewers and self._viewers[viewerKey]
    local anchorFrame = vs and vs.anchorFrame
    if not anchorFrame then
        return
    end

    if not blizzFrame or not blizzFrame:IsShown() then
        anchorFrame:Hide()
        return
    end

    local rightAnchor = rightFrame and rightFrame:IsShown() and rightFrame or blizzFrame

    anchorFrame:ClearAllPoints()
    anchorFrame:SetPoint("LEFT", blizzFrame, "LEFT", 0, 0)
    anchorFrame:SetPoint("RIGHT", rightAnchor, "RIGHT", 0, 0)
    anchorFrame:SetPoint("TOP", blizzFrame, "TOP", 0, 0)
    anchorFrame:SetPoint("BOTTOM", blizzFrame, "BOTTOM", 0, 0)
    anchorFrame:Show()
end

--- Gets the effective chain anchor for the main viewer.
---@return Frame|nil
function ExtraIcons:GetMainViewerAnchor()
    local vs = self._viewers and self._viewers.main
    local anchorFrame = vs and vs.anchorFrame
    if anchorFrame and anchorFrame:IsShown() then
        return anchorFrame
    end

    return _G[VIEWER_REGISTRY.main.blizzFrameKey]
end

--- Lays out icons for a single viewer.
---@param viewerKey string The viewer key ("utility" or "main").
---@param entries table[] The config entries for this viewer.
---@param isEditing boolean Whether edit mode is active.
---@return boolean changed Whether any icons were placed.
function ExtraIcons:_updateSingleViewer(viewerKey, entries, isEditing)
    local reg = VIEWER_REGISTRY[viewerKey]
    local blizzFrame = _G[reg.blizzFrameKey]
    local vs = self._viewers[viewerKey]
    if not vs then
        return false
    end
    local container = vs.container
    cacheOriginalPoint(vs, blizzFrame)

    -- Resolve entries to displayable items
    local items
    if not blizzFrame or not blizzFrame:IsShown() or isEditing or #entries == 0 then
        items = {}
    else
        items = resolveViewerEntries(entries)
    end

    if #items == 0 then
        -- Restore viewer position and hide container
        applyViewerPoint(vs, blizzFrame)
        if isEditing then
            vs.originalPoint = nil
        end
        container:Hide()
        if viewerKey == "main" then
            self:_updateViewerAnchor(viewerKey, blizzFrame, nil)
        end
        return false
    end

    -- Hide all existing pool icons
    for _, icon in ipairs(vs.iconPool) do
        icon:Hide()
    end

    -- Ensure pool is large enough
    ensurePoolSize(vs, #items)

    local siblingFontPath, siblingFontSize, siblingFontFlags = getSiblingCooldownNumberFont(blizzFrame)
    local iconSize = ns.Constants.DEFAULT_EXTRA_ICON_SIZE
    local spacing = 0
    local viewerScale = 1.0
    local lastActiveItemFrame = nil
    local numActiveViewerIcons = 0

    if blizzFrame:IsShown() then
        viewerScale = blizzFrame.iconScale or 1.0
        spacing = blizzFrame.childXPadding or 0

        if blizzFrame.GetItemFrames then
            for _, itemFrame in ipairs(blizzFrame:GetItemFrames()) do
                if itemFrame.isActive then
                    iconSize = itemFrame:GetWidth() or iconSize
                    lastActiveItemFrame = itemFrame
                    numActiveViewerIcons = numActiveViewerIcons + 1
                end
            end
        else
            for _, child in ipairs({ blizzFrame:GetChildren() }) do
                if child and child:IsShown() and child.GetSpellID then
                    iconSize = child:GetWidth() or iconSize
                    break
                end
            end
        end
    end

    container:SetScale(viewerScale)

    local numItems = #items
    local totalWidth = numItems * iconSize + (numItems - 1) * spacing
    container:SetSize(totalWidth, iconSize)

    if not vs.originalPoint then
        local point, relativeTo, relativePoint, x, y = blizzFrame:GetPoint()
        vs.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end

    -- Shift the Blizzard viewer left to keep the combined group centred
    local activeContentWidth = numActiveViewerIcons * iconSize + math.max(0, numActiveViewerIcons - 1) * spacing
    local viewerWidth = numActiveViewerIcons > 0 and blizzFrame:GetWidth() or 0
    local viewerOffsetX = (viewerWidth - activeContentWidth - spacing - totalWidth * viewerScale) / 2
    applyViewerPoint(vs, blizzFrame, viewerOffsetX)

    -- Position and configure each icon
    local borderScale = ns.Constants.EXTRA_ICON_BORDER_SCALE
    local xOffset = 0
    for i, iconData in ipairs(items) do
        local icon = vs.iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * borderScale, iconSize * borderScale)
        icon.slotId = iconData.slotId
        icon.itemId = iconData.itemId
        icon.spellId = iconData.spellId

        icon.Icon:SetTexture(iconData.texture)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", container, "LEFT", xOffset, 0)
        icon:Show()

        updateIconCooldown(icon)

        if siblingFontPath and siblingFontSize then
            applyCooldownNumberFont(icon, siblingFontPath, siblingFontSize, siblingFontFlags)
        end

        xOffset = xOffset + iconSize + spacing
    end

    container:ClearAllPoints()
    container:SetPoint("LEFT", lastActiveItemFrame or blizzFrame, "RIGHT", spacing, 0)
    container:Show()

    if viewerKey == "main" then
        self:_updateViewerAnchor(viewerKey, blizzFrame, container)
    end

    return true
end

--- Override UpdateLayout to position icons for all viewers.
---@param why string|nil Reason for layout update.
---@return boolean success Whether any viewer had icons placed.
function ExtraIcons:UpdateLayout(why)
    if not self.InnerFrame or not self._viewers then
        return false
    end

    local shouldShow = self:ShouldShow()
    local moduleConfig = self:GetModuleConfig()
    local isEditing = self._isEditModeActive
    if isEditing == nil then
        local editModeManager = _G.EditModeManagerFrame
        isEditing = editModeManager and editModeManager:IsShown() or false
    end

    -- When hidden, nil-out viewers so every _updateSingleViewer call gets
    -- empty entries, which restores Blizzard viewer positions and hides
    -- the extra-icon containers.
    local viewers = shouldShow and moduleConfig and moduleConfig.viewers
    local anyPlaced = false

    for i = 1, #VIEWER_ORDER do
        local viewerKey = VIEWER_ORDER[i]
        local entries = viewers and viewers[viewerKey] or {}
        local changed = self:_updateSingleViewer(viewerKey, entries, isEditing)
        if changed then
            anyPlaced = true
        end
    end

    -- Manage InnerFrame visibility (not handled by ApplyFramePosition since
    -- ExtraIcons overrides UpdateLayout without calling the base).
    if shouldShow then
        if not self.InnerFrame:IsShown() then
            self.InnerFrame:Show()
        end
    else
        self.InnerFrame:Hide()
    end

    if anyPlaced then
        ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")")
        self:ThrottledRefresh("UpdateLayout")
    end

    return anyPlaced
end

--- Override Refresh to update cooldown states on all viewers.
function ExtraIcons:Refresh(why, force)
    if not BarMixin.FrameProto.Refresh(self, why, force) then
        return false
    end

    if not self._viewers then
        return false
    end

    local anyRefreshed = false
    for _, vs in pairs(self._viewers) do
        local container = vs.container
        if container and container:IsShown() then
            for _, icon in ipairs(vs.iconPool) do
                if icon:IsShown() and (icon.slotId or icon.itemId or icon.spellId) then
                    updateIconCooldown(icon)
                end
            end
            anyRefreshed = true
        end
    end

    if anyRefreshed then
        ns.Log(self.Name, "Refresh complete (" .. (why or "") .. ")")
    end
    return anyRefreshed
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function ExtraIcons:OnBagUpdateCooldown()
    if self._viewers then
        self:ThrottledRefresh("OnBagUpdateCooldown")
    end
end

function ExtraIcons:OnBagUpdateDelayed()
    ns.Runtime.RequestLayout("ExtraIcons:OnBagUpdateDelayed")
end

function ExtraIcons:OnPlayerEquipmentChanged(_, slotId)
    if self._trackedEquipSlots and self._trackedEquipSlots[slotId] then
        ns.Runtime.RequestLayout("ExtraIcons:OnPlayerEquipmentChanged")
    end
end

function ExtraIcons:OnPlayerEnteringWorld()
    ns.Runtime.RequestLayout("ExtraIcons:OnPlayerEnteringWorld")
end

function ExtraIcons:OnSpellsChanged()
    ns.Runtime.RequestLayout("ExtraIcons:OnSpellsChanged")
end

--- Rebuild the set of tracked equipment slots from the current config.
function ExtraIcons:_rebuildTrackedSlots()
    local tracked = {}
    local config = self:GetModuleConfig()
    if config and config.viewers then
        for _, entries in pairs(config.viewers) do
            for _, entry in ipairs(entries) do
                if not entry.disabled then
                    local stack = entry.stackKey and BUILTIN_STACKS[entry.stackKey]
                    local kind = stack and stack.kind or entry.kind
                    local sid = stack and stack.slotId or entry.slotId
                    if kind == "equipSlot" and sid then
                        tracked[sid] = true
                    end
                end
            end
        end
    end
    self._trackedEquipSlots = tracked
end

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

--- Hook EditModeManagerFrame to pause layout while edit mode is active.
function ExtraIcons:HookEditMode()
    local editModeManager = _G.EditModeManagerFrame
    if not editModeManager or self._editModeHooked then
        return
    end

    self._editModeHooked = true
    self._isEditModeActive = editModeManager:IsShown()

    editModeManager:HookScript("OnShow", function()
        self._isEditModeActive = true
        if self._viewers then
            for _, vs in pairs(self._viewers) do
                vs.container:Hide()
            end
        end
        if self:IsEnabled() then
            ns.Runtime.RequestLayout("ExtraIcons:EnterEditMode")
        end
    end)

    editModeManager:HookScript("OnHide", function()
        self._isEditModeActive = false
        if self:IsEnabled() then
            ns.Runtime.RequestLayout("ExtraIcons:ExitEditMode")
        end
    end)
end

--- Hook a single Blizzard viewer frame.
---@param viewerKey string The viewer key.
function ExtraIcons:_hookViewer(viewerKey)
    local reg = VIEWER_REGISTRY[viewerKey]
    local blizzFrame = _G[reg.blizzFrameKey]
    local vs = self._viewers and self._viewers[viewerKey]
    if not blizzFrame or not vs or vs.hooked then
        return
    end

    vs.hooked = true

    blizzFrame:HookScript("OnShow", function()
        ns.Runtime.RequestLayout("ExtraIcons:OnShow")
    end)

    blizzFrame:HookScript("OnHide", function()
        if vs.container then
            vs.container:Hide()
        end
        if vs.anchorFrame then
            vs.anchorFrame:Hide()
        end
        if self:IsEnabled() then
            ns.Runtime.RequestLayout("ExtraIcons:OnHide")
        end
    end)

    blizzFrame:HookScript("OnSizeChanged", function()
        ns.Runtime.RequestLayout("ExtraIcons:OnSizeChanged")
    end)

    ns.Log(self.Name, "Hooked " .. reg.blizzFrameKey)
end

--- Hook the UtilityCooldownViewer (backward compat wrapper).
function ExtraIcons:HookUtilityViewer()
    self:_hookViewer("utility")
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

function ExtraIcons:OnInitialize()
    BarMixin.AddFrameMixin(self, "ExtraIcons")
end

function ExtraIcons:OnEnable()
    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)
    self:_rebuildTrackedSlots()

    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function(_, ...) self:OnBagUpdateCooldown(...) end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function(_, ...) self:OnBagUpdateDelayed(...) end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, ...) self:OnPlayerEquipmentChanged(...) end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, ...) self:OnPlayerEnteringWorld(...) end)
    self:RegisterEvent("SPELLS_CHANGED", function() self:OnSpellsChanged() end)
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function() self:ThrottledRefresh("OnSpellUpdateCooldown") end)

    -- Hook viewers after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookEditMode()
        for viewerKey in pairs(VIEWER_REGISTRY) do
            self:_hookViewer(viewerKey)
        end
        ns.Runtime.RequestLayout("ExtraIcons:OnEnable")
    end)
end

function ExtraIcons:OnDisable()
    self:UnregisterAllEvents()
    self:UpdateLayout("OnDisable")

    ns.Runtime.UnregisterFrame(self)

    if self._viewers then
        for _, vs in pairs(self._viewers) do
            vs.originalPoint = nil
        end
    end
    self._isEditModeActive = nil
    self._trackedEquipSlots = nil
end
