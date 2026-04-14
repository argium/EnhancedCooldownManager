-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local createCustomListRowInitializer = internal.createCustomListRowInitializer
local getOrderedValueEntries = internal.getOrderedValueEntries
local getSettingVariable = internal.getSettingVariable
local applyInputRowEnabledState = internal.applyInputRowEnabledState
local applyInputRowFrame = internal.applyInputRowFrame
local cancelInputPreviewTimer = internal.cancelInputPreviewTimer

function lib._installStandardControls(SB, env)
    local applyModifiers = env.applyModifiers
    local colorTableToHex = env.colorTableToHex
    local defaultSliderFormatter = env.defaultSliderFormatter
    local makeProxySetting = env.makeProxySetting
    local makeVarName = env.makeVarName
    local makeVarNameFromIdentifier = env.makeVarNameFromIdentifier
    local postSet = env.postSet
    local registerCategoryRefreshable = env.registerCategoryRefreshable
    local resolveBinding = env.resolveBinding
    local resolveCategory = env.resolveCategory
    local validateSpecFields = env.validateSpecFields

    function SB.Checkbox(spec)
        validateSpecFields("checkbox", spec)
        local setting, cat = makeProxySetting(spec, Settings.VarType.Boolean, false)
        local initializer = Settings.CreateCheckbox(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)
        return initializer, setting
    end

    function SB.Slider(spec)
        validateSpecFields("slider", spec)
        local setting, cat = makeProxySetting(spec, Settings.VarType.Number, 0)

        local options = Settings.CreateSliderOptions(spec.min, spec.max, spec.step or 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, spec.formatter or defaultSliderFormatter)

        local initializer = Settings.CreateSlider(cat, setting, options, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.Dropdown(spec)
        validateSpecFields("dropdown", spec)
        local binding = resolveBinding(spec)
        local cat = resolveCategory(spec)

        local default = binding.default
        if spec.getTransform then
            default = spec.getTransform(default)
        end

        local varType = spec.varType
            or (type(default) == "number" and Settings.VarType.Number)
            or Settings.VarType.String

        local setting = makeProxySetting(spec, varType, "", binding)
        local function optionsGenerator()
            local container = Settings.CreateControlTextContainer()
            local values = type(spec.values) == "function" and spec.values() or spec.values
            if values then
                for _, entry in ipairs(getOrderedValueEntries(values)) do
                    container:Add(entry.value, entry.label)
                end
            end
            return container:GetData()
        end
        setting._optionsGen = optionsGenerator

        local initializer = Settings.CreateDropdown(cat, setting, optionsGenerator, spec.tooltip)
        if spec.scrollHeight then
            initializer._lsbData = {
                _lsbKind = "scrollDropdown",
                setting = setting,
                values = spec.values,
                scrollHeight = spec.scrollHeight,
                name = spec.name,
                tooltip = spec.tooltip,
            }
            if initializer.SetSetting then
                initializer:SetSetting(setting)
            end
            initializer._lsbRefreshFrame = function(frame)
                if frame and frame.RefreshDropdownText then
                    frame:RefreshDropdownText()
                end
            end
            registerCategoryRefreshable(cat, initializer)
        end

        if initializer.SetSetting and (not initializer.GetSetting or not initializer:GetSetting()) then
            initializer:SetSetting(setting)
        end
        if type(spec.values) == "function" and not initializer._lsbRefreshFrame then
            initializer._lsbRefreshFrame = function(frame)
                if frame and frame.InitDropdown then
                    frame:InitDropdown(initializer)
                elseif frame and frame.SetValue and setting.GetValue then
                    frame:SetValue(setting:GetValue())
                end
            end
            registerCategoryRefreshable(cat, initializer)
        end

        if not initializer.GetSetting then
            initializer.GetSetting = function()
                return setting
            end
        end

        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.Color(spec)
        validateSpecFields("color", spec)
        local variable = makeVarName(spec)
        local cat = resolveCategory(spec)
        local binding = resolveBinding(spec)

        local function getter()
            local tbl = binding.get()
            return colorTableToHex(tbl)
        end

        local settingRef

        local function setter(hexValue)
            local color = CreateColorFromHexString(hexValue)
            local tbl = { r = color.r, g = color.g, b = color.b, a = color.a }
            binding.set(tbl)
            postSet(spec, tbl, settingRef)
        end

        local defaultTbl = binding.default or {}
        local defaultHex = colorTableToHex(defaultTbl)

        local setting =
            Settings.RegisterProxySetting(cat, variable, Settings.VarType.String, spec.name, defaultHex, getter, setter)
        settingRef = setting

        local initializer = Settings.CreateColorSwatch(cat, setting, spec.tooltip)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    function SB.Input(spec)
        validateSpecFields("input", spec)

        local setting, cat = makeProxySetting(spec, Settings.VarType.String, "")
        local data = {
            debounce = spec.debounce,
            maxLetters = spec.maxLetters,
            name = spec.name,
            numeric = spec.numeric,
            onTextChanged = spec.onTextChanged,
            resolveText = spec.resolveText,
            setting = setting,
            settingVariable = getSettingVariable(setting),
            tooltip = spec.tooltip,
            width = spec.width,
        }

        local watchVariables = {}
        if spec.watch then
            for _, identifier in ipairs(spec.watch) do
                watchVariables[#watchVariables + 1] = makeVarNameFromIdentifier(identifier)
            end
        end
        if spec.watchVariables then
            for _, variable in ipairs(spec.watchVariables) do
                watchVariables[#watchVariables + 1] = variable
            end
        end
        if #watchVariables > 0 then
            data.watchVariables = watchVariables
        end

        local extent = spec.resolveText and 46 or 26
        local initializer = createCustomListRowInitializer(lib.INPUTROW_TEMPLATE, data, extent, applyInputRowFrame)
        local originalInitFrame = initializer.InitFrame
        local originalResetter = initializer.Resetter

        initializer._lsbEnabled = true
        initializer.SetEnabled = function(controlInitializer, enabled)
            controlInitializer._lsbEnabled = enabled
            if controlInitializer._lsbActiveFrame then
                applyInputRowEnabledState(controlInitializer._lsbActiveFrame, enabled)
            end
        end

        initializer.InitFrame = function(controlInitializer, frame)
            controlInitializer._lsbActiveFrame = frame
            originalInitFrame(controlInitializer, frame)
            applyInputRowEnabledState(frame, controlInitializer._lsbEnabled ~= false)
        end

        initializer.Resetter = function(controlInitializer, frame)
            cancelInputPreviewTimer(frame)
            if frame and frame._lsbInputEditBox then
                if frame._lsbInputEditBox.ClearFocus then
                    frame._lsbInputEditBox:ClearFocus()
                end
                frame._lsbInputEditBox._lsbOwnerFrame = nil
            end
            frame._lsbInputData = nil
            frame._lsbInputSetting = nil
            if controlInitializer._lsbActiveFrame == frame then
                controlInitializer._lsbActiveFrame = nil
            end
            originalResetter(controlInitializer, frame)
        end

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    --- Creates a proxy setting backed by a custom frame template.
    --- The template's Init receives initializer data containing {setting, name, tooltip}.
    function SB.Custom(spec)
        validateSpecFields("custom", spec)
        assert(spec.template, "Custom: spec.template is required")
        local setting, cat = makeProxySetting(spec, spec.varType or Settings.VarType.String, "")

        local initializer =
            Settings.CreateElementInitializer(spec.template, { name = spec.name, tooltip = spec.tooltip })

        if initializer.SetSetting then
            initializer:SetSetting(setting)
        end

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer, setting
    end

    return SB
end
