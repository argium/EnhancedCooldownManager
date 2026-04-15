-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local REMOVE_STALE_SPELL_COLORS_POPUP = "ECM_CONFIRM_REMOVE_STALE_SPELL_COLORS"
local SPELL_COLORS_HEADER_BUTTON_WIDTH = 100

--- Generates the merged list of spell color rows from spell color entries.
---@param entries { key: ECM_SpellColorKey }[]|nil
---@return { key: ECM_SpellColorKey, textureFileID: number|nil }[]
local function buildSpellColorRows(entries)
    local rows = {}

    for _, entry in ipairs(entries or {}) do
        local normalized = ns.SpellColors.NormalizeKey(type(entry) == "table" and entry.key)
        if normalized then
            local merged = false
            for _, row in ipairs(rows) do
                if row.key:Matches(normalized) then
                    row.key = row.key:Merge(normalized) or row.key
                    row.textureFileID = row.key.textureFileID or row.textureFileID
                    merged = true
                    break
                end
            end

            if not merged then
                rows[#rows + 1] = {
                    key = normalized,
                    textureFileID = normalized.textureFileID,
                }
            end
        end
    end

    return rows
end

---@param key ECM_SpellColorKey|table|nil
---@return { hasSecretName: boolean, isIncomplete: boolean }|nil
local function getSpellColorKeyState(key)
    local normalized = ns.SpellColors.NormalizeKey(key)
    local primaryKey = normalized and normalized.primaryKey or (type(key) == "table" and key.primaryKey)
    if not normalized and type(primaryKey) ~= "string" then
        return nil
    end

    return {
        hasSecretName = type(primaryKey) == "string" and (issecretvalue(primaryKey) or primaryKey == ""),
        isIncomplete = normalized ~= nil and (normalized.spellName == nil
            or normalized.spellID == nil
            or normalized.cooldownID == nil
            or normalized.textureFileID == nil),
    }
end

---@return boolean
local function isSpellColorsReconcileRestricted()
    return _G.UnitAffectingCombat("player") or InCombatLockdown() or IsInInstance()
end

---@param rows { key: ECM_SpellColorKey }[]|nil
---@return { hasRowsNeedingReconcile: boolean, showSecretNameWarning: boolean, warningText: string, canReconcile: boolean }
local function getSpellColorsPageState(rows)
    local state = {
        hasRowsNeedingReconcile = false,
        showSecretNameWarning = false,
        warningText = "",
        canReconcile = false,
    }

    for _, row in ipairs(rows or {}) do
        local keyState = getSpellColorKeyState(row and row.key)
        if keyState then
            state.hasRowsNeedingReconcile = state.hasRowsNeedingReconcile or keyState.isIncomplete
            state.showSecretNameWarning = state.showSecretNameWarning or keyState.hasSecretName

            if state.hasRowsNeedingReconcile and state.showSecretNameWarning then
                break
            end
        end
    end

    if InCombatLockdown() then
        state.warningText = L["SPELL_COLORS_COMBAT_WARNING"]
    end

    state.canReconcile = state.hasRowsNeedingReconcile and not isSpellColorsReconcileRestricted()

    return state
end

