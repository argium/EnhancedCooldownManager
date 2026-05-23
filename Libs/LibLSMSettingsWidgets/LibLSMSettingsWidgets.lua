-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

-- LibLSMSettingsWidgets: LibSharedMedia picker widgets for LibSettingsBuilder rows.

local MAJOR, MINOR = "LibLSMSettingsWidgets-1.0", 3
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local LSM = LibStub("LibSharedMedia-3.0")

local FONT_PREVIEW_TEXT = "AaBbCcDd 1234"
local mediaCache = {}

local function invalidateMediaCache()
    wipe(mediaCache)
end

LSM:RegisterCallback("LibSharedMedia_Registered", invalidateMediaCache)

local function getSortedMediaNames(mediaType, fallback)
    local cached = mediaCache[mediaType]
    if cached then
        return cached
    end

    local sorted = {}
    for _, name in ipairs(LSM:List(mediaType)) do
        sorted[#sorted + 1] = name
    end

    if #sorted == 0 then
        sorted[1] = fallback
    end

    table.sort(sorted)
    mediaCache[mediaType] = sorted
    return sorted
end

local function getMediaValues(mediaType, fallback)
    local values = {}
    for _, name in ipairs(getSortedMediaNames(mediaType, fallback)) do
        values[name] = name
    end
    return values
end

function lib.GetFontValues()
    return getMediaValues("font", "Expressway")
end

function lib.GetStatusbarValues()
    return getMediaValues("statusbar", "Blizzard")
end

local function createDropDown(frame)
    local host = CreateFrame("Frame", nil, frame, "SettingsDropdownWithButtonsTemplate")
    if host.DecrementButton then
        host.DecrementButton:Hide()
    end
    if host.IncrementButton then
        host.IncrementButton:Hide()
    end

    local dropdown = host.Dropdown or host
    dropdown:SetWidth(200)
    return host, dropdown
end

local function ensurePicker(frame, kind)
    local picker = frame._lsmwPicker
    if not picker then
        local host, dropdown = createDropDown(frame)
        picker = { host = host, dropdown = dropdown }
        frame._lsmwPicker = picker
    end

    if picker.kind ~= kind then
        if picker.preview then
            picker.preview:Hide()
        end

        if kind == "font" then
            picker.preview = picker.fontPreview or frame:CreateFontString(nil, "OVERLAY")
            picker.fontPreview = picker.preview
            picker.preview:SetFontObject(GameFontHighlight)
            picker.preview:SetJustifyH("LEFT")
        else
            picker.preview = picker.texturePreview or frame:CreateTexture(nil, "ARTWORK")
            picker.texturePreview = picker.preview
            picker.preview:SetSize(120, 16)
            picker.preview:SetVertexColor(0.4, 0.6, 0.9, 1)
        end
        picker.kind = kind
    end

    return picker
end

local function setPickerEnabled(frame, enabled)
    local picker = frame._lsmwPicker
    if not picker then return end

    picker.dropdown:SetEnabled(enabled)
    picker.dropdown:EnableMouse(enabled)
    picker.host:SetEnabled(enabled)
    picker.host:EnableMouse(enabled)
    picker.preview[enabled and "Show" or "Hide"](picker.preview)
end

local function configurePickerInitializer(initializer)
    if initializer._lsmwHasEnabledBridge then return end

    initializer._lsmwEnabled = true
    initializer._lsmwHasEnabledBridge = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsmwEnabled = enabled
        local frame = controlInitializer._lsbActiveFrame
        if frame and (not frame._lsbInitializer or frame._lsbInitializer == controlInitializer) then
            setPickerEnabled(frame, enabled)
        end
    end
end

local function anchorPicker(frame, picker)
    if frame.Text then
        frame.Text:ClearAllPoints()
        frame.Text:SetPoint("LEFT", frame, "LEFT", 37, 0)
        frame.Text:SetPoint("RIGHT", frame, "CENTER", -85, 0)
        frame.Text:SetJustifyV("MIDDLE")
        frame.Text:Show()
    end

    picker.host:ClearAllPoints()
    if frame.Text then
        picker.host:SetPoint("LEFT", frame.Text, "RIGHT", 10, 0)
    else
        picker.host:SetPoint("LEFT", frame, "CENTER", -80, 0)
    end
    picker.host:Show()

    picker.preview:ClearAllPoints()
    picker.preview:SetPoint("LEFT", picker.dropdown, "RIGHT", 10, 0)
    picker.preview:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
    picker.preview:Show()
end

local function updateDropdownText(picker, setting, mediaType)
    local currentName = setting and setting.GetValue and setting:GetValue() or nil

    if picker.dropdown.OverrideText then
        picker.dropdown:OverrideText(currentName or "")
    end

    if not currentName then
        return nil, nil
    end

    return currentName, LSM:Fetch(mediaType, currentName)
end

local function updateFontPreview(picker, setting)
    local _, fontPath = updateDropdownText(picker, setting, "font")
    if fontPath then
        picker.preview:SetFont(fontPath, 14, "")
        picker.preview:SetText(FONT_PREVIEW_TEXT)
    else
        picker.preview:SetFontObject(GameFontHighlight)
        picker.preview:SetText("")
    end
end

local function updateTexturePreview(picker, setting)
    local _, texturePath = updateDropdownText(picker, setting, "statusbar")
    picker.preview:SetTexture(texturePath)
end

local function setupMediaDropdown(frame, picker, setting, mediaType, fallback, updatePreview)
    if not setting then return end

    picker.dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:SetScrollMode(200)

        for _, name in ipairs(getSortedMediaNames(mediaType, fallback)) do
            rootDescription:CreateRadio(name,
                function() return setting:GetValue() == name end,
                function()
                    setting:SetValue(name)
                    updatePreview(picker, setting)
                    if frame.RefreshDropdownText then
                        frame:RefreshDropdownText()
                    end
                end)
        end
    end)
