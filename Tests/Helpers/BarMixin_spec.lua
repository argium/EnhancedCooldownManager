-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("BarMixin", function()
    local originalGlobals
    local BarMixin

    local makeFrame = TestHelpers.makeFrame
    local makeTexture = TestHelpers.makeTexture

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM", "ColorUtil", "C_Timer", "GetTime", "UIParent",
            "CreateFrame", "issecretvalue",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {}
        _G.ColorUtil = { AreEqual = function(a, b)
            if a == nil and b == nil then return true end
            if a == nil or b == nil then return false end
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end }
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then error(message or "ECM.DebugAssert failed") end
        end
        _G.ECM.Log = function() end
        _G.ECM.PixelSnap = function(v) return math.floor(v + 0.5) end
        _G.C_Timer = { After = function(_, callback) callback() end }
        _G.GetTime = function() return 0 end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.issecretvalue = function() return false end

        -- Minimal CreateFrame stub for FrameMixin:CreateFrame
        _G.CreateFrame = function(frameType, name, parent, template)
            local f = makeFrame({ name = name })
            f.CreateTexture = function() return makeTexture() end
            f.CreateFontString = function()
                local fs = makeTexture()
                fs.SetText = function() end
                fs.SetJustifyH = function() end
                fs.SetJustifyV = function() end
                return fs
            end
            f.SetFrameStrata = function() end
            f.SetFrameLevel = function() end
            f.GetFrameLevel = function() return 1 end
            f.SetMinMaxValues = function() end
            f.SetValue = function() end
            f.SetStatusBarTexture = function() end
            f.SetStatusBarColor = function() end
            return f
        end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        TestHelpers.LoadChunk("Helpers/ModuleMixin.lua", "Unable to load Helpers/ModuleMixin.lua")()
        TestHelpers.LoadChunk("Helpers/FrameMixin.lua", "Unable to load Helpers/FrameMixin.lua")()
        TestHelpers.LoadChunk("Helpers/BarMixin.lua", "Unable to load Helpers/BarMixin.lua")()

        BarMixin = assert(ECM.BarMixin, "BarMixin module did not initialize")
    end)

    describe("AddMixin", function()
        local function makeModule(overrides)
            local mod = {
                IsEnabled = function() return true end,
                GetGlobalConfig = function()
                    return { barHeight = 20, barBgColor = { r = 0, g = 0, b = 0, a = 0.5 } }
                end,
                GetModuleConfig = function()
                    return { bgColor = { r = 0, g = 0, b = 0, a = 0.5 } }
                end,
            }
            if overrides then
                for k, v in pairs(overrides) do
                    mod[k] = v
                end
            end
            return mod
        end

        it("copies BarMixin methods to the target module", function()
            local mod = makeModule()
            BarMixin.AddMixin(mod, "TestBar")

            local expectedMethods = {
                "EnsureTicks", "HideAllTicks", "LayoutResourceTicks",
                "LayoutValueTicks", "GetStatusBarValues", "GetStatusBarColor",
                "Refresh", "CreateFrame",
            }
            for _, name in ipairs(expectedMethods) do
                assert.is_function(mod[name], "expected method " .. name .. " on module")
            end
        end)

        it("does not overwrite pre-existing methods on the module", function()
            local customRefresh = function() return "custom" end
            local mod = makeModule({ Refresh = customRefresh })
            BarMixin.AddMixin(mod, "TestBar")

            assert.are.equal(customRefresh, mod.Refresh)
        end)

        it("sets _lastUpdate from GetTime", function()
            _G.GetTime = function() return 42 end
            local mod = makeModule()
            BarMixin.AddMixin(mod, "TestBar")

            assert.are.equal(42, mod._lastUpdate)
        end)
    end)
end)
