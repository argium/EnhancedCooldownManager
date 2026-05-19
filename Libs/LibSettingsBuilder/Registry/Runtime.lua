-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

--- No-arg predicate used by declarative `disabled` and `hidden` fields.
---@alias LibSettingsBuilderPredicate boolean|fun(): boolean

--- Dropdown value source used by `dropdown` rows.
---@alias LibSettingsBuilderDropdownValues table<any, string>|fun(): table<any, string>

--- Inline slider label formatter used by `slider` rows.
---@alias LibSettingsBuilderSliderFormatter fun(value: number): string

--- Button row callback.
---@alias LibSettingsBuilderButtonClickCallback fun(ctx: LibSettingsBuilderCallbackContext)

--- Input preview resolver.
---@alias LibSettingsBuilderInputResolveTextCallback fun(value: string, setting: table, frame: Frame): string|nil

--- Input text-change hook.
---@alias LibSettingsBuilderInputTextChangedCallback fun(text: string, setting: table, frame: Frame)

--- Page-actions button callback.
---@alias LibSettingsBuilderPageActionClickCallback fun(action: LibSettingsBuilderPageActionConfig, frame: Frame)

--- Dynamic flat-list provider.
---@alias LibSettingsBuilderListItemsProvider fun(frame: Frame): table[]

--- Dynamic grouped-list provider.
---@alias LibSettingsBuilderSectionListProvider fun(frame: Frame): table[]

--- Canonical declarative row kinds accepted by `config.page.rows` and section page rows.
---@alias LibSettingsBuilderRowKind
---| "border"
---| "button"
---| "canvas"
---| "checkbox"
---| "checkboxList"
---| "color"
---| "colorList"
---| "custom"
---| "dropdown"
---| "fontOverride"
---| "header"
---| "heightOverride"
---| "info"
---| "input"
---| "list"
---| "pageActions"
---| "sectionList"
---| "slider"
---| "subheader"

--- Dynamic list presets supported by `type = "list"` rows.
---@alias LibSettingsBuilderListVariant
---| "editor"
---| "swatch"

--- Registered section metadata returned by `lsb:GetSection(...)`.
---@class LibSettingsBuilderSectionHandle
---@field key string Gets the stable section key.
---@field name string Gets the section display name.
---@field path string Gets the base path prefix applied to child pages and rows.

--- Plain page handle returned by `lsb:GetRootPage()` and `lsb:GetPage(...)`.
---@class LibSettingsBuilderPageHandle
---@field GetId fun(self: LibSettingsBuilderPageHandle): string Gets the Blizzard Settings category ID for this registered page.
---@field Refresh fun(self: LibSettingsBuilderPageHandle) Refreshes visible rows and dynamic content for this registered page.

--- Runtime object returned by `LSB.New(...)`.
---@class LibSettingsBuilderRuntime
---@field GetSection fun(self: LibSettingsBuilderRuntime, key: string): LibSettingsBuilderSectionHandle|nil Gets the registered section metadata by key.
---@field GetRootPage fun(self: LibSettingsBuilderRuntime): LibSettingsBuilderPageHandle|nil Gets the registered root page handle.
---@field GetPage fun(self: LibSettingsBuilderRuntime, sectionKey: string, pageKey: string): LibSettingsBuilderPageHandle|nil Gets the registered section page handle by section and page key.
---@field HasCategory fun(self: LibSettingsBuilderRuntime, category: table|nil): boolean Gets whether this runtime owns the supplied Blizzard Settings category.

--- Declarative page definition registered under the root category or a section.
---@class LibSettingsBuilderPageConfig
---@field key string Gets the stable page key within its owner.
---@field name string|nil Gets the page display name; defaults to the root or section name when omitted.
---@field path string|nil Gets the optional base path prefix prepended to child path-bound rows.
---@field rows LibSettingsBuilderRowConfig[] Gets the declarative row array registered on the page.
---@field onShow LibSettingsBuilderPageLifecycleCallback|nil Gets the callback fired when Blizzard shows this page.
---@field onHide LibSettingsBuilderPageLifecycleCallback|nil Gets the callback fired when Blizzard hides this page.
---@field onDefault fun()|nil Gets the callback invoked when the user clicks the Blizzard category-header `Defaults` button while this page is active. When supplied, the library replaces the button's default reset behavior for the duration the page is shown.
---@field onDefaultEnabled fun(): boolean|nil Gets the predicate that controls whether the `Defaults` button is enabled while this page is active. Defaults to always-enabled when `onDefault` is supplied.
---@field disabled LibSettingsBuilderPredicate|nil Gets the page-level disabled predicate propagated to child rows.
---@field hidden LibSettingsBuilderPredicate|nil Gets the page-level hidden predicate propagated to child rows.
---@field order number|nil Gets the sort order used when a section declares multiple pages.
---@field useSectionCategory boolean|nil Gets whether a multi-page section page is materialized on the section category instead of under a child category.

