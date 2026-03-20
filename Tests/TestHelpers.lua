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
        SetParentInitializer = function(self, parent, predicate)
            self._parentInit = parent
            self._parentPredicate = predicate
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
local function makeSetting(getter, setter, default)
    return {
        GetValue = function()
            return getter()
        end,
        SetValue = function(_, value)
            setter(value)
        end,
        _default = default,
    }
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

--- Registers a minimal LibEQOLEditMode-1.0 stub in an existing LibStub.
--- Must be called after LibStub is available.
function TestHelpers.SetupLibEQOLEditModeStub()
    assert(_G.LibStub, "LibStub must be set up before calling SetupLibEQOLEditModeStub")
    local lib = _G.LibStub:NewLibrary("LibEQOLEditMode-1.0", 1) or _G.LibStub("LibEQOLEditMode-1.0")
    lib.AddFrame = lib.AddFrame or function() end
    lib.AddFrameSettings = lib.AddFrameSettings or function() end
    lib.RegisterCallback = lib.RegisterCallback or function() end
    lib.GetActiveLayoutName = lib.GetActiveLayoutName or function() return "Modern" end
    lib.GetActiveLayoutIndex = lib.GetActiveLayoutIndex or function() return 1 end
    lib.IsInEditMode = lib.IsInEditMode or function() return false end
    lib.SetFrameDragEnabled = lib.SetFrameDragEnabled or function() end
    lib.selectionRegistry = lib.selectionRegistry or {}
    lib.SettingType = lib.SettingType or { Slider = 0, Dropdown = 1 }
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
        "ECM",
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

        RegisterProxySetting = function(cat, variable, varType, name, default, getter, setter)
            return makeSetting(getter, setter, default)
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
                    self:AddHandle({ variable = variable, callback = callback, owner = owner })
                end,
                Unregister = function(self)
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
        return { _type = "header", _text = text }
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

    _G.MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

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

    _G.ECM = _G.ECM or {}
    _G.ECM.CloneValue = deepClone
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

--------------------------------------------------------------------------------
-- Shared mock builders for frame/texture test stubs
--------------------------------------------------------------------------------

local unpack_fn = table.unpack or unpack

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
        __anchors = anchors,
        __regions = opts.regions or {},
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

--- Asserts anchor values match. Uses busted's assert when available, plain assert otherwise.
function TestHelpers.assertAnchor(frame, index, point, relativeTo, relativePoint, x, y)
    local ap, ar, arp, ax, ay = frame:GetPoint(index)
    local eq = (type(assert) == "table" and assert.are and assert.are.equal)
    if eq then
        eq(point, ap)
        eq(relativeTo, ar)
        eq(relativePoint, arp)
        eq(x, ax)
        eq(y, ay)
    else
        assert(point == ap, ("anchor point: expected %s, got %s"):format(tostring(point), tostring(ap)))
        assert(relativeTo == ar, ("relativeTo: expected %s, got %s"):format(tostring(relativeTo), tostring(ar)))
        assert(
            relativePoint == arp,
            ("relativePoint: expected %s, got %s"):format(tostring(relativePoint), tostring(arp))
        )
        assert(x == ax, ("x: expected %s, got %s"):format(tostring(x), tostring(ax)))
        assert(y == ay, ("y: expected %s, got %s"):format(tostring(y), tostring(ay)))
    end
end

--------------------------------------------------------------------------------
-- Options test environment
--------------------------------------------------------------------------------

--- Standard list of globals captured/restored by option tests.
TestHelpers.OPTIONS_GLOBALS = {
    "ECM",
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
    "UnitClass",
    "GetSpecialization",
    "GetSpecializationInfo",
    "Enum",
    "LibStub",
    "CreateFromMixins",
    "SettingsListElementInitializer",
    "GameFontHighlightSmall",
    "GameFontNormal",
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
}

--- Load the live ECM_Constants.lua to populate ECM.Constants.
function TestHelpers.LoadLiveConstants()
    _G.ECM = _G.ECM or {}
    if not ECM.Constants then
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
    end
