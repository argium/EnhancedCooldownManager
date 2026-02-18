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

---@class ECM_IconData
---@field itemId number Item ID.
---@field texture string|number Icon texture.
---@field slotId number|nil Inventory slot ID (trinkets only, nil for bag items).

---@class ECM_ItemIcon : Button
---@field slotId number|nil Inventory slot ID this icon represents (trinkets only).
---@field itemId number|nil Item ID this icon represents (bag items only).
---@field Icon Texture The icon texture.
---@field Cooldown Cooldown The cooldown overlay frame.

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Checks if a trinket slot has an on-use effect.
---@param slotId number Inventory slot ID (13 or 14).
---@return ECM_IconData|nil iconData Icon data if on-use, nil otherwise.
local function GetTrinketData(slotId)
    local itemId = GetInventoryItemID("player", slotId)
    if not itemId then
        return nil
    end

    local _, spellId = C_Item.GetItemSpell(itemId)
    if not spellId then
        return nil
    end

    local texture = GetInventoryItemTexture("player", slotId)
    return {
        itemId = itemId,
        texture = texture,
        slotId = slotId,
    }
end

--- Returns the first item from priorityList that exists in the player's bags.
---@param priorityList number[] Array of item IDs, ordered by priority.
---@return ECM_IconData|nil iconData Icon data if found, nil otherwise.
local function GetBestConsumable(priorityList)
    for _, itemId in ipairs(priorityList) do
        if C_Item.GetItemCount(itemId) > 0 then
            local texture = C_Item.GetItemIconByID(itemId)
            return {
                itemId = itemId,
                texture = texture,
                slotId = nil,
            }
        end
    end
    return nil
end

