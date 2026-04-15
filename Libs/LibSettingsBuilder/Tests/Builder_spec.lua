-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder Builder", function()
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
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupLibStub()
        TestHelpers.SetupSettingsStubs()
        TestHelpers.LoadLibSettingsBuilder()
    end)

    local function createBuilder(config)
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local profile = {
            general = {
                enabled = true,
                height = nil,
            },
        }
        local defaults = {
            general = {
                enabled = false,
                height = 12,
            },
        }

        return lsb.New({
            name = "Builder Spec",
            store = function()
                return profile
            end,
            defaults = function()
                return defaults
            end,
            onChanged = function() end,
            page = config and config.page or nil,
            sections = config and config.sections or nil,
        }), profile, defaults
    end

    it("registers root and section pages through LSB.New", function()
        local sb = createBuilder({
            page = {
                key = "about",
                rows = {
                    { type = "info", name = "Version", value = "1.0" },
                },
            },
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "checkbox", path = "general.enabled", name = "Enabled" },
                            },
                        },
                    },
                },
            },
        })

        local rootPage = assert(sb:GetRootPage())
        local generalPage = assert(sb:GetPage("general", "main"))

        assert.are.equal("Builder Spec", rootPage:GetId())
        assert.are.equal("Builder Spec.General", generalPage:GetId())
        assert.are.equal("general", assert(sb:GetSection("general")).key)
        assert.is_true(sb:HasCategory(rootPage._category))
        assert.is_true(sb:HasCategory(generalPage._category))
    end)

    it("returns nil for missing section-page lookups", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })

        assert.is_nil(sb:GetPage("general"))
        assert.is_nil(sb:GetPage("missing", "main"))
        assert.is_nil(sb:GetPage("general", "missing"))
    end)

    it("registers root-bound composite rows from an empty path", function()
        local sb, profile = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "heightOverride", path = "", disabled = false },
                            },
                        },
                    },
                },
            },
        })

        local settings = TestHelpers.CollectSettings(function()
            TestHelpers.RegisterSectionSpec(sb, {
                key = "generalTwo",
                name = "General Two",
                path = "general",
                pages = {
                    {
                        key = "main",
                        rows = {
                            { type = "heightOverride", path = "", disabled = false },
                        },
                    },
                },
            })
        end)

        assert.is_not_nil(settings["BS_generalTwo_height"] or settings["BS_general_height"])
        assert.is_nil(profile.general.height)
    end)

    it("rejects deprecated desc fields at registration time", function()
        local ok, err = pcall(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    { type = "checkbox", path = "general.enabled", name = "Enabled", desc = "Old tooltip" },
                                },
                            },
                        },
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("deprecated field 'desc'", 1, true))
    end)

    it("rejects removed condition fields at registration time", function()
        local ok, err = pcall(function()
            createBuilder({
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    {
                                        type = "checkbox",
                                        path = "general.enabled",
                                        name = "Enabled",
                                        condition = function()
                                            return true
                                        end,
                                    },
                                },
                            },
                        },
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("removed field 'condition'", 1, true))
    end)

    it("keeps page handles limited to the v2 public surface", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "info", name = "Version", value = "1.0" },
                            },
                        },
                    },
                },
            },
        })
        local page = assert(sb:GetPage("general", "main"))

        assert.is_function(page.GetId)
        assert.is_function(page.Refresh)
        assert.is_nil(page.GetID)
        assert.is_nil(page.RegisterRows)
        assert.is_nil(page.Checkbox)
        assert.is_nil(page.List)
    end)
end)
