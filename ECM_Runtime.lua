-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
ECM = ECM or {}
assert(ECM.Constants, "ECM_Constants.lua must be loaded before ECM_Runtime.lua")
assert(ECM.FrameMixin, "FrameMixin.lua must be loaded before ECM_Runtime.lua")
assert(ECM.EditMode, "ECM.EditMode must be initialized before ECM_Runtime.lua")
assert(ns.Addon, "ECM.lua must be loaded before ECM_Runtime.lua")

local C = ECM.Constants
local L = ECM.L
local EditMode = ECM.EditMode
local LibEQOLEditMode = EditMode.Lib
local Runtime = {}
ECM.Runtime = Runtime

--------------------------------------------------------------------------------
-- Layout — global visibility, fade, Blizzard frame enforcement, event dispatch
--------------------------------------------------------------------------------

local LAYOUT_EVENTS = {
    PLAYER_MOUNT_DISPLAY_CHANGED = { delay = 0 },
    UNIT_ENTERED_VEHICLE = { delay = 0 },
    UNIT_EXITED_VEHICLE = { delay = 0 },
    VEHICLE_UPDATE = { delay = 0 },
    PLAYER_UPDATE_RESTING = { delay = 0 },
    PLAYER_SPECIALIZATION_CHANGED = { delay = 0 },
    PLAYER_ENTERING_WORLD = { delay = C.LAYOUT_ENTERING_WORLD_DELAY },
    PLAYER_TARGET_CHANGED = { delay = 0 },
    PLAYER_REGEN_ENABLED = { delay = C.LAYOUT_COMBAT_END_DELAY, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = C.LAYOUT_ZONE_CHANGE_DELAY },
    ZONE_CHANGED = { delay = C.LAYOUT_ZONE_CHANGE_DELAY },
    ZONE_CHANGED_INDOORS = { delay = C.LAYOUT_ZONE_CHANGE_DELAY },
    UPDATE_SHAPESHIFT_FORM = { delay = 0 },
}

local _modules = {}
local _globallyHidden = false
local _desiredAlpha = 1
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _layoutEventsEnabled = false
local _layoutWatchdogTicker = nil
local _cooldownViewerSettingsHooked = false
local _layoutPreviewActive = false
local _hookedBlizzardFrames = {}

local _chainSet = {}
for _, name in ipairs(C.CHAIN_ORDER) do
    _chainSet[name] = true
end

local _detachedAnchor = nil
local _detachedAnchorLayout = nil

--- Enforces the current desired visibility and alpha on all Blizzard frames.
--- Single enforcement point called from state changes, OnShow hooks, and the
--- watchdog ticker.
local function enforceBlizzardFrameState()
    local alpha = _desiredAlpha
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            if _globallyHidden then
                if frame:IsShown() then
                    frame:Hide()
                    ECM.Log(nil, "Enforced hide on " .. (frame:GetName() or "?"))
                end
            else
                if not frame:IsShown() then
                    frame:Show()
                    ECM.Log(nil, "Enforced show on " .. (frame:GetName() or "?"))
                end
                ECM.FrameUtil.LazySetAlpha(frame, alpha)
            end
        end
    end
end

--- Hooks a Blizzard frame's OnShow to immediately re-enforce desired state.
--- Provides sub-frame correction when the game externally re-shows a frame.
--- @param frame Frame
--- @param name string
local function hookBlizzardFrame(frame, name)
    if _hookedBlizzardFrames[name] then
        return
    end

    frame:HookScript("OnShow", function(self)
        if _globallyHidden then
            self:Hide()
        else
            ECM.FrameUtil.LazySetAlpha(self, _desiredAlpha)
        end
    end)

    _hookedBlizzardFrames[name] = true
    ECM.Log(nil, "Hooked Blizzard frame: " .. name)
end

--- Attempts to hook OnShow on all known Blizzard cooldown viewer frames.
--- Frames may be created lazily; called periodically to catch latecomers.
local function hookBlizzardFrames()
    for _, name in ipairs(C.BLIZZARD_FRAMES) do
        local frame = _G[name]
        if frame then
            hookBlizzardFrame(frame, name)
        end
    end
end