--- Returns all display items in display order: Trinkets > Combat Potion > Health Potion > Healthstone.
---@param moduleConfig table Module configuration.
---@return ECM_IconData[] items Array of icon data.
local function GetDisplayItems(moduleConfig)
    local items = {}

    -- Trinkets first
    if moduleConfig.showTrinket1 then
        local data = GetTrinketData(ECM.Constants.TRINKET_SLOT_1)
        if data then
            items[#items + 1] = data
        end
    end

    if moduleConfig.showTrinket2 then
        local data = GetTrinketData(ECM.Constants.TRINKET_SLOT_2)
        if data then
            items[#items + 1] = data
        end
    end

    -- Combat potion
    if moduleConfig.showCombatPotion then
        local data = GetBestConsumable(ECM.Constants.COMBAT_POTIONS)
        if data then
            items[#items + 1] = data
        end
    end

    -- Health potion
    if moduleConfig.showHealthPotion then
        local data = GetBestConsumable(ECM.Constants.HEALTH_POTIONS)
        if data then
            items[#items + 1] = data
        end
    end

    -- Healthstone
    if moduleConfig.showHealthstone then
        if C_Item.GetItemCount(ECM.Constants.HEALTHSTONE_ITEM_ID) > 0 then
            local texture = C_Item.GetItemIconByID(ECM.Constants.HEALTHSTONE_ITEM_ID)
            items[#items + 1] = {
                itemId = ECM.Constants.HEALTHSTONE_ITEM_ID,
                texture = texture,
                slotId = nil,
            }
        end
    end

    return items
end

--- Creates a single item icon frame styled like cooldown viewer icons.
---@param parent Frame Parent frame to attach to.
---@param size number Icon size in pixels.
---@return ECM_ItemIcon icon The created icon frame.
local function CreateItemIcon(parent, size)
    local icon = CreateFrame("Button", nil, parent)
    icon:SetSize(size, size)

    -- Icon texture (the actual item icon) - ARTWORK layer
    icon.Icon = icon:CreateTexture(nil, "ARTWORK")
    icon.Icon:SetPoint("CENTER")
    icon.Icon:SetSize(size, size)

    -- Icon mask (rounds the corners) - ARTWORK layer
    icon.Mask = icon:CreateMaskTexture()
    icon.Mask:SetAtlas("UI-HUD-CoolDownManager-Mask")
    icon.Mask:SetPoint("CENTER")
    icon.Mask:SetSize(size, size)
    icon.Icon:AddMaskTexture(icon.Mask)

    -- Cooldown overlay with proper swipe and edge textures
    icon.Cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.Cooldown:SetAllPoints()
    icon.Cooldown:SetDrawEdge(true)
    icon.Cooldown:SetDrawSwipe(true)
    icon.Cooldown:SetHideCountdownNumbers(false)
    icon.Cooldown:SetSwipeTexture([[Interface\HUD\UI-HUD-CoolDownManager-Icon-Swipe]], 0, 0, 0, 0.2)
    icon.Cooldown:SetEdgeTexture([[Interface\Cooldown\UI-HUD-ActionBar-SecondaryCooldown]])

    -- Border overlay - OVERLAY layer (scaled size, centered)
    icon.Border = icon:CreateTexture(nil, "OVERLAY")
    icon.Border:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")
    icon.Border:SetPoint("CENTER")
    icon.Border:SetSize(size * ECM.Constants.ITEM_ICON_BORDER_SCALE, size * ECM.Constants.ITEM_ICON_BORDER_SCALE)

    -- Shadow overlay
    icon.Shadow = icon:CreateTexture(nil, "OVERLAY")
    icon.Shadow:SetAtlas("UI-CooldownManager-OORshadow")
    icon.Shadow:SetAllPoints()
    icon.Shadow:Hide() -- Only show when out of range (optional)

    return icon
end

--- Updates the cooldown display on an item icon.
---@param icon ECM_ItemIcon The icon to update.
local function UpdateIconCooldown(icon)
    local start, duration, enable

    if icon.slotId then
        -- Trinket (equipped item): enable is number (0/1)
        start, duration, enable = GetInventoryItemCooldown("player", icon.slotId)
        enable = (enable == 1)
    elseif icon.itemId then
        -- Bag item (potion/healthstone): enable is boolean
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

--- Gets cooldown number font info from a Blizzard utility cooldown icon.
--- @param utilityViewer Frame
--- @return string|nil fontPath, number|nil fontSize, string|nil fontFlags
local function GetSiblingCooldownNumberFont(utilityViewer)
    if not utilityViewer then
        return nil, nil, nil
    end

    for _, child in ipairs({ utilityViewer:GetChildren() }) do
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
--- @param icon ECM_ItemIcon
--- @param fontPath string
--- @param fontSize number
--- @param fontFlags string|nil
local function ApplyCooldownNumberFont(icon, fontPath, fontSize, fontFlags)
    if not (icon and icon.Cooldown and icon.Cooldown.GetRegions) then
        return
    end

    local region = select(1, icon.Cooldown:GetRegions())
    if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetFont then
        region:SetFont(fontPath, fontSize, fontFlags)
    end
end

--- Restores UtilityCooldownViewer to its original position.
---@param self ECM_ItemIconsModule
local function RestoreViewerPosition(self)
    if not self._viewerOriginalPoint then
        return
    end

    local utilityViewer = _G["UtilityCooldownViewer"]
    if not utilityViewer then
        return
    end

    local orig = self._viewerOriginalPoint
    utilityViewer:ClearAllPoints()
    utilityViewer:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
end

--- Applies midpoint-preserving X offset to UtilityCooldownViewer for added item icons.
---@param self ECM_ItemIconsModule
---@param utilityViewer Frame
---@param totalWidth number Container width (unscaled) for visible item icons.
---@param spacing number Gap between viewer and item icons (unscaled).
---@param viewerScale number Scale applied to UtilityCooldownViewer icons.
local function ApplyViewerMidpointOffset(self, utilityViewer, totalWidth, spacing, viewerScale)
    if not utilityViewer then
        return
    end

    if not self._viewerOriginalPoint then
        local point, relativeTo, relativePoint, x, y = utilityViewer:GetPoint()
        self._viewerOriginalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end

    local scaledContainerWidth = totalWidth * viewerScale
    local itemBlockWidth = scaledContainerWidth + spacing
    local viewerOffsetX = -(itemBlockWidth / 2)
    local orig = self._viewerOriginalPoint

    utilityViewer:ClearAllPoints()
    utilityViewer:SetPoint(orig[1], orig[2], orig[3], orig[4] + viewerOffsetX, orig[5])
end

--- Returns whether Blizzard Edit Mode is currently active.
---@param self ECM_ItemIconsModule|nil
---@return boolean
local function IsEditModeActive(self)
    if self and self._isEditModeActive ~= nil then
        return self._isEditModeActive
    end

    local editModeManager = _G.EditModeManagerFrame
    return editModeManager and editModeManager:IsShown() or false
end

--- Gets the icon size, spacing, and scale from UtilityCooldownViewer.
--- Falls back to defaults if viewer is unavailable.
--- Measures actual icon frames to respect Edit Mode settings.
--- Returns base (unscaled) sizes - caller should apply scale separately.
---@return number iconSize The base icon size in pixels (unscaled).
---@return number spacing The base spacing between icons in pixels (unscaled).
---@return number scale The icon scale factor from Edit Mode (applied to individual icons).
---@return boolean isStable True when spacing was measured from valid live geometry.
---@return table debugInfo Measurement debug payload for logs.
local function GetUtilityViewerLayout()
    local viewer = _G["UtilityCooldownViewer"]
    if not viewer or not viewer:IsShown() then
        return ECM.Constants.DEFAULT_ITEM_ICON_SIZE, ECM.Constants.DEFAULT_ITEM_ICON_SPACING, 1.0, false, {
            reason = "viewer_hidden_or_missing",
            measuredSpacing = nil,
            gap = nil,
            left = nil,
            right = nil,
        }
    end

    local children = { viewer:GetChildren() }
    local iconSize = ECM.Constants.DEFAULT_ITEM_ICON_SIZE
    local iconScale = 1.0
    local spacing = ECM.Constants.DEFAULT_ITEM_ICON_SPACING
    local isStable = false
    local debugInfo = {
        reason = "no_pair",
        measuredSpacing = nil,
        gap = nil,
        left = nil,
        right = nil,
        childScale = nil,
        maxSpacing = nil,
    }

    -- Find first cooldown icon to get size and scale
    -- Edit Mode "Icon Size" applies scale to individual icons, not the viewer
    for _, child in ipairs(children) do
        if child and child:IsShown() and child.GetSpellID then
            iconSize = child:GetWidth() or iconSize -- base size (unaffected by child scale)
            iconScale = child:GetScale() or 1.0
            break
        end
    end

    -- Calculate spacing from adjacent icons sorted by screen position.
    -- GetChildren() order is not guaranteed to be visual order.
    local measuredIcons = {}
    for _, child in ipairs(children) do
        if child and child:IsShown() and child.GetSpellID then
            local left = child:GetLeft()
            local right = child:GetRight()
            if left and right then
                measuredIcons[#measuredIcons + 1] = {
                    left = left,
                    right = right,
                    scale = child:GetScale() or 1.0,
                }
            end
        end
    end

    if #measuredIcons < 2 then
        debugInfo.reason = "no_pair"
        return iconSize or ECM.Constants.DEFAULT_ITEM_ICON_SIZE, spacing, iconScale, isStable, debugInfo
    end

    table.sort(measuredIcons, function(a, b)
        return a.left < b.left
    end)

    local maxSpacing = iconSize * ECM.Constants.ITEM_ICON_MAX_SPACING_FACTOR
    debugInfo.maxSpacing = maxSpacing

    local bestSpacing = nil
    local bestGap = nil
    local bestLeft = nil
    local bestRight = nil
    local bestScale = nil

    for i = 2, #measuredIcons do
        local prev = measuredIcons[i - 1]
        local curr = measuredIcons[i]
        local gap = curr.left - prev.right
        if gap >= 0 and curr.scale > 0 then
            local measuredSpacing = gap / curr.scale
            if measuredSpacing >= 0 and measuredSpacing <= maxSpacing then
                if not bestSpacing or measuredSpacing < bestSpacing then
                    bestSpacing = measuredSpacing
                    bestGap = gap
                    bestLeft = curr.left
                    bestRight = prev.right
                    bestScale = curr.scale
                end
            end
        end
    end

    if bestSpacing then
        spacing = bestSpacing
        isStable = true
        debugInfo.reason = "measured_ok_adjacent"
        debugInfo.measuredSpacing = bestSpacing
        debugInfo.gap = bestGap
        debugInfo.left = bestLeft
        debugInfo.right = bestRight
        debugInfo.childScale = bestScale
    else
        debugInfo.reason = "no_valid_adjacent_gap"
    end

    return iconSize or ECM.Constants.DEFAULT_ITEM_ICON_SIZE, spacing, iconScale, isStable, debugInfo
end

--------------------------------------------------------------------------------
-- ECM.ModuleMixin Overrides
--------------------------------------------------------------------------------

--- Override CreateFrame to create the container for item icons.
---@return Frame container The container frame.
function ItemIcons:CreateFrame()
    local frame = CreateFrame("Frame", "ECMItemIcons", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1) -- Will be resized in UpdateLayout

    -- Pool of icon frames (pre-allocate for max items)
    frame._iconPool = {}
    local initialSize = ECM.Constants.DEFAULT_ITEM_ICON_SIZE
    for i = 1, ECM.Constants.ITEM_ICONS_MAX do
        frame._iconPool[i] = CreateItemIcon(frame, initialSize)
    end

    return frame
end

--- Override ShouldShow to check module enabled state and item availability.
---@return boolean shouldShow Whether the frame should be shown.
function ItemIcons:ShouldShow()
    if not ECM.ModuleMixin.ShouldShow(self) then
        return false
    end

    -- Also hide if UtilityCooldownViewer is not visible
    local utilityViewer = _G["UtilityCooldownViewer"]
    if not utilityViewer or not utilityViewer:IsShown() then
        return false
    end

    return true
end

--- Override UpdateLayout to position icons relative to UtilityCooldownViewer.
--- @param why string|nil Reason for layout update (for logging/debugging).
--- @return boolean success Whether the layout was applied.
function ItemIcons:UpdateLayout(why)
    local frame = self.InnerFrame
    if not frame then
        return false
    end

    local moduleConfig = self:GetModuleConfig()
    if not moduleConfig then
        RestoreViewerPosition(self)
        return false
    end

    if IsEditModeActive(self) then
        RestoreViewerPosition(self)
        self._viewerOriginalPoint = nil
        frame:Hide()
        return false
    end

    -- Check visibility
    if not self:ShouldShow() then
        RestoreViewerPosition(self)
        frame:Hide()
        return false
    end

    local utilityViewer = _G["UtilityCooldownViewer"]
    if not utilityViewer then
        RestoreViewerPosition(self)
        frame:Hide()
        return false
    end

    local siblingFontPath, siblingFontSize, siblingFontFlags = GetSiblingCooldownNumberFont(utilityViewer)

    -- Get display items
    local items = GetDisplayItems(moduleConfig)
    local numItems = #items
    local iconSize, spacing, viewerScale, layoutStable, layoutDebug = GetUtilityViewerLayout()

    -- Apply the same scale as the viewer to match Edit Mode settings
    frame:SetScale(viewerScale)

    -- Hide all existing icons first
    for _, icon in ipairs(frame._iconPool) do
        icon:Hide()
    end

    -- If no items, hide container
    if numItems == 0 then
        RestoreViewerPosition(self)
        frame:Hide()
        return false
    end

    -- Calculate container size (using base sizes, scale is applied separately)
    local totalWidth = (numItems * iconSize) + ((numItems - 1) * spacing)
    local totalHeight = iconSize
    frame:SetSize(totalWidth, totalHeight)
    ApplyViewerMidpointOffset(self, utilityViewer, totalWidth, spacing, viewerScale)

    -- Position and configure each icon
    local xOffset = 0
    for i, iconData in ipairs(items) do
        local icon = frame._iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * ECM.Constants.ITEM_ICON_BORDER_SCALE, iconSize * ECM.Constants.ITEM_ICON_BORDER_SCALE)
        icon.slotId = iconData.slotId
        icon.itemId = iconData.itemId

        -- Set texture (handle nil case if item not loaded)
        if iconData.texture then
            icon.Icon:SetTexture(iconData.texture)
        else
            icon.Icon:SetTexture(nil)
        end

        -- Position
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "LEFT", xOffset, 0)
        icon:Show()

        if siblingFontPath and siblingFontSize then
            ApplyCooldownNumberFont(icon, siblingFontPath, siblingFontSize, siblingFontFlags)
        end

        xOffset = xOffset + iconSize + spacing
    end

    -- Position container to the right of UtilityCooldownViewer
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", utilityViewer, "RIGHT", spacing, 0)
    frame:Show()

    ECM_log(ECM.Constants.SYS.Layout, self.Name, "UpdateLayout (" .. (why or "") .. ")", {
        numItems = numItems,
        iconSize = iconSize,
        spacing = spacing,
        layoutStable = layoutStable,
        totalWidth = totalWidth,
        layoutDebug = layoutDebug,
    })

    -- TODO: there really must be a better way to handling this. I doubt this level of shit-hackery is required.
    if layoutStable then
        self._layoutRetryCount = 0
    elseif not self._layoutRetryPending and (self._layoutRetryCount or 0) < ECM.Constants.ITEM_ICON_LAYOUT_REMEASURE_ATTEMPTS then
        self._layoutRetryPending = true
        self._layoutRetryCount = (self._layoutRetryCount or 0) + 1
        C_Timer.After(ECM.Constants.ITEM_ICON_LAYOUT_REMEASURE_DELAY, function()
            self._layoutRetryPending = nil
            if self:IsEnabled() then
                self:ThrottledUpdateLayout("UpdateLayout")
            end
        end)
    end

    -- Update cooldowns after layout is complete (CLAUDE.md mandate)
    self:ThrottledRefresh("UpdateLayout")

    return true
end

--- Override Refresh to update cooldown states.
function ItemIcons:Refresh(why)
    if not FrameUtil.BaseRefresh(self, why) then
        return false
    end

    local frame = self.InnerFrame
    if not frame or not frame:IsShown() then
        return false
    end

    -- Update cooldowns on all visible icons
    for _, icon in ipairs(frame._iconPool) do
        if icon:IsShown() and (icon.slotId or icon.itemId) then
            UpdateIconCooldown(icon)
        end
    end

    ECM_log(ECM.Constants.SYS.Styling, self.Name, "Refresh complete (" .. (why or "") .. ")")
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

function ItemIcons:OnBagUpdateDelayed()
    -- Bag contents changed, which consumables to show may have changed
    self:ThrottledUpdateLayout("OnBagUpdateDelayed")
end

function ItemIcons:OnPlayerEquipmentChanged(_, slotId)
    -- Only update if a trinket slot changed
    if slotId == ECM.Constants.TRINKET_SLOT_1 or slotId == ECM.Constants.TRINKET_SLOT_2 then
        self:ThrottledUpdateLayout("OnPlayerEquipmentChanged")
    end
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
        if self.InnerFrame then
            self.InnerFrame:Hide()
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

--- Hook the UtilityCooldownViewer to update when it shows/hides or resizes.
function ItemIcons:HookUtilityViewer()
    local utilityViewer = _G["UtilityCooldownViewer"]
    if not utilityViewer or self._viewerHooked then
        return
    end

    self._viewerHooked = true

    utilityViewer:HookScript("OnShow", function()
        self:ThrottledUpdateLayout("OnShow")
    end)

    utilityViewer:HookScript("OnHide", function()
        if self.InnerFrame then
            self.InnerFrame:Hide()
        end
        if self:IsEnabled() then
            self:ThrottledUpdateLayout("OnHide")
        end
    end)

    utilityViewer:HookScript("OnSizeChanged", function()
        self:ThrottledUpdateLayout("OnSizeChanged")
    end)

    ECM_log(ECM.Constants.SYS.Core, self.Name, "Hooked UtilityCooldownViewer")
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ItemIcons:OnEnable()
    if not self.IsModuleMixin then
        ECM.ModuleMixin.AddMixin(self, "ItemIcons")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    -- Register events
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "OnBagUpdateCooldown") -- very noisy but required for cooldown updates on bag items
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagUpdateDelayed")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnPlayerEquipmentChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- Hook the utility viewer after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookEditMode()
        self:HookUtilityViewer()
        self:ThrottledUpdateLayout("OnEnable")
    end)

    ECM_log(ECM.Constants.SYS.Core, self.Name, "OnEnable - module enabled")
end

function ItemIcons:OnDisable()
    self:UnregisterAllEvents()

    self:UpdateLayout("OnDisable")

    if self.IsModuleMixin and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end

    self._viewerOriginalPoint = nil
    self._isEditModeActive = nil
    self._layoutRetryPending = nil
    self._layoutRetryCount = 0

    if self.InnerFrame then
        self.InnerFrame:Hide()
    end

    ECM_log(ECM.Constants.SYS.Core, self.Name, "Disabled")
end
