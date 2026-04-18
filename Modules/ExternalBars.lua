-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local BarMixin = ns.BarMixin
local FrameUtil = ns.FrameUtil
local FrameProto = BarMixin.FrameProto
local StyleChildBar = ns.BarStyle.StyleChildBar
local C = ns.Constants
local ExternalBars = ns.Addon:NewModule("ExternalBars")
ns.Addon.ExternalBars = ExternalBars

local PLAYER_UNIT = "player"
local SPELL_COLOR_SCOPE = C.SCOPE_EXTERNALBARS
local canAccessTable = _G.canaccesstable
local secondsToTimeAbbrev = _G.SecondsToTimeAbbrev

local function getSpellColors()
    return ns.SpellColors.Get(SPELL_COLOR_SCOPE)
end

---@class ECM_ExternalAuraState Cached external aura data keyed by Blizzard's aura array position.
---@field auraInstanceID number|nil Aura instance identifier forwarded only to Blizzard aura APIs.
---@field index number Aura array position currently bound to this cached aura state.
---@field name string|nil Non-secret aura name used for color lookup and optional display.
---@field spellID number|nil Non-secret spell ID used for spell-color lookup.
---@field texture string|number|nil Aura icon texture forwarded to widget APIs.
---@field duration number|nil Aura duration forwarded to the cooldown widget.
---@field expirationTime number|nil Aura expiration time used only when non-secret duration text is allowed.
---@field timeMod number|nil Aura time modifier forwarded to the cooldown widget.
---@field durationIsSecret boolean Whether the packed aura duration is secret.
---@field canShowDurationText boolean Whether duration text can be refreshed safely in Lua.
---@field hasRenderableDuration boolean Whether the cooldown widget can be configured for this aura.

---@class ECM_ExternalBarStatusBar : StatusBar Shared-status bar surface for one external aura row.
---@field Name FontString Spell name text.
---@field Duration FontString Remaining duration text.
---@field Pip Texture Hidden compatibility texture expected by `BarStyle.StyleChildBar`.

---@class ECM_ExternalBarMixin : Frame Reusable bar row styled by the shared BuffBars helpers.
---@field __ecmHooked boolean Whether the shared child-bar styling is allowed to target this frame.
---@field Bar ECM_ExternalBarStatusBar Inner status bar surface.
---@field Cooldown Cooldown Cooldown overlay rendering the draining fill.
---@field Icon Frame Icon frame containing the texture regions expected by `FrameUtil`.
---@field cooldownInfo { spellID: number|nil } Spell metadata consumed by `SpellColors`.
---@field _ecmAuraIndex number Aura array position currently bound to this pooled bar.
---@field _iconTexture Texture Cached icon texture for this bar.

local function getViewer()
    return _G["ExternalDefensivesFrame"]
end

---@param point string|nil
---@return boolean
local function pointGrowsUp(point)
    return point == "BOTTOMLEFT" or point == "BOTTOM" or point == "BOTTOMRIGHT"
end

---@param remaining number
---@return string
local function formatDurationText(remaining)
    if remaining <= 0 then
        return ""
    end

    if type(secondsToTimeAbbrev) == "function" then
        local text = secondsToTimeAbbrev(remaining)
        return text or ""
    end

    if remaining >= 60 then
        local minutes = math.floor(remaining / 60)
        local seconds = math.floor(remaining % 60)
        return string.format("%d:%02d", minutes, seconds)
    end

    if remaining >= 10 then
        return string.format("%d", math.floor(remaining + 0.5))
    end

    return string.format("%.1f", remaining)
end

---@param bars ECM_ExternalBarMixin[]
---@param container Frame
---@param growsUp boolean
---@param verticalSpacing number
local function layoutBars(bars, container, growsUp, verticalSpacing)
    local previous

    local function anchorBar(bar)
        local selfEdge = growsUp and "BOTTOM" or "TOP"
        local relativeEdge = previous and (growsUp and "TOP" or "BOTTOM") or selfEdge
        local anchor = previous or container
        local spacing = not previous and 0 or (growsUp and verticalSpacing or -verticalSpacing)

        FrameUtil.LazySetAnchors(bar, {
            { selfEdge .. "LEFT", anchor, relativeEdge .. "LEFT", 0, spacing },
            { selfEdge .. "RIGHT", anchor, relativeEdge .. "RIGHT", 0, spacing },
        })
        previous = bar
    end

    if growsUp then
        for index = #bars, 1, -1 do
            anchorBar(bars[index])
        end
        return
    end

    for _, bar in ipairs(bars) do
        anchorBar(bar)
    end
