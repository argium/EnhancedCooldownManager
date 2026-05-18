-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local BarMixin = ns.BarMixin
local FrameUtil = ns.FrameUtil
local ExtraIcons = ns.Addon:NewModule("ExtraIcons")
ns.Addon.ExtraIcons = ExtraIcons

local BUILTIN_STACKS = ns.Constants.BUILTIN_STACKS
local RACIAL_SPELL_ALIASES = ns.Constants.RACIAL_SPELL_ALIASES
local DEFAULT_SIZE = ns.Constants.DEFAULT_EXTRA_ICON_SIZE
local MAIN_BORDER_SCALE = ns.Constants.EXTRA_ICON_MAIN_BORDER_SCALE
local UTILITY_BORDER_SCALE = ns.Constants.EXTRA_ICON_UTILITY_BORDER_SCALE
local canAccessTable = _G.canaccesstable

local MAIN_VIEWER_KEY = "EssentialCooldownViewer"
local UTILITY_VIEWER_KEY = "UtilityCooldownViewer"
local VIEWERS = {
    { key = "main", blizzKey = MAIN_VIEWER_KEY, borderScale = { MAIN_BORDER_SCALE, MAIN_BORDER_SCALE }, ownsAnchor = true },
    -- Utility icon frames render square; keep the overlay square so extras do not look short.
    { key = "utility", blizzKey = UTILITY_VIEWER_KEY, borderScale = { UTILITY_BORDER_SCALE, UTILITY_BORDER_SCALE } },
}

--------------------------------------------------------------------------------
-- Shared horizontal centering
--------------------------------------------------------------------------------

local function cachePoint(vs, blizzFrame)
    if vs.originalPoint or not blizzFrame then return end
    local point, relativeTo, relativePoint, x, y = blizzFrame:GetPoint()
    vs.originalPoint = { point, relativeTo, relativePoint, x or 0, y or 0 }
end

local function updateMainViewerAnchor(vs, blizzFrame, rightFrame)
    local anchor = vs and vs.anchorFrame
    if not anchor then return end

    if not blizzFrame or not blizzFrame:IsShown() then
        anchor:Hide()
        return
    end

    local right = rightFrame and rightFrame:IsShown() and rightFrame or blizzFrame
    anchor:ClearAllPoints()
    anchor:SetPoint("LEFT", blizzFrame, "LEFT", 0, 0)
    anchor:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    anchor:SetPoint("TOP", blizzFrame, "TOP", 0, 0)
    anchor:SetPoint("BOTTOM", blizzFrame, "BOTTOM", 0, 0)
    anchor:Show()
end

--------------------------------------------------------------------------------
-- Entry resolution
--------------------------------------------------------------------------------

local function getEquipSlotIconData(slotId)
    local itemId = GetInventoryItemID("player", slotId)
    if not itemId then return nil end
    local _, spellId = C_Item.GetItemSpell(itemId)
    if not spellId then return nil end
    local texture = GetInventoryItemTexture("player", slotId)
    if not texture then return nil end
    return { itemId = itemId, texture = texture, slotId = slotId }
end

local function resolveFirstItem(ids, showIfMissing)
    local missingData

    for _, entry in ipairs(ids) do
        local itemId = entry.itemID or entry.itemId
        if itemId and C_Item.GetItemCount(itemId) > 0 then
            local texture = C_Item.GetItemIconByID(itemId)
            if texture then return { itemId = itemId, texture = texture } end
        elseif itemId and showIfMissing and not missingData then
            local texture = C_Item.GetItemIconByID(itemId)
            if texture then missingData = { itemId = itemId, texture = texture, missing = true } end
        end
    end

    return missingData
end

local function getKnownSpellData(spellId)
    if spellId and C_SpellBook.IsSpellKnown(spellId) then
        local texture = C_Spell.GetSpellTexture(spellId)
        if texture then return { spellId = spellId, texture = texture } end
    end
end

