-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local BarMixin = ns.BarMixin
local FrameUtil = ns.FrameUtil
local ChainRightPoint = BarMixin.FrameProto.ChainRightPoint
local StyleChildBar = ns.BarStyle.StyleChildBar
local BuffBars = ns.Addon:NewModule("BuffBars")
ns.Addon.BuffBars = BuffBars

local SPELL_COLOR_SCOPE = ns.Constants.SCOPE_BUFFBARS

local function getSpellColors()
    return ns.SpellColors.Get(SPELL_COLOR_SCOPE)
end

local function collectViewerChildren(viewer, why)
    local ok, children = pcall(function()
        return { viewer:GetChildren() }
    end)
    if not ok then
        ns.ErrorLogOnce("BuffBars", "GetChildren", "Unable to read buff bar children", {
            reason = why,
            error = children,
        })
        return nil
    end

    return children
end

---@class ECM_BuffBarMixin : Frame
---@field __ecmHooked boolean
---@field Bar StatusBar
---@field DebuffBorder any
---@field Icon Frame
---@field ignoreInLayout boolean|nil
---@field layoutIndex number|nil
---@field cooldownID number|nil
---@field cooldownInfo { spellID: number|nil }|nil

local function getChildrenOrdered(viewer, why)
    local children = collectViewerChildren(viewer, why)
    if not children then
        return nil
    end

    local result = {}
    for insertOrder, child in ipairs(children) do
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

local function hookChildFrame(child, module)
    if child.__ecmHooked then
        return
    end

    local spellColors = getSpellColors()

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
        StyleChildBar(module, child, module:GetModuleConfig(), module:GetGlobalConfig(), spellColors)
        module._layoutRunning = nil
        ns.Runtime.RequestLayout("BuffBars:SetPoint:hook", { secondPass = true })
    end)

    child:HookScript("OnShow", function()
        if module._layoutRunning then
            return
        end
        module._layoutRunning = true
        StyleChildBar(module, child, module:GetModuleConfig(), module:GetGlobalConfig(), spellColors)
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
local function layoutBars(children, viewer, growsUp, verticalSpacing)
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
    local spellColors = getSpellColors()

    if why == "PLAYER_SPECIALIZATION_CHANGED" or why == "ProfileChanged" then
        spellColors:ClearDiscoveredKeys()
    end

    -- Discover bars regardless of visibility so the spell colours options
    -- panel has the full list even when hidden (e.g. resting).
    local visibleChildren = getChildrenOrdered(viewer, why)
    if not visibleChildren then
        return false
    end

    for _, entry in ipairs(visibleChildren) do
        spellColors:DiscoverBar(entry.frame)
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
            StyleChildBar(self, entry.frame, cfg, globalConfig, spellColors)
        end

        layoutBars(visibleChildren, viewer, growsUp, verticalSpacing)
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

    local ordered = getChildrenOrdered(viewer, "GetActiveSpellData")
    if not ordered then
        return {}
    end

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
        if not self:IsEnabled() then
            return
        end
        ns.Runtime.RequestLayout("BuffBars:viewer:OnShow")
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if not self:IsEnabled() or self._layoutRunning then
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
    self:UnregisterAllEvents()
    ns.Runtime.UnregisterFrame(self)
end
