local ADDON_NAME, ns = ...
local EnhancedCooldownManager = ns.Addon
local Util = ns.Util

local PowerBars = EnhancedCooldownManager:NewModule("PowerBars", "AceEvent-3.0")
EnhancedCooldownManager.PowerBars = PowerBars

--- Returns max/current/display values for primary resource formatting.
---@param resource Enum.PowerType|nil
---@param cfg table|nil
---@return number|nil max
---@return number|nil current
---@return number|nil displayValue
---@return string|nil valueType
local function GetPrimaryResourceValue(resource, cfg)
    if not resource then
        return nil, nil, nil, nil
    end

    local current = UnitPower("player", resource) or 0
    local max = UnitPowerMax("player", resource) or 0

    if max <= 0 then
        return nil, nil, nil, nil
    end

    if cfg and cfg.showManaAsPercent and resource == Enum.PowerType.Mana then
        local percent = (current / max) * 100
        return max, current, percent, "percent"
    end

    return max, current, current, "number"
end

--- Returns the configured color for a resource type.
---@param resource Enum.PowerType
---@return number r
---@return number g
---@return number b
local function GetColorForResource(resource)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local ptc = profile and profile.powerTypeColors
    assert(ptc ~= nil, "Expected powerTypeColors config to be present.")

    local colors = ptc and ptc.colors
    local override = colors and colors[resource]
    if type(override) == "table" then
        return override[1] or 1, override[2] or 1, override[3] or 1
    end

    return 1, 1, 1
end

local function ShouldShowPowerBar()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not (profile and profile.powerBar and profile.powerBar.enabled) then
        return false
    end

    local _, class = UnitClass("player")
    local powerType = UnitPowerType("player")

    -- Hide mana bar for DPS specs, except mage/warlock/caster-form druid
    local role = GetSpecializationRole(GetSpecialization())
    if role == "DAMAGER" and powerType == Enum.PowerType.Mana then
        return class == "MAGE" or class == "WARLOCK" or class == "DRUID"
    end

    return true
end

---@class ECM_PowerBarFrame : Frame
---@field Background Texture
---@field StatusBar StatusBar
---@field TextFrame Frame
---@field TextValue FontString
---@field ticks Texture[]
---@field energyTick Texture|nil
---@field _lastAnchor Frame|nil
---@field _lastOffsetY number|nil
---@field _lastHeight number|nil
---@field _lastTexture string|nil

--- Creates the power bar frame with all child elements.
---@param frameName string
---@param parent Frame
---@return ECM_PowerBarFrame
local function CreatePowerBar(frameName, parent)
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local cfg = profile and profile.powerBar

    local bar = CreateFrame("Frame", frameName, parent or UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetHeight(Util.GetBarHeight(cfg, profile, Util.DEFAULT_POWER_BAR_HEIGHT))

    -- Background
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()

    -- StatusBar
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)

    -- Apply initial appearance
    Util.ApplyBarAppearance(bar, cfg, profile)

    -- Text overlay
    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 10)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", 0, 0)
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetJustifyV("MIDDLE")
    bar.TextValue:SetText("0")
    Util.ApplyFont(bar.TextValue, profile)

    bar:Hide()
    ---@cast bar ECM_PowerBarFrame
    return bar
end

--- Marks the power bar as externally hidden (e.g., via ViewerHook).
---@param hidden boolean
function PowerBars:SetExternallyHidden(hidden)
    Util.SetExternallyHidden(self, hidden, "PowerBars")
end

--- Returns or creates the power bar frame.
---@return ECM_PowerBarFrame
function PowerBars:GetFrame()
    if self._frame then
        return self._frame
    end

    Util.Log("PowerBars", "Creating frame")
    self._frame = CreatePowerBar(ADDON_NAME .. "PowerBar", UIParent)
    return self._frame
end

--- Returns the frame only if currently shown.
---@return ECM_PowerBarFrame|nil
function PowerBars:GetFrameIfShown()
    return Util.GetFrameIfShown(self)
end

--- Returns the tick marks configured for the current class and spec.
---@return ECM_TickMark[]|nil
function PowerBars:GetCurrentTicks()
    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local ticksCfg = profile and profile.powerBarTicks
    if not ticksCfg or not ticksCfg.mappings then
        return nil
    end

    local classID = select(3, UnitClass("player"))
    local specIndex = GetSpecialization()
    local specID = specIndex and GetSpecializationInfo(specIndex)
    if not classID or not specID then
        return nil
    end

    local classMappings = ticksCfg.mappings[classID]
    if not classMappings then
        return nil
    end

    return classMappings[specID]
end

