-- Bug report popup and player info helpers

local _, ns = ...

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
        tile = true,
        tileSize = 32,
        edgeSize = 32,
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
    local content = GetPlayerInfoString() .. "\n" .. string.rep("-", 60) .. "\n" .. ns.GetTraceLog()
    frame.originalText = content
    frame.editBox:SetText(content)
    frame.editBox:SetCursorPosition(0)
    frame:Show()
    frame.editBox:HighlightText()
end

ns.ShowBugReportPopup = ShowBugReportPopup
