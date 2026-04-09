-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

local REMOVE_STALE_SPELL_COLORS_POPUP = "ECM_CONFIRM_REMOVE_STALE_SPELL_COLORS"
local SPELL_COLORS_HEADER_BUTTON_WIDTH = 100
local SPELL_COLORS_HEADER_BUTTON_HEIGHT = 22
local SPELL_COLORS_HEADER_BUTTON_SPACING = 8

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

---@param owner Frame
---@param text string
local function setSimpleTooltip(owner, text)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.ClearLines then
            GameTooltip:ClearLines()
        end
        GameTooltip:SetText(text, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function()
        GameTooltip_Hide()
    end)
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
    GameTooltip:SetText(L["SPELL_COLORS_KEYS_TOOLTIP_TITLE"], 1, 1, 1)

    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line, nil, nil, nil, true)
    end

    GameTooltip:Show()
end

--------------------------------------------------------------------------------
-- Canvas Frame for Spell Colors
--------------------------------------------------------------------------------

StaticPopupDialogs["ECM_CONFIRM_RESET_SPELL_COLORS"] = ns.OptionUtil.MakeConfirmDialog(L["SPELL_COLORS_RESET_CONFIRM"])

local function createSpellColorCanvas(SB, subcatName)
    local layout = SB.CreateCanvasLayout(subcatName)
    local frame = layout.frame

    local function resetAllSpellColors()
        ns.SpellColors.ClearCurrentSpecColors()
        frame:RefreshSpellList()
        ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
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

                frame:RefreshSpellList()
                if #removedKeys > 0 then
                    ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
                end
            end
        )
    end

    -- Header — uses SettingsListTemplate's built-in Title, divider, and DefaultsButton
    local headerRow = layout:AddHeader(subcatName)
    local defaultsBtn = headerRow._defaultsButton
    local reconcileBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")
    local removeStaleBtn = CreateFrame("Button", nil, headerRow, "UIPanelButtonTemplate")

    reconcileBtn:SetSize(SPELL_COLORS_HEADER_BUTTON_WIDTH, SPELL_COLORS_HEADER_BUTTON_HEIGHT)
    reconcileBtn:SetPoint("RIGHT", defaultsBtn, "LEFT", -SPELL_COLORS_HEADER_BUTTON_SPACING, 0)
    reconcileBtn:SetText(L["SPELL_COLORS_RECONCILE_BUTTON"])
    reconcileBtn:SetScript("OnClick", function()
        if not reconcileBtn:IsEnabled() then
            return
        end
        reconcileSpellColors()
    end)

    removeStaleBtn:SetSize(SPELL_COLORS_HEADER_BUTTON_WIDTH, SPELL_COLORS_HEADER_BUTTON_HEIGHT)
    removeStaleBtn:SetPoint("RIGHT", reconcileBtn, "LEFT", -SPELL_COLORS_HEADER_BUTTON_SPACING, 0)
    removeStaleBtn:SetText(L["SPELL_COLORS_REMOVE_STALE_BUTTON"])
    removeStaleBtn:SetScript("OnClick", function()
        if not removeStaleBtn:IsEnabled() then
            return
        end
        removeStaleSpellColors()
    end)
    setSimpleTooltip(removeStaleBtn, L["SPELL_COLORS_REMOVE_STALE_TOOLTIP"])

    defaultsBtn:SetText(SETTINGS_DEFAULTS)
    defaultsBtn:SetScript("OnClick", function()
        if ns.Addon.BuffBars:IsEditLocked() then
            return
        end
        StaticPopup_Show("ECM_CONFIRM_RESET_SPELL_COLORS", nil, nil, {
            onAccept = resetAllSpellColors,
        })
    end)

    layout:AddSpacer(2)

    local descRow = layout:AddDescription(L["SPELL_COLORS_DESC"], "GameFontHighlight")
    descRow._text:SetWordWrap(true)

    local warningRow = layout:AddDescription("")
    local warningText = warningRow._text
    warningText:SetWordWrap(true)

    -- Default color swatch (above the per-spell list)
    local defaultColorRow, defaultColorSwatch = layout:AddColorSwatch("Default color")
    -- Reposition the default color swatch to align with the scroll list rows below,
    -- which are indented by the canvas label margin (37px from canvas edge).
    defaultColorRow._label:ClearAllPoints()
    defaultColorRow._label:SetPoint("LEFT", 74, 0)
    defaultColorRow._label:SetPoint("RIGHT", defaultColorRow, "CENTER", -85, 0)
    defaultColorSwatch:ClearAllPoints()
    defaultColorSwatch:SetPoint("LEFT", defaultColorRow, "CENTER", -70, 0)
    defaultColorSwatch:SetScript("OnClick", function()
        if ns.Addon.BuffBars:IsEditLocked() then
            return
        end
        local c = ns.SpellColors.GetDefaultColor()
        ns.OptionUtil.OpenColorPicker(c, false, function(color)
            ns.SpellColors.SetDefaultColor(color)
            defaultColorSwatch:SetColorRGB(color.r, color.g, color.b)
            ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    -- Scroll list using Blizzard's SettingsColorSwatchControlTemplate per element
    local scrollTopY = layout.yPos
    local scrollBox, scrollBar, view = layout:AddScrollList(C.SCROLL_ROW_HEIGHT_COMPACT)

    scrollBox:ClearAllPoints()
    scrollBox:SetPoint("TOPLEFT", 37, scrollTopY)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, C.SPELL_COLORS_SCROLL_BOTTOM_OFFSET_WITH_SECRET_NAMES)
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)

    local secretNameDescRow = layout:_CreateRow(C.SPELL_COLORS_SECRET_NAMES_DESC_HEIGHT)
    local secretNameDescText = secretNameDescRow:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    secretNameDescText:SetPoint("TOPLEFT", 37, 0)
    secretNameDescText:SetPoint("TOPRIGHT", secretNameDescRow, "TOPRIGHT", -10, 0)
    secretNameDescText:SetJustifyH("LEFT")
    secretNameDescText:SetWordWrap(true)
    secretNameDescText:SetText(L["SPELL_COLORS_SECRET_NAMES_DESC"])
    secretNameDescRow._text = secretNameDescText
    secretNameDescRow:ClearAllPoints()
    secretNameDescRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, C.SPELL_COLORS_SECRET_NAMES_DESC_BOTTOM_OFFSET)
    secretNameDescRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, C.SPELL_COLORS_SECRET_NAMES_DESC_BOTTOM_OFFSET)
    secretNameDescRow:Hide()

    local secretNameButtonRow, secretNameReloadButton = layout:AddButton("", L["SPELL_COLORS_RELOAD_BUTTON"])
    secretNameButtonRow._label:SetText("")
    secretNameButtonRow:ClearAllPoints()
    secretNameButtonRow:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, C.SPELL_COLORS_SECRET_NAMES_BUTTON_BOTTOM_OFFSET)
    secretNameButtonRow:SetPoint(
        "BOTTOMRIGHT",
        frame,
        "BOTTOMRIGHT",
        0,
        C.SPELL_COLORS_SECRET_NAMES_BUTTON_BOTTOM_OFFSET
    )
    secretNameButtonRow:Hide()
    secretNameReloadButton:SetScript("OnClick", function()
        ns.Addon:ConfirmReloadUI(L["SPELL_COLORS_SECRET_NAMES_DESC"])
    end)

    frame._secretNameDescRow = secretNameDescRow
    frame._secretNameReloadButtonRow = secretNameButtonRow
    frame._secretNameReloadButton = secretNameReloadButton
    frame._reconcileButton = reconcileBtn
    frame._removeStaleButton = removeStaleBtn
    frame._spellColorListView = view

    view:SetElementInitializer("SettingsColorSwatchControlTemplate", function(control, data)
        -- Position label (matches SettingsListElementMixin:Init positioning)
        if not control._ecmPositioned then
            control.Text:SetFontObject(GameFontNormal)
            control.Text:ClearAllPoints()
            control.Text:SetPoint("LEFT", 37, 0)
            control.Text:SetPoint("RIGHT", control, "CENTER", -85, 0)
            control._ecmPositioned = true
        end

        if not control._ecmSpellColorTooltipHooked then
            if control.EnableMouse then
                control:EnableMouse(true)
            end
            control:HookScript("OnEnter", function(self)
                maybeShowSpellColorKeyTooltip(self, self._ecmSpellColorRowData)
            end)
            control:HookScript("OnLeave", function()
                GameTooltip_Hide()
            end)
            control._ecmSpellColorTooltipHooked = true
        end

        control._ecmSpellColorRowData = data

        local name = getSpellColorRowName(data.key)
        local label = data.textureFileID and ("|T" .. data.textureFileID .. ":14:14|t  " .. name) or name
        control.Text:SetText(label)

        local c = ns.SpellColors.GetColorByKey(data.key) or ns.SpellColors.GetDefaultColor()
        control.ColorSwatch:SetColorRGB(c.r, c.g, c.b)

        control.ColorSwatch:SetScript("OnClick", function()
            if ns.Addon.BuffBars:IsEditLocked() then
                return
            end
            local current = ns.SpellColors.GetColorByKey(data.key) or ns.SpellColors.GetDefaultColor()
            ns.OptionUtil.OpenColorPicker(current, false, function(color)
                ns.SpellColors.SetColorByKey(data.key, color)
                control.ColorSwatch:SetColorRGB(color.r, color.g, color.b)
                ns.Runtime.ScheduleLayoutUpdate(0, "OptionsChanged")
            end)
        end)
    end)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    function frame:RefreshSpellList()
        local rows = buildSpellColorRows(ns.SpellColors.GetAllColorEntries())
        local secretNameFooterState = getSecretNameFooterState(rows)
        local hasIncompleteRows = hasRowsNeedingReconcile(rows)
        local canReconcile = hasIncompleteRows and not isSpellColorsReloadRestricted()
        local canRemoveStale = hasIncompleteRows and not isSpellColorsReloadRestricted()

        dataProvider:Flush()
        for _, row in ipairs(rows) do
            dataProvider:Insert(row)
        end

        -- Build warning text
        local parts = {}
        local locked, reason = ns.Addon.BuffBars:IsEditLocked()
        if locked and reason == "combat" then
            parts[#parts + 1] = L["SPELL_COLORS_COMBAT_WARNING"]
        elseif locked and reason == "secrets" then
            parts[#parts + 1] = L["SPELL_COLORS_SECRETS_WARNING"]
        end
        warningText:SetText(table.concat(parts, "\n"))

        if secretNameFooterState.show then
            secretNameDescRow:Show()
            secretNameButtonRow:Show()
        else
            secretNameDescRow:Hide()
            secretNameButtonRow:Hide()
        end
        secretNameReloadButton:SetEnabled(secretNameFooterState.enabled)

        local dc = ns.SpellColors.GetDefaultColor()
        defaultColorSwatch:SetColorRGB(dc.r, dc.g, dc.b)

        defaultsBtn:SetEnabled(not locked)
        reconcileBtn:SetEnabled(canReconcile)
        removeStaleBtn:SetEnabled(canRemoveStale)
    end

    -- Blizzard's panel calls OnDefault on canvas frames during global defaults
    frame.OnDefault = resetAllSpellColors

    frame:SetScript("OnShow", function(self)
        self:RefreshSpellList()
    end)

    return frame
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

    SB.Button({
        name = L["CONFIGURE_SPELL_COLORS"],
        buttonText = L["OPEN"],
        onClick = function()
            local catID = SB.GetSubcategoryID(L["SPELL_COLORS_SUBCAT"])
            if catID then
                Settings.OpenToCategory(catID)
            end
        end,
    })
end

ns.SettingsBuilder.RegisterSection(ns, "BuffBars", BuffBarsOptions)