--- Updates tick markers on the power bar based on per-class/spec configuration.
---@param bar ECM_PowerBarFrame
---@param resource Enum.PowerType
---@param max number
function PowerBars:UpdateTicks(bar, resource, max)
    -- Initialize tick pool if needed
    if not bar.tickPool then
        bar.tickPool = {}
    end

    -- Hide all existing ticks first
    for _, tick in ipairs(bar.tickPool) do
        tick:Hide()
    end

    local ticks = self:GetCurrentTicks()
    if not ticks or #ticks == 0 then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    local ticksCfg = profile and profile.powerBarTicks
    local defaultColor = ticksCfg and ticksCfg.defaultColor or { 0, 0, 0, 0.5 }
    local defaultWidth = ticksCfg and ticksCfg.defaultWidth or 1

    local barWidth = bar.StatusBar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth <= 0 or barHeight <= 0 or max <= 0 then
        return
    end

    for i, tickData in ipairs(ticks) do
        local value = tickData.value
        if value and value > 0 and value < max then
            -- Get or create tick texture
            local tick = bar.tickPool[i]
            if not tick then
                tick = bar.StatusBar:CreateTexture(nil, "OVERLAY")
                bar.tickPool[i] = tick
            end

            -- Get tick appearance
            local color = tickData.color or defaultColor
            local width = tickData.width or defaultWidth

            -- Position and style the tick
            local x = math.floor((value / max) * barWidth)
            tick:ClearAllPoints()
            tick:SetPoint("LEFT", bar.StatusBar, "LEFT", x, 0)
            tick:SetSize(math.max(1, Util.PixelSnap(width)), barHeight)
            tick:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 0.5)
            tick:Show()
        end
    end
end

--- Updates layout: positioning, sizing, anchoring, appearance.
function PowerBars:UpdateLayout()
    local result = Util.CheckUpdateLayoutPreconditions(self, "powerBar", ShouldShowPowerBar, "PowerBars")
    if not result then
        return
    end

    self:Enable()

    local profile, cfg = result.profile, result.cfg
    local bar = self:GetFrame()
    local anchor = Util.GetViewerAnchor() or UIParent

    local desiredHeight = Util.GetBarHeight(cfg, profile, Util.DEFAULT_POWER_BAR_HEIGHT)
    local desiredOffsetY = -Util.GetTopGapOffset(cfg, profile)

    Util.ApplyLayoutIfChanged(bar, anchor, desiredOffsetY, desiredHeight)

    -- Update appearance (background, texture)
    local tex = Util.ApplyBarAppearance(bar, cfg, profile)
    bar._lastTexture = tex

    -- Update font
    Util.ApplyFont(bar.TextValue, profile)

    Util.Log("PowerBars", "UpdateLayout complete", {
        anchorName = anchor.GetName and anchor:GetName() or "unknown",
        height = desiredHeight,
        offsetY = desiredOffsetY
    })

    bar:Show()
    self:Refresh()
end

--- Updates values: status bar value, text, colors, ticks.
function PowerBars:Refresh()
    if self._externallyHidden then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not profile then
        return
    end

    if not (profile.powerBar and profile.powerBar.enabled) then
        return
    end

    if not ShouldShowPowerBar() then
        if self._frame then
            self._frame:Hide()
        end
        return
    end

    local bar = self._frame
    if not bar then
        return
    end

    local cfg = profile.powerBar
    local resource = UnitPowerType("player")
    local max, current, displayValue, valueType = GetPrimaryResourceValue(resource, cfg)

    if not max then
        bar:Hide()
        return
    end

    current = current or 0
    displayValue = displayValue or 0

    bar.StatusBar:SetMinMaxValues(0, max)
    bar.StatusBar:SetValue(current)

    local r, g, b = GetColorForResource(resource)
    bar.StatusBar:SetStatusBarColor(r, g, b)

    -- Update text
    if valueType == "percent" then
        bar.TextValue:SetText(string.format("%.0f%%", displayValue))
    else
        bar.TextValue:SetText(tostring(displayValue))
    end

    bar.TextFrame:SetShown(cfg.showText ~= false)

    -- Update ticks
    self:UpdateTicks(bar, resource, max)

    bar:Show()
end

function PowerBars:OnUnitPower(_, unit)
    if unit ~= "player" then
        return
    end

    if self._externallyHidden then
        return
    end

    local profile = EnhancedCooldownManager.db and EnhancedCooldownManager.db.profile
    if not (profile and profile.powerBar and profile.powerBar.enabled) then
        return
    end

    local now = GetTime()
    local last = self._lastUpdate or 0
    local freq = profile.updateFrequency or 0.066

    if now - last >= freq then
        self:Refresh()
        self._lastUpdate = now
    end
end

function PowerBars:Enable()
    if self._enabled then
        return
    end
    self._enabled = true
    self._lastUpdate = GetTime()
    self:RegisterEvent("UNIT_POWER_UPDATE", "OnUnitPower")
    Util.Log("PowerBars", "Enabled - registered UNIT_POWER_UPDATE")
end

function PowerBars:Disable()
    if self._frame then
        self._frame:Hide()
    end

    if not self._enabled then
        return
    end
    self._enabled = false

    self:UnregisterEvent("UNIT_POWER_UPDATE")
    Util.Log("PowerBars", "Disabled - unregistered events")
end

function PowerBars:OnEnable()
    Util.Log("PowerBars", "OnEnable - module starting")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "UpdateLayout")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "UpdateLayout")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateLayout")

    C_Timer.After(0.1, function()
        self:UpdateLayout()
    end)
end

function PowerBars:OnDisable()
    Util.Log("PowerBars", "OnDisable - module stopping")
    self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    self:UnregisterEvent("UPDATE_SHAPESHIFT_FORM")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:Disable()
end
