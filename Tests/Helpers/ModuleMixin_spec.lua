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

        -- ECM.GetGlobalConfig is defined in ECM.lua; stub it here since we only load ModuleMixin.lua
        ECM.GetGlobalConfig = function()
            local db = ns.Addon and ns.Addon.db
            local profile = db and db.profile
            return profile and profile[ECM.Constants.CONFIG_SECTION_GLOBAL]
        end

        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")(nil, ns)
        ModuleMixin = assert(ECM.ModuleMixin, "ModuleMixin did not initialize")
    end)

    it("Proto exposes GetModuleConfig", function()
        assert.is_function(ModuleMixin.Proto.GetModuleConfig)
    end)

    it("GetModuleConfig returns live profile tables", function()
        local target = { _configKey = "powerBar" }
        setmetatable(target, { __index = ModuleMixin.Proto })

        assert.are.equal(ns.Addon.db.profile.powerBar, target:GetModuleConfig())

        ns.Addon.db.profile.powerBar.enabled = false
        assert.is_false(target:GetModuleConfig().enabled)
    end)

    it("GetModuleConfig returns nil when profile is missing", function()
        local target = { _configKey = "missing" }
        setmetatable(target, { __index = ModuleMixin.Proto })

        assert.is_nil(target:GetModuleConfig())
    end)
end)
