local ADDON_NAME, ns = ...

---@class ECM_ColorARGB
---@field a number
---@field r number
---@field g number
---@field b number

-- BEGIN: Configuration (type docs)

---@class ECM_BarConfigBase
---@field enabled boolean
---@field offsetY number|nil
---@field height number|nil
---@field texture string|nil
---@field showText boolean|nil
---@field bgColor ECM_ColorARGB|nil

---@class ECM_PowerBarConfig : ECM_BarConfigBase
---@field showManaAsPercent boolean

---@class ECM_SegmentBarConfig : ECM_BarConfigBase
---@field demonHunterSoulsSpellId number
---@field demonHunterSoulsMax number
---@field deathKnightRunesMax number
---@field frostMageIciclesSpellId number
---@field frostMageIciclesMax number
---@field colorDkBlood number[]
---@field colorDkFrost number[]
---@field colorDkUnholy number[]
---@field colorDemonHunterSouls number[]
---@field colorFrostMageIcicles number[]

---@alias ECM_ResourceType number|string

---@class ECM_PowerTypeColorsSpecial
---@field deathKnight table|nil

---@class ECM_PowerTypeColorsConfig
---@field colors table<ECM_ResourceType, number[]>
---@field special ECM_PowerTypeColorsSpecial

---@class ECM_GlobalConfig
---@field barHeight number
---@field texture string
---@field font string
---@field fontSize number
---@field fontOutline string Font outline style: "NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME"
---@field fontShadow boolean Whether to show font shadow

---@class ECM_DynamicBarConfig
---@field auraSpellIds number[] Spell IDs that map to this style entry.
---@field height number|nil
---@field texture string|nil
---@field bgColor ECM_ColorARGB|nil
---@field color number[]|nil

---@class ECM_DynamicBarsConfig
---@field showIcon boolean|nil When nil, defaults to showing the icon.
---@field showSpellName boolean|nil When nil, defaults to showing the spell name.
---@field showDuration boolean|nil When nil, defaults to showing the duration.

---@class ECM_BarCacheEntry
---@field spellName string|nil Display name (safe string, not secret)
---@field lastSeen number Timestamp of last appearance

---@class ECM_BuffBarColorsConfig
---@field colors table<number, table<number, table<number, number[]>>> [classID][specID][barIndex] = {r, g, b}
---@field cache table<number, table<number, table<number, ECM_BarCacheEntry>>> [classID][specID][barIndex] = metadata
---@field defaultColor number[] Default RGB color for buff bars

---@class ECM_ProcOverlayConfig
---@field enabled boolean Master toggle for proc overlay feature
---@field mappings table<number, table<number, table<number, number>>> [classID][specID][buffIconIndex] = targetIconIndex

---@class ECM_TickMark
---@field value number The resource value at which to display the tick
---@field color number[] RGBA color for this tick mark
---@field width number Width of the tick mark in pixels

---@class ECM_PowerBarTicksConfig
---@field mappings table<number, table<number, ECM_TickMark[]>> [classID][specID] = array of tick marks
---@field defaultColor number[] Default RGBA color for tick marks
---@field defaultWidth number Default width for tick marks

---@class ECM_Profile
---@field enabled boolean
---@field hideWhenMounted number
---@field updateFrequency number
---@field schemaVersion number
---@field debug boolean
---@field offsetY number
---@field global ECM_GlobalConfig
---@field powerBar ECM_PowerBarConfig
---@field segmentBar ECM_SegmentBarConfig
---@field powerTypeColors ECM_PowerTypeColorsConfig
---@field dynamicBars ECM_DynamicBarsConfig|ECM_DynamicBarConfig[]
---@field buffBarColors ECM_BuffBarColorsConfig
---@field procOverlay ECM_ProcOverlayConfig
---@field powerBarTicks ECM_PowerBarTicksConfig

-- END Configuration

local EnhancedCooldownManager = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.Addon = EnhancedCooldownManager

local LSM = LibStub("LibSharedMedia-3.0", true)

local POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI"

-- Priority list for default texture selection (first available wins)
local TEXTURE_PRIORITY = {
    "ElvUI Norm",
    "Solid",
}

--- Returns the first available texture from the priority list.
---@return string|nil
local function GetDefaultTexture()
    if not LSM or not LSM.IsValid then return nil end
    for _, textureName in ipairs(TEXTURE_PRIORITY) do
        if LSM:IsValid("statusbar", textureName) then
            return textureName
        end
    end
    return nil
end
ns.GetDefaultTexture = GetDefaultTexture

