-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local StaggerBar = ns.Addon:NewModule("StaggerBar")
local ClassUtil = ns.ClassUtil
local C = ns.Constants
ns.Addon.StaggerBar = StaggerBar

--- Returns whether the player currently has any Stagger debuff active.
local function hasAnyStagger()
    return C_UnitAuras.GetPlayerAuraBySpellID(C.SPELLID_STAGGER_HEAVY) ~= nil
        or C_UnitAuras.GetPlayerAuraBySpellID(C.SPELLID_STAGGER_MODERATE) ~= nil
        or C_UnitAuras.GetPlayerAuraBySpellID(C.SPELLID_STAGGER_LIGHT) ~= nil
end

function StaggerBar:ShouldShow()
    return ns.BarMixin.FrameProto.ShouldShow(self) and ClassUtil.IsBrewmasterMonk()
end

function StaggerBar:GetStatusBarValues()
    local current = UnitStagger("player") or 0
    local max = UnitHealthMax("player") or 0
    if max <= 0 then
        return 0, 1, "0%", true
    end
    return current, max, string.format("%.0f%%", current / max * 100), true
end

--- Gets the bar color for the current stagger level, derived from which stagger
--- debuff is active (heavy takes precedence over moderate over light).
---@return ECM_Color
function StaggerBar:GetStatusBarColor()
    local cfg = self:GetModuleConfig()
    if C_UnitAuras.GetPlayerAuraBySpellID(C.SPELLID_STAGGER_HEAVY) then
        return cfg.colorHeavy or C.COLOR_WHITE
    end
    if C_UnitAuras.GetPlayerAuraBySpellID(C.SPELLID_STAGGER_MODERATE) then
        return cfg.colorModerate or C.COLOR_WHITE
    end
    return cfg.colorLight or C.COLOR_WHITE
end

--- Starts the drain animation ticker if not already running. Stagger drains
--- continuously between UNIT_AURA events, so we poll while a stagger aura is
--- present and stop once the pool clears.
function StaggerBar:_StartTicker()
    if self._ticker then
        return
    end
    self._ticker = C_Timer.NewTicker(C.DEFAULT_REFRESH_FREQUENCY, function()
        if not (self:IsEnabled() and self.InnerFrame and self.InnerFrame:IsShown()) then
            self:_StopTicker()
            return
        end
        self:ThrottledRefresh("StaggerBar:Ticker")
        if not hasAnyStagger() then
            self:_StopTicker()
        end
    end)
end

--- Stops the drain animation ticker.
function StaggerBar:_StopTicker()
    if self._ticker then
        self._ticker:Cancel()
        self._ticker = nil
    end
end

function StaggerBar:OnEventUpdate(event, unit)
    if unit ~= "player" then
        return
    end
    self:_StartTicker()
    ns.Runtime.RequestRefresh(self, event or "StaggerBar:OnEventUpdate")
end

function StaggerBar:OnInitialize()
    ns.BarMixin.AddBarMixin(self, "StaggerBar")
end

function StaggerBar:OnEnable()
    local _, class = UnitClass("player")
    if class ~= "MONK" then
        return
    end

    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)

    self:RegisterEvent("UNIT_AURA", function(_, ...) self:OnEventUpdate(...) end)
end

function StaggerBar:OnDisable()
    self:UnregisterAllEvents()

    if self.InnerFrame then
        ns.Runtime.UnregisterFrame(self)
    end

    self:_StopTicker()
end
