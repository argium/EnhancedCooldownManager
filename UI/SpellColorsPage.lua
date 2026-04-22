-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local REMOVE_STALE_SPELL_COLORS_POPUP = "ECM_CONFIRM_REMOVE_STALE_SPELL_COLORS"
local SPELL_COLORS_HEADER_BUTTON_WIDTH = 100

local SpellColorsPage = ns.SpellColorsPage or {}
ns.SpellColorsPage = SpellColorsPage

local spellColorSections = SpellColorsPage._sections or {}
SpellColorsPage._sections = spellColorSections

local pageSpec = SpellColorsPage._pageSpec
local registeredPage = SpellColorsPage._registeredPage

---@param scope string|nil
---@return ECM_SpellColorStore
local function getSpellColors(scope)
    return ns.SpellColors.Get(scope)
end

---@param scope string|nil
---@return ECM_Color
local function getScopeDefaultColor(scope)
    local defaults = ns.defaults and ns.defaults.profile and ns.defaults.profile[scope]
    local color = defaults and defaults.colors and defaults.colors.defaultColor
    return color or C.BUFFBARS_DEFAULT_COLOR
end

---@param entries { key: ECM_SpellColorKey }[]|nil
---@param scope string|nil
---@return { key: ECM_SpellColorKey, textureFileID: number|nil }[]
local function buildSpellColorRows(entries, scope)
    local rows = {}
    local resolvedEntries = entries or getSpellColors(scope):GetAllColorEntries()

    for _, entry in ipairs(resolvedEntries or {}) do
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
---@param _scope string|nil
---@return { hasSecretName: boolean, isIncomplete: boolean }|nil
local function getSpellColorKeyState(key, _scope)
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
---@param scope string|nil
---@return { hasRowsNeedingReconcile: boolean, showSecretNameWarning: boolean, warningText: string, canReconcile: boolean }
local function getSpellColorsPageState(rows, scope)
    local state = {
        hasRowsNeedingReconcile = false,
        showSecretNameWarning = false,
        warningText = "",
        canReconcile = false,
    }
    local resolvedRows = rows or buildSpellColorRows(nil, scope)

    for _, row in ipairs(resolvedRows or {}) do
        local keyState = getSpellColorKeyState(row and row.key, scope)
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
---@param scope string|nil
---@return { key: ECM_SpellColorKey }[]
local function collectIncompleteSpellColorRows(rows, scope)
    local incompleteRows = {}
    local resolvedRows = rows or buildSpellColorRows(nil, scope)

    for _, row in ipairs(resolvedRows or {}) do
        local keyState = getSpellColorKeyState(row and row.key, scope)
        if keyState and keyState.isIncomplete then
            incompleteRows[#incompleteRows + 1] = row
        end
    end

    return incompleteRows
end

---@param key ECM_SpellColorKey|table|nil
---@param _scope string|nil
---@return string
local function getSpellColorRowName(key, _scope)
    local normalized = ns.SpellColors.NormalizeKey(key)
    local primaryKey = normalized and normalized.primaryKey or nil

    if type(primaryKey) == "string" then
        return primaryKey
    end

    return "Bar (" .. tostring(primaryKey) .. ")"
end

---@param key ECM_SpellColorKey|table|nil
---@param _scope string|nil
---@return string[]
local function buildSpellColorKeyTooltipLines(key, _scope)
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
---@param scope string|nil
local function maybeShowSpellColorKeyTooltip(owner, data, scope)
    if not IsControlKeyDown() then
        return
    end

    local lines = buildSpellColorKeyTooltipLines(type(data) == "table" and data.key, scope)
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

---@param refreshPage fun()
local function refreshSpellColors(refreshPage)
    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
    refreshPage()
end

---@param section table
---@return boolean
local function isSpellColorSectionDisabled(section)
    return section.isDisabledDelegate and section.isDisabledDelegate() or false
end

---@param section table
---@return table|nil
local function getSpellColorOwnerModule(section)
    return ns.Addon and section and section.ownerModuleName and ns.Addon[section.ownerModuleName] or nil
end

---@param section table
---@return boolean
local function isSpellColorSectionEditLocked(section)
    local ownerModule = getSpellColorOwnerModule(section)
    if ownerModule and ownerModule.IsEditLocked then
        return ownerModule:IsEditLocked()
    end
    return false
end

---@param section table
---@return boolean
local function isSpellColorSectionInteractionDisabled(section)
    return isSpellColorSectionDisabled(section) or isSpellColorSectionEditLocked(section)
end

---@param section table
---@return { key: ECM_SpellColorKey, textureFileID: number|nil }[]
local function getSectionSpellColorRows(section)
    return buildSpellColorRows(nil, section.scope)
end

---@param section table
---@return { hasRowsNeedingReconcile: boolean, showSecretNameWarning: boolean, warningText: string, canReconcile: boolean }
local function getSectionSpellColorPageState(section)
    return getSpellColorsPageState(nil, section.scope)
end

---@param refreshPage fun()|nil
local function doRefreshPage(refreshPage)
    if refreshPage then
        refreshPage()
        return
    end

    if registeredPage then
        registeredPage:Refresh()
    end
end

local combatRefreshCallback

---@param page Frame|table|nil
function SpellColorsPage.SetRegisteredPage(page)
    registeredPage = page
    SpellColorsPage._registeredPage = page

    if combatRefreshCallback then
        return
    end

    local addon = ns.Addon
    if not addon or type(addon.RegisterEvent) ~= "function" then
        return
    end

    combatRefreshCallback = function()
        doRefreshPage()
    end

    addon:RegisterEvent("PLAYER_REGEN_DISABLED", combatRefreshCallback)
    addon:RegisterEvent("PLAYER_REGEN_ENABLED", combatRefreshCallback)
end

---@param section table
local function resetSpellColorSection(section)
    local spellColors = getSpellColors(section.scope)
    spellColors:ClearCurrentSpecColors()
    spellColors:SetDefaultColor(getScopeDefaultColor(section.scope))
end

local function reconcileSpellColors()
    ns.Addon:ConfirmReloadUI(L["SPELL_COLORS_SECRET_NAMES_DESC"])
end

---@param section table
---@return ECM_SpellColorKey[]
local function removeStaleSpellColorSection(section)
    local staleRows = collectIncompleteSpellColorRows(nil, section.scope)
    if #staleRows == 0 then
        return {}
    end

    local staleKeys = {}
    for _, row in ipairs(staleRows) do
        staleKeys[#staleKeys + 1] = row.key
    end

    local removedKeys = getSpellColors(section.scope):RemoveEntriesByKeys(staleKeys)
    for _, key in ipairs(removedKeys) do
        ns.Print(L["SPELL_COLORS_REMOVED_STALE_ENTRY"]:format(getSpellColorRowName(key, section.scope)))
    end

    return removedKeys
end

---@param section table
---@param refreshPage fun()
---@return table[]
local function buildSpellColorItems(section, refreshPage)
    local items = {}
    local rows = getSectionSpellColorRows(section)
    local spellColors = getSpellColors(section.scope)

    local function isInteractionDisabled()
        return isSpellColorSectionInteractionDisabled(section)
    end

    local function decorateItem(item)
        if isSpellColorSectionDisabled(section) then
            item.alpha = 0.5
            item.iconDesaturated = true
        end
        return item
    end

    items[#items + 1] = decorateItem({
        label = L["DEFAULT_COLOR"],
        color = {
            value = spellColors:GetDefaultColor(),
            enabled = function()
                return not isInteractionDisabled()
            end,
            onClick = function()
                if isInteractionDisabled() then
                    return
                end

                ns.OptionUtil.OpenColorPicker(spellColors:GetDefaultColor(), false, function(color)
                    spellColors:SetDefaultColor(color)
                    refreshSpellColors(function()
                        doRefreshPage(refreshPage)
                    end)
                end)
            end,
        },
    })

    for _, row in ipairs(rows) do
        items[#items + 1] = decorateItem({
            label = getSpellColorRowName(row.key, section.scope),
            icon = row.textureFileID,
            color = {
                value = spellColors:GetColorByKey(row.key) or spellColors:GetDefaultColor(),
                enabled = function()
                    return not isInteractionDisabled()
                end,
                onClick = function()
                    if isInteractionDisabled() then
                        return
                    end

                    local current = spellColors:GetColorByKey(row.key) or spellColors:GetDefaultColor()
                    ns.OptionUtil.OpenColorPicker(current, false, function(color)
                        spellColors:SetColorByKey(row.key, color)
                        refreshSpellColors(function()
                            doRefreshPage(refreshPage)
                        end)
                    end)
                end,
            },
            onEnter = function(owner)
                maybeShowSpellColorKeyTooltip(owner, row, section.scope)
            end,
            onLeave = function()
                GameTooltip_Hide()
            end,
        })
    end

    return items
