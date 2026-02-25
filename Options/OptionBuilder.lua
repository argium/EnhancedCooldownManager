-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")

local function GetProfile()
    return mod.db and mod.db.profile
end

local function GetPathValue(path)
    local profile = GetProfile()
    if not profile then
        return nil
    end

    return ECM.OptionUtil.GetNestedValue(profile, path)
end

local function SetPathValue(path, value)
    local profile = GetProfile()
    if not profile then
        return
    end

    ECM.OptionUtil.SetNestedValue(profile, path, value)
end

local function LayoutChanged()
    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
end

local function NotifyOptionsChanged()
    AceConfigRegistry:NotifyChange("EnhancedCooldownManager")
end

local function MergeArgs(target, source)
    if type(target) ~= "table" then
        return target
    end
    if type(source) ~= "table" then
        return target
    end

    for key, value in pairs(source) do
        target[key] = value
    end

    return target
end

local function ApplyPostSet(spec, value, ...)
    if spec.onSet then
        spec.onSet(value, ...)
    end

    if spec.layout ~= false then
        LayoutChanged()
    end

    if spec.notify then
        NotifyOptionsChanged()
    end
end

local function ApplyCommonFields(option, spec)
    if spec.name ~= nil then option.name = spec.name end
    if spec.order ~= nil then option.order = spec.order end
    if spec.desc ~= nil then option.desc = spec.desc end
    if spec.width ~= nil then option.width = spec.width end
    if spec.disabled ~= nil then option.disabled = spec.disabled end
    if spec.hidden ~= nil then option.hidden = spec.hidden end
    if spec.dialogControl ~= nil then option.dialogControl = spec.dialogControl end
    if spec.values ~= nil then option.values = spec.values end
    if spec.confirm ~= nil then option.confirm = spec.confirm end
    if spec.confirmText ~= nil then option.confirmText = spec.confirmText end
    if spec.inline ~= nil then option.inline = spec.inline end
    if spec.childGroups ~= nil then option.childGroups = spec.childGroups end
    if spec.fontSize ~= nil then option.fontSize = spec.fontSize end
end

local function MakePathGetter(spec)
    return function()
        local value = GetPathValue(spec.path)
        if spec.getTransform then
            return spec.getTransform(value)
        end
        return value
    end
end

local function MakePathSetter(spec)
    return function(_, value)
        local storedValue
        if spec.setTransform then
            storedValue = spec.setTransform(value)
        else
            storedValue = value
        end
        SetPathValue(spec.path, storedValue)
        ApplyPostSet(spec, storedValue, value)
    end
end

local function MakePathColorGetter(spec)
    local hasAlpha = spec.hasAlpha

    return function()
        local color = GetPathValue(spec.path)
        if spec.getTransform then
            return spec.getTransform(color)
        end

        color = color or {}
        if hasAlpha then
            return color.r or 0, color.g or 0, color.b or 0, color.a or 1
        end
        return color.r or 0, color.g or 0, color.b or 0
    end
end

local function MakePathColorSetter(spec)
    local hasAlpha = spec.hasAlpha

    return function(_, r, g, b, a)
        local storedValue
        if spec.setTransform then
            storedValue = spec.setTransform(r, g, b, a)
        else
            storedValue = {
                r = r,
                g = g,
                b = b,
                a = hasAlpha and a or 1,
            }
        end

        SetPathValue(spec.path, storedValue)
        ApplyPostSet(spec, storedValue, r, g, b, a)
    end
end

local function MakePathToggle(spec)
    local option = { type = "toggle" }
    ApplyCommonFields(option, spec)
    option.get = MakePathGetter(spec)
    option.set = MakePathSetter(spec)
    return option
end

local function MakePathRange(spec)
    local option = {
        type = "range",
        min = spec.min,
        max = spec.max,
        step = spec.step,
    }
    ApplyCommonFields(option, spec)
    option.get = MakePathGetter(spec)
    option.set = MakePathSetter(spec)
    return option
end

local function MakePathSelect(spec)
    local option = {
        type = "select",
        values = spec.values,
    }
    ApplyCommonFields(option, spec)
    option.get = MakePathGetter(spec)
    option.set = MakePathSetter(spec)
    return option
