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
local getCanvasLayoutMetrics = internal.getCanvasLayoutMetrics
local BuilderMixin = lib.BuilderMixin

local SectionMethods = {}
local PageMethods = {}

local DISPATCH = {
    checkbox = "Checkbox",
    slider = "Slider",
    dropdown = "Dropdown",
    color = "Color",
    input = "Input",
    custom = "Custom",
}

local COMPOSITE_ROW_DISPATCH = {
    border = function(builder, path, spec)
        local result = builder:BorderGroup(path, spec)
        return result.enabledInit, result.enabledSetting
    end,
    fontOverride = function(builder, path, spec)
        local result = builder:FontOverrideGroup(path, spec)
        return result.enabledInit, result.enabledSetting
    end,
    heightOverride = function(builder, path, spec)
        return builder:HeightOverrideSlider(path, spec)
    end,
}

local PROXY_ROW_TYPES = {
    checkbox = true,
    slider = true,
    dropdown = true,
    color = true,
    input = true,
    custom = true,
}

local proxyMethods = {}
local proxyMT = {
    __index = function(self, key)
        local method = proxyMethods[key]
        if method then
            return method
        end

        local target = rawget(self, "_lsbTarget")
        if not target then
            return nil
        end

        local value = target[key]
        if type(value) == "function" then
            return function(_, ...)
                return value(target, ...)
            end
        end

        return value
    end,
}

function proxyMethods:_lsbBind(target)
    self._lsbTarget = target
    return target
end

function BuilderMixin:SetCanvasLayoutDefaults(overrides)
    if not overrides then
        return lib.CanvasLayoutDefaults
    end

    return copyMixin(lib.CanvasLayoutDefaults, overrides)
end

function BuilderMixin:ConfigureCanvasLayout(layout, overrides)
    assert(layout, "ConfigureCanvasLayout: layout is required")
    if not overrides then
        return getCanvasLayoutMetrics(layout)
    end

    layout._metrics = copyMixin(copyMixin({}, lib.CanvasLayoutDefaults), overrides)
    return layout._metrics
end

function BuilderMixin:Control(spec)
    local methodName = DISPATCH[spec.type]
    assert(methodName, "Control: unknown type '" .. tostring(spec.type) .. "'")
    return self[methodName](self, spec)
end

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

local function shouldProcessRow(row)
    local condition = row and row.condition
    return condition == nil
        or (type(condition) == "function" and condition())
        or (type(condition) ~= "function" and condition)
end

local function resolvePagePath(pagePath, rowPath)
    if not rowPath or rowPath:find("%.") or pagePath == "" then
        return rowPath or pagePath
    end
    return pagePath .. "." .. rowPath
end

local function copyDeclarativeRowSpec(row)
    local spec = copyMixin({}, row)
    spec.id = nil
    spec.condition = nil
    if spec.desc and not spec.tooltip then
        spec.tooltip = spec.desc
    end
    spec.desc = nil
    return spec
end

local function resolveDeclarativeParent(sourceName, created, rowID, spec)
    if type(spec.parent) ~= "string" then
        return
    end

    local ref = created[spec.parent]
    assert(
        ref,
        sourceName .. ": parent '" .. spec.parent .. "' not found for row '" .. tostring(rowID or spec.name or spec.type) .. "'"
    )

    spec.parent = ref.initializer
    local parentCheck = spec.parentCheck
    if parentCheck == "checked" or parentCheck == "notChecked" then
        local setting = ref.setting
        assert(setting, sourceName .. ": parentCheck='" .. parentCheck .. "' requires a parent setting")
        spec.parentCheck = parentCheck == "checked" and function()
            return setting:GetValue()
        end or function()
            return not setting:GetValue()
        end
    end
end

local function createProxy(kind)
    return setmetatable({ _lsbProxyKind = kind }, proxyMT)
end

local function bindProxy(proxy, target)
    if proxy then
        proxy:_lsbBind(target)
    end
    return target