end

local function applyPickerRow(frame, data, initializer, kind, mediaType, fallback, updatePreview)
    configurePickerInitializer(initializer)
    initializer._lsbActiveFrame = frame

    local picker = ensurePicker(frame, kind)
    local setting = data.setting

    frame._lsmwPickerSetting = setting
    if frame.Text then
        frame.Text:SetText(data.name or "")
    end

    anchorPicker(frame, picker)
    setupMediaDropdown(frame, picker, setting, mediaType, fallback, updatePreview)
    updatePreview(picker, setting)
    setPickerEnabled(frame, initializer._lsmwEnabled ~= false)
end

function lib.ApplyFontPickerRow(frame, data, initializer)
    applyPickerRow(frame, data, initializer, "font", "font", "Expressway", updateFontPreview)
end

function lib.ApplyTexturePickerRow(frame, data, initializer)
    applyPickerRow(frame, data, initializer, "texture", "statusbar", "Blizzard", updateTexturePreview)
end

function lib.ResetPickerRow(frame)
    local picker = frame._lsmwPicker
    if not picker then return end

    picker.host:Hide()
    if picker.fontPreview then
        picker.fontPreview:Hide()
    end
    if picker.texturePreview then
        picker.texturePreview:Hide()
    end
    frame._lsmwPickerSetting = nil
end

function lib.Register(settingsBuilder)
    if not settingsBuilder or not settingsBuilder.RegisterRowType then return end

    settingsBuilder:RegisterRowType("font", {
        varType = "string",
        defaultValue = "",
        extent = 26,
        applyFrame = lib.ApplyFontPickerRow,
        resetFrame = lib.ResetPickerRow,
    })
    settingsBuilder:RegisterRowType("texture", {
        varType = "string",
        defaultValue = "",
        extent = 26,
        applyFrame = lib.ApplyTexturePickerRow,
        resetFrame = lib.ResetPickerRow,
    })
end

lib.Register(LibStub("LibSettingsBuilder-1.0", true))
