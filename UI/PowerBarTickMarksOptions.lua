-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, ns = ...
local C = ECM.Constants

local BASE_DESC_TEXT = "Customize tick marks for the power bar. Marks are saved per class and specialization."

local function getTicksConfig()
    local powerBar = ns.Addon.db.profile.powerBar
    if powerBar and powerBar.ticks then return powerBar.ticks end
    if not ns.Addon.db.profile.powerBar then ns.Addon.db.profile.powerBar = {} end

    ns.Addon.db.profile.powerBar.ticks = {
        mappings = {},
        defaultColor = C.DEFAULT_POWERBAR_TICK_COLOR,
        defaultWidth = 1,
    }
    return ns.Addon.db.profile.powerBar.ticks
end

local store = {}

function store.GetCurrentTicks()
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then return {} end
    local ticksCfg = ns.Addon.db.profile.powerBar and ns.Addon.db.profile.powerBar.ticks
    local mappings = ticksCfg and ticksCfg.mappings
    local classMappings = mappings and mappings[classID]
    return classMappings and classMappings[specIndex] or {}
end

function store.SetCurrentTicks(ticks)
    local classID, specIndex = ECM.OptionUtil.GetCurrentClassSpec()
    if not classID or not specIndex then return end
    local ticksCfg = getTicksConfig()
    if not ticksCfg.mappings[classID] then ticksCfg.mappings[classID] = {} end
    ticksCfg.mappings[classID][specIndex] = ticks
end

function store.AddTick(value, color, width)
    local ticks = store.GetCurrentTicks()
    local ticksCfg = getTicksConfig()
    ticks[#ticks + 1] = {
        value = value,
        color = color or ECM.CloneValue(ticksCfg.defaultColor),
        width = width or ticksCfg.defaultWidth,
    }
    store.SetCurrentTicks(ticks)
end

function store.RemoveTick(index)
    local ticks = store.GetCurrentTicks()
    if not ticks[index] then return end
    table.remove(ticks, index)
    store.SetCurrentTicks(ticks)
end

function store.UpdateTick(index, field, value)
    local ticks = store.GetCurrentTicks()
    if not ticks[index] then return end
    ticks[index][field] = value
    store.SetCurrentTicks(ticks)
end

function store.GetDefaultColor()
    return getTicksConfig().defaultColor
end

function store.SetDefaultColor(color)
    getTicksConfig().defaultColor = color
end

function store.GetDefaultWidth()
    return getTicksConfig().defaultWidth
end

function store.SetDefaultWidth(width)
    getTicksConfig().defaultWidth = width
end

ECM.PowerBarTickMarksStore = store

StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"] = {
    text = "Are you sure you want to remove all tick marks for this spec?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function roundToStep(value)
    return math.floor(value + 0.5)
end

