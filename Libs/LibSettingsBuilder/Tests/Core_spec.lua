-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibSettingsBuilder Core", function()
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

    it("loads the split library through the shared ordered loader", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        assert.is_table(lsb)
        assert.is_nil(lsb._loadState.open)
    end)

    it("initializes implementation internals on load", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        assert.is_table(lsb._internal)
        assert.are.equal(26, lsb._internal.CanvasLayoutDefaults.elementHeight)
        assert.is_table(lsb._pageLifecycleCallbacks)
        assert.is_false(lsb._pageLifecycleHooked)
    end)

    it("exposes only the public API on builder instances", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local sb = lsb.New({
            name = "Phase 2",
            onChanged = function() end,
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

        assert.is_function(sb.GetSection)
        assert.is_function(sb.GetRootPage)
        assert.is_function(sb.GetPage)
        assert.is_function(sb.HasCategory)

        -- Internal builder methods not on the public prototype
        assert.is_nil(sb.Control)
        assert.is_nil(sb.Checkbox)
        assert.is_nil(sb.List)
        assert.is_nil(sb.EmbedCanvas)
        assert.is_nil(sb.BorderGroup)
    end)

    it("store/defaults bindings resolve nested values and defaults", function()
        local profile = {
            root = {
                enabled = true,
            },
        }
        local defaults = {
            root = {
                enabled = false,
            },
        }
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local sb = lsb.New({
            name = "Store Binding",
            store = function()
                return profile
            end,
            defaults = function()
                return defaults
            end,
            onChanged = function() end,
        })

        local binding = sb._adapter:resolve("root.enabled")
        assert.are.equal(true, binding.get())
        assert.are.equal(false, binding.default)

        binding.set(false)
        assert.are.equal(false, profile.root.enabled)
    end)

    it("registers canonical raw row tables without public helper constructors", function()
        local profile = {
            general = {
                enabled = true,
                threshold = 5,
            },
        }
        local defaults = {
            general = {
                enabled = false,
                threshold = 0,
            },
        }
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local sb = lsb.New({
            name = "Phase 2",
            store = function()
                return profile
            end,
            defaults = function()
                return defaults
            end,
            onChanged = function() end,
            sections = {
                {
                    key = "general",
                    name = "General",
                    pages = {
                        {
                            key = "main",
                            rows = {
                                { id = "enabled", type = "checkbox", path = "general.enabled", name = "Enable" },
                                {
                                    id = "threshold",
                                    type = "slider",
                                    path = "general.threshold",
                                    name = "Threshold",
                                    min = 0,
                                    max = 10,
                                    step = 1,
                                    formatValue = function(value)
                                        return tostring(value)
                                    end,
                                },
                            },
                        },
                    },
                },
            },
        })

        assert.has_no.errors(function()
            local page = sb:GetPage("general", "main")
            assert.is_table(page)
            assert.are.equal("Phase 2.General", page:GetId())
        end)
    end)

    it("fails early when a raw path-bound row is registered without a path adapter", function()
        local lsb = LibStub("LibSettingsBuilder-1.0")
        local ok, err = pcall(function()
            lsb.New({
                name = "Phase 2 Invalid",
                onChanged = function() end,
                sections = {
                    {
                        key = "general",
                        name = "General",
                        pages = {
                            {
                                key = "main",
                                rows = {
                                    { type = "checkbox", path = "general.enabled", name = "Enable" },
                                },
                            },
                        },
                    },
                },
            })
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):find("requires store/defaults on the builder", 1, true))
    end)
end)
