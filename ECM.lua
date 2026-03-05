-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local ADDON_NAME, ns = ...
local mod = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceEvent-3.0", "AceConsole-3.0")
ns.Addon = mod
ECM = ECM or {}
assert(ECM.defaults, "ECM_Defaults.lua must be loaded before ECM.lua")
assert(ECM.Constants, "ECM_Constants.lua must be loaded before ECM.lua")
assert(ECM.Migration, "Migration.lua must be loaded before ECM.lua")

local LSM = LibStub("LibSharedMedia-3.0", true)
local POPUP_CONFIRM_RELOAD_UI = "ECM_CONFIRM_RELOAD_UI"
local C = ECM.Constants

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

    return getLsmMedia("statusbar", "Blizzard") or C.DEFAULT_STATUSBAR_TEXTURE
end

function ECM.DebugAssert(condition, message, data)
    if not isDebugEnabled() then
        return
    end

    if data and not condition and DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, data, "|cff" .. C.DEBUG_COLOR .. "[ASSERT]|r " .. message)
    end
    assert(condition, message)
end

function ECM.ApplyFont(fontString, globalConfig, moduleConfig)
    local config = globalConfig or (ns.Addon and ns.Addon.db and ns.Addon.db.profile and ns.Addon.db.profile.global)
    local useModuleOverride = moduleConfig and moduleConfig.overrideFont == true
    local fontPath = getLsmMedia("font", (useModuleOverride and moduleConfig.font) or (config and config.font)) or C.DEFAULT_FONT
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
    local prefix = ColorUtil.Sparkle(C.ADDON_ABRV .. ":")
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

    local prefix = "[" .. C.ADDON_ABRV .. (module and (" " .. module) or "") .. "]"

    if DevTool and DevTool.AddData then
        local payload = {
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = ECM.ToString(data),
        }
        pcall(DevTool.AddData, DevTool, payload, "|cff" .. C.DEBUG_COLOR .. prefix .. "|r " .. message)
    end

    print("|cff" .. C.DEBUG_COLOR .. prefix .. "|r " .. message)
end

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
    PLAYER_ENTERING_WORLD = { delay = 0.4 },
    PLAYER_TARGET_CHANGED = { delay = 0 },
    PLAYER_REGEN_ENABLED = { delay = 0.1, combatChange = true },
    PLAYER_REGEN_DISABLED = { delay = 0, combatChange = true },
    ZONE_CHANGED_NEW_AREA = { delay = 0.1 },
    ZONE_CHANGED = { delay = 0.1 },
    ZONE_CHANGED_INDOORS = { delay = 0.1 },
    UPDATE_SHAPESHIFT_FORM = { delay = 0 },
}

local _modules = {}
local _globallyHidden = false
local _desiredAlpha = 1
local _inCombat = InCombatLockdown()
local _layoutPending = false
local _cooldownViewerSettingsHooked = false
local _hookedBlizzardFrames = {}

local _chainSet = {}
for _, name in ipairs(C.CHAIN_ORDER) do _chainSet[name] = true end

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
        ECM.Log(nil, "SetGloballyHidden " .. (hidden and "HIDDEN" or "VISIBLE") .. (reason and (" due to " .. reason) or ""))
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
    local globalConfig = mod.db and mod.db.profile and mod.db.profile.global
    if not globalConfig then
        return
    end

    -- Determine hidden state
    local hidden, reason = false, nil
    if not C_CVar.GetCVarBool("cooldownViewerEnabled") then
        hidden, reason = true, "cvar"
    elseif globalConfig.hideWhenMounted and (IsMounted() or UnitInVehicle("player")) then
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

            if not shouldSkipFade and hasLiveTarget and fadeConfig.exceptIfTargetCanBeAttacked and UnitCanAttack("player", "target") then
                shouldSkipFade = true
            end

            if not shouldSkipFade and hasLiveTarget and fadeConfig.exceptIfTargetCanBeHelped and UnitCanAssist("player", "target") then
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

