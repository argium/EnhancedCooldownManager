-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("StaggerBar real source", function()
    local originalGlobals
    local StaggerBar
    local ns
    local isBrewmaster
    local classToken
    local auras
    local stagger
    local healthMax
    local addMixinCalls
    local registerFrameCalls
    local unregisterFrameCalls
    local tickerCount
    local activeTicker

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "C_Timer",
            "C_UnitAuras",
            "UnitClass",
            "UnitStagger",
            "UnitHealthMax",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        isBrewmaster = true
        classToken = "MONK"
        auras = {}
        stagger = 0
        healthMax = 100
        addMixinCalls = 0
        registerFrameCalls = 0
        unregisterFrameCalls = 0
        tickerCount = 0
        activeTicker = nil

        _G.UnitClass = function()
            return "Monk", classToken
        end
        _G.UnitStagger = function()
            return stagger
        end
        _G.UnitHealthMax = function()
            return healthMax
        end
        _G.C_UnitAuras = {
            GetPlayerAuraBySpellID = function(spellID)
                return auras[spellID]
            end,
        }
        _G.C_Timer = {
            NewTicker = function(_, callback)
                tickerCount = tickerCount + 1
                activeTicker = {
                    callback = callback,
                    cancelled = false,
                    Cancel = function(self)
                        self.cancelled = true
                    end,
                }
                return activeTicker
            end,
        }

        ns = {
            BarMixin = {
                FrameProto = {
                    ShouldShow = function()
                        return true
                    end,
                },
                AddBarMixin = function(target)
                    addMixinCalls = addMixinCalls + 1
                    target.EnsureFrame = target.EnsureFrame or function() end
                end,
            },
            ClassUtil = {
                IsBrewmasterMonk = function()
                    return isBrewmaster
                end,
            },
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
                RequestRefresh = function() end,
            },
            Log = function() end,
        }
        TestHelpers.LoadChunk("Constants.lua", "Unable to load Constants.lua")(nil, ns)
        TestHelpers.LoadChunk("Locales/en.lua", "Unable to load Locales/en.lua")(nil, ns)

        ns.Addon = {
            NewModule = function(self, name)
                local module = { Name = name }
                self[name] = module
                return module
            end,
        }

        TestHelpers.LoadChunk("Modules/StaggerBar.lua", "Unable to load Modules/StaggerBar.lua")(nil, ns)
        StaggerBar = assert(ns.Addon.StaggerBar, "StaggerBar module did not initialize")
    end)

    it("ShouldShow requires the Brewmaster spec", function()
        assert.is_true(StaggerBar:ShouldShow())

        isBrewmaster = false
        assert.is_false(StaggerBar:ShouldShow())
    end)

    it("GetStatusBarValues returns stagger as a percentage of max health", function()
        stagger = 25
        healthMax = 100
        local current, max, display, isFraction = StaggerBar:GetStatusBarValues()
        assert.are.equal(25, current)
        assert.are.equal(100, max)
        assert.are.equal("25%", display)
        assert.is_true(isFraction)
    end)

    it("GetStatusBarValues guards against zero or missing max health", function()
        healthMax = 0
        local current, max, display = StaggerBar:GetStatusBarValues()
        assert.are.equal(0, current)
        assert.are.equal(1, max)
        assert.are.equal("0%", display)

        healthMax = nil
        current, max, display = StaggerBar:GetStatusBarValues()
        assert.are.equal(0, current)
        assert.are.equal(1, max)
        assert.are.equal("0%", display)
    end)

    it("GetStatusBarColor reflects the active stagger level, heavy first", function()
        function StaggerBar:GetModuleConfig()
            return {
                colorLight = { r = 1, g = 0, b = 0, a = 1 },
                colorModerate = { r = 0, g = 1, b = 0, a = 1 },
                colorHeavy = { r = 0, g = 0, b = 1, a = 1 },
            }
        end

        assert.same({ r = 1, g = 0, b = 0, a = 1 }, StaggerBar:GetStatusBarColor())

        auras[ns.Constants.SPELLID_STAGGER_MODERATE] = { applications = 1 }
        assert.same({ r = 0, g = 1, b = 0, a = 1 }, StaggerBar:GetStatusBarColor())

        auras[ns.Constants.SPELLID_STAGGER_HEAVY] = { applications = 1 }
        assert.same({ r = 0, g = 0, b = 1, a = 1 }, StaggerBar:GetStatusBarColor())
    end)

    it("only reacts to player unit events and starts the drain ticker", function()
        local reasons = {}
        ns.Runtime.RequestRefresh = function(_, reason)
            reasons[#reasons + 1] = reason
        end

        StaggerBar:OnEventUpdate("UNIT_AURA", "target")
        assert.are.equal(0, tickerCount)

        StaggerBar:OnEventUpdate("UNIT_AURA", "player")
        assert.same({ "UNIT_AURA" }, reasons)
        assert.are.equal(1, tickerCount)

        -- Ticker start is idempotent while one is already running.
        StaggerBar:OnEventUpdate("UNIT_AURA", "player")
        assert.are.equal(1, tickerCount)
    end)

    it("drain ticker refreshes while stagger is present and self-stops when it clears", function()
        function StaggerBar:IsEnabled()
            return true
        end
        StaggerBar.InnerFrame = { IsShown = function() return true end }
        local refreshCount = 0
        function StaggerBar:ThrottledRefresh()
            refreshCount = refreshCount + 1
        end

        auras[ns.Constants.SPELLID_STAGGER_LIGHT] = { applications = 1 }
        StaggerBar:_StartTicker()
        assert.are.equal(1, tickerCount)

        activeTicker.callback()
        assert.are.equal(1, refreshCount)
        assert.is_false(activeTicker.cancelled)

        -- Stagger clears: next tick refreshes once more, then cancels itself.
        auras[ns.Constants.SPELLID_STAGGER_LIGHT] = nil
        activeTicker.callback()
        assert.are.equal(2, refreshCount)
        assert.is_true(activeTicker.cancelled)
        assert.is_nil(StaggerBar._ticker)
    end)

    it("OnEnable only builds the frame for Monks; other classes are skipped", function()
        function StaggerBar:RegisterEvent() end
        function StaggerBar:UnregisterAllEvents() end

        classToken = "WARRIOR"
        StaggerBar:OnInitialize()
        StaggerBar:OnEnable()
        assert.are.equal(0, registerFrameCalls)

        classToken = "MONK"
        StaggerBar:OnEnable()
        assert.are.equal(1, registerFrameCalls)
    end)

    it("registers and unregisters with the frame system and stops the ticker", function()
        function StaggerBar:RegisterEvent() end
        function StaggerBar:UnregisterAllEvents() end

        StaggerBar:OnInitialize()
        StaggerBar:OnEnable()
        StaggerBar.InnerFrame = { IsShown = function() return true end }
        StaggerBar:OnDisable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, unregisterFrameCalls)
    end)

    it("registered callback drops the LibEvent target and forwards event args", function()
        local captured = {}
        function StaggerBar:RegisterEvent(event, cb)
            captured[event] = cb
        end
        function StaggerBar:UnregisterAllEvents() end

        StaggerBar:OnInitialize()
        StaggerBar:OnEnable()

        local reasons = {}
        ns.Runtime.RequestRefresh = function(_, reason)
            reasons[#reasons + 1] = reason
        end

        local cb = assert(captured["UNIT_AURA"], "expected UNIT_AURA registration")
        cb(StaggerBar, "UNIT_AURA", "player")
        assert.same({ "UNIT_AURA" }, reasons)
    end)

    it("does not define its own Refresh (uses base BarProto.Refresh)", function()
        assert.is_nil(rawget(StaggerBar, "Refresh"))
    end)
end)
