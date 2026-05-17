-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local foundation = lib._internal.foundation

function foundation.copyMixin(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
    return target
end

function foundation.evaluateStaticOrFunction(value, ...)
    if type(value) == "function" then
        return value(...)
    end
    return value
end

local function makeStableSortKey(value)
    local valueType = type(value)
    if valueType == "number" then
        return "1:" .. string.format("%020.10f", value)
    end
    if valueType == "boolean" then
        return value and "2:true" or "2:false"
    end
    return valueType .. ":" .. tostring(value):lower()
end

function foundation.getOrderedValueEntries(values)
    local entries = {}
    if not values then
        return entries
    end

    for value, label in pairs(values) do
        entries[#entries + 1] = {
            value = value,
            label = label,
            labelSortKey = tostring(label):lower(),
            valueSortKey = makeStableSortKey(value),
        }
    end

    table.sort(entries, function(left, right)
        if left.labelSortKey == right.labelSortKey then
            return left.valueSortKey < right.valueSortKey
        end
        return left.labelSortKey < right.labelSortKey
    end)

    return entries
end

function foundation.defaultSliderFormatter(value)
    return value == math.floor(value) and tostring(math.floor(value)) or string.format("%.1f", value)
end

function foundation.colorTableToHex(tbl)
    if not tbl then
        return "FFFFFFFF"
    end
    return string.format(
        "%02X%02X%02X%02X",
        math.floor((tbl.a or 1) * 255 + 0.5),
        math.floor((tbl.r or 1) * 255 + 0.5),
        math.floor((tbl.g or 1) * 255 + 0.5),
        math.floor((tbl.b or 1) * 255 + 0.5)
    )
end

function foundation.makeVarPrefixFromName(name)
    local words = {}
    for word in tostring(name or ""):gmatch("[A-Za-z0-9]+") do
        words[#words + 1] = word
    end

    local prefix = ""
    if #words > 1 then
        for _, word in ipairs(words) do
            prefix = prefix .. word:sub(1, 1):upper()
        end
    elseif words[1] then
        prefix = words[1]:upper():gsub("[^A-Z0-9]", "")
    end

    if prefix == "" then
        prefix = "LSB"
    end

    return prefix
end
