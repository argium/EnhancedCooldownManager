-- LibLSMSettingsWidgets: LibSharedMedia picker widgets for the WoW Settings API.
-- Provides font and texture picker templates with live previews.

local MAJOR, MINOR = "LibLSMSettingsWidgets-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local LSM = LibStub("LibSharedMedia-3.0")

lib.FONT_PICKER_TEMPLATE = "LibLSMSettingsWidgets_FontPickerTemplate"
lib.TEXTURE_PICKER_TEMPLATE = "LibLSMSettingsWidgets_TexturePickerTemplate"

--------------------------------------------------------------------------------
-- Media value helpers
--------------------------------------------------------------------------------

function lib.GetFontValues()
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List("font")) do
            values[name] = name
        end
    end

    if not next(values) then
        values["Expressway"] = "Expressway"
    end

    return values
end

function lib.GetStatusbarValues()
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List("statusbar")) do
            values[name] = name
        end
    end

    if not next(values) then
        values["Blizzard"] = "Blizzard"
    end

    return values
end

--------------------------------------------------------------------------------
-- Font Picker Mixin
--------------------------------------------------------------------------------

local function setPickerEnabled(self, enabled)
    if self.DropDown.SetEnabled then self.DropDown:SetEnabled(enabled) end
    if self.DropDown.EnableMouse then self.DropDown:EnableMouse(enabled) end
    if self.DropDownHost.SetEnabled then self.DropDownHost:SetEnabled(enabled) end
    if self.DropDownHost.EnableMouse then self.DropDownHost:EnableMouse(enabled) end
    self.Preview[enabled and "Show" or "Hide"](self.Preview)
end

LibLSMSettingsWidgets_FontPickerMixin = {}

function LibLSMSettingsWidgets_FontPickerMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)

    self.DropDown = self:CreateDropDown()
    self.Preview = self:CreateFontString(nil, "OVERLAY")
    self.Preview:SetFontObject(GameFontHighlight)
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetPoint("RIGHT", self, "RIGHT", -20, 0)
    self.Preview:SetJustifyH("LEFT")
    self.Preview:SetText("AaBbCcDd 1234")
end

function LibLSMSettingsWidgets_FontPickerMixin:CreateDropDown()
    local host = CreateFrame("Frame", nil, self, "SettingsDropdownWithButtonsTemplate")
    if host.DecrementButton then host.DecrementButton:Hide() end
    if host.IncrementButton then host.IncrementButton:Hide() end

    local dropdown = host.Dropdown or host
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    self.DropDownHost = host
    return dropdown
end

function LibLSMSettingsWidgets_FontPickerMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local data = initializer:GetData()
    self.setting = initializer:GetSetting() or data.setting

    if data.name and self.Text then
        self.Text:SetText(data.name)
    end

    self:SetupDropdown()
    self:UpdatePreview()

    local frame = self
    initializer.SetEnabled = function(_, enabled)
        frame:SetEnabled(enabled)
    end
end

LibLSMSettingsWidgets_FontPickerMixin.SetEnabled = setPickerEnabled

function LibLSMSettingsWidgets_FontPickerMixin:SetupDropdown()
    local setting = self.setting
    local picker = self

    if not setting then return end

    self.DropDown:SetupMenu(function(dropdown, rootDescription)
        rootDescription:SetScrollMode(200)

        local values = lib.GetFontValues()
        local sorted = {}
        for name in pairs(values) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
            local radio = rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    picker:UpdatePreview()
                end)
        end
    end)
end

function LibLSMSettingsWidgets_FontPickerMixin:UpdatePreview()
    if not self.setting then return end

    local currentName = self.setting:GetValue()
    local fontPath = LSM and LSM.Fetch and LSM:Fetch("font", currentName)

    if self.DropDown and self.DropDown.OverrideText then
        self.DropDown:OverrideText(currentName or "")
    end

    if fontPath and self.Preview then
        self.Preview:SetFont(fontPath, 14, "")
        self.Preview:SetText("AaBbCcDd 1234")
    end
end

--------------------------------------------------------------------------------
-- Texture Picker Mixin
--------------------------------------------------------------------------------

LibLSMSettingsWidgets_TexturePickerMixin = {}

function LibLSMSettingsWidgets_TexturePickerMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)

    self.DropDown = self:CreateDropDown()
    self.Preview = self:CreateTexture(nil, "ARTWORK")
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetSize(120, 16)
    self.Preview:SetVertexColor(0.4, 0.6, 0.9, 1)
end

function LibLSMSettingsWidgets_TexturePickerMixin:CreateDropDown()
    local host = CreateFrame("Frame", nil, self, "SettingsDropdownWithButtonsTemplate")
    if host.DecrementButton then host.DecrementButton:Hide() end
    if host.IncrementButton then host.IncrementButton:Hide() end

    local dropdown = host.Dropdown or host
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    self.DropDownHost = host
    return dropdown
end

function LibLSMSettingsWidgets_TexturePickerMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local data = initializer:GetData()
    self.setting = initializer:GetSetting() or data.setting

    if data.name and self.Text then
        self.Text:SetText(data.name)
    end

    self:SetupDropdown()
    self:UpdatePreview()

    local frame = self
    initializer.SetEnabled = function(_, enabled)
        frame:SetEnabled(enabled)
    end
end

LibLSMSettingsWidgets_TexturePickerMixin.SetEnabled = setPickerEnabled

function LibLSMSettingsWidgets_TexturePickerMixin:SetupDropdown()
    local setting = self.setting
    local picker = self

    if not setting then return end

    self.DropDown:SetupMenu(function(dropdown, rootDescription)
        rootDescription:SetScrollMode(200)

        local values = lib.GetStatusbarValues()
        local sorted = {}
        for name in pairs(values) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
            local radio = rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    picker:UpdatePreview()
                end)
        end
    end)
end

function LibLSMSettingsWidgets_TexturePickerMixin:UpdatePreview()
    if not self.setting then return end

    local currentName = self.setting:GetValue()
    local texturePath = LSM and LSM.Fetch and LSM:Fetch("statusbar", currentName)

    if self.DropDown and self.DropDown.OverrideText then
        self.DropDown:OverrideText(currentName or "")
    end

    if texturePath and self.Preview then
        self.Preview:SetTexture(texturePath)
    end
end
