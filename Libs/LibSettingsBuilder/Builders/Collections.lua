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
local registry = internal.registry
local builders = internal.builders

local function createCollectionInitializer(self, spec, errorPrefix)
    assert(spec.height, errorPrefix .. ": spec.height is required")

    local category = registry.resolveCategory(self, spec)
    local data = foundation.copyMixin({}, spec)
    if data.variant and data.preset == nil then
        data.preset = data.variant
    end

    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", data, spec.height, interop.applyCollectionFrame)

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        local activeFrame = controlInitializer._lsbActiveFrame
        if activeFrame then
            interop.applyCollectionFrame(activeFrame, data, controlInitializer)
            activeFrame:SetAlpha(enabled and 1 or 0.5)
            if enabled == false then
                registry.setCanvasInteractive(self, activeFrame, false)
            end
        end
    end

    initializer._lsbRefreshFrame = function(frame)
        initializer._lsbActiveFrame = frame
        initializer:SetEnabled(initializer._lsbEnabled ~= false)
    end

    interop.registerInitializer(category, initializer)
    registry.registerCategoryRefreshable(self, category, initializer)
    registry.applyModifiers(self, initializer, spec)

    return initializer
end

function builders.list(self, spec)
    assert(spec.items, "List: spec.items is required")
    assert(not spec.sections, "List: spec.sections is not supported")
    return createCollectionInitializer(self, spec, "List")
end

function builders.sectionList(self, spec)
    assert(spec.sections, "SectionList: spec.sections is required")
    return createCollectionInitializer(self, spec, "SectionList")
end
