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
local BuilderMixin = lib.BuilderMixin

function BuilderMixin:_createCollectionInitializer(spec, errorPrefix)
    assert(spec.height, errorPrefix .. ": spec.height is required")

    local category = self:_resolveCategory(spec)
    local data = copyMixin({}, spec)
    if data.variant and data.preset == nil then
        data.preset = data.variant
    end

    local initializer = createCustomListRowInitializer(lib.EMBED_CANVAS_TEMPLATE, data, spec.height, applyCollectionFrame)

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        local activeFrame = controlInitializer._lsbActiveFrame
        if activeFrame then
            self:_applyCanvasState(activeFrame, enabled)
        end
    end

    initializer._lsbRefreshFrame = function(frame)
        applyCollectionFrame(frame, data, initializer)
        initializer:SetEnabled(initializer._lsbEnabled ~= false)
    end

    Settings.RegisterInitializer(category, initializer)
    self:_registerCategoryRefreshable(category, initializer)
    self:_applyModifiers(initializer, spec)

    return initializer
end

function BuilderMixin:List(spec)
    assert(spec.items, "List: spec.items is required")
    assert(not spec.sections, "List: spec.sections is not supported")
    return self:_createCollectionInitializer(spec, "List")
end

function BuilderMixin:SectionList(spec)
    assert(spec.sections, "SectionList: spec.sections is required")
    return self:_createCollectionInitializer(spec, "SectionList")
end