end

---@param predicate fun(section: table): boolean
---@return boolean
local function doesAnySpellColorSectionMatch(predicate)
    for _, section in ipairs(spellColorSections) do
        if predicate(section) then
            return true
        end
    end

    return false
end

---@return boolean
local function canResetAnySpellColorSection()
    return doesAnySpellColorSectionMatch(function(section)
        return not isSpellColorSectionInteractionDisabled(section)
    end)
end

---@return boolean
local function canMaintainAnySpellColorSection()
    return doesAnySpellColorSectionMatch(function(section)
        return not isSpellColorSectionInteractionDisabled(section)
            and getSectionSpellColorPageState(section).canReconcile
    end)
end

---@param refreshPage fun()
local function resetAllSpellColors(refreshPage)
    local didReset = false

    for _, section in ipairs(spellColorSections) do
        if not isSpellColorSectionInteractionDisabled(section) then
            resetSpellColorSection(section)
            didReset = true
        end
    end

    if didReset then
        refreshSpellColors(function()
            doRefreshPage(refreshPage)
        end)
    end
end

---@param refreshPage fun()
local function removeAllStaleSpellColors(refreshPage)
    if not canMaintainAnySpellColorSection() then
        return
    end

    ns.Addon:ShowConfirmDialog(
        REMOVE_STALE_SPELL_COLORS_POPUP,
        L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"],
        L["REMOVE"],
        L["SPELL_COLORS_DONT_REMOVE"],
        function()
            local removedAny = false

            for _, section in ipairs(spellColorSections) do
                if not isSpellColorSectionInteractionDisabled(section)
                    and getSectionSpellColorPageState(section).canReconcile then
                    local removedKeys = removeStaleSpellColorSection(section)
                    if #removedKeys > 0 then
                        removedAny = true
                    end
                end
            end

            if removedAny then
                refreshSpellColors(function()
                    doRefreshPage(refreshPage)
                end)
            end
        end
    )
