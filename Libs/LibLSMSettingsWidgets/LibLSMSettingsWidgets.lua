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

local mediaCache = {}

local function invalidateMediaCache()
    wipe(mediaCache)
end

if LSM and LSM.RegisterCallback then
    LSM:RegisterCallback("LibSharedMedia_Registered", invalidateMediaCache)
end

local function getSortedMediaNames(mediaType, fallback)
    local cached = mediaCache[mediaType]
    if cached then
        return cached
    end

    local sorted = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List(mediaType)) do
            sorted[#sorted + 1] = name
        end
    end

    if #sorted == 0 then
        sorted[1] = fallback
    end

    table.sort(sorted)
    mediaCache[mediaType] = sorted
    return sorted
end

function lib.GetFontValues()
    local names = getSortedMediaNames("font", "Expressway")
    local values = {}
    for _, name in ipairs(names) do
        values[name] = name
    end
    return values
end

function lib.GetStatusbarValues()
    local names = getSortedMediaNames("statusbar", "Blizzard")
    local values = {}
    for _, name in ipairs(names) do
        values[name] = name
    end
    return values
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

    local data = initializer:GetData() or {}
    self.setting = initializer:GetSetting() or data.setting

    if data.name and self.Text then
        self.Text:SetText(data.name)
    end

    self:SetupDropdown()
    self:UpdatePreview()

    local frame = self
    local oldSetEnabled = initializer.SetEnabled
    initializer.SetEnabled = function(init, enabled)
        if oldSetEnabled then
            oldSetEnabled(init, enabled)
        end
        frame:SetEnabled(enabled)
    end
end

local function setupMediaDropdown(self, mediaType, fallback)
    local setting = self.setting
    local picker = self

    if not setting then return end

    self.DropDown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(200)

        local sorted = getSortedMediaNames(mediaType, fallback)

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
    setupMediaDropdown(self, "font", "Expressway")
end

function LibLSMSettingsWidgets_FontPickerMixin:UpdatePreview()
    local _, fontPath = updateDropdownText(self, "font")
    if self.Preview then
        if fontPath then
            self.Preview:SetFont(fontPath, 14, "")
            self.Preview:SetText("AaBbCcDd 1234")
        else
            self.Preview:SetFontObject(GameFontHighlight)
            self.Preview:SetText("")
        end
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
    setupMediaDropdown(self, "statusbar", "Blizzard")
end

function LibLSMSettingsWidgets_TexturePickerMixin:UpdatePreview()
    local _, texturePath = updateDropdownText(self, "statusbar")
    if self.Preview then
        if texturePath then
            self.Preview:SetTexture(texturePath)
        else
            self.Preview:SetTexture(nil)
        end
    end
end

--------------------------------------------------------------------------------
-- Settings Initializer Injection
--------------------------------------------------------------------------------

if not lib._initializerHooked and Settings and Settings.CreateElementInitializer then
    local origCreateElementInitializer = Settings.CreateElementInitializer
    -- luacheck: push ignore Settings Mixin
    function Settings.CreateElementInitializer(template, data)
        if template == lib.FONT_PICKER_TEMPLATE or template == lib.TEXTURE_PICKER_TEMPLATE then
            local initializer = origCreateElementInitializer("SettingsListElementTemplate", data)
            local targetMixin = template == lib.FONT_PICKER_TEMPLATE and LibLSMSettingsWidgets_FontPickerMixin or LibLSMSettingsWidgets_TexturePickerMixin

            local origInitFrame = initializer.InitFrame
            initializer.InitFrame = function(self, frame)
                if not frame._lsmMixinInjected then
                    Mixin(frame, targetMixin)
                    if frame.OnLoad then
                        frame:OnLoad()
                    end
                    frame._lsmMixinInjected = true
                end

                if origInitFrame then
                    origInitFrame(self, frame)
                end
            end

            return initializer
        end

        return origCreateElementInitializer(template, data)
    end
    -- luacheck: pop
    lib._initializerHooked = true
end
