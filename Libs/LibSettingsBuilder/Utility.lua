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
local copyMixin = internal.copyMixin
local installPageLifecycleHooks = internal.installPageLifecycleHooks

local PROXY_ROW_TYPES = {
    checkbox = true,
    slider = true,
    dropdown = true,
    color = true,
    input = true,
    custom = true,
}

local COMPOSITE_ROW_TYPES = {
    border = true,
    checkboxList = true,
    colorList = true,
    fontOverride = true,
    heightOverride = true,
}

local VALID_ROW_TYPES = {
    border = true,
    button = true,
    canvas = true,
    checkbox = true,
    checkboxList = true,
    color = true,
    colorList = true,
    custom = true,
    dropdown = true,
    fontOverride = true,
    header = true,
    heightOverride = true,
    info = true,
    input = true,
    list = true,
    pageActions = true,
    sectionList = true,
    slider = true,
    subheader = true,
}

local function refreshCategory(builder, category)
    if not category then
        return
    end

    local currentCategory = SettingsPanel and SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory() or nil
    local isVisible = SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and currentCategory == category

    local refreshables = builder._categoryRefreshables[category] or {}
    for _, initializer in ipairs(refreshables) do
        if initializer._lsbActiveFrame and initializer._lsbRefreshFrame then
            initializer._lsbRefreshFrame(initializer._lsbActiveFrame, initializer)
        end
    end

    if not isVisible then
        return
    end

    local settingsList = SettingsPanel.GetSettingsList and SettingsPanel:GetSettingsList()
    local scrollBox = settingsList and settingsList.ScrollBox
    if scrollBox and scrollBox.ForEachFrame then
        scrollBox:ForEachFrame(function(frame)
            local initializer = frame.GetElementData and frame:GetElementData() or frame._lsbInitializer
            if frame.EvaluateState then
                frame:EvaluateState()
            end
            if initializer and initializer._lsbRefreshFrame then
                initializer._lsbRefreshFrame(frame, initializer)
            end
        end)
    end
end

local function resolvePagePath(pagePath, rowPath)
    if rowPath == nil or rowPath == "" or rowPath:find("%.") or pagePath == "" then
        return (rowPath ~= nil and rowPath ~= "") and rowPath or pagePath
    end
    return pagePath .. "." .. rowPath
end

local function assertBooleanOrCallback(sourceName, fieldName, value)
    local valueType = type(value)
    assert(
        value == nil or valueType == "boolean" or valueType == "function",
        sourceName .. ": " .. fieldName .. " must be a boolean or function"
    )
end

local function getRowLabel(row)
    return tostring(row.id or row.key or row.path or row.name or row.type)
end

local function normalizeDeclarativeRowSpec(sourceName, row)
    assert(type(row) == "table", sourceName .. ": each row must be a table")

    local spec = copyMixin({}, row)
    assert(spec.desc == nil, sourceName .. ": row '" .. getRowLabel(spec) .. "' uses deprecated field 'desc'; use 'tooltip'")
    assert(spec.condition == nil, sourceName .. ": row '" .. getRowLabel(spec) .. "' uses removed field 'condition'")
    assert(spec.parent == nil, sourceName .. ": row '" .. getRowLabel(spec) .. "' uses removed field 'parent'")
    assert(spec.parentCheck == nil, sourceName .. ": row '" .. getRowLabel(spec) .. "' uses removed field 'parentCheck'")

    local rowType = spec.type
    assert(type(rowType) == "string" and VALID_ROW_TYPES[rowType], sourceName .. ": unknown row type '" .. tostring(rowType) .. "'")

    if rowType == "button" and spec.buttonText == nil and spec.value ~= nil then
        spec.buttonText = spec.value
    end
    spec.value = rowType == "button" and nil or spec.value

    if rowType == "dropdown" and spec.scrollHeight == nil and spec.maxScrollDisplayHeight ~= nil then
        spec.scrollHeight = spec.maxScrollDisplayHeight
    end
    spec.maxScrollDisplayHeight = nil

    if rowType == "info" and spec.values ~= nil then
        assert(spec.value == nil, sourceName .. ": info row '" .. getRowLabel(spec) .. "' cannot define both value and values")
        assert(type(spec.values) == "table", sourceName .. ": info row '" .. getRowLabel(spec) .. "' values must be a table")
        spec.value = table.concat(spec.values, "\n")
        spec.multiline = true
        spec.values = nil
    end

    if rowType == "input" and spec.debounce == nil and spec.debounceMilliseconds ~= nil then
        spec.debounce = spec.debounceMilliseconds / 1000
    end
    spec.debounceMilliseconds = nil

    if rowType == "slider" and spec.formatter == nil and spec.formatValue ~= nil then
        spec.formatter = spec.formatValue
    end
    spec.formatValue = nil

    spec.id = row.id

    return spec
end

