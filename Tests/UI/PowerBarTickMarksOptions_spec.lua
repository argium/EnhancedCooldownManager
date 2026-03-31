-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("PowerBarTickMarksOptions", function()
    local originalGlobals
    local ns

    local function makeFontString()
        local text = ""
        local width = 0
        local shown = true
        return {
            SetPoint = function() end,
            ClearAllPoints = function() end,
            SetWidth = function(_, value)
                width = value
            end,
            GetWidth = function()
                return width
            end,
            SetJustifyH = function() end,
            SetWordWrap = function() end,
            SetText = function(_, value)
                text = value
            end,
            GetText = function()
                return text
            end,
            Show = function()
                shown = true
            end,
            Hide = function()
                shown = false
            end,
            IsShown = function()
                return shown
            end,
        }
    end

    local function makeTexture()
        return {
            SetAllPoints = function() end,
            SetColorTexture = function() end,
            Show = function() end,
            Hide = function() end,
        }
    end

    local function makeFrame()
        local scripts = {}
        local shown = true
        local text = ""
        return {
            SetHeight = function() end,
            SetWidth = function() end,
            SetSize = function() end,
            SetPoint = function() end,
            SetAllPoints = function() end,
            ClearAllPoints = function() end,
            Show = function()
                shown = true
            end,
            Hide = function()
                shown = false
            end,
            IsShown = function()
                return shown
            end,
            EnableMouse = function() end,
            SetEnabled = function() end,
            RegisterForClicks = function() end,
            SetAutoFocus = function() end,
            SetNumeric = function() end,
            SetText = function(_, value)
                text = value
            end,
            GetText = function()
                return text
            end,
            SetColorRGB = function() end,
            SetDataProvider = function() end,
            SetWordWrap = function() end,
            SetJustifyH = function() end,
            SetFocus = function(self)
                self._focused = true
            end,
            ClearFocus = function(self)
                self._focused = false
            end,
            HighlightText = function(self)
                self._highlighted = true
            end,
            SetScript = function(_, event, fn)
                scripts[event] = fn
            end,
            GetScript = function(_, event)
                return scripts[event]
            end,
            CreateFontString = function()
                return makeFontString()
            end,
            CreateTexture = function()
                return makeTexture()
            end,
        }
    end

    local function makeSlider()
        local value
        local callbacks = {}
        local slider = makeFrame()
        local minValue = 0
        local maxValue = 0
        local stepValue = 1
        slider.RightText = makeFontString()
        slider.MinText = makeFontString()
        slider.MaxText = makeFontString()
        slider.Slider = {
            SetValueStep = function(_, step)
                stepValue = step
            end,
            GetValueStep = function()
                return stepValue
            end,
            GetMinMaxValues = function()
                return minValue, maxValue
            end,
        }

        slider.Init = function(_, initialValue, initialMin, initialMax, _, _)
            value = initialValue
            minValue = initialMin
            maxValue = initialMax
        end
        slider.RegisterCallback = function(_, event, fn, owner)
            callbacks[event] = callbacks[event] or {}
            callbacks[event][#callbacks[event] + 1] = { fn = fn, owner = owner }
        end
        slider.SetValue = function(self, newValue)
            value = newValue
            for _, callback in ipairs(callbacks.OnValueChanged or {}) do
                callback.fn(callback.owner or self, newValue)
            end
        end
        slider.GetValue = function()
            return value
        end

        return slider
    end

    local function registerSettingsWithHarness()
        local defaultWidthSlider
        local defaultWidthText
        local viewInitializer

        _G.MinimalSliderWithSteppersMixin = {
            Label = { Right = 1 },
            Event = { OnValueChanged = "OnValueChanged" },
        }

        _G.CreateFrame = function(frameType)
            if frameType == "Slider" then
                return makeSlider()
            end
            return makeFrame()
        end
        _G.CreateDataProvider = function()
            return {
                Flush = function() end,
                Insert = function() end,
            }
        end

        local SB = {
            CreateColorSwatch = function()
                return makeFrame()
            end,
            CreateCanvasLayout = function()
                local layout = { frame = makeFrame() }

                function layout:AddHeader()
                    local row = makeFrame()
                    row._defaultsButton = makeFrame()
                    return row
                end

                function layout:AddSpacer() end

                function layout:AddDescription(text)
                    local row = makeFrame()
                    row._text = makeFontString()
                    row._text:SetText(text)
                    return row
                end

                function layout:AddColorSwatch()
                    local row = makeFrame()
                    local swatch = makeFrame()
                    return row, swatch
                end

                function layout:AddSlider()
                    local row = makeFrame()
                    local slider = makeSlider()
                    local valueText = makeFontString()
                    defaultWidthSlider = slider
                    defaultWidthText = valueText
                    return row, slider, valueText
                end

                function layout:AddButton()
                    local row = makeFrame()
                    local button = makeFrame()
                    return row, button
                end

                function layout:AddScrollList()
                    local view = {}
                    view.SetElementInitializer = function(_, _, fn)
                        viewInitializer = fn
                    end
                    return makeFrame(), makeFrame(), view
                end

                return layout
            end,
        }

        ns.PowerBarTickMarksOptions.RegisterSettings(SB, {})

        return defaultWidthSlider, defaultWidthText, viewInitializer
    end

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "MinimalSliderWithSteppersMixin",
            "StaticPopupDialogs", "YES", "NO", "SETTINGS_DEFAULTS",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    it("module loads and exposes RegisterSettings and Store", function()
        ns = TestHelpers.SetupPowerBarTickMarksEnv()

        assert.is_table(ns.PowerBarTickMarksOptions)
        assert.is_function(ns.PowerBarTickMarksOptions.RegisterSettings)

        assert.is_table(ns.PowerBarTickMarksStore)
        assert.is_function(ns.PowerBarTickMarksStore.GetCurrentTicks)
        assert.is_function(ns.PowerBarTickMarksStore.AddTick)
    end)

    it("supports drag and manual entry for default and per-tick sliders", function()
        ns = TestHelpers.SetupPowerBarTickMarksEnv()
        ns.Runtime = { ScheduleLayoutUpdate = function() end }

        local defaultWidthSlider, defaultWidthText, viewInitializer = registerSettingsWithHarness()

        defaultWidthSlider:SetValue(4)
        assert.are.equal(4, ns.PowerBarTickMarksStore.GetDefaultWidth())
        assert.are.equal("4", defaultWidthText:GetText())

        defaultWidthSlider._ecmValueButton:GetScript("OnClick")()
        assert.is_true(defaultWidthSlider._ecmEditBox:IsShown())
        defaultWidthSlider._ecmEditBox:SetText("5")
        defaultWidthSlider._ecmEditBox:GetScript("OnEnterPressed")()
        assert.are.equal(5, ns.PowerBarTickMarksStore.GetDefaultWidth())
        assert.are.equal("5", defaultWidthText:GetText())
        assert.is_false(defaultWidthSlider._ecmEditBox:IsShown())

        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 50, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
        })

        local rowFrame = makeFrame()
        local tick = ns.PowerBarTickMarksStore.GetCurrentTicks()[1]
        viewInitializer(rowFrame, { index = 1, tick = tick })

        rowFrame._valueSlider:SetValue(75)

        rowFrame._widthSlider._ecmValueButton:GetScript("OnClick")()
        rowFrame._widthSlider._ecmEditBox:SetText("4")
        rowFrame._widthSlider._ecmEditBox:GetScript("OnEnterPressed")()

        tick = ns.PowerBarTickMarksStore.GetCurrentTicks()[1]
        assert.are.equal(75, tick.value)
        assert.are.equal(4, tick.width)
        assert.are.equal("75", rowFrame._valueText:GetText())
        assert.are.equal("4", rowFrame._widthText:GetText())
        assert.is_false(rowFrame._widthSlider._ecmEditBox:IsShown())
    end)

    it("rescales value slider for large resource values", function()
        ns = TestHelpers.SetupPowerBarTickMarksEnv()
        ns.Runtime = { ScheduleLayoutUpdate = function() end }

        local _, _, viewInitializer = registerSettingsWithHarness()

        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 50000, width = 2, color = { r = 1, g = 1, b = 1, a = 1 } },
        })

        local rowFrame = makeFrame()
        local tick = ns.PowerBarTickMarksStore.GetCurrentTicks()[1]
        viewInitializer(rowFrame, { index = 1, tick = tick })

        -- Slider should have rescaled to accommodate 50000
        assert.are.equal("50000", rowFrame._valueText:GetText())
        assert.are.equal(50000, rowFrame._valueSlider._ecmMaxValue)
        assert.are.equal(250, rowFrame._valueSlider._ecmStep)

        -- Typing a value in a higher tier should rescale further
        rowFrame._valueSlider._ecmValueButton:GetScript("OnClick")()
        rowFrame._valueSlider._ecmEditBox:SetText("120000")
        rowFrame._isRefreshing = false
        rowFrame._valueSlider._ecmEditBox:GetScript("OnEnterPressed")()
        assert.are.equal(500000, rowFrame._valueSlider._ecmMaxValue)
        assert.are.equal(2500, rowFrame._valueSlider._ecmStep)
    end)

    it("keeps small values in the default 1-200 tier", function()
        ns = TestHelpers.SetupPowerBarTickMarksEnv()
        ns.Runtime = { ScheduleLayoutUpdate = function() end }

        local _, _, viewInitializer = registerSettingsWithHarness()

        ns.PowerBarTickMarksStore.SetCurrentTicks({
            { value = 30, width = 1, color = { r = 1, g = 1, b = 1, a = 1 } },
        })

        local rowFrame = makeFrame()
        local tick = ns.PowerBarTickMarksStore.GetCurrentTicks()[1]
        viewInitializer(rowFrame, { index = 1, tick = tick })

        assert.are.equal("30", rowFrame._valueText:GetText())
        assert.are.equal(200, rowFrame._valueSlider._ecmMaxValue)
        assert.are.equal(1, rowFrame._valueSlider._ecmStep)
    end)
end)
