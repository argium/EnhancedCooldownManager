-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0")
if not AceGUI then return end

local Type, Version = "ECM_PositionModeSelector", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local AUTO_ICON = "Interface\\Icons\\inv_12_profession_blacksmithing_blacksmithstoolkit_purple"
local FREE_ICON = "Interface\\Icons\\inv_blacksmithing_toolbox_02"

local BUTTON_HEIGHT = 40
local BUTTON_GAP = 6
local ICON_SIZE = 26

local function CreateOptionButton(parent)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetHeight(BUTTON_HEIGHT)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(0.12, 0.12, 0.12, 0.85)
    btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

    local highlight = btn:GetHighlightTexture()
    highlight:SetBlendMode("ADD")
    highlight:SetAlpha(0.4)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetSize(ICON_SIZE, ICON_SIZE)
    btn.icon:SetPoint("LEFT", btn, "LEFT", 10, 0)

    btn.label = btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    btn.label:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
    btn.label:SetJustifyH("LEFT")

    btn.selectedTex = btn:CreateTexture(nil, "BORDER")
    btn.selectedTex:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2")
    btn.selectedTex:SetBlendMode("ADD")
    btn.selectedTex:SetPoint("TOPLEFT", 2, -2)
    btn.selectedTex:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.selectedTex:SetAlpha(0.35)
    btn.selectedTex:Hide()

    return btn
end

local methods = {}

function methods:OnAcquire()
    self:SetDisabled(false)
    if not self.value then
        self:SetValue("chain")
    else
        self:UpdateVisuals()
    end
end

function methods:OnRelease()
    self:SetDisabled(false)
    self.list = nil
end

function methods:SetList(list)
    self.list = list
    local autoLabel = list and list.chain or "Position Automatically"
    local freeLabel = list and list.free or "Free Positioning"
    self.autoButton.label:SetText(autoLabel)
    self.freeButton.label:SetText(freeLabel)
end

function methods:SetLabel(text)
    if not self.label then return end
    if text and text ~= "" then
        self.label:SetText(text)
        self.label:Show()
    else
        self.label:SetText("")
        self.label:Hide()
    end
end

function methods:SetValue(value)
    if value ~= "chain" and value ~= "free" then
        value = "chain"
    end
    self.value = value
    self:UpdateVisuals()
end

function methods:GetValue()
    return self.value
end

function methods:SetDisabled(disabled)
    self.disabled = disabled
    self.autoButton:SetEnabled(not disabled)
    self.freeButton:SetEnabled(not disabled)
    self.frame:SetAlpha(disabled and 0.5 or 1)
end

function methods:OnWidthSet(width)
    local buttonWidth = math.max(1, (width - BUTTON_GAP) / 2)
    self.autoButton:SetWidth(buttonWidth)
    self.freeButton:SetWidth(buttonWidth)
end

function methods:UpdateVisuals()
    local function Apply(button, isSelected)
        button.selectedTex:SetShown(isSelected)
        if isSelected then
            button:SetBackdropBorderColor(1, 0.82, 0, 1)
            button:SetBackdropColor(0.15, 0.12, 0.02, 0.95)
            button.label:SetTextColor(1, 1, 1)
        else
            button:SetBackdropBorderColor(0.45, 0.45, 0.45, 1)
            button:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            button.label:SetTextColor(0.8, 0.8, 0.8)
        end
    end

    Apply(self.autoButton, self.value == "chain")
    Apply(self.freeButton, self.value == "free")
end

local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:Hide()
    frame:SetHeight(BUTTON_HEIGHT + BUTTON_GAP)

    local label = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    label:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    label:SetJustifyH("LEFT")
    label:Hide()

    local autoButton = CreateOptionButton(frame)
    autoButton:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -BUTTON_GAP)
    autoButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    autoButton:SetPoint("RIGHT", frame, "CENTER", -BUTTON_GAP / 2, 0)
    autoButton.icon:SetTexture(AUTO_ICON)

    local freeButton = CreateOptionButton(frame)
    freeButton:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -BUTTON_GAP)
    freeButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    freeButton:SetPoint("LEFT", frame, "CENTER", BUTTON_GAP / 2, 0)
    freeButton.icon:SetTexture(FREE_ICON)

    local widget = {
        frame = frame,
        type = Type,
        label = label,
        autoButton = autoButton,
        freeButton = freeButton,
    }

    for method, func in pairs(methods) do
        widget[method] = func
    end

    autoButton:SetScript("OnClick", function()
        if widget.disabled then return end
        if widget.value ~= "chain" then
            widget:SetValue("chain")
            widget:Fire("OnValueChanged", "chain")
        end
    end)

    freeButton:SetScript("OnClick", function()
        if widget.disabled then return end
        if widget.value ~= "free" then
            widget:SetValue("free")
            widget:Fire("OnValueChanged", "free")
        end
    end)

    frame.obj = widget

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