--- Declarative section definition registered under `config.sections`.
--- Example (section page):
---     {
---         key = "general",
---         name = "General",
---         pages = {
---             {
---                 key = "main",
---                 rows = { { type = "checkbox", path = "enabled", name = "Enable" } },
---             },
---         },
---     }
---@class LibSettingsBuilderSectionConfig
---@field key string Gets the stable section key.
---@field name string Gets the section display name.
---@field path string|nil Gets the optional base path prefix; defaults to `key`.
---@field order number|nil Gets the sort order among sibling sections.
---@field pages LibSettingsBuilderPageConfig[] Gets the page definitions registered under this section.

--- Shared fields accepted by all declarative row kinds.
---@class LibSettingsBuilderRowBase
---@field type LibSettingsBuilderRowKind Gets the canonical row kind to register.
---@field id string|number|nil Gets the optional per-page row identifier.
---@field name string|nil Gets the primary display label when the row kind uses one.
---@field tooltip string|nil Gets the tooltip text shown for the row or control.
---@field disabled LibSettingsBuilderPredicate|nil Gets the disabled predicate reevaluated during row refreshes.
---@field hidden LibSettingsBuilderPredicate|nil Gets the hidden predicate reevaluated during row refreshes.

--- Shared binding fields for persisted row kinds.
--- Use either path mode (`path`) or handler mode (`key` + `get` + `set`), never both.
--- Example (path-bound row):
---     { type = "checkbox", path = "general.enabled", name = "Enable" }
--- Example (handler-bound row):
---     {
---         type = "input",
---         key = "draftSpellId",
---         name = "Spell ID",
---         get = function() return draft.spellIdText end,
---         set = function(value) draft.spellIdText = value or "" end,
---     }
---@class LibSettingsBuilderBindableRowBase: LibSettingsBuilderRowBase
---@field path string|nil Gets the dot-path resolved against `config.store` and `config.defaults`.
---@field key string|number|nil Gets the stable handler key used when the row is not path-bound.
---@field default any Gets the default value used when the binding does not provide one.
---@field get (fun(): any)|nil Gets the handler-mode getter callback.
---@field set fun(value: any)|nil Gets the handler-mode setter callback.
---@field getTransform (fun(value: any): any)|nil Gets the read transform applied before the control sees the stored value.
---@field setTransform (fun(value: any): any)|nil Gets the write transform applied before the value is stored.
---@field onSet LibSettingsBuilderRowSetCallback|nil Gets the row-local callback fired before `config.onChanged`.

--- Shared fields for composite rows that always consume a path prefix.
---@class LibSettingsBuilderPathRowBase: LibSettingsBuilderRowBase
---@field path string Gets the dot-path prefix consumed by this composite row.

--- Child definition used by `checkboxList` and `colorList` rows.
---@class LibSettingsBuilderCompositeListDef
---@field key string|number Gets the child key appended to the parent row path.
---@field name string Gets the child row label.
---@field tooltip string|nil Gets the child row tooltip.

--- Action button definition used by `pageActions` rows.
---@class LibSettingsBuilderPageActionConfig
---@field name string|nil Gets the fallback button label when `text` is omitted.
---@field text string|nil Gets the button label.
---@field width number|nil Gets the button width.
---@field height number|nil Gets the button height.
---@field buttonTextures table|nil Gets optional full-button texture states.
---@field iconTexture string|number|nil Gets the optional centered icon texture drawn over the default button chrome.
---@field iconSize number|nil Gets the optional centered icon size.
---@field iconAlpha number|nil Gets the optional enabled icon alpha.
---@field disabledIconAlpha number|nil Gets the optional disabled icon alpha.
---@field enabled boolean|(fun(action: LibSettingsBuilderPageActionConfig, frame: Frame): boolean|nil)|nil Gets the enabled predicate or static enabled flag.
---@field hidden boolean|(fun(action: LibSettingsBuilderPageActionConfig, frame: Frame): boolean|nil)|nil Gets the hidden predicate or static hidden flag.
---@field tooltip string|(fun(action: LibSettingsBuilderPageActionConfig, frame: Frame): string|nil)|nil Gets the tooltip text or tooltip resolver.
---@field onClick LibSettingsBuilderPageActionClickCallback|nil Gets the click callback.

---@class LibSettingsBuilderCheckboxRowConfig: LibSettingsBuilderBindableRowBase
---@field type "checkbox" Gets the checkbox row kind.

---@class LibSettingsBuilderSliderRowConfig: LibSettingsBuilderBindableRowBase
---@field type "slider" Gets the slider row kind.
---@field min number Gets the minimum slider value.
---@field max number Gets the maximum slider value.
---@field step number|nil Gets the slider step size.
---@field formatter LibSettingsBuilderSliderFormatter|nil Gets the inline value formatter.

---@class LibSettingsBuilderDropdownRowConfig: LibSettingsBuilderBindableRowBase
---@field type "dropdown" Gets the dropdown row kind.
---@field values LibSettingsBuilderDropdownValues Gets the dropdown value table or provider.
---@field scrollHeight number|nil Gets the optional scrollable menu height.
---@field varType any Gets the optional `Settings.VarType` override.