end

---@param refreshPage fun()
---@return table
local function createSpellColorPageActionsRow(refreshPage)
    return {
        id = "spellColorsPageActions",
        type = "pageActions",
        actions = {
            {
                text = L["SPELL_COLORS_RECONCILE_BUTTON"],
                width = SPELL_COLORS_HEADER_BUTTON_WIDTH,
                enabled = function()
                    return canMaintainAnySpellColorSection()
                end,
                onClick = function()
                    if not canMaintainAnySpellColorSection() then
                        return
                    end

                    reconcileSpellColors()
                end,
            },
            {
                text = L["SPELL_COLORS_REMOVE_STALE_BUTTON"],
                width = SPELL_COLORS_HEADER_BUTTON_WIDTH,
                tooltip = L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"],
                enabled = function()
                    return canMaintainAnySpellColorSection()
                end,
                onClick = function()
                    if not canMaintainAnySpellColorSection() then
                        return
                    end

                    removeAllStaleSpellColors(refreshPage)
                end,
            },
        },
    }
end

---@param section table
---@return table
local function createSpellColorSectionHeaderRow(section)
    return {
        id = section.key .. "SpellColorsHeader",
        type = "header",
        name = section.label,
        disabled = section.isDisabledDelegate,
    }
end

---@param section table
---@return table
local function createSpellColorWarningRow(section)
    return {
        id = section.key .. "SpellColorsWarning",
        type = "info",
        name = "",
        value = function()
            return getSectionSpellColorPageState(section).warningText
        end,
        wide = true,
        multiline = true,
        height = 30,
        hidden = function()
            return getSectionSpellColorPageState(section).warningText == ""
        end,
    }
end

---@param section table
---@param refreshPage fun()
---@return table
local function createSpellColorListRow(section, refreshPage)
    return {
        id = section.key .. "SpellColorCollection",
        type = "list",
        variant = "swatch",
        height = 180,
        rowHeight = C.SCROLL_ROW_HEIGHT_COMPACT,
        items = function()
            return buildSpellColorItems(section, refreshPage)
        end,
    }
