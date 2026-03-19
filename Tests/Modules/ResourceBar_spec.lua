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
    local barRefreshResult

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({ "ECM" })
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
        barRefreshResult = true

        _G.ECM = {
            FrameMixin = {
                ShouldShow = function()
                    return true
                end,
            },
            BarMixin = {
                Refresh = function()
                    return barRefreshResult
                end,
                AddMixin = function()
                    addMixinCalls = addMixinCalls + 1
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
            RegisterFrame = function()
                registerFrameCalls = registerFrameCalls + 1
            end,
            UnregisterFrame = function()
                unregisterFrameCalls = unregisterFrameCalls + 1
            end,
            Log = function() end,
        }
        TestHelpers.LoadChunk("ECM_Constants.lua", "Unable to load ECM_Constants.lua")()

        ns = {
            Addon = {
                NewModule = function(self, name)
                    local module = { Name = name }
                    self[name] = module
                    return module
                end,
            },
        }

        TestHelpers.LoadChunk("Modules/ResourceBar.lua", "Unable to load Modules/ResourceBar.lua")(nil, ns)
        ResourceBar = assert(ns.Addon.ResourceBar, "ResourceBar module did not initialize")
    end)

    it("ShouldShow requires a current resource type", function()
        assert.is_true(ResourceBar:ShouldShow())

        currentResourceType = nil
        assert.is_false(ResourceBar:ShouldShow())
    end)

    it("Refresh lays out ticks for safe discrete resources", function()
        local ensureCount
        local layoutCount
        local hidePoolKey
        ResourceBar.InnerFrame = { TicksFrame = {} }
        function ResourceBar:EnsureTicks(count)
            ensureCount = count
        end
        function ResourceBar:LayoutResourceTicks(maxResources)
            layoutCount = maxResources
        end
        function ResourceBar:HideAllTicks(poolKey)
            hidePoolKey = poolKey
        end

        assert.is_true(ResourceBar:Refresh("test"))
        assert.are.equal(4, ensureCount)
        assert.are.equal(5, layoutCount)
        assert.is_nil(hidePoolKey)
    end)

    it("Refresh hides ticks for devourer resources", function()
        local hidePoolKey
        currentResourceType = ECM.Constants.RESOURCEBAR_TYPE_DEVOURER_NORMAL
        currentValues = { 30, 4, 30 }
        ResourceBar.InnerFrame = { TicksFrame = {} }
        function ResourceBar:EnsureTicks()
            error("EnsureTicks should not be called for devourer resources")
        end
        function ResourceBar:LayoutResourceTicks()
            error("LayoutResourceTicks should not be called for devourer resources")
        end
        function ResourceBar:HideAllTicks(poolKey)
            hidePoolKey = poolKey
        end

        assert.is_true(ResourceBar:Refresh("test"))
        assert.are.equal("tickPool", hidePoolKey)
    end)

    it("Refresh hides ticks when safeMax is nil or too small", function()
        local hidePoolKey
        currentValues = { 1, 1, nil }
        ResourceBar.InnerFrame = { TicksFrame = {} }
        function ResourceBar:EnsureTicks()
            error("EnsureTicks should not be called when safeMax is nil")
        end
        function ResourceBar:LayoutResourceTicks()
            error("LayoutResourceTicks should not be called when safeMax is nil")
        end
        function ResourceBar:HideAllTicks(poolKey)
            hidePoolKey = poolKey
        end

        assert.is_true(ResourceBar:Refresh("test"))
        assert.are.equal("tickPool", hidePoolKey)
    end)

    it("only updates for player UNIT_AURA events and always updates for other events", function()
        local reasons = {}
        function ResourceBar:ThrottledUpdateLayout(reason)
            reasons[#reasons + 1] = reason
        end

        ResourceBar:OnEventUpdate("UNIT_AURA", "target")
        ResourceBar:OnEventUpdate("UNIT_AURA", "player")
        ResourceBar:OnEventUpdate("UNIT_POWER_UPDATE")

        assert.same({ "UNIT_AURA", "UNIT_POWER_UPDATE" }, reasons)
    end)

    it("registers and unregisters with the frame system", function()
        function ResourceBar:RegisterEvent() end
        function ResourceBar:UnregisterAllEvents() end

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
        currentResourceType = ECM.Constants.RESOURCEBAR_TYPE_ICICLES
        currentValues = { 5, 5, 5 }
        function ResourceBar:GetModuleConfig()
            return {
                colors = {
                    [ECM.Constants.RESOURCEBAR_TYPE_ICICLES] = { r = 0.2, g = 0.3, b = 0.4, a = 1 },
                },
                maxColorsEnabled = {
                    [ECM.Constants.RESOURCEBAR_TYPE_ICICLES] = true,
                },
                maxColors = {
                    [ECM.Constants.RESOURCEBAR_TYPE_ICICLES] = { r = 1, g = 1, b = 1, a = 1 },
                },
            }
        end
        assert.same({ r = 1, g = 1, b = 1, a = 1 }, ResourceBar:GetStatusBarColor())

        currentValues = { 5, 3, 5 }
        assert.same({ r = 0.2, g = 0.3, b = 0.4, a = 1 }, ResourceBar:GetStatusBarColor())
    end)

    it("returns false from Refresh when the base bar refresh stops the update", function()
        barRefreshResult = false
        ResourceBar.InnerFrame = { TicksFrame = {} }

        assert.is_false(ResourceBar:Refresh("test"))
    end)
end)
