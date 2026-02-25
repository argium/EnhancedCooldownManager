-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local LSM = LibStub("LibSharedMedia-3.0")

ECM_LSMTexturePickerMixin = {}

function ECM_LSMTexturePickerMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)

    self.DropDown = self:CreateDropDown()
    self.Preview = self:CreateTexture(nil, "ARTWORK")
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetSize(120, 16)
    self.Preview:SetVertexColor(0.4, 0.6, 0.9, 1)
end

function ECM_LSMTexturePickerMixin:CreateDropDown()
    local dropdown = CreateFrame("DropdownButton", nil, self, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    return dropdown
end

function ECM_LSMTexturePickerMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)

    local data = initializer:GetData()
    self.setting = data.setting

    self:SetupDropdown()
    self:UpdatePreview()
end

function ECM_LSMTexturePickerMixin:SetupDropdown()
    local setting = self.setting

    self.DropDown:SetupMenu(function(dropdown, rootDescription)
        local values = ECM.SharedMediaOptions.GetStatusbarValues()
        for name in pairs(values) do
            local texturePath = LSM:Fetch("statusbar", name)
            local radio = rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    self:UpdatePreview()
                end)

            if texturePath then
                radio:AddInitializer(function(button)
                    local preview = button:CreateTexture(nil, "ARTWORK")
                    preview:SetPoint("RIGHT", button, "RIGHT", -5, 0)
                    preview:SetSize(80, 12)
                    preview:SetTexture(texturePath)
                    preview:SetVertexColor(0.4, 0.6, 0.9, 1)
                end)
            end
        end
    end)
end

function ECM_LSMTexturePickerMixin:UpdatePreview()
    local currentName = self.setting:GetValue()
    local texturePath = LSM:Fetch("statusbar", currentName)
    if texturePath and self.Preview then
        self.Preview:SetTexture(texturePath)
    end
end

--- Creates an initializer for an LSM texture picker control.
---@param category table The settings category
---@param setting table The proxy setting
---@param tooltip string|nil Optional tooltip
---@return table initializer
function ECM_CreateLSMTexturePickerInitializer(category, setting, tooltip)
    local data = { setting = setting, tooltip = tooltip }
    local initializer = Settings.CreateElementInitializer("ECM_LSMTexturePickerTemplate", data)
    local layout = category:GetLayout()
    layout:AddInitializer(initializer)
    return initializer
end