local defaults = {
    profile = {
        enabled = true,
        debug = false,
        hideWhenMounted = true,
        updateFrequency = 0.066,
        schemaVersion = 1,
        offsetY = 3,
        global = {
            barHeight = 22,
            barBgColor = { 0.08, 0.08, 0.08, 0.85 },
            texture = nil, -- Selected from TEXTURE_PRIORITY on first load
            font = "Expressway",
            fontSize = 11,
            fontOutline = "OUTLINE",
            fontShadow = false,
        },
        powerBar = {
            enabled           = true,
            height            = nil,
            texture           = nil,
            showManaAsPercent = true,
            showText          = true,
        },
        segmentBar = {
            enabled = true,
            height = nil,
            texture = nil,
            bgColor = nil,
            demonHunterSoulsSpellId = 203720,
            demonHunterSoulsMax = 5,
            colorDemonHunterSouls = { 0.46, 0.98, 1.00 },
            deathKnightRunesMax = 6,
            -- NOTE: Icicles tracking uses AuraUtil.FindAuraBySpellId which will likely break in v12.0 due to secret value restrictions
            frostMageIciclesSpellId = 205473,
            frostMageIciclesMax = 5,
            colorFrostMageIcicles = { 0.41, 0.80, 0.94 },
            colorDkRunes = { 0.87, 0.10, 0.22 },
            colorComboPoints = { 0.75, 0.15, 0.15 },
        },
        dynamicBars = {
            showIcon = false,
            showSpellName = true,
            showDuration = true,
        },
        buffBarColors = {
            colors = {},
            cache = {},
            defaultColor = { 0.85, 0.75, 0.55 },
        },
        procOverlay = {
            enabled = false,
            mappings = {}, -- [classID][specID][buffIconIndex] = targetIconIndex
        },
        powerBarTicks = {
            mappings = {}, -- [classID][specID] = { { value = 50, color = {r,g,b,a}, width = 1 }, ... }
            defaultColor = { 0, 0, 0, 0.5 },
            defaultWidth = 1,
        },
        powerTypeColors = {
            colors = {
                [Enum.PowerType.Mana] = { 0.00, 0.00, 1.00 },
                [Enum.PowerType.Rage] = { 1.00, 0.00, 0.00 },
                [Enum.PowerType.Focus] = { 1.00, 0.57, 0.31 },
                [Enum.PowerType.Energy] = { 0.85, 0.65, 0.13 },
                [Enum.PowerType.RunicPower] = { 0.00, 0.82, 1.00 },
                [Enum.PowerType.LunarPower] = { 0.30, 0.52, 0.90 },
                [Enum.PowerType.Fury] = { 0.79, 0.26, 0.99 },
                [Enum.PowerType.Maelstrom] = { 0.00, 0.50, 1.00 },
                [Enum.PowerType.Essence] = { 0.20, 0.58, 0.50 },
                [Enum.PowerType.ArcaneCharges] = { 0.20, 0.60, 1.00 },
                [Enum.PowerType.Chi] = { 0.00, 1.00, 0.59 },
                [Enum.PowerType.HolyPower] = { 1.00, 0.82, 0.00 },
                [Enum.PowerType.SoulShards] = { 0.58, 0.51, 0.79 },
            },
        },
    },
}

-- Export defaults for Options module to access
ns.defaults = defaults

---@param colorPrefix string
---@param ... any
local function PrintColored(addon, colorPrefix, ...)
    local n = select("#", ...)
    if n <= 0 then
        return
    end

    local args = {}
    for i = 1, n do
        args[i] = addon:SafeGetDebugValue(select(i, ...))
    end

    print(colorPrefix .. table.concat(args, " ") .. "|r")
end

--------------------------------------------------------------------------------
-- Trace Log Buffer (circular buffer for last 100 debug messages)
--------------------------------------------------------------------------------
local TRACE_LOG_MAX = 100
local traceLogBuffer = {}
local traceLogIndex = 0
local traceLogCount = 0

--- Adds a message to the trace log buffer.
---@param message string
local function AddToTraceLog(message)
    traceLogIndex = (traceLogIndex % TRACE_LOG_MAX) + 1
    traceLogBuffer[traceLogIndex] = string.format("[%s] %s", date("%H:%M:%S"), message)
    if traceLogCount < TRACE_LOG_MAX then
        traceLogCount = traceLogCount + 1
    end
end
ns.AddToTraceLog = AddToTraceLog

--- Returns the trace log contents as a single string.
---@return string
local function GetTraceLog()
    if traceLogCount == 0 then
        return "(No trace logs recorded)"
    end

    local lines = {}
    local startIdx = (traceLogCount < TRACE_LOG_MAX) and 1 or (traceLogIndex + 1)
    for i = 1, traceLogCount do
        local idx = ((startIdx - 2 + i) % TRACE_LOG_MAX) + 1
        lines[i] = traceLogBuffer[idx]
    end
    return table.concat(lines, "\n")
end

