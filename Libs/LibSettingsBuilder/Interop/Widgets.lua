-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local interop = lib._internal.interop

local DEFAULT_ACTION_BUTTON_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local DEFAULT_ACTION_BUTTON_DISABLED_ALPHA = 0.4
interop.defaultSwatchCenterX = -73

function interop.setInitializerExtent(initializer, extent)
    if initializer.SetExtent then
        return initializer:SetExtent(extent)
    end
    initializer.GetExtent = function()
        return extent
    end
end

function interop.getInitializerData(initializer)
    return initializer and (initializer._lsbData or (initializer.GetData and initializer:GetData())) or nil
end

function interop.getSettingVariable(setting)
    return setting and (setting._lsbVariable or setting._variable)
end

function interop.registerValueChangedCallback(frame, variable, callback, owner)
    local handles = frame and frame.cbrHandles
    if variable and handles and handles.SetOnValueChangedCallback then
        handles:SetOnValueChangedCallback(variable, callback, owner or frame)
    end
end

function interop.setInitializerSetting(initializer, setting)
    if initializer and initializer.SetSetting then
        initializer:SetSetting(setting)
    end
end

function interop.setCanvasInteractive(frame, enabled)
    if frame.SetEnabled then
        frame:SetEnabled(enabled)
    end
    frame:EnableMouse(enabled)
    local children = { frame:GetChildren() }
    for i = 1, #children do
        interop.setCanvasInteractive(children[i], enabled)
    end
end

function interop.applyCanvasState(canvas, enabled)
    canvas:SetAlpha(enabled and 1 or 0.5)
    interop.setCanvasInteractive(canvas, enabled)
end

function interop.applyInitializerEnabledState(initializer, modifiers)
    local enabled = modifiers.isEnabled()
    if initializer.SetEnabled then
        initializer:SetEnabled(enabled)
    end
    if modifiers.canvas then
        interop.applyCanvasState(modifiers.canvas, enabled)
    end
    return enabled
end

function interop.applyInitializerModifiers(initializer, modifiers)
    if not initializer then
        return
    end

    if modifiers.disabled or modifiers.canvas or modifiers.parentInitializer then
        initializer:AddModifyPredicate(function()
            return interop.applyInitializerEnabledState(initializer, modifiers)
        end)
        interop.applyInitializerEnabledState(initializer, modifiers)
    end

    if modifiers.parentInitializer then
        initializer:SetParentInitializer(modifiers.parentInitializer, modifiers.isParentEnabled)
    end

    if modifiers.hidden then
        initializer:AddShownPredicate(function()
            return not modifiers.hidden()
        end)
    end
end

function interop.refreshInitializer(initializer)
    if initializer._lsbActiveFrame and initializer._lsbRefreshFrame then
        initializer._lsbRefreshFrame(initializer._lsbActiveFrame, initializer)
    end
end

function interop.refreshSettingsFrame(frame)
    local initializer = frame.GetElementData and frame:GetElementData() or frame._lsbInitializer
    if frame.EvaluateState then
        frame:EvaluateState()
    end
    if initializer and initializer._lsbRefreshFrame then
        initializer._lsbRefreshFrame(frame, initializer)
    end
end

function interop.showFrame(frame)
    if frame then
        frame:Show()
    end
end

function interop.setTextureValue(texture, value)
    if not texture then
        return
    end

    if value == nil then
        texture:SetTexture(nil)
        return
    end

    if type(value) == "number" and texture.SetToFileData then
        texture:SetToFileData(value)
        return
    end

    texture:SetTexture(value)
end

function interop.setGameTooltipText(text, wrap)
    GameTooltip:SetText(text, 1, 1, 1, 1, wrap == true)
end

function interop.setSimpleTooltip(owner, text)
    if not owner then
        return
    end

    owner:SetScript("OnEnter", nil)
    owner:SetScript("OnLeave", nil)

    if not text or text == "" then
        return
    end

    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        interop.setGameTooltipText(text, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)
end

