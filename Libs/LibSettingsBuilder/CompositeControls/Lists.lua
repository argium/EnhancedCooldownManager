-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

function lib._installCompositeListControls(SB, env)
    local propagateModifiers = env.propagateModifiers

    local function buildControlList(basePath, defs, spec, factory)
        local results = {}
        spec = spec or {}
        for _, def in ipairs(defs) do
            local childSpec = {
                path = basePath .. "." .. tostring(def.key),
                name = def.name,
                tooltip = def.tooltip,
            }
            propagateModifiers(childSpec, spec)
            local init, setting = factory(childSpec)
            results[#results + 1] = { key = def.key, initializer = init, setting = setting }
        end

        return results
    end

    function SB.ColorPickerList(basePath, defs, spec)
        return buildControlList(basePath, defs, spec, SB.Color)
    end

    function SB.CheckboxList(basePath, defs, spec)
        return buildControlList(basePath, defs, spec, SB.Checkbox)
    end

    return SB
end
