-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ProfileOptions getters/setters/defaults", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings, profileCategory, initializers, refreshCalls

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
        refreshCalls = {}
        SB.RefreshCategory = function(category)
            refreshCalls[#refreshCalls + 1] = category
        end

        -- Profile module needs import/export stubs
        ns.ImportExport = {
            ExportCurrentProfile = function() return "exported_string" end,
        }
        ns.Addon.ShowImportDialog = function() end
        ns.Addon.ShowExportDialog = function() end
        ns.Addon.Print = function() end

        settings = TestHelpers.CollectSettings(function()
            TestHelpers.LoadChunk("UI/ProfileOptions.lua", "ProfileOptions")(nil, ns)
            ns.OptionsSections.Profile.RegisterSettings(SB)
        end)
        profileCategory = SB._subcategories[ns.L["PROFILES"]]
        initializers = SB._layouts[profileCategory]._initializers
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
        it("setter refreshes the category", function()
            settings["ECM_ProfileSwitch"]:SetValue("Other")
            assert.are.same({ profileCategory }, refreshCalls)
        end)
        it("uses the localized New Profile row label", function()
            local newProfileButton = assert(TestHelpers.FindButtonInitializer(initializers, ns.L["NEW_PROFILE"]))

            assert.are.equal(ns.L["NEW_PROFILE"], newProfileButton._name)
        end)
        it("prompts for a profile name then switches to it", function()
            local switched
            ns.Addon.db.SetProfile = function(_, value) switched = value end

            local getShown = TestHelpers.InstallPopupAutoAccept("MyCustomProfile")

            TestHelpers.FindButtonInitializer(initializers, ns.L["NEW_PROFILE"])._onClick()

            assert.are.equal("ECM_NEW_PROFILE", getShown())
            assert.are.equal("MyCustomProfile", switched)
            assert.are.same({ profileCategory, profileCategory }, refreshCalls)
        end)
    end)

    describe("copy profile picker", function()
        it("setting exists", function()
            assert.is_not_nil(settings["ECM_ProfileCopy"])
        end)
        it("defaults to the first available profile when Default is unavailable", function()
            assert.are.equal("Other", settings["ECM_ProfileCopy"]:GetValue())
        end)
        it("keeps the picker row label", function()
            assert.are.equal(ns.L["COPY_FROM"], settings["ECM_ProfileCopy"]._name)
        end)
        it("options do not include a blank entry", function()
            local options = settings["ECM_ProfileCopy"]._optionsGen()
            assert.same({ value = "Other", label = "Other" }, options[1])
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
        it("defaults to the first available profile when Default is unavailable", function()
            assert.are.equal("Other", settings["ECM_ProfileDelete"]:GetValue())
        end)
        it("keeps the picker row label", function()
            assert.are.equal(ns.L["DELETE_PROFILE"], settings["ECM_ProfileDelete"]._name)
        end)
        it("options do not include a blank entry", function()
            local options = settings["ECM_ProfileDelete"]._optionsGen()
            assert.same({ value = "Other", label = "Other" }, options[1])
        end)
        it("setter updates transient selection", function()
            settings["ECM_ProfileDelete"]:SetValue("Other")
            assert.are.equal("Other", settings["ECM_ProfileDelete"]:GetValue())
        end)
    end)

    describe("profile action buttons", function()
        it("uses the localized Copy row label", function()
            local copyButton = assert(TestHelpers.FindButtonInitializer(initializers, ns.L["COPY"]))

            assert.are.equal(ns.L["COPY"], copyButton._name)
        end)

        it("uses the localized Delete row label", function()
            local deleteButton = assert(TestHelpers.FindButtonInitializer(initializers, ns.L["DELETE"]))

            assert.are.equal(ns.L["DELETE"], deleteButton._name)
        end)

        it("Copy shows a confirmation dialog before copying", function()
            settings["ECM_ProfileCopy"]:SetValue("Other")
            local getShown = TestHelpers.InstallPopupAutoAccept()
            local copied
            ns.Addon.db.CopyProfile = function(_, p) copied = p end

            TestHelpers.FindButtonInitializer(initializers, ns.L["COPY"])._onClick()

            assert.are.equal("ECM_CONFIRM_COPY_PROFILE", getShown())
            assert.are.equal("Other", copied)
            assert.are.same({ profileCategory }, refreshCalls)
        end)

        it("Copy does nothing when selection is empty", function()
            local copied = false
            ns.Addon.db.CopyProfile = function() copied = true end
            local current = ns.Addon.db:GetCurrentProfile()
            ns.Addon.db.GetProfiles = function()
                return { current }
            end
            settings["ECM_ProfileCopy"]:SetValue("")

            TestHelpers.FindButtonInitializer(initializers, ns.L["COPY"])._onClick()

            assert.is_false(copied)
        end)

        it("Delete shows a confirmation dialog before deleting", function()
            settings["ECM_ProfileDelete"]:SetValue("Other")
            local getShown = TestHelpers.InstallPopupAutoAccept()
            local deleted
            ns.Addon.db.DeleteProfile = function(_, p) deleted = p end

            TestHelpers.FindButtonInitializer(initializers, ns.L["DELETE"])._onClick()

            assert.are.equal("ECM_CONFIRM_DELETE_PROFILE", getShown())
            assert.are.equal("Other", deleted)
            assert.are.same({ profileCategory }, refreshCalls)
        end)

        it("Delete does nothing when selection is empty", function()
            local deleted = false
            ns.Addon.db.DeleteProfile = function() deleted = true end
            local current = ns.Addon.db:GetCurrentProfile()
            ns.Addon.db.GetProfiles = function()
                return { current }
            end
            settings["ECM_ProfileDelete"]:SetValue("")

            TestHelpers.FindButtonInitializer(initializers, ns.L["DELETE"])._onClick()

            assert.is_false(deleted)
        end)
    end)

    describe("reset profile", function()
        it("calls db:ResetProfile", function()
            local reset = false
            ns.Addon.db.ResetProfile = function() reset = true end

            TestHelpers.FindButtonInitializer(initializers, ns.L["RESET_PROFILE_BUTTON"])._onClick()

            assert.is_true(reset)
        end)
    end)

    describe("import", function()
        it("opens import dialog when out of combat", function()
            _G.InCombatLockdown = function() return false end
            local opened = false
            ns.Addon.ShowImportDialog = function() opened = true end

            TestHelpers.FindButtonInitializer(initializers, ns.L["IMPORT"])._onClick()

            assert.is_true(opened)
        end)

        it("blocks import during combat", function()
            _G.InCombatLockdown = function() return true end
            local opened = false
            local printed
            ns.Addon.ShowImportDialog = function() opened = true end
            ns.Print = function(msg) printed = msg end

            TestHelpers.FindButtonInitializer(initializers, ns.L["IMPORT"])._onClick()

            assert.is_false(opened)
            assert.are.equal(ns.L["CANNOT_IMPORT_IN_COMBAT"], printed)
        end)
    end)

    describe("export", function()
        it("opens export dialog on success", function()
            local exportedWith
            ns.Addon.ShowExportDialog = function(_, str) exportedWith = str end

            TestHelpers.FindButtonInitializer(initializers, ns.L["EXPORT"])._onClick()

            assert.are.equal("exported_string", exportedWith)
        end)

        it("prints error when export fails", function()
            ns.ImportExport.ExportCurrentProfile = function() return nil, "codec broke" end
            local printed
            ns.Print = function(msg) printed = msg end

            TestHelpers.FindButtonInitializer(initializers, ns.L["EXPORT"])._onClick()

            assert.are.equal(string.format(ns.L["EXPORT_FAILED"], "codec broke"), printed)
        end)

        it("prints fallback error when export fails with nil reason", function()
            ns.ImportExport.ExportCurrentProfile = function() return nil end
            local printed
            ns.Print = function(msg) printed = msg end

            TestHelpers.FindButtonInitializer(initializers, ns.L["EXPORT"])._onClick()

            assert.are.equal(string.format(ns.L["EXPORT_FAILED"], "Unknown error"), printed)
        end)
    end)
end)
