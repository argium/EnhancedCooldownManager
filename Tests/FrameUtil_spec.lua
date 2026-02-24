-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

if type(describe) ~= "function" or type(it) ~= "function" then
    return
end

local TestHelpers = assert(
    loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"),
    "Unable to load Tests/TestHelpers.lua"
)()

local unpack_fn = table.unpack or unpack

describe("FrameUtil", function()
    local originalGlobals
    local FrameUtil
    local scheduledTimers
    local fakeTime

    local function incCalls(obj, name)
        obj.__calls = obj.__calls or {}
        obj.__calls[name] = (obj.__calls[name] or 0) + 1
    end

    local function getCalls(obj, name)
        return (obj.__calls and obj.__calls[name]) or 0
    end

    local function color(r, g, b, a)
        return { r = r, g = g, b = b, a = a == nil and 1 or a }
    end

    local function makeRegion(regionType)
        local region = {
            __objectType = regionType or "Texture",
            __calls = {},
        }

        function region:IsObjectType(expectedType)
            return self.__objectType == expectedType
        end

        return region
    end

    local function makeTexture(opts)
        opts = opts or {}
        local texture = makeRegion("Texture")
        texture.__atlas = opts.atlas
        texture.__texture = opts.texture
        texture.__textureFileID = opts.textureFileID
        texture.__colorTexture = opts.colorTexture and { opts.colorTexture[1], opts.colorTexture[2], opts.colorTexture[3], opts.colorTexture[4] } or nil
        texture.__vertexColor = opts.vertexColor and { opts.vertexColor[1], opts.vertexColor[2], opts.vertexColor[3], opts.vertexColor[4] } or nil

        function texture:GetAtlas()
            return self.__atlas
        end

        function texture:GetTextureFileID()
            return self.__textureFileID
        end

        function texture:SetColorTexture(r, g, b, a)
            incCalls(self, "SetColorTexture")
            self.__colorTexture = { r, g, b, a }
        end

        function texture:GetColorTexture()
            if not self.__colorTexture then
                return nil
            end
            return self.__colorTexture[1], self.__colorTexture[2], self.__colorTexture[3], self.__colorTexture[4]
        end

        function texture:SetVertexColor(r, g, b, a)
            incCalls(self, "SetVertexColor")
            self.__vertexColor = { r, g, b, a }
        end

        function texture:GetVertexColor()
            if not self.__vertexColor then
                return nil
            end
            return self.__vertexColor[1], self.__vertexColor[2], self.__vertexColor[3], self.__vertexColor[4]
        end

        function texture:SetTexture(tex)
            incCalls(self, "SetTexture")
            self.__texture = tex
        end

        function texture:GetTexture()
            return self.__texture
        end

        return texture
    end

    local function cloneAnchors(anchors)
        local out = {}
        for i = 1, #anchors do
            local a = anchors[i]
            out[i] = { a[1], a[2], a[3], a[4], a[5] }
        end
        return out
    end

    local function makeFrame(opts)
        opts = opts or {}
        local frame = {
            __name = opts.name,
            __shown = opts.shown ~= false,
            __height = opts.height or 0,
            __width = opts.width or 0,
            __alpha = opts.alpha == nil and 1 or opts.alpha,
            __anchors = cloneAnchors(opts.anchors or {}),
            __regions = opts.regions or {},
            __calls = {},
        }

        function frame:GetName()
            return self.__name
        end

        function frame:SetHeight(h)
            incCalls(self, "SetHeight")
            self.__height = h
        end

        function frame:GetHeight()
            return self.__height
        end

        function frame:SetWidth(w)
            incCalls(self, "SetWidth")
            self.__width = w
        end

        function frame:GetWidth()
            return self.__width
        end

        function frame:SetAlpha(a)
            incCalls(self, "SetAlpha")
            self.__alpha = a
        end

        function frame:GetAlpha()
            return self.__alpha
        end

        function frame:Show()
            incCalls(self, "Show")
            self.__shown = true
        end

        function frame:Hide()
            incCalls(self, "Hide")
            self.__shown = false
        end

        function frame:IsShown()
            return self.__shown
        end

        function frame:ClearAllPoints()
            incCalls(self, "ClearAllPoints")
            self.__anchors = {}
        end

        function frame:SetPoint(point, relativeTo, relativePoint, x, y)
            incCalls(self, "SetPoint")
            self.__anchors[#self.__anchors + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
        end

        function frame:GetNumPoints()
            return #self.__anchors
        end

        function frame:GetPoint(index)
            local a = self.__anchors[index]
            if not a then
                return nil
            end
            return a[1], a[2], a[3], a[4], a[5]
        end

        function frame:GetRegions()
            return unpack_fn(self.__regions)
        end

        return frame
    end

    local function makeStatusBar(opts)
        opts = opts or {}
        local bar = makeFrame(opts)
        bar.__statusTexture = opts.statusTexture or makeTexture({ texture = opts.texturePath })
        bar.__statusBarColor = opts.statusBarColor and {
            opts.statusBarColor[1],
            opts.statusBarColor[2],
            opts.statusBarColor[3],
            opts.statusBarColor[4],
        } or { 1, 1, 1, 1 }

        function bar:SetStatusBarTexture(texturePath)
            incCalls(self, "SetStatusBarTexture")
            if self.__statusTexture and self.__statusTexture.SetTexture then
                self.__statusTexture:SetTexture(texturePath)
            end
        end

        function bar:GetStatusBarTexture()
            return self.__statusTexture
        end

        function bar:SetStatusBarColor(r, g, b, a)
            incCalls(self, "SetStatusBarColor")
            self.__statusBarColor = { r, g, b, a or 1 }
        end

        function bar:GetStatusBarColor()
            return self.__statusBarColor[1], self.__statusBarColor[2], self.__statusBarColor[3], self.__statusBarColor[4]
        end

        return bar
    end

    local function makeBorder(opts)
        opts = opts or {}
        local border = makeFrame({
            name = opts.name,
            shown = opts.shown ~= false,
        })
        border.__backdrop = opts.backdrop
        border.__borderColor = opts.borderColor and {
            opts.borderColor[1],
            opts.borderColor[2],
            opts.borderColor[3],
            opts.borderColor[4],
        } or { 0, 0, 0, 1 }

        function border:SetBackdrop(backdrop)
            incCalls(self, "SetBackdrop")
            self.__backdrop = backdrop
        end

        function border:GetBackdrop()
            return self.__backdrop
        end

        function border:SetBackdropBorderColor(r, g, b, a)
            incCalls(self, "SetBackdropBorderColor")
            self.__borderColor = { r, g, b, a or 1 }
        end

        function border:GetBackdropBorderColor()
            return self.__borderColor[1], self.__borderColor[2], self.__borderColor[3], self.__borderColor[4]
        end

        return border
    end

    local function assertAnchor(frame, index, point, relativeTo, relativePoint, x, y)
        local ap, ar, arp, ax, ay = frame:GetPoint(index)
        assert.are.equal(point, ap)
        assert.are.equal(relativeTo, ar)
        assert.are.equal(relativePoint, arp)
        assert.are.equal(x, ax)
        assert.are.equal(y, ay)
    end

    local function flushTimers()
        local pending = scheduledTimers
        scheduledTimers = {}
        for i = 1, #pending do
            pending[i].callback()
        end
    end

    setup(function()
        originalGlobals = TestHelpers.captureGlobals({
            "ECM",
            "ECM_AreColorsEqual",
            "ECM_debug_assert",
            "C_Timer",
            "GetTime",
            "UIParent",
        })
    end)

    teardown(function()
        TestHelpers.restoreGlobals(originalGlobals)
    end)

    before_each(function()
        scheduledTimers = {}
        fakeTime = 0

        _G.ECM = {}
        _G.ECM_AreColorsEqual = function(a, b)
            if a == nil and b == nil then
                return true
            end
            if a == nil or b == nil then
                return false
            end
            return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
        end
        _G.ECM_debug_assert = function(condition, message)
            if not condition then
                error(message or "ECM_debug_assert failed")
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

        local constantsChunk = TestHelpers.loadChunk(
            { "Constants.lua", "../Constants.lua" },
            "Unable to load Constants.lua"
        )
        constantsChunk()

        local frameUtilChunk = TestHelpers.loadChunk(
            { "Modules/FrameUtil.lua", "../Modules/FrameUtil.lua" },
            "Unable to load Modules/FrameUtil.lua"
        )
        frameUtilChunk()

        FrameUtil = assert(ECM.FrameUtil, "FrameUtil module did not initialize")
    end)

    describe("buff bar inspection helpers", function()
        it("GetSpellName returns the bar name text", function()
            local frame = {
                Bar = {
                    Name = {
                        GetText = function()
                            return "Immolation Aura"
                        end,
                    },
                },
            }

            assert.are.equal("Immolation Aura", FrameUtil.GetSpellName(frame))
        end)

        it("GetSpellName returns nil when the name region is missing", function()
            local frame = {
                Bar = {},
            }

            assert.is_nil(FrameUtil.GetSpellName(frame))
        end)

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
        it("LazySetHeight uses the live frame height and avoids redundant SetHeight calls", function()
            local frame = makeFrame({ height = 20 })

            assert.is_false(FrameUtil.LazySetHeight(frame, 20))
            assert.are.equal(0, getCalls(frame, "SetHeight"))

            assert.is_true(FrameUtil.LazySetHeight(frame, 25))
            assert.are.equal(1, getCalls(frame, "SetHeight"))
            assert.are.equal(25, frame:GetHeight())
        end)

        it("LazySetWidth uses the live frame width and avoids redundant SetWidth calls", function()
            local frame = makeFrame({ width = 40 })

            assert.is_false(FrameUtil.LazySetWidth(frame, 40))
            assert.are.equal(0, getCalls(frame, "SetWidth"))

            assert.is_true(FrameUtil.LazySetWidth(frame, 55))
            assert.are.equal(1, getCalls(frame, "SetWidth"))
            assert.are.equal(55, frame:GetWidth())
        end)

        it("LazySetAlpha uses the live alpha and avoids redundant SetAlpha calls", function()
            local frame = makeFrame({ alpha = 0.5 })

            assert.is_false(FrameUtil.LazySetAlpha(frame, 0.5))
            assert.are.equal(0, getCalls(frame, "SetAlpha"))

            assert.is_true(FrameUtil.LazySetAlpha(frame, 0.8))
            assert.are.equal(1, getCalls(frame, "SetAlpha"))
            assert.are.equal(0.8, frame:GetAlpha())
        end)

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
                ClearAllPoints = function(self)
                    incCalls(self, "ClearAllPoints")
                end,
                SetPoint = function(self)
                    incCalls(self, "SetPoint")
                end,
            }
            local anchors = {
                { "CENTER", UIParent, "CENTER", 0, 0 },
            }

            assert.is_true(FrameUtil.LazySetAnchors(frame, anchors))
            assert.is_true(FrameUtil.LazySetAnchors(frame, anchors))
            assert.are.equal(2, getCalls(frame, "ClearAllPoints"))
            assert.are.equal(2, getCalls(frame, "SetPoint"))
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

        it("LazySetVertexColor reads live vertex color and reapplies when getters are unavailable", function()
            local owner = {}
            local texture = makeTexture({ vertexColor = { 0.5, 0.5, 0.5, 1 } })

            assert.is_false(FrameUtil.LazySetVertexColor(owner, texture, "iconColor", color(0.5, 0.5, 0.5, 1)))
            assert.are.equal(0, getCalls(texture, "SetVertexColor"))

            texture.GetColorTexture = nil
            texture.GetVertexColor = nil

            assert.is_true(FrameUtil.LazySetVertexColor(owner, texture, "iconColor", color(1, 0, 0, 1)))
            assert.is_true(FrameUtil.LazySetVertexColor(owner, texture, "iconColor", color(1, 0, 0, 1)))
            assert.are.equal(2, getCalls(texture, "SetVertexColor"))
        end)

        it("LazySetStatusBarTexture reads the live texture object and reapplies when getters are unavailable", function()
            local owner = {}
            local bar = makeStatusBar({ texturePath = "TexA" })

            assert.is_false(FrameUtil.LazySetStatusBarTexture(owner, bar, "TexA"))
            assert.are.equal(0, getCalls(bar, "SetStatusBarTexture"))

            assert.is_true(FrameUtil.LazySetStatusBarTexture(owner, bar, "TexB"))
            assert.are.equal(1, getCalls(bar, "SetStatusBarTexture"))
            assert.are.equal("TexB", bar:GetStatusBarTexture():GetTexture())

            local fallbackBar = makeStatusBar({ texturePath = "X" })
            fallbackBar.GetStatusBarTexture = nil
            local fallbackOwner = {}
            assert.is_true(FrameUtil.LazySetStatusBarTexture(fallbackOwner, fallbackBar, "TexC"))
            assert.is_true(FrameUtil.LazySetStatusBarTexture(fallbackOwner, fallbackBar, "TexC"))
        end)

        it("LazySetStatusBarColor reads live status bar color and reapplies when getters are unavailable", function()
            local owner = {}
            local bar = makeStatusBar({ statusBarColor = { 0.2, 0.3, 0.4, 1 } })

            assert.is_false(FrameUtil.LazySetStatusBarColor(owner, bar, 0.2, 0.3, 0.4))
            assert.are.equal(0, getCalls(bar, "SetStatusBarColor"))

            assert.is_true(FrameUtil.LazySetStatusBarColor(owner, bar, 1, 0, 0, 0.9))
            assert.are.equal(1, getCalls(bar, "SetStatusBarColor"))

            local fallbackOwner = {}
            local fallbackBar = makeStatusBar()
            fallbackBar.GetStatusBarColor = nil
            assert.is_true(FrameUtil.LazySetStatusBarColor(fallbackOwner, fallbackBar, 0.1, 0.1, 0.1, 1))
            assert.is_true(FrameUtil.LazySetStatusBarColor(fallbackOwner, fallbackBar, 0.1, 0.1, 0.1, 1))
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
            local owner = {}
            local fontString = {
                __text = "Hello",
                __calls = {},
                GetText = function(self)
                    return self.__text
                end,
                SetText = function(self, text)
                    incCalls(self, "SetText")
                    self.__text = text
                end,
            }

            assert.is_false(FrameUtil.LazySetText(owner, fontString, "label", "Hello"))
            assert.are.equal(0, getCalls(fontString, "SetText"))

            assert.is_true(FrameUtil.LazySetText(owner, fontString, "label", "World"))
            assert.are.equal(1, getCalls(fontString, "SetText"))
        end)
    end)

    describe("layout helpers", function()
        it("CalculateLayoutParams returns chain mode parameters", function()
            local anchor = makeFrame({ name = "ChainAnchor" })
            local selfObj = {
                Name = "ResourceBar",
                GetGlobalConfig = function()
                    return { offsetY = 12, barHeight = 18, barWidth = 200 }
                end,
                GetModuleConfig = function()
                    return { anchorMode = ECM.Constants.ANCHORMODE_CHAIN, height = 22 }
                end,
                GetNextChainAnchor = function(_, name)
                    assert.are.equal("ResourceBar", name)
                    return anchor, true
                end,
            }

            local params = FrameUtil.CalculateLayoutParams(selfObj)
            assert.are.equal(ECM.Constants.ANCHORMODE_CHAIN, params.mode)
            assert.are.equal(anchor, params.anchor)
            assert.is_true(params.isFirst)
            assert.are.equal("TOPLEFT", params.anchorPoint)
            assert.are.equal("BOTTOMLEFT", params.anchorRelativePoint)
            assert.are.equal(0, params.offsetX)
            assert.are.equal(-12, params.offsetY)
            assert.are.equal(22, params.height)
            assert.is_nil(params.width)
        end)

        it("CalculateLayoutParams returns free mode parameters with defaults", function()
            local selfObj = {
                GetGlobalConfig = function()
                    return { barHeight = 19, barWidth = 240 }
                end,
                GetModuleConfig = function()
                    return { anchorMode = ECM.Constants.ANCHORMODE_FREE, offsetX = 7 }
                end,
            }

            local params = FrameUtil.CalculateLayoutParams(selfObj)
            assert.are.equal(ECM.Constants.ANCHORMODE_FREE, params.mode)
            assert.are.equal(UIParent, params.anchor)
            assert.is_false(params.isFirst)
            assert.are.equal("CENTER", params.anchorPoint)
            assert.are.equal("CENTER", params.anchorRelativePoint)
            assert.are.equal(7, params.offsetX)
            assert.are.equal(ECM.Constants.DEFAULT_FREE_ANCHOR_OFFSET_Y, params.offsetY)
            assert.are.equal(19, params.height)
            assert.are.equal(240, params.width)
        end)

        it("ApplyFramePosition hides the frame and returns nil when ShouldShow is false", function()
            local frame = makeFrame({ shown = true })
            local selfObj = {
                ShouldShow = function()
                    return false
                end,
            }

            local params = FrameUtil.ApplyFramePosition(selfObj, frame)
            assert.is_nil(params)
            assert.is_false(frame:IsShown())
            assert.are.equal(1, getCalls(frame, "Hide"))
        end)

        it("ApplyFramePosition shows hidden frame and applies chain anchors", function()
            local anchor = makeFrame({ name = "AnchorX" })
            local frame = makeFrame({ shown = false })
            local selfObj = {
                ShouldShow = function()
                    return true
                end,
                CalculateLayoutParams = function()
                    return {
                        mode = ECM.Constants.ANCHORMODE_CHAIN,
                        anchor = anchor,
                        offsetX = 3,
                        offsetY = -4,
                        anchorPoint = "TOPLEFT",
                        anchorRelativePoint = "BOTTOMLEFT",
                    }
                end,
            }

            local params = FrameUtil.ApplyFramePosition(selfObj, frame)
            assert.are.equal(anchor, params.anchor)
            assert.is_true(frame:IsShown())
            assert.are.equal(1, getCalls(frame, "Show"))
            assert.are.equal(2, frame:GetNumPoints())
            assertAnchor(frame, 1, "TOPLEFT", anchor, "BOTTOMLEFT", 3, -4)
            assertAnchor(frame, 2, "TOPRIGHT", anchor, "BOTTOMRIGHT", 3, -4)
        end)

        it("ApplyFramePosition applies free-mode single-point anchors", function()
            local anchor = makeFrame({ name = "AnchorY" })
            local frame = makeFrame()
            local selfObj = {
                ShouldShow = function()
                    return true
                end,
                CalculateLayoutParams = function()
                    return {
                        mode = ECM.Constants.ANCHORMODE_FREE,
                        anchor = anchor,
                        anchorPoint = "CENTER",
                        anchorRelativePoint = "TOPLEFT",
                        offsetX = 9,
                        offsetY = 10,
                    }
                end,
            }

            FrameUtil.ApplyFramePosition(selfObj, frame)
            assert.are.equal(1, frame:GetNumPoints())
            assertAnchor(frame, 1, "CENTER", anchor, "TOPLEFT", 9, 10)
        end)

        it("ApplyStandardLayout returns false when the frame should be hidden", function()
            local frame = makeFrame()
            local refreshWhy
            local selfObj = {
                Name = "TestModule",
                InnerFrame = frame,
                ShouldShow = function()
                    return false
                end,
                GetGlobalConfig = function()
                    return { barBgColor = color(0, 0, 0, 1) }
                end,
                GetModuleConfig = function()
                    return { anchorMode = ECM.Constants.ANCHORMODE_CHAIN }
                end,
                ThrottledRefresh = function(_, why)
                    refreshWhy = why
                end,
            }

            assert.is_false(FrameUtil.ApplyStandardLayout(selfObj, "skip"))
            assert.is_nil(refreshWhy)
        end)

        it("ApplyStandardLayout applies layout, styling, and triggers throttled refresh", function()
            local frame = makeFrame({
                name = "Inner",
                shown = false,
                height = 5,
                width = 10,
            })
            frame.Background = makeTexture()
            frame.Border = makeBorder({
                shown = false,
                backdrop = { edgeSize = 1 },
                borderColor = { 0, 0, 0, 1 },
            })

            local throttledWhy
            local anchor = makeFrame({ name = "AnchorMain" })
            local selfObj = {
                Name = "TestModule",
                InnerFrame = frame,
                ShouldShow = function()
                    return true
                end,
                CalculateLayoutParams = function()
                    return {
                        mode = ECM.Constants.ANCHORMODE_FREE,
                        anchor = anchor,
                        anchorPoint = "CENTER",
                        anchorRelativePoint = "CENTER",
                        offsetX = 4,
                        offsetY = -6,
                        width = 120,
                        height = 30,
                        isFirst = false,
                    }
                end,
                GetGlobalConfig = function()
                    return {
                        barBgColor = color(0.1, 0.1, 0.1, 0.6),
                    }
                end,
                GetModuleConfig = function()
                    return {
                        border = {
                            enabled = true,
                            thickness = 2,
                            color = color(0.8, 0.7, 0.6, 0.5),
                        },
                        bgColor = color(0.2, 0.3, 0.4, 0.5),
                    }
                end,
                ThrottledRefresh = function(_, why)
                    throttledWhy = why
                end,
            }

            assert.is_true(FrameUtil.ApplyStandardLayout(selfObj, "layout-pass"))
            assert.are.equal(30, frame:GetHeight())
            assert.are.equal(120, frame:GetWidth())
            assert.are.equal(1, getCalls(frame.Background, "SetColorTexture"))
            assert.are.equal(1, getCalls(frame.Border, "SetBackdropBorderColor"))
            assert.are.equal("UpdateLayout(layout-pass)", throttledWhy)
        end)
    end)

    describe("refresh and scheduling helpers", function()
        it("BaseRefresh returns false only when not forced and ShouldShow is false", function()
            local selfObj = {
                ShouldShow = function()
                    return false
                end,
            }

            assert.is_false(FrameUtil.BaseRefresh(selfObj, "why", false))
            assert.is_true(FrameUtil.BaseRefresh(selfObj, "why", true))

            selfObj.ShouldShow = function()
                return true
            end
            assert.is_true(FrameUtil.BaseRefresh(selfObj, "why", false))
        end)

        it("ScheduleDebounced coalesces calls and clears the pending flag after callback", function()
            local callbackCalls = 0
            local selfObj = {
                GetGlobalConfig = function()
                    return { updateFrequency = 0.25 }
                end,
            }

            FrameUtil.ScheduleDebounced(selfObj, "_pending", function()
                callbackCalls = callbackCalls + 1
            end)
            FrameUtil.ScheduleDebounced(selfObj, "_pending", function()
                callbackCalls = callbackCalls + 100
            end)

            assert.is_true(selfObj._pending)
            assert.are.equal(1, #scheduledTimers)
            assert.are.equal(0.25, scheduledTimers[1].delay)

            flushTimers()

            assert.is_nil(selfObj._pending)
            assert.are.equal(1, callbackCalls)
        end)

        it("ThrottledRefresh skips calls inside the throttle window and refreshes outside it", function()
            local refreshCalls = {}
            local selfObj = {
                _lastUpdate = nil,
                GetGlobalConfig = function()
                    return { updateFrequency = 0.1 }
                end,
                Refresh = function(_, why)
                    refreshCalls[#refreshCalls + 1] = why
                end,
            }

            fakeTime = 1.0
            assert.is_true(FrameUtil.ThrottledRefresh(selfObj, "first"))
            assert.are.same({ "first" }, refreshCalls)
            assert.are.equal(1.0, selfObj._lastUpdate)

            fakeTime = 1.05
            assert.is_false(FrameUtil.ThrottledRefresh(selfObj, "second"))
            assert.are.same({ "first" }, refreshCalls)

            fakeTime = 1.2
            assert.is_true(FrameUtil.ThrottledRefresh(selfObj, "third"))
            assert.are.same({ "first", "third" }, refreshCalls)
            assert.are.equal(1.2, selfObj._lastUpdate)
        end)

        it("ThrottledRefresh uses the default refresh frequency when global config is missing", function()
            local refreshCalls = 0
            local selfObj = {
                _lastUpdate = 0,
                GetGlobalConfig = function()
                    return nil
                end,
                Refresh = function()
                    refreshCalls = refreshCalls + 1
                end,
            }

            fakeTime = ECM.Constants.DEFAULT_REFRESH_FREQUENCY - 0.001
            assert.is_false(FrameUtil.ThrottledRefresh(selfObj, "early"))
            assert.are.equal(0, refreshCalls)

            fakeTime = ECM.Constants.DEFAULT_REFRESH_FREQUENCY + 0.001
            assert.is_true(FrameUtil.ThrottledRefresh(selfObj, "ready"))
            assert.are.equal(1, refreshCalls)
        end)

        it("ScheduleLayoutUpdate schedules UpdateLayout through the debounced helper", function()
            local layoutCalls = {}
            local selfObj = {
                GetGlobalConfig = function()
                    return { updateFrequency = 0.15 }
                end,
                UpdateLayout = function(_, why)
                    layoutCalls[#layoutCalls + 1] = why
                end,
            }

            FrameUtil.ScheduleLayoutUpdate(selfObj, "layout-1")
            FrameUtil.ScheduleLayoutUpdate(selfObj, "layout-2")

            assert.are.equal(1, #scheduledTimers)
            assert.are.equal(0.15, scheduledTimers[1].delay)

            flushTimers()
            assert.are.same({ "layout-1" }, layoutCalls)
        end)
    end)
end)
