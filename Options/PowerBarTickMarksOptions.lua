-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, _ = ...
local C = ECM.Constants
local BASE_DESC_TEXT = "Tick marks allow you to place markers at specific values on the power bar. These settings are saved per class and specialization"

local function GetStore()
    return ECM.PowerBarTickMarksStore
end

local function CreateStyledColorSwatch(parent, size)
    local swatch = CreateFrame("Button", nil, parent)
    swatch:SetSize(size, size)

    local border = swatch:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)

    local colorTex = swatch:CreateTexture(nil, "ARTWORK")
    colorTex:SetPoint("TOPLEFT", 1, -1)
    colorTex:SetPoint("BOTTOMRIGHT", -1, 1)
    colorTex:SetColorTexture(1, 1, 1)

    local highlight = swatch:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.2)

    swatch._tex = colorTex
    return swatch
end

local function RoundToStep(value)
    return math.floor(value + 0.5)
end

local function CreateTickMarksCanvas()
    local frame = CreateFrame("Frame", "ECM_TickMarksCanvas", UIParent)
    frame:SetSize(600, 400)
    frame:Hide()

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 10, -10)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText(BASE_DESC_TEXT .. ".")

    local defaultColorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    defaultColorLabel:SetPoint("TOPLEFT", 10, -78)
    defaultColorLabel:SetWidth(120)
    defaultColorLabel:SetJustifyH("LEFT")
    defaultColorLabel:SetText("Default color:")

    local defaultColorSwatch = CreateStyledColorSwatch(frame, 22)
    defaultColorSwatch:SetPoint("LEFT", defaultColorLabel, "RIGHT", 8, 0)
    local defaultSwatchTex = defaultColorSwatch._tex

    defaultColorSwatch:SetScript("OnClick", function()
        local store = GetStore()
        local c = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        ColorPickerFrame:SetupColorPickerAndShow({
            r = c.r, g = c.g, b = c.b, opacity = c.a,
            hasOpacity = true,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                local a = ColorPickerFrame:GetColorAlpha()
                store.SetDefaultColor({ r = r, g = g, b = b, a = a })
                defaultSwatchTex:SetColorTexture(r, g, b)
            end,
            cancelFunc = function(prev)
                store.SetDefaultColor({ r = prev.r, g = prev.g, b = prev.b, a = prev.opacity })
                defaultSwatchTex:SetColorTexture(prev.r, prev.g, prev.b)
            end,
        })
    end)

    local defaultWidthLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    defaultWidthLabel:SetPoint("TOPLEFT", 10, -108)
    defaultWidthLabel:SetWidth(120)
    defaultWidthLabel:SetJustifyH("LEFT")
    defaultWidthLabel:SetText("Default width:")

    local defaultWidthSlider = CreateFrame("Slider", nil, frame, "MinimalSliderWithSteppersTemplate")
    defaultWidthSlider:SetPoint("LEFT", defaultWidthLabel, "RIGHT", 8, 0)
    defaultWidthSlider:SetWidth(180)
    defaultWidthSlider:SetMinMaxValues(1, 5)
    defaultWidthSlider:SetValueStep(1)
    defaultWidthSlider:SetObeyStepOnDrag(true)

    local defaultWidthValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    defaultWidthValue:SetPoint("LEFT", defaultWidthSlider, "RIGHT", 8, 0)
    defaultWidthValue:SetWidth(24)
    defaultWidthValue:SetJustifyH("LEFT")

    defaultWidthSlider:SetScript("OnValueChanged", function(_, value)
        local rounded = RoundToStep(value)
        defaultWidthValue:SetText(tostring(rounded))
        GetStore().SetDefaultWidth(rounded)
    end)

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 22)
    addBtn:SetPoint("TOPLEFT", 10, -138)
    addBtn:SetText("Add Tick Mark")
    addBtn:SetScript("OnClick", function()
        GetStore().AddTick(50, nil, nil)
        frame:RefreshTicks()
    end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(120, 22)
    clearBtn:SetPoint("LEFT", addBtn, "RIGHT", 10, 0)
    clearBtn:SetText("Clear All Ticks")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["ECM_CONFIRM_CLEAR_TICKS"] = {
            text = "Are you sure you want to remove all tick marks for this spec?",
            button1 = YES,
            button2 = NO,
            OnAccept = function()
                GetStore().SetCurrentTicks({})
                frame:RefreshTicks()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("ECM_CONFIRM_CLEAR_TICKS")
    end)

    local tickCountLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tickCountLabel:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)

    local scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 10, -170)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, 10)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(34)
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

            local swatch = CreateStyledColorSwatch(rowFrame, 20)
            swatch:SetPoint("LEFT", widthValue, "RIGHT", 10, 0)
            rowFrame._swatch = swatch

            local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            removeBtn:SetSize(70, 22)
            removeBtn:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
            removeBtn:SetText("Remove")
            rowFrame._removeBtn = removeBtn

            rowFrame._valueSlider:SetScript("OnValueChanged", function(_, value)
                local rounded = RoundToStep(value)
                rowFrame._valueValue:SetText(tostring(rounded))

                if rowFrame._isRefreshing then
                    return
                end

                if rounded ~= value then
                    rowFrame._isRefreshing = true
                    rowFrame._valueSlider:SetValue(rounded)
                    rowFrame._isRefreshing = false
                    return
                end

                local rowIndex = rowFrame._rowIndex
                if rowIndex then
                    GetStore().UpdateTick(rowIndex, "value", rounded)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end
            end)

            rowFrame._widthSlider:SetScript("OnValueChanged", function(_, value)
                local rounded = RoundToStep(value)
                rowFrame._widthValue:SetText(tostring(rounded))

                if rowFrame._isRefreshing then
                    return
                end

                if rounded ~= value then
                    rowFrame._isRefreshing = true
                    rowFrame._widthSlider:SetValue(rounded)
                    rowFrame._isRefreshing = false
                    return
                end

                local rowIndex = rowFrame._rowIndex
                if rowIndex then
                    GetStore().UpdateTick(rowIndex, "width", rounded)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end
            end)

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
            local rowIndex = rowFrame._rowIndex
            if not rowIndex then
                return
            end

            local c = rowFrame._currentColor
            ColorPickerFrame:SetupColorPickerAndShow({
                r = c.r, g = c.g, b = c.b, opacity = c.a,
                hasOpacity = true,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha()
                    rowFrame._currentColor = { r = r, g = g, b = b, a = a }
                    store.UpdateTick(rowIndex, "color", rowFrame._currentColor)
                    rowFrame._swatch._tex:SetColorTexture(r, g, b)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
                cancelFunc = function(prev)
                    rowFrame._currentColor = { r = prev.r, g = prev.g, b = prev.b, a = prev.opacity }
                    store.UpdateTick(rowIndex, "color", rowFrame._currentColor)
                    rowFrame._swatch._tex:SetColorTexture(prev.r, prev.g, prev.b)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
            })
        end)

        rowFrame._removeBtn:SetScript("OnClick", function()
            local rowIndex = rowFrame._rowIndex
            if not rowIndex then
                return
            end

            store.RemoveTick(rowIndex)
            frame:RefreshTicks()
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)
    end)

    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

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

    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        local parent = self:GetParent()
        if parent and parent.Highlight then
            parent.Highlight:Hide()
        end
    end)

    frame:SetScript("OnShow", function(self)
        self:RefreshTicks()
    end)

    return frame
end

ECM.PowerBarTickMarksOptions = {
    RegisterSettings = function(SB)
        SB.Header("Tick Marks")
        local canvas = CreateTickMarksCanvas()
        SB.EmbedCanvas(canvas, 400)
    end,
}