end

---@param section table
---@return table
local function createSecretNameDescriptionRow(section)
    return {
        id = section.key .. "SecretNameDescription",
        type = "info",
        name = "",
        value = L["SPELL_COLORS_SECRET_NAMES_DESC"],
        wide = true,
        multiline = true,
        height = C.SPELL_COLORS_SECRET_NAMES_DESC_HEIGHT,
        hidden = function()
            return not getSectionSpellColorPageState(section).showSecretNameWarning
        end,
    }
end

local function buildPageRows()
    local rows = {}

    local function refreshPage()
        if registeredPage then
            registeredPage:Refresh()
        end
    end

    if #spellColorSections > 0 then
        rows[#rows + 1] = createSpellColorPageActionsRow(refreshPage)
        rows[#rows + 1] = {
            id = "spellColorsDescription",
            type = "info",
            name = "",
            value = L["SPELL_COLORS_DESC"],
            wide = true,
            multiline = true,
            height = 36,
        }
    end

    for _, section in ipairs(spellColorSections) do
        rows[#rows + 1] = createSpellColorSectionHeaderRow(section)

        rows[#rows + 1] = createSpellColorWarningRow(section)
        rows[#rows + 1] = createSpellColorListRow(section, refreshPage)
        rows[#rows + 1] = createSecretNameDescriptionRow(section)
    end

    return rows
end

local function rebuildPageSpecRows()
    if pageSpec then
        pageSpec.rows = buildPageRows()
    end
end

---@param section { key: string, label: string, scope: string, isDisabledDelegate: fun(): boolean, ownerModuleName: string }
function SpellColorsPage.RegisterSection(section)
    assert(type(section) == "table", "SpellColorsPage.RegisterSection: section must be a table")
    assert(type(section.key) == "string", "SpellColorsPage.RegisterSection: section.key is required")
    assert(type(section.label) == "string", "SpellColorsPage.RegisterSection: section.label is required")
    assert(type(section.scope) == "string", "SpellColorsPage.RegisterSection: section.scope is required")
    assert(type(section.ownerModuleName) == "string", "SpellColorsPage.RegisterSection: ownerModuleName is required")

    for index, existing in ipairs(spellColorSections) do
        if existing.key == section.key then
            spellColorSections[index] = section
            rebuildPageSpecRows()
            return section
        end
    end

    spellColorSections[#spellColorSections + 1] = section
    rebuildPageSpecRows()
    return section
end

---@param configPath string
---@param ownerModuleName string
---@return fun(): boolean
function SpellColorsPage.CreateSectionDisabledDelegate(configPath, ownerModuleName)
    local isDisabled = ns.OptionUtil.GetIsDisabledDelegate(configPath)

    return function()
        local ownerModule = ns.Addon and ns.Addon[ownerModuleName] or nil
        if not ownerModule then
            return true
        end

        return isDisabled()
    end
end

---@param subcatName string
---@return table
function SpellColorsPage.CreatePage(subcatName)
    if not pageSpec then
        local function refreshRegisteredPage()
            if registeredPage then
                registeredPage:Refresh()
            end
        end

        pageSpec = {
            key = "spellColors",
            name = subcatName,
            rows = {},
            onDefault = function()
                if not canResetAnySpellColorSection() then
                    return
                end

                resetAllSpellColors(refreshRegisteredPage)
            end,
            onDefaultEnabled = function()
                return canResetAnySpellColorSection()
            end,
        }
        pageSpec.SetRegisteredPage = SpellColorsPage.SetRegisteredPage
        SpellColorsPage._pageSpec = pageSpec
    end

    pageSpec.name = subcatName
    pageSpec.rows = buildPageRows()
    return pageSpec
end

SpellColorsPage._BuildSpellColorRows = buildSpellColorRows
SpellColorsPage._CollectIncompleteSpellColorRows = collectIncompleteSpellColorRows
SpellColorsPage._GetSpellColorsPageState = getSpellColorsPageState
SpellColorsPage._BuildSpellColorKeyTooltipLines = buildSpellColorKeyTooltipLines
