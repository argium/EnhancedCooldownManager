-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ProfileOptions getters/setters/defaults", function()
    local originalGlobals
    local profile, defaults, SB, ns, settings, profileCategory, initializers

    local function findButton(buttonText)
        for _, initializer in ipairs(initializers) do
            if initializer._type == "button" and initializer._buttonText == buttonText then
                return initializer
            end
        end
    end

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
        profileCategory = SB._subcategories[ECM.L["PROFILES"]]
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
        it("removes the New Profile button row label", function()
            local newProfileButton = assert(findButton(ECM.L["NEW_PROFILE"]))

            assert.are.equal("", newProfileButton._name)
        end)
    end)

    describe("copy profile picker", function()
        it("setting exists", function()
            assert.is_not_nil(settings["ECM_ProfileCopy"])
        end)
        it("getter returns empty by default", function()
            assert.are.equal("", settings["ECM_ProfileCopy"]:GetValue())
        end)
        it("keeps the picker row label", function()
            assert.are.equal(ECM.L["COPY_FROM"], settings["ECM_ProfileCopy"]._name)
        end)
        it("options include an explicit blank entry", function()
            local options = settings["ECM_ProfileCopy"]._optionsGen()
            assert.same({ value = "", label = "" }, options[1])
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
        it("keeps the picker row label", function()
            assert.are.equal(ECM.L["DELETE_PROFILE"], settings["ECM_ProfileDelete"]._name)
        end)
        it("options include an explicit blank entry", function()
            local options = settings["ECM_ProfileDelete"]._optionsGen()
            assert.same({ value = "", label = "" }, options[1])
        end)
        it("setter updates transient selection", function()
            settings["ECM_ProfileDelete"]:SetValue("Other")
            assert.are.equal("Other", settings["ECM_ProfileDelete"]:GetValue())
        end)
    end)

    describe("profile action buttons", function()
        it("removes the Copy button row label", function()
            local copyButton = assert(findButton(ECM.L["COPY"]))

            assert.are.equal("", copyButton._name)
        end)

        it("disables Copy until a source profile is selected", function()
            local copyButton = assert(findButton(ECM.L["COPY"]))

            assert.is_false(copyButton._enabled)
            assert.is_false(copyButton:EvaluateModifyPredicates())

            settings["ECM_ProfileCopy"]:SetValue("Other")

            assert.is_true(copyButton:EvaluateModifyPredicates())
            assert.is_true(copyButton._enabled)

            settings["ECM_ProfileCopy"]:SetValue("")

            assert.is_false(copyButton._enabled)
            assert.is_false(copyButton:EvaluateModifyPredicates())
        end)

        it("removes the Delete button row label", function()
            local deleteButton = assert(findButton(ECM.L["DELETE"]))

            assert.are.equal("", deleteButton._name)
        end)

        it("disables Delete until a target profile is selected", function()
            local deleteButton = assert(findButton(ECM.L["DELETE"]))

            assert.is_false(deleteButton._enabled)
            assert.is_false(deleteButton:EvaluateModifyPredicates())

            settings["ECM_ProfileDelete"]:SetValue("Other")

            assert.is_true(deleteButton:EvaluateModifyPredicates())
            assert.is_true(deleteButton._enabled)

            settings["ECM_ProfileDelete"]:SetValue("")

            assert.is_false(deleteButton._enabled)
            assert.is_false(deleteButton:EvaluateModifyPredicates())
        end)
    end)
end)
