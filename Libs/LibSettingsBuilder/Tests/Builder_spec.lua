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

    it("uses the section category for an unnamed page in a multi-page section", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "power",
                    name = "Power",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { type = "info", name = "Enabled", value = "Yes" },
                            },
                        },
                        {
                            key = "ticks",
                            name = "Ticks",
                            rows = {
                                { type = "info", name = "Count", value = "0" },
                            },
                        },
                    },
                },
            },
        })

        local mainPage = assert(sb:GetPage("power", "main"))
        local ticksPage = assert(sb:GetPage("power", "ticks"))

        assert.are.equal("Builder Spec.Power", mainPage:GetId())
        assert.are.equal("Builder Spec.Power.Ticks", ticksPage:GetId())
        assert.are.equal(mainPage._category, ticksPage._category._parent)
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

    it("returns an lsb instance with only the public API on its prototype", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = { { type = "info", name = "Version", value = "1.0" } },
                        },
                    },
                },
            },
        })

        -- Public API accessible via narrow prototype
        assert.is_function(sb.GetSection)
        assert.is_function(sb.GetRootPage)
        assert.is_function(sb.GetPage)
        assert.is_function(sb.HasCategory)

        -- Internal row-builder methods not on the public prototype
        assert.is_nil(sb.Checkbox)
        assert.is_nil(sb.Slider)
        assert.is_nil(sb.BorderGroup)
        assert.is_nil(sb.Control)
        assert.is_nil(sb.EmbedCanvas)

        -- Instance state is raw on the table
        assert.is_table(rawget(sb, "_sections"))
        assert.is_table(rawget(sb, "_layouts"))
    end)

    it("returns plain page handles with methods directly on the table", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = { { type = "info", name = "Version", value = "1.0" } },
                        },
                    },
                },
            },
        })
        local page = assert(sb:GetPage("general", "main"))

        -- Methods are directly on the handle, not via metatable
        assert.is_function(rawget(page, "GetId"))
        assert.is_function(rawget(page, "Refresh"))
        -- _category is kept for HasCategory use
        assert.is_not_nil(rawget(page, "_category"))

        -- Internal page state is not on the handle
        assert.is_nil(page._operations)
        assert.is_nil(page._rowIDs)
        assert.is_nil(page._registered)
        assert.is_nil(page._builder)
        assert.is_nil(page._root)
    end)

    it("registers declarative pageActions rows", function()
        local sb = createBuilder({
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            name = "Main",
                            rows = {
                                {
                                    id = "actions",
                                    type = "pageActions",
                                    name = "Spell Colors",
                                    attachToCategoryHeader = false,
                                    hideTitle = false,
                                    actions = {
                                        {
                                            text = "Reset",
                                            onClick = function() end,
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        })
        local page = assert(sb:GetPage("general", "main"))
        local initializers = assert(page._category:GetLayout())._initializers
        local initializer = assert(initializers[1])
        local data = initializer:GetData()

        assert.are.equal("pageActions", data._lsbKind)
        assert.are.equal("Spell Colors", data.name)
        assert.is_false(data.attachToCategoryHeader)
        assert.is_false(data.hideTitle)
        assert.are.equal("Reset", data.actions[1].text)
    end)
end)