---@class LibSettingsBuilderColorRowConfig: LibSettingsBuilderBindableRowBase
---@field type "color" Gets the color-swatch row kind.

---@class LibSettingsBuilderInputRowConfig: LibSettingsBuilderBindableRowBase
---@field type "input" Gets the text-input row kind.
---@field debounce number|nil Gets the preview debounce in seconds.
---@field maxLetters number|nil Gets the maximum edit-box length.
---@field numeric boolean|nil Gets whether the edit box only accepts numeric input.
---@field onTextChanged LibSettingsBuilderInputTextChangedCallback|nil Gets the callback fired after the new text is written.
---@field resolveText LibSettingsBuilderInputResolveTextCallback|nil Gets the preview-text resolver shown beneath the edit box.
---@field width number|nil Gets the edit-box width.

---@class LibSettingsBuilderCustomRowConfig: LibSettingsBuilderBindableRowBase
---@field type "custom" Gets the XML-template-backed custom row kind.
---@field template string Gets the XML template name registered with Blizzard's Settings API.
---@field varType any Gets the optional `Settings.VarType` override.

---@class LibSettingsBuilderButtonRowConfig: LibSettingsBuilderRowBase
---@field type "button" Gets the button row kind.
---@field buttonText string|nil Gets the button label; defaults to `name`.
---@field confirm boolean|string|nil Gets whether the row shows a confirmation dialog, or the confirmation text to use.
---@field onClick LibSettingsBuilderButtonClickCallback Gets the click callback.

---@class LibSettingsBuilderHeaderRowConfig: LibSettingsBuilderRowBase
---@field type "header" Gets the header row kind.
---@field name string Gets the header label.

---@class LibSettingsBuilderSubheaderRowConfig: LibSettingsBuilderRowBase
---@field type "subheader" Gets the subheader row kind.
---@field name string Gets the subheader label.

---@class LibSettingsBuilderInfoRowConfig: LibSettingsBuilderRowBase
---@field type "info" Gets the informational row kind.
---@field value string|number|boolean|(fun(frame: Frame, data: table): any)|nil Gets the primary value or dynamic value resolver.
---@field values string[]|nil Gets the optional multiline value array, joined with newlines during normalization.
---@field wide boolean|nil Gets whether the value should span the full row without a left label.
---@field multiline boolean|nil Gets whether the value text may wrap across multiple lines.
---@field height number|nil Gets the custom row height.

---@class LibSettingsBuilderCanvasRowConfig: LibSettingsBuilderRowBase
---@field type "canvas" Gets the embedded-canvas row kind.
---@field canvas Frame Gets the prebuilt frame to embed into the settings page.
---@field height number|nil Gets the embedded row height; defaults to the canvas height.

---@class LibSettingsBuilderPageActionsRowConfig: LibSettingsBuilderRowBase
---@field type "pageActions" Gets the page-actions row kind.
---@field actions LibSettingsBuilderPageActionConfig[] Gets the action button definitions attached to the page header.
---@field height number|nil Gets the placeholder row height used by the initializer.

---@class LibSettingsBuilderListRowConfig: LibSettingsBuilderRowBase
---@field type "list" Gets the dynamic flat-list row kind.
---@field height number Gets the total row height reserved for the list widget.
---@field variant LibSettingsBuilderListVariant|nil Gets the built-in list preset applied to item data.
---@field items LibSettingsBuilderListItemsProvider Gets the item provider called during refreshes.

---@class LibSettingsBuilderSectionListRowConfig: LibSettingsBuilderRowBase
---@field type "sectionList" Gets the dynamic grouped-list row kind.
---@field height number Gets the total row height reserved for the list widget.
---@field sections LibSettingsBuilderSectionListProvider Gets the section provider called during refreshes.

---@class LibSettingsBuilderCheckboxListRowConfig: LibSettingsBuilderPathRowBase
---@field type "checkboxList" Gets the checkbox-list composite row kind.
---@field defs LibSettingsBuilderCompositeListDef[] Gets the child checkbox definitions.
---@field label string|nil Gets the optional composite subheader label.

---@class LibSettingsBuilderColorListRowConfig: LibSettingsBuilderPathRowBase
---@field type "colorList" Gets the color-list composite row kind.
---@field defs LibSettingsBuilderCompositeListDef[] Gets the child color definitions.
---@field label string|nil Gets the optional composite subheader label.

---@class LibSettingsBuilderBorderRowConfig: LibSettingsBuilderPathRowBase
---@field type "border" Gets the border composite row kind.
---@field enabledName string|nil Gets the enable-row label.
---@field enabledTooltip string|nil Gets the enable-row tooltip.
---@field thicknessName string|nil Gets the border-width row label.
---@field thicknessTooltip string|nil Gets the border-width row tooltip.
---@field thicknessMin number|nil Gets the minimum border width.
---@field thicknessMax number|nil Gets the maximum border width.
---@field thicknessStep number|nil Gets the border-width step size.
---@field colorName string|nil Gets the color-row label.
---@field colorTooltip string|nil Gets the color-row tooltip.

