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
---@field demonHunterSoulsMax number
---@field colors table<ECM_ResourceType, number[]>

---@class ECM_RuneBarConfig : ECM_BarConfigBase
---@field max number
---@field colorDkRunes number[]

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

---@class ECM_BarCacheEntry
---@field spellName string|nil Display name (safe string, not secret)
---@field lastSeen number Timestamp of last appearance

---@class ECM_BuffBarColorsConfig
---@field colors table<number, table<number, table<number, number[]>>> [classID][specID][barIndex] = {r, g, b}
---@field cache table<number, table<number, table<number, ECM_BarCacheEntry>>> [classID][specID][barIndex] = metadata
---@field defaultColor number[] Default RGB color for buff bars

---@class ECM_BuffBarsConfig
---@field autoPosition boolean When true, automatically position below other ECM bars
---@field barWidth number Width of buff bars when autoPosition is false
---@field showIcon boolean|nil When nil, defaults to showing the icon.
---@field showSpellName boolean|nil When nil, defaults to showing the spell name.
---@field showDuration boolean|nil When nil, defaults to showing the duration.
---@field dynamicBars ECM_DynamicBarConfig[]|nil Per-aura style overrides

---@class ECM_TickMark
---@field value number The resource value at which to display the tick
---@field color number[] RGBA color for this tick mark
---@field width number Width of the tick mark in pixels

---@class ECM_PowerBarTicksConfig
---@field mappings table<number, table<number, ECM_TickMark[]>> [classID][specID] = array of tick marks
---@field defaultColor number[] Default RGBA color for tick marks
---@field defaultWidth number Default width for tick marks

---@class ECM_CombatFadeConfig
---@field enabled boolean Master toggle for combat fade feature
---@field opacity number Opacity percentage (0-100) when faded out of combat
---@field exceptInInstance boolean When true, don't fade in raids, dungeons, battlegrounds, or PVP

---@class ECM_Profile
---@field hideWhenMounted number
---@field updateFrequency number
---@field schemaVersion number
---@field debug boolean
---@field offsetY number
---@field combatFade ECM_CombatFadeConfig
---@field global ECM_GlobalConfig
---@field powerBar ECM_PowerBarConfig
---@field segmentBar ECM_SegmentBarConfig
---@field runeBar ECM_RuneBarConfig
---@field powerTypeColors ECM_PowerTypeColorsConfig
---@field buffBars ECM_BuffBarsConfig
---@field buffBarColors ECM_BuffBarColorsConfig
---@field powerBarTicks ECM_PowerBarTicksConfig

-- END Configuration

local EnhancedCooldownManager = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.Addon = EnhancedCooldownManager

local LSM = LibStub("LibSharedMedia-3.0", true)

local POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI"
local POPUP_EXPORT_PROFILE = "ECM_EXPORT_PROFILE"
local POPUP_IMPORT_PROFILE = "ECM_IMPORT_PROFILE"

-- Priority list for default texture selection (first available wins)
local TEXTURE_PRIORITY = {
    -- "ElvUI Norm",
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
        debug = false,
        hideWhenMounted = true,
        updateFrequency = 0.04,
        schemaVersion = 1,
        offsetY = 4,
        width = {
            auto = true,
            value = 330,
            min = 300,
        },
        combatFade = {
            enabled = false,
            opacity = 50,
            exceptInInstance = true,
        },
        global = {
            barHeight = 22,
            barBgColor = { 0.08, 0.08, 0.08, 0.75 },
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
            demonHunterSoulsMax = 6,
            colors = {
                souls = { 0.46, 0.98, 1.00 },
                [Enum.PowerType.ComboPoints] = { 0.75, 0.15, 0.15 },
                [Enum.PowerType.Chi] = { 0.00, 1.00, 0.59 },
                [Enum.PowerType.HolyPower] = { 0.8863, 0.8235, 0.2392 },
                [Enum.PowerType.SoulShards] = { 0.58, 0.51, 0.79 },
                [Enum.PowerType.Essence] = { 0.20, 0.58, 0.50 }
            },
        },
        runeBar = {
            enabled = true,
            height = nil,
            texture = nil,
            bgColor = nil,
            max = 6,
            color = { 0.87, 0.10, 0.22 },
        },
        buffBars = {
            autoPosition = true,
            barWidth = 300,
            showIcon = false,
            showSpellName = true,
            showDuration = true,
            dynamicBars = {},
        },
        buffBarColors = {
            colors = {},
            cache = {},
            defaultColor = { 228 / 255, 233 / 255, 235 / 255 },
        },
        powerBarTicks = {
            mappings = {}, -- [classID][specID] = { { value = 50, color = {r,g,b,a}, width = 1 }, ... }
            defaultColor = { 0, 0, 0, 0.5 },
            defaultWidth = 1,
        },
        powerTypeColors = {
            [Enum.PowerType.Mana] = { 0.00, 0.00, 1.00 },
            [Enum.PowerType.Rage] = { 1.00, 0.00, 0.00 },
            [Enum.PowerType.Focus] = { 1.00, 0.57, 0.31 },
            [Enum.PowerType.Energy] = { 0.85, 0.65, 0.13 },
            [Enum.PowerType.RunicPower] = { 0.00, 0.82, 1.00 },
            [Enum.PowerType.LunarPower] = { 0.30, 0.52, 0.90 },
            [Enum.PowerType.Fury] = { 0.79, 0.26, 0.99 },
            [Enum.PowerType.Maelstrom] = { 0.00, 0.50, 1.00 },
            [Enum.PowerType.ArcaneCharges] = { 0.20, 0.60, 1.00 },
        },
    },
}

