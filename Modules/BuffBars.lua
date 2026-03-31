-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local BarMixin = ns.BarMixin
local FrameUtil = ns.FrameUtil
local ChainRightPoint = BarMixin.FrameProto.ChainRightPoint
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

local function styleBarHeight(frame, bar, iconFrame, config, globalConfig)
    local height = (config and config.height) or (globalConfig and globalConfig.barHeight) or 15
    if height <= 0 then
        return
    end
    FrameUtil.LazySetHeight(frame, height)
    FrameUtil.LazySetHeight(bar, height)
    if iconFrame then
        FrameUtil.LazySetHeight(iconFrame, height)
        FrameUtil.LazySetWidth(iconFrame, height)
    end
end

local function styleBarBackground(frame, barBG, config, globalConfig)
    if not barBG then
        return
    end

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
        or ns.Constants.COLOR_BLACK
    barBG:SetTexture(ns.Constants.FALLBACK_TEXTURE)
    barBG:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    barBG:ClearAllPoints()
    barBG:SetAllPoints(frame)
    barBG:SetDrawLayer("BACKGROUND", 0)
end

--- Resolves the spell color for a bar, handling secret values with retry.
--- Returns true if the module's _editLocked flag was set by this call.
local function styleBarColor(module, frame, bar, globalConfig, retryCount)
    local textureName = globalConfig and globalConfig.texture
    FrameUtil.LazySetStatusBarTexture(bar, FrameUtil.GetTexture(textureName))

    local barColor = ns.SpellColors.GetColorForBar(frame)
    local spellName = bar.Name and bar.Name.GetText and bar.Name:GetText()
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
            if frame._ecmColorRetryTimer then
                frame._ecmColorRetryTimer:Cancel()
            end
            frame._ecmColorRetryTimer = C_Timer.NewTimer(1, function()
                frame._ecmColorRetryTimer = nil
                styleBarColor(module, frame, bar, globalConfig, retryCount + 1)
            end)
            -- Don't apply any colour while retries are pending — preserve
            -- the bar's existing colour rather than clobbering it with the
            -- default while we wait for secrets to clear.
            return
        elseif ns.IsDebugEnabled() and not module._warned then
            ns.Log(ns.Constants.BUFFBARS, "All identifying keys are secret outside of combat.")
            module._warned = true
        end
    end

    if frame._ecmColorRetryTimer then
        frame._ecmColorRetryTimer:Cancel()
        frame._ecmColorRetryTimer = nil
    end

    if barColor == nil and not allSecret then
        barColor = ns.SpellColors.GetDefaultColor()
    end
    if barColor then
        FrameUtil.LazySetStatusBarColor(bar, barColor.r, barColor.g, barColor.b, 1.0)
    end
end

local function styleBarIcon(frame, iconFrame, config)
    local showIcon = config and config.showIcon ~= false

    if iconFrame then
        FrameUtil.LazySetAnchors(iconFrame, {
            { "TOPLEFT", frame, "TOPLEFT", 0, 0 },
        })
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
    if iconFrame and iconFrame.Applications then
        FrameUtil.LazySetAlpha(iconFrame.Applications, showIcon and 1 or 0)
    end
end

local function styleBarAnchors(frame, bar, iconFrame, config)
    local showSpellName = config and config.showSpellName ~= false
    local showDuration = config and config.showDuration ~= false
    if bar.Name then
        bar.Name:SetShown(showSpellName)
    end
    if bar.Duration then
        bar.Duration:SetShown(showDuration)
    end

    local iconVisible = iconFrame and iconFrame:IsShown()
    local barLeftAnchor = iconVisible and iconFrame or frame
    local barLeftPoint = iconVisible and "TOPRIGHT" or "TOPLEFT"
    FrameUtil.LazySetAnchors(bar, {
        { "TOPLEFT", barLeftAnchor, barLeftPoint, 0, 0 },
        { "TOPRIGHT", frame, "TOPRIGHT", 0, 0 },
    })

    FrameUtil.LazySetAnchors(bar.Name, {
        { "LEFT", bar, "LEFT", ns.Constants.BUFFBARS_TEXT_PADDING, 0 },
        { "RIGHT", bar, "RIGHT", -ns.Constants.BUFFBARS_TEXT_PADDING, 0 },
    })

    if bar.Duration then
        FrameUtil.LazySetAnchors(bar.Duration, {
            { "RIGHT", bar, "RIGHT", -ns.Constants.BUFFBARS_TEXT_PADDING, 0 },
        })
    end