local function updateAllLayouts(reason)
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

--- Schedules a layout update after a delay (debounced).
--- @param delay number Delay in seconds
--- @param reason string|nil The lifecycle reason (defaults to OPTION_CHANGED)
function ECM.ScheduleLayoutUpdate(delay, reason)
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

--- Registers a ModuleMixin to receive layout update events.
--- @param frame ModuleMixin The frame to register
function ECM.RegisterFrame(frame)
    assert(frame and type(frame) == "table" and frame.Name, "RegisterFrame: invalid module (missing Name)")
    assert(_modules[frame.Name] == nil, "registerFrame: frame with name '" .. frame.Name .. "' is already registered")
    _modules[frame.Name] = frame
    ECM.Log(nil, "Frame registered: " .. frame.Name)

    if _globallyHidden then
        frame:SetHidden(true)
    end
    if frame.InnerFrame then
        ECM.FrameUtil.LazySetAlpha(frame.InnerFrame, _desiredAlpha)
    end
end

--- Unregisters a ModuleMixin from layout update events.
--- @param frame ModuleMixin The frame to unregister
function ECM.UnregisterFrame(frame)
    if not frame or type(frame) ~= "table" then
        return
    end

    local name = frame.Name
    if not name or _modules[name] ~= frame then
        return
    end

    _modules[name] = nil

    if frame.InnerFrame then
        frame.InnerFrame:Hide()
    end

    ECM.Log(nil, "Frame unregistered: " .. name)
end

--- Registers layout events and starts event-driven state updates.
local function enableLayoutEvents()
    local eventFrame = CreateFrame("Frame")

    for eventName in pairs(LAYOUT_EVENTS) do
        eventFrame:RegisterEvent(eventName)
    end
    eventFrame:RegisterEvent("CVAR_UPDATE")

    eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
        hookCooldownViewerSettings()

        if (event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE") and arg1 ~= "player" then
            return
        end

        if event == "CVAR_UPDATE" then
            if arg1 == "cooldownViewerEnabled" then
                ECM.ScheduleLayoutUpdate(0, "CVAR_UPDATE:cooldownViewerEnabled")
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
        else
            updateFadeAndHiddenStates()
            updateAllLayouts(event)
        end
    end)

    -- Watchdog — catches cases where the game externally re-shows or resets alpha
    -- on Blizzard cooldown viewer frames between layout events.
    C_Timer.NewTicker(C.WATCHDOG_INTERVAL, function()
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


local function registerAddonCompartmentEntry()
    if mod._addonCompartmentRegistered then
        return
    end

    if not (AddonCompartmentFrame and type(AddonCompartmentFrame.RegisterAddon) == "function") then
        return
    end

    local text = ColorUtil.Sparkle(C.ADDON_NAME)
    local ok = pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
        text = text,
        icon = C.ADDON_ICON_TEXTURE,
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

local function createDialogFrame(name, titleText, explainText)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(C.DIALOG_FRAME_WIDTH, C.DIALOG_FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop(C.DIALOG_BACKDROP)
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:EnableMouse(true)
    f:Hide()
    tinsert(UISpecialFrames, name)

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText(titleText)

    local explain = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    explain:SetPoint("TOP", 0, -40)
    explain:SetPoint("LEFT", 24, 0)
    explain:SetPoint("RIGHT", -24, 0)
    explain:SetJustifyH("LEFT")
    explain:SetJustifyV("TOP")
    explain:SetText(explainText)

    local scroll = CreateFrame("Frame", nil, f, "ScrollingEditBoxTemplate")
    scroll.hideCharCount = true
    scroll.maxLetters = 0
    scroll:SetPoint("TOPLEFT", 16, -88)
    scroll:SetPoint("BOTTOMRIGHT", -16, 48)
    f.Scroll = scroll

    return f
end

local function addButton(parent, label, anchor, onClick)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(96, 22)
    btn:SetPoint(unpack(anchor))
    btn:SetText(label)
    btn:SetScript("OnClick", onClick)
    return btn
end

local exportFrame

--- Shows a dialog with the export string for copying.
---@param exportString string
function mod:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        ECM.Print("Invalid export string provided")
        return
    end

    if not exportFrame then
        exportFrame = createDialogFrame("ECMExportFrame", "Export Profile",
            "Press Ctrl+C to copy. The dialog will close automatically.")
        addButton(exportFrame, CLOSE, {"BOTTOMRIGHT", -16, 8}, function() exportFrame:Hide() end)

        -- Auto-close after Ctrl+C
        exportFrame.Scroll.ScrollBox.EditBox:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.1, function()
                    exportFrame:Hide()
                    ECM.Print("Import string copied to clipboard.")
                end)
            end
        end)
    end

    exportFrame:Show()
    local editBox = exportFrame.Scroll.ScrollBox.EditBox
    editBox:SetText(exportString)
    editBox:HighlightText()
    editBox:SetFocus()
