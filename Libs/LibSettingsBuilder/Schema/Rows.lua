-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local foundation = lib._internal.foundation
local schema = lib._internal.schema
local MODIFIER_KEYS = { "category", "disabled", "hidden", "layout" }

schema.PROXY_ROW_TYPES = {
    checkbox = true,
    slider = true,
    dropdown = true,
    color = true,
    input = true,
}

schema.COMPOSITE_ROW_TYPES = {
    border = true,
    checkboxList = true,
    colorList = true,
    fontOverride = true,
    heightOverride = true,
}

schema.VALID_ROW_TYPES = {
    border = true,
    button = true,
    canvas = true,
    checkbox = true,
    checkboxList = true,
    color = true,
    colorList = true,
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

function schema.resolvePagePath(pagePath, rowPath)
    if rowPath == nil or rowPath == "" or rowPath:find("%.") or pagePath == "" then
        return (rowPath ~= nil and rowPath ~= "") and rowPath or pagePath
    end
    return pagePath .. "." .. rowPath
end

function schema.getRowLabel(row)
    return tostring(row.id or row.key or row.path or row.name or row.type)
end

function schema.normalizePredicate(value)
    if type(value) == "boolean" then
        return function()
            return value
        end
    end
    return value
end

function schema.propagateModifiers(target, source)
    for _, key in ipairs(MODIFIER_KEYS) do
        if target[key] == nil then
            target[key] = source[key]
        end
    end
end

function schema.normalizeRow(sourceName, row)
    assert(type(row) == "table", sourceName .. ": each row must be a table")

    local spec = foundation.copyMixin({}, row)
    assert(spec.desc == nil, sourceName .. ": row '" .. schema.getRowLabel(spec) .. "' uses deprecated field 'desc'; use 'tooltip'")
    assert(spec.condition == nil, sourceName .. ": row '" .. schema.getRowLabel(spec) .. "' uses removed field 'condition'")
    assert(spec.parent == nil, sourceName .. ": row '" .. schema.getRowLabel(spec) .. "' uses removed field 'parent'")
    assert(spec.parentCheck == nil, sourceName .. ": row '" .. schema.getRowLabel(spec) .. "' uses removed field 'parentCheck'")

    local rowType = spec.type
    assert(type(rowType) == "string" and schema.VALID_ROW_TYPES[rowType], sourceName .. ": unknown row type '" .. tostring(rowType) .. "'")

    if rowType == "button" and spec.buttonText == nil and spec.value ~= nil then
        spec.buttonText = spec.value
    end
    spec.value = rowType == "button" and nil or spec.value

    if rowType == "info" and spec.values ~= nil then
        assert(spec.value == nil, sourceName .. ": info row '" .. schema.getRowLabel(spec) .. "' cannot define both value and values")
        assert(type(spec.values) == "table", sourceName .. ": info row '" .. schema.getRowLabel(spec) .. "' values must be a table")
        spec.value = table.concat(spec.values, "\n")
        spec.multiline = true
        spec.values = nil
    end

    spec.id = row.id
    spec.disabled = schema.normalizePredicate(spec.disabled)
    spec.hidden = schema.normalizePredicate(spec.hidden)

    return spec
end

local function assertBooleanOrCallback(sourceName, fieldName, value)
    local valueType = type(value)
    assert(
        value == nil or valueType == "boolean" or valueType == "function",
        sourceName .. ": " .. fieldName .. " must be a boolean or function"
    )
end

function schema.validateRow(sourceName, builder, row)
    local rowType = row.type
    local rowLabel = schema.getRowLabel(row)
    local hasHandler = row.get ~= nil or row.set ~= nil

    assertBooleanOrCallback(sourceName, "disabled", row.disabled)
    assertBooleanOrCallback(sourceName, "hidden", row.hidden)

    if schema.PROXY_ROW_TYPES[rowType] then
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
    elseif schema.COMPOSITE_ROW_TYPES[rowType] then
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

function schema.validateRows(sourceName, builder, rows, seenRowIDs)
    assert(type(rows) == "table", sourceName .. ": rows must be a table")

    for _, row in ipairs(rows) do
        local normalized = schema.normalizeRow(sourceName, row)
        local rowID = normalized.id
        if rowID ~= nil then
            assert(not seenRowIDs[rowID], sourceName .. ": duplicate row id '" .. tostring(rowID) .. "'")
            seenRowIDs[rowID] = true
        end
        schema.validateRow(sourceName, builder, normalized)
    end
end

function schema.validatePageDefinition(sourceName, pageDef)
    assert(type(pageDef) == "table", sourceName .. ": page definition must be a table")
    assert(pageDef.key, sourceName .. ": page definition requires key")
    assert(type(pageDef.rows) == "table", sourceName .. ": page definition requires rows")
    assertBooleanOrCallback(sourceName, "disabled", pageDef.disabled)
    assertBooleanOrCallback(sourceName, "hidden", pageDef.hidden)
    if pageDef.hideDefaults ~= nil then
        assert(type(pageDef.hideDefaults) == "boolean", sourceName .. ": hideDefaults must be a boolean")
    end
end
