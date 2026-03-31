-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L
local mod = ns.Addon

local function markReleasePopupSeen(version)
    local gc = ns.GetGlobalConfig()
    ns.DebugAssert(gc ~= nil, "Global config missing when marking release popup seen", { version = version })
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
local copyTextFrame
local migrationLogFrame
local importFrame

function mod:ShowReleasePopup(force)
    local popupVersion = C.RELEASE_POPUP_VERSION
    local body = L["WHATS_NEW_BODY"]
    local hasBody = type(body) == "string" and body ~= "" and body ~= "WHATS_NEW_BODY"
    if not popupVersion or popupVersion == "" or not hasBody then
        return false
    end

    if force ~= true then
        local gc = ns.GetGlobalConfig()
        if not gc or gc.releasePopupSeenVersion == popupVersion then
            return false
        end
        if whatsNewFrame and whatsNewFrame:IsShown() then
            return false
        end
    end

    local frame = ensureWhatsNewFrame()
    frame.Title:SetText(ns.ColorUtil.Sparkle(L["ADDON_NAME"]))
    frame.Subtitle:SetText(string.format(L["WHATS_NEW_TITLE_FORMAT"], popupVersion))
    frame.Body:SetText(formatWhatsNewText(body))
    frame:Show()
    return true
end

--- Shows a dialog with the export string for copying.
---@param exportString string
function mod:ShowExportDialog(exportString)
    if not exportString or exportString == "" then
        ns.Print(L["INVALID_EXPORT_STRING"])
        return
    end

    if not exportFrame then
        exportFrame = createTextDialog("ECMExportFrame", {
            title = L["EXPORT_PROFILE_TITLE"],
            subtitle = L["COPY_CTRL_C"],
            closeOnCopy = true,
            onCopied = function() ns.Print(L["IMPORT_COPIED"]) end,
        })
        addButton(exportFrame, CLOSE, { "BOTTOMRIGHT", -16, 8 }, function()
            exportFrame:Hide()
        end)
    end

    showCopyDialog(exportFrame, exportString)
end

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
                ns.Print(L["IMPORT_CANCELLED"])
                return
            end

            local data, errorMsg = ns.ImportExport.ValidateImportString(input)
            if not data then
                ns.Print(string.format(L["IMPORT_FAILED"], errorMsg or "unknown error"))
                return
            end

            importFrame:Hide()

            local versionStr = data.metadata and data.metadata.addonVersion or "unknown"
            local confirmText = string.format(L["IMPORT_CONFIRM"], versionStr)

            mod:ConfirmReloadUI(confirmText, function()
                local success, applyErr = ns.ImportExport.ApplyImportData(data)
                if not success then
                    ns.Print(string.format(L["IMPORT_APPLY_FAILED"], applyErr or "unknown error"))
                end
            end, nil)
        end)
    end

    importFrame:Show()
    importFrame.Scroll.ScrollBox.EditBox:SetText("")
    importFrame.Scroll.ScrollBox.EditBox:SetFocus()
end