--------------------------------------------------------------------------------
-- Bug Report Popup Frame
--------------------------------------------------------------------------------
local bugReportFrame = nil

--- Gets player info string for bug reports.
---@return string
local function GetPlayerInfoString()
    local version = C_AddOns.GetAddOnMetadata("EnhancedCooldownManager", "Version") or "unknown"
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local specIndex = GetSpecialization()
    local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "None"

    return string.format("ECM v%s | %s %s %d | %s", version, race, class, level, specName)
end

--- Creates or returns the bug report popup frame.
---@return Frame
local function GetBugReportFrame()
    if bugReportFrame then
        return bugReportFrame
    end

    local frame = CreateFrame("Frame", "ECMBugReportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(600, 400)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:Hide()

    -- Header text
    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOP", 0, -16)
    header:SetText("Press Ctrl+C to copy, then click to close")
    header:SetTextColor(1, 0.82, 0)

    -- Scroll frame for content
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", -36, 16)

    -- Edit box for selectable/copyable text
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    editBox:SetAutoFocus(true)
    scrollFrame:SetScrollChild(editBox)

    frame.editBox = editBox
    frame.originalText = ""

    -- Make read-only by reverting any text changes
    editBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput and frame.originalText then
            self:SetText(frame.originalText)
            self:HighlightText()
        end
    end)

    editBox:SetScript("OnEscapePressed", function()
        frame:Hide()
    end)

    -- Re-highlight on click
    editBox:SetScript("OnMouseUp", function(self)
        self:HighlightText()
    end)

    -- Close on click anywhere on the frame background
    frame:SetScript("OnMouseDown", function()
        frame:Hide()
    end)

    bugReportFrame = frame
    return frame
end

--- Shows the bug report popup with trace log and player info.
local function ShowBugReportPopup()
    local frame = GetBugReportFrame()
    local content = GetPlayerInfoString() .. "\n" .. string.rep("-", 60) .. "\n" .. GetTraceLog()
    frame.originalText = content
    frame.editBox:SetText(content)
    frame.editBox:SetCursorPosition(0)
    frame:Show()
    frame.editBox:HighlightText()
end

function EnhancedCooldownManager:SafeGetDebugValue(v)
    if v == nil then
        return "<nil>"
    end

    -- Secret values: check for secret scalar first, then secret table
    if type(issecretvalue) == "function" and issecretvalue(v) then
        if type(canaccessvalue) == "function" and canaccessvalue(v) then
            return "s|" .. tostring(v)
        end
        return "<secret>"
    end

    if type(issecrettable) == "function" and issecrettable(v) then
        if type(canaccesstable) == "function" and canaccesstable(v) then
            return "s|<table>"
        end
        return "<secrettable>"
    end

    if type(v) == "table" then
        return "<table>"
    end

    return tostring(v)
end

--- Buffers a debug message when debug mode is enabled.
---@param ... any
function EnhancedCooldownManager:DebugPrint(...)
    if not self.db or not self.db.profile or not self.db.profile.debug then
        return
    end

    local n = select("#", ...)
    if n <= 0 then
        return
    end

    local args = {}
    for i = 1, n do
        args[i] = self:SafeGetDebugValue(select(i, ...))
    end

    AddToTraceLog(table.concat(args, " "))
end

function EnhancedCooldownManager:Warning(...)
    PrintColored(self, "|cffbbcccc", ...)
end

--- Shows a confirmation popup and reloads the UI on accept.
--- ReloadUI is blocked in combat.
---@param text string Popup message.
---@param onAccept fun()|nil Optional accept callback (runs before ReloadUI).
---@param onCancel fun()|nil Optional cancel callback.
function EnhancedCooldownManager:ConfirmReloadUI(text, onAccept, onCancel)
    local okCombat, inCombat = pcall(InCombatLockdown)
    if okCombat and inCombat then
        self:Print("Cannot reload the UI right now: UI reload is blocked during combat.")
        return
    end

    local dialogs = rawget(_G, "StaticPopupDialogs")
    local show = rawget(_G, "StaticPopup_Show")
    if not dialogs or not show then
        self:Print("Unable to show confirmation dialog (StaticPopup API unavailable).")
        return
    end

    if not dialogs[POPUP_CONFIRM_RELOAD_UI] then
        dialogs[POPUP_CONFIRM_RELOAD_UI] = {
            text = "Reload the UI?",
            button1 = rawget(_G, "YES") or "Yes",
            button2 = rawget(_G, "NO") or "No",
            OnAccept = function(_, data)
                if data and data.onAccept then
                    data.onAccept()
                end
                pcall(rawget(_G, "ReloadUI"))
            end,
            OnCancel = function(_, data)
                if data and data.onCancel then
                    data.onCancel()
                end
            end,
            timeout = 0,
            whileDead = 1,
            hideOnEscape = 1,
            preferredIndex = 3,
        }
    end

    -- Update the text per-call.
    dialogs[POPUP_CONFIRM_RELOAD_UI].text = text or "Reload the UI?"
    show(POPUP_CONFIRM_RELOAD_UI, nil, nil, { onAccept = onAccept, onCancel = onCancel })
