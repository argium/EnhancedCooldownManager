-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

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
    if page._onShow or page._onHide then
        lib._pageLifecycleCallbacks[page._category] = {
            onShow = page._onShow,
            onHide = page._onHide,
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
        _operations = {},
        _rowIDs = {},
        _registered = false,
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
    for i = 1, #section._pageList do
        orderedPages[i] = section._pageList[i]
    end
    sortByOrder(orderedPages)

    if nested then
        section._category = createManagedSubcategory(builder, section.name, section._root._category)
    end

    for _, page in ipairs(orderedPages) do
        if nested then
            assert(page.name and page.name ~= "", "registerSection: nested pages require spec.name")
            materializePage(page, createManagedSubcategory(builder, page.name, section._category))
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

function lib:GetSection(key)
    return self._sections[key]
end

function lib:GetRootPage()
    local page = self._registeredRootPage
    return page and page._handle or nil
end

function lib:GetPage(sectionKey, pageKey)
    if pageKey == nil then
        return nil
    end

    local section = self._sections[sectionKey]
    local page = section and section._pages[pageKey] or nil
    return page and page._handle or nil
end

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
        disabled = pageDef.disabled,
        hidden = pageDef.hidden,
        order = pageDef.order,
        path = pageDef.path,
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
