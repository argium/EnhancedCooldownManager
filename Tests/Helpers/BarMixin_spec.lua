-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("BarMixin", function()
    local originalGlobals
    local BarMixin

    local makeFrame = TestHelpers.makeFrame
    local makeTexture = TestHelpers.makeTexture

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "C_Timer",
            "GetTime",
            "UIParent",
            "CreateFrame",
            "issecretvalue",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        _G.ECM = {}
        _G.ECM.ColorUtil = {
            AreEqual = function(a, b)
                if a == nil and b == nil then
                    return true
                end
                if a == nil or b == nil then
                    return false
                end
                return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
            end,
        }
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then
                error(message or "ECM.DebugAssert failed")
            end
        end
        _G.ECM.Log = function() end
        _G.ECM.PixelSnap = function(v)
            return math.floor(v + 0.5)
        end
        _G.C_Timer = {
            After = function(_, callback)
                callback()
            end,
        }
        _G.GetTime = function()
            return 0
        end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.issecretvalue = function()
            return false
        end

        -- Minimal CreateFrame stub for FrameMixin:CreateFrame
        _G.CreateFrame = function(frameType, name, parent, template)
            local f = makeFrame({ name = name })
            f.CreateTexture = function()
                return makeTexture()
            end
            f.CreateFontString = function()
                local fs = makeTexture()
                fs.SetText = function() end
                fs.SetJustifyH = function() end
                fs.SetJustifyV = function() end
                fs.SetPoint = function() end
                return fs
            end
            f.SetFrameStrata = function() end
            f.SetFrameLevel = function() end
            f.GetFrameLevel = function()
                return 1
            end
            f.SetAllPoints = function() end
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
                IsEnabled = function()
                    return true
                end,
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
                "EnsureTicks",
                "HideAllTicks",
                "LayoutResourceTicks",
                "LayoutValueTicks",
                "GetStatusBarValues",
                "GetStatusBarColor",
                "Refresh",
                "CreateFrame",
            }
            for _, name in ipairs(expectedMethods) do
                assert.is_function(mod[name], "expected method " .. name .. " on module")
            end
        end)

        it("does not overwrite pre-existing methods on the module", function()
            local customRefresh = function()
                return "custom"
            end
            local mod = makeModule({ Refresh = customRefresh })
            BarMixin.AddMixin(mod, "TestBar")

            assert.are.equal(customRefresh, mod.Refresh)
        end)

        it("sets _lastUpdate from GetTime", function()
            _G.GetTime = function()
                return 42
            end
            local mod = makeModule()
            BarMixin.AddMixin(mod, "TestBar")

            assert.are.equal(42, mod._lastUpdate)
        end)

        it("creates InnerFrame with StatusBar for modules without custom CreateFrame", function()
            local mod = makeModule()
            BarMixin.AddMixin(mod, "TestBar")

            assert.is_not_nil(mod.InnerFrame, "InnerFrame should exist")
            assert.is_not_nil(mod.InnerFrame.StatusBar, "InnerFrame.StatusBar should exist")
        end)
    end)

    describe("tick helpers", function()
        local function makeTick()
            return {
                shown = false,
                points = {},
                size = nil,
                color = nil,
                Show = function(self)
                    self.shown = true
                end,
                Hide = function(self)
                    self.shown = false
                end,
                IsShown = function(self)
                    return self.shown
                end,
                ClearAllPoints = function(self)
                    self.points = {}
                end,
                SetPoint = function(self, point, relativeTo, relativePoint, x, y)
                    self.points[#self.points + 1] = { point, relativeTo, relativePoint, x, y }
                end,
                SetSize = function(self, width, height)
                    self.size = { width, height }
                end,
                SetColorTexture = function(self, r, g, b, a)
                    self.color = { r, g, b, a }
                end,
            }
        end

        local function makeParentFrame(created)
            local frame = makeFrame({ width = 100, height = 12 })
            function frame:CreateTexture()
                local tick = makeTick()
                created[#created + 1] = tick
                return tick
            end
            return frame
        end

        it("EnsureTicks creates new ticks and hides extras on reuse", function()
            local created = {}
            local mod = {}
            local parentFrame = makeParentFrame(created)

            BarMixin.EnsureTicks(mod, 3, parentFrame)
            assert.are.equal(3, #created)
            assert.is_true(mod.tickPool[1]:IsShown())
            assert.is_true(mod.tickPool[2]:IsShown())
            assert.is_true(mod.tickPool[3]:IsShown())

            BarMixin.EnsureTicks(mod, 1, parentFrame)
            assert.are.equal(3, #created)
            assert.is_true(mod.tickPool[1]:IsShown())
            assert.is_false(mod.tickPool[2]:IsShown())
            assert.is_false(mod.tickPool[3]:IsShown())
        end)

        it("HideAllTicks hides all ticks in a custom pool", function()
            local mod = {
                customPool = { makeTick(), makeTick() },
            }
            mod.customPool[1]:Show()
            mod.customPool[2]:Show()

            BarMixin.HideAllTicks(mod, "customPool")

            assert.is_false(mod.customPool[1]:IsShown())
            assert.is_false(mod.customPool[2]:IsShown())
        end)

        it("LayoutResourceTicks positions shown ticks evenly", function()
            local mod = {
                InnerFrame = makeFrame({ width = 100, height = 10 }),
                tickPool = { makeTick(), makeTick(), makeTick() },
            }
            for _, tick in ipairs(mod.tickPool) do
                tick:Show()
            end

            BarMixin.LayoutResourceTicks(mod, 4, { r = 1, g = 0.5, b = 0, a = 0.75 }, 2, "tickPool")

            assert.are.equal(25, mod.tickPool[1].points[1][4])
            assert.are.equal(50, mod.tickPool[2].points[1][4])
            assert.are.equal(75, mod.tickPool[3].points[1][4])
            assert.same({ 2, 10 }, mod.tickPool[1].size)
            assert.same({ 1, 0.5, 0, 0.75 }, mod.tickPool[1].color)
        end)

        it("LayoutValueTicks hides out-of-range ticks and applies defaults", function()
            local statusBar = makeFrame({ width = 100 })
            local mod = {
                InnerFrame = makeFrame({ width = 100, height = 8 }),
                tickPool = { makeTick(), makeTick(), makeTick(), makeTick() },
            }

            BarMixin.LayoutValueTicks(mod, statusBar, {
                { value = 25 },
                { value = 0 },
                { value = 100 },
                { value = 50, color = { r = 0, g = 1, b = 0, a = 1 }, width = 3 },
            }, 100, { r = 0, g = 0, b = 0, a = 0.5 }, 1, "tickPool")

            assert.is_true(mod.tickPool[1]:IsShown())
            assert.are.equal(25, mod.tickPool[1].points[1][4])
            assert.same({ 1, 8 }, mod.tickPool[1].size)
            assert.same({ 0, 0, 0, 0.5 }, mod.tickPool[1].color)

            assert.is_false(mod.tickPool[2]:IsShown())
            assert.is_false(mod.tickPool[3]:IsShown())

            assert.is_true(mod.tickPool[4]:IsShown())
            assert.are.equal(50, mod.tickPool[4].points[1][4])
            assert.same({ 3, 8 }, mod.tickPool[4].size)
            assert.same({ 0, 1, 0, 1 }, mod.tickPool[4].color)
        end)
    end)
end)
