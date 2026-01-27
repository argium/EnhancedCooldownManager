-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0

local _, ns = ...

local AceGUI = LibStub("AceGUI-3.0")
if not AceGUI then return end

local Type, Version = "ECM_PositionModeSelector", 1
if (AceGUI:GetWidgetVersion(Type) or 0) >= Version then return end

local AUTO_ICON = "Interface\\Icons\\inv_12_profession_blacksmithing_blacksmithstoolkit_purple"
local CUSTOM_ICON = "Interface\\Icons\\inv_blacksmithing_toolbox_02"

local BUTTON_HEIGHT = 36
local BUTTON_GAP = 6
local ICON_SIZE = 20

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
        self:SetValue("auto")
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
    local autoLabel = list and list.auto or "Position Automatically"
    local customLabel = list and list.custom or "Custom Positioning"
    self.autoButton.label:SetText(autoLabel)
    self.customButton.label:SetText(customLabel)
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
    if value ~= "auto" and value ~= "custom" then
        value = "auto"
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
    self.customButton:SetEnabled(not disabled)
    self.frame:SetAlpha(disabled and 0.5 or 1)
end

function methods:OnWidthSet(width)
    local buttonWidth = math.max(1, (width - BUTTON_GAP) / 2)
    self.autoButton:SetWidth(buttonWidth)
    self.customButton:SetWidth(buttonWidth)
end

function methods:UpdateVisuals()
    local selected = self.value

    local function Apply(button, isSelected)
        button.selectedTex:SetShown(isSelected)
        if isSelected then
            button:SetBackdropBorderColor(1, 0.82, 0.1, 1)
            button:SetBackdropColor(0.35, 0.26, 0.06, 0.95) -- gold background
            button.label:SetTextColor(1, 0.82, 0.1) -- gold text
            button.icon:SetDesaturated(false)
            button:SetAlpha(1)
        else
            button:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
            button:SetBackdropColor(0.08, 0.08, 0.08, 0.7)
            button.label:SetTextColor(0.8, 0.8, 0.8)
            button.icon:SetDesaturated(true)
            button:SetAlpha(0.85)
        end
    end

    Apply(self.autoButton, selected == "auto")
    Apply(self.customButton, selected == "custom")
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

    local customButton = CreateOptionButton(frame)
    customButton:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -BUTTON_GAP)
    customButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    customButton:SetPoint("LEFT", frame, "CENTER", BUTTON_GAP / 2, 0)
    customButton.icon:SetTexture(CUSTOM_ICON)

    local widget = {
        frame = frame,
        type = Type,
        label = label,
        autoButton = autoButton,
        customButton = customButton,
    }

    for method, func in pairs(methods) do
        widget[method] = func
    end

    autoButton:SetScript("OnClick", function()
        if widget.disabled then return end
        if widget.value ~= "auto" then
            widget:SetValue("auto")
            widget:Fire("OnValueChanged", "auto")
        end
    end)

    customButton:SetScript("OnClick", function()
        if widget.disabled then return end
        if widget.value ~= "custom" then
            widget:SetValue("custom")
            widget:Fire("OnValueChanged", "custom")
        end
    end)

    frame.obj = widget

    return AceGUI:RegisterAsWidget(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
