local _, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

---@class ECM_ProcOverlayModule
local ProcOverlay = EnhancedCooldownManager:NewModule("ProcOverlay", "AceEvent-3.0")
EnhancedCooldownManager.ProcOverlay = ProcOverlay

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local BUFF_ICON_VIEWER_NAME = "BuffIconCooldownViewer"
local ESSENTIAL_VIEWER_NAME = "EssentialCooldownViewer"

--------------------------------------------------------------------------------
-- Mapping Storage Helpers
--------------------------------------------------------------------------------

--- Returns current class ID and spec ID.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    return classID, specID
end

--- Ensures nested mapping storage exists.
---@param profile table
local function EnsureMappingStorage(profile)
    if not profile.procOverlay then
        profile.procOverlay = { enabled = false, mappings = {} }
    end
    if not profile.procOverlay.mappings then
        profile.procOverlay.mappings = {}
    end
end

--- Gets the mapping for a buff icon index.
---@param buffIconIndex number
---@return number|nil targetIconIndex
function ProcOverlay:GetMapping(buffIconIndex)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then return nil end
    
    EnsureMappingStorage(profile)
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then return nil end
    
    local mappings = profile.procOverlay.mappings
    return mappings[classID] and mappings[classID][specID] and mappings[classID][specID][buffIconIndex]
end

--- Sets a mapping for a buff icon to a target icon.
---@param buffIconIndex number
---@param targetIconIndex number|nil (nil to clear)
---@return boolean success
function ProcOverlay:SetMapping(buffIconIndex, targetIconIndex)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then return false end
    
    EnsureMappingStorage(profile)
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then return false end
    
    local mappings = profile.procOverlay.mappings
    if not mappings[classID] then mappings[classID] = {} end
    if not mappings[classID][specID] then mappings[classID][specID] = {} end
    
    -- Validate one-buff-per-target constraint (unless clearing)
    if targetIconIndex then
        for idx, target in pairs(mappings[classID][specID]) do
            if idx ~= buffIconIndex and target == targetIconIndex then
                return false -- Target already mapped
            end
        end
    end
    
    mappings[classID][specID][buffIconIndex] = targetIconIndex
    self:UpdateLayout()
    return true
end

--- Gets all mappings for current spec.
---@return table<number, number> [buffIconIndex] = targetIconIndex
function ProcOverlay:GetAllMappings()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then return {} end
    
    EnsureMappingStorage(profile)
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then return {} end
    
    local mappings = profile.procOverlay.mappings
    return mappings[classID] and mappings[classID][specID] or {}
end

--- Clears all mappings for current spec.
function ProcOverlay:ClearAllMappings()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then return end
    
    EnsureMappingStorage(profile)
    local classID, specID = GetCurrentClassSpec()
    if not classID or not specID then return end
    
    local mappings = profile.procOverlay.mappings
    if mappings[classID] and mappings[classID][specID] then
        wipe(mappings[classID][specID])
    end
    
    self:UpdateLayout()
end

--------------------------------------------------------------------------------
-- Icon Tracking Helpers
--------------------------------------------------------------------------------

--- Returns array of visible icon frames from a viewer.
---@param viewerName string
---@return table<number, Frame> [index] = iconFrame
local function GetVisibleIcons(viewerName)
    local viewer = _G[viewerName]
    if not viewer then
        return {}
    end

    local icons = {}
    for _, child in ipairs({ viewer:GetChildren() }) do
        if child and child:IsShown() then
            table.insert(icons, child)
        end
    end
    return icons
end

--- Returns array of visible icon frames from BuffIconCooldownViewer.
---@return table<number, Frame>
function ProcOverlay:GetBuffIcons()
    return GetVisibleIcons(BUFF_ICON_VIEWER_NAME)
end

--- Returns array of visible icon frames from EssentialCooldownViewer.
---@return table<number, Frame>
function ProcOverlay:GetTargetIcons()
    return GetVisibleIcons(ESSENTIAL_VIEWER_NAME)
end

--- Returns a specific target icon by index.
---@param index number
---@return Frame|nil
function ProcOverlay:GetTargetIconByIndex(index)
    local icons = self:GetTargetIcons()
    return icons[index]
end

--------------------------------------------------------------------------------
-- Overlay Frame Management
--------------------------------------------------------------------------------

-- Track original state of buff icons we've modified
local _modifiedIcons = {} -- [buffIconFrame] = { originalParent, originalStrata, originalLevel, originalPoints }

