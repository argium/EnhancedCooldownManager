-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

-- LibSettingsBuilder: A standalone path-based settings builder for the
-- World of Warcraft Settings API.  Provides proxy controls, composite groups
-- and utility helpers.

--- Row or builder-level change hook fired after a value is written.
---@alias LibSettingsBuilderChangedCallback fun(ctx: LibSettingsBuilderCallbackContext, value: any)

--- Row-local post-set hook fired before `config.onChanged`.
---@alias LibSettingsBuilderRowSetCallback fun(ctx: LibSettingsBuilderCallbackContext, value: any)

--- Page lifecycle hook fired when Blizzard shows or hides a registered page.
---@alias LibSettingsBuilderPageLifecycleCallback fun()

--- Custom nested-path getter used by path-bound rows.
---@alias LibSettingsBuilderGetNestedValue fun(tbl: table, path: string): any

--- Custom nested-path setter used by path-bound rows.
---@alias LibSettingsBuilderSetNestedValue fun(tbl: table, path: string, value: any)

--- Callback context passed to row callbacks and `config.onChanged`.
---@class LibSettingsBuilderCallbackContext
---@field builder LibSettingsBuilderRuntime Gets the runtime instance that owns the registered page tree.
---@field category table Gets the Blizzard Settings category backing the active row.
---@field key string|number|nil Gets the handler-mode key for rows registered through `key`.
---@field page LibSettingsBuilderPageHandle|nil Gets the registered page handle that owns the row, when available.
---@field path string|nil Gets the resolved path used by path-bound rows.
---@field setting table|nil Gets the proxy setting object for persisted row kinds.
---@field spec LibSettingsBuilderRowConfig Gets the normalized row spec that triggered the callback.

--- Root registration config passed to `LSB.New(...)`.
--- Example (root page):
---     local lsb = LSB.New({
---         name = "My Addon",
---         onChanged = function(ctx) MyAddon:Refresh() end,
---         page = {
---             key = "about",
---             rows = { { type = "info", name = "Version", value = AddOnVersion } },
---         },
---     })
---@class LibSettingsBuilderConfig
---@field name string|nil Gets the root category display name.
---@field onChanged LibSettingsBuilderChangedCallback Gets the callback fired after a row setter completes.
---@field store table|(fun(): table)|nil Gets the store table or lazy provider used by path-bound rows.
---@field defaults table|(fun(): table)|nil Gets the defaults table or lazy provider used by path-bound rows.
---@field getNestedValue LibSettingsBuilderGetNestedValue|nil Gets the custom nested-path reader used by path-bound rows.
---@field setNestedValue LibSettingsBuilderSetNestedValue|nil Gets the custom nested-path writer used by path-bound rows.
---@field page LibSettingsBuilderPageConfig|nil Gets the optional root-owned page definition.
---@field sections LibSettingsBuilderSectionConfig[]|nil Gets the optional section definitions registered under the root category.

local MAJOR, MINOR = "LibSettingsBuilder-1.0", 6
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end

lib._loadState = { open = true }
lib._internal = {}
lib._pageLifecycleCallbacks = {}
lib._pageLifecycleHooked = false

local internal = lib._internal

--- Returns Blizzard's category-header `Defaults` button if the SettingsPanel
--- has been created and the settings list is available.
local function getCategoryDefaultsButton()
    local settingsList = SettingsPanel and SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
    local header = settingsList and settingsList.Header
    return header and header.DefaultsButton or nil
end

