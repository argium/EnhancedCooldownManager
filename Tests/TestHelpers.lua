-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = {}

function TestHelpers.loadChunk(paths, errorMessage)
    for _, path in ipairs(paths) do
        local chunk = loadfile(path)
        if chunk then
            return chunk
        end
    end
    error(errorMessage)
end

function TestHelpers.captureGlobals(names)
    local snapshot = {}
    for _, name in ipairs(names) do
        snapshot[name] = _G[name]
    end
    return snapshot
end

function TestHelpers.restoreGlobals(snapshot)
    for name, value in pairs(snapshot) do
        _G[name] = value
    end
end

--- Deep-clone a Lua value (tables are cloned recursively).
local function deepClone(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepClone(v) end
    return out
end

--- Deep-equality comparison for two Lua values.
local function deepEquals(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not deepEquals(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

--- Create a minimal stub initializer returned by Settings.CreateCheckbox etc.
local function makeInitializer(setting)
    local init = {}
    init._parentInit = nil
    init._modifyPredicates = {}
    init._shownPredicates = {}

    function init:SetParentInitializer(parent, predicate)
        self._parentInit = parent
        self._parentPredicate = predicate
    end

    function init:AddModifyPredicate(fn)
        self._modifyPredicates[#self._modifyPredicates + 1] = fn
    end

    function init:AddShownPredicate(fn)
        self._shownPredicates[#self._shownPredicates + 1] = fn
    end

    function init:GetSetting()
        return setting
    end

    function init:EvaluateModifyPredicates()
        for _, fn in ipairs(self._modifyPredicates) do
            if not fn() then return false end
        end
        return true
    end

    return init
end

--- Create a minimal stub setting returned by Settings.RegisterProxySetting.
local function makeSetting(getter, setter, default)
    local setting = {}
    function setting:GetValue()
        return getter()
    end
    function setting:SetValue(value)
        setter(value)
    end
    setting._default = default
    return setting
end

--- Setup a minimal LibStub stub for tests.
function TestHelpers.setupLibStub()
    local libs = {}
    local LibStub = {
        NewLibrary = function(self, major, minor)
            if not libs[major] or libs[major].minor < minor then
                libs[major] = { minor = minor, lib = {} }
                return libs[major].lib
            end
            return nil
        end,
    }
    setmetatable(LibStub, {
        __call = function(self, major, silent)
            local entry = libs[major]
            if entry then return entry.lib end
            if not silent then error("Library not found: " .. major) end
            return nil
        end,
    })
    _G.LibStub = LibStub
    return LibStub
end

--- Install all Settings API stubs into _G. Returns the list of global names
--- that were set, so they can be captured/restored.
function TestHelpers.setupSettingsStubs()
    local globals = {
        "Settings", "CreateSettingsListSectionHeaderInitializer",
        "CreateSettingsButtonInitializer", "MinimalSliderWithSteppersMixin",
        "CreateColor", "CreateColorFromHexString", "StaticPopupDialogs", "StaticPopup_Show", "YES", "NO",
        "ECM_CloneValue", "ECM_DeepEquals",
        "CreateFromMixins", "SettingsListElementInitializer",
    }

    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },

        RegisterVerticalLayoutCategory = function(name)
            local layout = { _initializers = {} }
            function layout:AddInitializer(init)
                self._initializers[#self._initializers + 1] = init
            end
            return {
                _name = name,
                _id = name,
                GetID = function(self) return self._id end,
                GetLayout = function() return layout end,
            }, layout
        end,

        RegisterVerticalLayoutSubcategory = function(parent, name)
            local layout = { _initializers = {} }
            function layout:AddInitializer(init)
                self._initializers[#self._initializers + 1] = init
            end
            return {
                _name = name,
                _parent = parent,
                GetLayout = function() return layout end,
            }, layout
        end,

        RegisterCanvasLayoutSubcategory = function(parent, frame, name)
            return {
                _name = name,
                _parent = parent,
                _frame = frame,
            }
        end,

        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,

        RegisterInitializer = function(category, initializer)
            if category and category.GetLayout then
                local layout = category:GetLayout()
                if layout and layout.AddInitializer then
                    layout:AddInitializer(initializer)
                end
            end
        end,

        CreateElementInitializer = function(frameTemplate, data)
            local init = _G.CreateFromMixins(_G.SettingsListElementInitializer)
            init:Init(frameTemplate)
            init.data = data or {}
            return init
        end,

        RegisterProxySetting = function(cat, variable, varType, name, default, getter, setter)
            return makeSetting(getter, setter, default)
        end,

        CreateCheckbox = function(cat, setting, tooltip)
            return makeInitializer(setting)
        end,

        CreateSlider = function(cat, setting, options, tooltip)
            return makeInitializer(setting)
        end,

        CreateDropdown = function(cat, setting, optionsGen, tooltip)
            local init = makeInitializer(setting)
            init._optionsGen = optionsGen
            return init
        end,

        CreateColorSwatch = function(cat, setting, tooltip)
            return makeInitializer(setting)
        end,

        CreateSliderOptions = function(min, max, step)
            local opts = { min = min, max = max, step = step, _labelFormatter = nil, _labelFormatterLocation = nil }
            function opts:SetLabelFormatter(location, formatter)
                self._labelFormatterLocation = location
                self._labelFormatter = formatter
            end
            return opts
        end,

        CreateControlTextContainer = function()
            local data = {}
            return {
                Add = function(self, value, label)
                    data[#data + 1] = { value = value, label = label }
                end,
                GetData = function()
                    return data
                end,
            }
        end,
    }

    _G.CreateSettingsListSectionHeaderInitializer = function(text)
        return { _type = "header", _text = text }
    end

    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip, fullWidth)
        local init = makeInitializer(nil)
        init._type = "button"
        init._name = name
        init._buttonText = buttonText
        init._onClick = onClick
        init._tooltip = tooltip
        return init
    end

    _G.MinimalSliderWithSteppersMixin = {
        Label = { Right = 1 },
    }

    _G.CreateColor = function(r, g, b, a)
        return { r = r, g = g, b = b, a = a or 1 }
    end

    _G.CreateColorFromHexString = function(hex)
        local a = tonumber(hex:sub(1, 2), 16) / 255
        local r = tonumber(hex:sub(3, 4), 16) / 255
        local g = tonumber(hex:sub(5, 6), 16) / 255
        local b = tonumber(hex:sub(7, 8), 16) / 255
        return { r = r, g = g, b = b, a = a }
    end

    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function(name)
        local dialog = _G.StaticPopupDialogs[name]
        if dialog and dialog.OnAccept then
            dialog.OnAccept()
        end
    end
    _G.YES = "Yes"
    _G.NO = "No"

    _G.ECM_CloneValue = deepClone
    _G.ECM_DeepEquals = deepEquals

    _G.CreateFromMixins = function(...)
        local result = {}
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if mixin then
                for k, v in pairs(mixin) do
                    result[k] = v
                end
            end
        end
        return result
    end

    _G.SettingsListElementInitializer = {
        Init = function(self, templateName) self._template = templateName end,
        SetExtent = function(self, extent) self._extent = extent end,
        GetExtent = function(self) return self._extent end,
        GetData = function(self) return self.data end,
        SetSetting = function(self, setting)
            self.data = self.data or {}
            self.data.setting = setting
        end,
        SetParentInitializer = function(self, parent, predicate)
            self._parentInit = parent
            self._parentPredicate = predicate
        end,
        AddModifyPredicate = function(self, fn)
            self._modifyPredicates = self._modifyPredicates or {}
            self._modifyPredicates[#self._modifyPredicates + 1] = fn
        end,
        AddShownPredicate = function(self, fn)
            self._shownPredicates = self._shownPredicates or {}
            self._shownPredicates[#self._shownPredicates + 1] = fn
        end,
        GetSetting = function(self)
            return self.data and self.data.setting
        end,
    }

    return globals
end

return TestHelpers
