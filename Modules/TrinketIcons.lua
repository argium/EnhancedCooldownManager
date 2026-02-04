-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local ECM = ns.Addon
local Util = ns.Util
local C = ns.Constants

local ECMFrame = ns.Mixins.ECMFrame

local TrinketIcons = ECM:NewModule("TrinketIcons", "AceEvent-3.0")
ECM.TrinketIcons = TrinketIcons

---@class ECM_TrinketIconsModule : ECMFrame

---@class ECM_TrinketData
---@field slotId number Inventory slot ID (13 or 14).
---@field itemId number Item ID.
---@field texture string|number Icon texture.
---@field spellId number On-use spell ID.

---@class ECM_TrinketIcon : Button
---@field slotId number Inventory slot ID this icon represents.
---@field Icon Texture The icon texture.
---@field Cooldown Cooldown The cooldown overlay frame.

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Checks if a trinket slot has an on-use effect.
---@param slotId number Inventory slot ID (13 or 14).
---@return ECM_TrinketData|nil trinketData Trinket data if on-use, nil otherwise.
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
        slotId = slotId,
        itemId = itemId,
        texture = texture,
        spellId = spellId,
    }
end

--- Returns a table of usable trinkets (those with on-use effects).
---@param moduleConfig table Module configuration.
---@return ECM_TrinketData[] trinkets Array of trinket data.
local function GetUsableTrinkets(moduleConfig)
    local trinkets = {}

    if moduleConfig.showTrinket1 then
        local data = GetTrinketData(C.TRINKET_SLOT_1)
        if data then
            trinkets[#trinkets + 1] = data
        end
    end

    if moduleConfig.showTrinket2 then
        local data = GetTrinketData(C.TRINKET_SLOT_2)
        if data then
            trinkets[#trinkets + 1] = data
        end
    end

    return trinkets
end

--- Creates a single trinket icon frame styled like cooldown viewer icons.
---@param parent Frame Parent frame to attach to.
---@param size number Icon size in pixels.
---@return ECM_TrinketIcon icon The created icon frame.
local function CreateTrinketIcon(parent, size)
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
    icon.Border:SetSize(size * C.TRINKET_ICON_BORDER_SCALE, size * C.TRINKET_ICON_BORDER_SCALE)

    -- Shadow overlay
    icon.Shadow = icon:CreateTexture(nil, "OVERLAY")
    icon.Shadow:SetAtlas("UI-CooldownManager-OORshadow")
    icon.Shadow:SetAllPoints()
    icon.Shadow:Hide() -- Only show when out of range (optional)

    return icon
end

--- Updates the cooldown display on a trinket icon.
---@param icon ECM_TrinketIcon The icon to update.
---@param slotId number The inventory slot ID.
local function UpdateIconCooldown(icon, slotId)
    local start, duration, enable = GetInventoryItemCooldown("player", slotId)
    if enable == 1 and duration > 0 then
        icon.Cooldown:SetCooldown(start, duration)
    else
        icon.Cooldown:Clear()
    end
end

--- Restores UtilityCooldownViewer to its original position.
---@param self ECM_TrinketIconsModule The module instance.
local function RestoreViewerPosition(self)
    if not self._viewerOriginalPoint then
        return
    end

    local utilityViewer = _G[C.VIEWER_UTILITY]
    if not utilityViewer then
        return
    end

    local orig = self._viewerOriginalPoint
    utilityViewer:ClearAllPoints()
    utilityViewer:SetPoint(orig[1], orig[2], orig[3], orig[4], orig[5])
end

--- Gets the icon size, spacing, and scale from UtilityCooldownViewer.
--- Falls back to defaults if viewer is unavailable.
--- Measures actual icon frames to respect Edit Mode settings.
--- Returns base (unscaled) sizes - caller should apply scale separately.
---@return number iconSize The base icon size in pixels (unscaled).
---@return number spacing The base spacing between icons in pixels (unscaled).
---@return number scale The viewer's scale factor from Edit Mode.
local function GetUtilityViewerLayout()
    local viewer = _G[C.VIEWER_UTILITY]
    if not viewer or not viewer:IsShown() then
        return C.DEFAULT_TRINKET_ICON_SIZE, C.DEFAULT_TRINKET_ICON_SPACING, 1.0
    end

    -- Get the viewer's scale (affected by Edit Mode "Icon Size" setting)
    local viewerScale = viewer:GetScale() or 1.0

    local children = { viewer:GetChildren() }
    local iconSize = nil
    local spacing = C.DEFAULT_TRINKET_ICON_SPACING

    -- Find first visible icon to get size (this is the scaled size)
    for _, child in ipairs(children) do
        if child and child:IsShown() then
            local size = child:GetWidth()
            if size and size > 0 then
                -- Divide by scale to get the base size
                iconSize = size / viewerScale
                break
            end
        end
    end

    -- Calculate spacing by measuring gap between first two icons
    if #children >= 2 then
        local child1 = children[1]
        local child2 = children[2]
        if child1 and child2 and child1:IsShown() and child2:IsShown() then
            local left1 = child1:GetLeft()
            local left2 = child2:GetLeft()
            local width1 = child1:GetWidth()
            if left1 and left2 and width1 then
                -- Gap is in screen coordinates, so divide by scale to get base spacing
                local gap = (left2 - (left1 + width1)) / viewerScale
                if gap > 0 then
                    spacing = gap
                end
            end
        end
    end

    return iconSize or C.DEFAULT_TRINKET_ICON_SIZE, spacing, viewerScale
end

--------------------------------------------------------------------------------
-- ECMFrame Overrides
--------------------------------------------------------------------------------

--- Override CreateFrame to create the container for trinket icons.
---@return Frame container The container frame.
function TrinketIcons:CreateFrame()
    local frame = CreateFrame("Frame", "ECMTrinketIcons", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1) -- Will be resized in UpdateLayout

    -- Pool of icon frames (pre-allocate for both trinket slots)
    frame._iconPool = {}
    local initialSize = C.DEFAULT_TRINKET_ICON_SIZE
    for i = 1, 2 do
        frame._iconPool[i] = CreateTrinketIcon(frame, initialSize)
    end

    return frame
end

--- Override ShouldShow to check module enabled state and trinket availability.
---@return boolean shouldShow Whether the frame should be shown.
function TrinketIcons:ShouldShow()
    if not ECMFrame.ShouldShow(self) then
        return false
    end

    -- Also hide if UtilityCooldownViewer is not visible
    local utilityViewer = _G[C.VIEWER_UTILITY]
    if not utilityViewer or not utilityViewer:IsShown() then
        return false
    end

    return true
end

--- Override UpdateLayout to position icons relative to UtilityCooldownViewer.
---@return boolean success Whether the layout was applied.
function TrinketIcons:UpdateLayout()
    local frame = self.InnerFrame
    if not frame then
        return false
    end

    local moduleConfig = self.ModuleConfig
    if not moduleConfig then
        return false
    end

    -- Check visibility
    if not self:ShouldShow() then
        frame:Hide()
        return false
    end

    local utilityViewer = _G[C.VIEWER_UTILITY]
    if not utilityViewer then
        frame:Hide()
        return false
    end

    -- Get usable trinkets
    local trinkets = GetUsableTrinkets(moduleConfig)
    local numTrinkets = #trinkets
    local iconSize, spacing, viewerScale = GetUtilityViewerLayout()

    -- Apply the same scale as the viewer to match Edit Mode settings
    frame:SetScale(viewerScale)

    -- Hide all existing icons first
    for _, icon in ipairs(frame._iconPool) do
        icon:Hide()
    end

    -- If no trinkets, restore viewer position and hide container
    if numTrinkets == 0 then
        RestoreViewerPosition(self)
        frame:Hide()
        return false
    end

    -- Calculate container size (using base sizes, scale is applied separately)
    local totalWidth = (numTrinkets * iconSize) + ((numTrinkets - 1) * spacing)
    local totalHeight = iconSize
    frame:SetSize(totalWidth, totalHeight)

    -- Calculate offset to keep visual midpoint centered
    -- The trinket container width plus the gap between viewer and first icon
    local trinketContainerWidth = totalWidth + spacing
    local viewerOffsetX = -(trinketContainerWidth / 2)

    -- Store original viewer position on first call, then apply offset
    if not self._viewerOriginalPoint then
        local point, relativeTo, relativePoint, x, y = utilityViewer:GetPoint()
        self._viewerOriginalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end

    local orig = self._viewerOriginalPoint
    utilityViewer:ClearAllPoints()
    utilityViewer:SetPoint(orig[1], orig[2], orig[3], orig[4] + viewerOffsetX, orig[5])

    -- Position and configure each icon
    local xOffset = 0
    for i, trinketData in ipairs(trinkets) do
        local icon = frame._iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * C.TRINKET_ICON_BORDER_SCALE, iconSize * C.TRINKET_ICON_BORDER_SCALE)
        icon.slotId = trinketData.slotId

        -- Set texture (handle nil case if item not loaded)
        if trinketData.texture then
            icon.Icon:SetTexture(trinketData.texture)
        else
            icon.Icon:SetTexture(nil)
        end

        -- Position
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "LEFT", xOffset, 0)
        icon:Show()

        xOffset = xOffset + iconSize + spacing
    end

    -- Position container to the right of UtilityCooldownViewer
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", utilityViewer, "RIGHT", spacing, 0)
    frame:Show()

    Util.Log(self.Name, "TrinketIcons:UpdateLayout", {
        numTrinkets = numTrinkets,
        iconSize = iconSize,
        spacing = spacing,
        totalWidth = totalWidth,
    })

    -- Update cooldowns after layout is complete (CLAUDE.md mandate)
    self:ThrottledRefresh()

    return true
