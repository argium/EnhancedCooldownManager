-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...

local ECM = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.Addon = ECM
local Util = ns.Util
local LSM = LibStub("LibSharedMedia-3.0", true)

local POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI"
local POPUP_EXPORT_PROFILE = "ECM_EXPORT_PROFILE"
local POPUP_IMPORT_PROFILE = "ECM_IMPORT_PROFILE"

assert(ns.defaults, "Defaults.lua must be loaded before ECM.lua")
assert(ns.AddToTraceLog and ns.GetTraceLog, "TraceLog.lua must be loaded before ECM.lua")
assert(ns.ShowBugReportPopup, "BugReports.lua must be loaded before ECM.lua")

--- Shows a confirmation popup and reloads the UI on accept.
--- ReloadUI is blocked in combat.
---@param text string
---@param onAccept fun()|nil
---@param onCancel fun()|nil
function ECM:ConfirmReloadUI(text, onAccept, onCancel)
    if InCombatLockdown() then
        Util.Print("Cannot reload the UI right now: UI reload is blocked during combat.")
        return
    end

    if not StaticPopupDialogs or not StaticPopup_Show then
        Util.Print("Unable to show confirmation dialog (StaticPopup API unavailable).")
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
---@param dialog table
---@return EditBox editBox
local function GetDialogEditBox(dialog)
    return dialog.editBox or dialog:GetEditBox()
end

--- Creates or retrieves a StaticPopup dialog with common settings for editbox dialogs.
---@param key string
---@param config table
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
---@param exportString string
function ECM:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        Util.Print("Invalid export string provided")
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
function ECM:ShowImportDialog()
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
            ECM:Print("Import cancelled: no string provided")
            return
        end

        -- Validate first WITHOUT applying
        local data, errorMsg = ns.ImportExport.ValidateImportString(input)
        if not data then
            ECM:Print("Import failed: " .. (errorMsg or "unknown error"))
            return
        end

        local versionStr = data.metadata and data.metadata.addonVersion or "unknown"
        local confirmText = string.format(
            "Import profile settings (exported from v%s)?\n\nThis will replace your current profile and reload the UI.",
            versionStr
        )

        -- Only apply the import AFTER user confirms reload
        ECM:ConfirmReloadUI(confirmText, function()
            local success, applyErr = ns.ImportExport.ApplyImportData(data)
            if not success then
                ECM:Print("Import apply failed: " .. (applyErr or "unknown error"))
            end
        end, nil)
    end

    StaticPopup_Show(POPUP_IMPORT_PROFILE)
end

