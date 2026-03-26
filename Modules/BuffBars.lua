-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local FrameMixin = ECM.FrameMixin
local FrameUtil = ECM.FrameUtil
local ChainRightPoint = FrameMixin.Proto.ChainRightPoint
local EditMode = ECM.EditMode
local BuffBars = ns.Addon:NewModule("BuffBars")
ns.Addon.BuffBars = BuffBars

---@class ECM_BuffBarMixin : Frame
---@field __ecmHooked boolean
---@field Bar StatusBar
---@field DebuffBorder any
---@field Icon Frame
---@field ignoreInLayout boolean|nil
---@field layoutIndex number|nil
---@field cooldownID number|nil
---@field cooldownInfo { spellID: number|nil }|nil

local function getChildrenOrdered(viewer)
    local result = {}
    for insertOrder, child in ipairs({ viewer:GetChildren() }) do
        if child and not child.ignoreInLayout then
            result[#result + 1] = {
                frame = child,
                layoutIndex = child.layoutIndex,
                order = insertOrder,
            }
        end
    end

    table.sort(result, function(a, b)
        local aLayoutIndex = a.layoutIndex
        local bLayoutIndex = b.layoutIndex
        if aLayoutIndex ~= bLayoutIndex then
            if aLayoutIndex == nil then
                return false
            end
            if bLayoutIndex == nil then
                return true
            end
            return aLayoutIndex < bLayoutIndex
        end
        return a.order < b.order
    end)

    return result
end

