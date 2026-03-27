-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

---@class ECM_Addon : AceAddon Core addon object (AceAddon instance).
---@field db AceDBObject-3.0 AceDB database handle.
---@field _addonCompartmentRegistered boolean Whether the addon compartment entry has been registered.
---@field _openOptionsAfterCombat boolean Whether to open options after leaving combat.

local ADDON_NAME, ns = ...
local mod = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "LibEvent-1.0")
mod:SetDefaultModuleLibraries("LibEvent-1.0")
ns.Addon = mod
ECM = ECM or {}
assert(ECM.defaults, "ECM_Defaults.lua must be loaded before ECM.lua")
assert(ECM.Constants, "ECM_Constants.lua must be loaded before ECM.lua")
assert(ECM.Migration, "Migration.lua must be loaded before ECM.lua")
assert(ECM.FrameMixin, "FrameMixin.lua must be loaded before ECM.lua")
assert(ECM.EditMode, "ECM.EditMode must be initialized before ECM.lua")

local LibConsole = LibStub("LibConsole-1.0")
local LSM = LibStub("LibSharedMedia-3.0", true)
local C = ECM.Constants
local L = ECM.L

--- Returns the global config section. Standalone accessor for non-module callers.
---@return table|nil
function ECM.GetGlobalConfig()
    local db = ns.Addon and ns.Addon.db
    local profile = db and db.profile
    return profile and profile[C.CONFIG_SECTION_GLOBAL]
end

--- Returns whether debug mode is enabled.
function ECM.IsDebugEnabled()
    local gc = ECM.GetGlobalConfig()
    return gc and gc.debug
end

local function getAddonVersion()
    if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
        return C_AddOns.GetAddOnMetadata(ADDON_NAME, C.ADDON_METADATA_VERSION_KEY)
    end
end

local function markReleasePopupSeen(version)
    local gc = ECM.GetGlobalConfig()
    ECM.DebugAssert(gc ~= nil, "Global config missing when marking release popup seen", { version = version })
    if gc then
        gc.releasePopupSeenVersion = version
    end
end

local function formatWhatsNewText(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line:find("^### ") then
            line = ("|cff%s%s|r"):format(C.WHATS_NEW_HEADER_COLOR, line:sub(5))
        elseif line:find("^%- ") then
            line = C.WHATS_NEW_LIST_BULLET .. " " .. line:sub(3)
        end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n")
end

local whatsNewFrame

local function createDialogShell(name, width, height, centerYOffset)
    local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, centerYOffset or 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop(C.DIALOG_BACKDROP)
    frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    frame:EnableMouse(true)
    frame:Hide()
    return frame
end

local function ensureWhatsNewFrame()
    if whatsNewFrame then
        return whatsNewFrame
    end

    local frame = createDialogShell(
        C.WHATS_NEW_FRAME_NAME,
        C.WHATS_NEW_FRAME_WIDTH,
        C.WHATS_NEW_FRAME_HEIGHT,
        C.WHATS_NEW_FRAME_OFFSET_Y
    )
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", C.WHATS_NEW_FRAME_PADDING, -C.WHATS_NEW_FRAME_PADDING)
    title:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -C.WHATS_NEW_FRAME_PADDING, -C.WHATS_NEW_FRAME_PADDING)
    title:SetJustifyH("LEFT")
    frame.Title = title

    local subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -C.WHATS_NEW_SUBTITLE_SPACING)
    subtitle:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -C.WHATS_NEW_SUBTITLE_SPACING)
    subtitle:SetJustifyH("LEFT")
    frame.Subtitle = subtitle

    local body = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    body:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -C.WHATS_NEW_BODY_SPACING)
    body:SetPoint("TOPRIGHT", subtitle, "BOTTOMRIGHT", 0, -C.WHATS_NEW_BODY_SPACING)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    frame.Body = body

    local closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeButton:SetSize(C.WHATS_NEW_CLOSE_BUTTON_WIDTH, C.WHATS_NEW_BUTTON_HEIGHT)
    closeButton:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        -C.WHATS_NEW_FRAME_PADDING,
        C.WHATS_NEW_BUTTON_BOTTOM_OFFSET
    )
    closeButton:SetText(L["CLOSE"])
    closeButton:SetScript("OnClick", function()
        markReleasePopupSeen(C.RELEASE_POPUP_VERSION)
        frame:Hide()
    end)
    frame.CloseButton = closeButton

    local settingsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    settingsButton:SetSize(C.WHATS_NEW_SETTINGS_BUTTON_WIDTH, C.WHATS_NEW_BUTTON_HEIGHT)
    settingsButton:SetPoint("RIGHT", closeButton, "LEFT", -C.WHATS_NEW_BUTTON_SPACING, 0)
    settingsButton:SetText(L["OPEN_SETTINGS"])
    settingsButton:SetScript("OnClick", function()
        markReleasePopupSeen(C.RELEASE_POPUP_VERSION)
        frame:Hide()
        mod:ChatCommand("options")
    end)
    frame.SettingsButton = settingsButton

    frame:Hide()
    whatsNewFrame = frame
    return frame
