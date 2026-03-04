-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
ECM = ECM or {}

local mod = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.Addon = mod
local LSM = LibStub("LibSharedMedia-3.0", true)

local POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI"
local POPUP_EXPORT_PROFILE = "ECM_EXPORT_PROFILE"
local POPUP_IMPORT_PROFILE = "ECM_IMPORT_PROFILE"

assert(ECM.defaults, "ECM_Defaults.lua must be loaded before ECM.lua")
assert(ECM.Constants, "ECM_Constants.lua must be loaded before ECM.lua")
assert(ECM.Migration, "Migration.lua must be loaded before ECM.lua")

local function isDebugEnabled()
    return ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.global.debug
end

local function safeStrTostring(x)
    if x == nil then
        return "nil"
    elseif issecretvalue(x) then
        return "[secret]"
    else
        return tostring(x)
    end
end

local function safeTableTostring(tbl, depth, seen)
    if issecrettable(tbl) then
        return "[secrettable]"
    end

    if seen[tbl] then
        return "<cycle>"
    end

    if depth >= 3 then
        return "{...}"
    end

    seen[tbl] = true

    local ok, pairsOrErr = pcall(function()
        local parts = {}
        local count = 0

        for k, x in pairs(tbl) do
            count = count + 1
            if count > 25 then
                parts[#parts + 1] = "..."
                break
            end

            local keyStr = issecretvalue(k) and "[secret]" or tostring(k)
            local valueStr = type(x) == "table" and safeTableTostring(x, depth + 1, seen) or safeStrTostring(x)
            parts[#parts + 1] = keyStr .. "=" .. valueStr
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end)

    seen[tbl] = nil

    if not ok then
        return "<table_error>"
    end

    return pairsOrErr
end

local function getLsmMedia(mediaType, key)
    if LSM and key then
        return LSM:Fetch(mediaType, key, true)
    end
end

function ECM.ToString(v)
    if type(v) == "table" then
        return safeTableTostring(v, 0, {})
    end
    return safeStrTostring(v)
end

function ECM.GetTexture(texture)
    if texture then
        local fetched = getLsmMedia("statusbar", texture)
        if fetched then
            return fetched
        end

        if texture:find("\\") then
            return texture
        end
    end

    return getLsmMedia("statusbar", "Blizzard") or ECM.Constants.DEFAULT_STATUSBAR_TEXTURE
end

function ECM.DebugAssert(condition, message, data)
    if not isDebugEnabled() then
        return
    end

    if data and not condition and DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, data, "|cff" .. ECM.Constants.DEBUG_COLOR .. "[ASSERT]|r " .. message)
    end
    assert(condition, message)
end

function ECM.ApplyFont(fontString, globalConfig, moduleConfig)
    local config = globalConfig or (ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.global)
    local useModuleOverride = moduleConfig and moduleConfig.overrideFont == true
    local fontPath = getLsmMedia("font", (useModuleOverride and moduleConfig.font) or (config and config.font)) or ECM.Constants.DEFAULT_FONT
    local fontSize = (useModuleOverride and moduleConfig.fontSize) or (config and config.fontSize) or 11
    local fontOutline = (config and config.fontOutline)

    if fontOutline == "NONE" then
        fontOutline = ""
    end

    local hasShadow = config and config.fontShadow

    ECM.DebugAssert(fontPath, "Font path cannot be nil")
    ECM.DebugAssert(fontSize, "Font size cannot be nil")
    ECM.DebugAssert(fontOutline, "Font outline cannot be nil")

    fontString:SetFont(fontPath, fontSize, fontOutline)

    if hasShadow then
        fontString:SetShadowColor(0, 0, 0, 1)
        fontString:SetShadowOffset(1, -1)
    else
        fontString:SetShadowOffset(0, 0)
    end
end

function ECM.PixelSnap(v)
    local scale = UIParent:GetEffectiveScale()
    local snapped = math.floor(((tonumber(v) or 0) * scale) + 0.5)
    return snapped / scale
end

function ECM.CloneValue(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for k, v in pairs(value) do
        copy[k] = ECM.CloneValue(v)
    end
    return copy
end

function ECM.Print(...)
    local prefix = ColorUtil.Sparkle(ECM.Constants.ADDON_ABRV .. ":")
    local args = { ... }
    for i = 1, #args do
        args[i] = tostring(args[i])
    end
    local message = table.concat(args, " ")
    print(prefix .. " " .. message)
end

function ECM.Log(module, message, data)
    if not isDebugEnabled() then
        return
    end

    local prefix = "[" .. ECM.Constants.ADDON_ABRV .. (module and (" " .. module) or "") .. "]"

    if DevTool and DevTool.AddData then
        local payload = {
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = ECM.ToString(data),
        }
        pcall(DevTool.AddData, DevTool, payload, "|cff" .. ECM.Constants.DEBUG_COLOR .. prefix .. "|r " .. message)
    end

    print("|cff" .. ECM.Constants.DEBUG_COLOR .. prefix .. "|r " .. message)
end

local function registerAddonCompartmentEntry()
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
        ECM.Print("Cannot reload the UI right now: UI reload is blocked during combat.")
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

--- Creates or retrieves a StaticPopup dialog with common settings for editbox dialogs.
---@param key string
---@param config table
local function ensureEditBoxDialog(key, config)
    if StaticPopupDialogs[key] then
        return
    end

    StaticPopupDialogs[key] = {
        hasEditBox = true,
        editBoxWidth = 350,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    for k, v in pairs(config) do
        StaticPopupDialogs[key][k] = v
    end
end

--- Shows a dialog with the export string for copying.
---@param exportString string
function mod:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        ECM.Print("Invalid export string provided")
        return
    end

    ensureEditBoxDialog(POPUP_EXPORT_PROFILE, {
        text = "Press Ctrl+C to copy the export string:",
        button1 = CLOSE or "Close",
    })

    StaticPopupDialogs[POPUP_EXPORT_PROFILE].OnShow = function(self)
        self:SetFrameStrata("TOOLTIP")
        local editBox = self.editBox or self:GetEditBox()
        editBox:SetText(exportString)
        editBox:HighlightText()
        editBox:SetFocus()
    end

    StaticPopup_Show(POPUP_EXPORT_PROFILE)
end

--- Shows a dialog to paste an import string and handles the import process.
function mod:ShowImportDialog()
    ensureEditBoxDialog(POPUP_IMPORT_PROFILE, {
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
        local editBox = self.editBox or self:GetEditBox()
        editBox:SetText("")
        editBox:SetFocus()
    end

    StaticPopupDialogs[POPUP_IMPORT_PROFILE].OnAccept = function(self)
        local editBox = self.editBox or self:GetEditBox()
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

--- Handles slash command input.
---@param input string|nil
function mod:ChatCommand(input)
    local cmd, arg = (input or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")

    if cmd == "help" or (cmd == "migration" and arg ~= "" and arg ~= "log") then
        ECM.Print("/ecm debug [on|off||toggle] - toggle debug mode (logs detailed info to the chat frame)")
        ECM.Print("/ecm help - show this message")
        ECM.Print("/ecm options|config|settings|o - open the options menu")
        ECM.Print("/ecm rl||reload||refresh - refresh and reapply layout for all modules")
        ECM.Print("/ecm migrationlog - show the settings migration log")
        return
    end

    if cmd == "rl" or cmd == "reload" or cmd == "refresh" then
        ECM.ScheduleLayoutUpdate(0, "ChatCommand")
        ECM.Print("Refreshing all modules.")
        return
    end

    if cmd == "migration" then
        ECM.Migration.PrintLog()
        return
    end

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        if InCombatLockdown() then
            ECM.Print("Options cannot be opened during combat. They will open when combat ends.")
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
        local newVal
        if arg == "" or arg == "toggle" then
            newVal = not profile.global.debug
        elseif arg == "on" then
            newVal = true
        elseif arg == "off" then
            newVal = false
        else
            ECM.Print("Usage: expected on|off|toggle")
            return
        end
        profile.global.debug = newVal
        ECM.Print("Debug:", profile.global.debug and "ON" or "OFF")
        return
    end
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
    local module = self[moduleName] or ECM[moduleName]
    if not module and not silent then
        ECM.Print("Module not found:", moduleName)
    end
    return module
end

function mod:OnInitialize()
    -- Set up versioned SV store and point the active key at the current version.
    ECM.Migration.PrepareDatabase()

    self.db = LibStub("AceDB-3.0"):New(ECM.Constants.ACTIVE_SV_KEY, ECM.defaults, true)

    local profile = self.db and self.db.profile
    ECM.Log("Initialize", "Database loaded", {
        schemaVersion = profile and profile.schemaVersion or "nil",
        currentSchemaVersion = ECM.Constants.CURRENT_SCHEMA_VERSION
    })

    if profile and profile.schemaVersion and profile.schemaVersion < ECM.Constants.CURRENT_SCHEMA_VERSION then
        ECM.Migration.Run(profile)
    end

    ECM.Migration.FlushLog()

    -- Register bundled font with LibSharedMedia if present.
    if LSM then
        pcall(LSM.Register, LSM, "font", "Expressway",
            "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf")
    end

    self:RegisterChatCommand("enhancedcooldownmanager", "ChatCommand")
    self:RegisterChatCommand("ecm", "ChatCommand")
end

--- Enables the addon and ensures Blizzard's cooldown viewer is turned on.
function mod:OnEnable()
    pcall(C_CVar.SetCVar, "cooldownViewerEnabled", "1")
    registerAddonCompartmentEntry()
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