--- Parses on/off/toggle argument and returns the new boolean value.
---@param arg string
---@param current boolean
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
function ECM:ChatCommand(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "help" then
        Util.Print("Commands: /ecm on|off|toggle | /ecm debug [on|off|toggle] | /ecm bug | /ecm options")
        return
    end

    if cmd == "bug" then
        local profile = self.db and self.db.profile
        if not profile or not profile.debug then
            Util.Print("Debug mode must be enabled to use /ecm bug. Use /ecm debug on first.")
            return
        end
        ns.ShowBugReportPopup()
        return
    end

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        if InCombatLockdown() then
            Util.Print("Options cannot be opened during combat. They will open when combat ends.")
            if not self._openOptionsAfterCombat then
                self._openOptionsAfterCombat = true
                self:RegisterEvent("PLAYER_REGEN_ENABLED", "HandleOpenOptionsAfterCombat")
            end
            return
        end

        local optionsModule = self:GetModule("Options", true)
        if optionsModule then
            optionsModule:OpenOptions()
        end
        return
    end

    local profile = self.db and self.db.profile
    if not profile then
        return
    end

    if cmd == "debug" then
        local newVal, err = ParseToggleArg(arg, profile.debug)
        if err then
            Util.Print(err)
            return
        end
        profile.debug = newVal
        Util.Print("Debug:", profile.debug and "ON" or "OFF")
        return
    end

    Util.Print("Unknown command. Use /ecm help")
end

function ECM:HandleOpenOptionsAfterCombat()
    if not self._openOptionsAfterCombat then
        return
    end

    self._openOptionsAfterCombat = nil
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")

    local optionsModule = self:GetModule("Options", true)
    if optionsModule then
        optionsModule:OpenOptions()
    end
end

--- Returns true when the color array matches the expected RGBA values.
---@param color number[]|nil
---@param r number
---@param g number
---@param b number
---@param a number|nil
---@return boolean
local function IsColorMatch(color, r, g, b, a)
    if type(color) ~= "table" then
        return false
    end

    return color[1] == r and color[2] == g and color[3] == b and color[4] == a
end

--- Initializes saved variables, runs migrations, and registers slash commands.
--- Runs profile migrations for schema version upgrades.
--- Each migration is gated by schemaVersion to ensure it only runs once.
---@param profile table The profile to migrate
function ECM:RunMigrations(profile)
    -- Migration: buffBarColors -> buffBars.colors (schema 2 -> 3)
    if profile.schemaVersion < 3 then
        if profile.buffBarColors then
            Util.Log("Migration", "Migrating buffBarColors to buffBars.colors")

            profile.buffBars = profile.buffBars or {}
            profile.buffBars.colors = profile.buffBars.colors or {}

            local src = profile.buffBarColors
            local dst = profile.buffBars.colors

            dst.perBar = dst.perBar or src.colors or {}
            dst.cache = dst.cache or src.cache or {}
            dst.defaultColor = dst.defaultColor or src.defaultColor
            dst.selectedPalette = dst.selectedPalette or src.selectedPalette

            profile.buffBarColors = nil
        end

        -- Migration: colors.colors -> colors.perBar (rename within buffBars.colors)
        local colorsConfig = profile.buffBars and profile.buffBars.colors
        if colorsConfig and colorsConfig.colors and not colorsConfig.perBar then
            Util.Log("Migration", "Renaming buffBars.colors.colors to buffBars.colors.perBar")
            colorsConfig.perBar = colorsConfig.colors
            colorsConfig.colors = nil
        end

        profile.schemaVersion = 3
    end

    if profile.schemaVersion < 4 then
        -- Migration: powerBarTicks.defaultColor -> bold semi-transparent white (schema 3 -> 4)
        local ticksCfg = profile.powerBarTicks
        if ticksCfg and IsColorMatch(ticksCfg.defaultColor, 0, 0, 0, 0.5) then
            ticksCfg.defaultColor = { 1, 1, 1, 0.8 }
        end

        -- Migration: demon hunter souls default color update
        local resourceCfg = profile.resourceBar
        local colors = resourceCfg and resourceCfg.colors
        local soulsColor = colors and colors.souls
        if IsColorMatch(soulsColor, 0.46, 0.98, 1.00, nil) then
            colors.souls = { 0.259, 0.6, 0.91 }
        end

        -- Migration: powerBarTicks -> powerBar.ticks
        if profile.powerBarTicks then
            profile.powerBar = profile.powerBar or {}
            if not profile.powerBar.ticks then
                profile.powerBar.ticks = profile.powerBarTicks
            end
            profile.powerBarTicks = nil
        end

        profile.schemaVersion = 4
    end
end

function ECM:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("EnhancedCooldownManagerDB", ns.defaults, true)

    local profile = self.db and self.db.profile
    if profile then
        self:RunMigrations(profile)
    end

    -- Register bundled font with LibSharedMedia if present.
    if LSM and LSM.Register then
        pcall(LSM.Register, LSM, "font", "Expressway",
            "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf")
    end

    self:RegisterChatCommand("enhancedcooldownmanager", "ChatCommand")
    self:RegisterChatCommand("ecm", "ChatCommand")
end

--- Enables the addon and ensures Blizzard's cooldown viewer is turned on.
function ECM:OnEnable()
    pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")

    local moduleOrder = {
        "ViewerHook",
        "PowerBar",
        "ResourceBar",
        "RuneBar",
        "BuffBars",
    }

    for _, moduleName in ipairs(moduleOrder) do
        local module = self:GetModule(moduleName, true)
        assert(module, "Module not found: " .. moduleName)
        if not module:IsEnabled() then
            self:EnableModule(moduleName)
        end
    end
end
