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

function lib._installUtility(SB, env)
    local getCanvasLayoutMetrics = env.getCanvasLayoutMetrics

    function SB.SetCanvasLayoutDefaults(overrides)
        if not overrides then
            return lib.CanvasLayoutDefaults
        end

        return copyMixin(lib.CanvasLayoutDefaults, overrides)
    end

    function SB.ConfigureCanvasLayout(layout, overrides)
        assert(layout, "ConfigureCanvasLayout: layout is required")
        if not overrides then
            return getCanvasLayoutMetrics(layout)
        end

        layout._metrics = copyMixin(copyMixin({}, lib.CanvasLayoutDefaults), overrides)
        return layout._metrics
    end

    function SB.RegisterCategories()
        if SB._rootCategory then
            Settings.RegisterAddOnCategory(SB._rootCategory)
        end
    end

    function SB.GetRootCategoryID()
        return SB._rootCategory and SB._rootCategory:GetID()
    end

    function SB.GetSubcategoryID(name)
        local category = SB._subcategories[name]
        return category and category:GetID()
    end

    function SB.GetRootCategory()
        return SB._rootCategory
    end

    function SB.GetSubcategory(name)
        return SB._subcategories[name]
    end

    function SB.HasCategory(category)
        return category ~= nil and SB._layouts[category] ~= nil
    end

    local DISPATCH = {
        checkbox = "Checkbox",
        slider = "Slider",
        dropdown = "Dropdown",
        color = "Color",
        input = "Input",
        custom = "Custom",
    }

    function SB.Control(spec)
        local fn = SB[DISPATCH[spec.type]]
        assert(fn, "Control: unknown type '" .. tostring(spec.type) .. "'")
        return fn(spec)
    end

    function SB.RefreshCategory(categoryOrName)
        local category = categoryOrName
        if type(categoryOrName) == "string" then
            category = SB._subcategories[categoryOrName]
                or (categoryOrName == SB._rootCategoryName and SB._rootCategory)
        end
        if not category then
            return
        end

        local currentCategory = SettingsPanel and SettingsPanel.GetCurrentCategory and SettingsPanel:GetCurrentCategory() or nil
        local isVisible = SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() and currentCategory == category

        local refreshables = SB._categoryRefreshables[category] or {}
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

    local COMPOSITE_ROW_DISPATCH = {
        border = function(path, spec)
            local result = SB.BorderGroup(path, spec)
            return result.enabledInit, result.enabledSetting
        end,
        fontOverride = function(path, spec)
            local result = SB.FontOverrideGroup(path, spec)
            return result.enabledInit, result.enabledSetting
        end,
        heightOverride = function(path, spec)
            return SB.HeightOverrideSlider(path, spec)
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
        spec.id, spec.condition = nil, nil
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

    local function registerLabeledList(page, spec, builder)
        if spec.label then
            local labelInit = SB.Subheader({ name = spec.label, disabled = spec.disabled, hidden = spec.hidden })
            spec.parent = spec.parent or labelInit
        end
        local results = builder(resolvePagePath(page.path or "", spec.path), spec.defs or {}, spec)
        return results[1] and results[1].initializer, results[1] and results[1].setting
    end

    local DECLARATIVE_ROW_BUILDERS = {
        button = function(spec)
            return SB.Button(spec)
        end,
        canvas = function(spec)
            return SB.EmbedCanvas(spec.canvas, spec.height, spec)
        end,
        checkboxList = function(spec, page)
            return registerLabeledList(page, spec, SB.CheckboxList)
        end,
        colorList = function(spec, page)
            return registerLabeledList(page, spec, SB.ColorPickerList)
        end,
        header = function(spec)
            return SB.Header(spec)
        end,
        info = function(spec)
            return SB.InfoRow(spec)
        end,
        list = function(spec)
            return SB.List(spec)
        end,
        pageActions = function(spec)
            return SB.PageActions(spec)
        end,
        sectionList = function(spec)
            return SB.SectionList(spec)
        end,
        subheader = function(spec)
            return SB.Subheader(spec)
        end,
    }

    local function registerDeclarativeRow(sourceName, page, row, created)
        local rowType = row.type
        assert(rowType, sourceName .. ": each row requires a type")

        local spec = copyDeclarativeRowSpec(row)
        if page.disabled and spec.disabled == nil then
            spec.disabled = page.disabled
        end
        if page.hidden and spec.hidden == nil then
            spec.hidden = page.hidden
        end

        resolveDeclarativeParent(sourceName, created, row.id, spec)

        local init, setting
        local builder = DECLARATIVE_ROW_BUILDERS[rowType]
        if builder then
            init, setting = builder(spec, page)
        elseif COMPOSITE_ROW_DISPATCH[rowType] then
            local path = resolvePagePath(page.path or "", spec.path)
            init, setting = COMPOSITE_ROW_DISPATCH[rowType](path, spec)
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
            init, setting = SB.Control(spec)
        else
            error(sourceName .. ": unknown row type '" .. tostring(rowType) .. "'")
        end

        if row.id then
            created[row.id] = { initializer = init, setting = setting }
        end
    end

    function SB.RegisterPage(page)
        assert(page.name, "RegisterPage: page.name is required")

        if page.rootCategory then
            SB._currentSubcategory = SB._rootCategory
        else
            SB.CreateSubcategory(page.name, page.parentCategory)
        end

        if page.onShow or page.onHide then
            lib._pageLifecycleCallbacks[SB._currentSubcategory] = {
                onShow = page.onShow,
                onHide = page.onHide,
            }
            installPageLifecycleHooks()
        end

        local created = {}
        for _, row in ipairs(page.rows or {}) do
            if shouldProcessRow(row) then
                registerDeclarativeRow("RegisterPage", page, row, created)
            end
        end

        return SB._currentSubcategory
    end

    function SB.RegisterSection(nsTable, key, section)
        nsTable.OptionsSections = nsTable.OptionsSections or {}
        nsTable.OptionsSections[key] = section
        return section
    end

    return SB
end

lib._loadState.open = nil
