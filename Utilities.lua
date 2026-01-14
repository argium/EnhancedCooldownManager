local _, ns = ...

local Util = ns.Util or {}
ns.Util = Util

local LSM = LibStub("LibSharedMedia-3.0", true)

Util.WHITE8 = "Interface\\Buttons\\WHITE8X8"

--- Default background color used across all ECM bars.
Util.DEFAULT_BG_COLOR = { 0.08, 0.08, 0.08, 0.65 }

function Util.InSecretRegime()
    return type(canaccesssecrets) == "function" and not canaccesssecrets()
end

--- Pixel-snaps a number to the nearest pixel for the current UI scale.
---@param v number|nil
---@return number
function Util.PixelSnap(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
end

--- Returns the resolved background color from config or defaults.
---@param cfg table|nil Module-specific config (e.g., profile.powerBar)
---@param profile table|nil Full profile table
---@return number[] RGBA color array
function Util.GetBgColor(cfg, profile)
    local gbl = profile and profile.global
    return (cfg and cfg.bgColor) or (gbl and gbl.barBgColor) or Util.DEFAULT_BG_COLOR
end

--- Returns the resolved bar height from config or defaults.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@param fallback number|nil Fallback height if nothing is configured
---@return number
function Util.GetBarHeight(cfg, profile, fallback)
    local gbl = profile and profile.global
    local h = (cfg and cfg.height) or (gbl and gbl.barHeight) or (fallback or 20)
    return Util.PixelSnap(h)
end

--- Returns the top gap offset for the first bar anchored to the viewer.
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return number
function Util.GetTopGapOffset(cfg, profile)
    local defaultOffset = (profile and profile.offsetY) or 6
    if cfg and cfg.offsetY ~= nil then
        return cfg.offsetY
    end
    return defaultOffset
end

--- Returns a statusbar texture path (LSM-resolved when available).
---@param textureOverride string|nil
---@return string
function Util.GetTexture(textureOverride)
    if textureOverride and type(textureOverride) == "string" then
        if LSM and LSM.Fetch then
            local fetched = LSM:Fetch("statusbar", textureOverride, true)
            if fetched then
                return fetched
            end
        end

        -- If this doesn't look like a valid texture path (e.g. "Solid") and LSM isn't available,
        -- fall back to a built-in texture instead of returning an invalid path.
        if not textureOverride:find("\\") then
            return "Interface\\TARGETINGFRAME\\UI-StatusBar"
        end

        return textureOverride
    end

    if LSM and LSM.Fetch then
        local fetched = LSM:Fetch("statusbar", "Blizzard", true)
        if fetched then
            return fetched
        end
    end

    return "Interface\\TARGETINGFRAME\\UI-StatusBar"
end

--- Returns a font file path (LSM-resolved when available).
---@param fontKey string|nil
---@param fallback string|nil
---@return string
function Util.GetFontPath(fontKey, fallback)
    local fallbackPath = fallback or "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"

    if LSM and LSM.Fetch and fontKey and type(fontKey) == "string" then
        local fetched = LSM:Fetch("font", fontKey, true)
        if fetched then
            return fetched
        end
    end

    return fallbackPath
end

--- Applies background color and statusbar texture to a bar.
--- Returns the resolved texture path for caching.
---@param bar table Bar frame with Background and StatusBar children
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile table
---@return string|nil texture The resolved texture path
function Util.ApplyBarAppearance(bar, cfg, profile)
    if not bar then
        return nil
    end

    local bgColor = Util.GetBgColor(cfg, profile)
    if bar.Background and bar.Background.SetColorTexture then
        bar.Background:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end

    local gbl = profile and profile.global
    local tex = Util.GetTexture((cfg and cfg.texture) or (gbl and gbl.texture))
    if bar.StatusBar and bar.StatusBar.SetStatusBarTexture then
        bar.StatusBar:SetStatusBarTexture(tex)
    end

    return tex
end

--- Applies font settings to a FontString.
---@param fontString FontString
---@param profile table|nil Full profile table
function Util.ApplyFont(fontString, profile)
    if not fontString or not fontString.SetFont then
        return
    end

    local gbl = profile and profile.global
    local fontPath = Util.GetFontPath(gbl and gbl.font)
    local fontSize = (gbl and gbl.fontSize) or 11
    local fontOutline = (gbl and gbl.fontOutline) or "OUTLINE"
    local outlineFlag = fontOutline ~= "NONE" and fontOutline or ""

    fontString:SetFont(fontPath, fontSize, outlineFlag)

    if fontString.SetShadowOffset then
        if gbl and gbl.fontShadow then
            fontString:SetShadowColor(0, 0, 0, 1)
            fontString:SetShadowOffset(1, -1)
        else
            fontString:SetShadowOffset(0, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Shared module helpers (reduce duplication across PowerBars/SegmentBar)
--------------------------------------------------------------------------------

--- Default bar heights for each module type.
Util.DEFAULT_POWER_BAR_HEIGHT = 20
Util.DEFAULT_SEGMENT_BAR_HEIGHT = 13

--- Sets externally hidden state on a module (e.g., when mounted).
--- Use as: Util.SetExternallyHidden(self, hidden)
---@param module table AceModule with _externallyHidden, _frame fields
---@param hidden boolean Whether to hide externally
---@param moduleName string Module name for logging
function Util.SetExternallyHidden(module, hidden, moduleName)
    local wasHidden = module._externallyHidden
    module._externallyHidden = hidden and true or false
    if wasHidden ~= module._externallyHidden then
        Util.Log(moduleName, "SetExternallyHidden", { hidden = module._externallyHidden })
    end
    if module._externallyHidden and module._frame then
        module._frame:Hide()
    end
end

--- Returns the module's frame if it exists and is shown.
---@param module table AceModule with _externallyHidden, _frame fields
---@return Frame|nil
function Util.GetFrameIfShown(module)
    local f = module._frame
    return (not module._externallyHidden and f and f:IsShown()) and f or nil
end

--- Common UpdateLayout guards: checks profile, externally hidden, enabled, and shouldShow.
--- Returns nil on early-exit (caller should return), or { profile, cfg } on success.
---@param module table AceModule with _externallyHidden, _frame, :Disable() methods
---@param configKey string Config key in profile (e.g., "powerBar", "segmentBar")
---@param shouldShowFn function|nil Optional function returning bool for visibility
---@param moduleName string Module name for logging
---@return table|nil result { profile = ..., cfg = ... } or nil
function Util.CheckUpdateLayoutPreconditions(module, configKey, shouldShowFn, moduleName)
    local addon = ns.Addon
    local profile = addon and addon.db and addon.db.profile
    if not profile then
        Util.Log(moduleName, "UpdateLayout skipped - no profile")
        return nil
    end

    if module._externallyHidden then
        Util.Log(moduleName, "UpdateLayout skipped - externally hidden")
        if module._frame then
            module._frame:Hide()
        end
        return nil
    end

    if profile.enabled == false then
        Util.Log(moduleName, "UpdateLayout - addon disabled")
        module:Disable()
        return nil
    end

    local cfg = profile[configKey]
    if not (cfg and cfg.enabled) then
        Util.Log(moduleName, "UpdateLayout - " .. configKey .. " disabled in config")
        module:Disable()
        return nil
    end

    if shouldShowFn and not shouldShowFn() then
        Util.Log(moduleName, "UpdateLayout - shouldShow returned false")
        if module._frame then
            module._frame:Hide()
        end
        return nil
    end

    return { profile = profile, cfg = cfg }
end

--- Applies layout (anchor, height) to a bar frame only if changed.
--- Caches _lastAnchor, _lastOffsetY, _lastHeight on the bar.
---@param bar Frame Bar frame with ClearAllPoints, SetPoint, SetHeight methods
---@param anchor Frame Anchor frame
---@param offsetY number Vertical offset from anchor
---@param height number Desired bar height
function Util.ApplyLayoutIfChanged(bar, anchor, offsetY, height)
    if bar._lastAnchor ~= anchor or bar._lastOffsetY ~= offsetY then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, offsetY)
        bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, offsetY)
        bar._lastAnchor = anchor
        bar._lastOffsetY = offsetY
    end

    if bar._lastHeight ~= height then
        bar:SetHeight(height)
        bar._lastHeight = height
    end
