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

    it("creates first-class list and sectionList initializers after the split load", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local SB = lsb:New({
            pathAdapter = lsb.PathAdapter({
                getStore = function()
                    return { root = {} }
                end,
                getDefaults = function()
                    return { root = {} }
                end,
            }),
            varPrefix = "COLL",
            onChanged = function() end,
        })
        local root = SB.GetRoot("Collections")
        root:Register({
            sections = {
                {
                    key = "rows",
                    name = "Rows",
                    rows = {},
                },
            },
        })
        local page = root:GetSection("rows"):GetPage("main")
        local category = page._category

        local listInit = SB.List({
            category = category,
            height = 120,
            items = function()
                return {}
            end,
            variant = "swatch",
        })
        local sectionInit = SB.SectionList({
            category = category,
            height = 120,
            sections = function()
                return {}
            end,
        })

        assert.are.equal(SB.EMBED_CANVAS_TEMPLATE, listInit._template)
        assert.are.equal(SB.EMBED_CANVAS_TEMPLATE, sectionInit._template)
        assert.is_function(page.Refresh)
    end)
end)
