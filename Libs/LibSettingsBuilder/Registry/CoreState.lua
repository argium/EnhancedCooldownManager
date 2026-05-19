-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

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
---@class LibSettingsBuilderConfig
---@field name string|nil Gets the root category display name.
---@field onChanged LibSettingsBuilderChangedCallback Gets the callback fired after a row setter completes.
---@field store table|(fun(): table)|nil Gets the store table or lazy provider used by path-bound rows.
---@field defaults table|(fun(): table)|nil Gets the defaults table or lazy provider used by path-bound rows.
---@field defaultsConfirmation fun(pageName: string, onAccept: fun())|nil Gets the optional confirmation hook shown before any category-header `Defaults` reset.
---@field getNestedValue LibSettingsBuilderGetNestedValue|nil Gets the custom nested-path reader used by path-bound rows.
---@field setNestedValue LibSettingsBuilderSetNestedValue|nil Gets the custom nested-path writer used by path-bound rows.
---@field page LibSettingsBuilderPageConfig|nil Gets the optional root-owned page definition.
---@field sections LibSettingsBuilderSectionConfig[]|nil Gets the optional section definitions registered under the root category.

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local foundation = internal.foundation
local interop = internal.interop
local registry = internal.registry
lib._runtimeApi = lib._runtimeApi or {}

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
        resolve = function(_, path)
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
        read = function(_, path)
            return getNested(config.getStore(), path)
        end,
    }
end

function registry.makeVarName(self, spec)
    local id = spec.key or spec.path
    return self._config.varPrefix .. "_" .. tostring(id):gsub("%.", "_")
end

function registry.createCallbackContext(self, spec, setting)
    return {
        builder = self,
        category = registry.resolveCategory(self, spec),
        key = spec.key,
        page = spec._page and spec._page._handle,
        path = spec.path,
        setting = setting,
        spec = spec,
    }
end

function registry.resolveCategory(self, spec)
    return spec.category or self._currentSubcategory or self._rootCategory
end

function registry.registerCategoryRefreshable(self, category, initializer)
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

function registry.postSet(self, spec, value, setting)
    local ctx = registry.createCallbackContext(self, spec, setting)
    if spec.onSet then
        spec.onSet(ctx, value)
    end
    self._config.onChanged(ctx, value)
    registry.reevaluateReactiveControls(self)
end

function registry.resolveBinding(self, spec)
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

function registry.makeProxySetting(self, spec, varType, defaultFallback, binding)
    local variable = registry.makeVarName(self, spec)
    local category = registry.resolveCategory(self, spec)
    local setting

    binding = binding or registry.resolveBinding(self, spec)

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
        registry.postSet(self, spec, value, setting)
    end

    local function setValueNoCallback(_, value)
        value = applyValue(value)
        self._config.onChanged(registry.createCallbackContext(self, spec, setting), value)
        registry.reevaluateReactiveControls(self)
    end

    local defaultValue = binding.default
    if spec.getTransform then
        defaultValue = spec.getTransform(defaultValue)
    end
    if defaultValue == nil then
        defaultValue = defaultFallback
    end

    setting = interop.registerProxySetting(category, variable, varType, spec.name, defaultValue, getter, setter)
    setting.SetValueNoCallback = setValueNoCallback

    return setting, category
end

function registry.makeColorSetting(self, spec)
    local variable = registry.makeVarName(self, spec)
    local category = registry.resolveCategory(self, spec)
    local binding = registry.resolveBinding(self, spec)
    local setting

    local function getter()
        return foundation.colorTableToHex(binding.get())
    end

    local function setter(hexValue)
        local color = interop.createColorFromHexString(hexValue)
        local value = { r = color.r, g = color.g, b = color.b, a = color.a }
        binding.set(value)
        registry.postSet(self, spec, value, setting)
    end

    setting = interop.registerProxySetting(
        category,
        variable,
        interop.getVarTypeString(),
        spec.name,
        foundation.colorTableToHex(binding.default or {}),
        getter,
        setter
    )

    return setting, category
end

function registry.isParentEnabled(self, spec)
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

function registry.isControlEnabled(self, spec)
    if spec.disabled and spec.disabled() then
        return false
    end
    return registry.isParentEnabled(self, spec)
end

function registry.applyReactiveControlStates(self)
    for _, entry in ipairs(self._reactiveControls) do
        interop.applyInitializerEnabledState(entry.initializer, {
            canvas = entry.canvas,
            isEnabled = function()
                return registry.isControlEnabled(self, entry.spec)
            end,
        })
    end
end

function registry.reevaluateReactiveControls(self)
    interop.reevaluateVisibleSettingsFrames()
    registry.applyReactiveControlStates(self)
end

function registry.applyModifiers(self, initializer, spec, canvas)
    interop.applyInitializerModifiers(initializer, {
        disabled = spec.disabled,
        hidden = spec.hidden,
        parentInitializer = spec._parentInitializer,
        canvas = canvas,
        isEnabled = function()
            return registry.isControlEnabled(self, spec)
        end,
        isParentEnabled = function()
            return registry.isParentEnabled(self, spec)
        end,
    })

    if spec.disabled or spec._parentInitializer or canvas then
        self._reactiveControls[#self._reactiveControls + 1] = { initializer = initializer, canvas = canvas, spec = spec }
    end
end

function registry.applyBuildResult(self, spec, result)
    if not result then
        return
    end

    local initializer = result.initializer
    if result.registration == "layout" then
        interop.addLayoutInitializer(self._layouts[spec.category], initializer)
    elseif result.registration == "category" then
        interop.registerInitializer(spec.category, initializer)
    end

    if result.refreshable then
        registry.registerCategoryRefreshable(self, spec.category, initializer)
    end

    registry.applyModifiers(self, initializer, spec, result.canvas)

    return initializer, result.setting
end

function registry.storeCategory(self, name, category, layout)
    self._subcategories[name] = category
    self._subcategoryNames[category] = name
    self._layouts[category] = layout
    return category
end

function registry.newRuntime(config)
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

    return setmetatable({
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
    }, { __index = lib._runtimeApi })
end

function lib.New(selfOrConfig, maybeConfig)
    local config = maybeConfig or selfOrConfig
    assert(type(config) == "table", "LibSettingsBuilder.New: config table is required")

    assert(config.varPrefix == nil, "LibSettingsBuilder: varPrefix is not part of the v2 config")
    assert(config.pathAdapter == nil, "LibSettingsBuilder: pathAdapter is not part of the v2 config")
    assert(config.compositeDefaults == nil, "LibSettingsBuilder: compositeDefaults is not part of the v2 config")
    config.varPrefix = foundation.makeVarPrefixFromName(config.name)
    assert(config.onChanged, "LibSettingsBuilder: onChanged is required")

    local lsb = registry.newRuntime(config)

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