--- Sets the globally hidden state for all frames (ModuleMixins + Blizzard frames).
--- @param hidden boolean Whether to hide all frames
--- @param reason string|nil Reason for hiding ("mounted", "rest", "cvar")
local function setGloballyHidden(hidden, reason)
    if _globallyHidden ~= hidden then
        ECM.Log(
            nil,
            "SetGloballyHidden " .. (hidden and "HIDDEN" or "VISIBLE") .. (reason and (" due to " .. reason) or "")
        )
    end

    _globallyHidden = hidden

    for _, module in pairs(_modules) do
        module:SetHidden(hidden)
    end
end

--- Applies alpha to all managed frames.
--- @param alpha number
local function setAlpha(alpha)
    _desiredAlpha = alpha

    for _, module in pairs(_modules) do
        if module.InnerFrame then
            ECM.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
        end
    end
end

--- Checks all fade and hide conditions and updates global state.
local function updateFadeAndHiddenStates()
    local globalConfig = ECM.GetGlobalConfig()
    if not globalConfig then
        return
    end

    -- Force-show while edit mode or the Layout options preview is active so the
    -- user can see and position modules without hide/fade interference.
    if LibEQOLEditMode:IsInEditMode() or _layoutPreviewActive then
        setGloballyHidden(false)
        setAlpha(1)
        enforceBlizzardFrameState()
        return
    end

    -- Determine hidden state
    local hidden, reason = false, nil
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        hidden, reason = true, "cvar"
    elseif globalConfig.hideWhenMounted and (IsMounted() or UnitInVehicle("player") or UnitOnTaxi("player")) then
        hidden, reason = true, "mounted"
    elseif not _inCombat and globalConfig.hideOutOfCombatInRestAreas and IsResting() then
        hidden, reason = true, "rest"
    end

    setGloballyHidden(hidden, reason)

    -- Determine alpha (only matters when visible)
    local alpha = 1
    if not hidden then
        local fadeConfig = globalConfig.outOfCombatFade
        if not _inCombat and fadeConfig and fadeConfig.enabled then
            local shouldSkipFade = false

            if fadeConfig.exceptInInstance and IsInInstance() then
                shouldSkipFade = true
            end

            local hasLiveTarget = UnitExists("target") and not UnitIsDead("target")

            if
                not shouldSkipFade
                and hasLiveTarget
                and fadeConfig.exceptIfTargetCanBeAttacked
                and UnitCanAttack("player", "target")
            then
                shouldSkipFade = true
            end

            if
                not shouldSkipFade
                and hasLiveTarget
                and fadeConfig.exceptIfTargetCanBeHelped
                and UnitCanAssist("player", "target")
            then
                shouldSkipFade = true
            end

            if not shouldSkipFade then
                local opacity = fadeConfig.opacity or 100
                alpha = math.max(0, math.min(1, opacity / 100))
            end
        end
    end

    setAlpha(alpha)

    -- Single enforcement pass for Blizzard frames after all state is settled
    enforceBlizzardFrameState()
end

--- Gets the saved detached anchor position for a layout.
--- If no layout name is provided, this uses the current active Edit Mode layout.
---@param layoutName string|nil
---@return ECM_EditModePosition
local function getDetachedAnchorPosition(layoutName)
    local gc = ECM.GetGlobalConfig()
    return EditMode.GetPosition(gc and gc.detachedAnchorPositions, nil, layoutName)
end

--- Saves the detached anchor position for a specific layout.
---@param layoutName string
---@param point string
---@param x number
---@param y number
local function saveDetachedAnchorPosition(layoutName, point, x, y)
    local gc = ECM.GetGlobalConfig()
    EditMode.SavePosition(gc, "detachedAnchorPositions", layoutName, point, x, y)
end

-- Anchor names like TOPLEFT or BOTTOMRIGHT contain two separate choices:
-- which vertical edge to use (TOP/BOTTOM) and which horizontal edge to use
-- (LEFT/RIGHT). We split them so detached positioning can swap only the
-- vertical side when grow direction changes, while preserving the user's
-- horizontal alignment.
--- Splits an anchor name like TOPLEFT into its vertical and horizontal parts.
---@param point string|nil
---@return string|nil, string|nil
local function splitAnchorName(point)
    if point == nil or point == "CENTER" then
        return nil, nil
    end

    local vertical = point:find("TOP", 1, true) and "TOP" or (point:find("BOTTOM", 1, true) and "BOTTOM" or nil)
    local horizontal = point:find("LEFT", 1, true) and "LEFT" or (point:find("RIGHT", 1, true) and "RIGHT" or nil)
    return vertical, horizontal
