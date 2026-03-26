-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

describe("FrameUtil", function()
    local originalGlobals
    local FrameUtil
    local scheduledTimers
    local fakeTime
    local secretValues

    local incCalls = TestHelpers.incCalls
    local getCalls = TestHelpers.getCalls
    local color = TestHelpers.color
    local makeRegion = TestHelpers.makeRegion
    local makeTexture = TestHelpers.makeTexture
    local makeFrame = TestHelpers.makeFrame
    local makeStatusBar = TestHelpers.makeStatusBar
    local makeBorder = TestHelpers.makeBorder
    local assertAnchor = TestHelpers.assertAnchor

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "ECM",
            "C_Timer",
            "GetTime",
            "UIParent",
            "issecretvalue",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        scheduledTimers = {}
        fakeTime = 0
        secretValues = {}

        _G.ECM = {}
        _G.ECM.ColorUtil = {}
        _G.ECM.ColorUtil.AreEqual = function(a, b)
            if a == nil and b == nil then
                return true
            end
            if a == nil or b == nil then
                return false
            end
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end
        _G.ECM.DebugAssert = function(condition, message)
            if not condition then
                error(message or "ECM.DebugAssert failed")
            end
        end
        _G.C_Timer = {
            After = function(delay, callback)
                scheduledTimers[#scheduledTimers + 1] = {
                    delay = delay,
                    callback = callback,
                }
            end,
        }
        _G.GetTime = function()
            return fakeTime
        end
        _G.UIParent = makeFrame({ name = "UIParent" })
        _G.issecretvalue = function(value)
            return secretValues[value] == true
        end

        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")()
        TestHelpers.LoadChunk("Helpers/FrameUtil.lua", "Unable to load Helpers/FrameUtil.lua")()

        FrameUtil = assert(ECM.FrameUtil, "FrameUtil module did not initialize")
    end)

    describe("buff bar inspection helpers", function()
        it("GetIconTexture and GetIconOverlay return matching texture regions by index", function()
            local texture1 = makeTexture({ textureFileID = 101 })
            local nonTexture = makeRegion("FontString")
            local texture3 = makeTexture({ textureFileID = 303 })
            local frame = {
                Icon = makeFrame({
                    regions = { texture1, nonTexture, texture3 },
                }),
            }

            assert.are.equal(texture1, FrameUtil.GetIconTexture(frame))
            assert.are.equal(texture3, FrameUtil.GetIconOverlay(frame))
        end)

        it("GetIconTexture and GetIconOverlay return nil when region type does not match", function()
            local frame = {
                Icon = makeFrame({
                    regions = { makeRegion("FontString"), makeRegion("FontString"), makeRegion("FontString") },
                }),
            }

            assert.is_nil(FrameUtil.GetIconTexture(frame))
            assert.is_nil(FrameUtil.GetIconOverlay(frame))
        end)

        it("GetIconTextureFileID returns the texture file id when available", function()
            local texture = makeTexture({ textureFileID = 777 })
            local frame = {
                Icon = makeFrame({
                    regions = { texture },
                }),
            }

            assert.are.equal(777, FrameUtil.GetIconTextureFileID(frame))
        end)

        it("GetIconTextureFileID returns nil when texture or getter is missing", function()
            local texture = makeTexture()
            texture.GetTextureFileID = nil
            local frame = {
                Icon = makeFrame({
                    regions = { texture },
                }),
            }

            assert.is_nil(FrameUtil.GetIconTextureFileID(frame))
        end)

        it("GetBarBackground discovers and caches the Blizzard bar background texture", function()
            local regionA = makeTexture({ atlas = "OtherAtlas" })
            local regionB = makeTexture({ atlas = "UI-HUD-CooldownManager-Bar-BG" })
            local statusBar = makeStatusBar({
                regions = { regionA, regionB },
            })

            local found = FrameUtil.GetBarBackground(statusBar)
            assert.are.equal(regionB, found)
            assert.are.equal(regionB, statusBar.__ecmBarBG)

            statusBar.GetRegions = function()
                error("should not rescan regions when cache is valid")
            end
            assert.are.equal(regionB, FrameUtil.GetBarBackground(statusBar))
        end)

        it("GetBarBackground accepts both atlas spellings and returns nil for invalid input", function()
            local region = makeTexture({ atlas = "UI-HUD-CoolDownManager-Bar-BG" })
            local statusBar = makeStatusBar({ regions = { region } })
            assert.are.equal(region, FrameUtil.GetBarBackground(statusBar))
            assert.is_nil(FrameUtil.GetBarBackground({}))
            assert.is_nil(FrameUtil.GetBarBackground(nil))
        end)
    end)

    describe("lazy setters", function()
        local lazySetScalarCases = {
            { fn = "LazySetHeight", opts = { height = 20 }, same = 20, diff = 25, setter = "SetHeight", getter = "GetHeight" },
            { fn = "LazySetWidth", opts = { width = 40 }, same = 40, diff = 55, setter = "SetWidth", getter = "GetWidth" },
            { fn = "LazySetAlpha", opts = { alpha = 0.5 }, same = 0.5, diff = 0.8, setter = "SetAlpha", getter = "GetAlpha" },
        }
        for _, case in ipairs(lazySetScalarCases) do
            it(case.fn .. " skips redundant calls and applies changes", function()
                local frame = makeFrame(case.opts)
                assert.is_false(FrameUtil[case.fn](frame, case.same))
                assert.are.equal(0, getCalls(frame, case.setter))
                assert.is_true(FrameUtil[case.fn](frame, case.diff))
                assert.are.equal(1, getCalls(frame, case.setter))
                assert.are.equal(case.diff, frame[case.getter](frame))
            end)
        end

        it("LazySetAnchors no-ops when the live anchor set already matches", function()
            local anchor = makeFrame({ name = "AnchorA" })
            local frame = makeFrame({
                anchors = {
                    { "TOPLEFT", anchor, "BOTTOMLEFT", 1, -2 },
                    { "TOPRIGHT", anchor, "BOTTOMRIGHT", 1, -2 },
                },
            })
            local anchors = {
                { "TOPLEFT", anchor, "BOTTOMLEFT", 1, -2 },
                { "TOPRIGHT", anchor, "BOTTOMRIGHT", 1, -2 },
            }

            assert.is_false(FrameUtil.LazySetAnchors(frame, anchors))
            assert.are.equal(0, getCalls(frame, "ClearAllPoints"))
            assert.are.equal(0, getCalls(frame, "SetPoint"))
        end)

        it("LazySetAnchors reapplies anchors when the live anchors differ", function()
            local anchorA = makeFrame({ name = "AnchorA" })
            local anchorB = makeFrame({ name = "AnchorB" })
            local frame = makeFrame({
                anchors = {
                    { "TOPLEFT", anchorA, "BOTTOMLEFT", 0, 0 },
                },
            })
            local desired = {
                { "TOPLEFT", anchorB, "BOTTOMLEFT", 2, -3 },
                { "TOPRIGHT", anchorB, "BOTTOMRIGHT", 2, -3 },
            }

            assert.is_true(FrameUtil.LazySetAnchors(frame, desired))
            assert.are.equal(1, getCalls(frame, "ClearAllPoints"))
            assert.are.equal(2, getCalls(frame, "SetPoint"))
            assert.are.equal(2, frame:GetNumPoints())
            assertAnchor(frame, 1, "TOPLEFT", anchorB, "BOTTOMLEFT", 2, -3)
            assertAnchor(frame, 2, "TOPRIGHT", anchorB, "BOTTOMRIGHT", 2, -3)
        end)

        it("LazySetAnchors reapplies anchors when frame anchor getters are unavailable", function()
            local frame = {
                __calls = {},
                ClearAllPoints = function(self) incCalls(self, "ClearAllPoints") end,
                SetPoint = function(self) incCalls(self, "SetPoint") end,
            }
            local anchors = {
                { "CENTER", UIParent, "CENTER", 0, 0 },
            }

            assert.is_true(FrameUtil.LazySetAnchors(frame, anchors))
            assert.is_true(FrameUtil.LazySetAnchors(frame, anchors))
            assert.are.equal(2, getCalls(frame, "ClearAllPoints"))
            assert.are.equal(2, getCalls(frame, "SetPoint"))
        end)

        it("LazySetAnchors reuses cached anchors when live point strings are secret", function()
            local anchor = makeFrame({ name = "AnchorA" })
            local frame = makeFrame({
                anchors = {
                    { "TOPLEFT", anchor, "BOTTOMLEFT", 4, -5 },
                },
            })
            local desired = {
                { "TOPLEFT", anchor, "BOTTOMLEFT", 4, -5 },
            }
            local secretPoint = {}
            local secretRelativePoint = {}
            secretValues[secretPoint] = true
            secretValues[secretRelativePoint] = true

            frame.GetPoint = function(self, index)
                local a = self.__anchors[index]
                if not a then return nil end
                return secretPoint, a[2], secretRelativePoint, a[4], a[5]
            end

            assert.is_true(FrameUtil.LazySetAnchors(frame, desired))
            assert.are.equal(1, getCalls(frame, "ClearAllPoints"))
            assert.are.equal(1, getCalls(frame, "SetPoint"))

            assert.is_false(FrameUtil.LazySetAnchors(frame, desired))
            assert.are.equal(1, getCalls(frame, "ClearAllPoints"))
            assert.are.equal(1, getCalls(frame, "SetPoint"))
        end)

        it("LazySetBackgroundColor reads live texture color before writing", function()
            local bg = makeTexture({ colorTexture = { 0.1, 0.2, 0.3, 0.4 } })
            local frame = {
                Background = bg,
            }

            assert.is_false(FrameUtil.LazySetBackgroundColor(frame, color(0.1, 0.2, 0.3, 0.4)))
            assert.are.equal(0, getCalls(bg, "SetColorTexture"))

            assert.is_true(FrameUtil.LazySetBackgroundColor(frame, color(0.2, 0.3, 0.4, 0.5)))
            assert.are.equal(1, getCalls(bg, "SetColorTexture"))
        end)

        it("LazySetBackgroundColor no-ops when no background texture exists", function()
            local frame = {}
            local c = color(0.3, 0.3, 0.3, 0.8)

            assert.is_false(FrameUtil.LazySetBackgroundColor(frame, c))
            assert.is_false(FrameUtil.LazySetBackgroundColor(frame, c))
        end)

        it("LazySetVertexColor reapplies every call when getters are unavailable", function()
            local texture = makeTexture({ vertexColor = { 0.5, 0.5, 0.5, 1 } })

            assert.is_false(FrameUtil.LazySetVertexColor(texture, color(0.5, 0.5, 0.5, 1)))
            assert.are.equal(0, getCalls(texture, "SetVertexColor"))

            texture.GetColorTexture = nil
            texture.GetVertexColor = nil

            assert.is_true(FrameUtil.LazySetVertexColor(texture, color(1, 0, 0, 1)))
            assert.is_true(FrameUtil.LazySetVertexColor(texture, color(1, 0, 0, 1)))
            assert.are.equal(2, getCalls(texture, "SetVertexColor"))
        end)

        it("LazySetStatusBarTexture no-ops when texture matches and applies when different", function()
            local bar = makeStatusBar({ texturePath = "TexA" })

            assert.is_false(FrameUtil.LazySetStatusBarTexture(bar, "TexA"))
            assert.are.equal(0, getCalls(bar, "SetStatusBarTexture"))

            assert.is_true(FrameUtil.LazySetStatusBarTexture(bar, "TexB"))
            assert.are.equal(1, getCalls(bar, "SetStatusBarTexture"))
            assert.are.equal("TexB", bar:GetStatusBarTexture():GetTexture())
        end)

        it("LazySetStatusBarColor no-ops when color matches and applies when different", function()
            local bar = makeStatusBar({ statusBarColor = { 0.2, 0.3, 0.4, 1 } })

            assert.is_false(FrameUtil.LazySetStatusBarColor(bar, 0.2, 0.3, 0.4))
            assert.are.equal(0, getCalls(bar, "SetStatusBarColor"))

            assert.is_true(FrameUtil.LazySetStatusBarColor(bar, 1, 0, 0, 0.9))
            assert.are.equal(1, getCalls(bar, "SetStatusBarColor"))
        end)

        it("LazySetBorder returns false when no border frame exists", function()
            assert.is_false(FrameUtil.LazySetBorder({}, {
                enabled = true,
                thickness = 2,
                color = color(1, 1, 1, 1),
            }))
        end)

        it("LazySetBorder applies enabled border settings", function()
            local frame = {
                Border = makeBorder({
                    shown = false,
                    backdrop = { edgeSize = 1 },
                    borderColor = { 0, 0, 0, 1 },
                }),
            }
            local cfg = {
                enabled = true,
                thickness = 3,
                color = color(0.7, 0.6, 0.5, 0.4),
            }

            assert.is_true(FrameUtil.LazySetBorder(frame, cfg))
            assert.are.equal(1, getCalls(frame.Border, "Show"))
            assert.are.equal(1, getCalls(frame.Border, "SetBackdrop"))
            assert.are.equal(1, getCalls(frame.Border, "ClearAllPoints"))
            assert.are.equal(2, getCalls(frame.Border, "SetPoint"))
            assert.are.equal(1, getCalls(frame.Border, "SetBackdropBorderColor"))
        end)

        it("LazySetBorder no-ops when live border state already matches desired config", function()
            local border = makeBorder({
                shown = true,
                backdrop = { edgeSize = 4 },
                borderColor = { 0.2, 0.3, 0.4, 0.5 },
            })
            local frame = {
                Border = border,
            }
            local cfg = {
                enabled = true,
                thickness = 4,
                color = color(0.2, 0.3, 0.4, 0.5),
            }

            assert.is_false(FrameUtil.LazySetBorder(frame, cfg))
            assert.are.equal(0, getCalls(border, "SetBackdrop"))
            assert.are.equal(0, getCalls(border, "SetPoint"))
            assert.are.equal(0, getCalls(border, "SetBackdropBorderColor"))
        end)

        it("LazySetBorder hides the border when disabled", function()
            local border = makeBorder({
                shown = true,
                backdrop = { edgeSize = 2 },
                borderColor = { 1, 1, 1, 1 },
            })
            local frame = { Border = border }
            local cfg = {
                enabled = false,
                thickness = 2,
                color = color(1, 1, 1, 1),
            }

            assert.is_true(FrameUtil.LazySetBorder(frame, cfg))
            assert.are.equal(1, getCalls(border, "Hide"))
            assert.is_false(border:IsShown())
        end)

        it("LazySetText reads live text before writing", function()
            local fontString = { __text = "Hello", __calls = {} }
            fontString.GetText = function(self) return self.__text end
            fontString.SetText = function(self, text) incCalls(self, "SetText"); self.__text = text end

            assert.is_false(FrameUtil.LazySetText(fontString, "Hello"))
            assert.are.equal(0, getCalls(fontString, "SetText"))

            assert.is_true(FrameUtil.LazySetText(fontString, "World"))
            assert.are.equal(1, getCalls(fontString, "SetText"))
        end)

        -- Edge case: scalar setters detect external mutation
        for _, case in ipairs({
            { fn = "LazySetHeight", initial = 20, target = 20, external = 25, setter = "SetHeight", getter = "GetHeight", opts = { height = 20 } },
            { fn = "LazySetWidth", initial = 40, target = 40, external = 50, setter = "SetWidth", getter = "GetWidth", opts = { width = 40 } },
            { fn = "LazySetAlpha", initial = 0.5, target = 0.5, external = 1.0, setter = "SetAlpha", getter = "GetAlpha", opts = { alpha = 0.5 } },
        }) do
            it(case.fn .. " re-applies after external mutation", function()
                local frame = makeFrame(case.opts)
                assert.is_false(FrameUtil[case.fn](frame, case.target))

                -- External actor changes the value
                frame[case.setter](frame, case.external)

                -- Next lazy call detects drift and re-applies
                assert.is_true(FrameUtil[case.fn](frame, case.target))
                assert.are.equal(case.target, frame[case.getter](frame))
            end)
        end

        -- Edge case: LazySetBackgroundColor falls back to GetVertexColor
        it("LazySetBackgroundColor falls back to GetVertexColor when GetColorTexture returns nil", function()
            local bg = makeTexture({ vertexColor = { 0.5, 0.6, 0.7, 1 } })
            bg.GetColorTexture = function() return nil end
            local frame = { Background = bg }

            assert.is_false(FrameUtil.LazySetBackgroundColor(frame, color(0.5, 0.6, 0.7, 1)))
            assert.are.equal(0, getCalls(bg, "SetColorTexture"))

            assert.is_true(FrameUtil.LazySetBackgroundColor(frame, color(0.9, 0.8, 0.7, 0.6)))
            assert.are.equal(1, getCalls(bg, "SetColorTexture"))
        end)

        -- Edge case: LazySetBackgroundColor implicit alpha=1 matching
        it("LazySetBackgroundColor treats implicit alpha as 1", function()
            local bg = makeTexture({ colorTexture = { 0.1, 0.2, 0.3, 1 } })
            local frame = { Background = bg }

            -- color.a is explicitly 1, stored alpha is 1 → no-op
            assert.is_false(FrameUtil.LazySetBackgroundColor(frame, color(0.1, 0.2, 0.3, 1)))
            assert.are.equal(0, getCalls(bg, "SetColorTexture"))
        end)

        -- Edge case: LazySetVertexColor prefers GetColorTexture
        it("LazySetVertexColor reads via GetColorTexture when available", function()
            local texture = makeTexture({ colorTexture = { 0.3, 0.4, 0.5, 1 }, vertexColor = { 0, 0, 0, 1 } })

            -- Match is against colorTexture, not vertexColor
            assert.is_false(FrameUtil.LazySetVertexColor(texture, color(0.3, 0.4, 0.5, 1)))
            assert.are.equal(0, getCalls(texture, "SetVertexColor"))
        end)

        -- Edge case: LazySetVertexColor falls back to GetVertexColor when GetColorTexture returns nil values
        it("LazySetVertexColor falls back to GetVertexColor when GetColorTexture returns nil", function()
            local texture = makeTexture({ vertexColor = { 0.2, 0.3, 0.4, 0.8 } })
            texture.GetColorTexture = function() return nil end

            assert.is_false(FrameUtil.LazySetVertexColor(texture, color(0.2, 0.3, 0.4, 0.8)))
            assert.are.equal(0, getCalls(texture, "SetVertexColor"))

            assert.is_true(FrameUtil.LazySetVertexColor(texture, color(1, 1, 1, 1)))
            assert.are.equal(1, getCalls(texture, "SetVertexColor"))
        end)

        -- Edge case: LazySetVertexColor applies when only alpha differs
        it("LazySetVertexColor applies when only alpha differs", function()
            local texture = makeTexture({ vertexColor = { 0.5, 0.5, 0.5, 1 } })

            assert.is_true(FrameUtil.LazySetVertexColor(texture, color(0.5, 0.5, 0.5, 0.5)))
            assert.are.equal(1, getCalls(texture, "SetVertexColor"))
        end)

        -- Edge case: LazySetStatusBarTexture when GetStatusBarTexture returns nil
        it("LazySetStatusBarTexture always applies when GetStatusBarTexture returns nil", function()
            local bar = makeStatusBar({ texturePath = "TexA" })
            bar.GetStatusBarTexture = function() return nil end

            assert.is_true(FrameUtil.LazySetStatusBarTexture(bar, "TexA"))
            assert.are.equal(1, getCalls(bar, "SetStatusBarTexture"))

            assert.is_true(FrameUtil.LazySetStatusBarTexture(bar, "TexA"))
            assert.are.equal(2, getCalls(bar, "SetStatusBarTexture"))
        end)

        -- Edge case: LazySetStatusBarColor nil alpha matches stored 1
        it("LazySetStatusBarColor treats nil alpha as 1", function()
            local bar = makeStatusBar({ statusBarColor = { 0.5, 0.6, 0.7, 1 } })

            -- Omitted alpha (nil) should match stored alpha of 1
            assert.is_false(FrameUtil.LazySetStatusBarColor(bar, 0.5, 0.6, 0.7))
            assert.are.equal(0, getCalls(bar, "SetStatusBarColor"))

            -- Explicit alpha of 1 should also match
            assert.is_false(FrameUtil.LazySetStatusBarColor(bar, 0.5, 0.6, 0.7, 1))
            assert.are.equal(0, getCalls(bar, "SetStatusBarColor"))
        end)

        -- Edge case: LazySetBorder when disabled and already hidden.
        -- Note: the `and/or` idiom in liveEnabled causes re-hide on every call;
        -- this test documents the current behaviour.
        it("LazySetBorder re-hides when disabled and already hidden", function()
            local border = makeBorder({
                shown = false,
                backdrop = { edgeSize = 2 },
                borderColor = { 1, 1, 1, 1 },
            })
            local frame = { Border = border }
            local cfg = {
                enabled = false,
                thickness = 2,
                color = color(1, 1, 1, 1),
            }

            assert.is_true(FrameUtil.LazySetBorder(frame, cfg))
            assert.are.equal(1, getCalls(border, "Hide"))
        end)

        -- Edge case: LazySetBorder skips SetBackdrop when only color changed
        it("LazySetBorder skips SetBackdrop when only the color has changed", function()
            local border = makeBorder({
                shown = true,
                backdrop = { edgeSize = 3 },
                borderColor = { 0.1, 0.2, 0.3, 0.4 },
            })
            local frame = { Border = border }
            local cfg = {
                enabled = true,
                thickness = 3,
                color = color(0.9, 0.8, 0.7, 0.6),
            }

            assert.is_true(FrameUtil.LazySetBorder(frame, cfg))
            assert.are.equal(0, getCalls(border, "SetBackdrop"))
            assert.are.equal(1, getCalls(border, "SetBackdropBorderColor"))
        end)

        -- Edge case: LazySetBorder re-applies when GetBackdrop is unavailable
        it("LazySetBorder re-applies when GetBackdrop is unavailable", function()
            local border = makeBorder({
                shown = true,
                backdrop = { edgeSize = 2 },
                borderColor = { 1, 1, 1, 1 },
            })
            border.GetBackdrop = nil
            local frame = { Border = border }
            local cfg = {
                enabled = true,
                thickness = 2,
                color = color(1, 1, 1, 1),
            }

            -- Cannot read live thickness, so cannot confirm match → applies
            assert.is_true(FrameUtil.LazySetBorder(frame, cfg))
            assert.are.equal(1, getCalls(border, "SetBackdropBorderColor"))
        end)

        -- Edge case: LazySetBorder re-applies when GetBackdropBorderColor is unavailable
        it("LazySetBorder re-applies when GetBackdropBorderColor is unavailable", function()
            local border = makeBorder({
                shown = true,
                backdrop = { edgeSize = 2 },
                borderColor = { 1, 1, 1, 1 },
            })
            border.GetBackdropBorderColor = nil
            local frame = { Border = border }
            local cfg = {
                enabled = true,
                thickness = 2,
                color = color(1, 1, 1, 1),
            }

            -- Cannot read live color, so cannot confirm match → applies
            assert.is_true(FrameUtil.LazySetBorder(frame, cfg))
        end)

        -- Edge case: LazySetText nil→non-nil
        it("LazySetText applies when text changes from nil to non-nil", function()
            local fontString = { __text = nil, __calls = {} }
            fontString.GetText = function(self) return self.__text end
            fontString.SetText = function(self, text) incCalls(self, "SetText"); self.__text = text end

            assert.is_true(FrameUtil.LazySetText(fontString, "Hello"))
            assert.are.equal(1, getCalls(fontString, "SetText"))
            assert.are.equal("Hello", fontString:GetText())
        end)

        -- Edge case: LazySetText non-nil→nil
        it("LazySetText applies when text changes from non-nil to nil", function()
            local fontString = { __text = "Hello", __calls = {} }
            fontString.GetText = function(self) return self.__text end
            fontString.SetText = function(self, text) incCalls(self, "SetText"); self.__text = text end

            assert.is_true(FrameUtil.LazySetText(fontString, nil))
            assert.are.equal(1, getCalls(fontString, "SetText"))
        end)

        -- Edge case: LazySetAnchors detects external anchor mutation
        it("LazySetAnchors detects external anchor mutation even when cache matches", function()
            local anchorA = makeFrame({ name = "AnchorA" })
            local anchorB = makeFrame({ name = "AnchorB" })
            local desired = {
                { "TOPLEFT", anchorA, "BOTTOMLEFT", 0, 0 },
            }
            local frame = makeFrame({
                anchors = {
                    { "TOPLEFT", anchorA, "BOTTOMLEFT", 0, 0 },
                },
            })

            -- First call: matches live → no-op, caches
            assert.is_false(FrameUtil.LazySetAnchors(frame, desired))

            -- External actor changes the anchor
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", anchorB, "CENTER", 5, 5)

            -- Next call: cache matches desired but live differs → reapplies
            assert.is_true(FrameUtil.LazySetAnchors(frame, desired))
        end)

        -- Edge case: LazySetAnchors with different anchor count
        it("LazySetAnchors reapplies when anchor count differs", function()
            local anchor = makeFrame({ name = "AnchorA" })
            local frame = makeFrame({
                anchors = {
                    { "TOPLEFT", anchor, "BOTTOMLEFT", 0, 0 },
                    { "TOPRIGHT", anchor, "BOTTOMRIGHT", 0, 0 },
                },
            })
            local desired = {
                { "CENTER", anchor, "CENTER", 0, 0 },
            }

            assert.is_true(FrameUtil.LazySetAnchors(frame, desired))
            assert.are.equal(1, frame:GetNumPoints())
        end)
    end)

    describe("anchor geometry", function()
        -- Use a parent with known dimensions for position math tests.
        local parent
        before_each(function()
            parent = makeFrame({ name = "TestParent", width = 1024, height = 768 })
        end)

        describe("SplitAnchorName", function()
            it("returns nil, nil for CENTER", function()
                local v, h = FrameUtil.SplitAnchorName("CENTER")
                assert.is_nil(v)
                assert.is_nil(h)
            end)

            it("returns nil, nil for nil", function()
                local v, h = FrameUtil.SplitAnchorName(nil)
                assert.is_nil(v)
                assert.is_nil(h)
            end)

            it("splits TOPLEFT into TOP and LEFT", function()
                local v, h = FrameUtil.SplitAnchorName("TOPLEFT")
                assert.are.equal("TOP", v)
                assert.are.equal("LEFT", h)
            end)

            it("splits BOTTOMRIGHT into BOTTOM and RIGHT", function()
                local v, h = FrameUtil.SplitAnchorName("BOTTOMRIGHT")
                assert.are.equal("BOTTOM", v)
                assert.are.equal("RIGHT", h)
            end)

            it("splits TOP into TOP and nil", function()
                local v, h = FrameUtil.SplitAnchorName("TOP")
                assert.are.equal("TOP", v)
                assert.is_nil(h)
            end)

            it("splits LEFT into nil and LEFT", function()
                local v, h = FrameUtil.SplitAnchorName("LEFT")
                assert.is_nil(v)
                assert.are.equal("LEFT", h)
            end)

            it("splits BOTTOM into BOTTOM and nil", function()
                local v, h = FrameUtil.SplitAnchorName("BOTTOM")
                assert.are.equal("BOTTOM", v)
                assert.is_nil(h)
            end)

            it("splits RIGHT into nil and RIGHT", function()
                local v, h = FrameUtil.SplitAnchorName("RIGHT")
                assert.is_nil(v)
                assert.are.equal("RIGHT", h)
            end)
        end)

        describe("BuildAnchorName", function()
            it("returns CENTER for nil, nil", function()
                assert.are.equal("CENTER", FrameUtil.BuildAnchorName(nil, nil))
            end)

            it("returns TOPLEFT for TOP, LEFT", function()
                assert.are.equal("TOPLEFT", FrameUtil.BuildAnchorName("TOP", "LEFT"))
            end)

            it("returns BOTTOMRIGHT for BOTTOM, RIGHT", function()
                assert.are.equal("BOTTOMRIGHT", FrameUtil.BuildAnchorName("BOTTOM", "RIGHT"))
            end)

            it("returns TOP for TOP, nil", function()
                assert.are.equal("TOP", FrameUtil.BuildAnchorName("TOP", nil))
            end)

            it("returns LEFT for nil, LEFT", function()
                assert.are.equal("LEFT", FrameUtil.BuildAnchorName(nil, "LEFT"))
            end)
        end)

        describe("GetParentAnchorPosition", function()
            it("returns center for CENTER", function()
                local x, y = FrameUtil.GetParentAnchorPosition("CENTER", 1000, 600)
                assert.are.equal(500, x)
                assert.are.equal(300, y)
            end)

            it("returns top-left corner for TOPLEFT", function()
                local x, y = FrameUtil.GetParentAnchorPosition("TOPLEFT", 1000, 600)
                assert.are.equal(0, x)
                assert.are.equal(600, y)
            end)

            it("returns bottom-right corner for BOTTOMRIGHT", function()
                local x, y = FrameUtil.GetParentAnchorPosition("BOTTOMRIGHT", 1000, 600)
                assert.are.equal(1000, x)
                assert.are.equal(0, y)
            end)

            it("returns top center for TOP", function()
                local x, y = FrameUtil.GetParentAnchorPosition("TOP", 1000, 600)
                assert.are.equal(500, x)
                assert.are.equal(600, y)
            end)

            it("returns left center for LEFT", function()
                local x, y = FrameUtil.GetParentAnchorPosition("LEFT", 1000, 600)
                assert.are.equal(0, x)
                assert.are.equal(300, y)
            end)

            it("returns 0,0 for nil dimensions", function()
                local x, y = FrameUtil.GetParentAnchorPosition("TOPLEFT", nil, nil)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
            end)

            it("returns center for nil point", function()
                local x, y = FrameUtil.GetParentAnchorPosition(nil, 1000, 600)
                assert.are.equal(500, x)
                assert.are.equal(300, y)
            end)
        end)

        describe("GetParentSize", function()
            it("uses GetSize when available", function()
                local p = { GetSize = function() return 800, 600 end }
                local w, h = FrameUtil.GetParentSize(p)
                assert.are.equal(800, w)
                assert.are.equal(600, h)
            end)

            it("falls back to GetWidth/GetHeight", function()
                local p = {
                    GetWidth = function() return 1024 end,
                    GetHeight = function() return 768 end,
                }
                local w, h = FrameUtil.GetParentSize(p)
                assert.are.equal(1024, w)
                assert.are.equal(768, h)
            end)

            it("falls back to GetWidth/GetHeight when GetSize returns nil", function()
                local p = {
                    GetSize = function() return nil, nil end,
                    GetWidth = function() return 640 end,
                    GetHeight = function() return 480 end,
                }
                local w, h = FrameUtil.GetParentSize(p)
                assert.are.equal(640, w)
                assert.are.equal(480, h)
            end)

            it("returns 0, 0 for nil parent", function()
                local w, h = FrameUtil.GetParentSize(nil)
                assert.are.equal(0, w)
                assert.are.equal(0, h)
            end)
        end)

        describe("GetOffsetFromFrameCenter", function()
            it("returns 0, 0 for CENTER", function()
                local x, y = FrameUtil.GetOffsetFromFrameCenter("CENTER", 100, 60)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
            end)

            it("returns negative half-width and positive half-height for TOPLEFT", function()
                local x, y = FrameUtil.GetOffsetFromFrameCenter("TOPLEFT", 100, 60)
                assert.are.equal(-50, x)
                assert.are.equal(30, y)
            end)

            it("returns positive half-width and negative half-height for BOTTOMRIGHT", function()
                local x, y = FrameUtil.GetOffsetFromFrameCenter("BOTTOMRIGHT", 100, 60)
                assert.are.equal(50, x)
                assert.are.equal(-30, y)
            end)

            it("returns 0, 0 for nil dimensions", function()
                local x, y = FrameUtil.GetOffsetFromFrameCenter("TOPLEFT", nil, nil)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
            end)

            it("returns 0, 0 for nil point", function()
                local x, y = FrameUtil.GetOffsetFromFrameCenter(nil, 100, 60)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
            end)
        end)

        describe("NormalizePosition", function()
            it("no-ops when point equals relativePoint", function()
                local p, x, y = FrameUtil.NormalizePosition("TOPLEFT", "TOPLEFT", 10, 20, parent)
                assert.are.equal("TOPLEFT", p)
                assert.are.equal(10, x)
                assert.are.equal(20, y)
            end)

            it("no-ops when relativePoint is nil (defaults to point)", function()
                local p, x, y = FrameUtil.NormalizePosition("CENTER", nil, 5, -5, parent)
                assert.are.equal("CENTER", p)
                assert.are.equal(5, x)
                assert.are.equal(-5, y)
            end)

            it("rewrites offsets from BOTTOMLEFT to TOPLEFT", function()
                local p, x, y = FrameUtil.NormalizePosition("TOPLEFT", "BOTTOMLEFT", 10, -350, parent)
                assert.are.equal("TOPLEFT", p)
                assert.are.equal(10, x)
                assert.are.equal(-350 - 768, y)
            end)

            it("defaults nil point to CENTER", function()
                local p, x, y = FrameUtil.NormalizePosition(nil, nil, 0, 0, parent)
                assert.are.equal("CENTER", p)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
            end)

            it("defaults nil x/y to 0", function()
                local p, x, y = FrameUtil.NormalizePosition("CENTER", "CENTER", nil, nil, parent)
                assert.are.equal("CENTER", p)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
            end)
        end)

        describe("ConvertOffsetToAnchor", function()
            it("no-ops when source and target points are the same", function()
                local x, y = FrameUtil.ConvertOffsetToAnchor("CENTER", "CENTER", 10, 20, 100, 60, parent)
                assert.are.equal(10, x)
                assert.are.equal(20, y)
            end)

            it("converts CENTER to TOP accounting for frame height", function()
                -- parent 1024x768, frame 100x60
                -- parentAnchor CENTER=(512,384), TOP=(512,768)
                -- frameCenter CENTER=(0,0), TOP=(0,30)
                -- center: (512+10-0, 384+20-0) = (522, 404)
                -- result: (522+0-512, 404+30-768) = (10, -334)
                local x, y = FrameUtil.ConvertOffsetToAnchor("CENTER", "TOP", 10, 20, 100, 60, parent)
                assert.are.equal(10, x)
                assert.are.equal(-334, y)
            end)

            it("converts TOPLEFT to BOTTOMLEFT accounting for frame height", function()
                -- parent 1024x768, frame 0x100
                -- parentAnchor TOPLEFT=(0,768), BOTTOMLEFT=(0,0)
                -- frameCenter TOPLEFT=(0,50), BOTTOMLEFT=(0,-50)
                -- center: (0+0-0, 768+0-50) = (0, 718)
                -- result: (0+0-0, 718+(-50)-0) = (0, 668)
                local x, y = FrameUtil.ConvertOffsetToAnchor("TOPLEFT", "BOTTOMLEFT", 0, 0, 0, 100, parent)
                assert.are.equal(0, x)
                assert.are.equal(668, y)
            end)

            it("handles nil width and height", function()
                -- With nil dims, GetOffsetFromFrameCenter returns 0,0
                -- degrades to anchor-only offset conversion
                local x, y = FrameUtil.ConvertOffsetToAnchor("CENTER", "TOP", 0, 0, nil, nil, parent)
                assert.are.equal(0, x)
                assert.are.equal(-384, y)
            end)
        end)
    end)

end)