end

---@param moduleConfig ECM_ExternalBarsConfig|nil
---@param globalConfig ECM_GlobalConfig|nil
---@return ECM_ExternalBarsConfig|nil
function ExternalBars:_GetStyleConfig(moduleConfig, globalConfig)
    if not moduleConfig or moduleConfig.height ~= 0 then
        return moduleConfig
    end

    local styleConfig = self._styleConfig or {}
    wipe(styleConfig)

    for key, value in pairs(moduleConfig) do
        styleConfig[key] = value
    end

    styleConfig.height = (globalConfig and globalConfig.barHeight) or C.DEFAULT_BAR_HEIGHT
    self._styleConfig = styleConfig
    return styleConfig
end

---@param styleConfig ECM_ExternalBarsConfig|nil
---@param globalConfig ECM_GlobalConfig|nil
---@return number
function ExternalBars:_GetBarHeight(styleConfig, globalConfig)
    return (styleConfig and styleConfig.height) or (globalConfig and globalConfig.barHeight) or C.DEFAULT_BAR_HEIGHT
end

---@param hidden boolean
function ExternalBars:_SetOriginalIconsHidden(hidden)
    local viewer = getViewer()
    if not viewer then
        return
    end

    if hidden then
        self._originalIconsHidden = true
        viewer:SetAlpha(0)
        viewer:EnableMouse(false)
        return
    end

    if self._originalIconsHidden then
        local alpha = 1

        self._originalIconsHidden = nil

        if ns.Runtime and ns.Runtime.GetDesiredAlpha then
            alpha = ns.Runtime.GetDesiredAlpha()
        end

        viewer:SetAlpha(alpha)
        viewer:EnableMouse(alpha > 0)

        if ns.Runtime and ns.Runtime.RequestLayout then
            ns.Runtime.RequestLayout("ExternalBars:OriginalIconsShown")
        end
    end
end

function ExternalBars:_RefreshOriginalIconsState()
    local moduleConfig = self:GetModuleConfig()
    self:_SetOriginalIconsHidden(moduleConfig and moduleConfig.hideOriginalIcons == true)
end

function ExternalBars:_StopDurationTicker()
    if self._durationTicker then
        self._durationTicker:Cancel()
        self._durationTicker = nil
    end
end

---@param bar ECM_ExternalBarMixin
---@param auraState ECM_ExternalAuraState|nil
---@param showDuration boolean|nil
function ExternalBars:_RefreshBarDurationText(bar, auraState, showDuration)
    local durationText = bar and bar.Bar and bar.Bar.Duration
    if not durationText then
        return
    end

    if showDuration == false or not auraState or not auraState.canShowDurationText then
        durationText:SetText(nil)
        durationText:Hide()
        return
    end

    local remaining = auraState.expirationTime - GetTime()
    if remaining < 0 then
        remaining = 0
    end

    durationText:SetText(formatDurationText(remaining))
    durationText:Show()
end

function ExternalBars:_RefreshDurationTexts()
    local moduleConfig = self:GetModuleConfig()
    if not moduleConfig or moduleConfig.showDuration == false then
        self:_StopDurationTicker()
        return
    end

    local hasEligibleBars = false
    local barPool = self._barPool or {}
    local auraStates = self._auraStates or {}
    local activeAuraCount = self._activeAuraCount or 0

    for index = 1, activeAuraCount do
        local bar = barPool[index]
        local auraState = auraStates[index]
        if bar and bar:IsShown() and auraState and auraState.canShowDurationText then
            hasEligibleBars = true
        end
        if bar then
            self:_RefreshBarDurationText(bar, auraState, true)
        end
    end

    if not hasEligibleBars then
        self:_StopDurationTicker()
    end
end

function ExternalBars:_RestartDurationTicker()
    self:_StopDurationTicker()

    local moduleConfig = self:GetModuleConfig()
    if not moduleConfig or moduleConfig.showDuration == false then
        return
    end

    local auraStates = self._auraStates or {}
    local activeAuraCount = self._activeAuraCount or 0
    for index = 1, activeAuraCount do
        local auraState = auraStates[index]
        if auraState and auraState.canShowDurationText then
            self._durationTicker = C_Timer.NewTicker(0.1, function()
                self:_RefreshDurationTexts()
            end)
            return
        end
    end