end

local importFrame

--- Shows a dialog to paste an import string and handles the import process.
function mod:ShowImportDialog()
    if not importFrame then
        importFrame = createDialogFrame("ECMImportFrame", "Import Profile",
            "Paste your import string below and click Import.")

        local cancelBtn = addButton(importFrame, CANCEL, {"BOTTOMRIGHT", -16, 8}, function() importFrame:Hide() end)
        addButton(importFrame, OKAY, {"RIGHT", cancelBtn, "LEFT", -4, 0}, function()
            local input = importFrame.Scroll.ScrollBox.EditBox:GetText()

            if strtrim(input) == "" then
                mod:Print("Import cancelled: no string provided")
                return
            end

            local data, errorMsg = ECM.ImportExport.ValidateImportString(input)
            if not data then
                mod:Print("Import failed: " .. (errorMsg or "unknown error"))
                return
            end

            importFrame:Hide()

            local versionStr = data.metadata and data.metadata.addonVersion or "unknown"
            local confirmText = string.format(
                "Import profile settings (exported from v%s)?\n\nThis will replace your current profile and reload the UI.",
                versionStr
            )

            mod:ConfirmReloadUI(confirmText, function()
                local success, applyErr = ECM.ImportExport.ApplyImportData(data)
                if not success then
                    mod:Print("Import apply failed: " .. (applyErr or "unknown error"))
                end
            end, nil)
        end)
    end

    importFrame:Show()
    importFrame.Scroll.ScrollBox.EditBox:SetText("")
    importFrame.Scroll.ScrollBox.EditBox:SetFocus()
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

    self.db = LibStub("AceDB-3.0"):New(C.ACTIVE_SV_KEY, ECM.defaults, true)

    local profile = self.db and self.db.profile
    ECM.Log("Initialize", "Database loaded. Latest schema = " .. C.CURRENT_SCHEMA_VERSION .. ". Profile Schema = " .. (profile and profile.schemaVersion or "nil"))

    if profile and profile.schemaVersion and profile.schemaVersion < C.CURRENT_SCHEMA_VERSION then
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
        C.POWERBAR,
        C.RESOURCEBAR,
        C.RUNEBAR,
        C.BUFFBARS,
        C.ITEMICONS,
    }

    for _, moduleName in ipairs(moduleOrder) do
        local module = self:GetECMModule(moduleName)
        assert(module, "Module not found: " .. moduleName)

        local configKey = moduleName:sub(1, 1):lower() .. moduleName:sub(2)
        local moduleConfig = profile and profile[configKey]
        local shouldEnable = (not moduleConfig) or (moduleConfig.enabled ~= false)
        ECM.OptionUtil.SetModuleEnabled(moduleName, shouldEnable)
    end

    enableLayoutEvents()
end