---@class LibSettingsBuilderFontOverrideRowConfig: LibSettingsBuilderPathRowBase
---@field type "fontOverride" Gets the font-override composite row kind.
---@field enabledName string|nil Gets the override toggle label.
---@field enabledTooltip string|nil Gets the override toggle tooltip.
---@field fontName string|nil Gets the font-row label.
---@field fontTooltip string|nil Gets the font-row tooltip.
---@field fontValues (fun(): table<any, string>)|nil Gets the optional dropdown value provider for the font row.
---@field fontFallback (fun(): string|nil)|nil Gets the fallback font name used when no override is stored.
---@field fontTemplate string|nil Gets the optional custom template used instead of the built-in dropdown.
---@field sizeName string|nil Gets the font-size row label.
---@field sizeTooltip string|nil Gets the font-size row tooltip.
---@field sizeMin number|nil Gets the minimum font size.
---@field sizeMax number|nil Gets the maximum font size.
---@field sizeStep number|nil Gets the font-size step size.
---@field fontSizeFallback (fun(): number|nil)|nil Gets the fallback font size used when no override is stored.

---@class LibSettingsBuilderHeightOverrideRowConfig: LibSettingsBuilderPathRowBase
---@field type "heightOverride" Gets the height-override composite row kind.
---@field min number|nil Gets the minimum slider value.
---@field max number|nil Gets the maximum slider value.
---@field step number|nil Gets the slider step size.

---@alias LibSettingsBuilderRowConfig
---| LibSettingsBuilderCheckboxRowConfig
---| LibSettingsBuilderSliderRowConfig
---| LibSettingsBuilderDropdownRowConfig
---| LibSettingsBuilderColorRowConfig
---| LibSettingsBuilderInputRowConfig
---| LibSettingsBuilderCustomRowConfig
---| LibSettingsBuilderButtonRowConfig
---| LibSettingsBuilderHeaderRowConfig
---| LibSettingsBuilderSubheaderRowConfig
---| LibSettingsBuilderInfoRowConfig
---| LibSettingsBuilderCanvasRowConfig
---| LibSettingsBuilderPageActionsRowConfig
---| LibSettingsBuilderListRowConfig
---| LibSettingsBuilderSectionListRowConfig
---| LibSettingsBuilderCheckboxListRowConfig
---| LibSettingsBuilderColorListRowConfig
---| LibSettingsBuilderBorderRowConfig
---| LibSettingsBuilderFontOverrideRowConfig
---| LibSettingsBuilderHeightOverrideRowConfig

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local interop = internal.interop
local schema = internal.schema
local builders = internal.builders
local registry = internal.registry

local ROW_BUILDERS = {
    button = builders.button,
    canvas = function(spec)
        return builders.canvas(spec.canvas, spec.height, spec)
    end,
    checkbox = builders.checkbox,
    dropdown = builders.dropdown,
    header = builders.header,
    info = builders.info,
    list = builders.list,
    pageActions = builders.pageActions,
    sectionList = builders.sectionList,
    slider = builders.slider,
    subheader = builders.subheader,
    color = builders.color,
    input = builders.input,
    custom = builders.custom,
}
local PROXY_ROW_TYPES = schema.PROXY_ROW_TYPES

local function refreshCategory(builder, category)
    if not category then
        return
    end

    local isVisible = interop.isSettingsPanelShown() and interop.getCurrentSettingsCategory() == category

    local refreshables = builder._categoryRefreshables[category] or {}
    for _, initializer in ipairs(refreshables) do
        interop.refreshInitializer(initializer)
    end

    if not isVisible then
        return
    end

    interop.refreshVisibleSettingsFrames()
    registry.applyReactiveControlStates(builder)
end

local function getCategoryName(builder, category)
    return builder._subcategoryNames[category]
        or (category == builder._rootCategory and builder._rootCategoryName)
        or ""
end

local function ensureConfirmDialog(builder)
    if builder._confirmDialogName then
        return builder._confirmDialogName
    end

    builder._confirmDialogName = builder._config.varPrefix .. "_" .. MAJOR:gsub("[%-%.]", "_") .. "_SettingsConfirm"
    return interop.ensureConfirmDialog(builder._confirmDialogName)
end

local function prepareButtonClick(builder, spec)
    local callbackContext = registry.createCallbackContext(builder, spec)
    local originalClick = spec.onClick
    if spec.confirm then
        local confirmDialogName = ensureConfirmDialog(builder)
        local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
        spec._onClick = function()
            interop.showConfirmDialog(confirmDialogName, confirmText, {
                onAccept = function()
                    originalClick(callbackContext)
                end,
            })
        end
        return
    end

    spec._onClick = function()
        originalClick(callbackContext)
    end
