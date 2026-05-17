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
lib._pageLifecycleCallbacks = {}
lib._pageLifecycleHooked = false
