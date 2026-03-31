-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("ResourceBar real source", function()
    local originalGlobals
    local ResourceBar
    local ns
    local currentResourceType
    local currentValues
    local addMixinCalls
    local registerFrameCalls
    local unregisterFrameCalls

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({})
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        currentResourceType = "icicles"
        currentValues = { 5, 2, 5 }
        addMixinCalls = 0
        registerFrameCalls = 0
        unregisterFrameCalls = 0

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
                GetPlayerResourceType = function()
                    return currentResourceType
                end,
                GetCurrentMaxResourceValues = function()
                    return currentValues[1], currentValues[2], currentValues[3]
                end,
            },
            Runtime = {
                RegisterFrame = function()
                    registerFrameCalls = registerFrameCalls + 1
                end,
                UnregisterFrame = function()
                    unregisterFrameCalls = unregisterFrameCalls + 1
                end,
                RequestLayout = function() end,
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

        TestHelpers.LoadChunk("Modules/ResourceBar.lua", "Unable to load Modules/ResourceBar.lua")(nil, ns)
        ResourceBar = assert(ns.Addon.ResourceBar, "ResourceBar module did not initialize")
    end)

    it("ShouldShow requires a current resource type", function()
        assert.is_true(ResourceBar:ShouldShow())

        currentResourceType = nil
        assert.is_false(ResourceBar:ShouldShow())
    end)

    it("GetTickSpec returns resource spec for safe discrete resources", function()
        local spec = ResourceBar:GetTickSpec()
        assert.is_not_nil(spec)
        assert.are.equal(5, spec.maxResources)
        assert.are.equal(ns.Constants.COLOR_BLACK, spec.color)
        assert.are.equal(1, spec.width)
    end)

    it("GetTickSpec returns resource spec for devourer resources based on safeMax", function()
        currentResourceType = ns.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL
        currentValues = { 10, 2, 10 }

        local spec = ResourceBar:GetTickSpec()
        assert.is_not_nil(spec)
        assert.are.equal(10, spec.maxResources)
    end)

    it("GetTickSpec returns nil when safeMax is nil or too small", function()
        currentValues = { 1, 1, nil }
        assert.is_nil(ResourceBar:GetTickSpec())

        currentValues = { 1, 1, 1 }
        assert.is_nil(ResourceBar:GetTickSpec())
    end)

    it("only updates for player UNIT_AURA events and always updates for other events", function()
        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        ResourceBar:OnEventUpdate("UNIT_AURA", "target")
        ResourceBar:OnEventUpdate("UNIT_AURA", "player")
        ResourceBar:OnEventUpdate("UNIT_POWER_UPDATE")

        assert.same({ "UNIT_AURA", "UNIT_POWER_UPDATE" }, reasons)
    end)

    it("registered callbacks drop LibEvent target and forward event args", function()
        local captured = {}
        function ResourceBar:RegisterEvent(event, cb)
            captured[event] = cb
        end
        function ResourceBar:UnregisterAllEvents() end

        ResourceBar:OnInitialize()
        ResourceBar:OnEnable()

        local reasons = {}
        ns.Runtime.RequestLayout = function(reason)
            reasons[#reasons + 1] = reason
        end

        -- LibEvent dispatches cb(target, event, ...wowArgs)
        local cb = assert(captured["UNIT_AURA"], "expected UNIT_AURA registration")
        cb(ResourceBar, "UNIT_AURA", "player")
        assert.same({ "UNIT_AURA" }, reasons)
    end)

    it("registers and unregisters with the frame system", function()
        function ResourceBar:RegisterEvent() end
        function ResourceBar:UnregisterAllEvents() end

        ResourceBar:OnInitialize()
        ResourceBar:OnEnable()
        ResourceBar:OnDisable()

        assert.are.equal(1, addMixinCalls)
        assert.are.equal(1, registerFrameCalls)
        assert.are.equal(1, unregisterFrameCalls)
    end)

    it("returns real status values and fallback values through the module API", function()
        currentValues = { 5, 3, 5 }
        local current, max, display, isFraction = ResourceBar:GetStatusBarValues()
        assert.are.equal(3, current)
        assert.are.equal(5, max)
        assert.are.equal(3, display)
        assert.is_false(isFraction)

        currentValues = { nil, nil, nil }
        current, max, display, isFraction = ResourceBar:GetStatusBarValues()
        assert.are.equal(0, current)
        assert.are.equal(1, max)
        assert.are.equal(0, display)
        assert.is_false(isFraction)
    end)

    it("returns max colors and normal colors through the real module API", function()
        currentResourceType = ns.Constants.RESOURCEBAR_TYPE_ICICLES
        currentValues = { 5, 5, 5 }
        function ResourceBar:GetModuleConfig()
            return {
                colors = {
                    [ns.Constants.RESOURCEBAR_TYPE_ICICLES] = { r = 0.2, g = 0.3, b = 0.4, a = 1 },
                },
                maxColorsEnabled = {
                    [ns.Constants.RESOURCEBAR_TYPE_ICICLES] = true,
                },
                maxColors = {
                    [ns.Constants.RESOURCEBAR_TYPE_ICICLES] = { r = 1, g = 1, b = 1, a = 1 },
                },
            }
        end
        assert.same({ r = 1, g = 1, b = 1, a = 1 }, ResourceBar:GetStatusBarColor())

        currentValues = { 5, 3, 5 }
        assert.same({ r = 0.2, g = 0.3, b = 0.4, a = 1 }, ResourceBar:GetStatusBarColor())
    end)

    it("does not define its own Refresh (uses base BarProto.Refresh with GetTickSpec)", function()
        assert.is_nil(rawget(ResourceBar, 'Refresh'))
    end)
end)
