-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ns.Constants
local L = ns.L

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

    -- Header — uses SettingsListTemplate's built-in Title, divider, and DefaultsButton
    local headerRow = layout:AddHeader(subcatName)
    local defaultsBtn = headerRow._defaultsButton
    defaultsBtn:SetText(SETTINGS_DEFAULTS)
    defaultsBtn:SetScript("OnClick", function()
        if ns.Addon.BuffBars:IsEditLocked() then
            return
        end
        StaticPopupDialogs["ECM_CONFIRM_RESET_SPELL_COLORS"].OnAccept = resetAllSpellColors
        StaticPopup_Show("ECM_CONFIRM_RESET_SPELL_COLORS")
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

    view:SetElementInitializer("SettingsColorSwatchControlTemplate", function(control, data)
        -- Position label (matches SettingsListElementMixin:Init positioning)
        if not control._ecmPositioned then
            control.Text:SetFontObject(GameFontNormal)
            control.Text:ClearAllPoints()
            control.Text:SetPoint("LEFT", 37, 0)
            control.Text:SetPoint("RIGHT", control, "CENTER", -85, 0)
            control._ecmPositioned = true
        end

        local colorKey = data.key.primaryKey
        local name = type(colorKey) == "string" and colorKey or ("Bar (" .. colorKey .. ")")
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
BuffBarsOptions._IsSpellColorsReloadRestricted = isSpellColorsReloadRestricted
BuffBarsOptions._GetSecretNameFooterState = getSecretNameFooterState

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