end

--- Prompts the user to confirm disabling ECM and reloading the UI.
---
--- Notes:
--- - This does NOT disable the addon in the AddOns list; it flips ECM's internal master toggle.
--- - Reloading is required to fully undo all hooks/styling (especially BuffBars reskins).
--- - ReloadUI is blocked in combat.
---@param onCancel fun()|nil Called if the user cancels (e.g. to refresh options UI state).
function EnhancedCooldownManager:ConfirmDisableAndReload(onCancel)
    self:ConfirmReloadUI(
        "Disable Enhanced Cooldown Manager and reload the UI?",
        function()
            local addon = ns and ns.Addon
            if not addon or not addon.db or not addon.db.profile then
                return
            end

            addon.db.profile.enabled = false

            -- Best-effort: stop modules before reload.
            local powerBars = addon.PowerBars
            local segmentBar = addon.SegmentBar
            if powerBars then pcall(powerBars.Disable, powerBars) end
            if segmentBar then pcall(segmentBar.Disable, segmentBar) end
        end,
        onCancel
    )
end

--- Handles slash command input for toggling ECM bars.
---@param input string|nil
function EnhancedCooldownManager:ChatCommand(input)
    input = (tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")):lower()

    local cmd, arg = input:match("^(%S+)%s*(.-)$")
    cmd = cmd or ""
    arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")

    if cmd == "" or cmd == "help" then
        self:Print("Commands: /ecm on|off|toggle | /ecm debug [on|off|toggle] | /ecm bug | /ecm options")
        return
    end

    if cmd == "bug" then
        local profile = self.db and self.db.profile
        if not profile or not profile.debug then
            self:Print("Debug mode must be enabled to use /ecm bug. Use /ecm debug on and then reproduce the issue to collect logs.")
            return
        end
        ShowBugReportPopup()
        return
    end

    if cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        local optionsModule = self:GetModule("Options", true)
        if optionsModule and optionsModule.OpenOptions then
            optionsModule:OpenOptions()
        else
            Settings.OpenToCategory("Enhanced Cooldown Manager")
        end
        return
    end

    local profile = self.db and self.db.profile
    if not profile then
        return
    end

    local powerBars = self.PowerBars
    local segmentBar = self.SegmentBar
    assert(powerBars, "ECM: PowerBars module missing")
    assert(segmentBar, "ECM: SegmentBar module missing")

    if cmd == "debug" then
        if arg == "" or arg == "toggle" then
            profile.debug = not profile.debug
        elseif arg == "on" then
            profile.debug = true
        elseif arg == "off" then
            profile.debug = false
        else
            self:Print("Usage: /ecm debug [on|off|toggle]")
            return
        end

        self:Print("Debug:", profile.debug and "ON" or "OFF")
        return
    end

    if cmd == "on" then
        profile.enabled = true
        powerBars:Refresh()
        segmentBar:Refresh()
    elseif cmd == "off" then
        self:ConfirmDisableAndReload()
        return
    elseif cmd == "toggle" then
        if profile.enabled then
            self:ConfirmDisableAndReload()
            return
        end

        profile.enabled = true
        powerBars:Refresh()
        segmentBar:Refresh()
    else
        self:Print("Unknown command. Use /ecm help")
        return
    end

    self:Print("Enabled:", profile.enabled and "ON" or "OFF")
end

--- Initializes saved variables, runs migrations, and registers slash commands.
function EnhancedCooldownManager:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("EnhancedCooldownManagerDB", defaults, true)

    -- Register bundled font with LibSharedMedia if present.
    if LSM and LSM.Register then
        pcall(LSM.Register, LSM, "font", "Expressway",
        "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf")
    end

    -- Select default texture from priority list on first load
    if self.db.profile.global.texture == nil then
        self.db.profile.global.texture = GetDefaultTexture()
    end

    self:RegisterChatCommand("enhancedcooldownmanager", "ChatCommand")
    self:RegisterChatCommand("ecm", "ChatCommand")
end

--- Enables the addon and ensures Blizzard's cooldown viewer is turned on.
function EnhancedCooldownManager:OnEnable()
    pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")

    -- AceAddon enables modules automatically; ResourceBars registers events in its OnEnable.
    local gradientName = ns.SparkleUtil.GradientText("EnhancedCooldownManager")
    print(gradientName .. ": Thank you for helping me launch this addon. <3 If you encounter issues, please type |cffffcc00/ecm bug|r to collect information for bug reports.")
end
