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

local function getSpellColors()
    return ns.SpellColors.Get(SPELL_COLOR_SCOPE)
end

---@class ECM_ExternalAuraState Cached external aura data keyed by Blizzard's aura array position.
---@field auraInstanceID number|nil Aura instance identifier forwarded only to Blizzard aura APIs.
---@field index number Aura array position currently bound to this cached aura state.
---@field name string|nil Non-secret aura name used for color lookup and optional display.
---@field spellID number|nil Non-secret spell ID used for spell-color lookup.
---@field texture string|number|nil Aura icon texture forwarded to widget APIs.
---@field duration number|nil Aura duration retained only for diagnostics.
---@field expirationTime number|nil Aura expiration time retained only for diagnostics.
---@field durationObject table|nil Aura duration object consumed by StatusBar timer APIs.
---@field durationIsSecret boolean Whether the packed aura duration is secret.
---@field canShowDurationText boolean Whether duration text can be refreshed through engine formatting.
---@field canUpdateDurationBar boolean Whether duration progress can be refreshed through the StatusBar timer.

---@class ECM_ExternalBarStatusBar : StatusBar Shared-status bar surface for one external aura row.
---@field Name FontString Spell name text.
---@field Duration FontString Remaining duration text.
---@field Pip Texture Hidden compatibility texture expected by `BarStyle.StyleChildBar`.

---@class ECM_ExternalBarMixin : Frame Reusable bar row styled by the shared BuffBars helpers.
---@field __ecmHooked boolean Whether the shared child-bar styling is allowed to target this frame.
---@field Bar ECM_ExternalBarStatusBar Inner status bar surface.
---@field Icon Frame Icon frame containing the texture regions expected by `FrameUtil`.
---@field cooldownInfo { spellID: number|nil } Spell metadata consumed by `SpellColors`.
---@field _ecmAuraIndex number Aura array position currently bound to this pooled bar.
---@field _iconTexture Texture Cached icon texture for this bar.

local function getViewer()
    return _G["ExternalDefensivesFrame"]
end

---@param frame Frame|nil
---@return boolean|nil
local function getFrameShown(frame)
    return frame and frame.IsShown and frame:IsShown() or nil
end

---@param frame Frame|nil
---@return number|nil
local function getFrameAlpha(frame)
    return frame and frame.GetAlpha and frame:GetAlpha() or nil
end

---@param frame Frame|nil
---@return number|nil
local function getFrameWidth(frame)
    return frame and frame.GetWidth and frame:GetWidth() or nil
end

---@param frame Frame|nil
---@return number|nil
local function getFrameHeight(frame)
    return frame and frame.GetHeight and frame:GetHeight() or nil
end

---@param tbl table|nil
---@param logKey string|nil
---@param reason string|nil
---@return number|nil
local function countAccessibleArray(tbl, logKey, reason)
    if type(tbl) ~= "table" or not canAccessTable(tbl) then
        return nil
    end

    local count = 0
    local ok, err = pcall(function()
        for index in ipairs(tbl) do
            count = index
        end
    end)
    if ok then
        return count
    end

    if logKey then
        ns.ErrorLogOnce("ExternalBars", logKey, "ExternalBars diagnostics could not iterate a Blizzard table", {
            reason = reason,
            operation = "ipairs",
            error = tostring(err),
            inCombatLockdown = InCombatLockdown(),
        })
    end
    return nil
end

---@param tbl table|nil
---@param logKey string|nil
---@param reason string|nil
---@return number|nil
local function countAccessibleKeys(tbl, logKey, reason)
    if type(tbl) ~= "table" or not canAccessTable(tbl) then
        return nil
    end

    local count = 0
    local ok, err = pcall(function()
        for _ in pairs(tbl) do
            count = count + 1
        end
    end)
    if ok then
        return count
    end

    if logKey then
        ns.ErrorLogOnce("ExternalBars", logKey, "ExternalBars diagnostics could not iterate a Blizzard table", {
            reason = reason,
            operation = "pairs",
            error = tostring(err),
            inCombatLockdown = InCombatLockdown(),
        })
    end
    return nil
end

