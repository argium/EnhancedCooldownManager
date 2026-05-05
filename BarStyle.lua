-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local FrameUtil = ns.FrameUtil

--------------------------------------------------------------------------------
-- Shared child-bar styling helpers (BuffBars / ExternalBars)
--
-- Stateless functions that operate on already-constructed bar widgets.
-- Not a mixin — callers invoke these directly as `BarStyle.StyleChildBar(...)`.
--------------------------------------------------------------------------------

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

---@param frame Frame
---@param bar StatusBar
---@param iconFrame Frame|nil
---@param config table|nil
---@param globalConfig table|nil
local function styleBarHeight(frame, bar, iconFrame, config, globalConfig)
    assert(frame ~= nil, "BarStyle.styleBarHeight requires a frame")
    assert(bar ~= nil, "BarStyle.styleBarHeight requires a bar")

    local height = (config and config.height) or (globalConfig and globalConfig.barHeight)
    assert(type(height) == "number", "BarStyle.styleBarHeight requires config.height or globalConfig.barHeight")
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

---@param frame Frame
---@param barBG Texture|nil
---@param config table|nil
---@param globalConfig table|nil
local function styleBarBackground(frame, barBG, config, globalConfig)
    assert(frame ~= nil, "BarStyle.styleBarBackground requires a frame")

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
    assert(bgColor ~= nil, "BarStyle.styleBarBackground requires config.bgColor or globalConfig.barBgColor")
    barBG:SetTexture(ns.Constants.FALLBACK_TEXTURE)
    barBG:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
    barBG:ClearAllPoints()
    barBG:SetAllPoints(frame)
    barBG:SetDrawLayer("BACKGROUND", 0)
end

--- Resolves the spell color for a bar, handling secret values with retry.
--- Returns true if the module's _editLocked flag was set by this call.
---@param module table
---@param frame ECM_BuffBarMixin|Frame
---@param bar StatusBar
---@param globalConfig table|nil
---@param spellColors ECM_SpellColorStore
---@param retryCount number|nil
---@return boolean|nil
local function styleBarColor(module, frame, bar, globalConfig, spellColors, retryCount)
    assert(module ~= nil, "BarStyle.styleBarColor requires a module")
    assert(type(module.Name) == "string" and module.Name ~= "", "BarStyle.styleBarColor requires module.Name")
    assert(frame ~= nil, "BarStyle.styleBarColor requires a frame")
    assert(bar ~= nil, "BarStyle.styleBarColor requires a bar")
    assert(spellColors ~= nil, "BarStyle.styleBarColor requires an explicit spellColors store")

    local currentRetryCount = retryCount or 0
    local textureName = globalConfig and globalConfig.texture
    FrameUtil.LazySetStatusBarTexture(bar, FrameUtil.GetTexture(textureName))

    local barColor = spellColors:GetColorForBar(frame)
    local spellName = bar.Name and bar.Name.GetText and bar.Name:GetText()
    local spellID = frame.cooldownInfo and frame.cooldownInfo.spellID
    local cooldownID = frame.cooldownID
    local textureFileID = FrameUtil.GetIconTextureFileID(frame)

    -- When in a raid instance, and after exiting combat, all identifying
    -- values may remain secret. Lock editing only when every key is unusable.
    -- With four tiers (name, spellID, cooldownID, texture) the colour lookup
    -- is much more resilient to partial secrecy.
    local allSecret = issecretvalue(spellName)
        and issecretvalue(spellID)
        and issecretvalue(cooldownID)
        and issecretvalue(textureFileID)
    module._editLocked = module._editLocked or allSecret

    if allSecret and not InCombatLockdown() then
        if currentRetryCount < 3 then
            if frame._ecmColorRetryTimer then
                frame._ecmColorRetryTimer:Cancel()
            end
            frame._ecmColorRetryTimer = C_Timer.NewTimer(1, function()
                frame._ecmColorRetryTimer = nil
                styleBarColor(module, frame, bar, globalConfig, spellColors, currentRetryCount + 1)
            end)
            -- Don't apply any colour while retries are pending — preserve
            -- the bar's existing colour rather than clobbering it with the
            -- default while we wait for secrets to clear.
            return nil
        elseif ns.IsDebugEnabled() and not module._warned then
            ns.Log(module.Name, "All identifying keys are secret outside of combat.")
            module._warned = true
        end
    end

    if frame._ecmColorRetryTimer then
        frame._ecmColorRetryTimer:Cancel()
        frame._ecmColorRetryTimer = nil
    end

    if barColor == nil and not allSecret then
        barColor = spellColors:GetDefaultColor()
    end
    if barColor then
        FrameUtil.LazySetStatusBarColor(bar, barColor.r, barColor.g, barColor.b, 1.0)
    end

    return module._editLocked
end

---@param frame Frame
---@param iconFrame Frame|nil
---@param config table|nil
local function styleBarIcon(frame, iconFrame, config)
    assert(frame ~= nil, "BarStyle.styleBarIcon requires a frame")

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

---@param frame Frame
---@param bar StatusBar
---@param iconFrame Frame|nil
---@param config table|nil
local function styleBarAnchors(frame, bar, iconFrame, config)
    assert(frame ~= nil, "BarStyle.styleBarAnchors requires a frame")
    assert(bar ~= nil, "BarStyle.styleBarAnchors requires a bar")
    assert(bar.Name ~= nil, "BarStyle.styleBarAnchors requires bar.Name")

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

--- Applies all sizing, styling, visibility, and anchoring to a single child bar.
--- Lazy setters ensure no-ops when values haven't changed.
---@param module table
---@param frame ECM_BuffBarMixin|Frame
---@param config table|nil
---@param globalConfig table|nil
---@param spellColors ECM_SpellColorStore
local function styleChildBar(module, frame, config, globalConfig, spellColors)
    assert(module ~= nil, "BarStyle.styleChildBar requires a module")
    assert(frame ~= nil, "BarStyle.styleChildBar requires a frame")
    assert(frame.__ecmHooked, "Attempted to style a child frame that wasn't hooked.")
    assert(spellColors ~= nil, "BarStyle.styleChildBar requires an explicit spellColors store")

    local bar = assert(frame.Bar, "BarStyle.styleChildBar requires frame.Bar")
    local iconFrame = frame.Icon
    assert(bar.Pip ~= nil, "BarStyle.styleChildBar requires bar.Pip")
    assert(bar.Name ~= nil, "BarStyle.styleChildBar requires bar.Name")
    assert(bar.Duration ~= nil, "BarStyle.styleChildBar requires bar.Duration")

    styleBarHeight(frame, bar, iconFrame, config, globalConfig)

    bar.Pip:Hide()
    bar.Pip:SetTexture(nil)

    styleBarBackground(frame, FrameUtil.GetBarBackground(bar), config, globalConfig)
    styleBarColor(module, frame, bar, globalConfig, spellColors, 0)

    FrameUtil.ApplyFont(bar.Name, globalConfig, config)
    FrameUtil.ApplyFont(bar.Duration, globalConfig, config)

    styleBarIcon(frame, iconFrame, config)
    styleBarAnchors(frame, bar, iconFrame, config)
end

local BarStyle = {
    ApplySquareIconStyle = applySquareIconStyle,
    StyleBarHeight = styleBarHeight,
    StyleBarBackground = styleBarBackground,
    StyleBarColor = styleBarColor,
    StyleBarIcon = styleBarIcon,
    StyleBarAnchors = styleBarAnchors,
    StyleChildBar = styleChildBar,
}

ns.BarStyle = BarStyle