--- Stores original state of a buff icon before modifying it.
---@param buffIcon Frame
local function StoreOriginalState(buffIcon)
    if _modifiedIcons[buffIcon] then
        return -- Already stored
    end
    
    local points = {}
    for i = 1, buffIcon:GetNumPoints() do
        local point, relativeTo, relativePoint, xOfs, yOfs = buffIcon:GetPoint(i)
        points[i] = { point, relativeTo, relativePoint, xOfs, yOfs }
    end
    
    _modifiedIcons[buffIcon] = {
        originalParent = buffIcon:GetParent(),
        originalStrata = buffIcon:GetFrameStrata(),
        originalLevel = buffIcon:GetFrameLevel(),
        originalWidth = buffIcon:GetWidth(),
        originalHeight = buffIcon:GetHeight(),
        originalPoints = points,
    }
end

--- Restores a buff icon to its original state.
---@param buffIcon Frame
local function RestoreOriginalState(buffIcon)
    local state = _modifiedIcons[buffIcon]
    if not state then
        return
    end

    buffIcon:ClearAllPoints()

    -- Restore original points
    for _, pointData in ipairs(state.originalPoints) do
        local point, relativeTo, relativePoint, xOfs, yOfs = unpack(pointData)
        if point and relativeTo then
            buffIcon:SetPoint(point, relativeTo, relativePoint or point, xOfs or 0, yOfs or 0)
        end
    end

    -- Restore size, strata, and level
    if state.originalWidth and state.originalHeight then
        buffIcon:SetSize(state.originalWidth, state.originalHeight)
    end
    if state.originalStrata then
        buffIcon:SetFrameStrata(state.originalStrata)
    end
    if state.originalLevel then
        buffIcon:SetFrameLevel(state.originalLevel)
    end

    _modifiedIcons[buffIcon] = nil
end

--- Positions a buff icon to overlay a target icon.
---@param buffIcon Frame
---@param targetIcon Frame
local function PositionOverlay(buffIcon, targetIcon)
    StoreOriginalState(buffIcon)
    
    -- Get target icon size
    local width, height = targetIcon:GetSize()
    if not width or not height or width <= 0 or height <= 0 then
        width = targetIcon:GetWidth() or 32
        height = targetIcon:GetHeight() or 32
    end
    
    -- Reposition buff icon to overlay target
    buffIcon:ClearAllPoints()
    buffIcon:SetPoint("CENTER", targetIcon, "CENTER", 0, 0)
    buffIcon:SetSize(width, height)
    
    -- Ensure always on top
    buffIcon:SetFrameStrata("HIGH")
    buffIcon:SetFrameLevel(targetIcon:GetFrameLevel() + 10)
    
    buffIcon.__ecmProcOverlayActive = true
end

--------------------------------------------------------------------------------
-- Hook Management
--------------------------------------------------------------------------------

local _hookedViewer = false
local _hookedIcons = {} -- [buffIcon] = true

--- Hooks a buff icon for visibility changes.
---@param buffIcon Frame
---@param index number
local function HookBuffIcon(buffIcon, index)
    if _hookedIcons[buffIcon] then
        return
    end
    _hookedIcons[buffIcon] = true
    
    buffIcon:HookScript("OnShow", function()
        ProcOverlay:OnBuffIconShow(buffIcon, index)
    end)
    
    buffIcon:HookScript("OnHide", function()
        ProcOverlay:OnBuffIconHide(buffIcon)
    end)
end

--- Called when a buff icon becomes visible.
---@param buffIcon Frame
---@param buffIconIndex number
function ProcOverlay:OnBuffIconShow(buffIcon, buffIconIndex)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile or not profile.procOverlay or not profile.procOverlay.enabled then
        return
    end
    
    -- Get mapping for this buff icon
    local targetIconIndex = self:GetMapping(buffIconIndex)
    if not targetIconIndex then
        return
    end
    
    -- Get target icon
    local targetIcon = self:GetTargetIconByIndex(targetIconIndex)
    if not targetIcon then
        Util.Log("ProcOverlay", "Target icon not found", { buffIconIndex = buffIconIndex, targetIconIndex = targetIconIndex })
        return
    end
    
    PositionOverlay(buffIcon, targetIcon)
    Util.Log("ProcOverlay", "Applied overlay", { buffIconIndex = buffIconIndex, targetIconIndex = targetIconIndex })
end

--- Called when a buff icon is hidden.
---@param buffIcon Frame
function ProcOverlay:OnBuffIconHide(buffIcon)
    if buffIcon.__ecmProcOverlayActive then
        RestoreOriginalState(buffIcon)
        buffIcon.__ecmProcOverlayActive = nil
        Util.Log("ProcOverlay", "Cleared overlay")
    end
end