---@param reason string|nil
---@param viewer Frame|nil
---@param auraInfo table|nil
---@return table
local function getAuraInfoErrorData(reason, viewer, auraInfo)
    local instanceName, instanceType, difficultyID, difficultyName, maxPlayers, _, _, instanceID = _G.GetInstanceInfo()
    local canAccessAuraInfo = nil
    if type(auraInfo) == "table" then
        canAccessAuraInfo = canAccessTable(auraInfo)
    end

    return {
        reason = reason,
        auraInfoType = type(auraInfo),
        canAccessAuraInfo = canAccessAuraInfo,
        viewerExists = viewer ~= nil,
        viewerShown = getFrameShown(viewer),
        viewerAlpha = getFrameAlpha(viewer),
        inCombatLockdown = InCombatLockdown(),
        instanceName = instanceName,
        instanceType = instanceType,
        instanceID = instanceID,
        difficultyID = difficultyID,
        difficultyName = difficultyName,
        maxPlayers = maxPlayers,
    }
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

---@param auraState ECM_ExternalAuraState|nil
---@return number|nil
local function getRemainingDuration(auraState)
    if auraState == nil or auraState.durationObject == nil then
        return nil
    end

    return auraState.durationObject:GetRemainingDuration()
end

---@param durationText FontString
---@param remaining number
local function setDurationText(durationText, remaining)
    if issecretvalue(remaining) then
        durationText:SetFormattedText("%.0f", remaining)
        return
    end

    durationText:SetText(formatDurationText(remaining))
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

---@param viewer Frame|nil
---@param auraInfo table|nil
---@param reason string|nil
---@return table
function ExternalBars:_GetDiagnostics(viewer, auraInfo, reason)
    viewer = viewer or getViewer()
    if auraInfo == nil and viewer then
        auraInfo = viewer.auraInfo
    end

    local moduleConfig = self:GetModuleConfig()
    local frame = self.InnerFrame
    local auraFrames = viewer and viewer.auraFrames or nil

    local moduleConfigEnabled = nil
    if moduleConfig then
        moduleConfigEnabled = moduleConfig.enabled ~= false
    end

    local viewerHasUpdateAuras = false
    if viewer then
        viewerHasUpdateAuras = type(viewer.UpdateAuras) == "function"
    end

    return {
        moduleEnabled = self.IsEnabled and self:IsEnabled() or nil,
        moduleConfigEnabled = moduleConfigEnabled,
        moduleHidden = self.IsHidden == true,
        frameCreated = frame ~= nil,
        frameShown = getFrameShown(frame),
        frameWidth = getFrameWidth(frame),
        frameHeight = getFrameHeight(frame),
        viewerExists = viewer ~= nil,
        viewerShown = getFrameShown(viewer),
        viewerAlpha = getFrameAlpha(viewer),
        viewerHooked = self._viewerHooked == true,
        viewerHasUpdateAuras = viewerHasUpdateAuras,
        originalIconsHidden = self._originalIconsHidden == true,
        activeAuraCount = self._activeAuraCount or 0,
        auraInfoType = type(auraInfo),
        auraInfoArrayCount = countAccessibleArray(auraInfo, "AuraInfoDiagnosticsFailed", reason),
        auraInfoKeyCount = countAccessibleKeys(auraInfo, "AuraInfoDiagnosticsFailed", reason),
        auraFramesType = type(auraFrames),
        auraFramesArrayCount = countAccessibleArray(auraFrames, "AuraFramesDiagnosticsFailed", reason),
        auraFramesKeyCount = countAccessibleKeys(auraFrames, "AuraFramesDiagnosticsFailed", reason),
    }
end

---@param index number
---@param bar ECM_ExternalBarMixin|nil
---@param auraState ECM_ExternalAuraState|nil
---@return table
function ExternalBars:_GetBarDiagnostics(index, bar, auraState)
    local iconTexture = bar and bar._iconTexture or nil
    local durationIsSecret = nil
    local canShowDurationText = nil
    local canUpdateDurationBar = nil
    if auraState then
        durationIsSecret = auraState.durationIsSecret
        canShowDurationText = auraState.canShowDurationText
        canUpdateDurationBar = auraState.canUpdateDurationBar
    end

    return {
        index = index,
        auraIndex = auraState and auraState.index or nil,
        auraInstanceID = auraState and auraState.auraInstanceID or nil,
        name = auraState and auraState.name or nil,
        spellID = auraState and auraState.spellID or nil,
        texture = auraState and auraState.texture or nil,
        durationIsSecret = durationIsSecret,
        canShowDurationText = canShowDurationText,
        canUpdateDurationBar = canUpdateDurationBar,
        barExists = bar ~= nil,
        barShown = getFrameShown(bar),
        barWidth = getFrameWidth(bar),
        barHeight = getFrameHeight(bar),
        iconShown = bar and bar.Icon and getFrameShown(bar.Icon) or nil,
        iconTexture = iconTexture and iconTexture.GetTexture and iconTexture:GetTexture() or nil,
        cooldownSpellID = bar and bar.cooldownInfo and bar.cooldownInfo.spellID or nil,
    }
