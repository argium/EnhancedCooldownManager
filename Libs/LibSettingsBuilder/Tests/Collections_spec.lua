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
end)
