-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod
local FrameUtil = ECM.FrameUtil
local ModuleMixin = {}
ECM.ModuleMixin = ModuleMixin

---@alias AnchorPoint string

---@class ModuleMixin : AceModule Frame mixin that owns visibility and config access.
---@field _configKey string|nil Config key for this frame's section.
---@field IsHidden boolean|nil Whether the frame is currently hidden.
---@field InnerFrame Frame|nil Inner WoW frame owned by this mixin.
---@field Name string Name of the frame.

--- Returns the global config section (live from AceDB profile).
---@return table|nil
function ModuleMixin:GetGlobalConfig()
    local profile = mod.db and mod.db.profile
    return profile and profile[ECM.Constants.CONFIG_SECTION_GLOBAL]
end

--- Returns this module's config section (live from AceDB profile).
---@return table|nil
function ModuleMixin:GetModuleConfig()
    local profile = mod.db and mod.db.profile
    return profile and profile[self._configKey]
end

--- Determine the correct anchor for this specific frame in the fixed order.
--- @param frameName string|nil The name of the current frame, or nil if first in chain.
--- @return Frame The frame to anchor to.
--- @return boolean isFirst True if this is the first frame in the chain.
function ModuleMixin:GetNextChainAnchor(frameName)
    -- Find the ideal position
    local stopIndex = #ECM.Constants.CHAIN_ORDER + 1
    if frameName then
        for i, name in ipairs(ECM.Constants.CHAIN_ORDER) do
            if name == frameName then
                stopIndex = i
                break
            end
        end
    end

    -- Work backwards to identify the first valid frame to anchor to.
    -- Valid frames are those that are enabled, should be shown, in chain mode,
    -- and have an inner frame available. Visibility is intentionally not required
    -- because layout updates can occur while frames are transitioning hide/show.
    for i = stopIndex - 1, 1, -1 do
        local barName = ECM.Constants.CHAIN_ORDER[i]
        local barModule = mod:GetECMModule(barName, false)
        local isEnabled = barModule and barModule:IsEnabled() or false
        local shouldShow = barModule and barModule:ShouldShow() or false
        local moduleConfig = barModule and barModule:GetModuleConfig()
        local isChainMode = moduleConfig and moduleConfig.anchorMode == ECM.Constants.ANCHORMODE_CHAIN
        local innerFrame = barModule and barModule.InnerFrame

        if isEnabled and shouldShow and isChainMode and innerFrame then
            ECM.Log(self.Name, "GetNextChainAnchor ".. barName .." <-- " .. (frameName or "nil"))
            return innerFrame, false
        end
    end

    -- If none of the preceding frames in the chain are valid, anchor to the viewer as the first.
    ECM.Log(self.Name, "GetNextChainAnchor Viewer <-- " .. (frameName or "nil"))
    return _G["EssentialCooldownViewer"] or UIParent, true
end

function ModuleMixin:SetHidden(hide)
    self.IsHidden = hide
end

--- Determines whether this frame should be shown at this particular moment. Can be overridden.
function ModuleMixin:ShouldShow()
    local config = self:GetModuleConfig()
    return not self.IsHidden and (config == nil or config.enabled ~= false)
end

function ModuleMixin:CreateFrame()
    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local name = "ECM" .. self.Name
    local frame = CreateFrame("Frame", name, UIParent)

    local barHeight = (moduleConfig and moduleConfig.height)
        or (globalConfig and globalConfig.barHeight)
        or ECM.Constants.DEFAULT_BAR_HEIGHT

    frame:SetFrameStrata("MEDIUM")
    frame:SetHeight(barHeight)
    frame.Background = frame:CreateTexture(nil, "BACKGROUND")
    frame.Background:SetAllPoints()

    -- Optional border frame
    frame.Border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.Border:SetFrameLevel(frame:GetFrameLevel() + 3)
    frame.Border:Hide()

    return frame
end

--- Calculates layout parameters based on anchor mode. Override for custom positioning logic.
---@return table params Layout parameters: mode, anchor, isFirst, anchorPoint, anchorRelativePoint, offsetX, offsetY, width, height
function ModuleMixin:CalculateLayoutParams()
    return FrameUtil.CalculateLayoutParams(self)
