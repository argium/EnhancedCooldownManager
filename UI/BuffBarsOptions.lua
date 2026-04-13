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

--- Scans rows for entries whose primary key is a secret or empty string.
---@param rows { key: ECM_SpellColorKey }[]
---@return boolean
local function hasUnlabeledBars(rows)
    for _, row in ipairs(rows) do
        local key = row.key.primaryKey
        if type(key) == "string" and (issecretvalue(key) or key == "") then
            return true
        end
    end
    return false
end

--- Returns whether the player is in an environment where secret-name recovery should stay disabled.
---@return boolean
local function isSpellColorsReloadRestricted()
    return InCombatLockdown() or IsInInstance()
end

--- Returns the footer state for the secret-name recovery controls.
---@param rows { key: ECM_SpellColorKey }[]
---@return { show: boolean, enabled: boolean }
local function getSecretNameFooterState(rows)
    local show = hasUnlabeledBars(rows)
    return {
        show = show,
        enabled = show and not isSpellColorsReloadRestricted(),
    }
end

--- Returns true when the key is missing one or more identifying fields.
---@param key ECM_SpellColorKey|table|nil
---@return boolean
local function isIncompleteSpellColorKey(key)
    local normalized = ns.SpellColors.NormalizeKey(key)
    return normalized ~= nil
        and (normalized.spellName == nil
            or normalized.spellID == nil
            or normalized.cooldownID == nil
            or normalized.textureFileID == nil)
end

--- Returns whether any row is missing one or more identifying fields.
---@param rows { key: ECM_SpellColorKey }[]|nil
---@return boolean
local function hasRowsNeedingReconcile(rows)
    for _, row in ipairs(rows or {}) do
        if isIncompleteSpellColorKey(row and row.key) then
            return true
        end
    end

    return false
end

---@param rows { key: ECM_SpellColorKey }[]|nil
---@return { key: ECM_SpellColorKey }[]
local function collectIncompleteSpellColorRows(rows)
    local incompleteRows = {}

    for _, row in ipairs(rows or {}) do
        if isIncompleteSpellColorKey(row and row.key) then
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

