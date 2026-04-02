-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("RuneBar real source", function()
    local originalGlobals
    local RuneBar
    local ns
    local isDeathKnight
    local addMixinCalls
    local registerFrameCalls
    local tickerCount
    local unregisterFrameCalls
    local makeFrame = TestHelpers.makeFrame
    local createFrameCalls
    local frameRefreshResult
    local now

    setup(function()
        originalGlobals =
            TestHelpers.CaptureGlobals({
                "C_Timer",
                "CreateFrame",
                "GetSpecialization",
                "UIParent",
                "GetRuneCooldown",
                "GetTime",
            })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        isDeathKnight = false
        addMixinCalls = 0
        registerFrameCalls = 0
        tickerCount = 0
        unregisterFrameCalls = 0
        createFrameCalls = 0
        frameRefreshResult = true
        now = 100

        ns = {
            BarMixin = {
                FrameProto = {
                    ShouldShow = function()
                        return true
                    end,
                    Refresh = function()
                        return frameRefreshResult
                    end,
                    CreateFrame = function(self)
                        local frame = makeFrame({ name = self.Name, shown = true, width = 300, height = 20 })
                        frame.GetFrameLevel = function()
                            return 1
                        end
                        frame.SetFrameLevel = function() end
                        return frame
                    end,
                },
                AddBarMixin = function(target)
                    addMixinCalls = addMixinCalls + 1
                    target.EnsureFrame = target.EnsureFrame or function() end
                end,
            },
            IsDeathKnight = function()
                return isDeathKnight
            end,
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
                RequestLayout = function() end,
            },
            FrameUtil = {},
            Log = function() end,
        }
        _G.C_Timer = {
            NewTicker = function(_, callback)
                tickerCount = tickerCount + 1
                return {
                    callback = callback,
                    cancelled = false,
                    Cancel = function(self)
                        self.cancelled = true
                    end,
                }
            end,
        }
        _G.UIParent = makeFrame({ name = "UIParent" })
        -- wipe is a WoW Lua 5.1 built-in not available in busted's Lua 5.3+
        _G.wipe = function(t) for k in pairs(t) do t[k] = nil end end
        _G.GetSpecialization = function()
            return 1
        end
        _G.GetTime = function()
            return now
        end
        _G.GetRuneCooldown = function()
            return 0, 0, true
        end
        _G.CreateFrame = function(_, name)
            createFrameCalls = createFrameCalls + 1
            local frame = makeFrame({ name = name, shown = true, width = 300, height = 20 })
            frame.SetFrameLevel = function() end
            frame.GetFrameLevel = function()
                return 1
            end
            frame.SetStatusBarTexture = function() end
            frame.SetMinMaxValues = function() end
            frame.SetValue = function() end
            frame.SetStatusBarColor = function() end
            frame.SetSize = function(self, width, height)
                self:SetWidth(width)
                self:SetHeight(height)
            end
            return frame
        end
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        ns.Addon = {
            NewModule = function(self, name)
                local module = { Name = name }
                self[name] = module
                return module
            end,
        }

        TestHelpers.LoadChunk("Modules/RuneBar.lua", "Unable to load Modules/RuneBar.lua")(nil, ns)
        RuneBar = assert(ns.Addon.RuneBar, "RuneBar module did not initialize")
        function RuneBar:IsEnabled()
            return true
        end
        function RuneBar:RegisterEvent() end
        function RuneBar:UnregisterAllEvents() end
    end)

    it("only returns true from ShouldShow for death knights", function()
        assert.is_false(RuneBar:ShouldShow())

        isDeathKnight = true
        assert.is_true(RuneBar:ShouldShow())
    end)

    it("returns early from OnEnable for non-death-knights", function()
        RuneBar:OnInitialize()
        RuneBar:OnEnable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(0, registerFrameCalls)
        assert.are.equal(0, tickerCount)
    end)

    it("registers the frame for death knights without starting a ticker", function()
        isDeathKnight = true

        RuneBar:OnInitialize()
        RuneBar:OnEnable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(0, tickerCount)
        assert.is_nil(RuneBar._valueTicker)
    end)

    it("starts the animation ticker on rune power update", function()
        isDeathKnight = true
        RuneBar:OnInitialize()
        RuneBar:OnEnable()
        ns.Runtime.RequestRefresh = function() end

        RuneBar:OnRunePowerUpdate()

        assert.are.equal(1, tickerCount)
        assert.is_not_nil(RuneBar._valueTicker)
    end)

    it("defers a layout refresh on rune power updates", function()
        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end
        ns.Runtime.RequestRefresh = function(_, reason)
            reasons[#reasons + 1] = reason
        end

        RuneBar:OnRunePowerUpdate()

        assert.same({ "RuneBar:RUNE_POWER_UPDATE" }, reasons)
    end)

    it("unregisters the frame and cancels the ticker on disable when needed", function()
        local ticker = {
            cancelled = false,
            Cancel = function(self)
                self.cancelled = true
            end,
        }
        RuneBar.InnerFrame = makeFrame({ shown = true })
        RuneBar._valueTicker = ticker

        RuneBar:OnDisable()

        assert.are.equal(1, unregisterFrameCalls)
        assert.is_true(ticker.cancelled)
        assert.is_nil(RuneBar._valueTicker)
    end)

    it("skips unregistering on disable when no frame exists", function()
        RuneBar:OnDisable()

        assert.are.equal(0, unregisterFrameCalls)
    end)

    it("creates a frame with status and tick containers", function()
        local frame = RuneBar:CreateFrame()

        assert.is_not_nil(frame.StatusBar)
        assert.is_not_nil(frame.TicksFrame)
        assert.same({}, frame.FragmentedBars)
        assert.are.equal(2, createFrameCalls)
    end)

    it("Refresh initializes fragmented bars and lays out ticks", function()
        local ensureTicksCount
        local layoutTicksMax
        local frame = {
            StatusBar = {
                SetMinMaxValues = function() end,
                GetWidth = function()
                    return 300
                end,
                GetHeight = function()
                    return 20
                end,
            },
            TicksFrame = {},
            FragmentedBars = {},
            GetWidth = function()
                return 300
            end,
            GetHeight = function()
                return 20
            end,
            GetFrameLevel = function()
                return 1
            end,
            Show = function(self)
                self.__shown = true
            end,
        }
        RuneBar.InnerFrame = frame
        RuneBar.GetModuleConfig = function()
            return { useSpecColor = false, color = { r = 1, g = 0, b = 0 }, texture = "Solid" }
        end
        RuneBar.GetGlobalConfig = function()
            return { texture = "Solid", updateFrequency = 0.04 }
        end
        RuneBar.EnsureTicks = function(_, count)
            ensureTicksCount = count
        end
        RuneBar.LayoutResourceTicks = function(_, maxRunes)
            layoutTicksMax = maxRunes
        end
        ns.FrameUtil.GetTexture = function()
            return "Interface\\TargetingFrame\\UI-StatusBar"
        end
        ns.FrameUtil.PixelSnap = function(v)
            return math.floor(v + 0.5)
        end
        _G.GetRuneCooldown = function()
            return 0, 0, true
        end

        assert.is_true(RuneBar:Refresh("test"))
        assert.are.equal(ns.Constants.RUNEBAR_MAX_RUNES - 1, ensureTicksCount)
        assert.are.equal(ns.Constants.RUNEBAR_MAX_RUNES, layoutTicksMax)
        assert.is_true(frame.__shown == true)
    end)

    it("returns false from Refresh when the base frame refresh stops the update", function()
        frameRefreshResult = false
        RuneBar.InnerFrame = makeFrame({ shown = true })

        assert.is_false(RuneBar:Refresh("test"))
    end)

    it("ticker hot path updates fragment values without relayout when rune states are unchanged", function()
        local frags = {}
        for i = 1, ns.Constants.RUNEBAR_MAX_RUNES do
            frags[i] = {
                SetValue = function(self, value)
                    self.__value = value
                end,
                SetStatusBarColor = function(self, r, g, b)
                    self.__color = { r, g, b }
                end,
            }
        end
        RuneBar.InnerFrame = makeFrame({ shown = true, width = 300, height = 20 })
        RuneBar.InnerFrame.FragmentedBars = frags
        RuneBar.InnerFrame._maxResources = ns.Constants.RUNEBAR_MAX_RUNES
        RuneBar.InnerFrame._lastReadySet = {}
        for i = 1, ns.Constants.RUNEBAR_MAX_RUNES do
            RuneBar.InnerFrame._lastReadySet[i] = true
        end
        RuneBar.GetModuleConfig = function()
            return { useSpecColor = false, color = { r = 0.8, g = 0.1, b = 0.2 }, texture = "Solid" }
        end
        RuneBar.GetGlobalConfig = function()
            return { updateFrequency = 0.04, texture = "Solid" }
        end
        _G.GetRuneCooldown = function()
            return 0, 0, true
        end
        isDeathKnight = true

        RuneBar:OnInitialize()
        RuneBar:OnEnable()
        ns.Runtime.RequestRefresh = function() end
        RuneBar:OnRunePowerUpdate()
        RuneBar._valueTicker.callback()

        assert.are.equal(1, frags[1].__value)
        assert.same({ 0.8, 0.1, 0.2 }, frags[1].__color)
        -- Ticker should self-stop since all runes are ready
        assert.is_nil(RuneBar._valueTicker)
    end)

    it("ticker hot path requests relayout when rune ready states change", function()
        local reasons = {}
        local frags = {}
        for i = 1, ns.Constants.RUNEBAR_MAX_RUNES do
            frags[i] = {
                SetValue = function() end,
                SetStatusBarColor = function() end,
            }
        end
        RuneBar.InnerFrame = makeFrame({ shown = true, width = 300, height = 20 })
        RuneBar.InnerFrame.FragmentedBars = frags
        RuneBar.InnerFrame._maxResources = ns.Constants.RUNEBAR_MAX_RUNES
        RuneBar.InnerFrame._lastReadySet = {}
        for i = 1, ns.Constants.RUNEBAR_MAX_RUNES do
            RuneBar.InnerFrame._lastReadySet[i] = true
        end
        RuneBar.GetModuleConfig = function()
            return { useSpecColor = false, color = { r = 0.8, g = 0.1, b = 0.2 }, texture = "Solid" }
        end
        RuneBar.GetGlobalConfig = function()
            return { updateFrequency = 0.04, texture = "Solid" }
        end
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end
        ns.Runtime.RequestRefresh = function(_, reason)
            reasons[#reasons + 1] = reason
        end
        _G.GetRuneCooldown = function(index)
            if index == 1 then
                return 90, 10, false
            end
            return 0, 0, true
        end
        isDeathKnight = true

        RuneBar:OnInitialize()
        RuneBar:OnEnable()
        RuneBar:OnRunePowerUpdate()
        RuneBar._valueTicker.callback()

        assert.same({ "RuneBar:RUNE_POWER_UPDATE", "RuneBar:RuneStateChange" }, reasons)
    end)

    it("ticker hot path uses specialization colors when enabled", function()
        local specId = 0
        local colorCases = {
            { specId = ns.Constants.DEATHKNIGHT_FROST_SPEC_INDEX, expected = { 0.1, 0.2, 0.3 } },
            { specId = ns.Constants.DEATHKNIGHT_UNHOLY_SPEC_INDEX, expected = { 0.4, 0.5, 0.6 } },
            { specId = 99, expected = { 0.7, 0.8, 0.9 } },
        }
        _G.GetSpecialization = function()
            return specId
        end
        RuneBar.GetModuleConfig = function()
            return {
                useSpecColor = true,
                color = { r = 1, g = 1, b = 1 },
                colorBlood = { r = 0.7, g = 0.8, b = 0.9 },
                colorFrost = { r = 0.1, g = 0.2, b = 0.3 },
                colorUnholy = { r = 0.4, g = 0.5, b = 0.6 },
                texture = "Solid",
            }
        end
        RuneBar.GetGlobalConfig = function()
            return { updateFrequency = 0.04, texture = "Solid" }
        end
        _G.GetRuneCooldown = function()
            return 0, 0, true
        end
        isDeathKnight = true

        RuneBar:OnInitialize()
        RuneBar:OnEnable()
        ns.Runtime.RequestLayout = function() end
        ns.Runtime.RequestRefresh = function() end

        for _, case in ipairs(colorCases) do
            local frags = {}
            for i = 1, ns.Constants.RUNEBAR_MAX_RUNES do
                frags[i] = {
                    SetValue = function() end,
                    SetStatusBarColor = function(self, r, g, b)
                        self.__color = { r, g, b }
                    end,
                }
            end
            RuneBar.InnerFrame = makeFrame({ shown = true, width = 300, height = 20 })
            RuneBar.InnerFrame.FragmentedBars = frags
            RuneBar.InnerFrame._maxResources = ns.Constants.RUNEBAR_MAX_RUNES
            RuneBar.InnerFrame._lastReadySet = {}
            for i = 1, ns.Constants.RUNEBAR_MAX_RUNES do
                RuneBar.InnerFrame._lastReadySet[i] = true
            end

            specId = case.specId
            now = now + 1
            RuneBar:OnRunePowerUpdate()
            RuneBar._valueTicker.callback()

            assert.same(case.expected, frags[1].__color)
        end
    end)
end)
