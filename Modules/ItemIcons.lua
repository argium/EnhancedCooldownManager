-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local FrameMixin = ECM.FrameMixin
local ItemIcons = ns.Addon:NewModule("ItemIcons")
ns.Addon.ItemIcons = ItemIcons

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

--- Checks if a trinket slot has an on-use effect.
---@param slotId number Inventory slot ID (13 or 14).
---@return ECM_IconData|nil iconData Icon data if on-use, nil otherwise.
local function getTrinketData(slotId)
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
---@param priorityList { itemID: number, quality: number|nil }[] Array of priority entries, ordered by priority.
---@return ECM_IconData|nil iconData Icon data if found, nil otherwise.
local function getBestConsumable(priorityList)
    for _, entry in ipairs(priorityList) do
        local itemId = entry.itemID
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
local function getDisplayItems(moduleConfig)
    local items = {}

    if moduleConfig.showTrinket1 then
        local trinket1 = getTrinketData(ECM.Constants.TRINKET_SLOT_1)
        if trinket1 then
            items[#items + 1] = trinket1
        end
    end

    if moduleConfig.showTrinket2 then
        local trinket2 = getTrinketData(ECM.Constants.TRINKET_SLOT_2)
        if trinket2 then
            items[#items + 1] = trinket2
        end
    end

    if moduleConfig.showCombatPotion then
        local combatPotion = getBestConsumable(ECM.Constants.COMBAT_POTIONS)
        if combatPotion then
            items[#items + 1] = combatPotion
        end
    end

    if moduleConfig.showHealthPotion then
        local healthPotion = getBestConsumable(ECM.Constants.HEALTH_POTIONS)
        if healthPotion then
            items[#items + 1] = healthPotion
        end
    end

    if moduleConfig.showHealthstone and C_Item.GetItemCount(ECM.Constants.HEALTHSTONE_ITEM_ID) > 0 then
        items[#items + 1] = {
            itemId = ECM.Constants.HEALTHSTONE_ITEM_ID,
            texture = C_Item.GetItemIconByID(ECM.Constants.HEALTHSTONE_ITEM_ID),
        }
    end

    return items
end

--- Creates a single item icon frame styled like cooldown viewer icons.
---@param parent Frame Parent frame to attach to.
---@param size number Icon size in pixels.
---@return ECM_ItemIcon icon The created icon frame.
local function createItemIcon(parent, size)
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
local function updateIconCooldown(icon)
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
local function getSiblingCooldownNumberFont(utilityViewer)
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
local function applyCooldownNumberFont(icon, fontPath, fontSize, fontFlags)
    if not (icon and icon.Cooldown and icon.Cooldown.GetRegions) then
        return
    end

    local region = select(1, icon.Cooldown:GetRegions())
    if region and region.IsObjectType and region:IsObjectType("FontString") and region.SetFont then
        region:SetFont(fontPath, fontSize, fontFlags)
    end
end

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
        frame._iconPool[i] = createItemIcon(frame, initialSize)
    end

    return frame
end

--- Override ShouldShow to check module enabled state and item availability.
---@return boolean shouldShow Whether the frame should be shown.
function ItemIcons:ShouldShow()
    if not ECM.FrameMixin.Proto.ShouldShow(self) then
        return false
    end
    local utilityViewer = _G["UtilityCooldownViewer"]
    return utilityViewer ~= nil and utilityViewer:IsShown()
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
    local utilityViewer = _G["UtilityCooldownViewer"]
    local isEditing = self._isEditModeActive
    if isEditing == nil then
        local editModeManager = _G.EditModeManagerFrame
        isEditing = editModeManager and editModeManager:IsShown() or false
    end

    -- Bail early: no config, edit mode active, or shouldn't show
    if not moduleConfig or isEditing or not self:ShouldShow() then
        local viewerOriginalPoint = self._viewerOriginalPoint
        if viewerOriginalPoint and utilityViewer then
            utilityViewer:ClearAllPoints()
            utilityViewer:SetPoint(
                viewerOriginalPoint[1],
                viewerOriginalPoint[2],
                viewerOriginalPoint[3],
                viewerOriginalPoint[4],
                viewerOriginalPoint[5]
            )
        end

        if isEditing then
            self._viewerOriginalPoint = nil
        end

        frame:Hide()
        return false
    end

    local items = utilityViewer and getDisplayItems(moduleConfig) or {}
    local numItems = #items

    -- Hide all existing icons
    for _, icon in ipairs(frame._iconPool) do
        icon:Hide()
    end

    if numItems == 0 or not utilityViewer then
        local viewerOriginalPoint = self._viewerOriginalPoint
        if viewerOriginalPoint and utilityViewer then
            utilityViewer:ClearAllPoints()
            utilityViewer:SetPoint(
                viewerOriginalPoint[1],
                viewerOriginalPoint[2],
                viewerOriginalPoint[3],
                viewerOriginalPoint[4],
                viewerOriginalPoint[5]
            )
        end

        frame:Hide()
        return false
    end

    local siblingFontPath, siblingFontSize, siblingFontFlags = getSiblingCooldownNumberFont(utilityViewer)
    local iconSize = ECM.Constants.DEFAULT_ITEM_ICON_SIZE
    local spacing = 0
    local viewerScale = 1.0

    if utilityViewer:IsShown() then
        viewerScale = utilityViewer.iconScale or 1.0
        -- Blizzard's managed layout uses childXPadding for actual icon positioning.
        -- This differs from the Edit Mode iconPadding setting by a constant offset of -4
        -- (childXPadding = iconPadding - 4), accounting for transparent padding in icon atlases.
        spacing = utilityViewer.childXPadding or 0

        -- Get base icon size from a visible cooldown icon child.
        -- Edit Mode "Icon Size" applies scale to individual icons, not the viewer.
        for _, child in ipairs({ utilityViewer:GetChildren() }) do
            if child and child:IsShown() and child.GetSpellID then
                iconSize = child:GetWidth() or iconSize
                break
            end
        end
    end

    frame:SetScale(viewerScale)

    -- Calculate container size (using base sizes, scale is applied separately)
    local totalWidth = (numItems * iconSize) + ((numItems - 1) * spacing)
    local totalHeight = iconSize
    frame:SetSize(totalWidth, totalHeight)
    if not self._viewerOriginalPoint then
        local point, relativeTo, relativePoint, x, y = utilityViewer:GetPoint()
        self._viewerOriginalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end

    local viewerOriginalPoint = self._viewerOriginalPoint
    local viewerOffsetX = -(((totalWidth * viewerScale) + spacing) / 2)
    utilityViewer:ClearAllPoints()
    utilityViewer:SetPoint(
        viewerOriginalPoint[1],
        viewerOriginalPoint[2],
        viewerOriginalPoint[3],
        viewerOriginalPoint[4] + viewerOffsetX,
        viewerOriginalPoint[5]
    )

    -- Position and configure each icon
    local borderScale = ECM.Constants.ITEM_ICON_BORDER_SCALE
    local xOffset = 0
    for i, iconData in ipairs(items) do
        local icon = frame._iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * borderScale, iconSize * borderScale)
        icon.slotId = iconData.slotId
        icon.itemId = iconData.itemId

        icon.Icon:SetTexture(iconData.texture or nil)

        -- Position
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "LEFT", xOffset, 0)
        icon:Show()

        -- Apply cooldown immediately; ThrottledRefresh may be suppressed
        -- when BAG_UPDATE_COOLDOWN and BAG_UPDATE_DELAYED fire in the same batch.
        updateIconCooldown(icon)

        if siblingFontPath and siblingFontSize then
            applyCooldownNumberFont(icon, siblingFontPath, siblingFontSize, siblingFontFlags)
        end

        xOffset = xOffset + iconSize + spacing
    end

    -- Position container to the right of UtilityCooldownViewer
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", utilityViewer, "RIGHT", spacing, 0)
    frame:Show()

    ECM.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")")

    self:ThrottledRefresh("UpdateLayout")

    return true
end

--- Override Refresh to update cooldown states.
function ItemIcons:Refresh(why, force)
    -- call the frame mixin to check pre-conditions
    if not FrameMixin.Proto.Refresh(self, why, force) then
        return false
    end

    local frame = self.InnerFrame
    if not frame or not frame:IsShown() then
        return false
    end

    -- Update cooldowns on all visible icons
    for _, icon in ipairs(frame._iconPool) do
        if icon:IsShown() and (icon.slotId or icon.itemId) then
            updateIconCooldown(icon)
        end
    end

    ECM.Log(self.Name, "Refresh complete (" .. (why or "") .. ")")
    return true
end

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

    ECM.Log(self.Name, "Hooked UtilityCooldownViewer")
end

function ItemIcons:OnInitialize()
    ECM.FrameMixin.AddMixin(self, "ItemIcons")
end

function ItemIcons:OnEnable()
    self:EnsureFrame()
    ECM.Runtime.RegisterFrame(self)

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
end

function ItemIcons:OnDisable()
    self:UnregisterAllEvents()
    self:UpdateLayout("OnDisable")

    ECM.Runtime.UnregisterFrame(self)

    self._viewerOriginalPoint = nil
    self._isEditModeActive = nil
end