end

-- CooldownViewer icon-strip bound helpers.

local function TryGetLeftRight(frame)
    if not frame then
        return nil, nil
    end
    local l, r = frame:GetLeft(), frame:GetRight()
    return (type(l) == "number" and type(r) == "number") and l or nil, r
end

--- Attempts to find the left/right bounds of the icon strip inside EssentialCooldownViewer.
--- Simple + explicit: scan direct children for icon-like buttons and take min/max bounds.
---@param viewer table
local function TryFindEssentialViewerIconBounds(viewer)
    if not (viewer and viewer.GetChildren) then
        return nil, nil
    end

    local ok, children = pcall(function()
        return { viewer:GetChildren() }
    end)
    if not ok or not children then
        return nil, nil
    end

    local bestLeft, bestRight
    for _, child in ipairs(children) do
        if child and child.IsShown and child:IsShown() then
            local l, r = TryGetLeftRight(child)
            if l and r then
                if not bestLeft or l < bestLeft then
                    bestLeft = l
                end
                if not bestRight or r > bestRight then
                    bestRight = r
                end
            end
        end
    end

    if bestLeft and bestRight and bestRight > bestLeft then
        return bestLeft, bestRight
    end
    return nil, nil
end

local MIN_BAR_WIDTH = 200

--- Positions/sizes a bar relative to an anchor.
---@param bar table
---@param anchor table
---@param heightPx number|nil
---@param widthPx number|nil
---@param offsetX number|nil
---@param offsetY number|nil
---@param matchAnchorWidth boolean|nil When true, use points to match the anchor width instead of SetWidth.
function Util.ApplyBarLayout(bar, anchor, heightPx, widthPx, offsetX, offsetY, matchAnchorWidth)
    local desiredX = Util.PixelSnap(offsetX or 0)
    local desiredY = Util.PixelSnap(offsetY or 0)

    bar:ClearAllPoints()

    if matchAnchorWidth then
        local usedIconBounds = false

        -- If we're anchoring to a Blizzard CooldownViewer, match the bar to the actual icon strip
        -- so the bar doesn't extend beyond the left/right edges of the icons.
        local anchorName = (anchor and anchor.GetName) and anchor:GetName() or nil
        if anchorName == "EssentialCooldownViewer" then
            local iconLeft, iconRight = TryFindEssentialViewerIconBounds(anchor)
            local anchorLeft, anchorRight = TryGetLeftRight(anchor)
            if iconLeft and iconRight and anchorLeft and anchorRight then
                local leftOffset = Util.PixelSnap(iconLeft - anchorLeft) + desiredX
                local rightOffset = Util.PixelSnap(iconRight - anchorRight) + desiredX
                bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", leftOffset, -desiredY)
                bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", rightOffset, -desiredY)
                usedIconBounds = true
            end
        end

        -- Fallback for EssentialCooldownViewer when icon bounds not found.
        if not usedIconBounds then
            if anchorName == "EssentialCooldownViewer" then
                local rowX = Util.PixelSnap(desiredX - 4)
                bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", rowX, -desiredY)
                bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", rowX, -desiredY)
            else
                -- Non-viewer anchor: align edges directly.
                bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", desiredX, -desiredY)
                bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", desiredX, -desiredY)
            end
        end
    else
        -- Non-viewer anchor: align edges directly without the Blizzard offset.
        bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", desiredX, -desiredY)
        bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", desiredX, -desiredY)
    end

    if heightPx ~= nil and bar.SetHeight then
        bar:SetHeight(heightPx)
    end

    if not matchAnchorWidth and widthPx ~= nil and bar.SetWidth then
        bar:SetWidth(widthPx)
    end

    -- Enforce minimum bar width
    if bar.GetWidth and bar.SetWidth then
        local currentWidth = bar:GetWidth()
        if currentWidth and currentWidth < MIN_BAR_WIDTH then
            bar:SetWidth(MIN_BAR_WIDTH)
        end
    end