end

local function MakePathColor(spec)
    local option = {
        type = "color",
        hasAlpha = spec.hasAlpha,
    }
    ApplyCommonFields(option, spec)
    option.get = MakePathColorGetter(spec)
    option.set = MakePathColorSetter(spec)
    return option
end

local function MakeLayoutSetHandler(setter, opts)
    opts = opts or {}

    return function(...)
        setter(...)
        if opts.layout ~= false then
            LayoutChanged()
        end
        if opts.notify then
            NotifyOptionsChanged()
        end
    end
end

local function WrapHandlerIfNeeded(fn, spec)
    if not fn then
        return nil
    end

    if spec.layout ~= nil or spec.notify ~= nil then
        return MakeLayoutSetHandler(fn, {
            layout = spec.layout,
            notify = spec.notify,
        })
    end

    return fn
end

local function MakeControl(spec)
    local option = {
        type = spec.type,
    }

    ApplyCommonFields(option, spec)

    if spec.min ~= nil then option.min = spec.min end
    if spec.max ~= nil then option.max = spec.max end
    if spec.step ~= nil then option.step = spec.step end
    if spec.hasAlpha ~= nil then option.hasAlpha = spec.hasAlpha end
    if spec.args ~= nil then option.args = spec.args end
    if spec.get ~= nil then option.get = spec.get end
    if spec.set ~= nil then option.set = WrapHandlerIfNeeded(spec.set, spec) end
    if spec.func ~= nil then option.func = WrapHandlerIfNeeded(spec.func, spec) end

    return option
end

local function MakeActionButton(spec)
    local controlSpec = {
        type = "execute",
        name = spec.name,
        order = spec.order,
        desc = spec.desc,
        width = spec.width,
        disabled = spec.disabled,
        hidden = spec.hidden,
        confirm = spec.confirm,
        confirmText = spec.confirmText,
        func = spec.func,
        layout = spec.layout,
        notify = spec.notify,
    }

    return MakeControl(controlSpec)
end

local function MakeGroup(spec)
    return MakeControl({
        type = "group",
        name = spec.name,
        order = spec.order,
        args = spec.args,
        inline = spec.inline,
        disabled = spec.disabled,
        hidden = spec.hidden,
        desc = spec.desc,
        childGroups = spec.childGroups,
    })
end

local function MakeInlineGroup(name, order, args, opts)
    opts = opts or {}
    return MakeGroup({
        name = name,
        order = order,
        args = args,
        inline = true,
        disabled = opts.disabled,
        hidden = opts.hidden,
        desc = opts.desc,
        childGroups = opts.childGroups,
    })
end

local function MakeDescription(spec)
    return MakeControl({
        type = "description",
        name = spec.name,
        order = spec.order,
        width = spec.width,
        hidden = spec.hidden,
        disabled = spec.disabled,
        fontSize = spec.fontSize,
    })
end

local function MakeSpacer(order, opts)
    opts = opts or {}
    return MakeDescription({
        name = opts.name or " ",
        order = order,
        hidden = opts.hidden,
        width = opts.width,
        disabled = opts.disabled,
        fontSize = opts.fontSize,
    })
end

local function MakeHeader(spec)
    return MakeControl({
        type = "header",
        name = spec.name,
        order = spec.order,
        width = spec.width,
        hidden = spec.hidden,
    })
end

local function MakeResetButton(spec)
    local hidden = spec.hidden
    local path = spec.path

    local function BaseHidden(...)
        return not ECM.OptionUtil.IsValueChanged(path)
    end

    local mergedHidden
    if type(hidden) == "function" then
        mergedHidden = function(...)
            return hidden(...) or BaseHidden(...)
        end
    elseif hidden ~= nil then
        mergedHidden = function(...)
            return hidden or BaseHidden(...)
        end
    else
        mergedHidden = BaseHidden
    end

    return MakeActionButton({
        name = spec.name or "X",
        desc = spec.desc,
        order = spec.order,
        width = spec.width or 0.3,
        hidden = mergedHidden,
        disabled = spec.disabled,
        func = spec.func or ECM.OptionUtil.MakeResetHandler(path, spec.refreshFunc),
        confirm = spec.confirm,
        confirmText = spec.confirmText,
    })
