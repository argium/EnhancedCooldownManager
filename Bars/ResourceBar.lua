-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
local ECM = ns.Addon
local Util = ns.Util

local C = ns.Constants
local BarFrame = ns.Mixins.BarFrame

local ResourceBar = ECM:NewModule("ResourceBar", "AceEvent-3.0")
ECM.ResourceBar = ResourceBar

--- Power types that have discrete values and should be displayed using the resource bar.
local discreteResourceTypes = {
    [Enum.PowerType.ComboPoints] = true,
    [Enum.PowerType.Chi] = true,
    [Enum.PowerType.HolyPower] = true,
    [Enum.PowerType.SoulShards] = true,
    [Enum.PowerType.Essence] = true,
}

-- local function TransitioningToVoidMeta(self)
--     local isVoidMeta = GetDevourerVoidMetaState()
--     if isVoidMeta == nil then
--         return false
--     end

--     if self._lastVoidMeta == nil then
--         self._lastVoidMeta = isVoidMeta
--         return false
--     end

--     if isVoidMeta ~= self._lastVoidMeta then
--         self._lastVoidMeta = isVoidMeta
--         self:Refresh(true)
--         self._lastUpdate = GetTime()
--         return true
--     end

--     return false
-- end

--- Returns whether the Devourer DH is in void meta form.
---@return boolean|nil isVoidMeta
local function GetDevourerVoidMetaState()
    local _, class = UnitClass("player")
    if class ~= "DEMONHUNTER" or GetSpecialization() ~= C.DEMONHUNTER_DEVOURER_SPEC_INDEX then
        return nil
    end

    local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", 1227702)
    if collapsingStar then
        return true
    end

    local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", 1225789)
    if voidFragments then
        return false
    end

    return false
end

-- Gets the resource type for the player given their class, spec and current shapeshift form (if applicable).
---@return Enum.PowerType|nil powerType The current resource type, or nil if none.
local function GetActiveDiscreteResourceType()
    local _, class = UnitClass("player")

    for powerType in pairs(discreteResourceTypes) do
        local max = UnitPowerMax("player", powerType)
        if max and max > 0 then
            if class == "DRUID" then
                local formIndex = GetShapeshiftForm()
                if formIndex == 2 then
                    return powerType
                end
            else
                return powerType
            end
        end
    end
    return nil
end

--- Returns resource bar values based on class/power type.
---@param configSection table the resourceBar config section
---@return number|nil maxResources
---@return number|nil currentValue
---@return Enum.PowerType|string|nil kind
---@return boolean|nil isVoidMeta
local function GetValues(configSection)
    local _, class = UnitClass("player")

    -- Demon hunter souls can still be tracked by their aura stacks (thank the lord)
    if class == "DEMONHUNTER" then
        if GetSpecialization() == C.DEMONHUNTER_DEVOURER_SPEC_INDEX then
            -- Devourer is tracked by two spells - one for void meta, and one not.
            local voidFragments = C_UnitAuras.GetUnitAuraBySpellID("player", C.RESOURCEBAR_VOID_FRAGMENTS_SPELLID)
            local collapsingStar = C_UnitAuras.GetUnitAuraBySpellID("player", C.RESOURCEBAR_COLLAPSING_STAR_SPELLID)
            if collapsingStar then
                -- return 6, (collapsingStar.applications or 0) / 5, "souls", true
                return 30, collapsingStar.applications or 0, "souls", true
            end

            return 35, voidFragments and voidFragments.applications or 0, "souls", false
            -- return 7, (voidFragments.applications or 0) / 5, "souls", false
        elseif GetSpecialization() == C.DEMONHUNTER_VENGEANCE_SPEC_INDEX then
            -- Vengeance use the same type of soul fragments. The value can be tracked by checking
            -- the number of times spirit bomb can be cast, of all things.
            local count = C_Spell.GetSpellCastCount(C.RESOURCEBAR_SPIRIT_BOMB_SPELLID) or 0
            return C.RESOURCEBAR_VENGEANCE_SOULS_MAX, count, "souls", nil
        end

        -- Not displaying anything for havoc currently.
    else
        -- Everything else
        local powerType = GetActiveDiscreteResourceType()
        if powerType then
            local max = UnitPowerMax("player", powerType) or 0
            local current = UnitPower("player", powerType) or 0
            return max, current, powerType, nil
        end
    end

    return nil, nil, nil, nil
end

--------------------------------------------------------------------------------
-- ECMFrame/BarFrame Overrides
--------------------------------------------------------------------------------