end

function ModuleMixin:UpdateLayout(why)
    return FrameUtil.ApplyStandardLayout(self, why)
end

--- Handles common refresh logic for ModuleMixin-derived frames.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @param force boolean|nil Whether to force a refresh, even if the bar is hidden.
--- @return boolean continue True if the frame should continue refreshing, false to skip.
function ModuleMixin:Refresh(why, force)
    return FrameUtil.BaseRefresh(self, why, force)
end

--- Rate-limited refresh. Skips if called within updateFrequency window.
--- @param why string|nil Optional debug string for why the refresh was triggered.
--- @return boolean refreshed True if Refresh() was called
function ModuleMixin:ThrottledRefresh(why)
    return FrameUtil.ThrottledRefresh(self, why)
end

--- Checks if the module is ready for layout updates.
--- @return boolean ready True if the module is ready for updates.
function ModuleMixin:IsReady()
    return self:IsEnabled() and self.InnerFrame ~= nil
        and self:GetGlobalConfig() ~= nil and self:GetModuleConfig() ~= nil
end

--- Internal: checks readiness and runs the coalesced layout update.
local function updateLayoutDeferred(self)
    if not self:IsReady() then
        ECM.Log(self.Name, "Layout update skipped (not ready)")
        self._updateLayoutPending = false
        self._pendingWhy = nil
        return
    end

    -- Clear pending state to allow re-entry.
    local why = self._pendingWhy
    self._updateLayoutPending = false
    self._pendingWhy = nil

    self:UpdateLayout(why)

    -- Schedule second-pass if requested.
    if self._secondPassPending then
        self._secondPassPending = false
        C_Timer.After(ECM.Constants.LIFECYCLE_SECOND_PASS_DELAY, function()
            self:ThrottledUpdateLayout("SecondPass")
        end)
    end
end

--- Requests a layout update for this module.
--- @param reason string Debug trace string identifying the caller.
--- @param opts table|nil Optional parameters: { secondPass = boolean }
function ModuleMixin:ThrottledUpdateLayout(reason, opts)
    ECM.DebugAssert(reason, "ThrottledUpdateLayout: reason is required")

    -- Bail immediately if the module is disabled.
    if self.IsEnabled and not self:IsEnabled() then
        return
    end

    -- Request second-pass if needed.
    if opts and opts.secondPass then
        self._secondPassPending = true
    end

    -- Keep the first reason that triggered this batch for tracing.
    -- Queue exactly once if not already queued.
    if not self._updateLayoutPending then
        self._pendingWhy = reason
        self._updateLayoutPending = true
        C_Timer.After(0, function()
            updateLayoutDeferred(self)
        end)
    end
end

--- Applies only the config-access portion of the mixin (methods, Name, _configKey).
--- Safe to call at module creation time before OnEnable; does NOT create frames or
--- register with layout. Idempotent.
function ModuleMixin.ApplyConfigMixin(target, name)
    mod = mod or ns.Addon
    assert(target, "target required")
    assert(name, "name required")

    -- Only copy methods that the target doesn't already have.
    for k, v in pairs(ModuleMixin) do
        if type(v) == "function" and target[k] == nil then
            target[k] = v
        end
    end

    target.Name = name
    target._configKey = name:sub(1,1):lower() .. name:sub(2) -- camelCase-ish
    target.IsHidden = false
end

function ModuleMixin.AddFrameMixin(target, name)
    assert(target, "target required")
    assert(name, "name required")

    -- Get this at the last moment because this method may be called before ECM has fully initialized.
    mod = mod or ns.Addon

    -- Callers (BarMixin.AddMixin, BuffBars) already call ApplyConfigMixin before
    -- this point, but direct callers (ItemIcons) may not — so keep idempotent call.
    if not target.Name then
        ModuleMixin.ApplyConfigMixin(target, name)
    end

    if not target.InnerFrame then
        target.InnerFrame = target:CreateFrame()
    end
end