--- Strips circular masks and hides overlay/border to produce a square icon.
--- The heavy cleanup (mask removal, pcalls, region iteration) is cached on the
--- frame via `__ecmSquareStyled` so it only runs once per icon frame.
---@param iconFrame Frame|nil
---@param iconTexture Texture|nil
---@param iconOverlay Texture|nil
---@param debuffBorder Texture|nil
local function applySquareIconStyle(iconFrame, iconTexture, iconOverlay, debuffBorder)
    if not iconFrame or iconFrame.__ecmSquareStyled or not iconTexture then
        return
    end

    iconTexture:SetTexCoord(0, 1, 0, 1)

    -- Remove circular masks from the icon texture
    if iconTexture.GetNumMaskTextures and iconTexture.RemoveMaskTexture and iconTexture.GetMaskTexture then
        for i = (iconTexture:GetNumMaskTextures() or 0), 1, -1 do
            local mask = iconTexture:GetMaskTexture(i)
            if mask then
                iconTexture:RemoveMaskTexture(mask)
                if mask.Hide then mask:Hide() end
            end
        end
    elseif iconTexture.SetMask then
        pcall(iconTexture.SetMask, iconTexture, nil)
    end

    -- Remove mask regions from the icon frame
    if iconFrame.GetRegions and iconTexture.RemoveMaskTexture then
        for _, region in ipairs({ iconFrame:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("MaskTexture") then
                pcall(iconTexture.RemoveMaskTexture, iconTexture, region)
                if region.Hide then region:Hide() end
            end
        end
    end

    if iconOverlay then iconOverlay:Hide() end
    if debuffBorder then debuffBorder:Hide() end

    iconFrame.__ecmSquareStyled = true
end

--- Applies all sizing, styling, visibility, and anchoring to a single buff bar
--- child frame. Lazy setters ensure no-ops when values haven't changed.
---@param frame ECM_BuffBarMixin
---@param config table Module config
---@param globalConfig table Global config
---@param barIndex number Index of the bar (for logging)
---@param retryCount number|nil Number of times this function has been retried
local function styleChildFrame(module, frame, config, globalConfig, barIndex, retryCount)
    if not (frame and frame.__ecmHooked) then
        ECM.DebugAssert(false, "Attempted to style a child frame that wasn't hooked.")
        return
    end

    retryCount = retryCount or 0
    local bar = frame.Bar
    local iconFrame = frame.Icon
    local barBG = FrameUtil.GetBarBackground(bar)

    -- frame
    --  - Bar
    --     - Name
    --     - Duration
    --     - Pip
    --     - BarBG
    --  - Icon
    --    - Applications
    --  - DebuffBorder

    --------------------------------------------------------------------------
    -- Heights
    --------------------------------------------------------------------------
    local height = (config and config.height) or (globalConfig and globalConfig.barHeight) or 15
    if height > 0 then
        FrameUtil.LazySetHeight(frame, height)
        FrameUtil.LazySetHeight(bar, height)
        if iconFrame then
            FrameUtil.LazySetHeight(iconFrame, height)
            FrameUtil.LazySetWidth(iconFrame, height)
        end
    end

    --------------------------------------------------------------------------
    -- Pip — always hidden
    --------------------------------------------------------------------------
    bar.Pip:Hide()
    bar.Pip:SetTexture(nil)

    --------------------------------------------------------------------------
    -- Bar background (BarBG texture)
    --------------------------------------------------------------------------
    if barBG then
        -- One-time setup: reparent BarBG to the outer frame and hook SetPoint
        -- so Blizzard cannot override our anchors. SetAllPoints does not fire
        -- SetPoint hooks, so no re-entrancy guard is needed.
        if not barBG.__ecmBGHooked then
            barBG.__ecmBGHooked = true
            barBG:SetParent(frame)
            hooksecurefunc(barBG, "SetPoint", function()
                barBG:ClearAllPoints()
                barBG:SetAllPoints(frame)
            end)
        end

        local bgColor = (config and config.bgColor)
            or (globalConfig and globalConfig.barBgColor)
            or ECM.Constants.COLOR_BLACK
        barBG:SetTexture(ECM.Constants.FALLBACK_TEXTURE)
        barBG:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
        barBG:ClearAllPoints()
        barBG:SetAllPoints(frame)
        barBG:SetDrawLayer("BACKGROUND", 0)
    end

    --------------------------------------------------------------------------
    -- StatusBar texture & color
    --------------------------------------------------------------------------
    local textureName = globalConfig and globalConfig.texture
    local texture = ECM.GetTexture(textureName)
    FrameUtil.LazySetStatusBarTexture(bar, texture)

    local barColor = ECM.SpellColors.GetColorForBar(frame)
    local spellName = frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText()
    local spellID = frame.cooldownInfo and frame.cooldownInfo.spellID
    local cooldownID = frame.cooldownID
    local textureFileID = FrameUtil.GetIconTextureFileID(frame)

    -- When in a raid instance, and after exiting combat, all identifying
    -- values may remain secret.  Lock editing only when every key is
    -- unusable.  With four tiers (name, spellID, cooldownID, texture)
    -- the colour lookup is much more resilient to partial secrecy.
    local allSecret = issecretvalue(spellName)
        and issecretvalue(spellID)
        and issecretvalue(cooldownID)
        and issecretvalue(textureFileID)
    module._editLocked = module._editLocked or allSecret

    if allSecret and not InCombatLockdown() then
        if retryCount < 3 then
            C_Timer.After(1, function()
                styleChildFrame(module, frame, config, globalConfig, barIndex, retryCount + 1)
            end)
            -- Don't apply any colour while retries are pending — preserve
            -- the bar's existing colour rather than clobbering it with the
            -- default while we wait for secrets to clear.
            barColor = nil
        elseif ECM.IsDebugEnabled() and not module._warned then
            ECM.Log(ECM.Constants.BUFFBARS, "All identifying keys are secret outside of combat.")
            module._warned = true
        end
    end

    if barColor == nil and not allSecret then
        barColor = ECM.SpellColors.GetDefaultColor()
    end
    if barColor then
        FrameUtil.LazySetStatusBarColor(bar, barColor.r, barColor.g, barColor.b, 1.0)
    end

    --------------------------------------------------------------------------
    -- Fonts (before visibility/positioning — font changes affect layout)
    --------------------------------------------------------------------------
    ECM.ApplyFont(bar.Name, globalConfig, config)
    ECM.ApplyFont(bar.Duration, globalConfig, config)

    --------------------------------------------------------------------------
    -- Icon anchor
    --------------------------------------------------------------------------
    if iconFrame then
        FrameUtil.LazySetAnchors(iconFrame, {
            { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
        })
    end

    --------------------------------------------------------------------------
    -- Visibility — icon, name, duration, debuff border, applications
    --------------------------------------------------------------------------
    local showIcon = config and config.showIcon ~= false
    if iconFrame then
        local iconTexture = FrameUtil.GetIconTexture(frame)
        local iconOverlay = FrameUtil.GetIconOverlay(frame)
        applySquareIconStyle(iconFrame, iconTexture, iconOverlay, frame.DebuffBorder)
        iconFrame:SetShown(showIcon)
        if iconTexture then
            iconTexture:SetShown(showIcon)
        end
    end

    if frame.DebuffBorder then
        FrameUtil.LazySetAlpha(frame.DebuffBorder, 0)
        frame.DebuffBorder:Hide()
    end
    if iconFrame.Applications then
        FrameUtil.LazySetAlpha(iconFrame.Applications, showIcon and 1 or 0)
    end

    local showSpellName = config and config.showSpellName ~= false
    local showDuration = config and config.showDuration ~= false
    if bar.Name then
        bar.Name:SetShown(showSpellName)
    end
    if bar.Duration then
        bar.Duration:SetShown(showDuration)
    end

    --------------------------------------------------------------------------
    -- Bar anchors (relative to icon visibility)
    --------------------------------------------------------------------------
    local iconVisible = iconFrame and iconFrame:IsShown()
    if iconVisible then
        FrameUtil.LazySetAnchors(bar, {
            { "TOPLEFT", iconFrame, "TOPRIGHT", 0, 0 },
            { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 },
        })
    else
        FrameUtil.LazySetAnchors(bar, {
            { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
            { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 },
        })
    end

    --------------------------------------------------------------------------
    -- Name
    --------------------------------------------------------------------------
    FrameUtil.LazySetAnchors(bar.Name, {
        { "LEFT", bar, "LEFT", ECM.Constants.BUFFBARS_TEXT_PADDING, 0 },
        { "RIGHT", bar, "RIGHT", -ECM.Constants.BUFFBARS_TEXT_PADDING, 0 },
    })

    if bar.Duration then
        FrameUtil.LazySetAnchors(bar.Duration, {
            { "RIGHT", bar, "RIGHT", -ECM.Constants.BUFFBARS_TEXT_PADDING, 0 },
        })
    end
end

local function hookChildFrame(child, module)
    if child.__ecmHooked then
        return
    end

    -- Hook various parts of the blizzard frames to ensure our modifications aren't removed or overridden.
    -- Each hook guards against _layoutRunning to prevent recursion from our lazy setters.
    hooksecurefunc(child, "SetPoint", function()
        if module._layoutRunning then
            return
        end
        module._layoutRunning = true
        local cached = child.__ecmAnchorCache
        -- Restore the child's cached anchors to undo Blizzard's repositioning
        -- before the next render frame. LazySetAnchors populates __ecmAnchorCache
        -- during layoutBars, so after the first layout pass this is always available.
        if cached then
            FrameUtil.LazySetAnchors(child, cached)
        end
        styleChildFrame(module, child, module:GetModuleConfig(), module:GetGlobalConfig(), 0)
        module._layoutRunning = nil
        module:ThrottledUpdateLayout("SetPoint:hook", { secondPass = true })
    end)

    child:HookScript("OnShow", function()
        if module._layoutRunning then
            return
        end
        module._layoutRunning = true
        styleChildFrame(module, child, module:GetModuleConfig(), module:GetGlobalConfig(), 0)
        module._layoutRunning = nil
        module:ThrottledUpdateLayout("OnShow:child", { secondPass = true })
    end)

    child:HookScript("OnHide", function()
        if module._layoutRunning then
            return
        end
        module:ThrottledUpdateLayout("OnHide:child", { secondPass = true })
    end)

    child.__ecmHooked = true
end

local function getViewerPosition(module)
    local cfg = module:GetModuleConfig()
    local mode = cfg and cfg.anchorMode or ECM.Constants.ANCHORMODE_CHAIN

    if mode ~= ECM.Constants.ANCHORMODE_FREE then
        local params = FrameMixin.Proto.CalculateLayoutParams(module)
        return {
            mode = params.mode,
            anchor = params.anchor,
            point = params.anchorPoint,
            relativePoint = params.anchorRelativePoint,
            x = params.offsetX,
            y = params.offsetY,
        }
    end

    local pos = EditMode.GetPosition(cfg and cfg.editModePositions)
    return {
        mode = mode,
        anchor = UIParent,
        point = pos.point,
        relativePoint = pos.point,
        x = pos.x,
        y = pos.y,
    }
end

--- Positions all bar children in a vertical stack, preserving edit mode order.
local function layoutBars(viewer, growsUp, verticalSpacing)
    local children = getChildrenOrdered(viewer)
    local prev

    local function anchorChild(child)
        if not child:IsShown() then
            return
        end

        local selfEdge = growsUp and "BOTTOM" or "TOP"
        local relEdge = prev and (growsUp and "TOP" or "BOTTOM") or selfEdge
        local anchor = prev or viewer
        local spacing = not prev and 0 or (growsUp and verticalSpacing or -verticalSpacing)

        FrameUtil.LazySetAnchors(child, {
            { selfEdge .. "LEFT", anchor, relEdge .. "LEFT", 0, spacing },
            { selfEdge .. "RIGHT", anchor, relEdge .. "RIGHT", 0, spacing },
        })
        prev = child
    end

    if growsUp then
        for i = #children, 1, -1 do
            anchorChild(children[i].frame)
        end
    else
        for _, entry in ipairs(children) do
            anchorChild(entry.frame)
        end
    end
end

--- Buff bars are backed by Blizzard's BuffBarCooldownViewer system frame.
--- Registering that frame with the addon Edit Mode wrapper taints Blizzard's
--- own Edit Mode selection handling, so BuffBars must opt out.
---@return boolean
function BuffBars:ShouldRegisterEditMode()
    return false
end

function BuffBars:CreateFrame()
    return _G["BuffBarCooldownViewer"]
end

function BuffBars:IsReady()
    if not ECM.FrameMixin.Proto.IsReady(self) then
        return false
    end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return false
    end

    return pcall(viewer.GetChildren, viewer)
end

--- Override UpdateLayout to position the BuffBarViewer and apply styling to children.
function BuffBars:UpdateLayout(why)
    local viewer = _G["BuffBarCooldownViewer"]
    local globalConfig = self:GetGlobalConfig()
    local cfg = self:GetModuleConfig()

    if why == "PLAYER_SPECIALIZATION_CHANGED" then
        ECM.SpellColors.ClearDiscoveredKeys()
    end

    -- Discover bars regardless of visibility so the spell colours options
    -- panel has the full list even when hidden (e.g. resting).
    local visibleChildren = getChildrenOrdered(viewer)
    for _, entry in ipairs(visibleChildren) do
        ECM.SpellColors.DiscoverBar(entry.frame)
    end

    if not self:ShouldShow() then
        viewer:Hide()
        return false
    end

    local position = getViewerPosition(self)
    -- Free-positioned buff bars no longer have a separate grow-direction setting,
    -- so the effective anchor point decides stack direction: bottom-left grows upward,
    -- everything else grows downward.
    local growsUp = position.point == "BOTTOMLEFT"
    local verticalSpacing = math.max(0, cfg and cfg.verticalSpacing or 0)

    if position.mode == ECM.Constants.ANCHORMODE_FREE then
        FrameUtil.LazySetAnchors(viewer, {
            { position.point, position.anchor, position.relativePoint, position.x, position.y },
        })

        local baseBarWidth = viewer.baseBarWidth
        local barWidthScale = viewer.barWidthScale
        if type(baseBarWidth) == "number" and type(barWidthScale) == "number" then
            local width = baseBarWidth * barWidthScale
            if width > 0 then
                FrameUtil.LazySetWidth(viewer, width)
            end
        end
    else
        local leftAnchorPoint = position.point or "TOPLEFT"
        local leftRelativePoint = position.relativePoint or "BOTTOMLEFT"
        local rightAnchorPoint = ChainRightPoint(leftAnchorPoint, "TOPRIGHT")
        local rightRelativePoint = ChainRightPoint(leftRelativePoint, "BOTTOMRIGHT")
        FrameUtil.LazySetAnchors(viewer, {
            { leftAnchorPoint, position.anchor, leftRelativePoint, position.x, position.y },
            { rightAnchorPoint, position.anchor, rightRelativePoint, position.x, position.y },
        })
    end

    -- Guard against child SetPoint hooks scheduling redundant layout updates
    -- while we are actively styling and positioning bars.
    self._layoutRunning = true

    -- Style all visible children (lazy setters make redundant calls no-ops)
    self._warned = false
    self._editLocked = false
    local ok, err = pcall(function()
        for barIndex, entry in ipairs(visibleChildren) do
            hookChildFrame(entry.frame, self)
            styleChildFrame(self, entry.frame, cfg, globalConfig, barIndex)
        end

        layoutBars(viewer, growsUp, verticalSpacing)
    end)

    self._layoutRunning = nil
    ECM.DebugAssert(ok, "Error styling buff bars: " .. tostring(err))

    viewer:Show()
    ECM.Log(ECM.Constants.BUFFBARS, "UpdateLayout (" .. (why or "") .. ")", {
        mode = position.mode,
        childCount = #visibleChildren,
        anchor = position.anchor and position.anchor:GetName() or "nil",
        anchorPoint = position.point,
        anchorRelativePoint = position.relativePoint,
        offsetX = position.x,
        offsetY = position.y,
    })
    return true
end

--- Returns normalized spell-color keys for all currently-visible aura bars.
--- Secret values are filtered out via MakeKey's validation.
--- Bars where all identifying keys are secret/nil are skipped.
---@return ECM_SpellColorKey[]
function BuffBars:GetActiveSpellData()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return {}
    end

    local ordered = getChildrenOrdered(viewer)
    local result = {}
    for _, entry in ipairs(ordered) do
        local frame = entry.frame
        if frame:IsShown() then
            local name = frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText()
            local sid = frame.cooldownInfo and frame.cooldownInfo.spellID
            local cid = frame.cooldownID
            local tex = FrameUtil.GetIconTextureFileID(frame)
            local key = ECM.SpellColors.MakeKey(name, sid, cid, tex)
            if key then
                result[#result + 1] = key
            end
        end
    end
    return result
end

--- Hooks the BuffBarCooldownViewer for automatic updates.
function BuffBars:HookViewer()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer or self._viewerHooked then
        return
    end
    self._viewerHooked = true

    viewer:HookScript("OnShow", function()
        self:ThrottledUpdateLayout("viewer:OnShow")
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if self._layoutRunning then
            return
        end
        self:ThrottledUpdateLayout("viewer:OnSizeChanged", { secondPass = true })
    end)

    hooksecurefunc(viewer, "SetPoint", function(_, point, relativeTo, relativePoint, x, y)
        if self._layoutRunning then
            return
        end
        if not EditMode.Lib:IsInEditMode() then
            return
        end
        if relativeTo ~= nil and relativeTo ~= UIParent then
            return
        end

        local cfg = self:GetModuleConfig()
        if not cfg or cfg.anchorMode ~= ECM.Constants.ANCHORMODE_FREE then
            return
        end

        local layoutName = EditMode.GetActiveLayoutName()
        if not layoutName then
            return
        end

        local normalizedPoint, normalizedX, normalizedY = FrameUtil.NormalizePosition(
            point,
            relativePoint,
            x,
            y,
            UIParent
        )
        EditMode.SavePosition(cfg, "editModePositions", layoutName, normalizedPoint, normalizedX, normalizedY)
    end)

    ECM.Log(self.Name, "Hooked BuffBarCooldownViewer")
end

function BuffBars:OnZoneChanged()
    self:ThrottledUpdateLayout("OnZoneChanged")
end

--- Gets a boolean indicating if editing is allowed.
--- @return boolean isEditLocked Whether editing is locked due to combat or secrets
--- @return string reason Reason editing is locked ("combat", "secrets", or nil)
function BuffBars:IsEditLocked()
    local reason = InCombatLockdown() and "combat" or (self._editLocked and "secrets") or nil
    return reason ~= nil, reason
end

function BuffBars:OnInitialize()
    ECM.FrameMixin.AddMixin(self, "BuffBars")
end

function BuffBars:OnEnable()
    ECM.SpellColors.SetConfigAccessor(function()
        return self:GetModuleConfig()
    end)

    self:EnsureFrame()
    ECM.Runtime.RegisterFrame(self)

    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("ZONE_CHANGED", "OnZoneChanged")
    self:RegisterEvent("ZONE_CHANGED_INDOORS", "OnZoneChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnZoneChanged")

    C_Timer.After(0.1, function()
        self:HookViewer()
        self:ThrottledUpdateLayout("ModuleInit")
    end)
end

function BuffBars:OnDisable()
    ECM.SpellColors.SetConfigAccessor(nil)
    self:UnregisterAllEvents()
    ECM.Runtime.UnregisterFrame(self)
end
