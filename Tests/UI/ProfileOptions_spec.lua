-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ProfileOptions getters/setters/defaults", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals(TestHelpers.OPTIONS_GLOBALS)
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        TestHelpers.SetupOptionsGlobals()
        profile, defaults = TestHelpers.MakeOptionsProfile()
        SB, ns = TestHelpers.SetupOptionsEnv(profile, defaults)

        -- Profile module needs import/export stubs
        ECM.ImportExport = {
            ExportCurrentProfile = function() return "exported_string" end,
        }
        ns.Addon.ShowImportDialog = function() end
        ns.Addon.ShowExportDialog = function() end
        ns.Addon.Print = function() end

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ProfileOptions.lua", "ProfileOptions")(nil, ns)
            ns.OptionsSections.Profile.RegisterSettings(SB)
        end)
    end)

    describe("switch profile", function()
        it("getter returns current profile", function()
            assert.are.equal("Default", settings["ECM_ProfileSwitch"]:GetValue())
        end)
        it("setter calls db:SetProfile", function()
            local called
            ns.Addon.db.SetProfile = function(_, value) called = value end
            settings["ECM_ProfileSwitch"]:SetValue("Other")
            assert.are.equal("Other", called)
        end)
    end)

    describe("copy profile picker", function()
        it("setting exists", function()
            assert.is_not_nil(settings["ECM_ProfileCopy"])
        end)
        it("getter returns empty by default", function()
            assert.are.equal("", settings["ECM_ProfileCopy"]:GetValue())
        end)
        it("setter updates transient selection", function()
            settings["ECM_ProfileCopy"]:SetValue("Other")
            assert.are.equal("Other", settings["ECM_ProfileCopy"]:GetValue())
        end)
    end)

    describe("delete profile picker", function()
        it("setting exists", function()
            assert.is_not_nil(settings["ECM_ProfileDelete"])
        end)
        it("getter returns empty by default", function()
            assert.are.equal("", settings["ECM_ProfileDelete"]:GetValue())
        end)
        it("setter updates transient selection", function()
            settings["ECM_ProfileDelete"]:SetValue("Other")
            assert.are.equal("Other", settings["ECM_ProfileDelete"]:GetValue())
        end)
    end)
end)