local function validateDeclarativeRow(sourceName, builder, row)
    local rowType = row.type
    local rowLabel = getRowLabel(row)
    local hasHandler = row.get ~= nil or row.set ~= nil

    assertBooleanOrCallback(sourceName, "disabled", row.disabled)
    assertBooleanOrCallback(sourceName, "hidden", row.hidden)

    if PROXY_ROW_TYPES[rowType] then
        if hasHandler then
            assert(row.get, sourceName .. ": handler-mode row '" .. rowLabel .. "' requires get")
            assert(row.set, sourceName .. ": handler-mode row '" .. rowLabel .. "' requires set")
            assert(row.key or row.id, sourceName .. ": handler-mode row '" .. rowLabel .. "' requires key or id")
        else
            assert(row.path ~= nil, sourceName .. ": path-bound row '" .. rowLabel .. "' requires path")
            assert(builder._adapter, sourceName .. ": path-bound row '" .. rowLabel .. "' requires store/defaults on the builder")
        end
    end

    if rowType == "button" then
        assert(type(row.onClick) == "function", sourceName .. ": button row '" .. rowLabel .. "' requires onClick")
    elseif rowType == "canvas" then
        assert(row.canvas, sourceName .. ": canvas row '" .. rowLabel .. "' requires canvas")
    elseif rowType == "custom" then
        assert(row.template, sourceName .. ": custom row '" .. rowLabel .. "' requires template")
    elseif rowType == "dropdown" then
        assert(row.values ~= nil, sourceName .. ": dropdown row '" .. rowLabel .. "' requires values")
    elseif rowType == "list" then
        assert(type(row.items) == "function", sourceName .. ": list row '" .. rowLabel .. "' requires items")
        assert(row.height, sourceName .. ": list row '" .. rowLabel .. "' requires height")
    elseif rowType == "pageActions" then
        assert(type(row.actions) == "table", sourceName .. ": pageActions row '" .. rowLabel .. "' requires actions")
    elseif rowType == "sectionList" then
        assert(type(row.sections) == "function", sourceName .. ": sectionList row '" .. rowLabel .. "' requires sections")
        assert(row.height, sourceName .. ": sectionList row '" .. rowLabel .. "' requires height")
    elseif rowType == "slider" then
        assert(row.min ~= nil, sourceName .. ": slider row '" .. rowLabel .. "' requires min")
        assert(row.max ~= nil, sourceName .. ": slider row '" .. rowLabel .. "' requires max")
    elseif COMPOSITE_ROW_TYPES[rowType] then
        assert(row.path ~= nil, sourceName .. ": composite row '" .. rowLabel .. "' requires path")
        if rowType == "checkboxList" or rowType == "colorList" then
            assert(type(row.defs) == "table", sourceName .. ": composite row '" .. rowLabel .. "' requires defs")
        end
    elseif rowType == "info" then
        assert(
            row.value ~= nil or row.values ~= nil or row.name ~= nil,
            sourceName .. ": info row '" .. rowLabel .. "' requires value, values, or name"
        )
    elseif rowType == "header" or rowType == "subheader" then
        assert(row.name ~= nil, sourceName .. ": " .. rowType .. " row '" .. rowLabel .. "' requires name")
    end
end

local function validateDeclarativeRows(sourceName, builder, rows, seenRowIDs)
    assert(type(rows) == "table", sourceName .. ": rows must be a table")

    for _, row in ipairs(rows) do
        local normalized = normalizeDeclarativeRowSpec(sourceName, row)
        local rowID = normalized.id
        if rowID ~= nil then
            assert(not seenRowIDs[rowID], sourceName .. ": duplicate row id '" .. tostring(rowID) .. "'")
            seenRowIDs[rowID] = true
        end
        validateDeclarativeRow(sourceName, builder, normalized)
    end
end

local function validatePageDefinition(sourceName, pageDef)
    assert(type(pageDef) == "table", sourceName .. ": page definition must be a table")
    assert(pageDef.key, sourceName .. ": page definition requires key")
    assert(type(pageDef.rows) == "table", sourceName .. ": page definition requires rows")
end

local function registerLabeledList(page, spec, builderMethod)
    local builder = page._builder
    if spec.label then
        local labelInit = lib.Subheader(builder, {
            name = spec.label,
            disabled = spec.disabled,
            hidden = spec.hidden,
            category = page._category,
        })
        spec._parentInitializer = spec._parentInitializer or labelInit
    end

    local results = builderMethod(builder, resolvePagePath(page.path or "", spec.path), spec.defs or {}, spec)
    return results[1] and results[1].initializer, results[1] and results[1].setting
end

