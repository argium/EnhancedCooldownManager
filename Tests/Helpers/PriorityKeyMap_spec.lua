-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("PriorityKeyMap", function()
    local originalGlobals
    local PriorityKeyMap
    local scope
    local now

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({ "ECM", "time", "unpack" })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        now = 100
        scope = {
            byName = {},
            bySpellID = {},
            byTexture = {},
        }

        _G.time = function()
            return now
        end
        _G.ECM = {
            DebugAssert = function(condition, message)
                if not condition then
                    error(message or "ECM.DebugAssert failed")
                end
            end,
            Log = function() end,
            ToString = function(value)
                return tostring(value)
            end,
        }

        TestHelpers.LoadChunk("Helpers/PriorityKeyMap.lua", "Unable to load Helpers/PriorityKeyMap.lua")()
        PriorityKeyMap = assert(ECM.PriorityKeyMap, "PriorityKeyMap did not initialize")
    end)

    local function makeMap()
        return PriorityKeyMap.New({ "byName", "bySpellID", "byTexture" }, function()
            return scope
        end, function(key)
            return key
        end)
    end

    it("Set stores a single stamped entry across all valid keys", function()
        local map = makeMap()

        map:Set({ "Arcane Intellect", 1459, 135932 }, "blue", { source = "test" })

        assert.are.equal("blue", map:Get({ "Arcane Intellect", nil, nil }))
        assert.are.equal(scope.byName["Arcane Intellect"], scope.bySpellID[1459])
        assert.are.equal(scope.bySpellID[1459], scope.byTexture[135932])
        assert.are.equal("test", scope.byName["Arcane Intellect"].meta.source)
    end)

    it("Get reconciles later keys even when earlier keys are nil", function()
        local map = makeMap()

        scope.byTexture[999] = { value = "fallback", t = 25 }

        assert.are.equal("fallback", map:Get({ nil, nil, 999 }))
    end)

    it("Reconcile propagates the most recent stamped value", function()
        local map = makeMap()

        scope.byName.foo = { value = "old", t = 10 }
        scope.bySpellID[1] = { value = "new", t = 20 }

        assert.is_true(map:Reconcile({ "foo", 1, nil }))
        assert.are.equal("new", map:Get({ "foo", 1, nil }))
        assert.are.equal(scope.bySpellID[1], scope.byName.foo)
    end)

    it("ReconcileAll returns the number of changed key groups", function()
        local map = makeMap()

        scope.byName.alpha = { value = "a", t = 5 }
        scope.bySpellID[11] = { value = "b", t = 6 }
        scope.byName.beta = { value = "c", t = 7 }
        scope.byTexture[22] = { value = "d", t = 8 }

        local changed = map:ReconcileAll({
            { "alpha", 11, nil },
            { "beta", nil, 22 },
            { "gamma", nil, nil },
        })

        assert.are.equal(2, changed)
    end)

    it("Remove clears per-tier values and GetAll prefers higher priority tiers", function()
        local map = makeMap()

        scope.byTexture.shared = { value = "low", t = 1 }
        scope.byName.shared = { value = "high", t = 2 }
        map:Set({ "only", 42, nil }, "value")

        local all = map:GetAll()
        assert.are.equal("high", all.shared)
        assert.are.equal("value", all.only)

        local clearedName, clearedSpellID, clearedTexture = map:Remove({ "only", 42, 500 })
        assert.is_true(clearedName)
        assert.is_true(clearedSpellID)
        assert.is_false(clearedTexture)
        assert.is_nil(map:Get({ "only", 42, nil }))
    end)
end)