end

---@param index number
---@return ECM_ExternalBarMixin
function ExternalBars:_ensureBar(index)
    self._barPool = self._barPool or {}

    local bar = self._barPool[index]
    if bar then
        return bar
    end

    local container = self.InnerFrame
    ---@cast container Frame
    bar = CreateFrame("Frame", nil, container)
    bar:SetFrameStrata("MEDIUM")
    bar:SetFrameLevel(container:GetFrameLevel() + 1)
    bar.__ecmHooked = true
    bar.cooldownInfo = {}

    bar.Bar = CreateFrame("StatusBar", nil, bar)
    bar.Bar:SetAllPoints(bar)
    bar.Bar:SetFrameLevel(bar:GetFrameLevel() + 1)
    bar.Bar:SetMinMaxValues(0, 1)
    bar.Bar:SetValue(1)

    local barBackground = bar.Bar:CreateTexture(nil, "BACKGROUND")
    barBackground:SetAllPoints(bar.Bar)
    barBackground:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")

    bar.Bar.Pip = bar.Bar:CreateTexture(nil, "OVERLAY")
    bar.Bar.Pip:Hide()

    bar.Icon = CreateFrame("Frame", nil, bar)
    bar.Icon:SetFrameLevel(bar:GetFrameLevel() + 3)

    local iconTexture = bar.Icon:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints(bar.Icon)
    iconTexture:SetTexCoord(0, 1, 0, 1)
    bar._iconTexture = iconTexture

    bar.Icon.Applications = bar.Icon:CreateTexture(nil, "ARTWORK")
    bar.Icon.Applications:SetAllPoints(bar.Icon)
    bar.Icon.Applications:SetAlpha(0)

    local iconOverlay = bar.Icon:CreateTexture(nil, "OVERLAY")
    iconOverlay:SetAllPoints(bar.Icon)
    iconOverlay:SetAtlas("UI-HUD-CoolDownManager-IconOverlay")

    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameLevel(bar.Bar:GetFrameLevel() + 5)

    bar.Bar.Name = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Bar.Name:SetJustifyH("LEFT")
    bar.Bar.Name:SetJustifyV("MIDDLE")
    bar.Bar.Name:SetWordWrap(false)

    bar.Bar.Duration = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.Bar.Duration:SetJustifyH("RIGHT")
    bar.Bar.Duration:SetJustifyV("MIDDLE")
    bar.Bar.Duration:SetWordWrap(false)

    bar.Cooldown = CreateFrame("Cooldown", nil, bar.Bar, "CooldownFrameTemplate")
    bar.Cooldown:SetAllPoints(bar.Bar)
    bar.Cooldown:SetFrameLevel(bar.Bar:GetFrameLevel() + 2)
    bar.Cooldown:SetDrawSwipe(true)
    bar.Cooldown:SetDrawEdge(false)
    bar.Cooldown:SetDrawBling(false)
    bar.Cooldown:SetReverse(true)
    bar.Cooldown:SetHideCountdownNumbers(true)
    bar.Cooldown:SetSwipeColor(0, 0, 0, 1)

    bar:Hide()
    self._barPool[index] = bar
    return bar
end

---@param activeCount number
function ExternalBars:_hideExcessBars(activeCount)
    local barPool = self._barPool or {}
    for index = activeCount + 1, #barPool do
        local bar = barPool[index]
        if bar then
            if bar._ecmColorRetryTimer then
                bar._ecmColorRetryTimer:Cancel()
                bar._ecmColorRetryTimer = nil
            end
            bar.cooldownInfo.spellID = nil
            bar.Bar.Name:SetText(nil)
            bar.Bar.Duration:SetText(nil)
            bar.Bar.Duration:Hide()
            bar.Cooldown:Clear()
            bar:Hide()
        end
    end
end

