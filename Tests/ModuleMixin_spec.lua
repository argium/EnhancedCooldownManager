-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("FrameMixin.GetModuleConfig", function()
    local originalGlobals
    local FrameMixin
    local ns

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({})
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
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

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        -- ns.GetGlobalConfig is defined in ECM.lua; stub it here since we only load BarMixin.lua
        ns.GetGlobalConfig = function()
            local db = ns.Addon and ns.Addon.db
            local profile = db and db.profile
            return profile and profile[ns.Constants.CONFIG_SECTION_GLOBAL]
        end

        ns.FrameUtil = {}
        _G.LibStub = function()
            return {
                AddFrame = function() end,
                AddFrameSettings = function() end,
                GetActiveLayoutName = function()
                    return "Default"
                end,
                RegisterCallback = function() end,
            }
        end
        ns.Runtime = { ScheduleLayoutUpdate = function() end }
        ns.DebugAssert = function() end
        ns.EditMode = nil

        TestHelpers.LoadChunk("BarMixin.lua", "Unable to load BarMixin.lua")(nil, ns)
        FrameMixin = assert(ns.BarMixin, "BarMixin did not initialize")
    end)

    it("Proto exposes GetModuleConfig", function()
        assert.is_function(FrameMixin.FrameProto.GetModuleConfig)
    end)

    it("GetModuleConfig returns live profile tables", function()
        local target = { _configKey = "powerBar" }
        setmetatable(target, { __index = FrameMixin.FrameProto })

        assert.are.equal(ns.Addon.db.profile.powerBar, target:GetModuleConfig())

        ns.Addon.db.profile.powerBar.enabled = false
        assert.is_false(target:GetModuleConfig().enabled)
    end)

    it("GetModuleConfig returns nil when profile is missing", function()
        local target = { _configKey = "missing" }
        setmetatable(target, { __index = FrameMixin.FrameProto })

        assert.is_nil(target:GetModuleConfig())
    end)
end)
