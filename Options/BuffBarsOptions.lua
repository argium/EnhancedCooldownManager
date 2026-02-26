-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants

local unlabeledBarsPresent = false

local function IsEditLocked()
    local locked, _ = ECM.BuffBars:IsEditLocked()
    return locked
end

local function EditLockedReason()
    local _, reason = ECM.BuffBars:IsEditLocked()
    return reason
end

--- Generates the merged list of spell color rows from active bars and saved entries.
---@param activeBars ECM_SpellColorKey[]|nil
---@param savedEntries { key: ECM_SpellColorKey }[]|nil
---@return { key: ECM_SpellColorKey, textureFileID: number|nil }[]
local function BuildSpellColorRows(activeBars, savedEntries)
    local rows = {}

    local function AddDiscoveredKey(key)
        local normalized = ECM.SpellColors.NormalizeKey(key)
        if not normalized then
            return
        end

        for _, row in ipairs(rows) do
            if row.key:Matches(normalized) then
                row.key = row.key:Merge(normalized) or row.key
                row.textureFileID = row.key.textureFileID or row.textureFileID
                return
            end
        end

        rows[#rows + 1] = {
            key = normalized,
            textureFileID = normalized.textureFileID,
        }
    end

    if type(activeBars) == "table" then
        for _, key in ipairs(activeBars) do
            AddDiscoveredKey(key)
        end
    end

    if type(savedEntries) == "table" then
        for _, entry in ipairs(savedEntries) do
            AddDiscoveredKey(type(entry) == "table" and entry.key or nil)
        end
    end

    return rows
end

--------------------------------------------------------------------------------
-- Canvas Frame for Spell Colors
--------------------------------------------------------------------------------

local function CreateSpellColorCanvas()
    local frame = CreateFrame("Frame", "ECM_BuffBarsColorsCanvas", UIParent)
    frame:SetSize(600, 400)
    frame:Hide()

    -- Warning labels
    local combatWarning = frame:CreateFontString(nil, "OVERLAY", "GameFontRed")
    combatWarning:SetPoint("TOPLEFT", 10, -10)
    combatWarning:SetText("These settings cannot be changed while in combat lockdown.")
    combatWarning:Hide()

    local secretsWarning = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secretsWarning:SetPoint("TOPLEFT", 10, -10)
    secretsWarning:SetText("|cffFFDD3CSpell names are currently secret. Changes are blocked until you reload your UI out of combat.|r")
    secretsWarning:Hide()

    local unlabeledWarning = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    unlabeledWarning:SetPoint("TOPLEFT", 10, -30)
    unlabeledWarning:SetText("|cffFFDD3CSome spell names were secret and are displayed as a generic \"Bar\".|r")
    unlabeledWarning:Hide()

    -- Current spec label
    local specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    specLabel:SetPoint("TOPLEFT", 10, -55)

    -- ScrollBox for spell list
    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -80)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, 10)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(24)
    view:SetElementInitializer("Frame", function(rowFrame, data)
        if not rowFrame._initialized then
            rowFrame:SetSize(scrollBox:GetWidth(), 24)

            local icon = rowFrame:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 2, 0)
            rowFrame._icon = icon

            local nameLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", icon, "RIGHT", 5, 0)
            nameLabel:SetWidth(300)
            nameLabel:SetJustifyH("LEFT")
            rowFrame._nameLabel = nameLabel

            local swatch = CreateFrame("Button", nil, rowFrame)
            swatch:SetSize(20, 20)
            swatch:SetPoint("LEFT", nameLabel, "RIGHT", 5, 0)
            local swatchTex = swatch:CreateTexture(nil, "BACKGROUND")
            swatchTex:SetAllPoints()
            swatchTex:SetColorTexture(1, 1, 1)
            swatch._tex = swatchTex
            rowFrame._swatch = swatch

            local resetBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            resetBtn:SetSize(20, 20)
            resetBtn:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
            resetBtn:SetText("X")
            rowFrame._resetBtn = resetBtn

            rowFrame._initialized = true
        end

        -- Set icon
        if data.textureFileID then
            rowFrame._icon:SetTexture(data.textureFileID)
            rowFrame._icon:Show()
        else
            rowFrame._icon:Hide()
        end

        -- Set name
        local colorKey = data.key.primaryKey
        local label = type(colorKey) == "string" and colorKey or ("Bar (" .. colorKey .. ")")
        rowFrame._nameLabel:SetText(label)

        -- Track unlabeled bars
        if type(colorKey) == "string" and (issecretvalue(colorKey) or colorKey == "") then
            unlabeledBarsPresent = true
        end

        -- Set color swatch
        local function UpdateSwatch()
            local c = ECM.SpellColors.GetColorByKey(data.key)
            if not c then c = ECM.SpellColors.GetDefaultColor() end
            rowFrame._swatch._tex:SetColorTexture(c.r, c.g, c.b)
        end
        UpdateSwatch()

        rowFrame._swatch:SetScript("OnClick", function()
            if IsEditLocked() then return end
            local c = ECM.SpellColors.GetColorByKey(data.key) or ECM.SpellColors.GetDefaultColor()
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b,
                hasOpacity = false,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    ECM.SpellColors.SetColorByKey(data.key, { r = r, g = g, b = b, a = 1 })
                    UpdateSwatch()
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
                cancelFunc = function(prev)
                    ECM.SpellColors.SetColorByKey(data.key, { r = prev.r, g = prev.g, b = prev.b, a = 1 })
                    UpdateSwatch()
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
            })
        end)

        -- Reset button
        local hasCustomColor = ECM.SpellColors.GetColorByKey(data.key) ~= nil
        if hasCustomColor then
            rowFrame._resetBtn:Show()
        else
            rowFrame._resetBtn:Hide()
        end
        rowFrame._resetBtn:SetScript("OnClick", function()
            ECM.SpellColors.ResetColorByKey(data.key)
            UpdateSwatch()
            rowFrame._resetBtn:Hide()
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    frame._scrollBox = scrollBox
    frame._dataProvider = dataProvider
    frame._specLabel = specLabel
    frame._combatWarning = combatWarning
    frame._secretsWarning = secretsWarning
    frame._unlabeledWarning = unlabeledWarning

    function frame:RefreshSpellList()
        unlabeledBarsPresent = false
        local rows = BuildSpellColorRows(
            ECM.BuffBars:GetActiveSpellData(),
            ECM.SpellColors.GetAllColorEntries()
        )

        dataProvider:Flush()
        for _, row in ipairs(rows) do
            dataProvider:Insert(row)
        end

        -- Update warnings
        local locked = IsEditLocked()
        local reason = EditLockedReason()
        combatWarning:SetShown(locked and reason == "combat")
        secretsWarning:SetShown(locked and reason == "secrets")
        unlabeledWarning:SetShown(unlabeledBarsPresent)

        -- Update spec label
        local _, _, localisedClassName, specName, className = ECM.OptionUtil.GetCurrentClassSpec()
        local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
        specLabel:SetText("|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown"))
    end

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
BuffBarsOptions._BuildSpellColorRows = BuildSpellColorRows

