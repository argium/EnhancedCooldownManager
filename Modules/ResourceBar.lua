-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local ResourceBar = ns.Addon:NewModule("ResourceBar")
local ClassUtil = ECM.ClassUtil
ns.Addon.ResourceBar = ResourceBar

function ResourceBar:ShouldShow()
    return ECM.FrameMixin.ShouldShow(self) and ClassUtil.GetPlayerResourceType() ~= nil
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

    if ECM.Constants.RESOURCEBAR_MAX_COLOR_TYPES[resourceType]
        and cfg.maxColorsEnabled and cfg.maxColorsEnabled[resourceType] then
        local _, current, safeMax = ClassUtil.GetCurrentMaxResourceValues(resourceType)
        if safeMax and current == safeMax then
            return cfg.maxColors and cfg.maxColors[resourceType] or ECM.Constants.COLOR_WHITE
        end
    end

    local color = cfg.colors and cfg.colors[resourceType]
    return color or ECM.Constants.COLOR_WHITE
end

function ResourceBar:Refresh(why, force)
    local continue = ECM.BarMixin.Refresh(self, why, force)
    if not continue then
        return false
    end

    -- Use the safe discrete count (3rd return) for tick layout to avoid
    -- secret value comparison/arithmetic. Devourer types have large counts
    -- (30/35) that should not produce tick dividers.
    local resourceType = ClassUtil.GetPlayerResourceType()
    local _, _, safeMax = ClassUtil.GetCurrentMaxResourceValues(resourceType)
    local isDevourer = (
        resourceType == ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_META
        or resourceType == ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL
    )

    if isDevourer then
        self:HideAllTicks("tickPool")
    elseif safeMax and safeMax > 1 then
        local frame = self.InnerFrame
        local tickCount = safeMax - 1
        self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")
        self:LayoutResourceTicks(safeMax, ECM.Constants.COLOR_BLACK, 1, "tickPool")
    else
        self:HideAllTicks("tickPool")
    end

    ECM.Log(self.Name, "Refresh complete.")
    return true
end

function ResourceBar:OnEventUpdate(event, ...)
    if event == "UNIT_AURA" then
        local unit = ...
        if unit ~= "player" then
            return
        end
    end

    self:ThrottledUpdateLayout(event or "OnEventUpdate")
end

function ResourceBar:OnEnable()
    ECM.BarMixin.AddMixin(self, "ResourceBar")
    ECM.RegisterFrame(self)

    self:RegisterEvent("UNIT_AURA", "OnEventUpdate")
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnEventUpdate")
end

function ResourceBar:OnDisable()
    self:UnregisterAllEvents()
    ECM.UnregisterFrame(self)
end
