-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local FrameUtil = ECM.FrameUtil
local BuffBars = {}
ECM.BuffBars = BuffBars
ECM.ModuleMixin.ApplyConfigMixin(BuffBars, "BuffBars")
local _warned = false
local _editLocked = false

---@class ECM_BuffBarMixin : Frame
---@field __ecmHooked boolean
---@field Bar StatusBar
---@field DebuffBorder any
---@field Icon Frame
---@field cooldownID number|nil
---@field cooldownInfo { spellID: number|nil }|nil

local function get_children_ordered(viewer)
    local result = {}
    for insertOrder, child in ipairs({ viewer:GetChildren() }) do
        if child and child.Bar then
            local top = child.GetTop and child:GetTop()
            result[#result + 1] = { frame = child, top = top, order = insertOrder }
        end
    end

    -- Sort top-to-bottom (highest Y first). Use insertion order as tiebreaker
    -- when Y positions are equal or nil (bars not yet positioned by Blizzard).
    table.sort(result, function(a, b)
        local aTop = a.top or 0
        local bTop = b.top or 0
        if aTop ~= bTop then
            return aTop > bTop
        end
        return a.order < b.order
    end)

    return result
end

local function hook_child_frame(child, module)
    if child.__ecmHooked then
        return
    end

    -- Hook SetPoint to detect when Blizzard re-anchors this child.
    -- When triggered outside our own layout pass, invalidate the lazy
    -- anchor cache so the next layout re-applies the correct anchors.
    hooksecurefunc(child, "SetPoint", function()
        if module._layoutRunning then return end
        FrameUtil.LazyResetState(child)
        module:ThrottledUpdateLayout("SetPoint:hook", { secondPass = true })
    end)

    -- Hook OnShow to ensure newly shown bars get positioned
    child:HookScript("OnShow", function()
        module:ThrottledUpdateLayout("OnShow:child", { secondPass = true })
    end)

    child:HookScript("OnHide", function()
        module:ThrottledUpdateLayout("OnHide:child", { secondPass = true })
    end)

    child.__ecmHooked = true
end

--- Applies all sizing, styling, visibility, and anchoring to a single buff bar
--- child frame. Lazy setters ensure no-ops when values haven't changed.
---@param frame ECM_BuffBarMixin
---@param config table Module config
---@param globalConfig table Global config
---@param barIndex number Index of the bar (for logging)
---@param retryCount number|nil Number of times this function has been retried
local function style_child_frame(frame, config, globalConfig, barIndex, retryCount)
    if not (frame and frame.__ecmHooked) then
        ECM_debug_assert(false, "Attempted to style a child frame that wasn't hooked.")
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

        local bgColor = (config and config.bgColor) or (globalConfig and globalConfig.barBgColor) or ECM.Constants.COLOR_BLACK
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
    local texture = ECM_GetTexture(textureName)
    FrameUtil.LazySetStatusBarTexture(bar, bar, texture)

    local barColor = ECM.SpellColors.GetColorForBar(frame)
    local spellName = frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText() or "nil"
    local spellID = frame.cooldownInfo and frame.cooldownInfo.spellID or "nil"
    local cooldownID = frame.cooldownID or "nil"
    local textureFileID = FrameUtil.GetIconTextureFileID(frame) or "nil"

    -- When in a raid instance, and after exiting combat, all identifying
    -- values may remain secret.  Lock editing only when every key is
    -- unusable.  With four tiers (name, spellID, cooldownID, texture)
    -- the colour lookup is much more resilient to partial secrecy.
    local allSecret = issecretvalue(spellName) and issecretvalue(spellID)
        and issecretvalue(cooldownID) and issecretvalue(textureFileID)
    _editLocked = _editLocked or allSecret

    -- Purely diagnostics to help track down issues with secrets
    local hex = barColor and string.upper(ColorUtil.color_to_hex(barColor)) or nil
    local colorLog = (barColor and "|cff"..hex .."#" .. hex .."|r" or "nil")
    local logPrefix = "GetColorForBar[".. barIndex .."] "
    local logLine = logPrefix .. "(" .. ECM_tostring(spellName) .. ", " .. ECM_tostring(spellID) .. ", " .. ECM_tostring(cooldownID) .. ", " .. ECM_tostring(textureFileID) .. ") = " .. colorLog
    ECM_log(ECM.Constants.SYS.Styling, ECM.Constants.BUFFBARS, logLine, { frame = frame, cooldownID = cooldownID, spellID = spellID })

    if allSecret and not InCombatLockdown() then
        if retryCount < 3 then
            C_Timer.After(1, function()
                style_child_frame(frame, config, globalConfig, barIndex, retryCount + 1)
            end)
            -- Don't apply any colour while retries are pending — preserve
            -- the bar's existing colour rather than clobbering it with the
            -- default while we wait for secrets to clear.
            barColor = nil
        elseif not _warned then
            ECM_log(ECM.Constants.SYS.Styling, ECM.Constants.BUFFBARS, "All identifying keys are secret outside of combat.")
            _warned = true
        end
    elseif retryCount > 0 then
        ECM_log(ECM.Constants.SYS.Styling, ECM.Constants.BUFFBARS, "Successfully retrieved values on retry. " .. logLine)
    end

    if barColor == nil and not allSecret then
        barColor = ECM.SpellColors.GetDefaultColor()
    end
    if barColor then
        FrameUtil.LazySetStatusBarColor(bar, bar, barColor.r, barColor.g, barColor.b, 1.0)
    end

    --------------------------------------------------------------------------
    -- Fonts (before visibility/positioning — font changes affect layout)
    --------------------------------------------------------------------------
    ECM_ApplyFont(bar.Name)
    ECM_ApplyFont(bar.Duration)

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
        iconFrame:SetShown(showIcon)
        iconTexture:SetShown(showIcon)
        iconOverlay:SetShown(showIcon)
    end

    local iconAlpha = showIcon and 1 or 0
    if frame.DebuffBorder then
        FrameUtil.LazySetAlpha(frame.DebuffBorder, iconAlpha)
    end
    if iconFrame.Applications then
        FrameUtil.LazySetAlpha(iconFrame.Applications, iconAlpha)
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

    ECM_log(ECM.Constants.SYS.Styling, ECM.Constants.BUFFBARS, logPrefix .. "Applied style to bar", {
        barIndex = barIndex,
        height = height,
        pipHidden = true,
        pipTexture = nil,
        barBgColor = (barBG and ((config and config.bgColor) or (globalConfig and globalConfig.barBgColor) or ECM.Constants.COLOR_BLACK)) or nil,
        barBgTexture = barBG and ECM.Constants.FALLBACK_TEXTURE or nil,
        barBgLayer = barBG and "BACKGROUND" or nil,
        barBgSubLayer = barBG and 0 or nil,
        textureName = textureName,
        statusBarTexture = texture,
        statusBarColor = barColor,
        showIcon = showIcon,
        showSpellName = showSpellName,
        showDuration = showDuration,
        iconAlpha = iconAlpha,
        iconVisible = iconVisible,
        iconShown = iconFrame and iconFrame:IsShown() or false,
        iconSize = iconVisible and (iconFrame:GetHeight() or frame:GetHeight() or 0) or 0,
        debuffBorderAlpha = frame.DebuffBorder and iconAlpha or nil,
        applicationsAlpha = iconFrame.Applications and iconAlpha or nil,
        nameShown = showSpellName,
        durationShown = showDuration,
        nameLeftInset = ECM.Constants.BUFFBARS_TEXT_PADDING,
        nameRightPadding = ECM.Constants.BUFFBARS_TEXT_PADDING,
        barAnchorMode = iconVisible and "icon" or "frame",
    })
end

--- Positions all bar children in a vertical stack, preserving edit mode order.
local function layout_bars(self)
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return
    end

    local children = get_children_ordered(viewer)
    local prev

    for _, entry in ipairs(children) do
        local child = entry.frame
        if child:IsShown() then
            if not prev then
                FrameUtil.LazySetAnchors(child, {
                    { "TOPLEFT", viewer, "TOPLEFT", 0, 0 },
                    { "TOPRIGHT", viewer, "TOPRIGHT", 0, 0 },
                })
            else
                FrameUtil.LazySetAnchors(child, {
                    { "TOPLEFT", prev, "BOTTOMLEFT", 0, 0 },
                    { "TOPRIGHT", prev, "BOTTOMRIGHT", 0, 0 },
                })
            end
            prev = child
        end
    end
end

--- Override to support custom anchor points in free mode.
---@return table params Layout parameters
function BuffBars:CalculateLayoutParams()
    local globalConfig = self:GetGlobalConfig()
    local cfg = self:GetModuleConfig()
    local mode = cfg and cfg.anchorMode or ECM.Constants.ANCHORMODE_CHAIN

    local params = { mode = mode }

    if mode == ECM.Constants.ANCHORMODE_CHAIN then
        local anchor, isFirst = self:GetNextChainAnchor(ECM.Constants.BUFFBARS)
        params.anchor = anchor
        params.isFirst = isFirst
        params.anchorPoint = "TOPLEFT"
        params.anchorRelativePoint = "BOTTOMLEFT"
        params.offsetX = 0
        params.offsetY = (isFirst and -(globalConfig and globalConfig.offsetY or 0)) or 0
    else
        -- Free mode: BuffBars supports custom anchor points from config
        params.anchor = UIParent
        params.isFirst = false
        params.anchorPoint = cfg.anchorPoint or "CENTER"
        params.anchorRelativePoint = cfg.relativePoint or "CENTER"
        params.offsetX = cfg.offsetX or 0
        params.offsetY = cfg.offsetY or 0
        params.width = cfg.width
    end

    return params
end

function BuffBars:CreateFrame()
    return _G["BuffBarCooldownViewer"]
end

function BuffBars:IsReady()
    if not ECM.ModuleMixin.IsReady(self) then
        return false
    end

    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return false
    end

    -- Check if the viewer is in a state where we can enumerate children
    local canGetChildren = pcall(function() viewer:GetChildren() end)
    if not canGetChildren then
        return false
    end

    return true
end

--- Override UpdateLayout to position the BuffBarViewer and apply styling to children.
function BuffBars:UpdateLayout(why)
    local viewer = self.InnerFrame
    local globalConfig = self:GetGlobalConfig()
    local cfg = self:GetModuleConfig()

    if not self:ShouldShow() then
        viewer:Hide()
        return false
    end

    -- Only apply anchoring in chain mode; free mode is handled by Blizzard's edit mode
    local params = self:CalculateLayoutParams()
    if params.mode == ECM.Constants.ANCHORMODE_CHAIN then
        FrameUtil.LazySetAnchors(viewer, {
            { "TOPLEFT", params.anchor, "BOTTOMLEFT", params.offsetX, params.offsetY },
            { "TOPRIGHT", params.anchor, "BOTTOMRIGHT", params.offsetX, params.offsetY },
        })
    elseif params.mode == ECM.Constants.ANCHORMODE_FREE then
        -- Chain mode sets 2-point anchors (TOPLEFT+TOPRIGHT) which
        -- override explicit width.  If stale chain anchors remain,
        -- collapse to the first anchor point so SetWidth can work.
        -- Blizzard's edit mode manages positioning from here on.
        if viewer:GetNumPoints() > 1 then
            local point, relativeTo, relativePoint, ofsX, ofsY = viewer:GetPoint(1)
            viewer:ClearAllPoints()
            if point and relativeTo then
                viewer:SetPoint(point, relativeTo, relativePoint, ofsX, ofsY)
            end
            -- Invalidate anchor cache so chain mode can re-anchor later
            local s = viewer.__ecm_state
            if s then s.anchors = nil end
        end

        local width = (cfg and cfg.width) or (globalConfig and globalConfig.barWidth) or 300

        if width and width > 0 then
            FrameUtil.LazySetWidth(viewer, width)
        end
    end

    -- Guard against child SetPoint hooks scheduling redundant layout updates
    -- while we are actively styling and positioning bars.
    self._layoutRunning = true

    -- Style all visible children (lazy setters make redundant calls no-ops)
    _warned = false
    _editLocked = false
    local visibleChildren = get_children_ordered(viewer)
    for barIndex, entry in ipairs(visibleChildren) do
        -- Some children of the viewer do not have a Bar so might be some other part of the UI.
        if entry.frame.Bar then
            hook_child_frame(entry.frame, self)
            style_child_frame(entry.frame, cfg, globalConfig, barIndex)
        end
    end

    layout_bars(self)

    self._layoutRunning = nil
    viewer:Show()
    ECM_log(ECM.Constants.SYS.Layout, ECM.Constants.BUFFBARS, "UpdateLayout (" .. (why or "") .. ")", {
        mode = params.mode,
        childCount = #visibleChildren,
        viewerWidth = params.width or -1,
        anchor = params.anchor and params.anchor:GetName() or "nil",
        anchorPoint = params.anchorPoint,
        anchorRelativePoint = params.anchorRelativePoint,
        offsetX = params.offsetX,
        offsetY = params.offsetY,
    })
    return true
end

--- Resets all styled markers so bars get fully re-styled on next update.
function BuffBars:ResetStyledMarkers()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return
    end

    -- Clear lazy state on the viewer itself so chain anchoring is re-applied
    FrameUtil.LazyResetState(viewer)

    -- Clear lazy state on all children to force full re-style
    local children = { viewer:GetChildren() }
    for _, child in ipairs(children) do
        FrameUtil.LazyResetState(child)
        if child.Bar then
            FrameUtil.LazyResetState(child.Bar)
        end
    end
end

--- Returns metadata for all currently-visible aura bars.
--- Each entry contains a spellName (string), spellID (number),
--- cooldownID (number), and/or textureFileID (number), with secret
--- values filtered out. Entries where all keys are nil are skipped.
---@return { spellName: string|nil, spellID: number|nil, cooldownID: number|nil, textureFileID: number|nil }[]
function BuffBars:GetActiveSpellData()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return {}
    end

    local ordered = get_children_ordered(viewer)
    local result = {}
    for _, entry in ipairs(ordered) do
        local frame = entry.frame
        local name = frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText() or nil
        local sid = frame.cooldownInfo and frame.cooldownInfo.spellID or nil
        local cid = frame.cooldownID or nil
        local tex = FrameUtil.GetIconTextureFileID(frame) or nil

        -- Filter out secret values that cannot be used as table keys
        if name and issecretvalue(name) then name = nil end
        if sid and issecretvalue(sid) then sid = nil end
        if cid and issecretvalue(cid) then cid = nil end
        if tex and issecretvalue(tex) then tex = nil end

        if name or sid or cid or tex then
            result[#result + 1] = { spellName = name, spellID = sid, cooldownID = cid, textureFileID = tex }
        end
    end
    return result
end

--- Hooks the BuffBarCooldownViewer for automatic updates.
function BuffBars:HookViewer()
    local viewer = _G["BuffBarCooldownViewer"]
    if not viewer then
        return
    end

    if self._viewerHooked then
        return
    end
    self._viewerHooked = true

    -- Hook OnShow for initial layout
    viewer:HookScript("OnShow", function(f)
        self:ThrottledUpdateLayout("viewer:OnShow")
    end)

    -- Hook OnSizeChanged for responsive layout
    viewer:HookScript("OnSizeChanged", function()
        if self._layoutRunning then
            return
        end
        self:ThrottledUpdateLayout("viewer:OnSizeChanged", { secondPass = true })
    end)

    -- Hook edit mode transitions
    self:HookEditMode()

    ECM_log(ECM.Constants.SYS.Core, self.Name, "Hooked BuffBarCooldownViewer")
end

--- Hooks EditModeManagerFrame to re-apply layout on exit.
function BuffBars:HookEditMode()
    if self._editModeHooked then
        return
    end

    if not EditModeManagerFrame then
        return
    end

    self._editModeHooked = true

    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        self:ResetStyledMarkers()

        -- Edit mode exit is infrequent, so perform an immediate restyle pass.
        local viewer = _G["BuffBarCooldownViewer"]
        if viewer and viewer:IsShown() then
            self:ThrottledUpdateLayout("EditModeExit")
        end
    end)

    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        -- Re-apply style during edit mode so bars look correct while editing
        self:ThrottledUpdateLayout("EditModeEnter")
    end)

    ECM_log(ECM.Constants.SYS.Core, self.Name, "Hooked EditModeManagerFrame")
