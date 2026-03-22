-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibEvent", function()
    local originalGlobals
    local createFrameCalls
    local createdFrames
    local LibEvent

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "CreateFrame",
            "LibStub",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        createFrameCalls = 0
        createdFrames = {}

        TestHelpers.SetupLibStub()

        _G.CreateFrame = function(_, name)
            createFrameCalls = createFrameCalls + 1
            local frame = {
                name = name,
                registeredEvents = {},
                unregisteredEvents = {},
            }

            function frame:RegisterEvent(event)
                self.registeredEvents[#self.registeredEvents + 1] = event
            end

            function frame:UnregisterEvent(event)
                self.unregisteredEvents[#self.unregisteredEvents + 1] = event
            end

            function frame:SetScript(scriptName, callback)
                self.scriptName = scriptName
                self.onEvent = callback
            end

            createdFrames[#createdFrames + 1] = frame
            return frame
        end

        TestHelpers.LoadChunk("Libs/LibEvent/LibEvent.lua", "Unable to load LibEvent.lua")()
        LibEvent = assert(LibStub("LibEvent-1.0"), "LibEvent-1.0 was not registered")
    end)

    it("does not create an event frame until a target is embedded", function()
        assert.are.equal(0, createFrameCalls)

        local target = {}
        LibEvent:Embed(target)

        assert.are.equal(1, createFrameCalls)
        assert.are.equal("OnEvent", createdFrames[1].scriptName)
        assert.is_function(createdFrames[1].onEvent)
    end)

    it("embeds event methods onto targets", function()
        local target = {}

        LibEvent:Embed(target)

        assert.are.equal(LibEvent.RegisterEvent, target.RegisterEvent)
        assert.are.equal(LibEvent.UnregisterEvent, target.UnregisterEvent)
        assert.are.equal(LibEvent.UnregisterAllEvents, target.UnregisterAllEvents)
    end)

    it("creates a distinct frame per embedded target", function()
        local first = {}
        local second = {}

        LibEvent:Embed(first)
        LibEvent:Embed(second)

        assert.are.equal(2, createFrameCalls)
        assert.are_not.equal(createdFrames[1], createdFrames[2])
        assert.are.equal(createdFrames[1], LibEvent.embeds[first].frame)
        assert.are.equal(createdFrames[2], LibEvent.embeds[second].frame)
    end)

    it("dispatches to the default event-named method", function()
        local calls = {}
        local target = {
            TEST_EVENT = function(self, event, arg1, arg2)
                calls[#calls + 1] = { self = self, event = event, arg1 = arg1, arg2 = arg2 }
            end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT", "a", "b")

        assert.are.equal(1, #calls)
        assert.are.equal(target, calls[1].self)
        assert.are.equal("TEST_EVENT", calls[1].event)
        assert.are.equal("a", calls[1].arg1)
        assert.are.equal("b", calls[1].arg2)
    end)

    it("dispatches to an explicitly named method", function()
        local calls = {}
        local target = {
            HandleEvent = function(self, event, arg1)
                calls[#calls + 1] = { self = self, event = event, arg1 = arg1 }
            end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", "HandleEvent")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT", 42)

        assert.are.equal(1, #calls)
        assert.are.equal(target, calls[1].self)
        assert.are.equal("TEST_EVENT", calls[1].event)
        assert.are.equal(42, calls[1].arg1)
    end)

    it("dispatches to a function callback", function()
        local calls = {}
        local target = {}
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", function(self, event, arg1)
            calls[#calls + 1] = { self = self, event = event, arg1 = arg1 }
        end)
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT", "payload")

        assert.are.equal(1, #calls)
        assert.are.equal(target, calls[1].self)
        assert.are.equal("TEST_EVENT", calls[1].event)
        assert.are.equal("payload", calls[1].arg1)
    end)

    it("registers the same event independently on each target frame", function()
        local first = { TEST_EVENT = function() end }
        local second = { TEST_EVENT = function() end }
        LibEvent:Embed(first)
        LibEvent:Embed(second)

        first:RegisterEvent("TEST_EVENT")
        second:RegisterEvent("TEST_EVENT")

        assert.same({ "TEST_EVENT" }, LibEvent.embeds[first].frame.registeredEvents)
        assert.same({ "TEST_EVENT" }, LibEvent.embeds[second].frame.registeredEvents)
    end)

    it("unregisters a specific target without affecting others", function()
        local firstCalls = 0
        local secondCalls = 0
        local first = {
            TEST_EVENT = function()
                firstCalls = firstCalls + 1
            end,
        }
        local second = {
            TEST_EVENT = function()
                secondCalls = secondCalls + 1
            end,
        }
        LibEvent:Embed(first)
        LibEvent:Embed(second)

        first:RegisterEvent("TEST_EVENT")
        second:RegisterEvent("TEST_EVENT")
        first:UnregisterEvent("TEST_EVENT")
        LibEvent.embeds[first].frame.onEvent(nil, "TEST_EVENT")
        LibEvent.embeds[second].frame.onEvent(nil, "TEST_EVENT")

        assert.are.equal(0, firstCalls)
        assert.are.equal(1, secondCalls)
        assert.same({ "TEST_EVENT" }, LibEvent.embeds[first].frame.unregisteredEvents)
        assert.same({}, LibEvent.embeds[second].frame.unregisteredEvents)
    end)

    it("unregisters the target frame event when removed", function()
        local target = { TEST_EVENT = function() end }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT")
        target:UnregisterEvent("TEST_EVENT")

        assert.same({ "TEST_EVENT" }, LibEvent.embeds[target].frame.unregisteredEvents)
    end)

    it("unregisters all events for a target", function()
        local target = {
            TEST_EVENT = function() end,
            OTHER_EVENT = function() end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT")
        target:RegisterEvent("OTHER_EVENT")
        target:UnregisterAllEvents()

        local instance = LibEvent.embeds[target]
        assert.are.equal(2, #instance.frame.unregisteredEvents)
        assert.is_nil(instance._events.TEST_EVENT)
        assert.is_nil(instance._events.OTHER_EVENT)
    end)

    it("cleans up via OnEmbedDisable", function()
        local target = { TEST_EVENT = function() end }
        LibEvent:Embed(target)
        target:RegisterEvent("TEST_EVENT")

        LibEvent:OnEmbedDisable(target)

        assert.same({ "TEST_EVENT" }, LibEvent.embeds[target].frame.unregisteredEvents)
        assert.is_nil(LibEvent.embeds[target]._events.TEST_EVENT)
    end)

    it("fires multiple callbacks registered for the same event", function()
        local firstCalls = 0
        local secondCalls = 0
        local target = {
            First = function()
                firstCalls = firstCalls + 1
            end,
            Second = function()
                secondCalls = secondCalls + 1
            end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", "First")
        target:RegisterEvent("TEST_EVENT", "Second")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        assert.same({ "TEST_EVENT" }, LibEvent.embeds[target].frame.registeredEvents)
        assert.are.equal(1, firstCalls)
        assert.are.equal(1, secondCalls)
    end)

    it("is idempotent when the same callback is registered twice", function()
        local calls = 0
        local target = {
            Handler = function()
                calls = calls + 1
            end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", "Handler")
        target:RegisterEvent("TEST_EVENT", "Handler")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        assert.are.equal(1, calls)
    end)

    it("removes only a specific callback when UnregisterEvent is given a callback", function()
        local firstCalls = 0
        local secondCalls = 0
        local target = {
            First = function()
                firstCalls = firstCalls + 1
            end,
            Second = function()
                secondCalls = secondCalls + 1
            end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", "First")
        target:RegisterEvent("TEST_EVENT", "Second")
        target:UnregisterEvent("TEST_EVENT", "First")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        assert.are.equal(0, firstCalls)
        assert.are.equal(1, secondCalls)
        assert.same({}, LibEvent.embeds[target].frame.unregisteredEvents)
    end)

    it("unregisters the frame event when the last specific callback is removed", function()
        local target = {
            Handler = function() end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", "Handler")
        target:UnregisterEvent("TEST_EVENT", "Handler")

        assert.same({ "TEST_EVENT" }, LibEvent.embeds[target].frame.unregisteredEvents)
        assert.is_nil(LibEvent.embeds[target]._events.TEST_EVENT)
    end)

    it("removes all callbacks when UnregisterEvent is called without a callback", function()
        local firstCalls = 0
        local secondCalls = 0
        local target = {
            First = function()
                firstCalls = firstCalls + 1
            end,
            Second = function()
                secondCalls = secondCalls + 1
            end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT", "First")
        target:RegisterEvent("TEST_EVENT", "Second")
        target:UnregisterEvent("TEST_EVENT")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        assert.are.equal(0, firstCalls)
        assert.are.equal(0, secondCalls)
        assert.same({ "TEST_EVENT" }, LibEvent.embeds[target].frame.unregisteredEvents)
    end)

    it("handles a callback unregistering itself during dispatch", function()
        local calls = {}
        local target = {}
        LibEvent:Embed(target)

        local selfRemovingCb
        selfRemovingCb = function(self, event)
            calls[#calls + 1] = "self-removing"
            self:UnregisterEvent(event, selfRemovingCb)
        end

        local stableCb = function(_, _)
            calls[#calls + 1] = "stable"
        end

        target:RegisterEvent("TEST_EVENT", selfRemovingCb)
        target:RegisterEvent("TEST_EVENT", stableCb)
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        assert.same({ "self-removing", "stable" }, calls)

        -- Second dispatch: only stable callback remains
        calls = {}
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")
        assert.same({ "stable" }, calls)
    end)

    it("initializes _stats as an empty table", function()
        local target = {}
        LibEvent:Embed(target)
        assert.same({}, LibEvent.embeds[target]._stats)
    end)

    it("increments _stats on each event fire", function()
        local target = { TEST_EVENT = function() end }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        assert.are.equal(3, LibEvent.embeds[target]._stats.TEST_EVENT)
    end)

    it("tracks stats independently per event", function()
        local target = {
            EVENT_A = function() end,
            EVENT_B = function() end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("EVENT_A")
        target:RegisterEvent("EVENT_B")
        LibEvent.embeds[target].frame.onEvent(nil, "EVENT_A")
        LibEvent.embeds[target].frame.onEvent(nil, "EVENT_A")
        LibEvent.embeds[target].frame.onEvent(nil, "EVENT_B")

        assert.are.equal(2, LibEvent.embeds[target]._stats.EVENT_A)
        assert.are.equal(1, LibEvent.embeds[target]._stats.EVENT_B)
    end)

    it("tracks stats independently per target", function()
        local first = { TEST_EVENT = function() end }
        local second = { TEST_EVENT = function() end }
        LibEvent:Embed(first)
        LibEvent:Embed(second)

        first:RegisterEvent("TEST_EVENT")
        second:RegisterEvent("TEST_EVENT")
        LibEvent.embeds[first].frame.onEvent(nil, "TEST_EVENT")
        LibEvent.embeds[second].frame.onEvent(nil, "TEST_EVENT")
        LibEvent.embeds[second].frame.onEvent(nil, "TEST_EVENT")

        assert.are.equal(1, LibEvent.embeds[first]._stats.TEST_EVENT)
        assert.are.equal(2, LibEvent.embeds[second]._stats.TEST_EVENT)
    end)

    it("GetEventStats returns the target's _stats table", function()
        local target = { TEST_EVENT = function() end }
        LibEvent:Embed(target)

        target:RegisterEvent("TEST_EVENT")
        LibEvent.embeds[target].frame.onEvent(nil, "TEST_EVENT")

        local stats = target:GetEventStats()
        assert.are.equal(LibEvent.embeds[target]._stats, stats)
        assert.are.equal(1, stats.TEST_EVENT)
    end)

    it("ResetEventStats clears all counters for the target", function()
        local target = {
            EVENT_A = function() end,
            EVENT_B = function() end,
        }
        LibEvent:Embed(target)

        target:RegisterEvent("EVENT_A")
        target:RegisterEvent("EVENT_B")
        LibEvent.embeds[target].frame.onEvent(nil, "EVENT_A")
        LibEvent.embeds[target].frame.onEvent(nil, "EVENT_B")

        target:ResetEventStats()

        assert.same({}, target:GetEventStats())
    end)

    it("ResetEventStats does not affect other targets", function()
        local first = { TEST_EVENT = function() end }
        local second = { TEST_EVENT = function() end }
        LibEvent:Embed(first)
        LibEvent:Embed(second)

        first:RegisterEvent("TEST_EVENT")
        second:RegisterEvent("TEST_EVENT")
        LibEvent.embeds[first].frame.onEvent(nil, "TEST_EVENT")
        LibEvent.embeds[second].frame.onEvent(nil, "TEST_EVENT")

        first:ResetEventStats()

        assert.same({}, first:GetEventStats())
        assert.are.equal(1, second:GetEventStats().TEST_EVENT)
    end)

    it("does not increment stats when no callbacks are registered for the event", function()
        local target = {}
        LibEvent:Embed(target)

        LibEvent.embeds[target].frame.onEvent(nil, "UNREGISTERED_EVENT")

        assert.is_nil(target:GetEventStats().UNREGISTERED_EVENT)
    end)
end)
