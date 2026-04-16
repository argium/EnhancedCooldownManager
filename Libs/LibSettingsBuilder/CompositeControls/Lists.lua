-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local function buildControlList(builder, basePath, defs, spec, methodName)
    local results = {}
    spec = spec or {}
    for _, def in ipairs(defs) do
        local childSpec = {
            path = basePath .. "." .. tostring(def.key),
            name = def.name,
            tooltip = def.tooltip,
        }
        builder:_propagateModifiers(childSpec, spec)
        local initializer, setting = lib[methodName](builder, childSpec)
        results[#results + 1] = { key = def.key, initializer = initializer, setting = setting }
    end
    return results
end

function lib:ColorPickerList(basePath, defs, spec)
    return buildControlList(self, basePath, defs, spec, "Color")
end

function lib:CheckboxList(basePath, defs, spec)
    return buildControlList(self, basePath, defs, spec, "Checkbox")
end