end

local function BuildPathControlWithReset(makeControlFn, key, spec)
    return {
        [key] = makeControlFn(spec),
        [key .. "Reset"] = MakeResetButton({
            path = spec.path,
            order = spec.resetOrder,
            name = spec.resetName,
            desc = spec.resetDesc,
            width = spec.resetWidth,
            hidden = spec.resetHidden,
            disabled = spec.resetDisabled,
            refreshFunc = spec.resetRefreshFunc,
            func = spec.resetFunc,
            confirm = spec.resetConfirm,
            confirmText = spec.resetConfirmText,
        }),
    }
end

local function BuildPathRangeWithReset(key, spec)
    return BuildPathControlWithReset(MakePathRange, key, spec)
end

local function BuildPathSelectWithReset(key, spec)
    return BuildPathControlWithReset(MakePathSelect, key, spec)
end

local function BuildPathColorWithReset(key, spec)
    return BuildPathControlWithReset(MakePathColor, key, spec)
end

local function DisabledWhenPathFalse(path)
    return function()
        return not GetPathValue(path)
    end
end

local function DisabledWhenPathTrue(path)
    return function()
        return not not GetPathValue(path)
    end
end

local function IsPlayerClass(classToken)
    local _, className = UnitClass("player")
    return className == classToken
end

local function DisabledIfPlayerClass(classToken)
    return function()
        return IsPlayerClass(classToken)
    end
end

local function DisabledUnlessPlayerClass(classToken)
    return function()
        return not IsPlayerClass(classToken)
    end
end

local function RegisterSection(nsTable, key, section)
    nsTable.OptionsSections = nsTable.OptionsSections or {}
    nsTable.OptionsSections[key] = section
    return section
end

local function BuildModuleEnabledToggle(moduleName, path, label, order, opts)
    opts = opts or {}
    return MakePathToggle({
        path = path,
        name = label,
        order = order,
        width = opts.width or "full",
        disabled = opts.disabled,
        hidden = opts.hidden,
        onSet = function(value)
            ECM.OptionUtil.SetModuleEnabled(moduleName, value)
        end,
    })
end

local function BuildHeightOverrideArgs(sectionPath, orderBase)
    local args = {
        heightDesc = MakeDescription({
            name = "\nOverride the default bar height. Set to 0 to use the global default.",
            order = orderBase,
        }),
    }

    MergeArgs(args, BuildPathRangeWithReset("height", {
        path = sectionPath .. ".height",
        name = "Height Override",
        order = orderBase + 1,
        width = "half",
        min = 0,
        max = 40,
        step = 1,
        getTransform = function(value)
            return value or 0
        end,
        setTransform = function(value)
            return value > 0 and value or nil
        end,
        resetOrder = orderBase + 2,
    }))

    return args
end

local function BuildFontOverrideArgs(sectionPath, orderBase)
    local overridePath = sectionPath .. ".overrideFont"
    local isFontOverrideDisabled = DisabledWhenPathFalse(overridePath)

    local args = {
        fontOverrideDesc = MakeDescription({
            name = "\nOverride the global font settings for this module's text.",
            order = orderBase,
        }),
        overrideFont = MakePathToggle({
            path = overridePath,
            name = "Override font",
            order = orderBase + 1,
            width = "full",
            getTransform = function(value)
                return value == true
            end,
        }),
    }

    MergeArgs(args, BuildPathSelectWithReset("font", {
        path = sectionPath .. ".font",
        name = "Font",
        order = orderBase + 2,
        width = "half",
        dialogControl = "LSM30_Font",
        values = ECM.SharedMediaOptions.GetFontValues,
        getTransform = function(value)
            return value or GetPathValue("global.font") or "Expressway"
        end,
        disabled = isFontOverrideDisabled,
        resetOrder = orderBase + 3,
        resetDisabled = isFontOverrideDisabled,
    }))

    MergeArgs(args, BuildPathRangeWithReset("fontSize", {
        path = sectionPath .. ".fontSize",
        name = "Font Size",
        order = orderBase + 4,
        width = "half",
        min = 6,
        max = 32,
        step = 1,
        getTransform = function(value)
            return value or GetPathValue("global.fontSize") or 11
        end,
        disabled = isFontOverrideDisabled,
        resetOrder = orderBase + 5,
        resetDisabled = isFontOverrideDisabled,
    }))

    return args
