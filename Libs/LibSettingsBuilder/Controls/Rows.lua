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

function lib._installStandardRowControls(SB, env, config)
    local applyModifiers = env.applyModifiers
    local registerCategoryRefreshable = env.registerCategoryRefreshable
    local resolveCategory = env.resolveCategory

    local function addLayoutInitializer(spec, initializer, refreshable)
        local cat = resolveCategory(spec)
        SB._layouts[cat]:AddInitializer(initializer)
        if refreshable then
            registerCategoryRefreshable(cat, initializer)
        end
        applyModifiers(initializer, spec)
        return initializer, cat
    end

    function SB.Header(textOrSpec, category)
        local spec
        if type(textOrSpec) == "table" then
            spec = textOrSpec
        else
            spec = {
                name = textOrSpec,
                category = category,
            }
        end

        assert(not spec.actions, "Header: use PageActions for category header buttons")
        local initializer = CreateSettingsListSectionHeaderInitializer(spec.name)
        return addLayoutInitializer(spec, initializer)
    end

    function SB.PageActions(spec)
        assert(spec.actions, "PageActions: spec.actions is required")

        local cat = resolveCategory(spec)
        local catName = SB._subcategoryNames[cat] or (cat == SB._rootCategory and SB._rootCategoryName) or ""
        local initializer = createCustomListRowInitializer(lib.SUBHEADER_TEMPLATE, {
            _lsbKind = "pageActions",
            name = spec.name or catName,
            actions = spec.actions,
            hideTitle = true,
            attachToCategoryHeader = true,
        }, spec.height or 1, applyHeaderFrame)
        initializer._lsbRefreshFrame = function(frame)
            applyHeaderFrame(frame, initializer:GetData())
        end
        initializer._lsbResetFrame = hideHeaderActionButtons
        return addLayoutInitializer(spec, initializer, true)
    end

    function SB.Subheader(spec)
        local initializer = createCustomListRowInitializer(lib.SUBHEADER_TEMPLATE, {
            _lsbKind = "subheader",
            name = spec.name,
        }, 28, applySubheaderFrame)
        return addLayoutInitializer(spec, initializer)
    end

    function SB.InfoRow(spec)
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
        return addLayoutInitializer(spec, initializer, type(spec.value) == "function" or type(spec.name) == "function")
    end

    function SB.EmbedCanvas(canvas, height, spec)
        spec = spec or {}
        local cat = spec.category or SB._currentSubcategory or SB._rootCategory

        local modifiers = copyMixin({}, spec)
        modifiers.canvas = canvas

        local initializer = createCustomListRowInitializer(lib.EMBED_CANVAS_TEMPLATE, {
            _lsbKind = "embedCanvas",
            canvas = canvas,
        }, height or canvas:GetHeight(), applyEmbedCanvasFrame)

        Settings.RegisterInitializer(cat, initializer)
        applyModifiers(initializer, modifiers)

        return initializer
    end

    local confirmDialogName = config.varPrefix .. "_" .. MAJOR:gsub("[%-%.]", "_") .. "_SettingsConfirm"
    StaticPopupDialogs[confirmDialogName] = {
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

    function SB.Button(spec)
        local onClick = spec.onClick
        if spec.confirm then
            local confirmText = type(spec.confirm) == "string" and spec.confirm or "Are you sure?"
            local originalClick = onClick
            onClick = function()
                StaticPopup_Show(confirmDialogName, confirmText, nil, { onAccept = originalClick })
            end
        end

        local initializer =
            CreateSettingsButtonInitializer(spec.name, spec.buttonText or spec.name, onClick, spec.tooltip, true)
        return addLayoutInitializer(spec, initializer)
    end

    return SB
end
