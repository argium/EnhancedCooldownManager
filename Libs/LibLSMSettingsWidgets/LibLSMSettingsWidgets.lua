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

LibLSMSettingsWidgets_FontPickerMixin = {}

function LibLSMSettingsWidgets_FontPickerMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)

    self.DropDown = self:CreateDropDown()
    self.Preview = self:CreateFontString(nil, "OVERLAY")
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetPoint("RIGHT", self, "RIGHT", -20, 0)
    self.Preview:SetJustifyH("LEFT")
    self.Preview:SetText("AaBbCcDd 1234")
end

function LibLSMSettingsWidgets_FontPickerMixin:CreateDropDown()
    local dropdown = CreateFrame("DropdownButton", nil, self, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    return dropdown
end

function LibLSMSettingsWidgets_FontPickerMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local data = initializer:GetData()
    self.setting = data.setting

    if data.name and self.Text then
        self.Text:SetText(data.name)
    end

    self:SetupDropdown()
    self:UpdatePreview()
end

function LibLSMSettingsWidgets_FontPickerMixin:SetupDropdown()
    local setting = self.setting
    local picker = self

    self.DropDown:SetupMenu(function(dropdown, rootDescription)
        local values = lib.GetFontValues()
        local sorted = {}
        for name in pairs(values) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
            local fontPath = LSM:Fetch("font", name)
            local radio = rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    picker:UpdatePreview()
                end)

            if fontPath then
                radio:AddInitializer(function(button)
                    local regions = { button:GetRegions() }
                    for _, region in ipairs(regions) do
                        if region:IsObjectType("FontString") and region:GetText() == name then
                            region:SetFont(fontPath, 12, "")
                            break
                        end
                    end
                end)
            end
        end
    end)
end

function LibLSMSettingsWidgets_FontPickerMixin:UpdatePreview()
    local currentName = self.setting:GetValue()
    local fontPath = LSM:Fetch("font", currentName)
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
    local dropdown = CreateFrame("DropdownButton", nil, self, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    return dropdown
end

function LibLSMSettingsWidgets_TexturePickerMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local data = initializer:GetData()
    self.setting = data.setting

    if data.name and self.Text then
        self.Text:SetText(data.name)
    end

    self:SetupDropdown()
    self:UpdatePreview()
end

function LibLSMSettingsWidgets_TexturePickerMixin:SetupDropdown()
    local setting = self.setting
    local picker = self

    self.DropDown:SetupMenu(function(dropdown, rootDescription)
        local values = lib.GetStatusbarValues()
        local sorted = {}
        for name in pairs(values) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
            local texturePath = LSM:Fetch("statusbar", name)
            local radio = rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    picker:UpdatePreview()
                end)

            if texturePath then
                radio:AddInitializer(function(button)
                    if not button._lsmwPreview then
                        local preview = button:CreateTexture(nil, "ARTWORK")
                        preview:SetPoint("RIGHT", button, "RIGHT", -5, 0)
                        preview:SetSize(80, 12)
                        button._lsmwPreview = preview
                    end
                    button._lsmwPreview:SetTexture(texturePath)
                    button._lsmwPreview:SetVertexColor(0.4, 0.6, 0.9, 1)
                end)
            end
        end
    end)
end

function LibLSMSettingsWidgets_TexturePickerMixin:UpdatePreview()
    local currentName = self.setting:GetValue()
    local texturePath = LSM:Fetch("statusbar", currentName)
    if texturePath and self.Preview then
        self.Preview:SetTexture(texturePath)
    end
end