end

local function prepareProxyRow(builder, rowType, spec)
    local setting, category
    if rowType == "checkbox" then
        setting, category = registry.makeProxySetting(builder, spec, interop.getVarTypeBoolean(), false)
    elseif rowType == "slider" then
        setting, category = registry.makeProxySetting(builder, spec, interop.getVarTypeNumber(), 0)
    elseif rowType == "dropdown" then
        local binding = registry.resolveBinding(builder, spec)
        local defaultValue = binding.default
        if spec.getTransform then
            defaultValue = spec.getTransform(defaultValue)
        end
        setting, category = registry.makeProxySetting(
            builder,
            spec,
            spec.varType or (type(defaultValue) == "number" and interop.getVarTypeNumber()) or interop.getVarTypeString(),
            "",
            binding
        )
    elseif rowType == "color" then
        setting, category = registry.makeColorSetting(builder, spec)
    elseif rowType == "input" then
        setting, category = registry.makeProxySetting(builder, spec, interop.getVarTypeString(), "")
    elseif rowType == "custom" then
        setting, category = registry.makeProxySetting(builder, spec, spec.varType or interop.getVarTypeString(), "")
    end

    spec.setting = setting
    spec.category = category
end

local function prepareRow(sourceName, page, row)
    local spec = schema.normalizeRow(sourceName, row)
    local rowType = spec.type
    local builder = page._builder

    schema.validateRow(sourceName, builder, spec)

    if page.disabled and spec.disabled == nil then
        spec.disabled = page.disabled
    end
    if page.hidden and spec.hidden == nil then
        spec.hidden = page.hidden
    end
    if spec.category == nil then
        spec.category = page._category
    end

    spec._page = page

    if PROXY_ROW_TYPES[rowType] then
        if not spec.get then
            spec.path = schema.resolvePagePath(page.path or "", spec.path)
        elseif not spec.key then
            spec.key = row.id
        end
        if spec.get and not spec.key then
            error(sourceName .. ": handler-mode row '" .. tostring(row.id or spec.name) .. "' requires key or id")
        end
        prepareProxyRow(builder, rowType, spec)
    elseif rowType == "button" then
        prepareButtonClick(builder, spec)
    elseif rowType == "pageActions" then
        spec.categoryName = getCategoryName(builder, spec.category)
    end

    return spec
end

local rowRegistration = {}

local function registerBuiltRow(sourceName, page, row, created)
    local spec = prepareRow(sourceName, page, row)
    local builder = page._builder
    local rowType = spec.type
    local build = ROW_BUILDERS[rowType]
    if not build then
        error(sourceName .. ": unknown row type '" .. tostring(rowType) .. "'")
    end

    local initializer, setting = registry.applyBuildResult(builder, spec, build(spec))
    if row.id then
        created[row.id] = { initializer = initializer, setting = setting }
    end
    return initializer, setting
end

local function registerCompositeList(sourceName, page, row, created, childType)
    local spec = prepareRow(sourceName, page, row)
    local basePath = schema.resolvePagePath(page.path or "", spec.path)
    local firstInitializer, firstSetting

    if spec.label then
        rowRegistration.register(sourceName, page, {
            type = "subheader",
            name = spec.label,
            disabled = spec.disabled,
            hidden = spec.hidden,
        }, created)
    end

    for _, def in ipairs(spec.defs) do
        local child = {
            type = childType,
            path = basePath .. "." .. tostring(def.key),
            name = def.name,
            tooltip = def.tooltip,
        }
        schema.propagateModifiers(child, spec)
        local initializer, setting = rowRegistration.register(sourceName, page, child, created)
        firstInitializer = firstInitializer or initializer
        firstSetting = firstSetting or setting
    end

    if row.id then
        created[row.id] = { initializer = firstInitializer, setting = firstSetting }
    end
    return firstInitializer, firstSetting
end

local function registerHeightOverride(sourceName, page, row, created)
    local spec = prepareRow(sourceName, page, row)
    local sectionPath = schema.resolvePagePath(page.path or "", spec.path)
    local child = {
        type = "slider",
        path = sectionPath .. ".height",
        name = spec.name or "Height Override",
        tooltip = spec.tooltip or "Override the default bar height. Set to 0 to use the global default.",
        min = spec.min or 0,
        max = spec.max or 40,
        step = spec.step or 1,
        getTransform = function(value)
            return value or 0
        end,
        setTransform = function(value)
            return value > 0 and value or nil
        end,
    }
    schema.propagateModifiers(child, spec)

    local initializer, setting = rowRegistration.register(sourceName, page, child, created)
    if row.id then
        created[row.id] = { initializer = initializer, setting = setting }
    end
    return initializer, setting
end

