-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local applyCollectionFrame = internal.applyCollectionFrame
local createCustomListRowInitializer = internal.createCustomListRowInitializer
local copyMixin = internal.copyMixin
function internal.createCollectionInitializer(self, spec, errorPrefix)
    assert(spec.height, errorPrefix .. ": spec.height is required")

    local category = internal.resolveCategory(self, spec)
    local data = copyMixin({}, spec)
    if data.variant and data.preset == nil then
        data.preset = data.variant
    end

    local initializer = createCustomListRowInitializer("SettingsListElementTemplate", data, spec.height, applyCollectionFrame)

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        local activeFrame = controlInitializer._lsbActiveFrame
        if activeFrame then
            applyCollectionFrame(activeFrame, data, controlInitializer)
            if activeFrame.SetAlpha then
                activeFrame:SetAlpha(enabled and 1 or 0.5)
            end
            if enabled == false then
                internal.setCanvasInteractive(self, activeFrame, false)
            end
        end
    end

    initializer._lsbRefreshFrame = function(frame)
        initializer._lsbActiveFrame = frame
        initializer:SetEnabled(initializer._lsbEnabled ~= false)
    end

    Settings.RegisterInitializer(category, initializer)
    internal.registerCategoryRefreshable(self, category, initializer)
    internal.applyModifiers(self, initializer, spec)

    return initializer
end

function lib.List(self, spec)
    assert(spec.items, "List: spec.items is required")
    assert(not spec.sections, "List: spec.sections is not supported")
    return internal.createCollectionInitializer(self, spec, "List")
end

function lib.SectionList(self, spec)
    assert(spec.sections, "SectionList: spec.sections is required")
    return internal.createCollectionInitializer(self, spec, "SectionList")
end
