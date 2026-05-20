-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

-- LibSettingsBuilder: a thin declarative data-model to Blizzard Settings
-- translation library.

local MAJOR, MINOR = "LibSettingsBuilder-1.0", 6
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then
    return
end

lib._loadState = { open = true }
lib._internal = {
    foundation = {},
    interop = {},
    schema = {},
    builders = {},
    registry = {},
}
lib._registeredRowTypes = {}
lib._pageLifecycleCallbacks = {}
lib._pageLifecycleHooked = false

function lib:RegisterRowType(name, descriptor)
    assert(type(name) == "string" and name ~= "", "RegisterRowType: name is required")
    assert(type(descriptor) == "table", "RegisterRowType: descriptor is required")
    assert(type(descriptor.applyFrame) == "function", "RegisterRowType: descriptor.applyFrame is required")

    descriptor.name = name
    self._registeredRowTypes[name] = descriptor

    local schema = self._internal and self._internal.schema
    if schema and schema.VALID_ROW_TYPES then
        schema.VALID_ROW_TYPES[name] = true
        schema.PROXY_ROW_TYPES[name] = true
    end
end