--- Hooks the BuffIconCooldownViewer and its children.
function ProcOverlay:HookViewer()
    local viewer = _G[BUFF_ICON_VIEWER_NAME]
    if not viewer then
        Util.Log("ProcOverlay", "BuffIconCooldownViewer not found")
        return
    end
    
    if _hookedViewer then
        return
    end
    _hookedViewer = true
    
    -- Hook existing children
    local buffIcons = self:GetBuffIcons()
    for index, buffIcon in ipairs(buffIcons) do
        HookBuffIcon(buffIcon, index)
    end
    
    -- Hook for new children (in case icons are created dynamically)
    hooksecurefunc(viewer, "SetPoint", function()
        C_Timer.After(0.1, function()
            ProcOverlay:RescanAndHookIcons()
        end)
    end)
    
    Util.Log("ProcOverlay", "Hooked viewer", { iconCount = #buffIcons })
end

--- Rescans and hooks any new buff icons.
function ProcOverlay:RescanAndHookIcons()
    local buffIcons = self:GetBuffIcons()
    for index, buffIcon in ipairs(buffIcons) do
        HookBuffIcon(buffIcon, index)
    end
end

--------------------------------------------------------------------------------
-- Module Interface
--------------------------------------------------------------------------------

function ProcOverlay:UpdateLayout()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile or not profile.procOverlay or not profile.procOverlay.enabled then
        -- Clear any active overlays
        for buffIcon in pairs(_modifiedIcons) do
            RestoreOriginalState(buffIcon)
            buffIcon.__ecmProcOverlayActive = nil
        end
        return
    end
    
    -- Hook viewer if not already
    self:HookViewer()
    
    -- Refresh all overlays
    self:Refresh()
end

function ProcOverlay:Refresh()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile or not profile.procOverlay or not profile.procOverlay.enabled then
        return
    end
    
    -- Rescan icons in case order changed
    local buffIcons = self:GetBuffIcons()
    local targetIcons = self:GetTargetIcons()
    
    -- Apply or clear overlays based on current state
    for index, buffIcon in ipairs(buffIcons) do
        local targetIconIndex = self:GetMapping(index)
        
        if targetIconIndex and buffIcon:IsShown() then
            local targetIcon = targetIcons[targetIconIndex]
            if targetIcon and targetIcon:IsShown() then
                PositionOverlay(buffIcon, targetIcon)
            else
                -- Target icon not available, restore original
                if buffIcon.__ecmProcOverlayActive then
                    RestoreOriginalState(buffIcon)
                    buffIcon.__ecmProcOverlayActive = nil
                end
            end
        elseif buffIcon.__ecmProcOverlayActive then
            -- No mapping or not shown, restore original
            RestoreOriginalState(buffIcon)
            buffIcon.__ecmProcOverlayActive = nil
        end
    end
end

function ProcOverlay:Enable()
    if self._enabled then
        return
    end
    self._enabled = true
    
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")
    
    Util.Log("ProcOverlay", "Enabled")
end

function ProcOverlay:Disable()
    if not self._enabled then
        return
    end
    self._enabled = false
    
    self:UnregisterEvent("UNIT_AURA")
    
    -- Clear all overlays
    for buffIcon in pairs(_modifiedIcons) do
        RestoreOriginalState(buffIcon)
        buffIcon.__ecmProcOverlayActive = nil
    end
    
    Util.Log("ProcOverlay", "Disabled")
end

function ProcOverlay:OnUnitAura(_, unit)
    if unit == "player" then
        self:Refresh()
    end
end

function ProcOverlay:SetExternallyHidden(hidden)
    if hidden then
        -- Clear overlays when externally hidden (e.g., mounted)
        for buffIcon in pairs(_modifiedIcons) do
            RestoreOriginalState(buffIcon)
            buffIcon.__ecmProcOverlayActive = nil
        end
    else
        self:Refresh()
    end
end

function ProcOverlay:OnEnable()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if profile and profile.procOverlay and profile.procOverlay.enabled then
        self:Enable()
    end
    
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
        self:UpdateLayout()
    end)
    
    -- Delay initial setup to ensure viewers are loaded
    C_Timer.After(0.5, function()
        self:UpdateLayout()
    end)
    
    Util.Log("ProcOverlay", "OnEnable")
end

function ProcOverlay:OnDisable()
    self:Disable()
    Util.Log("ProcOverlay", "OnDisable")
end

--- Returns count of buff icons and target icons for UI display.
---@return number buffCount, number targetCount
function ProcOverlay:GetIconCounts()
    local buffIcons = self:GetBuffIcons()
    local targetIcons = self:GetTargetIcons()
    return #buffIcons, #targetIcons
end