---@param rows { key: ECM_SpellColorKey }[]|nil
---@return { key: ECM_SpellColorKey }[]
local function collectIncompleteSpellColorRows(rows)
    local incompleteRows = {}

    for _, row in ipairs(rows or {}) do
        local keyState = getSpellColorKeyState(row and row.key)
        if keyState and keyState.isIncomplete then
            incompleteRows[#incompleteRows + 1] = row
        end
    end

    return incompleteRows
end

---@param key ECM_SpellColorKey|table|nil
---@return string
local function getSpellColorRowName(key)
    local normalized = ns.SpellColors.NormalizeKey(key)
    local primaryKey = normalized and normalized.primaryKey or nil

    if type(primaryKey) == "string" then
        return primaryKey
    end

    return "Bar (" .. tostring(primaryKey) .. ")"
end

---@param key ECM_SpellColorKey|table|nil
---@return string[]
local function buildSpellColorKeyTooltipLines(key)
    local normalized = ns.SpellColors.NormalizeKey(key)
    if not normalized then
        return {}
    end

    local lines = {}

    local function addLine(formatString, value)
        local valueType = type(value)
        if valueType == "string" or valueType == "number" then
            lines[#lines + 1] = string.format(formatString, value)
        end
    end

    addLine(L["SPELL_COLORS_KEY_SPELL_NAME"], normalized.spellName)
    addLine(L["SPELL_COLORS_KEY_SPELL_ID"], normalized.spellID)
    addLine(L["SPELL_COLORS_KEY_COOLDOWN_ID"], normalized.cooldownID)
    addLine(L["SPELL_COLORS_KEY_TEXTURE_FILE_ID"], normalized.textureFileID)

    return lines
end

---@param owner Frame
---@param data { key: ECM_SpellColorKey }|nil
local function maybeShowSpellColorKeyTooltip(owner, data)
    if not IsControlKeyDown() then
        return
    end

    local lines = buildSpellColorKeyTooltipLines(type(data) == "table" and data.key)
    if #lines == 0 then
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if GameTooltip.ClearLines then
        GameTooltip:ClearLines()
    end
    GameTooltip:SetText(L["SPELL_COLORS_KEYS_TOOLTIP_TITLE"], 1, 1, 1, 1)

    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, 1, 1, 1, true)
    end

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Canvas Frame for Spell Colors
--------------------------------------------------------------------------------

local function createSpellColorPage(subcatName)
    local registeredPage
    local function setRegisteredPage(page)
        registeredPage = page
    end

    local function refreshPage()
        if registeredPage then
            registeredPage:Refresh()
        end
    end

    local function resetAllSpellColors()
        ns.SpellColors.ClearCurrentSpecColors()
        ns.SpellColors.SetDefaultColor(C.BUFFBARS_DEFAULT_COLOR)
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        refreshPage()
    end

    local function reconcileSpellColors()
        ns.Addon:ConfirmReloadUI(L["SPELL_COLORS_SECRET_NAMES_DESC"])
    end

    local function removeStaleSpellColors()
        local staleRows = collectIncompleteSpellColorRows(buildSpellColorRows(ns.SpellColors.GetAllColorEntries()))
        if #staleRows == 0 then
            return
        end

        ns.Addon:ShowConfirmDialog(
            REMOVE_STALE_SPELL_COLORS_POPUP,
            L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"],
            L["REMOVE"],
            L["SPELL_COLORS_DONT_REMOVE"],
            function()
                local staleKeys = {}
                for _, row in ipairs(staleRows) do
                    staleKeys[#staleKeys + 1] = row.key
                end

                local removedKeys = ns.SpellColors.RemoveEntriesByKeys(staleKeys)
                for _, key in ipairs(removedKeys) do
                    ns.Print(L["SPELL_COLORS_REMOVED_STALE_ENTRY"]:format(getSpellColorRowName(key)))
                end

                if #removedKeys > 0 then
                    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                    refreshPage()
                end
            end
        )
    end

    local function getRows()
        return buildSpellColorRows(ns.SpellColors.GetAllColorEntries())
    end

    local function buildSpellColorItems()
        local items = {}
        local rows = getRows()

        items[#items + 1] = {
            label = L["DEFAULT_COLOR"],
            color = {
                value = ns.SpellColors.GetDefaultColor(),
                enabled = function()
                    local locked = ns.Addon.BuffBars:IsEditLocked()
                    return not locked
                end,
                onClick = function()
                    local locked = ns.Addon.BuffBars:IsEditLocked()

                    if locked then
                        return
                    end

                    ns.OptionUtil.OpenColorPicker(ns.SpellColors.GetDefaultColor(), false, function(color)
                        ns.SpellColors.SetDefaultColor(color)
                        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                        refreshPage()
                    end)
                end,
            },
        }

        for _, row in ipairs(rows) do
            items[#items + 1] = {
                label = getSpellColorRowName(row.key),
                icon = row.textureFileID,
                color = {
                    value = ns.SpellColors.GetColorByKey(row.key) or ns.SpellColors.GetDefaultColor(),
                    onClick = function()
                        local locked = ns.Addon.BuffBars:IsEditLocked()

                        if locked then
                            return
                        end

                        local current = ns.SpellColors.GetColorByKey(row.key) or ns.SpellColors.GetDefaultColor()
                        ns.OptionUtil.OpenColorPicker(current, false, function(color)
                            ns.SpellColors.SetColorByKey(row.key, color)
                            ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                            refreshPage()
                        end)
                    end,
                },
                onEnter = function(owner)
                    maybeShowSpellColorKeyTooltip(owner, row)
                end,
                onLeave = function()
                    GameTooltip_Hide()
                end,
            }
        end
        return items
    end

    local pageSpec = {
        key = "spellColors",
        name = subcatName,
        rows = {
            {
                id = "spellColorsPageActions",
                type = "pageActions",
                name = subcatName,
                actions = {
                    {
                        text = L["SPELL_COLORS_RECONCILE_BUTTON"],
                        width = SPELL_COLORS_HEADER_BUTTON_WIDTH,
                        enabled = function()
                            return getSpellColorsPageState(getRows()).canReconcile
                        end,
                        onClick = function()
                            if getSpellColorsPageState(getRows()).canReconcile then
                                reconcileSpellColors()
                            end
                        end,
                    },
                    {
                        text = L["SPELL_COLORS_REMOVE_STALE_BUTTON"],
                        width = SPELL_COLORS_HEADER_BUTTON_WIDTH,
                        tooltip = L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"],
                        enabled = function()
                            return getSpellColorsPageState(getRows()).canReconcile
                        end,
                        onClick = function()
                            if getSpellColorsPageState(getRows()).canReconcile then
                                removeStaleSpellColors()
                            end
                        end,
                    },
                },
            },
            {
                id = "spellColorsDescription",
                type = "info",
                name = "",
                value = L["SPELL_COLORS_DESC"],
                wide = true,
                multiline = true,
                height = 36,
            },
            {
                id = "spellColorsWarning",
                type = "info",
                name = "",
                value = function()
                    return getSpellColorsPageState(getRows()).warningText
                end,
                wide = true,
                multiline = true,
                height = 30,
                hidden = function()
                    return getSpellColorsPageState(getRows()).warningText == ""
                end,
            },
            {
                id = "spellColorCollection",
                type = "list",
                variant = "swatch",
                height = 260,
                rowHeight = C.SCROLL_ROW_HEIGHT_COMPACT,
                items = buildSpellColorItems,
                onDefault = resetAllSpellColors,
            },
            {
                id = "secretNameDescription",
                type = "info",
                name = "",
                value = L["SPELL_COLORS_SECRET_NAMES_DESC"],
                wide = true,
                multiline = true,
                height = C.SPELL_COLORS_SECRET_NAMES_DESC_HEIGHT,
                hidden = function()
                    return not getSpellColorsPageState(getRows()).showSecretNameWarning
                end,
            },
        },
    }
    pageSpec.SetRegisteredPage = setRegisteredPage
    return pageSpec
end

--------------------------------------------------------------------------------
-- Options Registration
--------------------------------------------------------------------------------

local BuffBarsOptions = {}
ns.BuffBarsOptions = BuffBarsOptions
BuffBarsOptions._BuildSpellColorRows = buildSpellColorRows
BuffBarsOptions._CollectIncompleteSpellColorRows = collectIncompleteSpellColorRows
BuffBarsOptions._GetSpellColorsPageState = getSpellColorsPageState
BuffBarsOptions._BuildSpellColorKeyTooltipLines = buildSpellColorKeyTooltipLines

local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("buffBars")

local defaultZero = ns.OptionUtil.CreateDefaultValueTransform(0)
local layoutMovedButton = ns.OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton
layoutMovedButton.id = "layoutMovedButton"

BuffBarsOptions.key = "buffBars"
BuffBarsOptions.name = L["AURA_BARS"]
BuffBarsOptions.pages = {
    {
        key = "main",
        rows = {
            {
                id = "enabled",
                type = "checkbox",
                path = "enabled",
                name = L["ENABLE_AURA_BARS"],
                tooltip = L["ENABLE_AURA_BARS_DESC"],
                onSet = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", L["DISABLE_AURA_BARS_RELOAD"]),
            },

            layoutMovedButton,

            -- Appearance
            { id = "appearanceHeader", type = "header", name = L["APPEARANCE"], disabled = isDisabled },
            {
                id = "showIcon",
                type = "checkbox",
                path = "showIcon",
                name = L["SHOW_ICON"],
                disabled = isDisabled,
            },
            {
                id = "showSpellName",
                type = "checkbox",
                path = "showSpellName",
                name = L["SHOW_SPELL_NAME"],
                disabled = isDisabled,
            },
            {
                id = "showDuration",
                type = "checkbox",
                path = "showDuration",
                name = L["SHOW_REMAINING_DURATION"],
                disabled = isDisabled,
            },
            {
                id = "height",
                type = "slider",
                path = "height",
                name = L["HEIGHT_OVERRIDE"],
                tooltip = L["HEIGHT_OVERRIDE_DESC"],
                min = 0,
                max = 40,
                step = 1,
                disabled = isDisabled,
                getTransform = defaultZero,
                setTransform = function(value)
                    return value > 0 and value or nil
                end,
            },
            {
                id = "verticalSpacing",
                type = "slider",
                path = "verticalSpacing",
                name = L["AURA_VERTICAL_SPACING"],
                tooltip = L["AURA_VERTICAL_SPACING_DESC"],
                min = 0,
                max = 20,
                step = 1,
                disabled = isDisabled,
                getTransform = defaultZero,
            },
            (function()
                local row = ns.OptionUtil.CreateFontOverrideRow(isDisabled)
                row.id = "fontOverride"
                return row
            end)(),
        },
    },
    createSpellColorPage(L["SPELL_COLORS_SUBCAT"]),
}

function BuffBarsOptions.SetSpellColorsPage(page)
    local spellColorsPage = BuffBarsOptions.pages[2]
    if spellColorsPage and spellColorsPage.SetRegisteredPage then
        spellColorsPage.SetRegisteredPage(page)
    end
end
