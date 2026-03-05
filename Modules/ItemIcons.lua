-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local FrameUtil = ECM.FrameUtil
local ItemIcons = mod:NewModule("ItemIcons", "AceEvent-3.0")
mod.ItemIcons = ItemIcons
ItemIcons:SetEnabledState(false)
ECM.ModuleMixin.ApplyConfigMixin(ItemIcons, "ItemIcons")

---@class ECM_ItemIconsModule : ModuleMixin
---@field _viewers table<string, ECM_ViewerState> Per-viewer state keyed by "essential"/"utility".

---@class ECM_ViewerState
---@field frame Frame Container frame for icons.
---@field iconPool ECM_ItemIcon[] Pre-allocated icon frames.
---@field viewerName string Blizzard viewer global name.
---@field configKey string Config table key ("essential" or "utility").
---@field originalPoint table|nil Saved anchor before midpoint offset.
---@field hooked boolean Whether OnShow/OnHide/OnSizeChanged hooks are installed.

---@class ECM_ResolvedEntry
---@field type string "item" or "spell".
---@field id number Item ID or Spell ID.
---@field texture string|number Icon texture.
---@field slotId number|nil Inventory slot for equipped items; nil for bag items and spells.

---@class ECM_ItemIcon : Button
---@field type string|nil "item" or "spell".
---@field slotId number|nil Inventory slot ID this icon represents (equipped items only).
---@field itemId number|nil Item ID this icon represents (bag items only).
---@field spellId number|nil Spell ID this icon represents.
---@field Icon Texture The icon texture.
---@field Cooldown Cooldown The cooldown overlay frame.
---@field QualityBadge Texture Quality tier badge overlay.

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Resolves config entries into display-ready data, preserving config order.
---@param entries ECM_ItemIconEntry[] Ordered entry list from config.
---@return ECM_ResolvedEntry[] resolved Available entries with textures.
local function resolveEntries(entries)
    local resolved = {}
    for _, entry in ipairs(entries) do
        if entry.type == ECM.Constants.ITEM_ICON_TYPE_ITEM then
            local id = entry.id
            local texture = C_Item.GetItemIconByID(id)
            if texture then
                -- Check if equipped (only include if slot can be determined)
                if C_Item.IsEquippableItem(id) and IsEquippedItem(id) then
                    local invSlot = C_Item.GetItemInventorySlotInfo(id)
                    if invSlot then
                        resolved[#resolved + 1] = { type = "item", id = id, texture = texture, slotId = invSlot }
                    end
                elseif C_Item.GetItemCount(id) > 0 then
                    resolved[#resolved + 1] = { type = "item", id = id, texture = texture, slotId = nil }
                end
            end
        elseif entry.type == ECM.Constants.ITEM_ICON_TYPE_SPELL then
            local id = entry.id
            if IsPlayerSpell(id) then
                local texture = C_Spell.GetSpellTexture(id)
                if texture then
                    resolved[#resolved + 1] = { type = "spell", id = id, texture = texture, slotId = nil }
                end
            end
        end
    end
    return resolved
end

--- Creates a single item icon frame styled like cooldown viewer icons.
---@param parent Frame Parent frame to attach to.
---@param size number Icon size in pixels.
---@return ECM_ItemIcon icon The created icon frame.
local function createItemIcon(parent, size)
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
    icon.Border:SetSize(size * ECM.Constants.ITEM_ICON_BORDER_SCALE, size * ECM.Constants.ITEM_ICON_BORDER_SCALE)

    icon.Shadow = icon:CreateTexture(nil, "OVERLAY")
    icon.Shadow:SetAtlas("UI-CooldownManager-OORshadow")
    icon.Shadow:SetAllPoints()
    icon.Shadow:Hide()

    icon.QualityBadge = icon:CreateTexture(nil, "OVERLAY", nil, 2)
    icon.QualityBadge:SetSize(size * 0.4, size * 0.4)
    icon.QualityBadge:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    icon.QualityBadge:Hide()

    return icon
end

--- Updates the cooldown display on an item icon.
---@param icon ECM_ItemIcon The icon to update.
local function updateIconCooldown(icon)
    if icon.type == ECM.Constants.ITEM_ICON_TYPE_SPELL then
        local cooldownInfo = C_Spell.GetSpellCooldown(icon.spellId)
        if cooldownInfo and cooldownInfo.duration > 0 then
            icon.Cooldown:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
        else
            icon.Cooldown:Clear()
        end
        return
    end

    local start, duration, enable
    if icon.slotId then
        start, duration, enable = GetInventoryItemCooldown("player", icon.slotId)
        enable = (enable == 1)
    elseif icon.itemId then
        start, duration, enable = C_Item.GetItemCooldown(icon.itemId)
    else
        return
    end

    if enable and duration > 0 then
        icon.Cooldown:SetCooldown(start, duration)
    else
        icon.Cooldown:Clear()
    end
end

--- Gets cooldown number font info from a Blizzard cooldown viewer icon.
---@param viewer Frame Blizzard cooldown viewer frame.
---@return string|nil fontPath, number|nil fontSize, string|nil fontFlags
local function getSiblingCooldownNumberFont(viewer)
    if not viewer then
        return nil, nil, nil
    end

    for _, child in ipairs({ viewer:GetChildren() }) do
        local cooldown = child and child.Cooldown
        if cooldown and cooldown.GetRegions then
            local region = select(1, cooldown:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("FontString") and region.GetFont then
                local fontPath, fontSize, fontFlags = region:GetFont()
                if fontPath and fontSize then
                    return fontPath, fontSize, fontFlags
                end
            end
        end
    end

    return nil, nil, nil
end

--- Applies cooldown number font settings to one icon cooldown.
---@param icon ECM_ItemIcon
---@param fontPath string
---@param fontSize number
---@param fontFlags string|nil
local function applyCooldownNumberFont(icon, fontPath, fontSize, fontFlags)
    if not (icon and icon.Cooldown and icon.Cooldown.GetRegions) then
        return
    end

    local region = select(1, icon.Cooldown:GetRegions())
    if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetFont then
        region:SetFont(fontPath, fontSize, fontFlags)
    end
end

--- Restores a Blizzard viewer to its original position.
---@param viewerState ECM_ViewerState
local function restoreViewerPosition(viewerState)
    if not viewerState.originalPoint then
        return
    end

    local viewer = _G[viewerState.viewerName]
    if not viewer then
        return
    end

    local orig = viewerState.originalPoint
    viewer:ClearAllPoints()
    viewer:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
end

--- Applies midpoint-preserving X offset to a Blizzard viewer for added item icons.
---@param viewerState ECM_ViewerState
---@param viewer Frame The Blizzard viewer frame.
---@param totalWidth number Container width (unscaled) for visible item icons.
---@param spacing number Gap between viewer and item icons (unscaled).
---@param viewerScale number Scale applied to viewer icons.
local function applyViewerMidpointOffset(viewerState, viewer, totalWidth, spacing, viewerScale)
    if not viewer then
        return
    end

    if not viewerState.originalPoint then
        local point, relativeTo, relativePoint, x, y = viewer:GetPoint()
        viewerState.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end

    local scaledContainerWidth = totalWidth * viewerScale
    local itemBlockWidth = scaledContainerWidth + spacing
    local viewerOffsetX = -(itemBlockWidth / 2)
    local orig = viewerState.originalPoint

    viewer:ClearAllPoints()
    viewer:SetPoint(orig[1], orig[2], orig[3], orig[4] + viewerOffsetX, orig[5])
end

--- Returns whether Blizzard Edit Mode is currently active.
---@param self ECM_ItemIconsModule|nil
---@return boolean
local function isEditModeActive(self)
    if self and self._isEditModeActive ~= nil then
        return self._isEditModeActive
    end

    local editModeManager = _G.EditModeManagerFrame
    return editModeManager and editModeManager:IsShown() or false
end

--- Gets the icon size, spacing, and scale from a Blizzard cooldown viewer.
--- Falls back to defaults if viewer is unavailable.
---@param viewerName string Global name of the Blizzard viewer.
---@return number iconSize, number spacing, number scale, boolean isStable, table debugInfo
local function getViewerLayout(viewerName)
    local viewer = _G[viewerName]
    if not viewer or not viewer:IsShown() then
        return ECM.Constants.DEFAULT_ITEM_ICON_SIZE, ECM.Constants.DEFAULT_ITEM_ICON_SPACING, 1.0, false, {
            reason = "viewer_hidden_or_missing",
        }
    end

    local iconSize = ECM.Constants.DEFAULT_ITEM_ICON_SIZE
    local iconScale = 1.0
    local spacing = ECM.Constants.DEFAULT_ITEM_ICON_SPACING
    local isStable = false
    local debugInfo = { reason = "no_pair" }

    -- Blizzard's EditModeCooldownViewerSystemMixin stores iconPadding/iconScale on the frame.
    if viewer.iconPadding ~= nil then
        spacing = viewer.iconPadding
        isStable = true
        debugInfo.reason = "viewer_iconPadding"
        debugInfo.measuredSpacing = spacing
    end

    if viewer.iconScale then
        iconScale = viewer.iconScale
        debugInfo.childScale = iconScale
    end

    -- Get base icon size from a visible cooldown icon child.
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        if child and child:IsShown() and child.GetSpellID then
            iconSize = child:GetWidth() or iconSize
            break
        end
    end

    return iconSize or ECM.Constants.DEFAULT_ITEM_ICON_SIZE, spacing, iconScale, isStable, debugInfo
end

--- Creates a container frame and pre-allocated icon pool for one viewer.
---@param parent Frame Parent frame.
---@param viewerName string Blizzard viewer name (for naming).
---@return Frame container, ECM_ItemIcon[] iconPool
local function createViewerContainer(parent, viewerName)
    local frame = CreateFrame("Frame", "ECMItemIcons_" .. viewerName, parent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)

    local pool = {}
    local initialSize = ECM.Constants.DEFAULT_ITEM_ICON_SIZE
    for i = 1, ECM.Constants.ITEM_ICON_INITIAL_POOL_SIZE do
        pool[i] = createItemIcon(frame, initialSize)
    end

    return frame, pool
end

--- Ensures the icon pool has at least `needed` icons, creating extras on demand.
---@param pool ECM_ItemIcon[] Existing icon pool.
---@param needed number Required icon count.
---@param parent Frame Parent frame for new icons.
local function ensurePoolSize(pool, needed, parent)
    local initialSize = ECM.Constants.DEFAULT_ITEM_ICON_SIZE
    for i = #pool + 1, needed do
        pool[i] = createItemIcon(parent, initialSize)
    end
end

--- Applies the quality badge overlay on an icon based on item reagent quality.
---@param icon ECM_ItemIcon
---@param iconData ECM_ResolvedEntry
local function applyQualityBadge(icon, iconData)
    if iconData.type == ECM.Constants.ITEM_ICON_TYPE_ITEM
        and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
    then
        local quality = C_TradeSkillUI.GetItemReagentQualityByItemInfo(iconData.id)
        if quality and quality > 0 then
            icon.QualityBadge:SetAtlas("Professions-Icon-Quality-Tier" .. quality .. "-Small")
            icon.QualityBadge:Show()
            return
        end
    end
    icon.QualityBadge:Hide()
end

--------------------------------------------------------------------------------
-- ECM.ModuleMixin Overrides
--------------------------------------------------------------------------------

--- Override CreateFrame to create a parent frame with two viewer containers.
---@return Frame container The parent coordinator frame.
function ItemIcons:CreateFrame()
    local frame = CreateFrame("Frame", "ECMItemIcons", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)

    local essentialFrame, essentialPool = createViewerContainer(frame, "EssentialCooldownViewer")
    local utilityFrame, utilityPool = createViewerContainer(frame, "UtilityCooldownViewer")

    self._viewers = {
        essential = {
            frame = essentialFrame,
            iconPool = essentialPool,
            viewerName = "EssentialCooldownViewer",
            configKey = "essential",
            originalPoint = nil,
            hooked = false,
        },
        utility = {
            frame = utilityFrame,
            iconPool = utilityPool,
            viewerName = "UtilityCooldownViewer",
            configKey = "utility",
            originalPoint = nil,
            hooked = false,
        },
    }

    return frame
end

--- Override ShouldShow: return true when module is enabled; per-viewer visibility
--- is handled in UpdateLayout.
---@return boolean
function ItemIcons:ShouldShow()
    return ECM.ModuleMixin.ShouldShow(self)
end

--- Performs the layout pass for a single viewer.
---@param viewerState ECM_ViewerState
---@param entries ECM_ItemIconEntry[] Config entries for this viewer.
---@return boolean layoutStable, number numItems
local function layoutViewer(viewerState, entries)
    local viewer = _G[viewerState.viewerName]
    local container = viewerState.frame

    -- Hide container if Blizzard viewer is absent or hidden
    if not viewer or not viewer:IsShown() then
        restoreViewerPosition(viewerState)
        container:Hide()
        return true, 0
    end

    local items = resolveEntries(entries or {})
    local numItems = #items
    local iconSize, spacing, viewerScale, layoutStable = getViewerLayout(viewerState.viewerName)

    container:SetScale(viewerScale)

    -- Hide all icons
    for _, icon in ipairs(viewerState.iconPool) do
        icon:Hide()
    end

    if numItems == 0 then
        restoreViewerPosition(viewerState)
        container:Hide()
        return layoutStable, 0
    end

    -- Grow pool if needed
    ensurePoolSize(viewerState.iconPool, numItems, container)

    local siblingFontPath, siblingFontSize, siblingFontFlags = getSiblingCooldownNumberFont(viewer)
    local totalWidth = (numItems * iconSize) + ((numItems - 1) * spacing)
    container:SetSize(totalWidth, iconSize)
    applyViewerMidpointOffset(viewerState, viewer, totalWidth, spacing, viewerScale)

    local xOffset = 0
    for i, iconData in ipairs(items) do
        local icon = viewerState.iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * ECM.Constants.ITEM_ICON_BORDER_SCALE, iconSize * ECM.Constants.ITEM_ICON_BORDER_SCALE)
        icon.QualityBadge:SetSize(iconSize * 0.4, iconSize * 0.4)

        -- Set entry type data
        icon.type = iconData.type
        if iconData.type == ECM.Constants.ITEM_ICON_TYPE_SPELL then
            icon.spellId = iconData.id
            icon.itemId = nil
            icon.slotId = nil
        else
            icon.itemId = iconData.id
            icon.slotId = iconData.slotId
            icon.spellId = nil
        end

        icon.Icon:SetTexture(iconData.texture)
        applyQualityBadge(icon, iconData)

        icon:ClearAllPoints()
        icon:SetPoint("LEFT", container, "LEFT", xOffset, 0)
        icon:Show()

        if siblingFontPath and siblingFontSize then
            applyCooldownNumberFont(icon, siblingFontPath, siblingFontSize, siblingFontFlags)
        end

        xOffset = xOffset + iconSize + spacing
    end

    container:ClearAllPoints()
    container:SetPoint("LEFT", viewer, "RIGHT", spacing, 0)
    container:Show()

    return layoutStable, numItems
end

--- Override UpdateLayout to position icons relative to both Blizzard viewers.
---@param why string|nil Reason for layout update.
---@return boolean success
function ItemIcons:UpdateLayout(why)
    local frame = self.InnerFrame
    if not frame or not self._viewers then
        return false
    end

    local moduleConfig = self:GetModuleConfig()
    if not moduleConfig then
        for _, vs in pairs(self._viewers) do
            restoreViewerPosition(vs)
        end
        return false
    end

    if isEditModeActive(self) then
        for _, vs in pairs(self._viewers) do
            restoreViewerPosition(vs)
            vs.originalPoint = nil
            vs.frame:Hide()
        end
        return false
    end

    if not self:ShouldShow() then
        for _, vs in pairs(self._viewers) do
            restoreViewerPosition(vs)
            vs.frame:Hide()
        end
        return false
    end

    local anyUnstable = false
    local totalItems = 0

    for _, vs in pairs(self._viewers) do
        local entries = moduleConfig[vs.configKey]
        local stable, count = layoutViewer(vs, entries)
        if not stable then
            anyUnstable = true
        end
        totalItems = totalItems + count
    end

    ECM.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")", { totalItems = totalItems })

    -- Retry layout if viewer measurements are not yet stable
    if anyUnstable and not self._layoutRetryPending
        and (self._layoutRetryCount or 0) < ECM.Constants.ITEM_ICON_LAYOUT_REMEASURE_ATTEMPTS
    then
        self._layoutRetryPending = true
        self._layoutRetryCount = (self._layoutRetryCount or 0) + 1
        C_Timer.After(ECM.Constants.ITEM_ICON_LAYOUT_REMEASURE_DELAY, function()
            self._layoutRetryPending = nil
            if self:IsEnabled() then
                self:ThrottledUpdateLayout("Remeasure")
            end
        end)
    elseif not anyUnstable then
        self._layoutRetryCount = 0
    end

    self:ThrottledRefresh("UpdateLayout")
    return true
end

--- Override Refresh to update cooldown states across both viewers.
function ItemIcons:Refresh(why)
    if not FrameUtil.BaseRefresh(self, why) then
        return false
    end

    if not self._viewers then
        return false
    end

    for _, vs in pairs(self._viewers) do
        if vs.frame:IsShown() then
            for _, icon in ipairs(vs.iconPool) do
                if icon:IsShown() and (icon.slotId or icon.itemId or icon.spellId) then
                    updateIconCooldown(icon)
                end
            end
        end
    end

    ECM.Log(self.Name, "Refresh complete (" .. (why or "") .. ")")
    return true
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function ItemIcons:OnBagUpdateCooldown()
    if self.InnerFrame then
        self:ThrottledRefresh("OnBagUpdateCooldown")
    end
end

function ItemIcons:OnSpellUpdateCooldown()
    if self.InnerFrame then
        self:ThrottledRefresh("OnSpellUpdateCooldown")
    end
end

function ItemIcons:OnBagUpdateDelayed()
    self:ThrottledUpdateLayout("OnBagUpdateDelayed")
end

function ItemIcons:OnPlayerEquipmentChanged()
    self:ThrottledUpdateLayout("OnPlayerEquipmentChanged")
end

function ItemIcons:OnPlayerEnteringWorld()
    self:ThrottledUpdateLayout("OnPlayerEnteringWorld")
end

--- Hook EditModeManagerFrame to pause ItemIcons layout while edit mode is active.
function ItemIcons:HookEditMode()
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
                vs.frame:Hide()
            end
        end
        if self:IsEnabled() then
            self:ThrottledUpdateLayout("EnterEditMode")
        end
    end)

    editModeManager:HookScript("OnHide", function()
        self._isEditModeActive = false
        if self:IsEnabled() then
            self:ThrottledUpdateLayout("ExitEditMode")
        end
    end)
end

--- Hook both Blizzard cooldown viewers for OnShow/OnHide/OnSizeChanged.
function ItemIcons:HookViewers()
    if not self._viewers then
        return
    end

    for _, vs in pairs(self._viewers) do
        local viewer = _G[vs.viewerName]
        if viewer and not vs.hooked then
            vs.hooked = true

            viewer:HookScript("OnShow", function()
                self:ThrottledUpdateLayout(vs.viewerName .. ":OnShow")
            end)

            viewer:HookScript("OnHide", function()
                vs.frame:Hide()
                if self:IsEnabled() then
                    self:ThrottledUpdateLayout(vs.viewerName .. ":OnHide")
                end
            end)

            viewer:HookScript("OnSizeChanged", function()
                self:ThrottledUpdateLayout(vs.viewerName .. ":OnSizeChanged")
            end)

            ECM.Log(self.Name, "Hooked " .. vs.viewerName)
        end
    end
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ItemIcons:OnEnable()
    ECM.ModuleMixin.AddFrameMixin(self, "ItemIcons")
    ECM.RegisterFrame(self)

    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "OnBagUpdateCooldown")
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagUpdateDelayed")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnPlayerEquipmentChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "OnSpellUpdateCooldown")

    C_Timer.After(0.1, function()
        self:HookEditMode()
        self:HookViewers()
        self:ThrottledUpdateLayout("OnEnable")
    end)
end

function ItemIcons:OnDisable()
    self:UnregisterAllEvents()

    if self._viewers then
        for _, vs in pairs(self._viewers) do
            restoreViewerPosition(vs)
            vs.originalPoint = nil
        end
    end

    ECM.UnregisterFrame(self)

    self._isEditModeActive = nil
    self._layoutRetryPending = nil
    self._layoutRetryCount = 0
end
