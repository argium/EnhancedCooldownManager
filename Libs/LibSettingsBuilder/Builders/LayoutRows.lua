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

local function layoutResult(initializer, refreshable)
    return {
        initializer = initializer,
        registration = "layout",
        refreshable = refreshable,
    }
end

function builders.header(textOrSpec, category)
    local spec = type(textOrSpec) == "table" and textOrSpec or {
        name = textOrSpec,
        category = category,
    }

    assert(not spec.actions, "Header: use PageActions for page header buttons")
    return layoutResult(interop.createSectionHeaderInitializer(spec.name))
end

function builders.pageActions(spec)
    assert(spec.actions, "PageActions: spec.actions is required")

    local attachToCategoryHeader = spec.attachToCategoryHeader ~= false
    local hideTitle = spec.hideTitle
    if hideTitle == nil then
        hideTitle = attachToCategoryHeader
    end
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "pageActions",
        name = spec.name or spec.categoryName or "",
        actions = spec.actions,
        hideTitle = hideTitle,
        attachToCategoryHeader = attachToCategoryHeader,
    }, spec.height or (attachToCategoryHeader and 1 or 28), interop.applyHeaderFrame)

    interop.configurePageActionsInitializer(initializer)
    return layoutResult(initializer, true)
end

function builders.subheader(spec)
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "subheader",
        name = spec.name,
    }, 28, interop.applySubheaderFrame)
    return layoutResult(initializer)
end

function builders.info(spec)
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "infoRow",
        name = spec.name,
        value = spec.value,
        wide = spec.wide,
        multiline = spec.multiline,
    }, spec.height or 26, interop.applyInfoRowFrame)
    initializer._lsbRefreshFrame = function(frame)
        interop.applyInfoRowFrame(frame, initializer:GetData())
    end
    return layoutResult(initializer, type(spec.value) == "function" or type(spec.name) == "function")
end

function builders.canvas(canvas, height, spec)
    spec = spec or {}

    local modifiers = foundation.copyMixin({}, spec)
    modifiers.canvas = canvas

    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "embedCanvas",
        canvas = canvas,
    }, height or canvas:GetHeight(), interop.applyEmbedCanvasFrame)

    return { initializer = initializer, registration = "category", canvas = modifiers.canvas }
end

function builders.button(spec)
    local initializer = interop.createButtonInitializer(spec.name, spec.buttonText or spec.name, function()
        spec._onClick()
    end, spec.tooltip, true)
    interop.configureButtonInitializer(initializer)
    return layoutResult(initializer)
end
