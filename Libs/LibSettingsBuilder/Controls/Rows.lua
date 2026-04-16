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
function lib:_addLayoutInitializer(spec, initializer, refreshable)
    local category = self:_resolveCategory(spec)
    self._layouts[category]:AddInitializer(initializer)
    if refreshable then
        self:_registerCategoryRefreshable(category, initializer)
    end
    self:_applyModifiers(initializer, spec)
    return initializer, category
end

function lib:Header(textOrSpec, category)
    local spec = type(textOrSpec) == "table" and textOrSpec or {
        name = textOrSpec,
        category = category,
    }

    assert(not spec.actions, "Header: use PageActions for page header buttons")
    local initializer = CreateSettingsListSectionHeaderInitializer(spec.name)
    return self:_addLayoutInitializer(spec, initializer)
end

function lib:PageActions(spec)
    assert(spec.actions, "PageActions: spec.actions is required")

    local category = self:_resolveCategory(spec)
    local categoryName = self._subcategoryNames[category]
        or (category == self._rootCategory and self._rootCategoryName)
        or ""
    local initializer = createCustomListRowInitializer(internal.SUBHEADER_TEMPLATE, {
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

function lib:Subheader(spec)
    local initializer = createCustomListRowInitializer(internal.SUBHEADER_TEMPLATE, {
        _lsbKind = "subheader",
        name = spec.name,
    }, 28, applySubheaderFrame)
    return self:_addLayoutInitializer(spec, initializer)
end

function lib:InfoRow(spec)
    local initializer = createCustomListRowInitializer(internal.INFOROW_TEMPLATE, {
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

function lib:EmbedCanvas(canvas, height, spec)
    spec = spec or {}

    local modifiers = copyMixin({}, spec)
    modifiers.canvas = canvas

    local initializer = createCustomListRowInitializer(internal.EMBED_CANVAS_TEMPLATE, {
        _lsbKind = "embedCanvas",
        canvas = canvas,
    }, height or canvas:GetHeight(), applyEmbedCanvasFrame)

    Settings.RegisterInitializer(self:_resolveCategory(spec), initializer)
    self:_applyModifiers(initializer, modifiers)

    return initializer
end

function lib:_ensureConfirmDialog()
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

function lib:Button(spec)
    local callbackContext = self:_createCallbackContext(spec)
    local onClick = spec.onClick
    if spec.confirm then
        local confirmDialogName = self:_ensureConfirmDialog()
        local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
        local originalClick = onClick
        onClick = function(ctx)
            StaticPopup_Show(confirmDialogName, confirmText, nil, {
                onAccept = function()
                    originalClick(ctx)
                end,
            })
        end
    end

    local initializer = CreateSettingsButtonInitializer(spec.name, spec.buttonText or spec.name, function()
        onClick(callbackContext)
    end, spec.tooltip, true)
    return self:_addLayoutInitializer(spec, initializer)
end