end

--- Applies all sizing, styling, visibility, and anchoring to a single buff bar
--- child frame. Lazy setters ensure no-ops when values haven't changed.
local function styleChildFrame(module, frame, config, globalConfig)
    if not (frame and frame.__ecmHooked) then
        ns.DebugAssert(false, "Attempted to style a child frame that wasn't hooked.")
        return
    end

    local bar = frame.Bar
    local iconFrame = frame.Icon

    styleBarHeight(frame, bar, iconFrame, config, globalConfig)

    bar.Pip:Hide()
    bar.Pip:SetTexture(nil)

    styleBarBackground(frame, FrameUtil.GetBarBackground(bar), config, globalConfig)
    styleBarColor(module, frame, bar, globalConfig, 0)

    FrameUtil.ApplyFont(bar.Name, globalConfig, config)
    FrameUtil.ApplyFont(bar.Duration, globalConfig, config)

    styleBarIcon(frame, iconFrame, config)
    styleBarAnchors(frame, bar, iconFrame, config)
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
        styleChildFrame(module, child, module:GetModuleConfig(), module:GetGlobalConfig())
        module._layoutRunning = nil
        ns.Runtime.RequestLayout("BuffBars:SetPoint:hook", { secondPass = true })
    end)

    child:HookScript("OnShow", function()
        if module._layoutRunning then
            return
        end
        module._layoutRunning = true
        styleChildFrame(module, child, module:GetModuleConfig(), module:GetGlobalConfig())
        module._layoutRunning = nil
        ns.Runtime.RequestLayout("BuffBars:OnShow:child", { secondPass = true })
    end)

    child:HookScript("OnHide", function()
        if module._layoutRunning then
            return
        end
        ns.Runtime.RequestLayout("BuffBars:OnHide:child", { secondPass = true })
    end)

    child.__ecmHooked = true
end