local function createSpellColorCanvas(SB, subcatName)
    local function resetAllSpellColors()
        ns.SpellColors.ClearCurrentSpecColors()
        ns.SpellColors.SetDefaultColor(C.BUFFBARS_DEFAULT_COLOR)
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        SB.RefreshCategory(subcatName)
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
                    SB.RefreshCategory(subcatName)
                end
            end
        )
    end

    local function getRows()
        return buildSpellColorRows(ns.SpellColors.GetAllColorEntries())
    end

    local function getWarningText()
        local parts = {}
        local locked, reason = ns.Addon.BuffBars:IsEditLocked()
        if locked and reason == "combat" then
            parts[#parts + 1] = L["SPELL_COLORS_COMBAT_WARNING"]
        elseif locked and reason == "secrets" then
            parts[#parts + 1] = L["SPELL_COLORS_SECRETS_WARNING"]
        end
        return table.concat(parts, "\n")
    end

    local function buildSpellColorItems()
        local items = {}

        items[#items + 1] = {
            label = L["DEFAULT_COLOR"],
            color = {
                value = ns.SpellColors.GetDefaultColor(),
                enabled = function()
                    local locked = ns.Addon.BuffBars:IsEditLocked()
                    return not locked
                end,
                onClick = function()
                    if ns.Addon.BuffBars:IsEditLocked() then
                        return
                    end
                    ns.OptionUtil.OpenColorPicker(ns.SpellColors.GetDefaultColor(), false, function(color)
                        ns.SpellColors.SetDefaultColor(color)
                        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                        SB.RefreshCategory(subcatName)
                    end)
                end,
            },
        }

        for _, row in ipairs(getRows()) do
            items[#items + 1] = {
                label = getSpellColorRowName(row.key),
                icon = row.textureFileID,
                color = {
                    value = ns.SpellColors.GetColorByKey(row.key) or ns.SpellColors.GetDefaultColor(),
                    onClick = function()
                        if ns.Addon.BuffBars:IsEditLocked() then
                            return
                        end
                        local current = ns.SpellColors.GetColorByKey(row.key) or ns.SpellColors.GetDefaultColor()
                        ns.OptionUtil.OpenColorPicker(current, false, function(color)
                            ns.SpellColors.SetColorByKey(row.key, color)
                            ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                            SB.RefreshCategory(subcatName)
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

    SB.RegisterFromTable({
        name = subcatName,
        args = {
            spellColorsHeader = {
                type = "header",
                name = subcatName,
                actions = {
                    {
                        text = L["SPELL_COLORS_RECONCILE_BUTTON"],
                        width = SPELL_COLORS_HEADER_BUTTON_WIDTH,
                        enabled = function()
                            local rows = getRows()
                            return hasRowsNeedingReconcile(rows) and not isSpellColorsReloadRestricted()
                        end,
                        onClick = function()
                            if hasRowsNeedingReconcile(getRows()) and not isSpellColorsReloadRestricted() then
                                reconcileSpellColors()
                            end
                        end,
                    },
                    {
                        text = L["SPELL_COLORS_REMOVE_STALE_BUTTON"],
                        width = SPELL_COLORS_HEADER_BUTTON_WIDTH,
                        tooltip = L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"],
                        enabled = function()
                            local rows = getRows()
                            return hasRowsNeedingReconcile(rows) and not isSpellColorsReloadRestricted()
                        end,
                        onClick = function()
                            if hasRowsNeedingReconcile(getRows()) and not isSpellColorsReloadRestricted() then
                                removeStaleSpellColors()
                            end
                        end,
                    },
                },
                order = 1,
            },
            spellColorsDescription = {
                type = "info",
                name = "",
                value = L["SPELL_COLORS_DESC"],
                wide = true,
                multiline = true,
                height = 36,
                order = 2,
            },
            spellColorsWarning = {
                type = "info",
                name = "",
                value = getWarningText,
                wide = true,
                multiline = true,
                height = 30,
                hidden = function()
                    return getWarningText() == ""
                end,
                order = 3,
            },
            spellColorCollection = {
                type = "collection",
                preset = "swatch",
                height = 260,
                rowHeight = C.SCROLL_ROW_HEIGHT_COMPACT,
                items = buildSpellColorItems,
                onDefault = resetAllSpellColors,
                order = 4,
            },
            secretNameDescription = {
                type = "info",
                name = "",
                value = L["SPELL_COLORS_SECRET_NAMES_DESC"],
                wide = true,
                multiline = true,
                height = C.SPELL_COLORS_SECRET_NAMES_DESC_HEIGHT,
                hidden = function()
                    return not getSecretNameFooterState(getRows()).show
                end,
                order = 5,
            },
            secretNameReload = {
                type = "button",
                name = " ",
                buttonText = L["SPELL_COLORS_RELOAD_BUTTON"],
                hidden = function()
                    return not getSecretNameFooterState(getRows()).show
                end,
                disabled = function()
                    return not getSecretNameFooterState(getRows()).enabled
                end,
                onClick = function()
                    ns.Addon:ConfirmReloadUI(L["SPELL_COLORS_SECRET_NAMES_DESC"])
                end,
                order = 6,
            },
        },
    })
end

--------------------------------------------------------------------------------
-- Options Registration
--------------------------------------------------------------------------------

local BuffBarsOptions = {}
ns.BuffBarsOptions = BuffBarsOptions
BuffBarsOptions._BuildSpellColorRows = buildSpellColorRows
BuffBarsOptions._HasUnlabeledBars = hasUnlabeledBars
BuffBarsOptions._HasRowsNeedingReconcile = hasRowsNeedingReconcile
BuffBarsOptions._CollectIncompleteSpellColorRows = collectIncompleteSpellColorRows
BuffBarsOptions._IsSpellColorsReloadRestricted = isSpellColorsReloadRestricted
BuffBarsOptions._GetSecretNameFooterState = getSecretNameFooterState
BuffBarsOptions._BuildSpellColorKeyTooltipLines = buildSpellColorKeyTooltipLines

local isDisabled = ns.OptionUtil.GetIsDisabledDelegate("buffBars")

function BuffBarsOptions.RegisterSettings(SB)
    local defaultZero = ns.OptionUtil.CreateDefaultValueTransform(0)
    SB.RegisterFromTable({
        name = L["AURA_BARS"],
        path = "buffBars",
        args = {
            enabled = {
                type = "toggle",
                path = "enabled",
                name = L["ENABLE_AURA_BARS"],
                desc = L["ENABLE_AURA_BARS_DESC"],
                order = 0,
                onSet = ns.OptionUtil.CreateModuleEnabledHandler("BuffBars", L["DISABLE_AURA_BARS_RELOAD"]),
            },

            layoutMovedButton = ns.OptionUtil.CreateLayoutBreadcrumbArgs(10).layoutMovedButton,

            -- Appearance
            appearanceHeader = { type = "header", name = L["APPEARANCE"], disabled = isDisabled, order = 20 },
            showIcon = { type = "toggle", path = "showIcon", name = L["SHOW_ICON"], disabled = isDisabled, order = 21 },
            showSpellName = {
                type = "toggle",
                path = "showSpellName",
                name = L["SHOW_SPELL_NAME"],
                disabled = isDisabled,
                order = 22,
            },
            showDuration = {
                type = "toggle",
                path = "showDuration",
                name = L["SHOW_REMAINING_DURATION"],
                disabled = isDisabled,
                order = 23,
            },
            height = {
                type = "range",
                path = "height",
                name = L["HEIGHT_OVERRIDE"],
                desc = L["HEIGHT_OVERRIDE_DESC"],
                min = 0,
                max = 40,
                step = 1,
                disabled = isDisabled,
                getTransform = defaultZero,
                setTransform = function(value)
                    return value > 0 and value or nil
                end,
                order = 24,
            },
            verticalSpacing = {
                type = "range",
                path = "verticalSpacing",
                name = L["AURA_VERTICAL_SPACING"],
                desc = L["AURA_VERTICAL_SPACING_DESC"],
                min = 0,
                max = 20,
                step = 1,
                disabled = isDisabled,
                getTransform = defaultZero,
                order = 25,
            },
            fontOverride = { type = "fontOverride", disabled = isDisabled, order = 26 },
        },
    })

    createSpellColorCanvas(SB, L["SPELL_COLORS_SUBCAT"])
end

ns.SettingsBuilder.RegisterSection(ns, "BuffBars", BuffBarsOptions)