local function resolveFirstKnownSpell(ids)
    for _, entry in ipairs(ids) do
        local spellId = type(entry) == "table" and entry.spellId or entry
        local data = getKnownSpellData(spellId)
        if data then return data end

        local aliases = RACIAL_SPELL_ALIASES[spellId]
        if aliases then
            for _, aliasSpellId in ipairs(aliases) do
                if aliasSpellId ~= spellId then
                    data = getKnownSpellData(aliasSpellId)
                    if data then return data end
                end
            end
        end
    end
end

local function shouldShowItemStack(itemStack)
    if not itemStack then return false end
    local hiddenInRatedPvp = itemStack.hideInRatedPvp and C_PvP.IsRatedMap()
    local inInstance, instanceType = IsInInstance()
    local hiddenInInstance = itemStack.hideInInstances and inInstance and instanceType ~= "pvp" and instanceType ~= "arena"
    return not hiddenInRatedPvp and not hiddenInInstance
end

local function getConfiguredItemStackData(entry, moduleConfig)
    local itemStacks = moduleConfig and moduleConfig.itemStacks
    local itemStack = itemStacks and itemStacks.byId and itemStacks.byId[entry.itemStackId]
    return shouldShowItemStack(itemStack)
        and itemStack.ids
        and resolveFirstItem(itemStack.ids, itemStack.showIfMissing == true)
        or nil
end

local function resolveEntry(entry, moduleConfig)
    local kind, slotId, ids
    if entry.stackKey then
        local stack = BUILTIN_STACKS[entry.stackKey]
        if not stack then return nil end
        kind, slotId, ids = stack.kind, stack.slotId, stack.ids
    else
        kind, slotId, ids = entry.kind, entry.slotId, entry.ids
    end
    if kind == "equipSlot" then return getEquipSlotIconData(slotId) end
    if kind == "item" then return ids and resolveFirstItem(ids) end
    if kind == "itemStack" then return getConfiguredItemStackData(entry, moduleConfig) end
    if kind == "spell" then return ids and resolveFirstKnownSpell(ids) end
end

local _resolved = {}
local function resolveEntries(entries, moduleConfig)
    wipe(_resolved)
    for _, entry in ipairs(entries) do
        local data = not entry.disabled and resolveEntry(entry, moduleConfig) or nil
        if data then _resolved[#_resolved + 1] = data end
    end
    return _resolved
end

--------------------------------------------------------------------------------
-- Icon creation and cooldown
--------------------------------------------------------------------------------

local function createIcon(parent, size, borderScale)
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
    icon.Border:SetSize(size * borderScale[1], size * borderScale[2])

    icon.Count = icon:CreateFontString(nil, "OVERLAY")
    icon.Count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -2, 2)
    icon.Count:SetJustifyH("RIGHT")
    icon.Count:SetJustifyV("BOTTOM")
    icon.Count:Hide()

    icon.Shadow = icon:CreateTexture(nil, "OVERLAY")
    icon.Shadow:SetAtlas("UI-CooldownManager-OORshadow")
    icon.Shadow:SetAllPoints()
    icon.Shadow:Hide()

    return icon
end

local function updateIconCooldown(icon)
    if icon.spellId then
        local cdInfo = C_Spell.GetSpellCooldown(icon.spellId)
        if cdInfo and cdInfo.isOnGCD then
            icon.Cooldown:SetCooldown(0, 0)
            return
        end
        -- Charge spells: per-charge timer so the icon shows ready while
        -- charges remain. Single-charge spells report zero-span here.
        local charges = C_Spell.GetSpellCharges(icon.spellId)
        local isCharge = charges and charges.maxCharges and charges.maxCharges > 1
        local durObj = isCharge
            and C_Spell.GetSpellChargeDuration(icon.spellId)
            or C_Spell.GetSpellCooldownDuration(icon.spellId)
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