local function getViewerPosition(module)
    local cfg = module:GetModuleConfig()
    local mode = cfg and cfg.anchorMode or ns.Constants.ANCHORMODE_CHAIN

    -- In free mode Blizzard owns the viewer position entirely — return nil
    -- so UpdateLayout knows not to reposition.
    if mode == ns.Constants.ANCHORMODE_FREE then
        return nil
    end

    local params = BarMixin.FrameProto.CalculateLayoutParams(module)
    return {
        mode = params.mode,
        anchor = params.anchor,
        point = params.anchorPoint,
        relativePoint = params.anchorRelativePoint,
        x = params.offsetX,
        y = params.offsetY,
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
    if not BarMixin.FrameProto.IsReady(self) then
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

    if why == "PLAYER_SPECIALIZATION_CHANGED" or why == "ProfileChanged" then
        ns.SpellColors.ClearDiscoveredKeys()
    end

    -- Discover bars regardless of visibility so the spell colours options
    -- panel has the full list even when hidden (e.g. resting).
    local visibleChildren = getChildrenOrdered(viewer)
    for _, entry in ipairs(visibleChildren) do
        ns.SpellColors.DiscoverBar(entry.frame)
    end

    if not self:ShouldShow() then
        viewer:Hide()
        return false
    end

    local position = getViewerPosition(self)
    local verticalSpacing = math.max(0, cfg and cfg.verticalSpacing or 0)

    if position then
        -- Chain/detached: ECM owns the viewer position.
        local leftAnchorPoint = position.point or "TOPLEFT"
        local leftRelativePoint = position.relativePoint or "BOTTOMLEFT"
        local rightAnchorPoint = ChainRightPoint(leftAnchorPoint, "TOPRIGHT")
        local rightRelativePoint = ChainRightPoint(leftRelativePoint, "BOTTOMRIGHT")
        FrameUtil.LazySetAnchors(viewer, {
            { leftAnchorPoint, position.anchor, leftRelativePoint, position.x, position.y },
            { rightAnchorPoint, position.anchor, rightRelativePoint, position.x, position.y },
        })
    else
        -- Free mode: Blizzard owns position and width. Snapshot the viewer's
        -- current width so child 2-point anchoring works even after Blizzard
        -- stops actively managing the frame (e.g. after exiting edit mode).
        local viewerWidth = viewer:GetWidth()
        local baseBarWidth = viewer.baseBarWidth
        local barWidthScale = viewer.barWidthScale
        if type(baseBarWidth) == "number" and type(barWidthScale) == "number" then
            local computed = baseBarWidth * barWidthScale
            if computed > 0 then
                viewerWidth = computed
            end
        end
        if viewerWidth and viewerWidth > 0 then
            FrameUtil.LazySetWidth(viewer, viewerWidth)
        end
    end

    -- Determine stack direction from the resolved anchor point.
    local growsUp
    if position then
        growsUp = position.point == "BOTTOMLEFT"
    else
        -- In free mode, infer from the viewer's current (Blizzard-managed) anchor.
        local currentPoint = viewer.GetPoint and viewer:GetPoint(1)
        growsUp = currentPoint == "BOTTOMLEFT" or currentPoint == "BOTTOM" or currentPoint == "BOTTOMRIGHT"
    end

    -- Guard against child SetPoint hooks scheduling redundant layout updates
    -- while we are actively styling and positioning bars.
    self._layoutRunning = true

    -- Style all visible children (lazy setters make redundant calls no-ops)
    self._editLocked = false
    local ok, err = pcall(function()
        for _, entry in ipairs(visibleChildren) do
            hookChildFrame(entry.frame, self)
            styleChildFrame(self, entry.frame, cfg, globalConfig)
        end

        layoutBars(viewer, growsUp, verticalSpacing)
    end)

    self._layoutRunning = nil
    if not self._editLocked then
        self._warned = false
    end
    ns.DebugAssert(ok, "Error styling buff bars: " .. tostring(err))

    viewer:Show()
    ns.Log(ns.Constants.BUFFBARS, "UpdateLayout (" .. (why or "") .. ")", {
        mode = position and position.mode or "free",
        childCount = #visibleChildren,
        anchor = position and position.anchor and position.anchor:GetName() or "(blizzard)",
        anchorPoint = position and position.point,
        anchorRelativePoint = position and position.relativePoint,
        offsetX = position and position.x,
        offsetY = position and position.y,
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
            local key = ns.SpellColors.MakeKey(name, sid, cid, tex)
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
        ns.Runtime.RequestLayout("BuffBars:viewer:OnShow")
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if self._layoutRunning then
            return
        end
        ns.Runtime.RequestLayout("BuffBars:viewer:OnSizeChanged", { secondPass = true })
    end)

    ns.Log(self.Name, "Hooked BuffBarCooldownViewer")
end

function BuffBars:OnZoneChanged()
    ns.Runtime.RequestLayout("BuffBars:OnZoneChanged")
end

--- Gets a boolean indicating if editing is allowed.
--- @return boolean isEditLocked Whether editing is locked due to combat or secrets
--- @return string reason Reason editing is locked ("combat", "secrets", or nil)
function BuffBars:IsEditLocked()
    local reason = InCombatLockdown() and "combat" or (self._editLocked and "secrets") or nil
    return reason ~= nil, reason
end

function BuffBars:OnInitialize()
    BarMixin.AddFrameMixin(self, "BuffBars")
end

function BuffBars:OnEnable()
    self._warned = false

    ns.SpellColors.SetConfigAccessor(function()
        return self:GetModuleConfig()
    end)

    self:EnsureFrame()
    ns.Runtime.RegisterFrame(self)

    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function(_, ...) self:OnZoneChanged(...) end)
    self:RegisterEvent("ZONE_CHANGED", function(_, ...) self:OnZoneChanged(...) end)
    self:RegisterEvent("ZONE_CHANGED_INDOORS", function(_, ...) self:OnZoneChanged(...) end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, ...) self:OnZoneChanged(...) end)

    C_Timer.After(0.1, function()
        self:HookViewer()
        ns.Runtime.RequestLayout("BuffBars:ModuleInit")
    end)
end

function BuffBars:OnDisable()
    ns.SpellColors.SetConfigAccessor(nil)
    self:UnregisterAllEvents()
    ns.Runtime.UnregisterFrame(self)
end
