-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _, _ = ...
local C = ECM.Constants

local function GetStore()
    return ECM.PowerBarTickMarksStore
end

local function CreateTickMarksCanvas()
    local frame = CreateFrame("Frame", "ECM_TickMarksCanvas", UIParent)
    frame:SetSize(600, 400)

    local desc = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 10, -10)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText("Tick marks allow you to place markers at specific values on the power bar. These settings are saved per class and specialization.")

    local specLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    specLabel:SetPoint("TOPLEFT", 10, -50)

    local defaultColorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    defaultColorLabel:SetPoint("TOPLEFT", 10, -75)
    defaultColorLabel:SetText("Default color:")

    local defaultColorSwatch = CreateFrame("Button", nil, frame)
    defaultColorSwatch:SetSize(20, 20)
    defaultColorSwatch:SetPoint("LEFT", defaultColorLabel, "RIGHT", 5, 0)
    local defaultSwatchTex = defaultColorSwatch:CreateTexture(nil, "BACKGROUND")
    defaultSwatchTex:SetAllPoints()
    defaultSwatchTex:SetColorTexture(1, 1, 1)

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
    defaultWidthLabel:SetPoint("TOPLEFT", 200, -75)
    defaultWidthLabel:SetText("Default width:")

    local defaultWidthSlider = CreateFrame("Slider", nil, frame, "MinimalSliderWithSteppersTemplate")
    defaultWidthSlider:SetPoint("LEFT", defaultWidthLabel, "RIGHT", 5, 0)
    defaultWidthSlider:SetWidth(120)
    defaultWidthSlider:SetMinMaxValues(1, 5)
    defaultWidthSlider:SetValueStep(1)
    defaultWidthSlider:SetObeyStepOnDrag(true)
    defaultWidthSlider:SetScript("OnValueChanged", function(_, value)
        GetStore().SetDefaultWidth(value)
    end)

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(120, 22)
    addBtn:SetPoint("TOPLEFT", 10, -105)
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
    scrollBox:SetPoint("TOPLEFT", 10, -135)
    scrollBox:SetPoint("BOTTOMRIGHT", -30, 10)

    local scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 5, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 5, 0)

    local view = CreateScrollBoxListLinearView()
    view:SetElementInitializer("Frame", function(rowFrame, data)
        if not rowFrame._initialized then
            rowFrame:SetSize(scrollBox:GetWidth(), 30)

            local headerLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            headerLabel:SetPoint("LEFT", 2, 0)
            headerLabel:SetWidth(60)
            rowFrame._header = headerLabel

            local valueSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
            valueSlider:SetPoint("LEFT", headerLabel, "RIGHT", 5, 0)
            valueSlider:SetWidth(120)
            valueSlider:SetMinMaxValues(1, 200)
            valueSlider:SetValueStep(1)
            valueSlider:SetObeyStepOnDrag(true)
            rowFrame._valueSlider = valueSlider

            local widthSlider = CreateFrame("Slider", nil, rowFrame, "MinimalSliderWithSteppersTemplate")
            widthSlider:SetPoint("LEFT", valueSlider, "RIGHT", 10, 0)
            widthSlider:SetWidth(80)
            widthSlider:SetMinMaxValues(1, 5)
            widthSlider:SetValueStep(1)
            widthSlider:SetObeyStepOnDrag(true)
            rowFrame._widthSlider = widthSlider

            local swatch = CreateFrame("Button", nil, rowFrame)
            swatch:SetSize(20, 20)
            swatch:SetPoint("LEFT", widthSlider, "RIGHT", 10, 0)
            local swatchTex = swatch:CreateTexture(nil, "BACKGROUND")
            swatchTex:SetAllPoints()
            swatchTex:SetColorTexture(1, 1, 1)
            swatch._tex = swatchTex
            rowFrame._swatch = swatch

            local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
            removeBtn:SetSize(20, 20)
            removeBtn:SetPoint("LEFT", swatch, "RIGHT", 5, 0)
            removeBtn:SetText("X")
            rowFrame._removeBtn = removeBtn

            rowFrame._initialized = true
        end

        local store = GetStore()
        local index = data.index
        rowFrame._header:SetText("Tick " .. index)

        rowFrame._valueSlider:SetValue(data.tick.value or 50)
        rowFrame._valueSlider:SetScript("OnValueChanged", function(_, value)
            store.UpdateTick(index, "value", value)
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)

        rowFrame._widthSlider:SetValue(data.tick.width or store.GetDefaultWidth())
        rowFrame._widthSlider:SetScript("OnValueChanged", function(_, value)
            store.UpdateTick(index, "width", value)
            ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
        end)

        local tc = data.tick.color or store.GetDefaultColor()
        rowFrame._swatch._tex:SetColorTexture(tc.r, tc.g, tc.b)
        rowFrame._swatch:SetScript("OnClick", function()
            ColorPickerFrame:SetupColorPickerAndShow({
                r = tc.r, g = tc.g, b = tc.b, opacity = tc.a,
                hasOpacity = true,
                swatchFunc = function()
                    local r, g, b = ColorPickerFrame:GetColorRGB()
                    local a = ColorPickerFrame:GetColorAlpha()
                    store.UpdateTick(index, "color", { r = r, g = g, b = b, a = a })
                    rowFrame._swatch._tex:SetColorTexture(r, g, b)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
                cancelFunc = function(prev)
                    store.UpdateTick(index, "color", { r = prev.r, g = prev.g, b = prev.b, a = prev.opacity })
                    rowFrame._swatch._tex:SetColorTexture(prev.r, prev.g, prev.b)
                    ECM.ScheduleLayoutUpdate(0, "OptionsChanged")
                end,
            })
        end)

        rowFrame._removeBtn:SetScript("OnClick", function()
            store.RemoveTick(index)
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
            tickCountLabel:SetText("|cffaaaaaa(No tick marks configured for this spec)|r")
        else
            tickCountLabel:SetText(string.format("|cff888888%d tick mark(s) configured|r", count))
        end

        clearBtn:SetEnabled(count > 0)

        local _, _, localisedClassName, specName, className = ECM.OptionUtil.GetCurrentClassSpec()
        local color = C.CLASS_COLORS[className] or C.COLOR_WHITE_HEX
        specLabel:SetText("|cff" .. color .. (localisedClassName or "Unknown") .. "|r " .. (specName or "Unknown"))

        local dc = store.GetDefaultColor() or C.DEFAULT_POWERBAR_TICK_COLOR
        defaultSwatchTex:SetColorTexture(dc.r, dc.g, dc.b)
        defaultWidthSlider:SetValue(store.GetDefaultWidth() or 1)
    end

    frame:SetScript("OnShow", function(self)
        self:RefreshTicks()
    end)

    return frame
end

ECM.PowerBarTickMarksOptions = {
    RegisterSettings = function(SB)
        local canvas = CreateTickMarksCanvas()
        SB.CreateCanvasSubcategory(canvas, "Tick Marks")
    end,
}