end

local function safeStrTostring(x)
    if x == nil then return "nil" end
    return issecretvalue(x) and "[secret]" or tostring(x)
end

local function safeTableTostring(tbl, depth, seen)
    if issecrettable(tbl) then return "[secrettable]" end
    if seen[tbl] then return "<cycle>" end
    if depth >= C.TOSTRING_MAX_DEPTH then return "{...}" end

    seen[tbl] = true

    local ok, pairsOrErr = pcall(function()
        local parts = {}
        local count = 0

        for k, x in pairs(tbl) do
            count = count + 1
            if count > C.TOSTRING_MAX_ITEMS then
                parts[#parts + 1] = "..."
                break
            end

            local keyStr = issecretvalue(k) and "[secret]" or tostring(k)
            local valueStr = type(x) == "table" and safeTableTostring(x, depth + 1, seen) or safeStrTostring(x)
            parts[#parts + 1] = keyStr .. "=" .. valueStr
        end

        return "{" .. table.concat(parts, ", ") .. "}"
    end)

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
    local fetched = texture and getLsmMedia("statusbar", texture)
    if fetched then return fetched end
    if texture and texture:find("\\") then return texture end
    return getLsmMedia("statusbar", "Blizzard") or C.DEFAULT_STATUSBAR_TEXTURE
end

function ECM.DebugAssert(condition, message, data)
    if not ECM.IsDebugEnabled() then
        return
    end

    if data and not condition and DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, data, "|cff" .. C.DEBUG_COLOR .. "[ASSERT]|r " .. message)
    end
    assert(condition, message)
end

function ECM.ApplyFont(fontString, globalConfig, moduleConfig)
    local config = globalConfig or ECM.GetGlobalConfig()
    local useModuleOverride = moduleConfig and moduleConfig.overrideFont
    local fontPath = getLsmMedia("font", (useModuleOverride and moduleConfig.font) or (config and config.font))
        or C.DEFAULT_FONT
    local fontSize = (useModuleOverride and moduleConfig.fontSize)
        or (config and config.fontSize)
        or C.DEFAULT_FONT_SIZE
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

ECM.Print = LibConsole:NewPrinter(function(message)
    print(ECM.ColorUtil.Sparkle(L["ADDON_ABRV"] .. ":") .. " " .. message)
end)

function ECM.Log(module, message, data)
    if not ECM.IsDebugEnabled() then
        return
    end

    local coloredPrefix = "|cff" .. C.DEBUG_COLOR .. "[" .. L["ADDON_ABRV"]
        .. (module and (" " .. module) or "") .. "]|r "

    if DevTool and DevTool.AddData then
        pcall(DevTool.AddData, DevTool, {
            module = module or "nil",
            message = message,
            timestamp = GetTime(),
            data = data and ECM.ToString(data),
        }, coloredPrefix .. message)
    end

    local cfg = ECM.GetGlobalConfig()
    if cfg and cfg.debugToChat then
        print(coloredPrefix .. message)
    end
end

--- Shows a confirmation popup and reloads the UI on accept.
--- ReloadUI is blocked in combat.
---@param text string
---@param onAccept fun()|nil
---@param onCancel fun()|nil
function mod:ConfirmReloadUI(text, onAccept, onCancel)
    if InCombatLockdown() then
        ECM.Print(L["RELOAD_BLOCKED_COMBAT"])
        return
    end

    if not StaticPopupDialogs[C.POPUP_CONFIRM_RELOAD_UI] then
        StaticPopupDialogs[C.POPUP_CONFIRM_RELOAD_UI] = {
            text = L["RELOAD_UI_PROMPT"],
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
            preferredIndex = C.POPUP_PREFERRED_INDEX,
        }
    end

    StaticPopupDialogs[C.POPUP_CONFIRM_RELOAD_UI].text = text or L["RELOAD_UI_PROMPT"]
    StaticPopup_Show(C.POPUP_CONFIRM_RELOAD_UI, nil, nil, { onAccept = onAccept, onCancel = onCancel })
end

function mod:ShowReleasePopup(force)
    local popupVersion = C.RELEASE_POPUP_VERSION
    local body = L["WHATS_NEW_BODY"]
    local hasBody = type(body) == "string" and body ~= "" and body ~= "WHATS_NEW_BODY"
    if not popupVersion or popupVersion == "" or not hasBody then
        return false
    end

    if force ~= true then
        local gc = ECM.GetGlobalConfig()
        if not gc or gc.releasePopupSeenVersion == popupVersion then
            return false
        end
        if whatsNewFrame and whatsNewFrame:IsShown() then
            return false
        end
    end

    local frame = ensureWhatsNewFrame()
    frame.Title:SetText(ECM.ColorUtil.Sparkle(L["ADDON_NAME"]))
    frame.Subtitle:SetText(string.format(L["WHATS_NEW_TITLE_FORMAT"], popupVersion))
    frame.Body:SetText(formatWhatsNewText(body))
    frame:Show()
    return true
end

--- Creates a dialog with a title, optional subtitle, and a scrolling edit box.
---@param name string Frame name registered in UISpecialFrames (ESC-closable).
---@param opts table
---  title       string?   Title text (default "")
---  subtitle    string?   Explanation text below title; shifts edit box down
---  width       number?   Frame width  (default DIALOG_FRAME_WIDTH)
---  height      number?   Frame height (default DIALOG_FRAME_HEIGHT)
---  readOnly    boolean?  Disable editing
---  movable     boolean?  Allow dragging to reposition
---  resizable   boolean?  Add a drag-resize grip at bottom-right
---  minWidth    number?   Min resize width  (default 400)
---  minHeight   number?   Min resize height (default 200)
---  closeOnCopy boolean?  Auto-close when Ctrl+C is pressed
---  onCopied    function? Callback after Ctrl+C close
local function createTextDialog(name, opts)
    local f = createDialogShell(name, opts.width or C.DIALOG_FRAME_WIDTH, opts.height or C.DIALOG_FRAME_HEIGHT)
    tinsert(UISpecialFrames, name)

    if opts.movable then
        f:SetMovable(true)
        f:SetClampedToScreen(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function(self) self:StartMoving() end)
        f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    end

    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(opts.title or "")
    f.title = title

    local scrollTop = -42
    if opts.subtitle then
        local explain = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        explain:SetPoint("TOP", 0, -40)
        explain:SetPoint("LEFT", 24, 0)
        explain:SetPoint("RIGHT", -24, 0)
        explain:SetJustifyH("LEFT")
        explain:SetJustifyV("TOP")
        explain:SetText(opts.subtitle)
        scrollTop = -88
    end

    local scroll = CreateFrame("Frame", nil, f, "ScrollingEditBoxTemplate")
    scroll.hideCharCount = true
    scroll.maxLetters = 0
    scroll:SetPoint("TOPLEFT", 16, scrollTop)
    scroll:SetPoint("BOTTOMRIGHT", -16, 48)
    f.Scroll = scroll

    local editBox = scroll.ScrollBox.EditBox

    if opts.readOnly then
        local restoring = false
        editBox:HookScript("OnTextChanged", function(self)
            if restoring then return end
            if f._readOnlyText and self:GetText() ~= f._readOnlyText then
                restoring = true
                self:SetText(f._readOnlyText)
                restoring = false
            end
        end)
    end

    if opts.closeOnCopy then
        editBox:SetScript("OnKeyDown", function(_, key)
            if key == "C" and IsControlKeyDown() then
                C_Timer.After(0.1, function()
                    f:Hide()
                    if opts.onCopied then opts.onCopied() end
                end)
            end
        end)
    end

    if opts.resizable then
        f:SetResizable(true)
        f:SetResizeBounds(opts.minWidth or 400, opts.minHeight or 200)
        local grip = CreateFrame("Button", nil, f)
        grip:SetSize(16, 16)
        grip:SetPoint("BOTTOMRIGHT")
        grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
        grip:SetScript("OnMouseDown", function()
            -- Re-anchor from TOPLEFT so BOTTOMRIGHT sizing doesn't fight the CENTER anchor.
            local left, top = f:GetLeft(), f:GetTop()
            local parentTop = UIParent:GetTop()
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", left, top - parentTop)
            f:StartSizing("BOTTOMRIGHT")
        end)
        grip:SetScript("OnMouseUp", function()
            f:StopMovingOrSizing()
        end)
    end

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

local function showCopyDialog(frame, text)
    frame:Show()
    local editBox = frame.Scroll.ScrollBox.EditBox
    editBox:SetText(text)
    editBox:HighlightText()
    editBox:SetFocus()
end

local exportFrame

--- Shows a dialog with the export string for copying.
---@param exportString string
function mod:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        ECM.Print(L["INVALID_EXPORT_STRING"])
        return
    end

    if not exportFrame then
        exportFrame = createTextDialog("ECMExportFrame", {
            title = L["EXPORT_PROFILE_TITLE"],
            subtitle = L["COPY_CTRL_C"],
            closeOnCopy = true,
            onCopied = function() ECM.Print(L["IMPORT_COPIED"]) end,
        })
        addButton(exportFrame, CLOSE, { "BOTTOMRIGHT", -16, 8 }, function()
            exportFrame:Hide()
        end)
    end

    showCopyDialog(exportFrame, exportString)
end

local copyTextFrame

--- Shows a small dialog with text for copying (e.g. a URL).
---@param text string
---@param title string|nil
function mod:ShowCopyTextDialog(text, title)
    if not text or text == "" then
        return
    end

    if not copyTextFrame then
        copyTextFrame = createTextDialog("ECMCopyTextFrame", {
            subtitle = L["COPY_CTRL_C"],
            width = C.DIALOG_FRAME_WIDTH_SMALL,
            height = C.DIALOG_FRAME_HEIGHT_SMALL,
            closeOnCopy = true,
        })
        addButton(copyTextFrame, CLOSE, { "BOTTOMRIGHT", -16, 8 }, function()
            copyTextFrame:Hide()
        end)
    end

    copyTextFrame.title:SetText(title or L["COPY_LINK"])
    showCopyDialog(copyTextFrame, text)
end

local migrationLogFrame

--- Shows the migration log in a read-only dialog window.
---@param text string
function mod:ShowMigrationLogDialog(text)
    if not migrationLogFrame then
        migrationLogFrame = createTextDialog("ECMMigrationLogFrame", {
            title = L["MIGRATION_LOG_TITLE"],
            width = C.DIALOG_FRAME_WIDTH * 2,
            height = C.DIALOG_FRAME_HEIGHT * 2,
            readOnly = true,
            movable = true,
            resizable = true,
        })
        addButton(migrationLogFrame, CLOSE, { "BOTTOMRIGHT", -16, 8 }, function()
            migrationLogFrame:Hide()
        end)
    end

    migrationLogFrame._readOnlyText = text
    migrationLogFrame:Show()
    migrationLogFrame.Scroll.ScrollBox.EditBox:SetText(text)
end

local importFrame

--- Shows a dialog to paste an import string and handles the import process.
function mod:ShowImportDialog()
    if not importFrame then
        importFrame = createTextDialog("ECMImportFrame", {
            title = L["IMPORT_PROFILE_TITLE"],
            subtitle = L["IMPORT_PASTE_PROMPT"],
        })

        local cancelBtn = addButton(importFrame, CANCEL, { "BOTTOMRIGHT", -16, 8 }, function()
            importFrame:Hide()
        end)
        addButton(importFrame, OKAY, { "RIGHT", cancelBtn, "LEFT", -4, 0 }, function()
            local input = importFrame.Scroll.ScrollBox.EditBox:GetText()

            if strtrim(input) == "" then
                ECM.Print(L["IMPORT_CANCELLED"])
                return
            end

            local data, errorMsg = ECM.ImportExport.ValidateImportString(input)
            if not data then
                ECM.Print(string.format(L["IMPORT_FAILED"], errorMsg or "unknown error"))
                return
            end

            importFrame:Hide()

            local versionStr = data.metadata and data.metadata.addonVersion or "unknown"
            local confirmText = string.format(L["IMPORT_CONFIRM"], versionStr)

            mod:ConfirmReloadUI(confirmText, function()
                local success, applyErr = ECM.ImportExport.ApplyImportData(data)
                if not success then
                    ECM.Print(string.format(L["IMPORT_APPLY_FAILED"], applyErr or "unknown error"))
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

    if cmd == "help" then
        ECM.Print(L["CMD_HELP_CLEARSEEN"])
        ECM.Print(L["CMD_HELP_DEBUG"])
        ECM.Print(L["CMD_HELP_EVENTS"])
        ECM.Print(L["CMD_HELP_HELP"])
        ECM.Print(L["CMD_HELP_MIGRATION"])
        ECM.Print(L["CMD_HELP_OPTIONS"])
        ECM.Print(L["CMD_HELP_REFRESH"])
        return
    end

    if cmd == "rl" or cmd == "reload" or cmd == "refresh" then
        ECM.Runtime.ScheduleLayoutUpdate(0, "ChatCommand")
        ECM.Print(L["REFRESHING_ALL_MODULES"])
        return
    end

    if cmd == "migration" then
        local subcmd, subarg = arg:match("^(%S*)%s*(.-)%s*$")
        if subcmd == "log" then
            local text = ECM.Migration.GetLogText()
            if not text then
                ECM.Print(L["MIGRATION_LOG_EMPTY"])
            else
                self:ShowMigrationLogDialog(text)
            end
            return
        end

        if subcmd == "rollback" then
            local n = tonumber(subarg)
            if not n then
                ECM.Print(L["MIGRATION_ROLLBACK_USAGE"])
                return
            end
            if n == 0 then
                ECM.Print(L["VERSION_ZERO_INVALID"])
                return
            end
            if n == -1 then
                n = ECM.Constants.CURRENT_SCHEMA_VERSION - 1
            end
            local ok, message = ECM.Migration.ValidateRollback(n)
            if not ok then
                ECM.Print(message)
                return
            end
            self:ConfirmReloadUI(message, function()
                ECM.Migration.Rollback(n)
            end)
            return
        end

        ECM.Migration.PrintInfo()
        return
    end

    if cmd == "" or cmd == "options" or cmd == "config" or cmd == "settings" or cmd == "o" then
        if InCombatLockdown() then
            ECM.Print(L["OPTIONS_BLOCKED_COMBAT"])
            self._openOptionsAfterCombat = true
            return
        end

        local optionsModule = self:GetModule("Options", true)
        if optionsModule then
            optionsModule:OpenOptions()
        end
        return
    end

    if cmd == "events" then
        self:HandleEventsCommand(arg)
        return
    end

    local gc = ECM.GetGlobalConfig()
    if not gc then
        return
    end

    if cmd == "debug" then
        local newVal
        if arg == "" or arg == "toggle" then
            newVal = not gc.debug
        elseif arg == "on" then
            newVal = true
        elseif arg == "off" then
            newVal = false
        else
            ECM.Print(L["DEBUG_USAGE"])
            return
        end
        gc.debug = newVal
        ECM.Print(L["DEBUG_STATUS"] .. " " .. (gc.debug and L["DEBUG_ON"] or L["DEBUG_OFF"]))
        return
    end

    if cmd == "clearseen" then
        gc.releasePopupSeenVersion = nil
        ECM.Print(L["SEEN_CLEARED"])
        return
    end
end

function mod:HandleEventsCommand(arg)
    if arg == "reset" then
        self:ResetEventStats()
        for _, m in self:IterateModules() do
            if m.ResetEventStats then
                m:ResetEventStats()
            end
        end
        ECM.Print(L["EVENTS_RESET"])
        return
    end

    -- Aggregate stats from the addon and all its modules.
    local merged = {}
    for event, count in pairs(self:GetEventStats()) do
        merged[event] = (merged[event] or 0) + count
    end
    for _, m in self:IterateModules() do
        if m.GetEventStats then
            for event, count in pairs(m:GetEventStats()) do
                merged[event] = (merged[event] or 0) + count
            end
        end
    end

    -- Sort descending by count.
    local sorted = {}
    for event, count in pairs(merged) do
        sorted[#sorted + 1] = { event = event, count = count }
    end

    if #sorted == 0 then
        ECM.Print(L["EVENTS_NONE"])
        return
    end

    table.sort(sorted, function(a, b)
        return a.count > b.count
    end)

    ECM.Print(L["EVENTS_HEADER"])
    for i = 1, #sorted do
        ECM.Print("  " .. sorted[i].event .. ": " .. sorted[i].count)
    end
end

function mod:HandleOpenOptionsAfterCombat()
    if not self._openOptionsAfterCombat then
        return
    end

    self._openOptionsAfterCombat = nil

    local optionsModule = self:GetModule("Options", true)
    if optionsModule then
        optionsModule:OpenOptions()
    end
end

function mod:GetECMModule(moduleName, silent)
    local module = self[moduleName] or ECM[moduleName]
    if not module and not silent then
        ECM.Print(L["MODULE_NOT_FOUND"] .. " " .. moduleName)
    end
    return module
end

function mod:OnInitialize()
    -- Set up versioned SV store and point the active key at the current version.
    ECM.Migration.PrepareDatabase()

    self.db = LibStub("AceDB-3.0"):New(C.ACTIVE_SV_KEY, ECM.defaults, true)

    ECM.Migration.Run(self.db.profile)

    ECM.Migration.FlushLog()

    -- Register bundled font with LibSharedMedia if present.
    if LSM then
        pcall(
            LSM.Register,
            LSM,
            "font",
            "Expressway",
            "Interface\\AddOns\\EnhancedCooldownManager\\media\\Fonts\\Expressway.ttf"
        )
    end

    local chatHandler = function(input) mod:ChatCommand(input) end
    LibConsole:RegisterCommand("enhancedcooldownmanager", chatHandler)
    LibConsole:RegisterCommand("ecm", chatHandler)
end

--- Enables the addon and ensures Blizzard's cooldown viewer is turned on.
function mod:OnEnable()
    C_CVar.SetCVar("cooldownViewerEnabled", "1")
    if not self._addonCompartmentRegistered and AddonCompartmentFrame then
        local ok = pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
            text = ECM.ColorUtil.Sparkle(L["ADDON_NAME"]),
            icon = C.ADDON_ICON_TEXTURE,
            notCheckable = true,
            func = function()
                self:ChatCommand("options")
            end,
        })
        self._addonCompartmentRegistered = ok
    end

    ECM.Runtime.OnCombatEnd = function()
        self:HandleOpenOptionsAfterCombat()
    end

    ECM.Runtime.Enable(self)

    -- Re-evaluate module enable/disable states on profile switch.
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChangedHandler")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChangedHandler")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChangedHandler")

    local version = getAddonVersion()

    if type(version) == "string" and version:lower():find(C.VERSION_TAG_BETA, 1, true) ~= nil then
        ECM.Print(L["BETA_LOGIN_MESSAGE"])
    end

    self:ShowReleasePopup()
end

--- Re-evaluates module enable/disable states after a profile change and refreshes layout.
function mod:OnProfileChangedHandler()
    ECM.Migration.Run(self.db.profile)
    ECM.Runtime.Enable(self)
    ECM.Runtime.ScheduleLayoutUpdate(0, "ProfileChanged")
end

function mod:OnDisable()
    ECM.Runtime.Disable(self)
end
