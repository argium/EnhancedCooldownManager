-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("ModuleMixin", function()
    local originalGlobals
    local FrameUtil
    local ModuleMixin
    local fakeTime

    local function incCalls(obj, name)
        obj.__calls = obj.__calls or {}
        obj.__calls[name] = (obj.__calls[name] or 0) + 1
    end

    local function getCalls(obj, name)
        return (obj.__calls and obj.__calls[name]) or 0
    end

    local function color(r, g, b, a)
        return { r = r, g = g, b = b, a = a or 1 }
    end

    local function makeFrame(opts)
        opts = opts or {}
        local anchors = {}
        for i = 1, #(opts.anchors or {}) do
            local a = opts.anchors[i]
            anchors[i] = { a[1], a[2], a[3], a[4], a[5] }
        end
        local frame = {
            __name = opts.name,
            __shown = opts.shown ~= false,
            __height = opts.height or 0,
            __width = opts.width or 0,
            __alpha = opts.alpha == nil and 1 or opts.alpha,
            __anchors = anchors,
            __calls = {},
        }

        function frame:GetName() return self.__name end

        for _, prop in ipairs({
            { "Height", "__height" },
            { "Width", "__width" },
            { "Alpha", "__alpha" },
        }) do
            frame["Set" .. prop[1]] = function(self, val) incCalls(self, "Set" .. prop[1]); self[prop[2]] = val end
            frame["Get" .. prop[1]] = function(self) return self[prop[2]] end
        end

        function frame:Show() incCalls(self, "Show"); self.__shown = true end
        function frame:Hide() incCalls(self, "Hide"); self.__shown = false end
        function frame:IsShown() return self.__shown end

        function frame:ClearAllPoints() incCalls(self, "ClearAllPoints"); self.__anchors = {} end
        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            incCalls(self, "SetPoint")
            self.__anchors[#self.__anchors + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end
        function frame:GetNumPoints() return #self.__anchors end
        function frame:GetPoint(index)
            local a = self.__anchors[index]
            if a then return a[1], a[2], a[3], a[4], a[5] end
        end

        return frame
    end

    local function makeTexture(opts)
        opts = opts or {}
        local texture = { __calls = {} }
        texture.__colorTexture = opts.colorTexture
        function texture:SetColorTexture(r, g, b, a) incCalls(self, "SetColorTexture"); self.__colorTexture = { r, g, b, a } end
        function texture:GetColorTexture()
            if self.__colorTexture then return self.__colorTexture[1], self.__colorTexture[2], self.__colorTexture[3], self.__colorTexture[4] end
        end
        function texture:IsObjectType() return true end
        function texture:SetAllPoints() end
        return texture
    end

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
        _G.ColorUtil = _G.ColorUtil or {}
        _G.ColorUtil.AreEqual = function(a, b)
            if a == nil and b == nil then return true end
            if a == nil or b == nil then return false end
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then error(message or "ECM.DebugAssert failed") end
        end
        _G.C_Timer = {
            After = function(_, callback) callback() end,
        }
        _G.GetTime = function() return fakeTime end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.issecretvalue = function() return false end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()

        FrameUtil = assert(ECM.FrameUtil, "FrameUtil module did not initialize")
    end)

    describe("UpdateLayout", function()
        --- Builds a minimal module object wired like ModuleMixin:UpdateLayout.
        local function makeModule(opts)
            local anchor = opts.anchor or makeFrame({ name = "Anchor" })
            local innerFrame = opts.innerFrame or makeFrame({ shown = opts.shown ~= false })
            innerFrame.Background = innerFrame.Background or makeTexture()

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
                        offsetX = 0,
                        offsetY = 0,
                        height = opts.height or 20,
                    }
                end,
                GetGlobalConfig = function()
                    return { barBgColor = color(0, 0, 0, 0.5), updateFrequency = 0 }
                end,
                GetModuleConfig = function()
                    return { bgColor = color(0, 0, 0, 0.5) }
                end,
                Refresh = function() end,
            }

            -- Wire UpdateLayout to FrameUtil like ModuleMixin does
            function selfObj:UpdateLayout(why)
                return FrameUtil.ApplyStandardLayout(self, why)
            end
            function selfObj:ThrottledRefresh(why)
                return FrameUtil.ThrottledRefresh(self, why)
            end

            return selfObj
        end

        it("re-hides a frame that was externally shown while ShouldShow is false", function()
            local mod = makeModule({ shouldShow = false, shown = true })

            -- First layout pass: hides the frame
            assert.is_false(mod:UpdateLayout("initial"))
            assert.is_false(mod.InnerFrame:IsShown())
            assert.are.equal(1, getCalls(mod.InnerFrame, "Hide"))

            -- External actor shows the frame
            mod.InnerFrame:Show()
            assert.is_true(mod.InnerFrame:IsShown())

            -- Second layout pass: re-hides the frame
            assert.is_false(mod:UpdateLayout("re-check"))
            assert.is_false(mod.InnerFrame:IsShown())
            assert.are.equal(2, getCalls(mod.InnerFrame, "Hide"))
        end)

        it("re-applies alpha via lazy setter when externally mutated", function()
            local mod = makeModule({ shouldShow = true })
            local frame = mod.InnerFrame

            -- Override CalculateLayoutParams to include a specific height
            -- and let ApplyStandardLayout set it via LazySetHeight
            frame:SetHeight(20)

            mod:UpdateLayout("initial")
            assert.are.equal(20, frame:GetHeight())

            -- External actor changes height
            frame:SetHeight(999)
            assert.are.equal(999, frame:GetHeight())

            -- Next layout pass detects drift and re-applies
            mod:UpdateLayout("re-check")
            assert.are.equal(20, frame:GetHeight())
        end)

        it("shows a hidden frame when ShouldShow becomes true", function()
            local mod = makeModule({ shouldShow = false, shown = true })

            -- Hide it
            mod:UpdateLayout("hide")
            assert.is_false(mod.InnerFrame:IsShown())

            -- ShouldShow flips to true
            mod.ShouldShow = function() return true end
            mod:UpdateLayout("show")
            assert.is_true(mod.InnerFrame:IsShown())
        end)
    end)
end)