end

--- Builds an anchor name from separate vertical and horizontal parts.
--- Example: TOP + LEFT becomes TOPLEFT.
---@param vertical string|nil
---@param horizontal string|nil
---@return string
local function buildAnchorName(vertical, horizontal)
    if vertical == nil and horizontal == nil then
        return "CENTER"
    end
    if vertical == nil then
        return horizontal
    end
    if horizontal == nil then
        return vertical
    end
    return vertical .. horizontal
end

-- Returns the offset from the frame's centre to one of its named anchor
-- points. For example, on a 100px tall frame, TOP is 50 units above the
-- centre and BOTTOM is 50 units below it.
--- Gets the offset from the frame's centre to one of its anchor points.
--- This is used when converting one anchor-based position into another.
---@param point string|nil
---@param width number|nil
---@param height number|nil
---@return number, number
local function getOffsetFromFrameCenter(point, width, height)
    local vertical, horizontal = splitAnchorName(point)
    local halfWidth = (width or 0) * 0.5
    local halfHeight = (height or 0) * 0.5

    local x = 0
    if horizontal == "LEFT" then
        x = -halfWidth
    elseif horizontal == "RIGHT" then
        x = halfWidth
    end

    local y = 0
    if vertical == "BOTTOM" then
        y = -halfHeight
    elseif vertical == "TOP" then
        y = halfHeight
    end

    return x, y
end

-- Returns the absolute position of one of the parent frame's anchor points.
-- Example: UIParent/TOP is the middle of the screen's top edge.
--- Gets the absolute position of one of the parent frame's anchor points.
--- Example: TOP on UIParent is the middle of the top edge of the screen.
---@param point string|nil
---@param parentWidth number|nil
---@param parentHeight number|nil
---@return number, number
local function getParentAnchorPosition(point, parentWidth, parentHeight)
    local vertical, horizontal = splitAnchorName(point)
    local x = (parentWidth or 0) * 0.5
    local y = (parentHeight or 0) * 0.5

    if horizontal == "LEFT" then
        x = 0
    elseif horizontal == "RIGHT" then
        x = parentWidth or 0
    end

    if vertical == "BOTTOM" then
        y = 0
    elseif vertical == "TOP" then
        y = parentHeight or 0
    end

    return x, y
end

--- Gets a frame's width and height, preferring GetSize when available.
---@param parent Frame|nil
---@return number, number
local function getParentSize(parent)
    if parent and parent.GetSize then
        local width, height = parent:GetSize()
        if width and height then
            return width, height
        end
    end

    local width = (parent and parent.GetWidth and parent:GetWidth()) or 0
    local height = (parent and parent.GetHeight and parent:GetHeight()) or 0
    return width, height
end

-- Converts offsets from one anchor reference to another without changing the
-- frame's actual on-screen position.
--
-- Example: a saved position expressed relative to CENTER needs different x/y
-- offsets when rewritten relative to TOP, even if the frame should stay in the
-- same place visually.
--
-- To do that, we:
-- 1) reconstruct the frame's real position on its parent using the source
--    anchor and offsets;
-- 2) calculate the offsets needed to express that same position using the
--    target anchor instead.
--
-- This avoids the bug where switching from CENTER to TOP/BOTTOM only adjusted
-- for frame height and accidentally changed the visible position.
--- Converts offsets from one anchor reference to another while keeping the
--- frame in the same visual position on its parent.
---@param point string
---@param targetPoint string
---@param x number
---@param y number
---@param width number|nil
---@param height number|nil
---@param parent Frame|nil
---@return number, number
local function convertOffsetToAnchor(point, targetPoint, x, y, width, height, parent)
    if point == targetPoint then
        return x, y
    end

    local parentWidth, parentHeight = getParentSize(parent or UIParent)
    local sourceAnchorX, sourceAnchorY = getParentAnchorPosition(point, parentWidth, parentHeight)
    local sourcePointX, sourcePointY = getOffsetFromFrameCenter(point, width, height)
    local centerX = sourceAnchorX + (x or 0) - sourcePointX
    local centerY = sourceAnchorY + (y or 0) - sourcePointY
    local targetAnchorX, targetAnchorY = getParentAnchorPosition(targetPoint, parentWidth, parentHeight)
    local targetPointX, targetPointY = getOffsetFromFrameCenter(targetPoint, width, height)

    return centerX + targetPointX - targetAnchorX, centerY + targetPointY - targetAnchorY