end

local function unwrapProxy(value, kind, sourceName)
    if type(value) ~= "table" or value._lsbProxyKind ~= kind then
        return value
    end

    local target = rawget(value, "_lsbTarget")
    assert(target, sourceName .. ": dependent control was not materialized yet")
    return target
end

local function callBuilder(builder, methodName, ...)
    return builder[methodName](builder, ...)
end

local function registerLabeledList(page, spec, methodName)
    local builder = page._builder
    if spec.label then
        local labelInit = builder:Subheader({
            name = spec.label,
            disabled = spec.disabled,
            hidden = spec.hidden,
            category = page._category,
        })
        spec.parent = spec.parent or labelInit
    end

    local results = callBuilder(
        builder,
        methodName,
        resolvePagePath(page.path or "", spec.path),
        spec.defs or {},
        spec
    )
    return results[1] and results[1].initializer, results[1] and results[1].setting
end

local function registerDeclarativeRow(sourceName, page, row, created)
    local rowType = row.type
    assert(rowType, sourceName .. ": each row requires a type")

    local builder = page._builder
    local spec = copyDeclarativeRowSpec(row)
    if page.disabled and spec.disabled == nil then
        spec.disabled = page.disabled
    end
    if page.hidden and spec.hidden == nil then
        spec.hidden = page.hidden
    end
    if spec.category == nil then
        spec.category = page._category
    end

    resolveDeclarativeParent(sourceName, created, row.id, spec)
    spec._page = page

    if spec.onClick then
        local original = spec.onClick
        spec.onClick = function(...)
            return original(page, ...)
        end
    end

    local initializer, setting
    if rowType == "button" then
        initializer = builder:Button(spec)
    elseif rowType == "canvas" then
        initializer = builder:EmbedCanvas(spec.canvas, spec.height, spec)
    elseif rowType == "checkboxList" then
        initializer, setting = registerLabeledList(page, spec, "CheckboxList")
    elseif rowType == "colorList" then
        initializer, setting = registerLabeledList(page, spec, "ColorPickerList")
    elseif rowType == "header" then
        initializer = builder:Header(spec)
    elseif rowType == "info" then
        initializer = builder:InfoRow(spec)
    elseif rowType == "list" then
        initializer = builder:List(spec)
    elseif rowType == "pageActions" then
        initializer = builder:PageActions(spec)
    elseif rowType == "sectionList" then
        initializer = builder:SectionList(spec)
    elseif rowType == "subheader" then
        initializer = builder:Subheader(spec)
    elseif COMPOSITE_ROW_DISPATCH[rowType] then
        initializer, setting = COMPOSITE_ROW_DISPATCH[rowType](
            builder,
            resolvePagePath(page.path or "", spec.path),
            spec
        )
    elseif PROXY_ROW_TYPES[rowType] then
        if not spec.get then
            spec.path = resolvePagePath(page.path or "", spec.path)
        elseif not spec.key then
            spec.key = row.id
        end
        if spec.get and not spec.key then
            error(sourceName .. ": handler-mode row '" .. tostring(row.id or spec.name) .. "' requires key or id")
        end
        spec.type = rowType
        initializer, setting = builder:Control(spec)
    else
        error(sourceName .. ": unknown row type '" .. tostring(rowType) .. "'")
    end

    if row.id then
        created[row.id] = { initializer = initializer, setting = setting }
    end
end

local function createManagedSubcategory(builder, name, parentCategory)
    local previous = builder._currentSubcategory
    local category = builder:_createSubcategory(name, parentCategory)
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

local function prepareSpec(page, sourceName, spec)
    local prepared = copyMixin({}, spec)
    prepared._page = page
    if prepared.category == nil then
        prepared.category = page._category
    end
    if prepared.parent then
        prepared.parent = unwrapProxy(prepared.parent, "initializer", sourceName)
    end
    if prepared.onClick then
        local original = prepared.onClick
        prepared.onClick = function(...)
            return original(page, ...)
        end
    end
    return prepared