end

--- Load the live ECM_Defaults.lua to populate ECM.defaults.
--- Requires ECM.Constants and Enum to be set up first.
function TestHelpers.LoadLiveDefaults()
    TestHelpers.LoadLiveConstants()
    TestHelpers.LoadChunk("ECM_Defaults.lua", "Unable to load ECM_Defaults.lua")()
end

--- Create a full default profile for option tests using the live defaults file.
function TestHelpers.MakeOptionsProfile()
    TestHelpers.LoadLiveDefaults()
    return deepClone(ECM.defaults.profile), deepClone(ECM.defaults.profile)
end

--- Install common WoW globals for option tests.
function TestHelpers.SetupOptionsGlobals()
    TestHelpers.SetupLibStub()
    TestHelpers.SetupSettingsStubs()

    _G.ECM_DeepEquals = deepEquals
    _G.GameFontHighlightSmall = "GameFontHighlightSmall"
    _G.GameFontNormal = "GameFontNormal"
    _G.SETTINGS_DEFAULTS = "Defaults"
    _G.InCombatLockdown = function()
        return false
    end
    _G.UnitName = function()
        return "TestPlayer"
    end
    _G.date = function()
        return "120000"
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
        local f = { scripts = {}, _children = {} }
        local noop = function() end
        f.SetScript = function(self, event, fn)
            self.scripts[event] = fn
        end
        f.GetScript = function(self, event)
            return self.scripts[event]
        end
        f.GetHeight = function()
            return 0
        end
        f.SetHeight = noop
        f.SetWidth = noop
        f.SetSize = noop
        f.SetPoint = noop
        f.SetAllPoints = noop
        f.ClearAllPoints = noop
        f.Show = noop
        f.Hide = noop
        f.IsShown = function()
            return false
        end
        f.SetAlpha = noop
        f.EnableMouse = noop
        f.GetChildren = function()
            return
        end
        f.SetEnabled = noop
        f.SetText = noop
        f.GetText = function()
            return ""
        end
        f.SetWordWrap = noop
        f.SetJustifyH = noop
        f.SetColorRGB = noop
        f.SetBackdrop = noop
        f.SetBackdropBorderColor = noop
        f.SetMinMaxValues = noop
        f.SetValueStep = noop
        f.SetObeyStepOnDrag = noop
        f.SetDataProvider = noop
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
        return makeFrameStub()
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
        view.SetElementInitializer = function(self, template, fn)
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

--- Load LibSettingsBuilder + Options.lua and return the SB and ns.
--- @param profile table Profile data
--- @param defaults table Default profile data
--- @return table SB SettingsBuilder instance
--- @return table ns Addon namespace
function TestHelpers.SetupOptionsEnv(profile, defaults)
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

    TestHelpers.LoadLiveConstants()
    ECM.CloneValue = deepClone
    ECM.ScheduleLayoutUpdate = function() end
    ECM.ClassUtil = {
        IsDeathKnight = function()
            return false
        end,
    }

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

    TestHelpers.LoadChunk("UI/Options.lua", "Unable to load UI/Options.lua")(nil, ns)

    local SB = ECM.SettingsBuilder
    SB.CreateRootCategory("Test")

    return SB, ns
end

--- Collect all proxy settings created during a function call.
--- Wraps Settings.RegisterProxySetting to capture variable → setting pairs.
--- @param fn function The function to run (e.g., RegisterSettings)
--- @return table Map of variable name → setting object
function TestHelpers.CollectSettings(fn)
    local captured = {}
    local orig = Settings.RegisterProxySetting
    Settings.RegisterProxySetting = function(cat, variable, varType, name, default, getter, setter)
        local setting = orig(cat, variable, varType, name, default, getter, setter)
        captured[variable] = setting
        return setting
    end
    fn()
    Settings.RegisterProxySetting = orig
    return captured
end

return TestHelpers