local function createTitle(parent, template, x, y, text, fontObject)
    local title = parent:CreateFontString(nil, "OVERLAY", template)
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    if fontObject then
        title:SetFontObject(fontObject)
    end
    if text ~= nil then
        title:SetText(text)
    end
    title:Show()
    return title
end

function interop.createSubheaderTitle(parent, text)
    return createTitle(parent, "GameFontNormalSmall", 35, -8, text)
end

function interop.createHeaderTitle(parent, text)
    return createTitle(parent, "GameFontHighlightLarge", 7, -16, text)
end

function interop.createColorSwatch(parent)
    local swatch = CreateFrame("Button", nil, parent, "SettingsColorSwatchTemplate")
    swatch._tex = swatch.Color
    swatch:EnableMouse(true)
    swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    swatch:SetPropagateMouseClicks(false)
    return swatch
end

local function getButtonTextureValue(button, getterName)
    local getter = button and button[getterName]
    if type(getter) ~= "function" then
        return nil
    end

    local texture = getter(button)
    if texture and texture.GetTexture then
        return texture:GetTexture()
    end

    return texture
end

local function ensureActionButtonTextureDefaults(button)
    if button._lsbActionButtonTextureDefaults then
        return button._lsbActionButtonTextureDefaults
    end

    local defaults = {
        disabled = getButtonTextureValue(button, "GetDisabledTexture"),
        highlight = getButtonTextureValue(button, "GetHighlightTexture"),
        normal = getButtonTextureValue(button, "GetNormalTexture"),
        pushed = getButtonTextureValue(button, "GetPushedTexture"),
    }

    button._lsbActionButtonTextureDefaults = defaults
    return defaults
end

local function setButtonTextureState(button, setterName, getterName, value, blendMode, alpha)
    local setter = button and button[setterName]
    if type(setter) ~= "function" then
        return
    end

    if blendMode ~= nil then
        setter(button, value, blendMode)
    else
        setter(button, value)
    end

    local getter = button and button[getterName]
    if type(getter) ~= "function" then
        return
    end

    local texture = getter(button)
    if not texture then
        return
    end

    texture:ClearAllPoints()
    texture:SetAllPoints(button)
    if alpha ~= nil then
        texture:SetAlpha(alpha)
    end
end

function interop.applyActionButtonTextures(button, action, enabled)
    if not button then
        return
    end

    local defaults = ensureActionButtonTextureDefaults(button)
    local textures = action and action.buttonTextures

    button:SetText(textures and textures.normal and "" or (action and action.text or ""))

    if textures and textures.normal then
        setButtonTextureState(button, "SetNormalTexture", "GetNormalTexture", textures.normal, nil, 1)
        setButtonTextureState(button, "SetPushedTexture", "GetPushedTexture", textures.pushed or textures.normal, nil, 1)
        setButtonTextureState(button, "SetDisabledTexture", "GetDisabledTexture", textures.disabled or textures.normal, nil, 1)

        local highlight = textures.highlight
        if highlight == nil then
            highlight = DEFAULT_ACTION_BUTTON_HIGHLIGHT
        end
        setButtonTextureState(
            button,
            "SetHighlightTexture",
            "GetHighlightTexture",
            highlight,
            highlight and "ADD" or nil,
            textures.highlightAlpha or 0.25
        )

        button:SetAlpha(enabled == false and (textures.disabledAlpha or DEFAULT_ACTION_BUTTON_DISABLED_ALPHA) or 1)
        button._lsbUsesActionButtonTextures = true
        return
    end

    if button._lsbUsesActionButtonTextures then
        setButtonTextureState(button, "SetNormalTexture", "GetNormalTexture", defaults.normal)
        setButtonTextureState(button, "SetPushedTexture", "GetPushedTexture", defaults.pushed)
        setButtonTextureState(button, "SetDisabledTexture", "GetDisabledTexture", defaults.disabled)
        setButtonTextureState(button, "SetHighlightTexture", "GetHighlightTexture", defaults.highlight)
        button._lsbUsesActionButtonTextures = nil
    end

    button:SetAlpha(1)
end