end

---@param hidden boolean
function ExternalBars:_SetOriginalIconsHidden(hidden)
    local viewer = getViewer()
    if not viewer then
        return
    end

    if hidden then
        if self._originalIconsHidden then
            return
        end

        self._originalIconsHidden = true
        viewer:SetAlpha(0)
        viewer:EnableMouse(false)
        return
    end

    if not self._originalIconsHidden then
        return
    end

    self._originalIconsHidden = nil
    viewer:SetAlpha(1)
    viewer:EnableMouse(true)
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
---@param remaining number|nil
function ExternalBars:_RefreshBarDurationText(bar, auraState, showDuration, remaining)
    local durationText = bar and bar.Bar and bar.Bar.Duration
    if not durationText then
        return
    end

    if showDuration == false or auraState == nil or not auraState.canShowDurationText then
        durationText:SetText(nil)
        durationText:Hide()
        return
    end

    remaining = remaining or getRemainingDuration(auraState)
    if remaining == nil then
        durationText:SetText(nil)
        durationText:Hide()
        return
    end

    setDurationText(durationText, remaining)
    durationText:Show()
end

---@param bar ECM_ExternalBarMixin
---@param auraState ECM_ExternalAuraState|nil
---@return number|nil
function ExternalBars:_RefreshBarDurationProgress(bar, auraState)
    local statusBar = bar and bar.Bar
    if not statusBar then
        return nil
    end

    if auraState == nil or auraState.durationObject == nil then
        statusBar:SetMinMaxValues(0, 1)
        statusBar:SetValue(1)
        return nil
    end

    statusBar:SetMinMaxValues(0, 1)
    statusBar:SetTimerDuration(
        auraState.durationObject,
        Enum.StatusBarInterpolation.ExponentialEaseOut,
        Enum.StatusBarTimerDirection.RemainingTime
    )
    statusBar:SetToTargetValue()
    return getRemainingDuration(auraState)
end