end

local VIEWER_ANCHOR_NAME = "EssentialCooldownViewer"

--- Returns the base viewer anchor frame (even if it's currently hidden).
---@return Frame
function Util.GetViewerAnchor()
    local f = _G[VIEWER_ANCHOR_NAME]
    return (f and f:GetPoint(1)) and f or UIParent
end

--- Returns the bottom-most visible ECM bar frame for anchoring.
--- Chain order: Viewer -> PowerBar -> SegmentBar.
--- Modules that don't exist or aren't shown are skipped.
---@param addon table The EnhancedCooldownManager addon table
---@param excludeModule string|nil Module name to exclude from the chain (e.g., "SegmentBar" when SegmentBar is querying its own anchor)
---@return Frame anchor The frame to anchor to
---@return boolean isFirstBar True if anchoring directly to the viewer (no ECM bars above)
function Util.GetPreferredAnchor(addon, excludeModule)
    local viewer = Util.GetViewerAnchor()

    -- Chain: PowerBars -> SegmentBar (in order)
    local chain = { "PowerBars", "SegmentBar" }
    local bottomMost = nil

    for _, modName in ipairs(chain) do
        if modName ~= excludeModule then
            local mod = addon[modName]
            if mod and mod.GetFrameIfShown then
                local f = mod:GetFrameIfShown()
                if f then
                    bottomMost = f
                end
            end
        end
    end

    if bottomMost then
        return bottomMost, false
    end

    return viewer, true
end

--- Safely converts a value to a copyable form, handling WoW secret values.
---@param v any
---@return any
local function SafeCopyValue(v)
    if type(issecretvalue) == "function" and issecretvalue(v) then
        return (type(canaccessvalue) == "function" and canaccessvalue(v)) and ("s|" .. tostring(v)) or "<secret>"
    end
    if type(issecrettable) == "function" and issecrettable(v) then
        return (type(canaccesstable) == "function" and canaccesstable(v)) and "s|<table>" or "<secrettable>"
    end
    return v
end

--- Creates a deep copy of a table with cycle detection and depth limit.
---@param tbl any Value to copy
---@param seen table|nil Table tracking visited tables (for recursion)
---@param depth number|nil Current depth (for recursion)
---@return any
function Util.DeepCopy(tbl, seen, depth)
    if type(tbl) ~= "table" then
        return tbl
    end

    depth = (depth or 0) + 1
    if depth > 10 then
        return "<max depth>"
    end

    seen = seen or {}
    if seen[tbl] then
        return "<cycle>"
    end
    seen[tbl] = true

    local copy = {}
    for k, v in pairs(tbl) do
        -- Handle secret keys
        if type(issecretvalue) == "function" and issecretvalue(k) then
            copy["<secret_key>"] = "<secret>"
        elseif type(v) == "table" then
            copy[k] = Util.DeepCopy(v, seen, depth)
        else
            copy[k] = SafeCopyValue(v)
        end
    end

    seen[tbl] = nil
    return copy
end

--- Unified debug logging: sends to DevTool and trace buffer when debug mode is ON.
---@param moduleName string Module name for prefix (e.g., "PowerBars", "SegmentBar")
---@param message string Log message describing the event
---@param data any|nil Optional data to log (tables are deep-copied for DevTool)
function Util.Log(moduleName, message, data)
    local addon = ns.Addon
    local profile = addon and addon.db and addon.db.profile
    if not profile or not profile.debug then
        return
    end

    local prefix = "ECM:" .. moduleName .. " - " .. message

    -- Add to trace log buffer for /ecm bug
    if ns.AddToTraceLog then
        local logLine = prefix
        if data ~= nil then
            if type(data) == "table" then
                local parts = {}
                for k, v in pairs(data) do
                    parts[#parts + 1] = tostring(k) .. "=" .. addon:SafeGetDebugValue(v)
                end
                logLine = logLine .. ": {" .. table.concat(parts, ", ") .. "}"
            else
                logLine = logLine .. ": " .. addon:SafeGetDebugValue(data)
            end
        end
        ns.AddToTraceLog(logLine)
    end

    -- Send to DevTool when available
    if DevTool and DevTool.AddData then
        local payload = {
            module = moduleName,
            message = message,
            timestamp = GetTime(),
            data = type(data) == "table" and Util.DeepCopy(data) or SafeCopyValue(data),
        }
        pcall(DevTool.AddData, DevTool, payload, prefix)
    end
end
