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

local function getMediaValues(mediaType, fallback)
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List(mediaType)) do
            values[name] = name
        end
    end

    if not next(values) then
        values[fallback] = fallback
    end

    return values
end

function lib.GetFontValues()
    return getMediaValues("font", "Expressway")
end

function lib.GetStatusbarValues()
    return getMediaValues("statusbar", "Blizzard")
end

--------------------------------------------------------------------------------
-- Shared picker helpers
--------------------------------------------------------------------------------

local function setPickerEnabled(self, enabled)
    if self.DropDown.SetEnabled then self.DropDown:SetEnabled(enabled) end
    if self.DropDown.EnableMouse then self.DropDown:EnableMouse(enabled) end
    if self.DropDownHost.SetEnabled then self.DropDownHost:SetEnabled(enabled) end
    if self.DropDownHost.EnableMouse then self.DropDownHost:EnableMouse(enabled) end
    self.Preview[enabled and "Show" or "Hide"](self.Preview)
end

local function createDropDown(self)
    local host = CreateFrame("Frame", nil, self, "SettingsDropdownWithButtonsTemplate")
    if host.DecrementButton then host.DecrementButton:Hide() end
    if host.IncrementButton then host.IncrementButton:Hide() end

    local dropdown = host.Dropdown or host
    dropdown:SetPoint("LEFT", self.Text, "RIGHT", 10, 0)
    dropdown:SetWidth(200)
    self.DropDownHost = host
    return dropdown
end

local function initPicker(self, initializer)
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

local function setupMediaDropdown(self, getValues)
    local setting = self.setting
    local picker = self

    if not setting then return end

    self.DropDown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(200)

        local values = getValues()
        local sorted = {}
        for name in pairs(values) do
            sorted[#sorted + 1] = name
        end
        table.sort(sorted)

        for _, name in ipairs(sorted) do
            rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    picker:UpdatePreview()
                end)
        end
    end)
end

--- Updates the dropdown label and fetches the media path for the current value.
---@return string|nil currentName
---@return string|nil mediaPath
local function updateDropdownText(self, mediaType)
    if not self.setting then return nil, nil end

    local currentName = self.setting:GetValue()
    local mediaPath = LSM and LSM.Fetch and LSM:Fetch(mediaType, currentName)

    if self.DropDown and self.DropDown.OverrideText then
        self.DropDown:OverrideText(currentName or "")
    end

    return currentName, mediaPath
end

--------------------------------------------------------------------------------
-- Font Picker Mixin
--------------------------------------------------------------------------------

LibLSMSettingsWidgets_FontPickerMixin = {}

function LibLSMSettingsWidgets_FontPickerMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)

    self.DropDown = createDropDown(self)
    self.Preview = self:CreateFontString(nil, "OVERLAY")
    self.Preview:SetFontObject(GameFontHighlight)
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetPoint("RIGHT", self, "RIGHT", -20, 0)
    self.Preview:SetJustifyH("LEFT")
    self.Preview:SetText("AaBbCcDd 1234")
end

LibLSMSettingsWidgets_FontPickerMixin.CreateDropDown = createDropDown
LibLSMSettingsWidgets_FontPickerMixin.Init = initPicker
LibLSMSettingsWidgets_FontPickerMixin.SetEnabled = setPickerEnabled

function LibLSMSettingsWidgets_FontPickerMixin:SetupDropdown()
    setupMediaDropdown(self, lib.GetFontValues)
end

function LibLSMSettingsWidgets_FontPickerMixin:UpdatePreview()
    local _, fontPath = updateDropdownText(self, "font")
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

    self.DropDown = createDropDown(self)
    self.Preview = self:CreateTexture(nil, "ARTWORK")
    self.Preview:SetPoint("LEFT", self.DropDown, "RIGHT", 10, 0)
    self.Preview:SetSize(120, 16)
    self.Preview:SetVertexColor(0.4, 0.6, 0.9, 1)
end

LibLSMSettingsWidgets_TexturePickerMixin.CreateDropDown = createDropDown
LibLSMSettingsWidgets_TexturePickerMixin.Init = initPicker
LibLSMSettingsWidgets_TexturePickerMixin.SetEnabled = setPickerEnabled

function LibLSMSettingsWidgets_TexturePickerMixin:SetupDropdown()
    setupMediaDropdown(self, lib.GetStatusbarValues)
end

function LibLSMSettingsWidgets_TexturePickerMixin:UpdatePreview()
    local _, texturePath = updateDropdownText(self, "statusbar")
    if texturePath and self.Preview then
        self.Preview:SetTexture(texturePath)
    end
end
