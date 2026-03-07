-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("FrameMixin", function()
    local originalGlobals
    local FrameUtil
    local fakeTime

    local getCalls = TestHelpers.getCalls
    local color = TestHelpers.color
    local makeFrame = TestHelpers.makeFrame
    local makeTexture = TestHelpers.makeTexture

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM", "ColorUtil", "C_Timer", "GetTime", "UIParent", "issecretvalue",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        fakeTime = 0

        _G.ECM = {}
        _G.ColorUtil = { AreEqual = function(a, b)
            if a == nil and b == nil then return true end
            if a == nil or b == nil then return false end
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end }
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then error(message or "ECM.DebugAssert failed") end
        end
        _G.C_Timer = { After = function(_, callback) callback() end }
        _G.GetTime = function() return fakeTime end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.issecretvalue = function() return false end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()
        FrameUtil = assert(ECM.FrameUtil, "FrameUtil module did not initialize")
    end)

    describe("UpdateLayout", function()
        local function makeModule(opts)
            local anchor = opts.anchor or makeFrame({ name = "Anchor" })
            local innerFrame = opts.innerFrame or makeFrame({ shown = opts.shown ~= false })
            innerFrame.Background = makeTexture()

            local selfObj = {
                Name = opts.name or "TestModule",
                InnerFrame = innerFrame,
                _lastUpdate = 0,
                ShouldShow = function() return opts.shouldShow end,
                CalculateLayoutParams = function()
                    return {
                        mode = ECM.Constants.ANCHORMODE_CHAIN,
                        anchor = anchor,
                        anchorPoint = "TOPLEFT",
                        anchorRelativePoint = "BOTTOMLEFT",
                        offsetX = 0, offsetY = 0,
                        height = opts.height or 20,
                    }
                end,
                GetGlobalConfig = function() return { barBgColor = color(0, 0, 0, 0.5), updateFrequency = 0 } end,
                GetModuleConfig = function() return { bgColor = color(0, 0, 0, 0.5) } end,
                Refresh = function() end,
            }

            function selfObj:UpdateLayout(why)
                if not self:ShouldShow() then self.InnerFrame:Hide(); return false end
                if not self.InnerFrame:IsShown() then self.InnerFrame:Show() end
                local params = self:CalculateLayoutParams()
                if params.height then FrameUtil.LazySetHeight(self.InnerFrame, params.height) end
                if params.width then FrameUtil.LazySetWidth(self.InnerFrame, params.width) end
                local mc = self:GetModuleConfig()
                local gc = self:GetGlobalConfig()
                local bgColor = (mc and mc.bgColor) or (gc and gc.barBgColor)
                if bgColor then FrameUtil.LazySetBackgroundColor(self.InnerFrame, bgColor) end
                self:ThrottledRefresh("UpdateLayout(" .. (why or "") .. ")")
                return true
            end
            function selfObj:ThrottledRefresh(why)
                local gc = self:GetGlobalConfig()
                local freq = (gc and gc.updateFrequency) or ECM.Constants.DEFAULT_REFRESH_FREQUENCY
                if GetTime() - (self._lastUpdate or 0) < freq then return false end
                self:Refresh(why)
                self._lastUpdate = GetTime()
                return true
            end
            return selfObj
        end

        it("re-hides a frame that was externally shown while ShouldShow is false", function()
            local mod = makeModule({ shouldShow = false, shown = true })

            mod:UpdateLayout("initial")
            assert.is_false(mod.InnerFrame:IsShown())
            assert.are.equal(1, getCalls(mod.InnerFrame, "Hide"))

            mod.InnerFrame:Show()

            mod:UpdateLayout("re-check")
            assert.is_false(mod.InnerFrame:IsShown())
            assert.are.equal(2, getCalls(mod.InnerFrame, "Hide"))
        end)

        it("re-applies height via lazy setter when externally mutated", function()
            local mod = makeModule({ shouldShow = true })

            mod:UpdateLayout("initial")
            assert.are.equal(20, mod.InnerFrame:GetHeight())

            mod.InnerFrame:SetHeight(999)
            mod:UpdateLayout("re-check")
            assert.are.equal(20, mod.InnerFrame:GetHeight())
        end)

        it("shows a hidden frame when ShouldShow becomes true", function()
            local mod = makeModule({ shouldShow = false, shown = true })

            mod:UpdateLayout("hide")
            assert.is_false(mod.InnerFrame:IsShown())

            mod.ShouldShow = function() return true end
            mod:UpdateLayout("show")
            assert.is_true(mod.InnerFrame:IsShown())
        end)
    end)
end)
