-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _ = ...
local C = ECM.Constants
local BASE_DESC_TEXT = "Tick marks allow you to place markers at specific values on the power bar. These settings are saved per class and specialization"

StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"] = {
    text = "Are you sure you want to remove all tick marks for this spec?",
    button1 = YES,
    button2 = NO,
    OnAccept = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local function GetStore()
    return ECM.PowerBarTickMarksStore
end

local function RoundToStep(value)
    return math.floor(value + 0.5)
end

--- Wires up a slider's OnValueChanged with rounding, refresh guards, and store persistence.
local function BindTickSlider(rowFrame, slider, valueLabel, storeField)
    slider:SetScript("OnValueChanged", function(_, value)
        local rounded = RoundToStep(value)
        valueLabel:SetText(tostring(rounded))
        if rowFrame._isRefreshing then return end
        if rounded ~= value then
            rowFrame._isRefreshing = true
            slider:SetValue(rounded)
            rowFrame._isRefreshing = false
            return
        end
        if rowFrame._rowIndex then
            GetStore().UpdateTick(rowFrame._rowIndex, storeField, rounded)
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end
    end)
end

local function CreateTickMarksCanvas(SB, subcatName)
    local layout = SB.CreateCanvasLayout(subcatName)
    local frame = layout:GetFrame()

    local descRow = layout:AddDescription(BASE_DESC_TEXT .. ".")
    local desc = descRow._text

    local _, defaultColorSwatch = layout:AddColorSwatch("Default color")
    local defaultSwatchTex = defaultColorSwatch._tex

    defaultColorSwatch:SetScript("OnClick", function()
        local store = GetStore()
        local c = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        ECM.OptionUtil.OpenColorPicker(c, true, function(color)
            store.SetDefaultColor(color)
            defaultSwatchTex:SetColorTexture(color.r, color.g, color.b)
        end)
    end)

    local _, defaultWidthSlider, defaultWidthValue = layout:AddSlider("Default width", 1, 5, 1)

    defaultWidthSlider:SetScript("OnValueChanged", function(_, value)
        local rounded = RoundToStep(value)
        defaultWidthValue:SetText(tostring(rounded))
        GetStore().SetDefaultWidth(rounded)
    end)

    local _, addBtn = layout:AddButton("Add Tick Mark", "Add")
    addBtn:SetScript("OnClick", function()
        GetStore().AddTick(50, nil, nil)
        frame:RefreshTicks()
    end)

    local _, clearBtn = layout:AddButton("Clear All Ticks", "Clear")
    clearBtn:SetScript("OnClick", function()
        local dialog = StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"]
        dialog.OnAccept = function()
            GetStore().SetCurrentTicks({})
            frame:RefreshTicks()
        end
        StaticPopup_Show("ECM_CONFIRM_CLEAR_TICKS")
    end)

    local tickCountRow = layout:AddDescription("")
    local tickCountLabel = tickCountRow._text

    local scrollBox, _, view = layout:AddScrollList(34)

    view:SetElementInitializer("Frame", function(rowFrame, data)
        if not rowFrame._initialized then
            rowFrame:SetSize(scrollBox:GetWidth(), 34)

            local hoverHighlight = rowFrame:CreateTexture(nil, "BACKGROUND")
            hoverHighlight:SetAllPoints()
            hoverHighlight:SetColorTexture(1, 1, 1, 0.08)
            hoverHighlight:Hide()
            rowFrame._hoverHighlight = hoverHighlight

            rowFrame:EnableMouse(true)
            rowFrame:SetScript("OnEnter", function(self)
                if self._hasData then
                    self._hoverHighlight:Show()
                end
            end)
            rowFrame:SetScript("OnLeave", function(self)
                self._hoverHighlight:Hide()
            end)

            local headerLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerLabel:SetPoint("LEFT", 10, 0)
            headerLabel:SetWidth(70)
            headerLabel:SetJustifyH("LEFT")
            rowFrame._header = headerLabel

            local valueSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
            valueSlider:SetPoint("LEFT", headerLabel, "RIGHT", 8, 0)
            valueSlider:SetWidth(150)
            valueSlider:SetMinMaxValues(1, 200)
            valueSlider:SetValueStep(1)
            valueSlider:SetObeyStepOnDrag(true)
            rowFrame._valueSlider = valueSlider

            local valueValue = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            valueValue:SetPoint("LEFT", valueSlider, "RIGHT", 6, 0)
            valueValue:SetWidth(28)
            valueValue:SetJustifyH("LEFT")
            rowFrame._valueValue = valueValue

            local widthSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
            widthSlider:SetPoint("LEFT", valueValue, "RIGHT", 12, 0)
            widthSlider:SetWidth(90)
            widthSlider:SetMinMaxValues(1, 5)
            widthSlider:SetValueStep(1)
            widthSlider:SetObeyStepOnDrag(true)
            rowFrame._widthSlider = widthSlider

            local widthValue = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            widthValue:SetPoint("LEFT", widthSlider, "RIGHT", 6, 0)
            widthValue:SetWidth(18)
            widthValue:SetJustifyH("LEFT")
            rowFrame._widthValue = widthValue

            local swatch = SB.CreateColorSwatch(rowFrame, 20)
            swatch:SetPoint("LEFT", widthValue, "RIGHT", 10, 0)
            rowFrame._swatch = swatch

            local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            removeBtn:SetSize(70, 22)
            removeBtn:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
            removeBtn:SetText("Remove")
            rowFrame._removeBtn = removeBtn

            BindTickSlider(rowFrame, valueSlider, valueValue, "value")
            BindTickSlider(rowFrame, widthSlider, widthValue, "width")

            rowFrame._initialized = true
        end

        local store = GetStore()
        local index = data.index
        rowFrame._rowIndex = index
        rowFrame._hasData = true
        rowFrame._hoverHighlight:Hide()
        rowFrame._header:SetText("Tick " .. index)

        local value = data.tick.value or 50
        local width = data.tick.width or store.GetDefaultWidth()

        rowFrame._isRefreshing = true
        rowFrame._valueSlider:SetValue(value)
        rowFrame._valueValue:SetText(tostring(RoundToStep(value)))
        rowFrame._widthSlider:SetValue(width)
        rowFrame._widthValue:SetText(tostring(RoundToStep(width)))
        rowFrame._isRefreshing = false

        local tc = data.tick.color or store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        rowFrame._currentColor = { r = tc.r, g = tc.g, b = tc.b, a = tc.a }
        rowFrame._swatch._tex:SetColorTexture(tc.r, tc.g, tc.b)
        rowFrame._swatch:SetScript("OnClick", function()
            if not rowFrame._rowIndex then return end
            ECM.OptionUtil.OpenColorPicker(rowFrame._currentColor, true, function(color)
                rowFrame._currentColor = color
                store.UpdateTick(rowFrame._rowIndex, "color", color)
                rowFrame._swatch._tex:SetColorTexture(color.r, color.g, color.b)
                ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
            end)
        end)

        rowFrame._removeBtn:SetScript("OnClick", function()
            if not rowFrame._rowIndex then return end
            store.RemoveTick(rowFrame._rowIndex)
            frame:RefreshTicks()
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    local dataProvider = CreateDataProvider()
    scrollBox:SetDataProvider(dataProvider)

    function frame:RefreshTicks()
        local store = GetStore()
        local ticks = store.GetCurrentTicks()

        dataProvider:Flush()
        for i, tick in ipairs(ticks) do
            dataProvider:Insert({ index = i, tick = tick })
        end

        local count = #ticks
        if count == 0 then
            tickCountLabel:SetText("")
        else
            tickCountLabel:SetText(string.format("|cff888888%d tick mark(s) configured|r", count))
        end

        clearBtn:SetEnabled(count > 0)

        local _, _, localisedClassName, specName, className = ECM.OptionUtil.GetCurrentClassSpec()
        local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
        local classSpecText = "|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown")
        desc:SetText(BASE_DESC_TEXT .. " (" .. classSpecText .. ").")

        local dc = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        defaultSwatchTex:SetColorTexture(dc.r, dc.g, dc.b)

        local defaultWidth = store.GetDefaultWidth() or 1
        defaultWidthSlider:SetValue(defaultWidth)
        defaultWidthValue:SetText(tostring(RoundToStep(defaultWidth)))
    end

    frame:SetScript("OnShow", function(self)
        self:RefreshTicks()
    end)
end

ECM.PowerBarTickMarksOptions = {
    RegisterSettings = function(SB)
        local SUBCAT_NAME = "Tick Marks"
        CreateTickMarksCanvas(SB, SUBCAT_NAME)

        SB.Header("Tick Marks")
        SB.Button({
            name = "Configure Tick Marks",
            buttonText = "Open",
            onClick = function()
                local catID = SB.GetSubcategoryID(SUBCAT_NAME)
                if catID then
                    Settings.OpenToCategory(catID)
                end
            end,
        })
    end,
}