local function isDisabled()
    return not ECM.OptionUtil.GetNestedValue(mod.db.profile, "buffBars.enabled")
end

function BuffBarsOptions.RegisterSettings(SB)
    SB.RegisterFromTable({
        name = "Aura Bars",
        path = "buffBars",
        args = {
            enabled = {
                type = "toggle",
                path = "enabled",
                name = "Enable aura bars",
                desc = "Styles and repositions Blizzard's aura duration bars that are part of the Cooldown Manager.",
                order = 0,
                onSet = function(value, setting)
                    if value then
                        ECM.OptionUtil.SetModuleEnabled("BuffBars", true)
                    else
                        setting:SetValue(true)
                        mod:ConfirmReloadUI(
                            "Disabling aura bars requires a UI reload. Reload now?",
                            function()
                                ECM.OptionUtil.SetModuleEnabled("BuffBars", false)
                            end
                        )
                    end
                end,
            },

            -- Layout
            layoutHeader      = { type = "header", name = "Layout", disabled = isDisabled, order = 10 },
            positioning       = { type = "positioning", disabled = isDisabled, includeOffsetX = false, order = 11 },
            freeGrowDirection = {
                type = "select",
                path = "freeGrowDirection",
                name = "Free Grow Direction",
                desc = "Choose whether aura bars stack downward or upward in free positioning mode.",
                values = {
                    [C.GROW_DIRECTION_DOWN] = "Down",
                    [C.GROW_DIRECTION_UP] = "Up",
                },
                disabled = isDisabled,
                getTransform = function(value) return value or C.GROW_DIRECTION_DOWN end,
                parent = "positioning",
                parentCheck = function()
                    return ECM.OptionUtil.IsAnchorModeFree(
                        ECM.OptionUtil.GetNestedValue(mod.db.profile, "buffBars"))
                end,
                order = 12,
            },

            -- Appearance
            appearanceHeader  = { type = "header", name = "Appearance", disabled = isDisabled, order = 20 },
            showIcon          = { type = "toggle", path = "showIcon", name = "Show icon", disabled = isDisabled, order = 21 },
            showSpellName     = { type = "toggle", path = "showSpellName", name = "Show spell name", disabled = isDisabled, order = 22 },
            showDuration      = { type = "toggle", path = "showDuration", name = "Show remaining duration", disabled = isDisabled, order = 23 },
            height            = {
                type = "range",
                path = "height",
                name = "Height Override",
                desc = "Override the default bar height. Set to 0 to use the global default.",
                min = 0, max = 40, step = 1,
                disabled = isDisabled,
                getTransform = function(value) return value or 0 end,
                setTransform = function(value) return value > 0 and value or nil end,
                order = 24,
            },
            verticalSpacing   = {
                type = "range",
                path = "verticalSpacing",
                name = "Vertical Spacing",
                desc = "Vertical gap between aura bars. Set to 0 for no spacing.",
                min = 0, max = 20, step = 1,
                disabled = isDisabled,
                getTransform = function(value) return value or 0 end,
                order = 25,
            },
            fontOverride      = { type = "fontOverride", disabled = isDisabled, order = 26 },
        },
    })

    -- Spell Colors (separate subcategory)
    local colorsFrame = CreateSpellColorCanvas()

    SB.RegisterFromTable({
        name = "    Spell Colors",
        path = "buffBars",
        args = {
            defaultColor = {
                type = "color",
                path = "colors.defaultColor",
                name = "Default color",
                desc = "The fallback color used for aura bars that do not have a custom color assigned.",
                disabled = isDisabled,
                order = 10,
            },
            refresh = {
                type = "execute",
                name = "Refresh spell list",
                buttonText = "Refresh",
                desc = "Re-scan active aura bars and reconcile with saved spell color entries.",
                onClick = function()
                    if IsEditLocked() then return end
                    local activeKeys = ECM.BuffBars:GetActiveSpellData()
                    ECM.SpellColors.ReconcileAllKeys(activeKeys)
                    colorsFrame:RefreshSpellList()
                end,
                order = 20,
            },
            colors = {
                type = "canvas",
                canvas = colorsFrame,
                height = 400,
                order = 30,
            },
        },
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "BuffBars", BuffBarsOptions)
