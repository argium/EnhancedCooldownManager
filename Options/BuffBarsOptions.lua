-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local mod = ns.Addon
local C = ECM.Constants

local function IsEditLocked()
    return ECM.BuffBars:IsEditLocked()
end

--- Generates the merged list of spell color rows from spell color entries.
---@param entries { key: ECM_SpellColorKey }[]|nil
---@return { key: ECM_SpellColorKey, textureFileID: number|nil }[]
local function BuildSpellColorRows(entries)
    local rows = {}

    if type(entries) ~= "table" then
        return rows
    end

    for _, entry in ipairs(entries) do
        local normalized = ECM.SpellColors.NormalizeKey(type(entry) == "table" and entry.key or nil)
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
local function HasUnlabeledBars(rows)
    for _, row in ipairs(rows) do
        local key = row.key.primaryKey
        if type(key) == "string" and (issecretvalue(key) or key == "") then
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Canvas Frame for Spell Colors
--------------------------------------------------------------------------------

local function CreateSpellColorCanvas(SB, subcatName)
    local layout = SB.CreateCanvasLayout(subcatName)
    local frame = layout.frame

    local warningRow = layout:AddDescription("")
    local warningText = warningRow._text
    warningText:SetWordWrap(true)

    local specRow = layout:AddDescription("")
    local specLabel = specRow._text
    specLabel:SetFontObject(GameFontNormalLarge)

    local scrollBox, _, view = layout:AddScrollList(24)

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

            local swatch = SB.CreateColorSwatch(rowFrame, 20)
            swatch:SetPoint("LEFT", nameLabel, "RIGHT", 5, 0)
            rowFrame._swatch = swatch

            local resetBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            resetBtn:SetSize(20, 20)
            resetBtn:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
            resetBtn:SetText("X")
            rowFrame._resetBtn = resetBtn

            function rowFrame:UpdateSwatch()
                local c = ECM.SpellColors.GetColorByKey(self._data.key)
                if not c then c = ECM.SpellColors.GetDefaultColor() end
                self._swatch._tex:SetColorTexture(c.r, c.g, c.b)
            end

            rowFrame._initialized = true
        end

        rowFrame._data = data

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

        rowFrame:UpdateSwatch()

        rowFrame._swatch:SetScript("OnClick", function()
            if IsEditLocked() then return end
            local c = ECM.SpellColors.GetColorByKey(data.key) or ECM.SpellColors.GetDefaultColor()
            ECM.OptionUtil.OpenColorPicker(c, false, function(color)
                ECM.SpellColors.SetColorByKey(data.key, color)
                rowFrame:UpdateSwatch()
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end)
        end)

        -- Reset button
        rowFrame._resetBtn:SetShown(ECM.SpellColors.GetColorByKey(data.key) ~= nil)
        rowFrame._resetBtn:SetScript("OnClick", function()
            ECM.SpellColors.ResetColorByKey(data.key)
            rowFrame:UpdateSwatch()
            rowFrame._resetBtn:Hide()
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    function frame:RefreshSpellList()
        local rows = BuildSpellColorRows(
            ECM.SpellColors.GetAllColorEntries()
        )

        dataProvider:Flush()
        for _, row in ipairs(rows) do
            dataProvider:Insert(row)
        end

        -- Build warning text
        local parts = {}
        local locked, reason = IsEditLocked()
        if locked and reason == "combat" then
            parts[#parts + 1] = "|cffFF0000These settings cannot be changed while in combat lockdown.|r"
        elseif locked and reason == "secrets" then
            parts[#parts + 1] = "|cffFFDD3CSpell names are currently secret. Changes are blocked until you reload your UI out of combat.|r"
        end
        if HasUnlabeledBars(rows) then
            parts[#parts + 1] = "|cffFFDD3CSome spell names were secret and are displayed as a generic \"Bar\".|r"
        end
        warningText:SetText(table.concat(parts, "\n"))

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
BuffBarsOptions._HasUnlabeledBars = HasUnlabeledBars

local isDisabled = ECM.OptionUtil.GetIsDisabledDelegate("buffBars")

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

    -- Spell Colors (canvas subcategory, opened via button)
    local SPELL_COLORS_SUBCAT = "Spell Colors"
    local colorsFrame = CreateSpellColorCanvas(SB, SPELL_COLORS_SUBCAT)

    SB.Header("Spell Colors")
    SB.PathControl({
        type = "color",
        path = "buffBars.colors.defaultColor",
        name = "Default color",
        tooltip = "The fallback color used for aura bars that do not have a custom color assigned.",
        disabled = isDisabled,
    })
    SB.Button({
        name = "Refresh spell list",
        buttonText = "Refresh",
        tooltip = "Reconcile discovered aura bars with saved spell color entries and refresh the list.",
        onClick = function()
            if IsEditLocked() then return end
            ECM.SpellColors.ReconcileDiscoveredKeys()
            colorsFrame:RefreshSpellList()
        end,
    })
    SB.Button({
        name = "Configure Spell Colors",
        buttonText = "Open",
        onClick = function()
            local catID = SB.GetSubcategoryID(SPELL_COLORS_SUBCAT)
            if catID then
                Settings.OpenToCategory(catID)
            end
        end,
    })
end

ECM.SettingsBuilder.RegisterSection(ns, "BuffBars", BuffBarsOptions)