end

local function BuildBorderArgs(borderPath, orderBase, opts)
    opts = opts or {}
    local enabledPath = borderPath .. ".enabled"
    local isBorderDisabled = DisabledWhenPathFalse(enabledPath)

    local args = {
        borderEnabled = MakePathToggle({
            path = enabledPath,
            name = opts.enabledLabel or "Show border",
            order = orderBase,
            width = "full",
        }),
    }

    MergeArgs(args, BuildPathRangeWithReset("borderThickness", {
        path = borderPath .. ".thickness",
        name = opts.thicknessLabel or "Border width",
        order = orderBase + 1,
        width = opts.controlWidth or "small",
        min = 1,
        max = 10,
        step = 1,
        disabled = isBorderDisabled,
        resetOrder = orderBase + 1.5,
        resetDisabled = isBorderDisabled,
    }))

    MergeArgs(args, BuildPathColorWithReset("borderColor", {
        path = borderPath .. ".color",
        name = opts.colorLabel or "Border color",
        order = orderBase + 2,
        width = opts.controlWidth or "small",
        hasAlpha = true,
        disabled = isBorderDisabled,
        resetOrder = orderBase + 2.5,
        resetDisabled = isBorderDisabled,
    }))

    return args
end

local function BuildColorPickerList(basePath, defs, orderBase, opts)
    opts = opts or {}
    local args = {}

    for i, def in ipairs(defs) do
        local key = def.key
        local path = basePath .. "." .. tostring(key)
        local rowOrder = orderBase + (i - 1) * 2
        local suffix = tostring(key)

        MergeArgs(args, BuildPathColorWithReset("color" .. suffix, {
            path = path,
            name = def.name,
            order = rowOrder,
            width = opts.width or "double",
            hasAlpha = opts.hasAlpha,
            resetOrder = rowOrder + 1,
        }))
    end

    return args
end

ECM.OptionBuilder = {
    MergeArgs = MergeArgs,
    MakeGroup = MakeGroup,
    MakeInlineGroup = MakeInlineGroup,
    MakeDescription = MakeDescription,
    MakeSpacer = MakeSpacer,
    MakeHeader = MakeHeader,
    MakeControl = MakeControl,
    MakeActionButton = MakeActionButton,
    MakePathToggle = MakePathToggle,
    MakePathRange = MakePathRange,
    MakePathSelect = MakePathSelect,
    MakePathColor = MakePathColor,
    MakeResetButton = MakeResetButton,
    MakeLayoutSetHandler = MakeLayoutSetHandler,
    NotifyOptionsChanged = NotifyOptionsChanged,
    LayoutChanged = LayoutChanged,
    BuildPathRangeWithReset = BuildPathRangeWithReset,
    BuildPathSelectWithReset = BuildPathSelectWithReset,
    BuildPathColorWithReset = BuildPathColorWithReset,
    DisabledWhenPathFalse = DisabledWhenPathFalse,
    DisabledWhenPathTrue = DisabledWhenPathTrue,
    IsPlayerClass = IsPlayerClass,
    DisabledIfPlayerClass = DisabledIfPlayerClass,
    DisabledUnlessPlayerClass = DisabledUnlessPlayerClass,
    RegisterSection = RegisterSection,
    BuildModuleEnabledToggle = BuildModuleEnabledToggle,
    BuildHeightOverrideArgs = BuildHeightOverrideArgs,
    BuildFontOverrideArgs = BuildFontOverrideArgs,
    BuildBorderArgs = BuildBorderArgs,
    BuildColorPickerList = BuildColorPickerList,
}