--- Replaces the category-header `Defaults` button click handler with `onClick`
--- and forces it enabled (or evaluates `enabledPredicate` when supplied) for as
--- long as the override is active. Returns a restore function the caller must
--- invoke when the page is hidden so other categories keep Blizzard's default
--- behavior.
function internal.installCategoryDefaultsOverride(onClick, enabledPredicate)
    local button = getCategoryDefaultsButton()
    if not button then
        return function() end
    end

    local originalOnClick = button:GetScript("OnClick")
    local originalEnabled = button:IsEnabled()

    local function applyEnabled()
        if enabledPredicate then
            button:SetEnabled(enabledPredicate() and true or false)
        else
            button:SetEnabled(true)
        end
    end

    button:SetScript("OnClick", function()
        if enabledPredicate and not enabledPredicate() then
            return
        end
        onClick()
        applyEnabled()
    end)
    applyEnabled()

    return function()
        if button:GetScript("OnClick") then
            button:SetScript("OnClick", originalOnClick)
        end
        button:SetEnabled(originalEnabled)
    end
end

--- Installs one-time hooks on SettingsPanel to fire page-level onShow/onHide
--- callbacks registered through the root/section/page API. Defers automatically if
--- SettingsPanel has not been created yet (Blizzard_Settings loads on demand).
local function installPageLifecycleHooks()    if lib._pageLifecycleHooked then
        return
    end

    if type(SettingsPanel) ~= "table" or type(SettingsPanel.DisplayCategory) ~= "function" then
        -- SettingsPanel not yet loaded; listen for ADDON_LOADED to retry.
        if lib._pageLifecycleDeferred or type(CreateFrame) ~= "function" then
            return
        end
        lib._pageLifecycleDeferred = true
        local f = CreateFrame("Frame")
        f:RegisterEvent("ADDON_LOADED")
        f:SetScript("OnEvent", function(self)
            if type(SettingsPanel) == "table" and type(SettingsPanel.DisplayCategory) == "function" then
                self:UnregisterAllEvents()
                installPageLifecycleHooks()
            end
        end)
        return
    end

    lib._pageLifecycleHooked = true

    -- DisplayCategory fires for both sidebar clicks and OpenToCategory.
    -- Retrieve the active category via GetCurrentCategory inside the hook.
    hooksecurefunc(SettingsPanel, "DisplayCategory", function(panel)
        local category = panel.GetCurrentCategory and panel:GetCurrentCategory() or nil
        local old = lib._activeLifecycleCategory
        if old == category then
            return
        end

        if old then
            local cbs = lib._pageLifecycleCallbacks[old]
            if cbs then
                if cbs._defaultsRestore then
                    cbs._defaultsRestore()
                    cbs._defaultsRestore = nil
                end
                if cbs.onHide then
                    cbs.onHide()
                end
            end
        end

        lib._activeLifecycleCategory = category
        if category then
            local cbs = lib._pageLifecycleCallbacks[category]
            if cbs then
                if cbs.onDefault then
                    cbs._defaultsRestore = internal.installCategoryDefaultsOverride(cbs.onDefault, cbs.onDefaultEnabled)
                end
                if cbs.onShow then
                    cbs.onShow()
                end
            end
        end
    end)

    SettingsPanel:HookScript("OnHide", function()
        local active = lib._activeLifecycleCategory
        if active then
            local cbs = lib._pageLifecycleCallbacks[active]
            if cbs then
                if cbs._defaultsRestore then
                    cbs._defaultsRestore()
                    cbs._defaultsRestore = nil
                end
                if cbs.onHide then
                    cbs.onHide()
                end
            end
        end
        lib._activeLifecycleCategory = nil
    end)
end

