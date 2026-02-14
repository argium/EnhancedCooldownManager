-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...

local mod = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.Addon = mod
local LSM = LibStub("LibSharedMedia-3.0", true)

local POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI"
local POPUP_EXPORT_PROFILE = "ECM_EXPORT_PROFILE"
local POPUP_IMPORT_PROFILE = "ECM_IMPORT_PROFILE"

assert(ECM.defaults, "Defaults.lua must be loaded before ECM.lua")
assert(ECM.Constants, "Constants.lua must be loaded before ECM.lua")
assert(ECM.Migration, "Migration.lua must be loaded before ECM.lua")

local function RegisterAddonCompartmentEntry()
    if mod._addonCompartmentRegistered then
        return
    end

    if not (AddonCompartmentFrame and type(AddonCompartmentFrame.RegisterAddon) == "function") then
        return
    end

    local text = ColorUtil.Sparkle(ECM.Constants.ADDON_NAME)
    local ok = pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
        text = text,
        icon = ECM.Constants.ADDON_ICON_TEXTURE,
        notCheckable = true,
        func = function()
            mod:ChatCommand("options")
        end,
    })

    if ok then
        mod._addonCompartmentRegistered = true
    end
end

--- Shows a confirmation popup and reloads the UI on accept.
--- ReloadUI is blocked in combat.
---@param text string
---@param onAccept fun()|nil
---@param onCancel fun()|nil
function mod:ConfirmReloadUI(text, onAccept, onCancel)
    if InCombatLockdown() then
        ECM_print("Cannot reload the UI right now: UI reload is blocked during combat.")
        return
    end

    if not StaticPopupDialogs or not StaticPopup_Show then
        ECM_print("Unable to show confirmation dialog (StaticPopup API unavailable).")
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
function mod:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        ECM_print("Invalid export string provided")
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
function mod:ShowImportDialog()
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

        if strtrim(input) == "" then
            mod:Print("Import cancelled: no string provided")
            return
        end

        -- Validate first WITHOUT applying
        local data, errorMsg = ECM.ImportExport.ValidateImportString(input)
        if not data then
            mod:Print("Import failed: " .. (errorMsg or "unknown error"))
            return
        end

        local versionStr = data.metadata and data.metadata.addonVersion or "unknown"
        local confirmText = string.format(
            "Import profile settings (exported from v%s)?\n\nThis will replace your current profile and reload the UI.",
            versionStr
        )

        -- Only apply the import AFTER user confirms reload
        mod:ConfirmReloadUI(confirmText, function()
            local success, applyErr = ECM.ImportExport.ApplyImportData(data)
            if not success then
                mod:Print("Import apply failed: " .. (applyErr or "unknown error"))
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

--- Handles slash command input.
---@param input string|nil
function mod:ChatCommand(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "help" then
        ECM_print("Commands: /ecm debug [on|off|toggle] | /ecm options")
        return
    end

    if cmd == "rl" or cmd == "reload" or cmd == "refresh" then
        ECM.ScheduleLayoutUpdate(0, "ChatCommand")
        ECM_print("Refreshing all modules.")
        return
    end

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        if InCombatLockdown() then
            ECM_print("Options cannot be opened during combat. They will open when combat ends.")
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
            ECM_print(err)
            return
        end
        profile.debug = newVal
        ECM_print("Debug:", profile.debug and "ON" or "OFF")
        return
    end

    ECM_print("Unknown command. Use /ecm help")
end

function mod:HandleOpenOptionsAfterCombat()
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

function mod:GetECMModule(moduleName, silent)
    local module = self[moduleName] or ECM[moduleName] or nil
    if not module and not silent then
        ECM_print("Module not found:", moduleName)
    end
    return module
end

function mod:OnInitialize()
    -- Set up versioned SV store and point the active key at the current version.
    ECM.Migration.PrepareDatabase()

    self.db = LibStub("AceDB-3.0"):New(ECM.Constants.ACTIVE_SV_KEY, ECM.defaults, true)

    local profile = self.db and self.db.profile
    ECM_log(ECM.Constants.SYS.Core, nil, "Initialize", {
        schemaVersion = profile and profile.schemaVersion or "nil",
        currentSchemaVersion = ECM.Constants.CURRENT_SCHEMA_VERSION
    })

    if profile and profile.schemaVersion and profile.schemaVersion < ECM.Constants.CURRENT_SCHEMA_VERSION then
        ECM.Migration.Run(profile)
    end

    ECM.Migration.FlushLog()

    -- Register bundled font with LibSharedMedia if present.
    if LSM and LSM.Register then
        pcall(LSM.Register, LSM, "font", "Expressway",
            "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf")
    end

    self:RegisterChatCommand("enhancedcooldownmanager", "ChatCommand")
    self:RegisterChatCommand("ecm", "ChatCommand")
end

--- Enables the addon and ensures Blizzard's cooldown viewer is turned on.
function mod:OnEnable()
    pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")
    RegisterAddonCompartmentEntry()
    local profile = self.db and self.db.profile

    local moduleOrder = {
        ECM.Constants.POWERBAR,
        ECM.Constants.RESOURCEBAR,
        ECM.Constants.RUNEBAR,
        ECM.Constants.BUFFBARS,
        ECM.Constants.ITEMICONS,
    }

    for _, moduleName in ipairs(moduleOrder) do
        local module = self:GetECMModule(moduleName)
        assert(module, "Module not found: " .. moduleName)

        local configKey = moduleName:sub(1, 1):lower() .. moduleName:sub(2)
        local moduleConfig = profile and profile[configKey]
        local shouldEnable = (not moduleConfig) or (moduleConfig.enabled ~= false)
        ECM.OptionUtil.SetModuleEnabled(moduleName, shouldEnable)
    end
end