local function applyIconCountText(icon, text)
    if text ~= nil then
        icon.Count:SetText(tostring(text))
        icon.Count:Show()
    else
        icon.Count:SetText(nil)
        icon.Count:Hide()
    end
end

local function updateIconCountText(icon, globalConfig, config)
    if not icon.Count then return end
    FrameUtil.ApplyFont(icon.Count, globalConfig, config)

    if icon.itemId and (not config or config.showStackCount ~= false) then
        local count = C_Item.GetItemCount(icon.itemId)
        if count and count > 1 then
            applyIconCountText(icon, count)
            return
        end
    end

    if icon.spellId and (not config or config.showCharges ~= false) then
        local charges = C_Spell.GetSpellCharges(icon.spellId)
        if charges and charges.maxCharges and charges.maxCharges > 1 and charges.currentCharges ~= nil then
            applyIconCountText(icon, charges.currentCharges)
            return
        end
    end

    applyIconCountText(icon, nil)
end

local function getItemFramesCount(itemFrames)
    if type(itemFrames) ~= "table" or not canAccessTable(itemFrames) then
        return nil
    end

    local count = 0
    local ok = pcall(function()
        for index in ipairs(itemFrames) do
            count = index
        end
    end)
    return ok and count or nil
end

local function getViewerDiagnostics(blizzFrame, viewerConfig, why, itemFrames)
    local itemFramesAccessible = nil
    if type(itemFrames) == "table" then
        itemFramesAccessible = canAccessTable(itemFrames)
    end

    return {
        viewerKey = viewerConfig.key,
        blizzardFrameKey = viewerConfig.blizzKey,
        reason = why,
        viewerExists = blizzFrame ~= nil,
        viewerName = ns.GetFrameValue(blizzFrame, "GetName"),
        viewerShown = ns.GetFrameValue(blizzFrame, "IsShown"),
        viewerWidth = ns.GetFrameValue(blizzFrame, "GetWidth"),
        viewerHeight = ns.GetFrameValue(blizzFrame, "GetHeight"),
        viewerAlpha = ns.GetFrameValue(blizzFrame, "GetAlpha"),
        viewerNumPoints = ns.GetFrameValue(blizzFrame, "GetNumPoints"),
        viewerIconScale = blizzFrame and blizzFrame.iconScale or nil,
        viewerChildXPadding = blizzFrame and blizzFrame.childXPadding or nil,
        viewerHasGetItemFrames = blizzFrame ~= nil and type(blizzFrame.GetItemFrames) == "function",
        itemFramesType = type(itemFrames),
        itemFramesAccessible = itemFramesAccessible,
        itemFramesArrayCount = getItemFramesCount(itemFrames),
    }
end

local function getAccessibleItemFrames(blizzFrame, viewerConfig, why)
    local ok, itemFrames = pcall(blizzFrame.GetItemFrames, blizzFrame)
    if not ok then
        local data = getViewerDiagnostics(blizzFrame, viewerConfig, why, nil)
        data.error = tostring(itemFrames)
        ns.ErrorLogOnce("ExtraIcons", "GetItemFrames:" .. viewerConfig.key,
            "Unable to read cooldown viewer item frames for " .. viewerConfig.key .. " during "
            .. tostring(why or "unknown") .. ": " .. tostring(itemFrames), data)
        return nil
    end

    if type(itemFrames) ~= "table" then
        return nil
    end

    if not canAccessTable(itemFrames) then
        ns.ErrorLogOnce("ExtraIcons", "InaccessibleItemFrames:" .. viewerConfig.key,
            "Cooldown viewer item frames are inaccessible for " .. viewerConfig.key .. " during "
            .. tostring(why or "unknown"), getViewerDiagnostics(blizzFrame, viewerConfig, why, itemFrames))
        return nil
    end

    return itemFrames
end

--------------------------------------------------------------------------------
-- Module methods
--------------------------------------------------------------------------------