-- Export defaults for Options module to access
ns.defaults = defaults


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

    -- Handle Blizzard secret values
    if type(issecretvalue) == "function" and issecretvalue(v) then
        return (type(canaccessvalue) == "function" and canaccessvalue(v)) and ("s|" .. tostring(v)) or "<secret>"
    end
    if type(issecrettable) == "function" and issecrettable(v) then
        return (type(canaccesstable) == "function" and canaccesstable(v)) and "s|<table>" or "<secrettable>"
    end

    return type(v) == "table" and "<table>" or tostring(v)
end

--- Buffers a debug message when debug mode is enabled.
---@param ... any
function EnhancedCooldownManager:DebugPrint(...)
    local profile = self.db and self.db.profile
    if not profile or not profile.debug or select("#", ...) == 0 then
        return
    end

    local args = {}
    for i = 1, select("#", ...) do
        args[i] = self:SafeGetDebugValue(select(i, ...))
    end
    AddToTraceLog(table.concat(args, " "))
end

function EnhancedCooldownManager:Warning(...)
    local args = {}
    for i = 1, select("#", ...) do
        args[i] = self:SafeGetDebugValue(select(i, ...))
    end
    if #args > 0 then
        print("|cffbbcccc" .. table.concat(args, " ") .. "|r")
    end
end

