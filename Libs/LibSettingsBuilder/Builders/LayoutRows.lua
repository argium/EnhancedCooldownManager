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

local function addLayoutInitializer(self, spec, initializer, refreshable)
    local category = registry.resolveCategory(self, spec)
    interop.addLayoutInitializer(self._layouts[category], initializer)
    if refreshable then
        registry.registerCategoryRefreshable(self, category, initializer)
    end
    registry.applyModifiers(self, initializer, spec)
    return initializer, category
end

function builders.header(self, textOrSpec, category)
    local spec = type(textOrSpec) == "table" and textOrSpec or {
        name = textOrSpec,
        category = category,
    }

    assert(not spec.actions, "Header: use PageActions for page header buttons")
    return addLayoutInitializer(self, spec, interop.createSectionHeaderInitializer(spec.name))
end

function builders.pageActions(self, spec)
    assert(spec.actions, "PageActions: spec.actions is required")

    local category = registry.resolveCategory(self, spec)
    local categoryName = self._subcategoryNames[category]
        or (category == self._rootCategory and self._rootCategoryName)
        or ""
    local attachToCategoryHeader = spec.attachToCategoryHeader ~= false
    local hideTitle = spec.hideTitle
    if hideTitle == nil then
        hideTitle = attachToCategoryHeader
    end
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "pageActions",
        name = spec.name or categoryName,
        actions = spec.actions,
        hideTitle = hideTitle,
        attachToCategoryHeader = attachToCategoryHeader,
    }, spec.height or (attachToCategoryHeader and 1 or 28), interop.applyHeaderFrame)

    initializer._lsbEnabled = true
    initializer.SetEnabled = function(controlInitializer, enabled)
        controlInitializer._lsbEnabled = enabled
        local activeFrame = controlInitializer._lsbActiveFrame
        if activeFrame then
            registry.applyCanvasState(self, activeFrame, enabled)
        end
    end

    initializer._lsbRefreshFrame = function(frame)
        interop.applyHeaderFrame(frame, initializer:GetData())
        initializer:SetEnabled(initializer._lsbEnabled ~= false)
    end
    initializer._lsbResetFrame = interop.hideHeaderActionButtons
    return addLayoutInitializer(self, spec, initializer, true)
end

function builders.subheader(self, spec)
    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "subheader",
        name = spec.name,
    }, 28, interop.applySubheaderFrame)
    return addLayoutInitializer(self, spec, initializer)
end

function builders.info(self, spec)
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
    return addLayoutInitializer(self, spec, initializer, type(spec.value) == "function" or type(spec.name) == "function")
end

function builders.canvas(self, canvas, height, spec)
    spec = spec or {}

    local modifiers = foundation.copyMixin({}, spec)
    modifiers.canvas = canvas

    local initializer = interop.createCustomListRowInitializer("SettingsListElementTemplate", {
        _lsbKind = "embedCanvas",
        canvas = canvas,
    }, height or canvas:GetHeight(), interop.applyEmbedCanvasFrame)

    interop.registerInitializer(registry.resolveCategory(self, spec), initializer)
    registry.applyModifiers(self, initializer, modifiers)

    return initializer
end

local function ensureConfirmDialog(self)
    if self._confirmDialogName then
        return self._confirmDialogName
    end

    self._confirmDialogName = self._config.varPrefix .. "_" .. MAJOR:gsub("[%-%.]", "_") .. "_SettingsConfirm"
    return interop.ensureConfirmDialog(self._confirmDialogName)
end

function builders.button(self, spec)
    local callbackContext = registry.createCallbackContext(self, spec)
    local onClick = spec.onClick
    if spec.confirm then
        local confirmDialogName = ensureConfirmDialog(self)
        local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
        local originalClick = onClick
        onClick = function(ctx)
            interop.showConfirmDialog(confirmDialogName, confirmText, {
                onAccept = function()
                    originalClick(ctx)
                end,
            })
        end
    end

    local initializer = interop.createButtonInitializer(spec.name, spec.buttonText or spec.name, function()
        onClick(callbackContext)
    end, spec.tooltip, true)
    return addLayoutInitializer(self, spec, initializer)
end