local function copyMixin(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

local function setInitializerExtent(initializer, extent)
    if initializer.SetExtent then
        return initializer:SetExtent(extent)
    end
    initializer.GetExtent = function()
        return extent
    end
end

local function getInitializerData(initializer)
    return initializer and (initializer._lsbData or (initializer.GetData and initializer:GetData())) or nil
end

local function getSettingVariable(setting)
    return setting and (setting._lsbVariable or setting._variable)
end

local function registerValueChangedCallback(frame, variable, callback, owner)
    local handles = frame and frame.cbrHandles
    if variable and handles and handles.SetOnValueChangedCallback then
        handles:SetOnValueChangedCallback(variable, callback, owner or frame)
    end
end

local function makeStableSortKey(value)
    local valueType = type(value)
    if valueType == "number" then
        return "1:" .. string.format("%020.10f", value)
    end
    if valueType == "boolean" then
        return value and "2:true" or "2:false"
    end
    return valueType .. ":" .. tostring(value):lower()
end

local function getOrderedValueEntries(values)
    local entries = {}
    if not values then
        return entries
    end

    for value, label in pairs(values) do
        entries[#entries + 1] = {
            value = value,
            label = label,
            labelSortKey = tostring(label):lower(),
            valueSortKey = makeStableSortKey(value),
        }
    end

    table.sort(entries, function(left, right)
        if left.labelSortKey == right.labelSortKey then
            return left.valueSortKey < right.valueSortKey
        end
        return left.labelSortKey < right.labelSortKey
    end)

    return entries
end

local function showFrame(frame)
    if frame and frame.Show then
        frame:Show()
    end
end

local function setTextureValue(texture, value)
    if not texture or not texture.SetTexture then
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

local DEFAULT_ACTION_BUTTON_HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local DEFAULT_ACTION_BUTTON_DISABLED_ALPHA = 0.4
local DEFAULT_SWATCH_CENTER_X = -73

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

    if texture.ClearAllPoints then
        texture:ClearAllPoints()
    end
    if texture.SetAllPoints then
        texture:SetAllPoints(button)
    end
    if alpha ~= nil and texture.SetAlpha then
        texture:SetAlpha(alpha)
    end
end

local function applyActionButtonTextures(button, action, enabled)
    if not button then
        return
    end

    local defaults = ensureActionButtonTextureDefaults(button)
    local textures = action and action.buttonTextures

    if button.SetText then
        button:SetText(textures and textures.normal and "" or (action and action.text or ""))
    end

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

        if button.SetAlpha then
            button:SetAlpha(enabled == false and (textures.disabledAlpha or DEFAULT_ACTION_BUTTON_DISABLED_ALPHA) or 1)
        end

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

    if button.SetAlpha then
        button:SetAlpha(1)
    end
end

local function setGameTooltipText(text, wrap)
    GameTooltip:SetText(text, 1, 1, 1, 1, wrap == true)
end

local function setSimpleTooltip(owner, text)
    if not owner or not owner.SetScript then
        return
    end

    owner:SetScript("OnEnter", nil)
    owner:SetScript("OnLeave", nil)

    if not text or text == "" then
        return
    end

    owner:SetScript("OnEnter", function(self)
        if not GameTooltip then
            return
        end

        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
        setGameTooltipText(text, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        if GameTooltip_Hide then
            GameTooltip_Hide()
        end
    end)
end

local function evaluateStaticOrFunction(value, ...)
    if type(value) == "function" then
        return value(...)
    end
    return value
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

local function createSubheaderTitle(parent, text)
    return createTitle(parent, "GameFontNormalSmall", 35, -8, text)
end

local function createHeaderTitle(parent, text)
    return createTitle(parent, "GameFontHighlightLarge", 7, -16, text)
end

--------------------------------------------------------------------------------
-- CanvasLayout: Vertical stacking engine for canvas subcategory pages.
-- Replicates Blizzard's Settings panel positioning so canvas pages are
-- visually indistinguishable from vertical-layout pages.
--
-- Measurements from Blizzard_SettingControls.xml/.lua:
--   Element height:      26   (all control types)
--   Section header:      45   (GameFontHighlightLarge at TOPLEFT 7, -16)
--   Label left offset:   indent + 37
--   Label right bound:   CENTER - 85
--   Control anchor:      CENTER - 80  (checkbox, slider, color swatch)
--   Button anchor:       CENTER - 40  (width 200)
--   Indent per level:    15
--------------------------------------------------------------------------------

internal.CanvasLayoutDefaults = {
    elementHeight = 26,
    headerHeight = 50,
    labelX = 37,
    controlCenterX = -80,
    buttonCenterX = -40,
    buttonWidth = 200,
    sliderWidth = 250,
    swatchCenterX = DEFAULT_SWATCH_CENTER_X,
    verifiedPatch = "Retail 12.0/12.1",
}
local CanvasLayout = {}
internal.CanvasLayout = CanvasLayout

local function getCanvasLayoutMetrics(layout)
    return layout._metrics or internal.CanvasLayoutDefaults
end

function CanvasLayout:_Advance(h)
    self.yPos = self.yPos - h
end

function CanvasLayout:_CreateRow(h)
    local metrics = getCanvasLayoutMetrics(self)
    h = h or metrics.elementHeight
    local row = CreateFrame("Frame", nil, self.frame)
    row:SetPoint("TOPLEFT", 0, self.yPos)
    row:SetPoint("RIGHT")
    row:SetHeight(h)
    self.elements[#self.elements + 1] = row
    self:_Advance(h)
    return row
end

function CanvasLayout:_AddLabel(row, text, fontObject)
    local metrics = getCanvasLayoutMetrics(self)
    local label = row:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    label:SetPoint("LEFT", metrics.labelX, 0)
    label:SetPoint("RIGHT", row, "CENTER", -85, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    label:SetText(text)
    row._label = label
    return label
end

--- Add a page header using Blizzard's SettingsListTemplate.Header.
--- Provides Title, Options_HorizontalDivider, and DefaultsButton.
---@return Frame row  (row._title, row._defaultsButton exposed)
function CanvasLayout:AddHeader(text)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow(metrics.headerHeight)
    local settingsList = CreateFrame("Frame", nil, row, "SettingsListTemplate")
    settingsList:SetAllPoints(row)
    settingsList.ScrollBox:Hide()
    settingsList.ScrollBar:Hide()
    settingsList.Header.Title:SetText(text)
    row._title = settingsList.Header.Title
    row._defaultsButton = settingsList.Header.DefaultsButton
    return row
end

--- Add vertical spacing.
function CanvasLayout:AddSpacer(height)
    self:_Advance(height)
end

--- Add a description / informational text row.
function CanvasLayout:AddDescription(text, fontObject)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    local label = row:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    label:SetPoint("LEFT", metrics.labelX, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -10, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    row._text = label
    return row
end

--- Add a color swatch row (label + clickable swatch).
---@return Frame row, Button swatch
function CanvasLayout:AddColorSwatch(labelText)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    self:_AddLabel(row, labelText)
    local swatch = internal.createColorSwatch(row)
    swatch:SetPoint("LEFT", row, "CENTER", metrics.swatchCenterX, 0)
    row._swatch = swatch
    return row, swatch
end

--- Add a slider row (label + MinimalSliderWithSteppers).
---@return Frame row, Slider slider, FontString valueText
function CanvasLayout:AddSlider(labelText, min, max, step)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    self:_AddLabel(row, labelText)
    local slider = CreateFrame("Slider", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetWidth(metrics.sliderWidth)
    slider:SetPoint("LEFT", row, "CENTER", metrics.controlCenterX, 3)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    local valueText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    valueText:SetWidth(40)
    valueText:SetJustifyH("LEFT")
    row._slider = slider
    row._valueText = valueText
    return row, slider, valueText
end

--- Add a button row (label + UIPanelButton).
---@return Frame row, Button button
function CanvasLayout:AddButton(labelText, buttonText)
    local metrics = getCanvasLayoutMetrics(self)
    local row = self:_CreateRow()
    self:_AddLabel(row, labelText)
    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetSize(metrics.buttonWidth, 26)
    button:SetPoint("LEFT", row, "CENTER", metrics.buttonCenterX, 0)
    button:SetText(buttonText)
    row._button = button
    return row, button
end

--- Add a scroll list that fills the remaining vertical space.
---@return Frame scrollBox, EventFrame scrollBar, table view
function CanvasLayout:AddScrollList(elementExtent)
    local metrics = getCanvasLayoutMetrics(self)
    local scrollBox = CreateFrame("Frame", nil, self.frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", metrics.labelX, self.yPos)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, 10)
    local scrollBar = CreateFrame("EventFrame", nil, self.frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(elementExtent)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
    return scrollBox, scrollBar, view
end

--------------------------------------------------------------------------------
-- Static utilities (shared across all instances)
--------------------------------------------------------------------------------

--- Create a color swatch button using Blizzard's SettingsColorSwatchTemplate.
--- Inherits ColorSwatchTemplate (SwatchBg/InnerBorder/Color layers) and
--- SettingsColorSwatchMixin (hover effects, color picker integration).
---@param parent Frame
---@return Button swatch  (swatch._tex points to swatch.Color for backward compat)
local function createColorSwatch(parent)
    local swatch = CreateFrame("Button", nil, parent, "SettingsColorSwatchTemplate")
    swatch._tex = swatch.Color
    if swatch.EnableMouse then
        swatch:EnableMouse(true)
    end
    if swatch.RegisterForClicks then
        swatch:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    end
    if swatch.SetPropagateMouseClicks then
        swatch:SetPropagateMouseClicks(false)
    end
    return swatch
end
internal.createColorSwatch = createColorSwatch

--------------------------------------------------------------------------------
-- Path accessors: built-in dot-path resolution with numeric key support
--------------------------------------------------------------------------------

local function defaultGetNestedValue(tbl, path)
    local current = tbl
    for segment in path:gmatch("[^.]+") do
        if type(current) ~= "table" then
            return nil
        end
        local val = current[segment]
        if val == nil then
            local num = tonumber(segment)
            if num then
                val = current[num]
            end
        end
        current = val
    end
    return current
end

local function defaultSetNestedValue(tbl, path, value)
    local current, lastKey = tbl, nil
    for segment in path:gmatch("[^.]+") do
        if lastKey then
            local resolved = lastKey
            local existing = current[lastKey]
            if existing == nil then
                local num = tonumber(lastKey)
                if num and current[num] ~= nil then
                    resolved = num
                    existing = current[num]
                end
            end
            if type(existing) ~= "table" then
                existing = {}
                current[resolved] = existing
            end
            current = existing
        end
        lastKey = segment
    end
    assert(lastKey, "defaultSetNestedValue: path is required")
    local resolved = lastKey
    if current[lastKey] == nil then
        local num = tonumber(lastKey)
        if num then
            resolved = num
        end
    end
    current[resolved] = value
end

local function createStoreAdapter(config)
    local getNested = config.getNestedValue or defaultGetNestedValue
    local setNested = config.setNestedValue or defaultSetNestedValue

    return {
        resolve = function(self, path)
            return {
                get = function()
                    return getNested(config.getStore(), path)
                end,
                set = function(value)
                    setNested(config.getStore(), path, value)
                end,
                default = getNested(config.getDefaults(), path),
            }
        end,
        read = function(self, path)
            return getNested(config.getStore(), path)
        end,
    }
end

local function defaultSliderFormatter(value)
    return value == math.floor(value) and tostring(math.floor(value)) or string.format("%.1f", value)
end

local function makeVarPrefixFromName(name)
    local words = {}
    for word in tostring(name or ""):gmatch("[A-Za-z0-9]+") do
        words[#words + 1] = word
    end

    local prefix = ""
    if #words > 1 then
        for _, word in ipairs(words) do
            prefix = prefix .. word:sub(1, 1):upper()
        end
    elseif words[1] then
        prefix = words[1]:upper():gsub("[^A-Z0-9]", "")
    end

    if prefix == "" then
        prefix = "LSB"
    end

    return prefix
end

local MODIFIER_KEYS = { "category", "disabled", "hidden", "layout" }

local COMMON_SPEC_FIELDS = {
    path = true,
    name = true,
    tooltip = true,
    category = true,
    onSet = true,
    getTransform = true,
    setTransform = true,
    disabled = true,
    hidden = true,
    layout = true,
    type = true,
    desc = true,
    get = true,
    set = true,
    key = true,
    default = true,
}

local EXTRA_FIELDS_BY_TYPE = {
    checkbox = {},
    slider = { min = true, max = true, step = true, formatter = true },
    dropdown = { values = true, scrollHeight = true },
    color = {},
    input = {
        debounce = true,
        maxLetters = true,
        numeric = true,
        onTextChanged = true,
        resolveText = true,
        width = true,
    },
    custom = { template = true, varType = true },
}

function internal.makeVarName(self, spec)
    local id = spec.key or spec.path
    return self._config.varPrefix .. "_" .. tostring(id):gsub("%.", "_")
end

---@param self LibSettingsBuilderRuntime
---@param spec LibSettingsBuilderRowConfig|table
function internal.createCallbackContext(self, spec, setting)
    return {
        builder = self,
        category = internal.resolveCategory(self, spec),
        key = spec.key,
        page = spec._page and spec._page._handle,
        path = spec.path,
        setting = setting,
        spec = spec,
    }
end

function internal.resolveCategory(self, spec)
    return spec.category or self._currentSubcategory or self._rootCategory
end

function internal.registerCategoryRefreshable(self, category, initializer)
    if not category or not initializer then
        return
    end

    local refreshables = self._categoryRefreshables[category]
    if not refreshables then
        refreshables = {}
        self._categoryRefreshables[category] = refreshables
    end

    for _, existing in ipairs(refreshables) do
        if existing == initializer then
            return
        end
    end

    refreshables[#refreshables + 1] = initializer
end

function internal.postSet(self, spec, value, setting)
    local ctx = internal.createCallbackContext(self, spec, setting)
    if spec.onSet then
        spec.onSet(ctx, value)
    end
    self._config.onChanged(ctx, value)
    internal.reevaluateReactiveControls(self)
end

function internal.resolveBinding(self, spec)
    local hasPath = spec.path ~= nil
    local hasHandler = spec.get ~= nil or spec.set ~= nil

    assert(not (hasPath and hasHandler), "spec cannot have both path and get/set")

    if hasHandler then
        assert(spec.get, "handler mode requires get")
        assert(spec.set, "handler mode requires set")
        assert(spec.key, "handler mode requires key")
        return { get = spec.get, set = spec.set, default = spec.default }
    end

    assert(hasPath, "spec must have either path or get/set")
    assert(self._adapter, "path mode requires store/defaults on the builder")

    local binding = self._adapter:resolve(spec.path)
    if spec.default ~= nil then
        binding.default = spec.default
    end
    return binding
end

function internal.makeProxySetting(self, spec, varType, defaultFallback, binding)
    local variable = internal.makeVarName(self, spec)
    local category = internal.resolveCategory(self, spec)
    local setting

    binding = binding or internal.resolveBinding(self, spec)

    local function getter()
        local value = binding.get()
        if spec.getTransform then
            value = spec.getTransform(value)
        end
        return value
    end

    local function applyValue(value)
        if spec.setTransform then
            value = spec.setTransform(value)
        end
        binding.set(value)
        return value
    end

    local function setter(value)
        value = applyValue(value)
        internal.postSet(self, spec, value, setting)
    end

    local function setValueNoCallback(_, value)
        value = applyValue(value)
        self._config.onChanged(internal.createCallbackContext(self, spec, setting), value)
        internal.reevaluateReactiveControls(self)
    end

    local defaultValue = binding.default
    if spec.getTransform then
        defaultValue = spec.getTransform(defaultValue)
    end
    if defaultValue == nil then
        defaultValue = defaultFallback
    end

    setting = Settings.RegisterProxySetting(category, variable, varType, spec.name, defaultValue, getter, setter)
    setting.SetValueNoCallback = setValueNoCallback
    setting._lsbVariable = variable

    return setting, category
end

function internal.propagateModifiers(self, target, source)
    for _, key in ipairs(MODIFIER_KEYS) do
        if target[key] == nil then
            target[key] = source[key]
        end
    end
end

function internal.validateSpecFields(self, controlType, spec)
    if not LSB_DEBUG then
        return
    end

    local allowed = EXTRA_FIELDS_BY_TYPE[controlType]
    if not allowed then
        return
    end

    for key in pairs(spec) do
        if not COMMON_SPEC_FIELDS[key] and not allowed[key] then
            print(
                "|cffFF8800LibSettingsBuilder WARNING:|r Unknown spec field '"
                    .. tostring(key)
                    .. "' on "
                    .. controlType
                    .. " control '"
                    .. tostring(spec.name or spec.path)
                    .. "'"
            )
        end
    end
end

function internal.setCanvasInteractive(self, frame, enabled)
    if frame.SetEnabled then
        frame:SetEnabled(enabled)
    end
    if frame.EnableMouse then
        frame:EnableMouse(enabled)
    end
    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            internal.setCanvasInteractive(self, children[i], enabled)
        end
    end
end

function internal.isParentEnabled(self, spec)
    if not spec._parentInitializer then
        return true
    end
    if spec._parentPredicate then
        return spec._parentPredicate()
    end
    if not spec._parentInitializer.GetSetting then
        return true
    end

    local setting = spec._parentInitializer:GetSetting()
    if not setting then
        return true
    end

    return setting:GetValue()
end

function internal.isControlEnabled(self, spec)
    if spec.disabled and spec.disabled() then
        return false
    end
    return internal.isParentEnabled(self, spec)
end

function internal.applyCanvasState(self, canvas, enabled)
    if canvas.SetAlpha then
        canvas:SetAlpha(enabled and 1 or 0.5)
    end
    internal.setCanvasInteractive(self, canvas, enabled)
end

function internal.reevaluateReactiveControls(self)
    local panel = SettingsPanel
    if panel and panel:IsShown() then
        local settingsList = panel:GetSettingsList()
        if settingsList and settingsList.ScrollBox then
            settingsList.ScrollBox:ForEachFrame(function(frame)
                if frame.EvaluateState then
                    frame:EvaluateState()
                end
            end)
        end
    end

    for _, entry in ipairs(self._reactiveControls) do
        local spec = entry[2]
        if spec.canvas then
            internal.applyCanvasState(self, spec.canvas, internal.isControlEnabled(self, spec))
        end
    end
end

function internal.applyEnabledState(self, initializer, spec)
    local enabled = internal.isControlEnabled(self, spec)
    if initializer.SetEnabled then
        initializer:SetEnabled(enabled)
    end
    if spec.canvas then
        internal.applyCanvasState(self, spec.canvas, enabled)
    end
    return enabled
end

function internal.applyModifiers(self, initializer, spec)
    if not initializer then
        return
    end

    if spec.disabled or spec.canvas or spec._parentInitializer then
        initializer:AddModifyPredicate(function()
            return internal.applyEnabledState(self, initializer, spec)
        end)
        internal.applyEnabledState(self, initializer, spec)
    end

    if spec._parentInitializer then
        initializer:SetParentInitializer(spec._parentInitializer, function()
            return internal.isParentEnabled(self, spec)
        end)
    end

    if spec.hidden then
        initializer:AddShownPredicate(function()
            return not spec.hidden()
        end)
    end

    if spec.canvas then
        self._reactiveControls[#self._reactiveControls + 1] = { initializer, spec }
    end
end

function internal.colorTableToHex(self, tbl)
    if not tbl then
        return "FFFFFFFF"
    end
    return string.format(
        "%02X%02X%02X%02X",
        math.floor((tbl.a or 1) * 255 + 0.5),
        math.floor((tbl.r or 1) * 255 + 0.5),
        math.floor((tbl.g or 1) * 255 + 0.5),
        math.floor((tbl.b or 1) * 255 + 0.5)
    )
end

function internal.storeCategory(self, name, category, layout)
    self._subcategories[name] = category
    self._subcategoryNames[category] = name
    self._layouts[category] = layout
    return category
end

internal.defaultSliderFormatter = defaultSliderFormatter

--- Creates a LibSettingsBuilder runtime instance and optionally registers the full declarative tree.
--- `config.onChanged(ctx, value)` runs after any row-local `onSet(ctx, value)` hook.
--- Path-bound rows resolve against `config.store` / `config.defaults`; handler-bound rows use row-local `get`, `set`, and `key` callbacks.
---@overload fun(config: LibSettingsBuilderConfig): LibSettingsBuilderRuntime
---@param selfOrConfig LibSettingsBuilderConfig|table
---@param maybeConfig LibSettingsBuilderConfig|nil
---@return LibSettingsBuilderRuntime lsb
function lib.New(selfOrConfig, maybeConfig)
    local config = maybeConfig or selfOrConfig
    assert(type(config) == "table", "LibSettingsBuilder.New: config table is required")

    assert(config.varPrefix == nil, "LibSettingsBuilder: varPrefix is not part of the v2 config")
    assert(config.pathAdapter == nil, "LibSettingsBuilder: pathAdapter is not part of the v2 config")
    assert(config.compositeDefaults == nil, "LibSettingsBuilder: compositeDefaults is not part of the v2 config")
    config.varPrefix = makeVarPrefixFromName(config.name)
    assert(config.onChanged, "LibSettingsBuilder: onChanged is required")

    local adapter
    if config.store ~= nil then
        local getStore = type(config.store) == "function" and config.store or function()
            return config.store
        end
        local getDefaults = type(config.defaults) == "function" and config.defaults or function()
            return config.defaults
        end
        adapter = createStoreAdapter({
            getDefaults = getDefaults,
            getNestedValue = config.getNestedValue,
            getStore = getStore,
            setNestedValue = config.setNestedValue,
        })
    end

    local lsb = setmetatable({
        _config = config,
        _adapter = adapter,
        _rootCategory = nil,
        _rootCategoryName = nil,
        _rootRegistered = nil,
        _registeredRootPage = nil,
        _currentSubcategory = nil,
        _subcategories = {},
        _subcategoryNames = {},
        _layouts = {},
        _reactiveControls = {},
        _categoryRefreshables = {},
        _pages = {},
        _pageList = {},
        _sectionList = {},
        _sections = {},
        _nextRootPageSequence = 0,
        _nextSectionSequence = 0,
        name = nil,
    }, { __index = lib._publicApi or lib })

    if config.name ~= nil then
        lsb:_initializeRoot(config.name)
    end

    if config.page or config.sections then
        lsb:_registerTree({
            page = config.page,
            sections = config.sections,
        })
    end

    return lsb
end

-- Export local functions to internal for cross-file access
internal.installPageLifecycleHooks = installPageLifecycleHooks
internal.copyMixin = copyMixin
internal.setInitializerExtent = setInitializerExtent
internal.getInitializerData = getInitializerData
internal.getSettingVariable = getSettingVariable
internal.registerValueChangedCallback = registerValueChangedCallback
internal.getOrderedValueEntries = getOrderedValueEntries
internal.showFrame = showFrame
internal.setTextureValue = setTextureValue
internal.setGameTooltipText = setGameTooltipText
internal.setSimpleTooltip = setSimpleTooltip
internal.applyActionButtonTextures = applyActionButtonTextures
internal.evaluateStaticOrFunction = evaluateStaticOrFunction
internal.getCanvasLayoutMetrics = getCanvasLayoutMetrics
internal.defaultSwatchCenterX = DEFAULT_SWATCH_CENTER_X
internal.createHeaderTitle = createHeaderTitle
internal.createSubheaderTitle = createSubheaderTitle