end

function BuffBars:OnUnitAura(_, unit)
    if unit == "player" then
        self:ThrottledUpdateLayout("OnUnitAura")
    end
end

function BuffBars:OnZoneChanged()
    --- Invalidates lazy state so the next layout pass re-applies chain anchoring.
    self:ResetStyledMarkers()
    self:ThrottledUpdateLayout("OnZoneChanged")
end

function BuffBars:IsEnabled()
    return self._enabled or false
end

--- Gets a boolean indicating if editing is allowed.
--- @return boolean isEditLocked Whether editing is locked due to combat or secrets
--- @return string reason Reason editing is locked ("combat", "secrets", or nil)
function BuffBars:IsEditLocked()
    local reason = InCombatLockdown() and "combat" or (_editLocked and "secrets") or nil
    return reason ~= nil, reason
end

local _eventFrame = CreateFrame("Frame")
function BuffBars:Enable()
    if self._enabled then return end
    self._enabled = true

    ECM.ModuleMixin.AddMixin(self, "BuffBars")

    _eventFrame:RegisterEvent("UNIT_AURA")
    _eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    _eventFrame:RegisterEvent("ZONE_CHANGED")
    _eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
    _eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Hook the viewer and edit mode after a short delay to ensure Blizzard frames are loaded
    C_Timer.After(0.1, function()
        self:HookViewer()
        self:HookEditMode()
        self:ThrottledUpdateLayout("ModuleInit")
    end)

    ECM_log(ECM.Constants.SYS.Core, self.Name, "Enable - module enabled")
end

_eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "UNIT_AURA" then
        BuffBars:OnUnitAura(event, ...)
    else
        BuffBars:OnZoneChanged()
    end
end)