function ExtraIcons:CreateFrame()
    local parent = CreateFrame("Frame", "ECMExtraIcons", UIParent)
    parent:SetFrameStrata("MEDIUM")
    parent:SetSize(1, 1)

    self._viewers = {}
    for _, v in ipairs(VIEWERS) do
        local container = CreateFrame("Frame", "ECMExtraIcons_" .. v.key, parent)
        container:SetFrameStrata("MEDIUM")
        container:SetSize(1, 1)

        local anchor
        if v.ownsAnchor then
            anchor = CreateFrame("Frame", "ECMExtraIcons_" .. v.key .. "Anchor", parent)
            anchor:SetFrameStrata("MEDIUM")
            anchor:SetSize(1, 1)
            anchor:Hide()
        end

        self._viewers[v.key] = {
            anchorFrame = anchor,
            container = container,
            iconPool = {},
            originalPoint = nil,
            hooked = false,
        }
    end

    return parent
end

function ExtraIcons:ShouldShow()
    if not BarMixin.FrameProto.ShouldShow(self) then return false end
    for _, v in ipairs(VIEWERS) do
        local frame = _G[v.blizzKey]
        if frame and frame:IsShown() then return true end
    end
    return false
end

--- Returns the logical anchor frame used by chained ECM modules so they
--- inherit the combined width of Blizzard icons plus appended extra icons.
function ExtraIcons:GetMainViewerAnchor()
    local vs = self._viewers and self._viewers.main
    local anchor = vs and vs.anchorFrame
    if anchor and anchor:IsShown() then return anchor end
    return _G[MAIN_VIEWER_KEY]
end