---@param bar ECM_ExternalBarMixin
---@param auraState ECM_ExternalAuraState
---@param moduleConfig ECM_ExternalBarsConfig|nil
---@param globalConfig ECM_GlobalConfig|nil
---@param styleConfig ECM_ExternalBarsConfig|nil
---@param spellColors ECM_SpellColorStore
function ExternalBars:_ConfigureBar(bar, auraState, moduleConfig, globalConfig, styleConfig, spellColors)
    bar._ecmAuraIndex = auraState.index
    bar.cooldownInfo.spellID = auraState.spellID
    bar._iconTexture:SetTexture(auraState.texture)
    bar.Bar.Name:SetText(auraState.name)

    StyleChildBar(self, bar, styleConfig, globalConfig, spellColors)
    spellColors:DiscoverBar(bar)

    self:_RefreshBarDurationText(bar, auraState, moduleConfig and moduleConfig.showDuration ~= false)

    if auraState.hasRenderableDuration then
        bar.Cooldown:SetCooldownDuration(auraState.duration, auraState.timeMod)
    else
        bar.Cooldown:Clear()
    end

    bar:Show()
end

function ExternalBars:GetActiveSpellData()
    local result = {}
    local auraStates = self._auraStates or {}
    local barPool = self._barPool or {}
    local activeAuraCount = self._activeAuraCount or 0

    for index = 1, activeAuraCount do
        local auraState = auraStates[index]
        if auraState then
            local bar = barPool[index]
            local textureFileID = bar and FrameUtil.GetIconTextureFileID(bar) or nil
            local key = ns.SpellColors.MakeKey(auraState.name, auraState.spellID, nil, textureFileID)
            if key then
                result[#result + 1] = key
            end
        end
    end

    return result
end

---@return boolean isEditLocked
---@return string|nil reason
function ExternalBars:IsEditLocked()
    local reason = InCombatLockdown() and "combat" or (self._editLocked and "secrets") or nil
    return reason ~= nil, reason
end

function ExternalBars:ShouldShow()
    if not FrameProto.ShouldShow(self) then
        return false
    end

    local viewer = getViewer()
    return viewer ~= nil and viewer:IsShown() and (self._activeAuraCount or 0) > 0
end

function ExternalBars:CreateFrame()
    local frame = CreateFrame("Frame", "ECMExternalBars", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(1, 1)
    return frame
end

function ExternalBars:HookViewer()
    local viewer = getViewer()
    if not viewer or self._viewerHooked then
        return
    end

    self._viewerHooked = true

    hooksecurefunc(viewer, "UpdateAuras", function()
        if self:IsEnabled() then
            self:OnExternalAurasUpdated()
        end
    end)

    viewer:HookScript("OnShow", function()
        if not self:IsEnabled() then
            return
        end
        self:_RefreshOriginalIconsState()
        self:OnExternalAurasUpdated()
    end)

    viewer:HookScript("OnHide", function()
        if not self:IsEnabled() then
            return
        end
        self._activeAuraCount = 0
        self:_hideExcessBars(0)
        self:_StopDurationTicker()
        ns.Runtime.RequestLayout("ExternalBars:viewer:OnHide")
    end)

    ns.Log(self.Name, "Hooked ExternalDefensivesFrame")
end

function ExternalBars:OnExternalAurasUpdated()
    self:HookViewer()
    self:_RefreshOriginalIconsState()

    local viewer = getViewer()
    local auraInfo = viewer and viewer.auraInfo or nil
    local auraStates = self._auraStates or {}
    self._auraStates = auraStates

    local activeAuraCount = 0
    if type(auraInfo) == "table" then
        for index, info in ipairs(auraInfo) do
            activeAuraCount = index

            local auraState = auraStates[index] or {}
            auraStates[index] = auraState

            local auraInstanceID = info.auraInstanceID
            local auraName = nil
            local spellID = nil
            local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(PLAYER_UNIT, auraInstanceID)
            local accessibleAuraData = canAccessTable(auraData) and auraData or nil
            if accessibleAuraData then
                local auraDataName = accessibleAuraData.name
                if not issecretvalue(auraDataName) and auraDataName ~= nil and auraDataName ~= "" then
                    auraName = auraDataName
                end

                local auraSpellID = accessibleAuraData.spellId
                if not issecretvalue(auraSpellID) and auraSpellID ~= nil then
                    spellID = auraSpellID
                end
            end

            local duration = info.duration
            local expirationTime = info.expirationTime
            local durationIsSecret = issecretvalue(duration)
            local expirationTimeIsSecret = issecretvalue(expirationTime)

            auraState.index = index
            auraState.auraInstanceID = auraInstanceID
            auraState.name = auraName
            auraState.spellID = spellID
            auraState.texture = info.texture
            auraState.duration = duration
            auraState.expirationTime = expirationTime
            auraState.timeMod = info.timeMod
            auraState.durationIsSecret = durationIsSecret
            auraState.canShowDurationText = not durationIsSecret
                and not expirationTimeIsSecret
                and type(duration) == "number"
                and duration > 0
                and type(expirationTime) == "number"
            auraState.hasRenderableDuration = durationIsSecret or (type(duration) == "number" and duration > 0)
        end
    end

    self._activeAuraCount = activeAuraCount
    ns.Runtime.RequestLayout("ExternalBars:UpdateAuras")
end

---@param why string|nil
---@return boolean
function ExternalBars:UpdateLayout(why)
    local frame = self.InnerFrame
    if not frame then
        return false
    end

    self:HookViewer()
    self:_RefreshOriginalIconsState()

    local spellColors = getSpellColors()

    if why == "PLAYER_SPECIALIZATION_CHANGED" or why == "ProfileChanged" then
        spellColors:ClearDiscoveredKeys()
    end

    local globalConfig = self:GetGlobalConfig()
    local moduleConfig = self:GetModuleConfig()
    local styleConfig = self:_GetStyleConfig(moduleConfig, globalConfig)
    local params = self:ApplyFramePosition()
    if not params then
        self:_hideExcessBars(0)
        self:_StopDurationTicker()
        return false
    end

    if params.width then
        FrameUtil.LazySetWidth(frame, params.width)
    end

    self._editLocked = false

    local activeBars = self._activeBars or {}
    wipe(activeBars)
    self._activeBars = activeBars

    local activeAuraCount = self._activeAuraCount or 0
    local auraStates = self._auraStates or {}
    local ok, err = pcall(function()
        for index = 1, activeAuraCount do
            local auraState = auraStates[index]
            if auraState then
                local bar = self:_ensureBar(index)
                self:_ConfigureBar(bar, auraState, moduleConfig, globalConfig, styleConfig, spellColors)
                activeBars[#activeBars + 1] = bar

                local textureFileID = FrameUtil.GetIconTextureFileID(bar)
                local textureIsSecret = issecretvalue(textureFileID)
                if auraState.name == nil and auraState.spellID == nil and (textureIsSecret or textureFileID == nil) then
                    self._editLocked = true
                end
            end
        end

        self:_hideExcessBars(#activeBars)
        layoutBars(activeBars, frame, pointGrowsUp(params.anchorPoint), math.max(0, moduleConfig and moduleConfig.verticalSpacing or 0))
    end)

    if not self._editLocked then
        self._warned = false
    end

    if not ok then
        self:_hideExcessBars(0)
        self:_StopDurationTicker()
        ns.DebugAssert(false, "Error styling external bars: " .. tostring(err))
        return false
    end

    local barCount = #activeBars
    local barHeight = self:_GetBarHeight(styleConfig, globalConfig)
    local verticalSpacing = math.max(0, moduleConfig and moduleConfig.verticalSpacing or 0)
    local totalHeight = (barCount * barHeight) + (math.max(0, barCount - 1) * verticalSpacing)
    FrameUtil.LazySetHeight(frame, totalHeight)

    self:_RestartDurationTicker()

    ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")", {
        barCount = barCount,
        anchorPoint = params.anchorPoint,
        offsetX = params.offsetX,
        offsetY = params.offsetY,
    })
    return true
end

function ExternalBars:OnInitialize()
    BarMixin.AddFrameMixin(self, "ExternalBars")
end

function ExternalBars:OnEnable()
    self._barPool = self._barPool or {}
    self._activeBars = self._activeBars or {}
    self._auraStates = self._auraStates or {}
    self._activeAuraCount = 0
    self._warned = false

    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)

    C_Timer.After(0.1, function()
        if not self:IsEnabled() then
            return
        end

        self:HookViewer()
        self:_RefreshOriginalIconsState()
        self:OnExternalAurasUpdated()
        ns.Runtime.RequestLayout("ExternalBars:OnEnable")
    end)
end

function ExternalBars:OnDisable()
    self:UnregisterAllEvents()
    self:_StopDurationTicker()
    self:_SetOriginalIconsHidden(false)
    self._activeAuraCount = 0
    self:_hideExcessBars(0)

    ns.Runtime.UnregisterFrame(self)
end