function ExternalBars:_RefreshDurationDisplays()
    local moduleConfig = self:GetModuleConfig()
    if not moduleConfig then
        self:_StopDurationTicker()
        return
    end

    local hasEligibleBars = false
    local showDuration = moduleConfig.showDuration ~= false
    local barPool = self._barPool or {}
    local auraStates = self._auraStates or {}
    local activeAuraCount = self._activeAuraCount or 0

    for index = 1, activeAuraCount do
        local bar = barPool[index]
        local auraState = auraStates[index]
        if bar and bar:IsShown() and auraState and auraState.canUpdateDurationBar then
            hasEligibleBars = true
        end
        if bar then
            self:_RefreshBarDurationText(bar, auraState, showDuration)
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
        if auraState and auraState.canUpdateDurationBar then
            self._durationTicker = C_Timer.NewTicker(0.1, function()
                self:_RefreshDurationDisplays()
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

    bar:Hide()
    self._barPool[index] = bar
    return bar
end

---@param activeCount number
function ExternalBars:_hideExcessBars(activeCount)
    local barPool = self._barPool or {}
    if ns.IsDebugEnabled() and #barPool > activeCount then
        ns.Log(self.Name, "Hiding excess external bars", {
            activeCount = activeCount,
            pooledBars = #barPool,
        })
    end

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
            bar.Bar:SetMinMaxValues(0, 1)
            bar.Bar:SetValue(1)
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

    self:_RefreshBarDurationText(
        bar,
        auraState,
        moduleConfig and moduleConfig.showDuration ~= false,
        self:_RefreshBarDurationProgress(bar, auraState)
    )

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
    ns.Log(self.Name, "Frame created", {
        frameName = "ECMExternalBars",
        frameWidth = frame:GetWidth(),
        frameHeight = frame:GetHeight(),
    })
    return frame
end

function ExternalBars:HookViewer()
    local viewer = getViewer()
    if not viewer then
        if ns.IsDebugEnabled() then
            ns.Log(self.Name, "HookViewer skipped", {
                reason = "missing-viewer",
                diagnostics = self:_GetDiagnostics(viewer, nil, "HookViewer:missing-viewer"),
            })
        end
        return
    end

    if self._viewerHooked then
        if ns.IsDebugEnabled() then
            ns.Log(self.Name, "HookViewer skipped", {
                reason = "already-hooked",
                diagnostics = self:_GetDiagnostics(viewer, nil, "HookViewer:already-hooked"),
            })
        end
        return
    end

    self._viewerHooked = true

    hooksecurefunc(viewer, "UpdateAuras", function()
        if self:IsEnabled() then
            self:OnExternalAurasUpdated("viewer:UpdateAuras")
        end
    end)

    viewer:HookScript("OnShow", function()
        if not self:IsEnabled() then
            return
        end
        self:_RefreshOriginalIconsState()
        self:OnExternalAurasUpdated("viewer:OnShow")
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

    if ns.IsDebugEnabled() then
        ns.Log(self.Name, "Hooked ExternalDefensivesFrame", self:_GetDiagnostics(viewer, nil, "HookViewer:hooked"))
    end
end

---@param reason string|nil
function ExternalBars:OnExternalAurasUpdated(reason)
    self:HookViewer()
    self:_RefreshOriginalIconsState()

    local viewer = getViewer()
    local auraInfo = viewer and viewer.auraInfo or nil
    local auraStates = self._auraStates or {}
    self._auraStates = auraStates
    local debugEnabled = ns.IsDebugEnabled()
    local auraDiagnostics = debugEnabled and {} or nil

    local activeAuraCount = 0
    if type(auraInfo) == "table" and not canAccessTable(auraInfo) then
        wipe(auraStates)
        self:_hideExcessBars(0)
        self:_StopDurationTicker()
        local data = getAuraInfoErrorData(reason, viewer, auraInfo)
        data.activeAuraCountBefore = self._activeAuraCount or 0
        ns.ErrorLogOnce("ExternalBars", "AuraInfoInaccessible", "Blizzard external aura info is inaccessible", data)
    elseif type(auraInfo) == "table" then
        local ok, err = pcall(function()
            for index, info in ipairs(auraInfo) do
                if type(info) ~= "table" or not canAccessTable(info) then
                    error("inaccessible external aura info entry at index " .. tostring(index))
                end

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
                local durationObject = C_UnitAuras.GetAuraDuration(PLAYER_UNIT, auraInstanceID)
                local canUpdateDurationBar = durationObject ~= nil

                auraState.index = index
                auraState.auraInstanceID = auraInstanceID
                auraState.name = auraName
                auraState.spellID = spellID
                auraState.texture = info.texture
                auraState.duration = duration
                auraState.expirationTime = expirationTime
                auraState.durationObject = durationObject
                auraState.durationIsSecret = durationIsSecret
                auraState.canShowDurationText = canUpdateDurationBar
                auraState.canUpdateDurationBar = canUpdateDurationBar

                if auraDiagnostics then
                    auraDiagnostics[#auraDiagnostics + 1] = {
                        index = index,
                        auraInstanceID = auraInstanceID,
                        name = auraName,
                        spellID = spellID,
                        texture = info.texture,
                        hasAuraData = accessibleAuraData ~= nil,
                        durationIsSecret = durationIsSecret,
                        expirationTimeIsSecret = expirationTimeIsSecret,
                        canShowDurationText = auraState.canShowDurationText,
                        canUpdateDurationBar = auraState.canUpdateDurationBar,
                    }
                end
            end
        end)
        if not ok then
            activeAuraCount = 0
            wipe(auraStates)
            self:_hideExcessBars(0)
            self:_StopDurationTicker()
            local data = getAuraInfoErrorData(reason, viewer, auraInfo)
            data.activeAuraCountBefore = self._activeAuraCount or 0
            data.error = tostring(err)
            ns.ErrorLogOnce("ExternalBars", "AuraInfoIterateFailed", "Blizzard external aura info could not be iterated", data)
        end
    end

    self._activeAuraCount = activeAuraCount

    if debugEnabled then
        ns.Log(self.Name, "OnExternalAurasUpdated", {
            reason = reason,
            diagnostics = self:_GetDiagnostics(viewer, auraInfo, reason),
            viewerShown = viewer ~= nil and viewer:IsShown() or false,
            viewerAlpha = viewer and viewer.GetAlpha and viewer:GetAlpha() or nil,
            viewerHooked = self._viewerHooked == true,
            hideOriginalIcons = self._originalIconsHidden == true,
            runtimeOriginalIconsHidden = self._originalIconsHidden == true,
            auraCount = activeAuraCount,
            auraInfoType = type(auraInfo),
            auras = auraDiagnostics,
        })
    end

    ns.Runtime.RequestLayout("ExternalBars:" .. (reason or "UpdateAuras"))
end

---@param why string|nil
---@return boolean
function ExternalBars:UpdateLayout(why)
    local frame = self.InnerFrame
    local debugEnabled = ns.IsDebugEnabled()
    if not frame then
        if debugEnabled then
            ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")", {
                applied = false,
                reason = "no-frame",
                diagnostics = self:_GetDiagnostics(),
                activeAuraCount = self._activeAuraCount or 0,
            })
        end
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
        if debugEnabled then
            ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")", {
                applied = false,
                reason = "no-position",
                diagnostics = self:_GetDiagnostics(),
                activeAuraCount = self._activeAuraCount or 0,
            })
        end
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
    local barDiagnostics = debugEnabled and {} or nil
    local ok, err = pcall(function()
        for index = 1, activeAuraCount do
            local auraState = auraStates[index]
            if auraState then
                local bar = self:_ensureBar(index)
                self:_ConfigureBar(bar, auraState, moduleConfig, globalConfig, styleConfig, spellColors)
                activeBars[#activeBars + 1] = bar
                if barDiagnostics then
                    barDiagnostics[#barDiagnostics + 1] = self:_GetBarDiagnostics(index, bar, auraState)
                end

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
        if debugEnabled then
            ns.Log(self.Name, "UpdateLayout error", {
                error = tostring(err),
                diagnostics = self:_GetDiagnostics(),
                activeAuraCount = activeAuraCount,
                bars = barDiagnostics,
            })
        end
        ns.DebugAssert(false, "Error styling external bars: " .. tostring(err))
        return false
    end

    local barCount = #activeBars
    local barHeight = self:_GetBarHeight(styleConfig, globalConfig)
    local verticalSpacing = math.max(0, moduleConfig and moduleConfig.verticalSpacing or 0)
    local totalHeight = (barCount * barHeight) + (math.max(0, barCount - 1) * verticalSpacing)
    FrameUtil.LazySetHeight(frame, totalHeight)

    self:_RestartDurationTicker()

    if debugEnabled then
        local viewer = getViewer()
        ns.Log(self.Name, "UpdateLayout (" .. (why or "") .. ")", {
            diagnostics = self:_GetDiagnostics(viewer, nil, why),
            activeAuraCount = activeAuraCount,
            barCount = barCount,
            bars = barDiagnostics,
            viewerShown = viewer ~= nil and viewer:IsShown() or false,
            viewerAlpha = viewer and viewer.GetAlpha and viewer:GetAlpha() or nil,
            viewerHooked = self._viewerHooked == true,
            hideOriginalIcons = self._originalIconsHidden == true,
            runtimeOriginalIconsHidden = self._originalIconsHidden == true,
            editLocked = self._editLocked == true,
            anchorPoint = params.anchorPoint,
            offsetX = params.offsetX,
            offsetY = params.offsetY,
        })
    end
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
    if ns.IsDebugEnabled() then
        ns.Log(self.Name, "OnEnable", self:_GetDiagnostics(nil, nil, "OnEnable"))
    end

    C_Timer.After(0.1, function()
        if not self:IsEnabled() then
            return
        end

        self:HookViewer()
        self:_RefreshOriginalIconsState()
        self:OnExternalAurasUpdated("OnEnable")
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
