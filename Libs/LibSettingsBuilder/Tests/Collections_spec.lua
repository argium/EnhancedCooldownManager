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
            InitScrollBoxListWithScrollBar = function() end,
        }
        TestHelpers.LoadLibSettingsBuilder()
    end)

    local function makeCollectionControl(clickedButtons)
        local control = TestHelpers.makeFrame()
        local textColor = { 1, 1, 1, 1 }
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
