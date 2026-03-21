-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ModuleMixin", function()
    local originalGlobals
    local ModuleMixin
    local ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({ "ECM" })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {}
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")()

        ns = {
            Addon = {
                db = {
                    profile = {
                        global = { updateFrequency = 0.04 },
                        powerBar = { enabled = true },
                    },
                },
            },
        }

        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")(nil, ns)
        ModuleMixin = assert(ECM.ModuleMixin, "ModuleMixin did not initialize")
    end)

    it("AddMixin sets Name and camel-case config key", function()
        local target = {}

        ModuleMixin.AddMixin(target, "PowerBar")

        assert.are.equal("PowerBar", target.Name)
        assert.are.equal("powerBar", target._configKey)
        assert.is_function(target.GetGlobalConfig)
        assert.is_function(target.GetModuleConfig)
    end)

    it("GetGlobalConfig and GetModuleConfig return live profile tables", function()
        local target = {}
        ModuleMixin.AddMixin(target, "PowerBar")

        assert.are.equal(ns.Addon.db.profile.global, target:GetGlobalConfig())
        assert.are.equal(ns.Addon.db.profile.powerBar, target:GetModuleConfig())

        ns.Addon.db.profile.powerBar.enabled = false
        assert.is_false(target:GetModuleConfig().enabled)
    end)

    it("does not overwrite pre-existing methods", function()
        local existing = function()
            return "keep"
        end
        local target = {
            GetModuleConfig = existing,
        }

        ModuleMixin.AddMixin(target, "PowerBar")

        assert.are.equal(existing, target.GetModuleConfig)
    end)
end)