end

local function prepareControlSpec(page, sourceName, spec)
    local prepared = prepareSpec(page, sourceName, spec)
    if not prepared.get and prepared.path then
        prepared.path = resolvePagePath(page.path or "", prepared.path)
    end
    return prepared
end

local function queuePageOperation(page, sourceName, fn)
    assertPageMutable(page, sourceName)
    page._operations[#page._operations + 1] = fn
end

local function queueSpecPair(page, sourceName, methodName, spec)
    local initializerProxy = createProxy("initializer")
    local settingProxy = createProxy("setting")
    local snapshot = copyMixin({}, spec or {})

    queuePageOperation(page, sourceName, function()
        local initializer, setting = callBuilder(
            page._builder,
            methodName,
            prepareControlSpec(page, sourceName, snapshot)
        )
        bindProxy(initializerProxy, initializer)
        bindProxy(settingProxy, setting)
    end)

    return initializerProxy, settingProxy
end

local function queueSpecInit(page, sourceName, methodName, spec)
    local initializerProxy = createProxy("initializer")
    local snapshot = copyMixin({}, spec or {})

    queuePageOperation(page, sourceName, function()
        local initializer = callBuilder(page._builder, methodName, prepareSpec(page, sourceName, snapshot))
        bindProxy(initializerProxy, initializer)
    end)

    return initializerProxy
end

local function queueHeightOverride(page, sectionPath, spec)
    local initializerProxy = createProxy("initializer")
    local settingProxy = createProxy("setting")
    local snapshot = copyMixin({}, spec or {})

    queuePageOperation(page, "page:HeightOverrideSlider", function()
        local initializer, setting = callBuilder(
            page._builder,
            "HeightOverrideSlider",
            resolvePagePath(page.path or "", sectionPath),
            prepareSpec(page, "page:HeightOverrideSlider", snapshot)
        )
        bindProxy(initializerProxy, initializer)
        bindProxy(settingProxy, setting)
    end)

    return initializerProxy, settingProxy
end

local function queueCompositeGroup(page, sourceName, methodName, basePath, spec, fields)
    local result = {}
    for key, kind in pairs(fields) do
        result[key] = createProxy(kind)
    end

    local snapshot = copyMixin({}, spec or {})
    queuePageOperation(page, sourceName, function()
        local actual = callBuilder(
            page._builder,
            methodName,
            resolvePagePath(page.path or "", basePath),
            prepareSpec(page, sourceName, snapshot)
        )
        for key in pairs(fields) do
            bindProxy(result[key], actual[key])
        end
    end)

    return result
end

local function queueCompositeList(page, sourceName, methodName, basePath, defs, spec)
    local proxies = {}
    for i, def in ipairs(defs or {}) do
        proxies[i] = {
            key = def.key,
            initializer = createProxy("initializer"),
            setting = createProxy("setting"),
        }
    end

    local snapshot = copyMixin({}, spec or {})
    queuePageOperation(page, sourceName, function()
        local actual = callBuilder(
            page._builder,
            methodName,
            resolvePagePath(page.path or "", basePath),
            defs,
            prepareSpec(page, sourceName, snapshot)
        )
        for i, proxy in ipairs(proxies) do
            bindProxy(proxy.initializer, actual[i] and actual[i].initializer)
            bindProxy(proxy.setting, actual[i] and actual[i].setting)
        end
    end)

    return proxies
end

local function materializePage(page, category)
    assert(not page._registered, "materializePage: page is already registered")
    page._category = category
    bindPageLifecycle(page)

    local created = {}
    for _, operation in ipairs(page._operations) do
        operation(created)
    end

    setmetatable(page, { __index = PageMethods })
    page._registered = true
    if page._onRegistered then
        page._onRegistered(page)
    end
    return page
end

local function appendDeclarativeRows(page, sourceName, rows)
    queuePageOperation(page, sourceName, function(created)
        for _, row in ipairs(rows or {}) do
            if shouldProcessRow(row) then
                registerDeclarativeRow(sourceName, page, row, created)
            end
        end
    end)
    return page
end

function PageMethods:RegisterRows(rows)
    return appendDeclarativeRows(self, "page:RegisterRows", rows)
end

function PageMethods:Checkbox(spec)
    return queueSpecPair(self, "page:Checkbox", "Checkbox", spec)
end

function PageMethods:Slider(spec)
    return queueSpecPair(self, "page:Slider", "Slider", spec)
end

function PageMethods:Dropdown(spec)
    return queueSpecPair(self, "page:Dropdown", "Dropdown", spec)
end

function PageMethods:Input(spec)
    return queueSpecPair(self, "page:Input", "Input", spec)
end

function PageMethods:Color(spec)
    return queueSpecPair(self, "page:Color", "Color", spec)
end

function PageMethods:Custom(spec)
    return queueSpecPair(self, "page:Custom", "Custom", spec)
end

function PageMethods:Button(spec)
    return queueSpecInit(self, "page:Button", "Button", spec)
end

function PageMethods:PageActions(spec)
    return queueSpecInit(self, "page:PageActions", "PageActions", spec)
end

function PageMethods:Header(spec)
    if type(spec) ~= "table" then
        spec = { name = spec }
    end
    return queueSpecInit(self, "page:Header", "Header", spec)
end

function PageMethods:Subheader(spec)
    return queueSpecInit(self, "page:Subheader", "Subheader", spec)
end

function PageMethods:InfoRow(spec)
    return queueSpecInit(self, "page:InfoRow", "InfoRow", spec)
end

function PageMethods:List(spec)
    return queueSpecInit(self, "page:List", "List", spec)
end

function PageMethods:SectionList(spec)
    return queueSpecInit(self, "page:SectionList", "SectionList", spec)
end

function PageMethods:EmbedCanvas(canvas, height, spec)
    local initializerProxy = createProxy("initializer")
    local snapshot = copyMixin({}, spec or {})

    queuePageOperation(self, "page:EmbedCanvas", function()
        local initializer = callBuilder(
            self._builder,
            "EmbedCanvas",
            canvas,
            height,
            prepareSpec(self, "page:EmbedCanvas", snapshot)
        )
        bindProxy(initializerProxy, initializer)
    end)

    return initializerProxy
end

function PageMethods:HeightOverrideSlider(sectionPath, spec)
    return queueHeightOverride(self, sectionPath, spec)
end

function PageMethods:FontOverrideGroup(sectionPath, spec)
    return queueCompositeGroup(self, "page:FontOverrideGroup", "FontOverrideGroup", sectionPath, spec, {
        enabledInit = "initializer",
        enabledSetting = "setting",
        fontInit = "initializer",
        sizeInit = "initializer",
    })
end

function PageMethods:BorderGroup(borderPath, spec)
    return queueCompositeGroup(self, "page:BorderGroup", "BorderGroup", borderPath, spec, {
        enabledInit = "initializer",
        enabledSetting = "setting",
        thicknessInit = "initializer",
        colorInit = "initializer",
    })
end

function PageMethods:ColorPickerList(basePath, defs, spec)
    return queueCompositeList(self, "page:ColorPickerList", "ColorPickerList", basePath, defs, spec)
end

function PageMethods:CheckboxList(basePath, defs, spec)
    return queueCompositeList(self, "page:CheckboxList", "CheckboxList", basePath, defs, spec)
end

function PageMethods:GetID()
    assert(self._registered and self._category, "page:GetID: page is not registered")
    return self._category:GetID()
end

function PageMethods:Refresh()
    assert(self._registered and self._category, "page:Refresh: page is not registered")
    refreshCategory(self._builder, self._category)
end

local function createPage(owner, key, rows, opts)
    assert(key, "CreatePage: key is required")

    opts = opts or {}
    local ownerPath = owner.path or ""
    local page = setmetatable({
        _builder = owner._builder or owner,
        _root = owner._root or owner,
        _section = owner._root and owner or nil,
        _key = key,
        _name = opts.name,
        _onShow = opts.onShow,
        _onHide = opts.onHide,
        _onRegistered = opts.onRegistered,
        _operations = {},
        _registered = false,
        disabled = opts.disabled,
        hidden = opts.hidden,
        key = key,
        name = opts.name,
        order = opts.order,
        path = opts.path ~= nil and opts.path or ownerPath,
    }, { __index = PageMethods })

    if rows then
        appendDeclarativeRows(page, "CreatePage", rows)
    end

    return page
end

function SectionMethods:GetPage(key)
    return self._pages[key]
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
    local nested = section.display == "nested" or #section._pageList > 1
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
    local display = opts.display or "auto"
    assert(display == "auto" or display == "nested", "createSection: display must be 'auto' or 'nested'")

    local section = setmetatable({
        _builder = root,
        _root = root,
        _pages = {},
        _pageList = {},
        _nextPageSequence = 0,
        _registered = false,
        _sequence = root._nextSectionSequence,
        display = display,
        key = key,
        name = name,
        order = opts.order,
        path = opts.path ~= nil and opts.path or key,
    }, { __index = SectionMethods })

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

function BuilderMixin:GetSection(key)
    return self._sections[key]
end

function BuilderMixin:GetPage(key)
    return self._pages[key]
end

function BuilderMixin:GetRoot(name)
    self:_initializeRoot(name)
    return self
end

function BuilderMixin:HasCategory(category)
    return category ~= nil and self._layouts[category] ~= nil
end

local function registerPageDefinition(owner, pageDef, defaultName)
    assert(type(pageDef) == "table", "registerPageDefinition: page definition must be a table")
    assert(pageDef.key, "registerPageDefinition: page definition requires key")

    local creator = owner._root and createSectionPage or createRootPage
    return creator(owner, pageDef.key, pageDef.rows, {
        name = pageDef.name or defaultName,
        onShow = pageDef.onShow,
        onHide = pageDef.onHide,
        onRegistered = pageDef.onRegistered,
        disabled = pageDef.disabled,
        hidden = pageDef.hidden,
        order = pageDef.order,
        path = pageDef.path,
    })
end

function BuilderMixin:Register(spec)
    assertRootConfigured(self, "Register")
    assert(type(spec) == "table", "Register: spec must be a table")

    if spec.page then
        registerRootPage(self, registerPageDefinition(self, spec.page, self.name))
    end

    for _, sectionDef in ipairs(spec.sections or {}) do
        assert(type(sectionDef) == "table", "Register: each section definition must be a table")
        assert(sectionDef.key, "Register: each section requires a key")
        assert(sectionDef.name, "Register: each section requires a name")

        local section = createSection(self, sectionDef.key, sectionDef.name, {
            display = sectionDef.display,
            order = sectionDef.order,
            path = sectionDef.path,
        })

        if sectionDef.pages then
            assert(sectionDef.rows == nil, "Register: a section cannot define both rows and pages")
            for _, pageDef in ipairs(sectionDef.pages) do
                registerPageDefinition(section, pageDef, sectionDef.name)
            end
        else
            createSectionPage(section, sectionDef.pageKey or "main", sectionDef.rows, {
                name = sectionDef.pageName or (sectionDef.display == "nested" and sectionDef.name or nil),
                onShow = sectionDef.onShow,
                onHide = sectionDef.onHide,
                onRegistered = sectionDef.onRegistered,
                disabled = sectionDef.disabled,
                hidden = sectionDef.hidden,
                order = sectionDef.pageOrder,
            })
        end

        registerSection(section)
    end

    return self
end

function BuilderMixin:_initializeRoot(name)
    if not self._rootCategory then
        assert(name, "_initializeRoot: name is required")
        self:_createRootCategory(name)
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

lib._loadState.open = nil