local function registerFontOverride(sourceName, page, row, created)
    local spec = prepareRow(sourceName, page, row)
    local sectionPath = schema.resolvePagePath(page.path or "", spec.path)
    local enabledSpec = {
        type = "checkbox",
        path = sectionPath .. ".overrideFont",
        name = spec.enabledName or "Override font",
        tooltip = spec.enabledTooltip or "Override the global font settings for this module.",
        getTransform = function(value)
            return value == true
        end,
    }
    schema.propagateModifiers(enabledSpec, spec)
    local enabledInit, enabledSetting = rowRegistration.register(sourceName, page, enabledSpec, created)

    local outerDisabled = spec.disabled
    local function isOverrideDisabled()
        if outerDisabled and outerDisabled() then
            return true
        end
        return not enabledSetting:GetValue()
    end

    local fontSpec = {
        type = spec.fontTemplate and "custom" or "dropdown",
        path = sectionPath .. ".font",
        name = spec.fontName or "Font",
        tooltip = spec.fontTooltip,
        values = spec.fontValues,
        template = spec.fontTemplate,
        disabled = isOverrideDisabled,
        getTransform = function(value)
            if value then
                return value
            end
            if spec.fontFallback then
                return spec.fontFallback()
            end
            return nil
        end,
    }
    schema.propagateModifiers(fontSpec, spec)
    rowRegistration.register(sourceName, page, fontSpec, created)

    local sizeSpec = {
        type = "slider",
        path = sectionPath .. ".fontSize",
        name = spec.sizeName or "Font Size",
        tooltip = spec.sizeTooltip,
        min = spec.sizeMin or 6,
        max = spec.sizeMax or 32,
        step = spec.sizeStep or 1,
        disabled = isOverrideDisabled,
        getTransform = function(value)
            if value then
                return value
            end
            if spec.fontSizeFallback then
                return spec.fontSizeFallback()
            end
            return 11
        end,
    }
    schema.propagateModifiers(sizeSpec, spec)
    rowRegistration.register(sourceName, page, sizeSpec, created)

    if row.id then
        created[row.id] = { initializer = enabledInit, setting = enabledSetting }
    end
    return enabledInit, enabledSetting
end

local function registerBorder(sourceName, page, row, created)
    local spec = prepareRow(sourceName, page, row)
    local borderPath = schema.resolvePagePath(page.path or "", spec.path)
    local enabledSpec = {
        type = "checkbox",
        path = borderPath .. ".enabled",
        name = spec.enabledName or "Show border",
        tooltip = spec.enabledTooltip,
    }
    schema.propagateModifiers(enabledSpec, spec)
    local enabledInit, enabledSetting = rowRegistration.register(sourceName, page, enabledSpec, created)

    local thicknessSpec = {
        type = "slider",
        path = borderPath .. ".thickness",
        name = spec.thicknessName or "Border width",
        tooltip = spec.thicknessTooltip,
        min = spec.thicknessMin or 1,
        max = spec.thicknessMax or 10,
        step = spec.thicknessStep or 1,
        _parentInitializer = enabledInit,
        _parentPredicate = function()
            return enabledSetting:GetValue()
        end,
    }
    schema.propagateModifiers(thicknessSpec, spec)
    rowRegistration.register(sourceName, page, thicknessSpec, created)

    local colorSpec = {
        type = "color",
        path = borderPath .. ".color",
        name = spec.colorName or "Border color",
        tooltip = spec.colorTooltip,
        _parentInitializer = enabledInit,
        _parentPredicate = function()
            return enabledSetting:GetValue()
        end,
    }
    schema.propagateModifiers(colorSpec, spec)
    rowRegistration.register(sourceName, page, colorSpec, created)

    if row.id then
        created[row.id] = { initializer = enabledInit, setting = enabledSetting }
    end
    return enabledInit, enabledSetting
end

function rowRegistration.register(sourceName, page, row, created)
    local rowType = row.type
    if rowType == "checkboxList" then
        return registerCompositeList(sourceName, page, row, created, "checkbox")
    elseif rowType == "colorList" then
        return registerCompositeList(sourceName, page, row, created, "color")
    elseif rowType == "border" then
        return registerBorder(sourceName, page, row, created)
    elseif rowType == "fontOverride" then
        return registerFontOverride(sourceName, page, row, created)
    elseif rowType == "heightOverride" then
        return registerHeightOverride(sourceName, page, row, created)
    end

    return registerBuiltRow(sourceName, page, row, created)
end

local function createManagedSubcategory(builder, name, parentCategory)
    local previous = builder._currentSubcategory
    local parent = parentCategory or builder._rootCategory
    local category, layout = interop.createSubcategory(parent, name)
    registry.storeCategory(builder, name, category, layout)
    builder._currentSubcategory = category
    builder._currentSubcategory = previous
    return category
end

local function assertRootConfigured(root, sourceName)
    assert(root._category, sourceName .. ": builder was created without config.name")
end

local function sortByOrder(items)
    table.sort(items, function(left, right)
        local leftOrder = left.order or left._sequence
        local rightOrder = right.order or right._sequence
        if leftOrder == rightOrder then
            return left._sequence < right._sequence
        end
        return leftOrder < rightOrder
    end)
    return items