end

--- Override Refresh to update cooldown states.
function TrinketIcons:Refresh()
    if not ECMFrame.Refresh(self) then
        return false
    end

    local frame = self.InnerFrame
    if not frame or not frame:IsShown() then
        return false
    end

    -- Update cooldowns on all visible icons
    for _, icon in ipairs(frame._iconPool) do
        if icon:IsShown() and icon.slotId then
            UpdateIconCooldown(icon, icon.slotId)
        end
    end

    return true
end

--------------------------------------------------------------------------------
-- Event Handlers
--------------------------------------------------------------------------------

function TrinketIcons:OnBagUpdateCooldown()
    self:ThrottledRefresh()
end

function TrinketIcons:OnPlayerEquipmentChanged(_, slotId)
    -- Only update if a trinket slot changed
    if slotId == C.TRINKET_SLOT_1 or slotId == C.TRINKET_SLOT_2 then
        self:ScheduleLayoutUpdate()
    end
end

function TrinketIcons:OnPlayerEnteringWorld()
    self:ScheduleLayoutUpdate()
end

--- Hook the UtilityCooldownViewer to update when it shows/hides or resizes.
function TrinketIcons:HookUtilityViewer()
    local utilityViewer = _G[C.VIEWER_UTILITY]
    if not utilityViewer or self._viewerHooked then
        return
    end

    self._viewerHooked = true

    utilityViewer:HookScript("OnShow", function()
        self:ScheduleLayoutUpdate()
    end)

    utilityViewer:HookScript("OnHide", function()
        RestoreViewerPosition(self)
        if self.InnerFrame then
            self.InnerFrame:Hide()
        end
    end)

    utilityViewer:HookScript("OnSizeChanged", function()
        self:ScheduleLayoutUpdate()
    end)

    Util.Log(self.Name, "Hooked UtilityCooldownViewer")
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function TrinketIcons:OnEnable()
    ECMFrame.AddMixin(self, "TrinketIcons")

    -- Register events
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "OnBagUpdateCooldown")
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnPlayerEquipmentChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- Hook the utility viewer after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookUtilityViewer()
        self:ScheduleLayoutUpdate()
    end)

    Util.Log(self.Name, "OnEnable - module enabled")
end

function TrinketIcons:OnDisable()
    self:UnregisterAllEvents()

    RestoreViewerPosition(self)

    if self.InnerFrame then
        self.InnerFrame:Hide()
    end

    Util.Log(self.Name, "Disabled")
end