local function createTickRowWidgets(rowFrame, SB)
    rowFrame:SetHeight(34)

    local highlight = rowFrame:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
    highlight:Hide()
    rowFrame._highlight = highlight

    rowFrame:EnableMouse(true)
    rowFrame:SetScript("OnEnter", function(self) self._highlight:Show() end)
    rowFrame:SetScript("OnLeave", function(self) self._highlight:Hide() end)

    local label = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0)
    label:SetWidth(70)
    label:SetJustifyH("LEFT")
    rowFrame._label = label

    local valueSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
    valueSlider:SetPoint("LEFT", label, "RIGHT", 8, 0)
    valueSlider:SetWidth(150)
    valueSlider:SetMinMaxValues(1, 200)
    valueSlider:SetValueStep(1)
    valueSlider:SetObeyStepOnDrag(true)
    rowFrame._valueSlider = valueSlider

    local valueText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", valueSlider, "RIGHT", 6, 0)
    valueText:SetWidth(28)
    valueText:SetJustifyH("LEFT")
    rowFrame._valueText = valueText

    local widthSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
    widthSlider:SetPoint("LEFT", valueText, "RIGHT", 12, 0)
    widthSlider:SetWidth(90)
    widthSlider:SetMinMaxValues(1, 5)
    widthSlider:SetValueStep(1)
    widthSlider:SetObeyStepOnDrag(true)
    rowFrame._widthSlider = widthSlider

    local widthText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    widthText:SetPoint("LEFT", widthSlider, "RIGHT", 6, 0)
    widthText:SetWidth(18)
    widthText:SetJustifyH("LEFT")
    rowFrame._widthText = widthText

    local swatch = SB.CreateColorSwatch(rowFrame)
    swatch:SetPoint("LEFT", widthText, "RIGHT", 10, 0)
    rowFrame._swatch = swatch

    local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
    removeBtn:SetSize(70, 22)
    removeBtn:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    removeBtn:SetText("Remove")
    rowFrame._removeBtn = removeBtn

    local function bindSlider(slider, textLabel, storeField)
        slider:SetScript("OnValueChanged", function(_, val)
            local rounded = roundToStep(val)
            textLabel:SetText(tostring(rounded))
            if rowFrame._isRefreshing then return end
            if rounded ~= val then
                rowFrame._isRefreshing = true
                slider:SetValue(rounded)
                rowFrame._isRefreshing = false
                return
            end
            store.UpdateTick(rowFrame._rowIndex, storeField, rounded)
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end

    bindSlider(valueSlider, valueText, "value")
    bindSlider(widthSlider, widthText, "width")
end

local function createTickMarksCanvas(SB, subcatName)
    local layout = SB.CreateCanvasLayout(subcatName)
    local frame = layout.frame

    local function clearAllTicks()
        store.SetCurrentTicks({})
        frame:RefreshTicks()
        ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
    end

    local headerRow = layout:AddHeader(subcatName)
    local defaultsBtn = headerRow._defaultsButton
    defaultsBtn:SetText(SETTINGS_DEFAULTS)
    defaultsBtn:SetScript("OnClick", function()
        StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"].OnAccept = clearAllTicks
        StaticPopup_Show("ECM_CONFIRM_CLEAR_TICKS")
    end)

    layout:AddSpacer(2)

    layout:AddDescription(BASE_DESC_TEXT, "GameFontHighlight")._text:SetWordWrap(true)

    local infoRow = layout:AddDescription("")
    local infoText = infoRow._text
    infoText:SetWordWrap(true)

    local _, defaultColorSwatch = layout:AddColorSwatch("Default color")
    defaultColorSwatch:SetScript("OnClick", function()
        local c = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        ECM.OptionUtil.OpenColorPicker(c, true, function(color)
            store.SetDefaultColor(color)
            defaultColorSwatch:SetColorRGB(color.r, color.g, color.b)
        end)
    end)

    local _, defaultWidthSlider, defaultWidthText = layout:AddSlider("Default width", 1, 5, 1)
    defaultWidthSlider:SetScript("OnValueChanged", function(_, value)
        local rounded = roundToStep(value)
        defaultWidthText:SetText(tostring(rounded))
        store.SetDefaultWidth(rounded)
    end)

    local _, addBtn = layout:AddButton("Add Tick Mark", "Add")
    addBtn:SetScript("OnClick", function()
        store.AddTick(50, nil, nil)
        frame:RefreshTicks()
    end)

    local scrollBox, _, view = layout:AddScrollList(34)

    view:SetElementInitializer("Frame", function(rowFrame, data)
        if not rowFrame._initialized then
            createTickRowWidgets(rowFrame, SB)
            rowFrame._initialized = true
        end

        local index = data.index
        rowFrame._rowIndex = index
        rowFrame._highlight:Hide()
        rowFrame._label:SetText("Tick " .. index)

        local tickValue = data.tick.value or 50
        local tickWidth = data.tick.width or store.GetDefaultWidth()

        rowFrame._isRefreshing = true
        rowFrame._valueSlider:SetValue(tickValue)
        rowFrame._valueText:SetText(tostring(roundToStep(tickValue)))
        rowFrame._widthSlider:SetValue(tickWidth)
        rowFrame._widthText:SetText(tostring(roundToStep(tickWidth)))
        rowFrame._isRefreshing = false

        local tc = data.tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        rowFrame._swatch:SetColorRGB(tc.r, tc.g, tc.b)

        rowFrame._swatch:SetScript("OnClick", function()
            local current = data.tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
            ECM.OptionUtil.OpenColorPicker(current, true, function(color)
                store.UpdateTick(rowFrame._rowIndex, "color", color)
                rowFrame._swatch:SetColorRGB(color.r, color.g, color.b)
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end)
        end)

        rowFrame._removeBtn:SetScript("OnClick", function()
            store.RemoveTick(rowFrame._rowIndex)
            frame:RefreshTicks()
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    function frame:RefreshTicks()
        local ticks = store.GetCurrentTicks()

        dataProvider:Flush()
        for i, tick in ipairs(ticks) do
            dataProvider:Insert({ index = i, tick = tick })
        end

        local _, _, localisedClassName, specName, className = ECM.OptionUtil.GetCurrentClassSpec()
        local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
        local classSpecLabel = "|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown")
        local count = #ticks
        if count == 0 then
            infoText:SetText(classSpecLabel .. " - no tick marks configured.")
        else
            infoText:SetText(string.format("%s - %d tick mark(s) configured.", classSpecLabel, count))
        end

        defaultsBtn:SetEnabled(count > 0)

        local dc = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        defaultColorSwatch:SetColorRGB(dc.r, dc.g, dc.b)

        local dw = store.GetDefaultWidth() or 1
        defaultWidthSlider:SetValue(dw)
        defaultWidthText:SetText(tostring(roundToStep(dw)))
    end

    frame.OnDefault = clearAllTicks

    frame:SetScript("OnShow", function(self)
        self:RefreshTicks()
    end)
end

ECM.PowerBarTickMarksOptions = {
    RegisterSettings = function(SB)
        createTickMarksCanvas(SB, "Tick Marks")
    end,
}