end

--- Returns whether detached stacks are configured to grow upward.
---@return boolean
local function detachedAnchorGrowsUp()
    local gc = ECM.GetGlobalConfig()
    return (gc and gc.detachedGrowDirection) == C.GROW_DIRECTION_UP
end

-- Detached stacks are more stable if their saved position is based on the edge
-- they grow from, rather than the centre of the full stack.
--
-- That means:
-- - grow down stacks are saved from their top edge;
-- - grow up stacks are saved from their bottom edge.
--
-- With that rule, the "anchored" edge stays fixed even if the total stack
-- height changes after reloads or after modules appear/disappear.
--- Rewrites a detached position so it is saved from the stack's stable grow
--- edge rather than from the middle of the detached stack.
---@param point string|nil
---@param x number|nil
---@param y number|nil
---@param width number|nil
---@param height number|nil
---@return string, number, number
local function normalizeDetachedPositionToGrowEdge(point, x, y, width, height)
    local sourcePoint = point or C.EDIT_MODE_DEFAULT_POINT
    local _, horizontal = splitAnchorName(sourcePoint)
    local targetVertical = detachedAnchorGrowsUp() and "BOTTOM" or "TOP"
    local targetPoint = buildAnchorName(targetVertical, horizontal)
    local offsetX, offsetY = convertOffsetToAnchor(sourcePoint, targetPoint, x or 0, y or 0, width, height, UIParent)
    return targetPoint, offsetX, offsetY
end