--- Shows a confirmation popup and reloads the UI on accept.
--- ReloadUI is blocked in combat.
---@param text string Popup message.
---@param onAccept fun()|nil Optional accept callback (runs before ReloadUI).
---@param onCancel fun()|nil Optional cancel callback.
function EnhancedCooldownManager:ConfirmReloadUI(text, onAccept, onCancel)
    if InCombatLockdown() then
        self:Print("Cannot reload the UI right now: UI reload is blocked during combat.")
        return
    end

    if not StaticPopupDialogs or not StaticPopup_Show then
        self:Print("Unable to show confirmation dialog (StaticPopup API unavailable).")
        return
    end

    if not StaticPopupDialogs[POPUP_CONFIRM_RELOAD_UI] then
        StaticPopupDialogs[POPUP_CONFIRM_RELOAD_UI] = {
            text = "Reload the UI?",
            button1 = YES or "Yes",
            button2 = NO or "No",
            OnAccept = function(_, data)
                if data and data.onAccept then
                    data.onAccept()
                end
                ReloadUI()
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

    StaticPopupDialogs[POPUP_CONFIRM_RELOAD_UI].text = text or "Reload the UI?"
    StaticPopup_Show(POPUP_CONFIRM_RELOAD_UI, nil, nil, { onAccept = onAccept, onCancel = onCancel })
end

--- Safely gets the edit box from a StaticPopup dialog.
---@param dialog table The StaticPopup dialog frame
---@return EditBox editBox The edit box widget
local function GetDialogEditBox(dialog)
    return dialog.editBox or dialog:GetEditBox()
end

--- Creates or retrieves a StaticPopup dialog with common settings for editbox dialogs.
---@param key string The dialog key (e.g., "ECM_EXPORT_PROFILE")
---@param config table Dialog-specific configuration overrides
local function EnsureEditBoxDialog(key, config)
    if StaticPopupDialogs[key] then
        return
    end

    local defaults = {
        hasEditBox = true,
        editBoxWidth = 350,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    -- Merge config into defaults
    local dialog = {}
    for k, v in pairs(defaults) do
        dialog[k] = v
    end
    for k, v in pairs(config or {}) do
        dialog[k] = v
    end

    StaticPopupDialogs[key] = dialog
end

--- Shows a dialog with the export string for copying.
---@param exportString string The export string to display
function EnhancedCooldownManager:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        self:Print("Invalid export string provided")
        return
    end

    EnsureEditBoxDialog(POPUP_EXPORT_PROFILE, {
        text = "Press Ctrl+C to copy the export string:",
        button1 = CLOSE or "Close",
    })

    StaticPopupDialogs[POPUP_EXPORT_PROFILE].OnShow = function(self)
        self:SetFrameStrata("TOOLTIP")
        local editBox = GetDialogEditBox(self)
        editBox:SetText(exportString)
        editBox:HighlightText()
        editBox:SetFocus()
    end

    StaticPopup_Show(POPUP_EXPORT_PROFILE)
end

--- Shows a dialog to paste an import string and handles the import process.
function EnhancedCooldownManager:ShowImportDialog()
    EnsureEditBoxDialog(POPUP_IMPORT_PROFILE, {
        text = "Paste your import string:",
        button1 = OKAY or "Import",
        button2 = CANCEL or "Cancel",
        EditBoxOnEnterPressed = function(editBox)
            local parent = editBox:GetParent()
            if parent and parent.button1 then
                parent.button1:Click()
            end
        end,
    })

    StaticPopupDialogs[POPUP_IMPORT_PROFILE].OnShow = function(self)
        self:SetFrameStrata("TOOLTIP")
        local editBox = GetDialogEditBox(self)
        editBox:SetText("")
        editBox:SetFocus()
    end

    StaticPopupDialogs[POPUP_IMPORT_PROFILE].OnAccept = function(self)
        local editBox = GetDialogEditBox(self)
        local input = editBox:GetText() or ""

        if input:trim() == "" then
            EnhancedCooldownManager:Print("Import cancelled: no string provided")
            return
        end

        -- Validate first WITHOUT applying (fixes critical bug)
        local data, errorMsg = ns.ImportExport.ValidateImportString(input)
        if not data then
            EnhancedCooldownManager:Print("Import failed: " .. (errorMsg or "unknown error"))
            return
        end

        local versionStr = data.metadata and data.metadata.addonVersion or "unknown"
        local confirmText = string.format(
            "Import profile settings (exported from v%s)?\n\nThis will replace your current profile and reload the UI.",
            versionStr
        )

        -- Only apply the import AFTER user confirms reload
        EnhancedCooldownManager:ConfirmReloadUI(confirmText, function()
            local success, applyErr = ns.ImportExport.ApplyImportData(data)
            if not success then
                EnhancedCooldownManager:Print("Import apply failed: " .. (applyErr or "unknown error"))
            end
        end, nil)
    end

    StaticPopup_Show(POPUP_IMPORT_PROFILE)
end

--- Parses on/off/toggle argument and returns the new boolean value.
---@param arg string The argument ("on", "off", "toggle", or "")
---@param current boolean The current value
---@return boolean|nil newValue, string|nil error
local function ParseToggleArg(arg, current)
    if arg == "" or arg == "toggle" then
        return not current, nil
    elseif arg == "on" then
        return true, nil
    elseif arg == "off" then
        return false, nil
    end
    return nil, "Usage: expected on|off|toggle"
end

--- Handles slash command input for toggling ECM bars.
---@param input string|nil
function EnhancedCooldownManager:ChatCommand(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "help" then
        self:Print("Commands: /ecm on|off|toggle | /ecm debug [on|off|toggle] | /ecm bug | /ecm options")
        return
    end

    if cmd == "bug" then
        local profile = self.db and self.db.profile
        if not profile or not profile.debug then
            self:Print("Debug mode must be enabled to use /ecm bug. Use /ecm debug on first.")
            return
        end
        ShowBugReportPopup()
        return
    end

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        local optionsModule = self:GetModule("Options", true)
        optionsModule:OpenOptions()
        return
    end

    local profile = self.db and self.db.profile
    if not profile then
        return
    end

    if cmd == "debug" then
        local newVal, err = ParseToggleArg(arg, profile.debug)
        if err then
            self:Print(err)
            return
        end
        profile.debug = newVal
        self:Print("Debug:", profile.debug and "ON" or "OFF")
        return
    end

    self:Print("Unknown command. Use /ecm help")
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
end
