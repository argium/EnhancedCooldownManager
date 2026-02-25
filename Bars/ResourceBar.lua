-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local ResourceBar = mod:NewModule("ResourceBar", "AceEvent-3.0")
local ClassUtil = ECM.ClassUtil
mod.ResourceBar = ResourceBar
ECM.BarMixin.ApplyConfigMixin(ResourceBar, "ResourceBar")

--- Returns resource bar values based on class/power type.
---@return number|nil maxResources
---@return number|nil currentValue
local function GetValues()
    local resourceType = ClassUtil.GetPlayerResourceType()
    return ClassUtil.GetCurrentMaxResourceValues(resourceType)
end

--------------------------------------------------------------------------------
-- ModuleMixin/BarMixin Overrides
--------------------------------------------------------------------------------
function ResourceBar:ShouldShow()
    local shouldShow = ECM.BarMixin.ShouldShow(self)

    if not shouldShow then
        return false
    end

    return ClassUtil.GetPlayerResourceType() ~= nil
end

function ResourceBar:GetStatusBarValues()
    local maxResources, currentValue = GetValues()

    if not maxResources or maxResources <= 0 then
        return 0, 1, 0, false
    end

    currentValue = currentValue or 0
    return currentValue, maxResources, currentValue, false
end

--- Gets the color for the resource bar based on resource type.
--- Handles DH souls (Vengeance, Devourer normal/meta).
---@return ECM_Color
function ResourceBar:GetStatusBarColor()
    local cfg = self:GetModuleConfig()
    local resourceType = ClassUtil.GetPlayerResourceType()
    local color = cfg.colors and cfg.colors[resourceType]
    ECM.DebugAssert(color, "Expected color to be defined for resourceType " .. tostring(resourceType))
    return color or ECM.Constants.COLOR_WHITE
end

function ResourceBar:Refresh(why, force)
    local continue = ECM.BarMixin.Refresh(self, why, force)
    if not continue then
        return false
    end

    -- Handle ticks (Devourer has no ticks, others have dividers)
    local resourceType = ClassUtil.GetPlayerResourceType()
    local isDevourer = (resourceType == "devourerMeta" or resourceType == "devourerNormal")

    if isDevourer then
        self:HideAllTicks("tickPool")
    else
        local frame = self.InnerFrame
        local maxResources = select(2, self:GetStatusBarValues())
        if maxResources > 1 then
            local tickCount = maxResources - 1
            self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")
            self:LayoutResourceTicks(maxResources, ECM.Constants.COLOR_BLACK, 1, "tickPool")
        else
            self:HideAllTicks("tickPool")
        end
    end

    ECM.Log(self.Name, "Refresh complete.")
    return true
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------

function ResourceBar:OnEventUpdate(event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit ~= "player" then
            return
        end
    end

    self:ThrottledUpdateLayout(event or "OnEventUpdate")
end

--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ResourceBar:OnEnable()
    if not self.IsModuleMixin then
        ECM.BarMixin.AddMixin(self, "ResourceBar")
    elseif ECM.RegisterFrame then
        ECM.RegisterFrame(self)
    end

    self:RegisterEvent("UNIT_AURA", "OnEventUpdate")
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnEventUpdate")
end

function ResourceBar:OnDisable()
    self:UnregisterAllEvents()
    if self.IsModuleMixin and ECM.UnregisterFrame then
        ECM.UnregisterFrame(self)
    end
end