function ResourceBar:ShouldShow()
    local shouldShow = BarFrame.ShouldShow(self)

    if not shouldShow then
        return false
    end

    local _, class = UnitClass("player")
    local specId =  GetSpecialization()

    if (class == "DEMONHUNTER") and (specId == C.DEMONHUNTER_DEVOURER_SPEC_INDEX or specId == C.DEMONHUNTER_VENGEANCE_SPEC_INDEX) then
         return true
    end

    local discreteResource = GetActiveDiscreteResourceType()
    return discreteResource ~= nil
end

function ResourceBar:GetStatusBarValues()
    local maxResources, currentValue, kind, isVoidMeta = GetValues(self:GetConfigSection())

    if not maxResources or maxResources <= 0 then
        return 0, 1, 0, false
    end

    currentValue = currentValue or 0
    return currentValue, maxResources, currentValue, false
end

--------------------------------------------------------------------------------
-- Layout and Refresh
--------------------------------------------------------------------------------

function ResourceBar:Refresh(force)
    -- Base refresh checks (enabled, hidden, etc.)
    local continue = BarFrame.Refresh(self, force)
    if not continue then
        Util.Log(self.Name, "ResourceBar:Refresh", "Skipping refresh (base checks)")
        return false
    end

    local globalConfig = self:GetGlobalConfig()
    local cfg = self:GetConfigSection()
    local frame = self:GetInnerFrame()

    -- Get resource values
    local maxResources, currentValue, kind, isVoidMeta = GetValues(cfg)
    if not maxResources or maxResources <= 0 then
        Util.Log(self.Name, "ResourceBar:Refresh", "No resources available, hiding")
        frame:Hide()
        return false
    end

    currentValue = currentValue or 0
    local isDevourer = (kind == "souls" and GetSpecialization() == C.DEMONHUNTER_DEVOURER_SPEC_INDEX)

    -- Determine color (ResourceBar-specific logic for DH souls)
    local color = cfg.colors and cfg.colors[kind]
    if isDevourer then
        if isVoidMeta then
            color = cfg.colors and cfg.colors.devourerMeta
        else
            color = cfg.colors and cfg.colors.devourerNormal
        end
    end

    -- Track void meta state changes
    -- if isDevourer then
    --     self._lastVoidMeta = not not isVoidMeta
    -- else
    --     self._lastVoidMeta = nil
    -- end
    color = color or C.COLOR_WHITE

    -- Update StatusBar
    frame.StatusBar:SetMinMaxValues(0, maxResources)
    frame.StatusBar:SetValue(currentValue)
    frame.StatusBar:SetStatusBarColor(color.r, color.g, color.b)

    -- Set texture
    local tex = Util.GetTexture((cfg and cfg.texture) or (globalConfig and globalConfig.texture))
    if tex then
        frame.StatusBar:SetStatusBarTexture(tex)
    end

    -- Handle text and ticks based on resource type
    local showText = cfg.showText ~= false
    if isDevourer then
        -- Devourer shows value as text (multiply by 5 for fragment count), no ticks
        if showText and frame.TextValue then
            local displayValue = math.floor(currentValue * 5)
            frame:SetText(tostring(displayValue))
            Util.ApplyFont(frame.TextValue, cfg)
        end
        frame:SetTextVisible(showText)
        self:HideAllTicks("tickPool")
    else
        -- Normal resources show ticks (dividers), optionally show numeric value as text
        if showText and frame.TextValue then
            frame:SetText(tostring(math.floor(currentValue)))
            Util.ApplyFont(frame.TextValue, cfg)
        end
        frame:SetTextVisible(showText)

        -- Render tick dividers between resources
        local tickCount = math.max(0, maxResources - 1)
        self:EnsureTicks(tickCount, frame.TicksFrame, "tickPool")
        self:LayoutResourceTicks(maxResources, { r = 0, g = 0, b = 0, a = 1 }, 1, "tickPool")
    end

    frame:Show()
    Util.Log(self.Name, "ResourceBar:Refresh", {
        maxResources = maxResources,
        currentValue = currentValue,
        kind = kind,
        isDevourer = isDevourer,
        isVoidMeta = isVoidMeta,
        showText = showText,
        color = color,
    })

    return true
end

--------------------------------------------------------------------------------
-- Event Handling
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
-- Module Lifecycle
--------------------------------------------------------------------------------

function ResourceBar:OnEnable()
    BarFrame.AddMixin(self, "ResourceBar")

    self:RegisterEvent("UNIT_AURA", "ThrottledRefresh")
    self:RegisterEvent("UNIT_POWER_FREQUENT", "ThrottledRefresh")
end

function ResourceBar:OnDisable()
    self:UnregisterAllEvents()
end