function ExtraIcons:_updateSingleViewer(viewerConfig, entries, isEditing, moduleConfig, why)
    local blizzFrame = _G[viewerConfig.blizzKey]
    local vs = self._viewers[viewerConfig.key]
    if not vs then return false end
    local container = vs.container
    cachePoint(vs, blizzFrame)

    local items = (not blizzFrame or not blizzFrame:IsShown() or isEditing or #entries == 0)
        and {} or resolveEntries(entries, moduleConfig)

    if #items == 0 then
        local p = vs.originalPoint
        if p and blizzFrame then
            FrameUtil.LazySetAnchors(blizzFrame, { { p[1], p[2], p[3], p[4], p[5] } })
        end
        if isEditing then vs.originalPoint = nil end
        container:Hide()
        if viewerConfig.ownsAnchor then updateMainViewerAnchor(vs, blizzFrame, nil) end
        return false
    end

    for _, icon in ipairs(vs.iconPool) do icon:Hide() end
    for i = #vs.iconPool + 1, #items do
        vs.iconPool[i] = createIcon(container, DEFAULT_SIZE, viewerConfig.borderScale)
    end

    local globalConfig = self:GetGlobalConfig()
    local iconSize = DEFAULT_SIZE
    local viewerScale = blizzFrame.iconScale or 1.0
    local spacing = blizzFrame.childXPadding or 0
    local lastActive = nil

    local itemFrames = getAccessibleItemFrames(blizzFrame, viewerConfig, why)
    if itemFrames then
        local ok, err = pcall(function()
            for _, itemFrame in ipairs(itemFrames) do
                if itemFrame.isActive then
                    iconSize = itemFrame:GetWidth() or iconSize
                    if itemFrame:IsShown() then lastActive = itemFrame end
                end
            end
        end)
        if not ok then
            iconSize = DEFAULT_SIZE
            lastActive = nil
            local data = getViewerDiagnostics(blizzFrame, viewerConfig, why, itemFrames)
            data.error = tostring(err)
            ns.ErrorLogOnce("ExtraIcons", "IterateItemFrames:" .. viewerConfig.key,
                "Unable to iterate cooldown viewer item frames for " .. viewerConfig.key .. " during "
                .. tostring(why or "unknown") .. ": " .. tostring(err), data)
        end
    end

    container:SetScale(viewerScale)

    local totalWidth = #items * iconSize + (#items - 1) * spacing
    container:SetSize(totalWidth, iconSize)

    -- Shift the Blizzard viewer left to keep the combined group centred.
    -- The Blizzard frame auto-sizes to its scaled active icons, so its
    -- on-screen centre already coincides with the original anchor; we only
    -- need to absorb the on-screen width of the gap + extra group.
    local extraOnScreen = (spacing + totalWidth) * viewerScale
    local p = vs.originalPoint
    if p and blizzFrame then
        FrameUtil.LazySetAnchors(blizzFrame, { { p[1], p[2], p[3], p[4] - extraOnScreen / 2, p[5] } })
    end

    local xOffset = 0
    for i, data in ipairs(items) do
        local icon = vs.iconPool[i]
        icon:SetSize(iconSize, iconSize)
        icon.Icon:SetSize(iconSize, iconSize)
        icon.Mask:SetSize(iconSize, iconSize)
        icon.Border:SetSize(iconSize * viewerConfig.borderScale[1], iconSize * viewerConfig.borderScale[2])
        icon.slotId = data.slotId
        icon.itemId = data.itemId
        icon.spellId = data.spellId

        icon.Icon:SetTexture(data.texture)
        icon.Icon:SetDesaturated(data.missing == true)
        FrameUtil.LazySetAnchors(icon, { { "LEFT", container, "LEFT", xOffset, 0 } })
        icon:Show()

        updateIconCooldown(icon)
        updateIconCountText(icon, globalConfig, moduleConfig)

        xOffset = xOffset + iconSize + spacing
    end

    FrameUtil.LazySetAnchors(container, { { "LEFT", lastActive or blizzFrame, "RIGHT", spacing, 0 } })
    container:Show()

    if viewerConfig.ownsAnchor then updateMainViewerAnchor(vs, blizzFrame, container) end
    return true
end

function ExtraIcons:UpdateLayout(why)
    if not self.InnerFrame or not self._viewers then return false end

    local shouldShow = self:ShouldShow()
    local moduleConfig = self:GetModuleConfig()
    local isEditing = self._isEditModeActive
    if isEditing == nil then
        local mgr = _G.EditModeManagerFrame
        isEditing = mgr and mgr:IsShown() or false
    end

    -- When hidden, leave viewers nil so each call gets empty entries, which
    -- restores Blizzard viewer positions and hides extra-icon containers.
    local viewers = shouldShow and moduleConfig and moduleConfig.viewers
    local anyPlaced = false

    for _, v in ipairs(VIEWERS) do
        local entries = viewers and viewers[v.key] or {}
        if self:_updateSingleViewer(v, entries, isEditing, moduleConfig, why) then
            anyPlaced = true
        end
    end

    -- ApplyFramePosition is bypassed because UpdateLayout is overridden, so
    -- manage InnerFrame visibility here.
    if shouldShow then
        if not self.InnerFrame:IsShown() then self.InnerFrame:Show() end
    else
        self.InnerFrame:Hide()
    end

    if anyPlaced then
        ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")")
        self:ThrottledRefresh("UpdateLayout")
    end

    return anyPlaced
end

function ExtraIcons:Refresh(why, force)
    if not BarMixin.FrameProto.Refresh(self, why, force) then return false end
    if not self._viewers then return false end

    local refreshed = false
    local moduleConfig = self.GetModuleConfig and self:GetModuleConfig() or nil
    local globalConfig = self:GetGlobalConfig()
    for _, vs in pairs(self._viewers) do
        if vs.container and vs.container:IsShown() then
            for _, icon in ipairs(vs.iconPool) do
                if icon:IsShown() and (icon.slotId or icon.itemId or icon.spellId) then
                    updateIconCooldown(icon)
                    updateIconCountText(icon, globalConfig, moduleConfig)
                end
            end
            refreshed = true
        end
    end
    if refreshed then
        ns.Log(self.Name, "Refresh complete (" .. (why or "") .. ")")
    end
    return refreshed
