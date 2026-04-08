-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = {}

function TestHelpers.LoadChunk(path, errorMessage)
    local chunk = loadfile(path)
    if chunk then
        return chunk
    end
    error(errorMessage)
end

--- Load a stub from Tests/stubs/.
function TestHelpers.LoadStub(name)
    return TestHelpers.LoadChunk("Tests/stubs/" .. name, "Unable to load Tests/stubs/" .. name)()
end

function TestHelpers.CaptureGlobals(names)
    local snapshot = {}
    for _, name in ipairs(names) do
        snapshot[name] = _G[name]
    end
    return snapshot
end

function TestHelpers.RestoreGlobals(snapshot)
    for name, value in pairs(snapshot) do
        _G[name] = value
    end
end

--- Deep-clone a Lua value (tables are cloned recursively).
local function deepClone(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for k, v in pairs(value) do
        out[k] = deepClone(v)
    end
    return out
end
TestHelpers.deepClone = deepClone

--- Deep-equality comparison for two Lua values.
local function deepEquals(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not deepEquals(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end
TestHelpers.deepEquals = deepEquals

--- Create a minimal stub initializer returned by Settings.CreateCheckbox etc.
local function makeInitializer(setting)
    return {
        _parentInit = nil,
        _modifyPredicates = {},
        _shownPredicates = {},
        _enabled = true,
        SetParentInitializer = function(self, parent, _)
            self._parentInit = parent
        end,
        SetEnabled = function(self, enabled)
            self._enabled = enabled
        end,
        AddModifyPredicate = function(self, fn)
            self._modifyPredicates[#self._modifyPredicates + 1] = fn
        end,
        AddShownPredicate = function(self, fn)
            self._shownPredicates[#self._shownPredicates + 1] = fn
        end,
        GetSetting = function()
            return setting
        end,
        EvaluateModifyPredicates = function(self)
            for _, fn in ipairs(self._modifyPredicates) do
                if not fn() then
                    return false
                end
            end
            return true
        end,
    }
end

--- Create a minimal stub setting returned by Settings.RegisterProxySetting.
local function makeSetting(getter, setter, default, name, variable)
    local setting = {
        _default = default,
        _lsbCallbacks = {},
        _lsbVariable = variable,
        _name = name,
    }

    function setting:GetValue()
        return getter()
    end

    function setting:_lsbNotifyValueChanged(value)
        for _, handle in ipairs(self._lsbCallbacks) do
            handle.callback(handle.owner or self, value, self)
        end
    end

    function setting:SetValue(value)
        setter(value)
        self:_lsbNotifyValueChanged(self:GetValue())
    end

    return setting
end

--- Setup a minimal LibStub stub for tests.
function TestHelpers.SetupLibStub()
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
            if entry then
                return entry.lib
            end
            if not silent then
                error("Library not found: " .. major)
            end
            return nil
        end,
    })
    _G.LibStub = LibStub
    return LibStub
end

--- Registers a minimal LibEditMode stub in an existing LibStub.
--- Must be called after LibStub is available.
function TestHelpers.SetupLibEditModeStub()
    assert(_G.LibStub, "LibStub must be set up before calling SetupLibEditModeStub")
    local lib = _G.LibStub:NewLibrary("LibEditMode", 15) or _G.LibStub("LibEditMode")
    lib.callbacks = {}
    lib.frameSelections = {}
    lib.addFrameSettingsCalls = {}
    lib.AddFrame = function(_, frame)
        lib.frameSelections[frame] = {
            HookScript = function(self, event, callback)
                self[event] = callback
            end,
            Hide = function(self)
                self.hidden = true
            end,
        }
    end
    lib.AddFrameSettings = function(_, frame, settings)
        lib.addFrameSettingsCalls[frame] = settings
    end
    lib.RegisterCallback = function(_, eventName, callback)
        lib.callbacks[eventName] = callback
    end
    lib.GetActiveLayoutName = function()
        return "Modern"
    end
    lib.IsInEditMode = function()
        return false
    end
    lib.SettingType = { Slider = 0, Dropdown = 1 }
    return lib
end

--- Install all Settings API stubs into _G. Returns the list of global names
--- that were set, so they can be captured/restored.
function TestHelpers.SetupSettingsStubs()
    local globals = {
        "Settings",
        "CreateSettingsListSectionHeaderInitializer",
        "CreateSettingsButtonInitializer",
        "MinimalSliderWithSteppersMixin",
        "CreateColor",
        "CreateColorFromHexString",
        "StaticPopupDialogs",
        "StaticPopup_Show",
        "YES",
        "NO",
        "ECM_DeepEquals",
        "CreateFromMixins",
        "SettingsListElementInitializer",
    }

    local function makeLayout()
        local layout = { _initializers = {} }
        layout.AddInitializer = function(self, init)
            self._initializers[#self._initializers + 1] = init
        end
        return layout
    end

    local proxySettingsByVariable = {}

    _G.Settings = {
        VarType = { Boolean = "boolean", Number = "number", String = "string" },

        RegisterVerticalLayoutCategory = function(name)
            local layout = makeLayout()
            return {
                _name = name,
                _id = name,
                GetID = function(self)
                    return self._id
                end,
                GetLayout = function()
                    return layout
                end,
            },
                layout
        end,

        RegisterVerticalLayoutSubcategory = function(parent, name)
            local layout = makeLayout()
            local id = parent._id .. "." .. name
            return {
                _name = name,
                _parent = parent,
                _id = id,
                GetID = function(self)
                    return self._id
                end,
                GetLayout = function()
                    return layout
                end,
            },
                layout
        end,

        RegisterCanvasLayoutSubcategory = function(parent, frame, name)
            local layout = makeLayout()
            return {
                _name = name,
                _parent = parent,
                _frame = frame,
                GetLayout = function()
                    return layout
                end,
            },
                layout
        end,

        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,

        RegisterInitializer = function(category, initializer)
            local layout = category and category.GetLayout and category:GetLayout()
            if layout and layout.AddInitializer then
                layout:AddInitializer(initializer)
            end
        end,

        CreateElementInitializer = function(frameTemplate, data)
            local init = _G.CreateFromMixins(_G.SettingsListElementInitializer)
            init:Init(frameTemplate)
            init.data = data or {}
            return init
        end,

        RegisterProxySetting = function(_, variable, _, name, default, getter, setter)
            local setting = makeSetting(getter, setter, default, name, variable)
            proxySettingsByVariable[variable] = setting
            return setting
        end,

        CreateCheckbox = function(cat, setting)
            return makeInitializer(setting)
        end,
        CreateSlider = function(cat, setting)
            return makeInitializer(setting)
        end,
        CreateColorSwatch = function(cat, setting)
            return makeInitializer(setting)
        end,

        CreateDropdown = function(cat, setting, optionsGen)
            local init = makeInitializer(setting)
            init._optionsGen = optionsGen
            setting._optionsGen = optionsGen
            return init
        end,

        CreateSliderOptions = function(min, max, step)
            local opts = { min = min, max = max, step = step }
            opts.SetLabelFormatter = function(self, location, formatter)
                self._labelFormatterLocation = location
                self._labelFormatter = formatter
            end
            return opts
        end,

        CreateCallbackHandleContainer = function()
            return {
                _handles = {},
                IsEmpty = function(self)
                    return #self._handles == 0
                end,
                AddHandle = function(self, handle)
                    self._handles[#self._handles + 1] = handle
                end,
                SetOnValueChangedCallback = function(self, variable, callback, owner)
                    local handle = { variable = variable, callback = callback, owner = owner }
                    self:AddHandle(handle)
                    local setting = proxySettingsByVariable[variable]
                    if setting then
                        handle.setting = setting
                        setting._lsbCallbacks[#setting._lsbCallbacks + 1] = handle
                    end
                end,
                Unregister = function(self)
                    for _, handle in ipairs(self._handles) do
                        local setting = handle.setting
                        if setting and setting._lsbCallbacks then
                            for i = #setting._lsbCallbacks, 1, -1 do
                                if setting._lsbCallbacks[i] == handle then
                                    table.remove(setting._lsbCallbacks, i)
                                end
                            end
                        end
                    end
                    self._handles = {}
                    self._unregistered = true
                end,
            }
        end,

        CreateControlTextContainer = function()
            local data = {}
            return {
                Add = function(_, value, label)
                    data[#data + 1] = { value = value, label = label }
                end,
                GetData = function()
                    return data
                end,
            }
        end,
    }

    _G.CreateSettingsListSectionHeaderInitializer = function(text)
        local init = makeInitializer(nil)
        init._type = "header"
        init._text = text
        return init
    end

    _G.CreateSettingsButtonInitializer = function(name, buttonText, onClick, tooltip)
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
        Event = { OnValueChanged = "OnValueChanged" },
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
    _G.StaticPopup_Show = function(name, _text1, _text2, data)
        local dialog = _G.StaticPopupDialogs[name]
        if dialog and dialog.OnAccept then
            if dialog.hasEditBox then
                local text = ""
                local editBox = { GetText = function() return text end, SetText = function(_, t) text = t end, HighlightText = function() end }
                local self = { editBox = editBox, button1 = { IsEnabled = function() return true end } }
                if dialog.OnShow then dialog.OnShow(self) end
                dialog.OnAccept(self, data)
            else
                dialog.OnAccept(nil, data)
            end
        end
    end
    _G.YES = "Yes"
    _G.NO = "No"
    _G.OKAY = "Okay"
    _G.CANCEL = "Cancel"
    _G.strtrim = function(s) return (s:match("^%s*(.-)%s*$")) end

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
        Init = function(self, templateName)
            self._template = templateName
        end,
        SetExtent = function(self, extent)
            self._extent = extent
        end,
        GetExtent = function(self)
            return self._extent
        end,
        GetData = function(self)
            return self.data
        end,
        SetSetting = function(self, setting)
            self.data = self.data or {}
            self.data.setting = setting
        end,
        SetParentInitializer = function(self, parent, _)
            self._parentInit = parent
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

--------------------------------------------------------------------------------
-- Shared mock builders for frame/texture test stubs
--------------------------------------------------------------------------------

local unpack_fn = table.unpack or unpack
TestHelpers.unpack_fn = unpack_fn

function TestHelpers.incCalls(obj, name)
    obj.__calls = obj.__calls or {}
    obj.__calls[name] = (obj.__calls[name] or 0) + 1
end

function TestHelpers.getCalls(obj, name)
    return (obj.__calls and obj.__calls[name]) or 0
end

function TestHelpers.color(r, g, b, a)
    return { r = r, g = g, b = b, a = a or 1 }
end

function TestHelpers.makeRegion(regionType)
    local region = { __objectType = regionType or "Texture", __calls = {} }
    function region:IsObjectType(expected)
        return self.__objectType == expected
    end
    function region:SetAllPoints() end
    return region
end

function TestHelpers.makeTexture(opts)
    local incCalls = TestHelpers.incCalls
    opts = opts or {}
    local texture = TestHelpers.makeRegion("Texture")
    texture.__atlas = opts.atlas
    texture.__texture = opts.texture
    texture.__textureFileID = opts.textureFileID
    texture.__colorTexture = opts.colorTexture
            and { opts.colorTexture[1], opts.colorTexture[2], opts.colorTexture[3], opts.colorTexture[4] }
        or nil
    texture.__vertexColor = opts.vertexColor
            and { opts.vertexColor[1], opts.vertexColor[2], opts.vertexColor[3], opts.vertexColor[4] }
        or nil

    function texture:GetAtlas()
        return self.__atlas
    end
    function texture:GetTextureFileID()
        return self.__textureFileID
    end

    for _, prop in ipairs({ { "ColorTexture", "__colorTexture" }, { "VertexColor", "__vertexColor" } }) do
        texture["Set" .. prop[1]] = function(self, r, g, b, a)
            incCalls(self, "Set" .. prop[1])
            self[prop[2]] = { r, g, b, a }
        end
        texture["Get" .. prop[1]] = function(self)
            if self[prop[2]] then
                return self[prop[2]][1], self[prop[2]][2], self[prop[2]][3], self[prop[2]][4]
            end
        end
    end

    function texture:SetTexture(tex)
        incCalls(self, "SetTexture")
        self.__texture = tex
    end
    function texture:GetTexture()
        return self.__texture
    end

    return texture
end

function TestHelpers.makeFrame(opts)
    local incCalls = TestHelpers.incCalls
    opts = opts or {}
    local anchors = {}
    for i = 1, #(opts.anchors or {}) do
        local a = opts.anchors[i]
        anchors[i] = { a[1], a[2], a[3], a[4], a[5] }
    end
    local frame = {
        __name = opts.name,
        __shown = opts.shown ~= false,
        __height = opts.height or 0,
        __width = opts.width or 0,
        __alpha = opts.alpha == nil and 1 or opts.alpha,
        __frameStrata = opts.frameStrata,
        __anchors = anchors,
        __regions = opts.regions or {},
        __scripts = opts.scripts or {},
        __calls = {},
    }

    function frame:GetName()
        return self.__name
    end

    for _, prop in ipairs({ { "Height", "__height" }, { "Width", "__width" }, { "Alpha", "__alpha" } }) do
        frame["Set" .. prop[1]] = function(self, val)
            incCalls(self, "Set" .. prop[1])
            self[prop[2]] = val
        end
        frame["Get" .. prop[1]] = function(self)
            return self[prop[2]]
        end
    end

    function frame:SetSize(width, height)
        self:SetWidth(width)
        self:SetHeight(height)
    end
    function frame:GetSize()
        return self.__width, self.__height
    end
    function frame:SetFrameStrata(strata)
        self.__frameStrata = strata
    end
    function frame:GetFrameStrata()
        return self.__frameStrata
    end

    function frame:Show()
        incCalls(self, "Show")
        self.__shown = true
    end
    function frame:Hide()
        incCalls(self, "Hide")
        self.__shown = false
    end
    function frame:IsShown()
        return self.__shown
    end
    function frame:SetAllPoints() end
    function frame:ClearAllPoints()
        incCalls(self, "ClearAllPoints")
        self.__anchors = {}
    end
    function frame:SetPoint(point, relativeTo, relativePoint, x, y)
        incCalls(self, "SetPoint")
        self.__anchors[#self.__anchors + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end
    function frame:GetNumPoints()
        return #self.__anchors
    end
    function frame:GetPoint(index)
        local a = self.__anchors[index]
        if a then
            return a[1], a[2], a[3], a[4], a[5]
        end
    end
    function frame:GetRegions()
        return unpack_fn(self.__regions)
    end
    function frame:SetScript(event, callback)
        self.__scripts[event] = callback
    end
    function frame:GetScript(event)
        return self.__scripts[event]
    end
    function frame:RegisterEvent(event)
        self.__registeredEvents = self.__registeredEvents or {}
        self.__registeredEvents[event] = true
    end
    function frame:UnregisterEvent(event)
        self.__unregisteredEvents = self.__unregisteredEvents or {}
        self.__unregisteredEvents[event] = true
        if self.__registeredEvents then
            self.__registeredEvents[event] = nil
        end
    end
    function frame:HookScript() end
    function frame:GetEffectiveScale()
        return 1
    end
    function frame:GetBackdropBorderColor()
        return 0, 0, 0, 1
    end
    function frame:GetBackdrop()
        return nil
    end
    function frame:GetColorTexture()
        return nil
    end
    function frame:SetColorTexture() end
    function frame:GetVertexColor()
        return nil
    end
    function frame:IsObjectType()
        return false
    end

    return frame
end

function TestHelpers.makeHookableFrame(opts)
    opts = type(opts) == "table" and opts or { shown = opts }

    local frame = TestHelpers.makeFrame(opts)
    frame._hooks = {}
    frame._children = opts.children or {}

    function frame:HookScript(scriptName, callback)
        self._hooks[scriptName] = self._hooks[scriptName] or {}
        self._hooks[scriptName][#self._hooks[scriptName] + 1] = callback
    end

    function frame:GetHookCount(scriptName)
        return self._hooks[scriptName] and #self._hooks[scriptName] or 0
    end

    function frame:GetChildren()
        return unpack_fn(self._children)
    end

    local baseGetPoint = frame.GetPoint
    function frame:GetPoint(index)
        return baseGetPoint(self, index or 1)
    end

    return frame
end

function TestHelpers.makeStatusBar(opts)
    local incCalls = TestHelpers.incCalls
    opts = opts or {}
    local bar = TestHelpers.makeFrame(opts)
    bar.__statusTexture = opts.statusTexture or TestHelpers.makeTexture({ texture = opts.texturePath })
    bar.__statusBarColor = opts.statusBarColor
            and { opts.statusBarColor[1], opts.statusBarColor[2], opts.statusBarColor[3], opts.statusBarColor[4] }
        or { 1, 1, 1, 1 }

    function bar:SetStatusBarTexture(texturePath)
        incCalls(self, "SetStatusBarTexture")
        if self.__statusTexture and self.__statusTexture.SetTexture then
            self.__statusTexture:SetTexture(texturePath)
        end
    end
    function bar:GetStatusBarTexture()
        return self.__statusTexture
    end
    function bar:SetStatusBarColor(r, g, b, a)
        incCalls(self, "SetStatusBarColor")
        self.__statusBarColor = { r, g, b, a or 1 }
    end
    function bar:GetStatusBarColor()
        return self.__statusBarColor[1], self.__statusBarColor[2], self.__statusBarColor[3], self.__statusBarColor[4]
    end

    return bar
end

function TestHelpers.makeBorder(opts)
    local incCalls = TestHelpers.incCalls
    opts = opts or {}
    local border = TestHelpers.makeFrame({ name = opts.name, shown = opts.shown ~= false })
    border.__backdrop = opts.backdrop
    border.__borderColor = opts.borderColor
            and { opts.borderColor[1], opts.borderColor[2], opts.borderColor[3], opts.borderColor[4] }
        or { 0, 0, 0, 1 }

    function border:SetBackdrop(backdrop)
        incCalls(self, "SetBackdrop")
        self.__backdrop = backdrop
    end
    function border:GetBackdrop()
        return self.__backdrop
    end
    function border:SetBackdropBorderColor(r, g, b, a)
        incCalls(self, "SetBackdropBorderColor")
        self.__borderColor = { r, g, b, a or 1 }
    end
    function border:GetBackdropBorderColor()
        return self.__borderColor[1], self.__borderColor[2], self.__borderColor[3], self.__borderColor[4]
    end

    return border
end

local function assertEqual(expected, actual, label)
    local bustedAssert = _G.assert
    local are = type(bustedAssert) == "table" and rawget(bustedAssert, "are") or nil
    local eq = are and rawget(are, "equal") or nil
    if eq then
        eq(expected, actual)
        return
    end

    assert(expected == actual, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

--- Asserts anchor values match. Uses busted's assert when available, plain assert otherwise.
function TestHelpers.assertAnchor(frame, index, point, relativeTo, relativePoint, x, y)
    local ap, ar, arp, ax, ay = frame:GetPoint(index)
    assertEqual(point, ap, "anchor point")
    assertEqual(relativeTo, ar, "relativeTo")
    assertEqual(relativePoint, arp, "relativePoint")
    assertEqual(x, ax, "x")
    assertEqual(y, ay, "y")
end

--- Resolve a parent-relative anchor position into absolute coordinates on UIParent.
function TestHelpers.getAbsoluteAnchorPosition(ns, point, x, y, defaultPoint)
    local frameUtil = assert(ns and ns.FrameUtil, "ns.FrameUtil must be initialized")
    local parentFrame = assert(_G.UIParent, "UIParent must be initialized")
    local anchorPoint = point or defaultPoint or ns.Constants.EDIT_MODE_DEFAULT_POINT
    local parentWidth, parentHeight = frameUtil.GetParentSize(parentFrame)
    local anchorX, anchorY = frameUtil.GetParentAnchorPosition(anchorPoint, parentWidth, parentHeight)
    return anchorX + (x or 0), anchorY + (y or 0)
end

--- Assert that a migrated edit-mode position preserves the same absolute placement.
function TestHelpers.assertAbsolutePositionPreserved(ns, beforePoint, beforeRelativePoint, beforeX, beforeY, migrated, defaultPoint)
    local beforeAbsX, beforeAbsY = TestHelpers.getAbsoluteAnchorPosition(
        ns,
        beforeRelativePoint or beforePoint,
        beforeX,
        beforeY,
        defaultPoint
    )
    local afterAbsX, afterAbsY = TestHelpers.getAbsoluteAnchorPosition(
        ns,
        migrated.point,
        migrated.x,
        migrated.y,
        defaultPoint
    )
    assertEqual(beforeAbsX, afterAbsX, "absolute x")
    assertEqual(beforeAbsY, afterAbsY, "absolute y")
end

--------------------------------------------------------------------------------
-- Options test environment
--------------------------------------------------------------------------------

--- Standard list of globals captured/restored by option tests.
TestHelpers.OPTIONS_GLOBALS = {
    "ECM_DeepEquals",
    "Settings",
    "CreateSettingsListSectionHeaderInitializer",
    "CreateSettingsButtonInitializer",
    "MinimalSliderWithSteppersMixin",
    "CreateColor",
    "CreateColorFromHexString",
    "StaticPopupDialogs",
    "StaticPopup_Show",
    "YES",
    "NO",
    "OKAY",
    "CANCEL",
    "strtrim",
    "UnitClass",
    "GetSpecialization",
    "GetSpecializationInfo",
    "Enum",
    "LibStub",
    "CreateFromMixins",
    "SettingsListElementInitializer",
    "GameFontHighlightSmall",
    "GameFontNormal",
    "GameFontDisable",
    "SETTINGS_DEFAULTS",
    "InCombatLockdown",
    "UnitName",
    "date",
    "ColorPickerFrame",
    "CreateFrame",
    "CreateDataProvider",
    "hooksecurefunc",
    "CreateScrollBoxListLinearView",
    "ScrollUtil",
    "SettingsPanel",
    "C_AddOns",
    "issecretvalue",
    "issecrettable",
    "canaccessvalue",
    "canaccesstable",
    "time",
    "C_Timer",
    "C_PartyInfo",
    "IsInInstance",
    "GetInventoryItemID",
    "GetInventoryItemTexture",
    "C_Item",
    "C_Spell",
    "CreateTextureMarkup",
    "CreateAtlasMarkup",
    "GameTooltip",
    "GameTooltip_Hide",
}

--- Load the live Constants.lua and Locales/en.lua to populate ECM.Constants and ECM.L.
function TestHelpers.LoadLiveConstants(ns)
    if not ns.Constants then
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
    end
    if not ns.L then
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)
    end
end

--- Load the live Defaults.lua to populate ECM.defaults.
--- Requires ECM.Constants and Enum to be set up first.
function TestHelpers.LoadLiveDefaults(ns)
    TestHelpers.LoadLiveConstants(ns)
    TestHelpers.LoadChunk("Defaults.lua", "Unable to load Defaults.lua")(nil, ns)
end

--- Create a full default profile for option tests using the live defaults file.
function TestHelpers.MakeOptionsProfile()
    local ns = {}
    TestHelpers.LoadLiveDefaults(ns)
    return deepClone(ns.defaults.profile), deepClone(ns.defaults.profile)
end

--- Install common WoW globals for option tests.
function TestHelpers.SetupOptionsGlobals()
    TestHelpers.SetupLibStub()
    TestHelpers.SetupSettingsStubs()

    _G.ECM_DeepEquals = deepEquals
    _G.GameFontHighlightSmall = "GameFontHighlightSmall"
    _G.GameFontNormal = "GameFontNormal"
    _G.GameFontDisable = "GameFontDisable"
    _G.SETTINGS_DEFAULTS = "Defaults"
    _G.InCombatLockdown = function()
        return false
    end
    _G.C_PartyInfo = {
        IsDelveInProgress = function()
            return false
        end,
    }
    _G.IsInInstance = function()
        return false
    end
    _G.GetInventoryItemID = function()
        return nil
    end
    _G.GetInventoryItemTexture = function()
        return nil
    end
    _G.C_Item = {
        GetItemIconByID = function()
            return nil
        end,
        GetItemNameByID = function()
            return nil
        end,
        DoesItemExistByID = function()
            return true
        end,
        RequestLoadItemDataByID = function() end,
    }
    _G.C_Spell = {
        GetSpellName = function()
            return nil
        end,
        GetSpellTexture = function()
            return nil
        end,
    }
    _G.CreateTextureMarkup = function(texture)
        return "|T" .. tostring(texture) .. "|t"
    end
    _G.CreateAtlasMarkup = function(atlas)
        return "|A" .. tostring(atlas) .. "|a"
    end
    _G.GameTooltip = {
        _title = nil,
        _lines = {},
        _owner = nil,
        _anchor = nil,
        _shown = false,
        SetOwner = function(self, owner, anchor)
            self._owner = owner
            self._anchor = anchor
        end,
        ClearLines = function(self)
            self._title = nil
            self._lines = {}
        end,
        SetText = function(self, text)
            self._title = text
            self._lines = {}
        end,
        AddLine = function(self, text)
            self._lines[#self._lines + 1] = text
        end,
        Show = function(self)
            self._shown = true
        end,
        Hide = function(self)
            self._shown = false
        end,
    }
    _G.GameTooltip_Hide = function()
        if _G.GameTooltip and _G.GameTooltip.Hide then
            _G.GameTooltip:Hide()
        end
    end
    _G.UnitName = function()
        return "TestPlayer"
    end
    _G.date = function()
        return "120000"
    end
    _G.time = function()
        return 1000
    end
    local pendingTimers = {}
    TestHelpers._pendingCTimers = pendingTimers
    _G.C_Timer = {
        After = function(delay, callback)
            pendingTimers[#pendingTimers + 1] = { delay = delay, callback = callback }
        end,
        NewTimer = function(delay, callback)
            local timer = { delay = delay, callback = callback, cancelled = false }
            function timer:Cancel()
                self.cancelled = true
            end
            pendingTimers[#pendingTimers + 1] = timer
            return timer
        end,
    }
    _G.C_AddOns = {
        GetAddOnMetadata = function()
            return nil
        end,
    }
    _G.issecretvalue = function()
        return false
    end
    _G.issecrettable = function()
        return false
    end
    _G.canaccessvalue = function()
        return true
    end
    _G.canaccesstable = function()
        return true
    end
    _G.ColorPickerFrame = {
        SetupColorPickerAndShow = function() end,
        GetColorRGB = function()
            return 1, 1, 1
        end,
        GetColorAlpha = function()
            return 1
        end,
    }

    _G.UnitClass = function()
        return "Warrior", "WARRIOR", 1
    end
    _G.GetSpecialization = function()
        return 1
    end
    _G.GetSpecializationInfo = function()
        return nil, "Arms"
    end

    -- Minimal CreateFrame stub for canvas layouts
    local function makeFrameStub()
        local f = { scripts = {}, hooks = {}, callbacks = {}, _children = {} }
        local noop = function() end
        local value, minValue, maxValue, stepValue = nil, 0, 0, 1
        local shown = false
        local mouseEnabled = false
        local text = ""
        local fontObject = nil
        local anchors = {}
        f.SetScript = function(self, event, fn)
            self.scripts[event] = fn
        end
        f.GetScript = function(self, event)
            return self.scripts[event]
        end
        f.HookScript = function(self, event, fn)
            self.hooks[event] = self.hooks[event] or {}
            self.hooks[event][#self.hooks[event] + 1] = fn
        end
        f.GetHeight = function()
            return 0
        end
        f.SetHeight = noop
        f.SetWidth = noop
        f.SetSize = noop
        f.SetPoint = function(_, point, relativeTo, relativePoint, x, y)
            anchors[#anchors + 1] = { point, relativeTo, relativePoint, x, y }
        end
        f.SetAllPoints = noop
        f.ClearAllPoints = function()
            anchors = {}
        end
        f.GetPoint = function(_, index)
            local anchor = anchors[index or 1]
            if anchor then
                return anchor[1], anchor[2], anchor[3], anchor[4], anchor[5]
            end
        end
        f.GetNumPoints = function()
            return #anchors
        end
        f.Show = function()
            shown = true
        end
        f.Hide = function()
            shown = false
        end
        f.IsShown = function()
            return shown
        end
        f.SetAlpha = noop
        f.EnableMouse = function(_, enabled)
            mouseEnabled = not not enabled
        end
        f.IsMouseEnabled = function()
            return mouseEnabled
        end
        f.GetChildren = function()
            return
        end
        f.SetEnabled = noop
        f.RegisterForClicks = noop
        f.SetAutoFocus = noop
        f.SetNumeric = noop
        f.SetText = function(_, newText)
            text = newText
        end
        f.GetText = function()
            return text
        end
        f.SetWordWrap = noop
        f.SetJustifyH = noop
        f.SetJustifyV = noop
        f.SetColorRGB = noop
        f.SetColorTexture = noop
        f.SetTexture = noop
        f.SetFontObject = function(_, newFontObject)
            fontObject = newFontObject
        end
        f.GetFontObject = function()
            return fontObject
        end
        f.SetFocus = noop
        f.ClearFocus = noop
        f.HighlightText = noop
        f.SetBackdrop = noop
        f.SetBackdropBorderColor = noop
        f.SetMinMaxValues = noop
        f.SetValueStep = noop
        f.SetObeyStepOnDrag = noop
        f.RegisterCallback = function(self, event, fn, owner)
            self.callbacks[event] = self.callbacks[event] or {}
            self.callbacks[event][#self.callbacks[event] + 1] = { fn = fn, owner = owner }
        end
        f.Init = function(self, initialValue, initialMin, initialMax)
            value = initialValue
            minValue = initialMin
            maxValue = initialMax
        end
        f.SetValue = function(self, newValue)
            value = newValue
            for _, callback in ipairs(self.callbacks.OnValueChanged or {}) do
                callback.fn(callback.owner or self, newValue)
            end
        end
        f.GetValue = function()
            return value
        end
        f.SetDataProvider = noop
        f.Slider = {
            SetValueStep = function(_, step)
                stepValue = step
            end,
            GetValueStep = function()
                return stepValue
            end,
            GetMinMaxValues = function()
                return minValue, maxValue
            end,
        }
        f.CreateFontString = function()
            return makeFrameStub()
        end
        f.CreateTexture = function()
            return makeFrameStub()
        end
        -- Auto-create sub-tables on access for template frames
        setmetatable(f, {
            __index = function(t, k)
                if type(k) == "string" and k:sub(1, 1):match("%u") then
                    local child = makeFrameStub()
                    rawset(t, k, child)
                    return child
                end
            end,
        })
        return f
    end
    _G.CreateFrame = function()
        local frame = makeFrameStub()
        frame.RightText = makeFrameStub()
        frame.MinText = makeFrameStub()
        frame.MaxText = makeFrameStub()
        return frame
    end

    _G.CreateDataProvider = function()
        local data = {}
        return {
            Flush = function()
                data = {}
            end,
            Insert = function(_, item)
                data[#data + 1] = item
            end,
            GetSize = function()
                return #data
            end,
        }
    end

    _G.hooksecurefunc = function(tbl, method, hook)
        if type(tbl) == "table" and type(method) == "string" and type(hook) == "function" then
            local orig = tbl[method]
            if type(orig) == "function" then
                tbl[method] = function(...)
                    orig(...)
                    hook(...)
                end
            end
        end
    end

    local settingsPanelScripts = {}
    local settingsPanelCurrentCategory = nil
    _G.SettingsPanel = {
        SelectCategory = function() end,
        DisplayCategory = function() end,
        GetCurrentCategory = function() return settingsPanelCurrentCategory end,
        SetCurrentCategory = function(_, cat) settingsPanelCurrentCategory = cat end,
        IsShown = function() return false end,
        GetSettingsList = function() return nil end,
        HookScript = function(_, event, fn)
            settingsPanelScripts[event] = settingsPanelScripts[event] or {}
            settingsPanelScripts[event][#settingsPanelScripts[event] + 1] = fn
        end,
        _fireScript = function(event)
            for _, fn in ipairs(settingsPanelScripts[event] or {}) do
                fn(_G.SettingsPanel)
            end
        end,
    }

    _G.CreateScrollBoxListLinearView = function()
        local view = {}
        view.SetElementExtent = function() end
        view.SetElementInitializer = function(self, _, fn)
            self._initFn = fn
        end
        return view
    end
    _G.ScrollUtil = { InitScrollBoxListWithScrollBar = function() end }

    _G.Enum = {
        PowerType = {
            Mana = 0,
            Rage = 1,
            Focus = 2,
            Energy = 3,
            RunicPower = 6,
            LunarPower = 8,
            Maelstrom = 11,
            Insanity = 13,
            Fury = 17,
            ArcaneCharges = 16,
            Chi = 12,
            ComboPoints = 4,
            Essence = 19,
            HolyPower = 9,
            SoulShards = 7,
        },
    }
end

function TestHelpers.RunNextTimer()
    local pending = TestHelpers._pendingCTimers or {}
    while #pending > 0 do
        local timer = table.remove(pending, 1)
        if not timer.cancelled and timer.callback then
            timer.callback()
            return true
        end
    end
    return false
end

function TestHelpers.RunAllTimers()
    while TestHelpers.RunNextTimer() do
    end
end

--- Load LibSettingsBuilder and register the shared LibLSMSettingsWidgets test stub.
function TestHelpers.SetupLibSettingsBuilder()
    TestHelpers.LoadChunk("Libs/LibSettingsBuilder/LibSettingsBuilder.lua", "Unable to load LibSettingsBuilder.lua")()

    local lsmw = LibStub:NewLibrary("LibLSMSettingsWidgets-1.0", 1)
    lsmw.GetFontValues = function()
        return { Expressway = "Expressway" }
    end
    lsmw.GetStatusbarValues = function()
        return { Solid = "Solid" }
    end
    lsmw.FONT_PICKER_TEMPLATE = "TestFontPickerTemplate"
    lsmw.TEXTURE_PICKER_TEMPLATE = "TestTexturePickerTemplate"

    return lsmw
end

--- Load LibSettingsBuilder + Options.lua and return the SB and ns.
--- @param profile table Profile data
--- @param defaults table Default profile data
--- @return table SB SettingsBuilder instance
--- @return table ns Addon namespace
function TestHelpers.SetupOptionsEnv(profile, defaults)
    TestHelpers.SetupLibSettingsBuilder()

    local mod = {
        db = {
            profile = profile,
            defaults = { profile = defaults },
            GetCurrentProfile = function()
                return "Default"
            end,
            SetProfile = function() end,
            GetProfiles = function()
                return { "Default", "Other" }
            end,
            CopyProfile = function() end,
            DeleteProfile = function() end,
            ResetProfile = function() end,
            RegisterCallback = function() end,
        },
        NewModule = function(_, name)
            return { moduleName = name }
        end,
        EnableModule = function() end,
        DisableModule = function() end,
    }

    local ns = { Addon = mod, OptionsSections = {} }
    TestHelpers.LoadLiveConstants(ns)
    ns.CloneValue = deepClone
    ns.Runtime = ns.Runtime or {}
    ns.Runtime.ScheduleLayoutUpdate = function() end
    ns.IsDeathKnight = function()
        return false
    end
    ns.ClassUtil = {}

    TestHelpers.LoadChunk("UI/OptionUtil.lua", "Unable to load UI/OptionUtil.lua")(nil, ns)
    TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

    local SB = ns.SettingsBuilder
    SB.CreateRootCategory("Test")

    return SB, ns
end

--- Collect all proxy settings created during a function call.
--- Wraps Settings.RegisterProxySetting to capture variable → setting pairs.
--- @param fn function The function to run (e.g., RegisterSettings)
--- @return table Map of variable name → setting object
function TestHelpers.CollectSettings(fn)
    local captured = {}
    local settings = Settings
    local orig = settings.RegisterProxySetting
    rawset(settings, "RegisterProxySetting", function(cat, variable, varType, name, default, getter, setter)
        local setting = orig(cat, variable, varType, name, default, getter, setter)
        captured[variable] = setting
        return setting
    end)
    fn()
    rawset(settings, "RegisterProxySetting", orig)
    return captured
end

--- Find a button initializer by button text from a layout initializer list.
--- @param initializers table
--- @param buttonText string
--- @return table|nil
function TestHelpers.FindButtonInitializer(initializers, buttonText)
    for _, initializer in ipairs(initializers or {}) do
        if initializer._type == "button" and initializer._buttonText == buttonText then
            return initializer
        end
    end
    return nil
end

--- Override StaticPopup_Show to capture the popup key and auto-accept it.
--- For edit-box dialogs, optionally sets provided text before OnAccept.
--- @param editText string|nil
--- @return function getShownPopupName
function TestHelpers.InstallPopupAutoAccept(editText)
    local shown
    _G.StaticPopup_Show = function(name, _text1, _text2, data)
        shown = name
        local dialog = _G.StaticPopupDialogs and _G.StaticPopupDialogs[name]
        if not dialog then
            return
        end

        if dialog.hasEditBox then
            local text = ""
            local editBox = {
                GetText = function()
                    return text
                end,
                SetText = function(_, value)
                    text = value
                end,
                HighlightText = function() end,
            }
            local popupFrame = {
                EditBox = editBox,
                editBox = editBox,
                button1 = {
                    IsEnabled = function()
                        return true
                    end,
                },
            }

            if dialog.OnShow then
                dialog.OnShow(popupFrame)
            end
            if editText ~= nil then
                editBox:SetText(editText)
            end
            if dialog.OnAccept then
                dialog.OnAccept(popupFrame, data)
            end
            return
        end

        if dialog.OnAccept then
            dialog.OnAccept(nil, data)
        end
    end

    return function()
        return shown
    end
end

--- Override StaticPopup_Show to record popup keys without auto-accepting them.
--- @return function getShownPopupNames
function TestHelpers.InstallPopupRecorder()
    local shownNames = {}
    _G.StaticPopup_Show = function(name, _text1, _text2, _data)
        shownNames[#shownNames + 1] = name
    end

    return function()
        return shownNames
    end
end

--- Set up the PowerBar tick marks options/store environment and load the live module.
--- @param opts table|nil Optional overrides for constants, profile, or GetCurrentClassSpec
--- @return table addonNS
function TestHelpers.SetupPowerBarTickMarksEnv(opts)
    opts = opts or {}

    _G.StaticPopupDialogs = _G.StaticPopupDialogs or {}
    _G.YES = "Yes"
    _G.NO = "No"
    _G.SETTINGS_DEFAULTS = "Defaults"

    local ns = opts.addonNS or {
        Addon = {
            db = {
                profile = opts.profile or {},
            },
        },
    }

    ns.Constants = opts.constants or {
        DEFAULT_POWERBAR_TICK_COLOR = { r = 1, g = 1, b = 1, a = 1 },
        CLASS_COLORS = { WARRIOR = "C79C6E" },
        COLOR_WHITE_HEX = "FFFFFF",
        VALUE_SLIDER_TIERS = {
            { ceiling = 200,    step = 1 },
            { ceiling = 1000,   step = 5 },
            { ceiling = 5000,   step = 25 },
            { ceiling = 10000,  step = 50 },
            { ceiling = 50000,  step = 250 },
            { ceiling = 100000, step = 500 },
            { ceiling = 500000, step = 2500 },
        },
    }
    ns.L = setmetatable({}, { __index = function(_, k)
        return k
    end })
    ns.CloneValue = TestHelpers.deepClone
    ns.OptionUtil = {
        GetCurrentClassSpec = opts.getCurrentClassSpec or function()
            return 1, 2, "Warrior", "Fury", "WARRIOR"
        end,
        MakeConfirmDialog = function(text)
            return {
                text = text,
                button1 = _G.YES,
                button2 = _G.NO,
                OnAccept = function(self, data)
                    if data and data.onAccept then data.onAccept() end
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
            }
        end,
    }
    ns.ScheduleLayoutUpdate = function() end

    TestHelpers.LoadChunk("UI/PowerBarTickMarksOptions.lua", "Unable to load UI/PowerBarTickMarksOptions.lua")(nil, ns)
    return ns
end

return TestHelpers
