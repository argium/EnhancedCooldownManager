-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local LSM = LibStub("LibSharedMedia-3.0")

LSMFontPickerMixin = {}

function LSMFontPickerMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)

    self.DropDown = self:CreateDropDown()
    self.Preview = self:CreateFontString(nil, "OVERLAY")
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetText("AaBbCcDd 1234")
end

function LSMFontPickerMixin:CreateDropDown()
    local dropdown = CreateFrame("DropdownButton", nil, self, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    return dropdown
end

function LSMFontPickerMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local data = initializer:GetData()
    self.setting = data.setting

    self:SetupDropdown()
    self:UpdatePreview()
end

function LSMFontPickerMixin:SetupDropdown()
    local setting = self.setting

    self.DropDown:SetupMenu(function(dropdown, rootDescription)
        local values = ECM.SharedMediaOptions.GetFontValues()
        for name in pairs(values) do
            local fontPath = LSM:Fetch("font", name)
            local radio = rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    self:UpdatePreview()
                end)

            if fontPath then
                radio:AddInitializer(function(button)
                    local fontString = button:GetFontString()
                    if fontString then
                        fontString:SetFont(fontPath, 12, "")
                    end
                end)
            end
        end
    end)
end

function LSMFontPickerMixin:UpdatePreview()
    local currentName = self.setting:GetValue()
    local fontPath = LSM:Fetch("font", currentName)
    if fontPath and self.Preview then
        self.Preview:SetFont(fontPath, 14, "")
    end
end
