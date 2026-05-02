-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder Collections", function()
    local originalGlobals

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "LibStub",
            "Settings",
            "CreateFrame",
            "hooksecurefunc",
            "SettingsDropdownControlMixin",
            "SettingsSliderControlMixin",
            "SettingsListElementMixin",
            "CreateDataProvider",
            "CreateScrollBoxListLinearView",
            "GameFontDisable",
            "GameFontNormal",
            "ScrollUtil",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        _G.hooksecurefunc = function() end
        _G.SettingsListElementMixin = {}
        _G.SettingsDropdownControlMixin = {}
        _G.SettingsSliderControlMixin = {}
        _G.GameFontDisable = {
            GetTextColor = function()
                return 0.5, 0.5, 0.5, 1
            end,
        }
        _G.GameFontNormal = {
            GetTextColor = function()
                return 1, 0.82, 0, 1
            end,
        }
        _G.CreateFrame = function()
            return TestHelpers.makeFrame()
        end
        _G.CreateDataProvider = function()
            return {
                Flush = function(self)
                    self.items = {}
                end,
                Insert = function(self, item)
                    self.items = self.items or {}
                    self.items[#self.items + 1] = item
                end,
            }
        end
        _G.CreateScrollBoxListLinearView = function()
            return {
                SetElementExtent = function() end,
                SetElementInitializer = function(self, _, fn)
                    self._initializer = fn
                end,
            }
        end
        _G.ScrollUtil = {
            InitScrollBoxListWithScrollBar = function(scrollBox, _, view)
                scrollBox._scrollView = view
            end,
        }
        TestHelpers.LoadLibSettingsBuilder()
    end)

    local function makeCollectionControl(clickedButtons)
        local control = TestHelpers.makeFrame()
        control._children = {}
        local callbacks = {}
        local textColor = { 1, 1, 1, 1 }
        local function fireValueChanged(self, value)
            for _, callback in ipairs(callbacks.OnValueChanged or {}) do
                callback.fn(callback.owner or self, value)
            end
        end
        control.SetShown = function(self, shown)
            if shown then
                self:Show()
            else
                self:Hide()
            end
        end
        control.GetChildren = function(self)
            return (table.unpack or unpack)(self._children)
        end
        control.SetText = function(self, text)
            self._text = text
        end
        control.GetText = function(self)
            return self._text or ""
        end
        control.SetTexture = function(self, textureValue)
            self._texture = textureValue
        end
        control.GetTexture = function(self)
            return self._texture
        end
        control.GetStringWidth = function(self)
            return #(self._text or "") * 5
        end
        control.SetFontObject = function(self, fontObject)
            self._fontObject = fontObject
        end
        control.SetTextColor = function(_, r, g, b, a)
            textColor = { r, g, b, a or 1 }
        end
        control.GetTextColor = function()
            return textColor[1], textColor[2], textColor[3], textColor[4]
        end
        control.SetWordWrap = function() end
        control.SetJustifyH = function() end
        control.SetJustifyV = function() end
        control.SetAutoFocus = function() end
        control.SetNumeric = function() end
        control.SetMaxLetters = function() end
        control.SetTextInsets = function() end
        control.SetFocus = function() end
        control.HighlightText = function() end
        control.SetEnabled = function(self, enabled)
            self._enabled = enabled
        end
        control.EnableMouse = function(self, enabled)
            self._mouseEnabled = enabled
        end
        control.RegisterForClicks = function(self, ...)
            self._registeredClicks = { ... }
            if clickedButtons then
                clickedButtons[#clickedButtons + 1] = self
            end
        end
        control.SetPropagateMouseClicks = function(self, propagate)
            self._propagateMouseClicks = propagate
        end
        control.SetMinMaxValues = function(self, minValue, maxValue)
            self._minValue = minValue
            self._maxValue = maxValue
        end
        control.SetValueStep = function(self, step)
            self._valueStep = step
        end
        control.SetObeyStepOnDrag = function(self, obey)
            self._obeyStepOnDrag = obey
        end
        control.RegisterCallback = function(self, event, fn, owner)
            callbacks[event] = callbacks[event] or {}
            callbacks[event][#callbacks[event] + 1] = { fn = fn, owner = owner }
        end
        control.Init = function(self, initialValue, minValue, maxValue)
            self._value = initialValue
            self._minValue = minValue
            self._maxValue = maxValue
            fireValueChanged(self, initialValue)
        end
        control.SetValue = function(self, value)
            self._value = value
            fireValueChanged(self, value)
        end
        control.Slider = {
            SetValueStep = function(_, step)
                control._valueStep = step
            end,
        }
        control.SetColorRGB = function(self, r, g, b)
            self._color = { r, g, b }
        end
        control.SetDataProvider = function(self, dataProvider)
            self._dataProvider = dataProvider
            if self._scrollView and self._scrollView._initializer then
                self._rows = self._rows or {}
                for index, item in ipairs(dataProvider.items or {}) do
                    local row = self._rows[index] or makeCollectionControl(clickedButtons)
                    self._rows[index] = row
                    if not row._testParented then
                        self._children[#self._children + 1] = row
                        row._testParented = true
                    end
                    self._scrollView._initializer(row, item)
                end
            end
        end
        control.CreateFontString = function()
            return makeCollectionControl(clickedButtons)
        end
        control.CreateTexture = function()
            local texture = makeCollectionControl(clickedButtons)
            texture.SetDesaturated = function(self, desaturated)
                self._desaturated = desaturated
            end
            texture.SetVertexColor = function(self, r, g, b, a)
                self._vertexColor = { r, g, b, a }
            end
            return texture
        end

        local function setButtonTexture(self, key, textureValue)
            self[key] = self[key] or makeCollectionControl(clickedButtons)
            self[key]:SetTexture(textureValue)
        end
        control.SetNormalTexture = function(self, textureValue)
            setButtonTexture(self, "_normalTexture", textureValue)
        end
        control.GetNormalTexture = function(self)
            return self._normalTexture
        end
        control.SetPushedTexture = function(self, textureValue)
            setButtonTexture(self, "_pushedTexture", textureValue)
        end
        control.GetPushedTexture = function(self)
            return self._pushedTexture
        end
        control.SetDisabledTexture = function(self, textureValue)
            setButtonTexture(self, "_disabledTexture", textureValue)
        end
        control.GetDisabledTexture = function(self)
            return self._disabledTexture
        end
        control.SetHighlightTexture = function(self, textureValue)
            setButtonTexture(self, "_highlightTexture", textureValue)
        end
        control.GetHighlightTexture = function(self)
            return self._highlightTexture
        end
        return control
    end

    it("creates first-class list and sectionList initializers from raw row specs", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local SB = lsb.New({
            name = "Collections",
            store = function()
                return { root = {} }
            end,
            defaults = function()
                return { root = {} }
            end,
            onChanged = function() end,
            sections = {
                {
                    key = "rows",
                    name = "Rows",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                {
                                    id = "listRow",
                                    type = "list",
                                    height = 120,
                                    items = function()
                                        return {}
                                    end,
                                    variant = "swatch",
                                },
                                {
                                    id = "sectionRow",
                                    type = "sectionList",
                                    height = 120,
                                    sections = function()
                                        return {}
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        })
        local page = SB:GetPage("rows", "main")
        local initializers = page._category:GetLayout()._initializers
        local listInit = initializers[1]
        local sectionInit = initializers[2]

        assert.are.equal("SettingsListElementTemplate", listInit._template)
        assert.are.equal("SettingsListElementTemplate", sectionInit._template)
        assert.is_function(page.Refresh)
    end)

    it("registers section-list row action buttons for mouse-up clicks", function()
        local clickedButtons = {}

        _G.CreateFrame = function()
            return makeCollectionControl(clickedButtons)
        end

        local lsb = LibStub("LibSettingsBuilder-1.0")
        lsb._internal.applyCollectionFrame(makeCollectionControl(clickedButtons), {
            sections = function()
                return {
                    {
                        key = "utility",
                        title = "Utility",
                        items = {
                            {
                                label = "Shadowmeld",
                                actions = {
                                    delete = {
                                        text = "Remove",
                                    },
                                },
                            },
                        },
                    },
                }
            end,
        })

        assert.is_true(#clickedButtons > 0)
        for _, button in ipairs(clickedButtons) do
            assert.are.same({ "LeftButtonUp" }, button._registeredClicks)
        end
    end)

    it("resets reused section-list row visuals from disabled to enabled", function()
        _G.CreateFrame = function()
            return makeCollectionControl()
        end

        local sections = {
            {
                key = "utility",
                title = "Utility",
                items = {
                    {
                        label = "Shadowmeld",
                        icon = 58984,
                        tooltip = "Add Shadowmeld",
                        disabled = true,
                        actions = {
                            delete = {
                                buttonTextures = { normal = "add", disabled = "add-disabled" },
                                enabled = false,
                                tooltip = "Add",
                            },
                        },
                    },
                },
            },
        }
        local data = {
            sections = function()
                return sections
            end,
        }
        local host = makeCollectionControl()
        local lsb = LibStub("LibSettingsBuilder-1.0")

        lsb._internal.applyCollectionFrame(host, data)
        local row = assert(host._lsbSectionRowPools.utility[1])
        assert.are.same({ 0.5, 0.5, 0.5, 1 }, { row._label:GetTextColor() })
        assert.are.equal(0.5, row._label:GetAlpha())
        assert.are.equal(0.4, row._textureButtons.delete:GetAlpha())
        assert.is_nil(row._textureButtons.delete:GetScript("OnEnter"))

        sections[1].items[1] = {
            label = "Shadowmeld",
            icon = 58984,
            tooltip = "Remove Shadowmeld",
            disabled = false,
            actions = {
                delete = {
                    buttonTextures = { normal = "remove", disabled = "remove-disabled" },
                    enabled = true,
                    tooltip = "Remove",
                },
            },
        }
        lsb._internal.applyCollectionFrame(host, data)

        assert.are.same({ 1, 0.82, 0, 1 }, { row._label:GetTextColor() })
        assert.are.equal(1, row._label:GetAlpha())
        assert.are.equal(1, row._textureButtons.delete:GetAlpha())
        assert.are.equal(1, row._textureButtons.delete:GetNormalTexture():GetAlpha())
        assert.are.equal(row._label:GetStringWidth(), row._tooltipOwner:GetWidth())
        row._tooltipOwner:GetScript("OnEnter")(row._tooltipOwner)
        assert.is_true(row._highlight:IsShown())
        assert.is_function(row._textureButtons.delete:GetScript("OnEnter"))
    end)

    it("prevents editor row controls from selecting the host settings row", function()
        _G.CreateFrame = function()
            return makeCollectionControl()
        end

        local item = {
            label = "Tick 1",
            fields = {
                {
                    value = 50,
                    min = 1,
                    max = 100,
                    step = 1,
                },
            },
            color = {
                value = { r = 1, g = 1, b = 1, a = 1 },
            },
            remove = {
                text = "Remove",
            },
        }
        local host = makeCollectionControl()
        local lsb = LibStub("LibSettingsBuilder-1.0")

        lsb._internal.applyCollectionFrame(host, {
            preset = "editor",
            rowHeight = 34,
            items = function()
                return { item }
            end,
        })

        local row = makeCollectionControl()
        host._lsbCollectionView._initializer(row, assert(host._lsbCollectionDataProvider.items[1]))

        local slider = row._fieldWidgets[1].slider
        assert.is_false(row._mouseEnabled)
        assert.is_nil(row:GetScript("OnEnter"))
        assert.is_nil(row:GetScript("OnLeave"))
        assert.is_false(slider._propagateMouseClicks)
        assert.is_false(slider._lsbValueButton._propagateMouseClicks)
        assert.is_false(row._swatch._propagateMouseClicks)
        assert.is_false(row._removeButton._propagateMouseClicks)
        assert.are.same({ "LeftButtonUp" }, row._removeButton._registeredClicks)
    end)

    it("keeps editor slider callbacks current across recycled row refreshes", function()
        _G.CreateFrame = function()
            return makeCollectionControl()
        end

        local calls = {}
        local items = {
            {
                label = "Tick 1",
                fields = {
                    {
                        value = 10,
                        min = 1,
                        max = 100,
                        step = 1,
                        onValueChanged = function(value)
                            calls[#calls + 1] = "first:" .. value
                        end,
                    },
                },
            },
        }
        local host = makeCollectionControl()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local data = {
            preset = "editor",
            rowHeight = 34,
            items = function()
                return items
            end,
        }

        lsb._internal.applyCollectionFrame(host, data)
        items = {
            {
                label = "Tick 2",
                fields = {
                    {
                        value = 20,
                        min = 1,
                        max = 100,
                        step = 1,
                        onValueChanged = function(value)
                            calls[#calls + 1] = "second:" .. value
                        end,
                    },
                },
            },
        }
        lsb._internal.applyCollectionFrame(host, data)

        host._lsbCollectionScrollBox._rows[1]._fieldWidgets[1].slider:SetValue(42)

        assert.are.same({ "second:42" }, calls)
    end)

    it("resolves editor slider text entry ranges against the current item", function()
        _G.CreateFrame = function()
            return makeCollectionControl()
        end

        local resolvedItem
        local host = makeCollectionControl()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local item = {
            label = "Tick 1",
            fields = {
                {
                    value = 50,
                    min = 1,
                    max = 100,
                    step = 1,
                    getRange = function(currentItem, targetValue)
                        resolvedItem = currentItem
                        return 1, targetValue, 5
                    end,
                },
            },
        }

        lsb._internal.applyCollectionFrame(host, {
            preset = "editor",
            rowHeight = 34,
            items = function()
                return { item }
            end,
        })

        local minValue, maxValue, step = host._lsbCollectionScrollBox._rows[1]._fieldWidgets[1].slider._lsbRangeResolver(500)

        assert.are.equal(item, resolvedItem)
        assert.are.equal(1, minValue)
        assert.are.equal(500, maxValue)
        assert.are.equal(5, step)
    end)

    it("does not re-enable editor row mouse targets during initializer state evaluation", function()
        _G.CreateFrame = function(_, _, parent)
            local frame = makeCollectionControl()
            if parent and parent._children then
                parent._children[#parent._children + 1] = frame
            end
            return frame
        end

        local lsb = LibStub("LibSettingsBuilder-1.0")
        local SB = lsb.New({
            name = "Collections",
            store = function()
                return { root = {} }
            end,
            defaults = function()
                return { root = {} }
            end,
            onChanged = function() end,
            sections = {
                {
                    key = "rows",
                    name = "Rows",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                {
                                    id = "listRow",
                                    type = "list",
                                    height = 120,
                                    variant = "editor",
                                    items = function()
                                        return {
                                            {
                                                label = "Tick 1",
                                                fields = {
                                                    { value = 50, min = 1, max = 100, step = 1 },
                                                },
                                                color = {
                                                    value = { r = 1, g = 1, b = 1, a = 1 },
                                                },
                                                remove = {
                                                    text = "Remove",
                                                },
                                            },
                                        }
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        })
        local initializer = SB:GetPage("rows", "main")._category:GetLayout()._initializers[1]
        local host = makeCollectionControl()

        initializer:InitFrame(host)

        local row = host._lsbCollectionScrollBox._rows[1]
        local slider = row._fieldWidgets[1].slider
        assert.is_false(row._mouseEnabled)
        assert.is_false(slider._propagateMouseClicks)
        assert.is_false(slider._lsbValueButton._propagateMouseClicks)
        assert.is_false(row._removeButton._propagateMouseClicks)
        assert.is_true(host:IsShown())
        assert.are.equal(1, host:GetAlpha())
    end)

    it("keeps mode-input submit disabled until the footer reports a valid value", function()
        _G.CreateFrame = function()
            return makeCollectionControl()
        end

        local valid = false
        local submitCalls = 0
        local data = {
            sections = function()
                return {
                    {
                        key = "utility",
                        title = "Utility",
                        footer = {
                            type = "modeInput",
                            modeText = "Spell",
                            inputText = function()
                                return valid and "12345" or ""
                            end,
                            submitText = "Add",
                            submitEnabled = function()
                                return valid
                            end,
                            onSubmit = function()
                                submitCalls = submitCalls + 1
                            end,
                        },
                    },
                }
            end,
        }
        local host = makeCollectionControl()
        local lsb = LibStub("LibSettingsBuilder-1.0")

        lsb._internal.applyCollectionFrame(host, data)
        local footer = assert(host._lsbSectionTrailerRows.utility)
        assert.is_false(footer._submitButton._enabled)
        footer._submitButton:GetScript("OnClick")()
        assert.are.equal(0, submitCalls)

        valid = true
        lsb._internal.applyCollectionFrame(host, data)
        assert.is_true(footer._submitButton._enabled)
        footer._submitButton:GetScript("OnClick")()
        assert.are.equal(1, submitCalls)
    end)

    it("prevents embedded color swatch clicks from selecting the host settings row", function()
        local created
        _G.CreateFrame = function()
            created = {
                EnableMouse = function(self, enabled)
                    self._mouseEnabled = enabled
                end,
                RegisterForClicks = function(self, ...)
                    self._registeredClicks = { ... }
                end,
                SetPropagateMouseClicks = function(self, propagate)
                    self._propagateMouseClicks = propagate
                end,
            }
            return created
        end

        local lsb = LibStub("LibSettingsBuilder-1.0")
        local swatch = lsb._internal.createColorSwatch(TestHelpers.makeFrame())

        assert.are.equal(created, swatch)
        assert.is_true(swatch._mouseEnabled)
        assert.is_false(swatch._propagateMouseClicks)
    end)
end)
