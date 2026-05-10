-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local foundation = internal.foundation
local interop = internal.interop
local builders = internal.builders

local function createCollectionInitializer(spec, errorPrefix)
    assert(spec.height, errorPrefix .. ": spec.height is required")

    local data = foundation.copyMixin({}, spec)
    if data.variant and data.preset == nil then
        data.preset = data.variant
    end

    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", data, spec.height, interop.applyCollectionFrame)
    interop.configureCollectionInitializer(initializer, data)

    return {
        initializer = initializer,
        registration = "category",
        refreshable = true,
    }
end

function builders.list(spec)
    assert(spec.items, "List: spec.items is required")
    assert(not spec.sections, "List: spec.sections is not supported")
    return createCollectionInitializer(spec, "List")
end

function builders.sectionList(spec)
    assert(spec.sections, "SectionList: spec.sections is required")
    return createCollectionInitializer(spec, "SectionList")
end