--- Creates and registers the detached anchor frame with LibEQOL.
local function ensureDetachedAnchor()
    if _detachedAnchor then
        return _detachedAnchor
    end

    local frame = CreateFrame("Frame", "ECMDetachedAnchor", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetSize(C.DEFAULT_BAR_WIDTH, 1)
    ECM.FrameUtil.LazySetAnchors(frame, {
        { C.EDIT_MODE_DEFAULT_POINT, UIParent, C.EDIT_MODE_DEFAULT_POINT, 0, 0 },
    })
    frame:Hide()
    _detachedAnchor = frame
    Runtime.DetachedAnchor = frame

    EditMode.RegisterFrame(frame, {
        name = "ECM: Detached Anchor",
        onPositionChanged = function(layoutName, point, x, y)
            -- Edit Mode reports the drop position using the detached box's
            -- current anchor. We immediately rewrite that position to the
            -- detached stack's stable grow edge so later height changes do not
            -- make the stack appear to move.
            local normalizedPoint, normalizedX, normalizedY = normalizeDetachedPositionToGrowEdge(
                point,
                x,
                y,
                frame:GetWidth(),
                frame:GetHeight()
            )
            saveDetachedAnchorPosition(layoutName, normalizedPoint, normalizedX, normalizedY)
            Runtime.UpdateLayoutImmediately("DetachedAnchorDrag")
        end,
        allowDrag = true,
        settings = {
            {
                kind = LibEQOLEditMode.SettingType.Slider,
                name = L["WIDTH"],
                get = function()
                    local gc = ECM.GetGlobalConfig()
                    return (gc and gc.detachedBarWidth) or C.DEFAULT_BAR_WIDTH
                end,
                set = function(_, value)
                    local gc = ECM.GetGlobalConfig()
                    if gc then
                        gc.detachedBarWidth = value
                        Runtime.UpdateLayoutImmediately("DetachedAnchorWidth")
                    end
                end,
                default = C.DEFAULT_BAR_WIDTH,
                minValue = 100,
                maxValue = 600,
                valueStep = 1,
                allowInput = true,
            },
            {
                kind = LibEQOLEditMode.SettingType.Slider,
                name = L["SPACING"],
                get = function()
                    local gc = ECM.GetGlobalConfig()
                    return (gc and gc.detachedModuleSpacing) or 0
                end,
                set = function(_, value)
                    local gc = ECM.GetGlobalConfig()
                    if gc then
                        gc.detachedModuleSpacing = value
                        Runtime.UpdateLayoutImmediately("DetachedAnchorSpacing")
                    end
                end,
                default = 0,
                minValue = 0,
                maxValue = 20,
                valueStep = 1,
                allowInput = true,
            },
            {
                kind = LibEQOLEditMode.SettingType.Dropdown,
                name = L["GROW_DIRECTION"],
                get = function()
                    local gc = ECM.GetGlobalConfig()
                    return (gc and gc.detachedGrowDirection) or C.GROW_DIRECTION_DOWN
                end,
                set = function(_, value)
                    local gc = ECM.GetGlobalConfig()
                    if gc then
                        gc.detachedGrowDirection = value
                        Runtime.UpdateLayoutImmediately("DetachedAnchorGrowDirection")
                    end
                end,
                values = {
                    { label = L["DOWN"], value = C.GROW_DIRECTION_DOWN },
                    { label = L["UP"], value = C.GROW_DIRECTION_UP },
                },
            },
        },
    })

    ECM.Log(nil, "Detached anchor created and registered with edit mode")
    return frame
end

---@return number
---@return number
local function getDetachedAnchorMetrics()
    local totalHeight = 0
    local count = 0

    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local barModule = ns.Addon and ns.Addon:GetECMModule(moduleName, true)
        if barModule and barModule:IsEnabled() and barModule:ShouldShow() then
            local mc = barModule:GetModuleConfig()
            if mc and mc.anchorMode == C.ANCHORMODE_DETACHED and barModule.InnerFrame then
                local h = barModule.InnerFrame:GetHeight()
                if h and h > 0 then
                    totalHeight = totalHeight + h
                    count = count + 1
                end
            end
        end
    end

    return totalHeight, count
end

---@return boolean
local function hasVisibleDetachedModules()
    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local barModule = ns.Addon and ns.Addon:GetECMModule(moduleName, true)
        if barModule and barModule:IsEnabled() and barModule:ShouldShow() then
            local mc = barModule:GetModuleConfig()
            if mc and mc.anchorMode == C.ANCHORMODE_DETACHED and barModule.InnerFrame then
                return true
            end
        end
    end

    return false
end

---@param anchor Frame
---@param layoutName string|nil
---@return boolean
local function applyDetachedAnchorPosition(anchor, layoutName)
    if not layoutName then
        return false
    end

    local pos = getDetachedAnchorPosition(layoutName)
    local point, x, y = normalizeDetachedPositionToGrowEdge(
        pos.point,
        pos.x,
        pos.y,
        anchor:GetWidth(),
        anchor:GetHeight()
    )
    ECM.FrameUtil.LazySetAnchors(anchor, {
        { point, UIParent, point, x, y },
    })
    _detachedAnchorLayout = layoutName
    return true
end

--- Ensures the detached anchor exists and is already positioned for the active
--- layout before detached modules calculate their own anchors.
---@return Frame|nil
local function prepareDetachedAnchorForLayout()
    if not hasVisibleDetachedModules() then
        return nil
    end

    local anchor = ensureDetachedAnchor()
    local gc = ECM.GetGlobalConfig()
    local barWidth = (gc and gc.detachedBarWidth) or C.DEFAULT_BAR_WIDTH
    ECM.FrameUtil.LazySetWidth(anchor, barWidth)

    local layoutName = EditMode.GetActiveLayoutName()
    -- Detached modules ask for their root anchor during this same layout pass.
    -- If the detached anchor is still using the wrong layout position here,
    -- every detached child will calculate its own position from stale data.
    if layoutName and (not anchor:IsShown() or layoutName ~= _detachedAnchorLayout) then
        applyDetachedAnchorPosition(anchor, layoutName)
    end

    if not anchor:IsShown() then
        anchor:Show()
    end

    return anchor
end

--- Updates the detached anchor's size and visibility to match the current set
--- of shown detached modules.
local function updateDetachedAnchorSize()
    local totalHeight, count = getDetachedAnchorMetrics()
    if count == 0 then
        if _detachedAnchor and _detachedAnchor:IsShown() then
            _detachedAnchor:Hide()
        end
        _detachedAnchorLayout = nil
        return
    end

    local anchor = ensureDetachedAnchor()
    local gc = ECM.GetGlobalConfig()
    local barWidth = (gc and gc.detachedBarWidth) or C.DEFAULT_BAR_WIDTH
    local spacing = (gc and gc.detachedModuleSpacing) or 0

    if count > 1 then
        totalHeight = totalHeight + (spacing * (count - 1))
    end

    ECM.FrameUtil.LazySetWidth(anchor, barWidth)
    ECM.FrameUtil.LazySetHeight(anchor, math.max(totalHeight, 1))

    -- Apply the position again after width/height are final.
    --
    -- This matters for two cases:
    -- - older saved data may still have been recorded from the centre;
    -- - the current detached stack may have changed height because modules were
    --   shown, hidden, enabled, or disabled.
    --
    -- Re-running the conversion with the final size keeps the visible anchored
    -- edge consistent for the current layout.
    local layoutName = EditMode.GetActiveLayoutName()
    if layoutName then
        applyDetachedAnchorPosition(anchor, layoutName)
    end

    if not anchor:IsShown() then
        anchor:Show()
    end
end

local function updateAllLayouts(reason)
    prepareDetachedAnchorForLayout()

    -- Chain frames update in deterministic order so downstream bars can
    -- resolve anchors against already-laid-out predecessors.
    for _, moduleName in ipairs(C.CHAIN_ORDER) do
        local module = _modules[moduleName]
        if module then
            module:ThrottledUpdateLayout(reason)
        end
    end

    for frameName, module in pairs(_modules) do
        if not _chainSet[frameName] then
            module:ThrottledUpdateLayout(reason)
        end
    end

    updateDetachedAnchorSize()
end

--- Hooks CooldownViewerSettings hide to force alpha/layout reapplication.
local function hookCooldownViewerSettings()
    if _cooldownViewerSettingsHooked then
        return
    end

    local settingsFrame = _G.CooldownViewerSettings
    if not settingsFrame then
        return
    end

    settingsFrame:HookScript("OnHide", function()
        updateFadeAndHiddenStates()
        updateAllLayouts("OnHide:CooldownViewerSettings")
    end)

    _cooldownViewerSettingsHooked = true
    ECM.Log(nil, "Hooked CooldownViewerSettings OnHide")
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Sets or clears the layout preview override.
--- When active, hide-when-mounted, hide-in-rest, and out-of-combat fade are bypassed.
---@param active boolean
function Runtime.SetLayoutPreview(active)
    active = active == true
    if _layoutPreviewActive == active then
        return
    end
    _layoutPreviewActive = active
    ECM.Log(nil, "Layout preview " .. (active and "ON" or "OFF"))
    updateFadeAndHiddenStates()
    Runtime.ScheduleLayoutUpdate(0, active and "LayoutPreviewOn" or "LayoutPreviewOff")
end

--- Runs a layout update synchronously (no timer batching).
--- Use for Edit Mode drag where 1-frame latency is noticeable.
--- @param reason string|nil The lifecycle reason.
function Runtime.UpdateLayoutImmediately(reason)
    _layoutPending = false
    hookCooldownViewerSettings()
    updateFadeAndHiddenStates()
    updateAllLayouts(reason)
end

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
--- @param reason string|nil The lifecycle reason (defaults to OPTION_CHANGED)
function Runtime.ScheduleLayoutUpdate(delay, reason)
    if _layoutPending then
        return
    end

    _layoutPending = true
    C_Timer.After(delay or 0, function()
        _layoutPending = false
        hookCooldownViewerSettings()
        updateFadeAndHiddenStates()
        updateAllLayouts(reason)
    end)
end

--- Registers a FrameMixin to receive layout update events.
--- @param frame FrameMixin The frame to register
function Runtime.RegisterFrame(frame)
    ECM.FrameMixin.AssertValid(frame)
    assert(_modules[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")

    _modules[frame.Name] = frame
    frame:SetHidden(_globallyHidden)
    ECM.FrameUtil.LazySetAlpha(frame.InnerFrame, _desiredAlpha)
    ECM.Log(nil, "Frame registered: " .. frame.Name)
end

--- Unregisters a FrameMixin from layout update events.
--- @param frame FrameMixin The frame to unregister
function Runtime.UnregisterFrame(frame)
    ECM.FrameMixin.AssertValid(frame)
    assert(_modules[frame.Name] ~= nil, "UnregisterFrame: frame with name '" .. frame.Name .. "' is not registered")

    local name = frame.Name
    _modules[name] = nil
    frame:SetHidden(true)
    ECM.Log(nil, "Frame unregistered: " .. name)
end

--------------------------------------------------------------------------------
-- Event dispatch
--------------------------------------------------------------------------------

--- Handles a layout-triggering event, updating combat state and scheduling layout.
---@param addon table The AceAddon instance (self from the event handler)
---@param event string
---@param arg1 any
local function handleLayoutEvent(_addon, event, arg1)
    hookCooldownViewerSettings()

    if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then
        return
    end

    if event == "PLAYER_REGEN_ENABLED" and Runtime.OnCombatEnd then
        Runtime.OnCombatEnd()
    end

    if event == "CVAR_UPDATE" then
        if arg1 == "cooldownViewerEnabled" then
            Runtime.ScheduleLayoutUpdate(0, "CVAR_UPDATE:cooldownViewerEnabled")
        end
        return
    end

    local config = LAYOUT_EVENTS[event]
    if not config then
        return
    end

    if config.combatChange then
        _inCombat = (event == "PLAYER_REGEN_DISABLED")
    end

    if config.delay and config.delay > 0 then
        C_Timer.After(config.delay, function()
            updateFadeAndHiddenStates()
            updateAllLayouts(event)
        end)
        return
    end

    updateFadeAndHiddenStates()
    updateAllLayouts(event)
end

local function enableLayoutEvents(addon)
    if _layoutEventsEnabled then
        return
    end

    _layoutEventsEnabled = true

    if _layoutWatchdogTicker and type(_layoutWatchdogTicker.Cancel) == "function" then
        _layoutWatchdogTicker:Cancel()
    end

    for eventName in pairs(LAYOUT_EVENTS) do
        addon:RegisterEvent(eventName, function(_, ...) handleLayoutEvent(addon, eventName, ...) end)
    end
    addon:RegisterEvent("CVAR_UPDATE", function(_, ...) handleLayoutEvent(addon, "CVAR_UPDATE", ...) end)

    -- Watchdog — catches cases where the game externally re-shows or resets alpha
    -- on Blizzard cooldown viewer frames between layout events.
    _layoutWatchdogTicker = C_Timer.NewTicker(C.WATCHDOG_INTERVAL, function()
        hookBlizzardFrames()
        hookCooldownViewerSettings()
        enforceBlizzardFrameState()

        local alpha = _desiredAlpha
        for _, module in pairs(_modules) do
            if module.InnerFrame and not module.IsHidden then
                ECM.FrameUtil.LazySetAlpha(module.InnerFrame, alpha)
            end
        end
    end)
end

local function disableLayoutEvents(addon)
    if not _layoutEventsEnabled then
        return
    end

    _layoutEventsEnabled = false

    for eventName in pairs(LAYOUT_EVENTS) do
        addon:UnregisterEvent(eventName)
    end
    addon:UnregisterEvent("CVAR_UPDATE")

    if _layoutWatchdogTicker and type(_layoutWatchdogTicker.Cancel) == "function" then
        _layoutWatchdogTicker:Cancel()
    end
    _layoutWatchdogTicker = nil
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

--- Enables the runtime: enables/disables modules per config and starts layout events.
---@param addon table The AceAddon instance
function Runtime.Enable(addon)
    local profile = addon.db and addon.db.profile

    for _, moduleName in ipairs(C.MODULE_ORDER) do
        local configKey = C.MODULE_CONFIG_KEYS[moduleName]
        local moduleConfig = profile and profile[configKey]
        local shouldEnable = (not moduleConfig) or (moduleConfig.enabled ~= false)
        if shouldEnable then
            addon:EnableModule(moduleName)
        else
            addon:DisableModule(moduleName)
        end
    end

    enableLayoutEvents(addon)
end

--- Disables the runtime: stops layout events.
---@param addon table The AceAddon instance
function Runtime.Disable(addon)
    disableLayoutEvents(addon)
end