end

local function assertPageMutable(page, sourceName)
    assert(not page._registered, sourceName .. ": page is already registered")
    if page._section then
        assert(not page._section._registered, sourceName .. ": section is already registered")
    end
end

local function bindPageLifecycle(page)
    local confirmDefaults = page._builder._config.defaultsConfirmation
    if page._onShow or page._onHide or page._onDefault or confirmDefaults then
        lib._pageLifecycleCallbacks[page._category] = {
            onShow = page._onShow,
            onHide = page._onHide,
            onDefault = page._onDefault,
            onDefaultEnabled = page._onDefaultEnabled,
            confirmDefaults = confirmDefaults,
            pageName = page._name,
        }
        interop.installPageLifecycleHooks()
    end
end

local function queuePageOperation(page, sourceName, fn)
    assertPageMutable(page, sourceName)
    page._operations[#page._operations + 1] = fn
end

local function materializePage(page, category)
    assert(not page._registered, "materializePage: page is already registered")
    page._category = category
    bindPageLifecycle(page)

    -- Create the handle before row operations so ctx.page is available in callbacks
    -- registered during those operations (e.g. onClick, onSet).
    page._handle = {
        _category = page._category,
        GetId = function(_)
            return page._category:GetID()
        end,
        Refresh = function(_)
            refreshCategory(page._builder, page._category)
        end,
    }

    local created = {}
    for _, operation in ipairs(page._operations) do
        operation(created)
    end

    page._registered = true
    return page
end

local function appendDeclarativeRows(page, sourceName, rows)
    schema.validateRows(sourceName, page._builder, rows, page._rowIDs)
    queuePageOperation(page, sourceName, function(created)
        for _, row in ipairs(rows) do
            rowRegistration.register(sourceName, page, row, created)
        end
    end)
    return page
end

local function createPage(owner, key, rows, opts)
    assert(key, "CreatePage: key is required")

    opts = opts or {}
    local ownerPath = owner.path or ""
    local page = {
        _builder = owner._builder or owner,
        _root = owner._root or owner,
        _section = owner._root and owner or nil,
        _key = key,
        _name = opts.name,
        _onShow = opts.onShow,
        _onHide = opts.onHide,
        _onDefault = opts.onDefault,
        _onDefaultEnabled = opts.onDefaultEnabled,
        _operations = {},
        _rowIDs = {},
        _registered = false,
        _useSectionCategory = opts.useSectionCategory == true,
        disabled = opts.disabled,
        hidden = opts.hidden,
        key = key,
        name = opts.name,
        order = opts.order,
        path = opts.path ~= nil and opts.path or ownerPath,
    }

    if rows then
        appendDeclarativeRows(page, "CreatePage", rows)
    end

    return page
end

local function createSectionPage(section, key, rows, opts)
    assert(not section._registered, "createSectionPage: section is already registered")
    assert(key, "createSectionPage: key is required")
    assert(not section._pages[key], "createSectionPage: duplicate page key '" .. tostring(key) .. "'")

    section._nextPageSequence = section._nextPageSequence + 1
    local page = createPage(section, key, rows, opts)
    page._sequence = section._nextPageSequence
    section._pages[key] = page
    section._pageList[#section._pageList + 1] = page
    return page
end

local function registerRootPage(root, page)
    assert(not page._section, "registerRootPage: only root-owned pages can be registered directly")
    assert(not page._registered, "registerRootPage: page is already registered")
    assert(
        not root._registeredRootPage or root._registeredRootPage == page,
        "registerRootPage: root already has a registered page"
    )
    root._registeredRootPage = page
    materializePage(page, root._category)
    return page
end

local function registerSection(section)
    assert(not section._registered, "registerSection: section is already registered")
    assert(#section._pageList > 0, "registerSection: section must contain at least one page")

    local builder = section._builder
    local nested = #section._pageList > 1
    local orderedPages = {}
    local sectionCategoryPage
    for i = 1, #section._pageList do
        orderedPages[i] = section._pageList[i]
    end
    sortByOrder(orderedPages)

    if nested then
        for _, page in ipairs(orderedPages) do
            if page._useSectionCategory then
                assert(not sectionCategoryPage, "registerSection: only one nested page can use the section category")
                sectionCategoryPage = page
            end
        end
    end

    if nested then
        section._category = createManagedSubcategory(builder, section.name, section._root._category)
    end

    for _, page in ipairs(orderedPages) do
        if nested then
            assert(page.name and page.name ~= "", "registerSection: nested pages require spec.name")
            if page == sectionCategoryPage then
                materializePage(page, section._category)
            else
                materializePage(page, createManagedSubcategory(builder, page.name, section._category))
            end
        else
            materializePage(page, createManagedSubcategory(builder, section.name, section._root._category))
        end
    end

    section._registered = true
    return section
end

local function createSection(root, key, name, opts)
    assert(key, "createSection: key is required")
    assert(name, "createSection: name is required")
    assert(not root._sections[key], "createSection: duplicate section key '" .. tostring(key) .. "'")

    opts = opts or {}
    root._nextSectionSequence = root._nextSectionSequence + 1
    local section = {
        _builder = root,
        _root = root,
        _pages = {},
        _pageList = {},
        _nextPageSequence = 0,
        _registered = false,
        _sequence = root._nextSectionSequence,
        key = key,
        name = name,
        order = opts.order,
        path = opts.path ~= nil and opts.path or key,
    }

    root._sections[key] = section
    root._sectionList[#root._sectionList + 1] = section
    return section
end

local function createRootPage(root, key, rows, opts)
    assert(key, "createRootPage: key is required")
    assert(not root._pages[key], "createRootPage: duplicate root page key '" .. tostring(key) .. "'")

    local page = createPage(root, key, rows, opts)
    page._sequence = root._nextRootPageSequence + 1
    root._nextRootPageSequence = page._sequence
    root._pages[key] = page
    root._pageList[#root._pageList + 1] = page
    return page
end

--- Gets the registered section metadata by key.
---@param key string
---@return LibSettingsBuilderSectionHandle|nil section
function lib:GetSection(key)
    return self._sections[key]
end

--- Gets the registered root page handle.
---@return LibSettingsBuilderPageHandle|nil page
function lib:GetRootPage()
    local page = self._registeredRootPage
    return page and page._handle or nil
end

--- Gets the registered section page handle by section and page key.
---@param sectionKey string
---@param pageKey string
---@return LibSettingsBuilderPageHandle|nil page
function lib:GetPage(sectionKey, pageKey)
    if pageKey == nil then
        return nil
    end

    local section = self._sections[sectionKey]
    local page = section and section._pages[pageKey] or nil
    return page and page._handle or nil
end

--- Gets whether this runtime owns the supplied Blizzard Settings category.
---@param category table|nil
---@return boolean owned
function lib:HasCategory(category)
    return category ~= nil and self._layouts[category] ~= nil
end

local function registerPageDefinition(owner, pageDef, defaultName)
    schema.validatePageDefinition("registerPageDefinition", pageDef)

    local creator = owner._root and createSectionPage or createRootPage
    return creator(owner, pageDef.key, pageDef.rows, {
        name = pageDef.name or defaultName,
        onShow = pageDef.onShow,
        onHide = pageDef.onHide,
        onDefault = pageDef.onDefault,
        onDefaultEnabled = pageDef.onDefaultEnabled,
        disabled = schema.normalizePredicate(pageDef.disabled),
        hidden = schema.normalizePredicate(pageDef.hidden),
        order = pageDef.order,
        path = pageDef.path,
        useSectionCategory = pageDef.useSectionCategory or (owner._root ~= nil and pageDef.name == nil),
    })
end

function registry.registerTree(self, spec)
    assertRootConfigured(self, "Register")
    assert(type(spec) == "table", "Register: spec must be a table")
    assert(spec.page or spec.sections, "Register: spec requires page or sections")

    if spec.page then
        registerRootPage(self, registerPageDefinition(self, spec.page, self.name))
    end

    for _, sectionDef in ipairs(spec.sections or {}) do
        assert(type(sectionDef) == "table", "Register: each section definition must be a table")
        assert(sectionDef.key, "Register: each section requires a key")
        assert(sectionDef.name, "Register: each section requires a name")

        local section = createSection(self, sectionDef.key, sectionDef.name, {
            order = sectionDef.order,
            path = sectionDef.path,
        })

        assert(type(sectionDef.pages) == "table", "Register: each section requires a pages array")
        for _, pageDef in ipairs(sectionDef.pages) do
            registerPageDefinition(section, pageDef, sectionDef.name)
        end

        registerSection(section)
    end

    return self
end

function registry.initializeRoot(self, name)
    if not self._rootCategory then
        assert(name, "_initializeRoot: name is required")
        local category, layout = interop.createRootCategory(name)
        self._rootCategory = category
        self._rootCategoryName = name
        self._layouts[category] = layout
        self._currentSubcategory = nil
    elseif name and self._rootCategoryName ~= name then
        error("_initializeRoot: root already exists with name '" .. tostring(self._rootCategoryName) .. "'")
    end

    if not self._rootRegistered and self._rootCategory then
        interop.registerAddOnCategory(self._rootCategory)
        self._rootRegistered = true
    end

    self._category = self._rootCategory
    self.name = self._rootCategoryName
    return self
end

lib._runtimeApi.GetSection = lib.GetSection
lib._runtimeApi.GetRootPage = lib.GetRootPage
lib._runtimeApi.GetPage = lib.GetPage
lib._runtimeApi.HasCategory = lib.HasCategory
lib._runtimeApi._registerTree = registry.registerTree
lib._runtimeApi._initializeRoot = registry.initializeRoot
lib._publicApi = lib._runtimeApi

lib._loadState.open = nil
