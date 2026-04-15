-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR = "LibSettingsBuilder-1.0"
local lib = LibStub(MAJOR, true)
if not lib or not lib._loadState or not lib._loadState.open then
    return
end

local internal = lib._internal
local applyEmbedCanvasFrame = internal.applyEmbedCanvasFrame
local applyHeaderFrame = internal.applyHeaderFrame
local applyInfoRowFrame = internal.applyInfoRowFrame
local applySubheaderFrame = internal.applySubheaderFrame
local copyMixin = internal.copyMixin
local createCustomListRowInitializer = internal.createCustomListRowInitializer
local hideHeaderActionButtons = internal.hideHeaderActionButtons
local BuilderMixin = lib.BuilderMixin

function BuilderMixin:_addLayoutInitializer(spec, initializer, refreshable)
    local category = self:_resolveCategory(spec)
    self._layouts[category]:AddInitializer(initializer)
    if refreshable then
        self:_registerCategoryRefreshable(category, initializer)
    end
    self:_applyModifiers(initializer, spec)
    return initializer, category
end

function BuilderMixin:Header(textOrSpec, category)
    local spec = type(textOrSpec) == "table" and textOrSpec or {
        name = textOrSpec,
        category = category,
    }

    assert(not spec.actions, "Header: use PageActions for page header buttons")
    local initializer = CreateSettingsListSectionHeaderInitializer(spec.name)
    return self:_addLayoutInitializer(spec, initializer)
end

function BuilderMixin:PageActions(spec)
    assert(spec.actions, "PageActions: spec.actions is required")

    local category = self:_resolveCategory(spec)
    local categoryName = self._subcategoryNames[category]
        or (category == self._rootCategory and self._rootCategoryName)
        or ""
    local initializer = createCustomListRowInitializer(lib.SUBHEADER_TEMPLATE, {
        _lsbKind = "pageActions",
        name = spec.name or categoryName,
        actions = spec.actions,
        hideTitle = true,
        attachToCategoryHeader = true,
    }, spec.height or 1, applyHeaderFrame)
    initializer._lsbRefreshFrame = function(frame)
        applyHeaderFrame(frame, initializer:GetData())
    end
    initializer._lsbResetFrame = hideHeaderActionButtons
    return self:_addLayoutInitializer(spec, initializer, true)
end

function BuilderMixin:Subheader(spec)
    local initializer = createCustomListRowInitializer(lib.SUBHEADER_TEMPLATE, {
        _lsbKind = "subheader",
        name = spec.name,
    }, 28, applySubheaderFrame)
    return self:_addLayoutInitializer(spec, initializer)
end

function BuilderMixin:InfoRow(spec)
    local initializer = createCustomListRowInitializer(lib.INFOROW_TEMPLATE, {
        _lsbKind = "infoRow",
        name = spec.name,
        value = spec.value,
        wide = spec.wide,
        multiline = spec.multiline,
    }, spec.height or 26, applyInfoRowFrame)
    initializer._lsbRefreshFrame = function(frame)
        applyInfoRowFrame(frame, initializer:GetData())
    end
    return self:_addLayoutInitializer(spec, initializer, type(spec.value) == "function" or type(spec.name) == "function")
end

function BuilderMixin:EmbedCanvas(canvas, height, spec)
    spec = spec or {}

    local modifiers = copyMixin({}, spec)
    modifiers.canvas = canvas

    local initializer = createCustomListRowInitializer(lib.EMBED_CANVAS_TEMPLATE, {
        _lsbKind = "embedCanvas",
        canvas = canvas,
    }, height or canvas:GetHeight(), applyEmbedCanvasFrame)

    Settings.RegisterInitializer(self:_resolveCategory(spec), initializer)
    self:_applyModifiers(initializer, modifiers)

    return initializer
end

function BuilderMixin:_ensureConfirmDialog()
    if self._confirmDialogName then
        return self._confirmDialogName
    end

    self._confirmDialogName = self._config.varPrefix .. "_" .. MAJOR:gsub("[%-%.]", "_") .. "_SettingsConfirm"
    if not StaticPopupDialogs[self._confirmDialogName] then
        StaticPopupDialogs[self._confirmDialogName] = {
            text = "%s",
            button1 = YES,
            button2 = NO,
            OnAccept = function(_, data)
                if data and data.onAccept then
                    data.onAccept()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
    end

    return self._confirmDialogName
end

function BuilderMixin:Button(spec)
    local onClick = spec.onClick
    if spec.confirm then
        local confirmDialogName = self:_ensureConfirmDialog()
        local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
        local originalClick = onClick
        onClick = function()
            StaticPopup_Show(confirmDialogName, confirmText, nil, { onAccept = originalClick })
        end
    end

    local initializer = CreateSettingsButtonInitializer(spec.name, spec.buttonText or spec.name, onClick, spec.tooltip, true)
    return self:_addLayoutInitializer(spec, initializer)
end