end

--------------------------------------------------------------------------------
-- Events and hooks
--------------------------------------------------------------------------------

function ExtraIcons:OnBagUpdateCooldown()
    self:ThrottledRefresh("OnBagUpdateCooldown")
end

function ExtraIcons:OnBagUpdateDelayed()
    ns.Runtime.RequestLayout("ExtraIcons:OnBagUpdateDelayed")
end

function ExtraIcons:OnPlayerEquipmentChanged(slotId)
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

--- Rebuilds the set of equipment slots referenced by current config.
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
                    if kind == "equipSlot" and sid then tracked[sid] = true end
                end
            end
        end
    end
    self._trackedEquipSlots = tracked
end

function ExtraIcons:HookEditMode()
    local mgr = _G.EditModeManagerFrame
    if not mgr or self._editModeHooked then return end
    self._editModeHooked = true
    self._isEditModeActive = mgr:IsShown()

    mgr:HookScript("OnShow", function()
        if not self:IsEnabled() then
            return
        end
        self._isEditModeActive = true
        if self._viewers then
            for _, vs in pairs(self._viewers) do vs.container:Hide() end
        end
        ns.Runtime.RequestLayout("ExtraIcons:EnterEditMode")
    end)

    mgr:HookScript("OnHide", function()
        if not self:IsEnabled() then
            return
        end
        self._isEditModeActive = false
        ns.Runtime.RequestLayout("ExtraIcons:ExitEditMode")
    end)
end

function ExtraIcons:_hookViewer(viewerConfig)
    local blizzFrame = _G[viewerConfig.blizzKey]
    local vs = self._viewers and self._viewers[viewerConfig.key]
    if not blizzFrame or not vs or vs.hooked then return end
    vs.hooked = true

    blizzFrame:HookScript("OnShow", function()
        if not self:IsEnabled() then
            return
        end
        ns.Runtime.RequestLayout("ExtraIcons:OnShow")
    end)
    blizzFrame:HookScript("OnHide", function()
        if not self:IsEnabled() then
            return
        end
        if vs.container then vs.container:Hide() end
        if vs.anchorFrame then vs.anchorFrame:Hide() end
        ns.Runtime.RequestLayout("ExtraIcons:OnHide")
    end)
    blizzFrame:HookScript("OnSizeChanged", function()
        if not self:IsEnabled() then
            return
        end
        ns.Runtime.RequestLayout("ExtraIcons:OnSizeChanged")
    end)

    ns.Log(self.Name, "Hooked " .. viewerConfig.blizzKey)
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

    self:RegisterEvent("BAG_UPDATE_COOLDOWN", function() self:OnBagUpdateCooldown() end)
    self:RegisterEvent("BAG_UPDATE_DELAYED", function() self:OnBagUpdateDelayed() end)
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function(_, slotId) self:OnPlayerEquipmentChanged(slotId) end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:OnPlayerEnteringWorld() end)
    self:RegisterEvent("SPELLS_CHANGED", function() self:OnSpellsChanged() end)
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", function()
        self:ThrottledRefresh("OnSpellUpdateCooldown")
    end)

    -- Hook viewers after a short delay to ensure Blizzard frames are loaded.
    C_Timer.After(0.1, function()
        if not self:IsEnabled() then
            return
        end

        self:HookEditMode()
        for _, v in ipairs(VIEWERS) do self:_hookViewer(v) end
        ns.Runtime.RequestLayout("ExtraIcons:OnEnable")
    end)
end

function ExtraIcons:OnDisable()
    self:UnregisterAllEvents()
    self:UpdateLayout("OnDisable")
    ns.Runtime.UnregisterFrame(self)

    if self._viewers then
        for _, vs in pairs(self._viewers) do vs.originalPoint = nil end
    end
    self._isEditModeActive = nil
    self._trackedEquipSlots = nil
end
