-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ResourceBar = ns.Addon:NewModule("ResourceBar")
local ClassUtil = ns.ClassUtil
local C = ns.Constants
ns.Addon.ResourceBar = ResourceBar

function ResourceBar:ShouldShow()
    return ns.BarMixin.FrameProto.ShouldShow(self) and ClassUtil.GetPlayerResourceType() ~= nil
end

function ResourceBar:GetStatusBarValues()
    local resourceType = ClassUtil.GetPlayerResourceType()
    local maxResources, currentValue = ClassUtil.GetCurrentMaxResourceValues(resourceType)

    if not maxResources then
        return 0, 1, 0, false
    end

    return currentValue, maxResources, currentValue, false
end

--- Gets the color for the resource bar based on resource type.
--- Returns a max-value color override when the type supports it, the user has
--- enabled it, and the resource is currently at its maximum.
---@return ECM_Color
function ResourceBar:GetStatusBarColor()
    local cfg = self:GetModuleConfig()
    local resourceType = ClassUtil.GetPlayerResourceType()

    if
        C.RESOURCEBAR_MAX_COLOR_TYPES[resourceType]
        and cfg.maxColorsEnabled
        and cfg.maxColorsEnabled[resourceType]
    then
        local _, current, safeMax = ClassUtil.GetCurrentMaxResourceValues(resourceType)
        if safeMax and current == safeMax then
            return cfg.maxColors and cfg.maxColors[resourceType] or C.COLOR_WHITE
        end
    end

    local color = cfg.colors and cfg.colors[resourceType]
    return color or C.COLOR_WHITE
end

--- Returns a tick spec for BarProto to lay out resource divider ticks.
--- Returns nil when safeMax is unavailable or too small for dividers.
---@return table|nil spec { maxResources, color, width }
function ResourceBar:GetTickSpec()
    local resourceType = ClassUtil.GetPlayerResourceType()
    local _, _, safeMax = ClassUtil.GetCurrentMaxResourceValues(resourceType)
    if not safeMax or safeMax <= 1 then return nil end
    return { maxResources = safeMax, color = C.COLOR_BLACK, width = 1 }
end

function ResourceBar:OnEventUpdate(event, ...)
    local unit = ...
    if unit ~= "player" then
        return
    end

    ns.Runtime.RequestLayout(event or "ResourceBar:OnEventUpdate")
end

function ResourceBar:OnInitialize()
    ns.BarMixin.AddBarMixin(self, "ResourceBar")
end

function ResourceBar:OnEnable()
    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)

    self:RegisterEvent("UNIT_AURA", function(_, ...) self:OnEventUpdate(...) end)
    self:RegisterEvent("UNIT_POWER_UPDATE", function(_, ...) self:OnEventUpdate(...) end)
end

function ResourceBar:OnDisable()
    self:UnregisterAllEvents()
    ns.Runtime.UnregisterFrame(self)
end