local function registerDeclarativeRow(sourceName, page, row, created)
    local spec = normalizeDeclarativeRowSpec(sourceName, row)
    local rowType = spec.type

    local builder = page._builder
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

    local initializer, setting
    local path = resolvePagePath(page.path or "", spec.path)
    if rowType == "button" then
        initializer = lib.Button(builder, spec)
    elseif rowType == "canvas" then
        initializer = lib.EmbedCanvas(builder, spec.canvas, spec.height, spec)
    elseif rowType == "checkboxList" then
        initializer, setting = registerLabeledList(page, spec, lib.CheckboxList)
    elseif rowType == "colorList" then
        initializer, setting = registerLabeledList(page, spec, lib.ColorPickerList)
    elseif rowType == "header" then
        initializer = lib.Header(builder, spec)
    elseif rowType == "info" then
        initializer = lib.InfoRow(builder, spec)
    elseif rowType == "list" then
        initializer = lib.List(builder, spec)
    elseif rowType == "pageActions" then
        initializer = lib.PageActions(builder, spec)
    elseif rowType == "sectionList" then
        initializer = lib.SectionList(builder, spec)
    elseif rowType == "subheader" then
        initializer = lib.Subheader(builder, spec)
    elseif rowType == "border" then
        local result = lib.BorderGroup(builder, path, spec)
        initializer, setting = result.enabledInit, result.enabledSetting
    elseif rowType == "fontOverride" then
        local result = lib.FontOverrideGroup(builder, path, spec)
        initializer, setting = result.enabledInit, result.enabledSetting
    elseif rowType == "heightOverride" then
        initializer, setting = lib.HeightOverrideSlider(builder, path, spec)
    elseif PROXY_ROW_TYPES[rowType] then
        if not spec.get then
            spec.path = path
        elseif not spec.key then
            spec.key = row.id
        end
        if spec.get and not spec.key then
            error(sourceName .. ": handler-mode row '" .. tostring(row.id or spec.name) .. "' requires key or id")
        end
        if rowType == "checkbox" then
            initializer, setting = lib.Checkbox(builder, spec)
        elseif rowType == "slider" then
            initializer, setting = lib.Slider(builder, spec)
        elseif rowType == "dropdown" then
            initializer, setting = lib.Dropdown(builder, spec)
        elseif rowType == "color" then
            initializer, setting = lib.Color(builder, spec)
        elseif rowType == "input" then
            initializer, setting = lib.Input(builder, spec)
        elseif rowType == "custom" then
            initializer, setting = lib.Custom(builder, spec)
        end
    else
        error(sourceName .. ": unknown row type '" .. tostring(rowType) .. "'")
    end

    if row.id then
        created[row.id] = { initializer = initializer, setting = setting }
    end
end

local function createManagedSubcategory(builder, name, parentCategory)
    local previous = builder._currentSubcategory
    local category = internal.createSubcategory(builder, name, parentCategory)
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
    if page._onShow or page._onHide or page._onDefault then
        lib._pageLifecycleCallbacks[page._category] = {
            onShow = page._onShow,
            onHide = page._onHide,
            onDefault = page._onDefault,
            onDefaultEnabled = page._onDefaultEnabled,
        }
        installPageLifecycleHooks()
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
    validateDeclarativeRows(sourceName, page._builder, rows, page._rowIDs)
    queuePageOperation(page, sourceName, function(created)
        for _, row in ipairs(rows) do
            registerDeclarativeRow(sourceName, page, row, created)
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
    validatePageDefinition("registerPageDefinition", pageDef)

    local creator = owner._root and createSectionPage or createRootPage
    return creator(owner, pageDef.key, pageDef.rows, {
        name = pageDef.name or defaultName,
        onShow = pageDef.onShow,
        onHide = pageDef.onHide,
        onDefault = pageDef.onDefault,
        onDefaultEnabled = pageDef.onDefaultEnabled,
        disabled = pageDef.disabled,
        hidden = pageDef.hidden,
        order = pageDef.order,
        path = pageDef.path,
        useSectionCategory = pageDef.useSectionCategory or (owner._root ~= nil and pageDef.name == nil),
    })
end

function internal.registerTree(self, spec)
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

function internal.initializeRoot(self, name)
    if not self._rootCategory then
        assert(name, "_initializeRoot: name is required")
        internal.createRootCategory(self, name)
    elseif name and self._rootCategoryName ~= name then
        error("_initializeRoot: root already exists with name '" .. tostring(self._rootCategoryName) .. "'")
    end

    if not self._rootRegistered and self._rootCategory then
        Settings.RegisterAddOnCategory(self._rootCategory)
        self._rootRegistered = true
    end

    self._category = self._rootCategory
    self.name = self._rootCategoryName
    return self
end

lib._publicApi = {
    GetSection = lib.GetSection,
    GetRootPage = lib.GetRootPage,
    GetPage = lib.GetPage,
    HasCategory = lib.HasCategory,
    _registerTree = internal.registerTree,
    _initializeRoot = internal.initializeRoot,
}

lib._loadState.open = nil
