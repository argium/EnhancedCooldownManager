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

function lib._installStandardCollectionControls(SB, env)
    local applyCanvasState = env.applyCanvasState
    local applyModifiers = env.applyModifiers
    local registerCategoryRefreshable = env.registerCategoryRefreshable
    local resolveCategory = env.resolveCategory

    local function createCollectionInitializer(spec, errorPrefix)
        assert(spec.height, errorPrefix .. ": spec.height is required")
        local cat = resolveCategory(spec)
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
                applyCanvasState(activeFrame, enabled)
            end
        end

        initializer._lsbRefreshFrame = function(frame)
            applyCollectionFrame(frame, data, initializer)
            initializer:SetEnabled(initializer._lsbEnabled ~= false)
        end

        Settings.RegisterInitializer(cat, initializer)
        registerCategoryRefreshable(cat, initializer)
        applyModifiers(initializer, spec)

        return initializer
    end

    function SB.List(spec)
        assert(spec.items, "List: spec.items is required")
        assert(not spec.sections, "List: spec.sections is not supported")
        return createCollectionInitializer(spec, "List")
    end

    function SB.SectionList(spec)
        assert(spec.sections, "SectionList: spec.sections is required")
        return createCollectionInitializer(spec, "SectionList")
    end

    return SB
end
