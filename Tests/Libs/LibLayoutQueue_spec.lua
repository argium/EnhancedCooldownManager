-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local TestHelpers =
    assert(loadfile("Tests/TestHelpers.lua") or loadfile("TestHelpers.lua"), "Unable to load Tests/TestHelpers.lua")()

describe("LibLayoutQueue", function()
    local originalGlobals
    local LibLayoutQueue
    local timerQueue

    setup(function()
        originalGlobals = TestHelpers.CaptureGlobals({
            "C_Timer",
            "LibStub",
        })
    end)

    teardown(function()
        TestHelpers.RestoreGlobals(originalGlobals)
    end)

    before_each(function()
        timerQueue = {}

        TestHelpers.SetupLibStub()
        _G.C_Timer = {
            After = function(delay, callback)
                timerQueue[#timerQueue + 1] = { delay = delay, callback = callback }
            end,
        }

        TestHelpers.LoadChunk("Libs/LibLayoutQueue/LibLayoutQueue.lua", "Unable to load LibLayoutQueue.lua")()
        LibLayoutQueue = assert(LibStub("LibLayoutQueue-1.0"), "LibLayoutQueue-1.0 was not registered")
    end)

    it("flushes layout work in order, using registration order as the tie-breaker", function()
        local queue = LibLayoutQueue:Create()
        local calls = {}
        local first = { id = "first" }
        local second = { id = "second" }
        local third = { id = "third" }

        local function captureLayout(target, reason)
            calls[#calls + 1] = target.id .. ":" .. reason
        end

        queue:Register(second, { order = 20, layout = captureLayout })
        queue:Register(first, { order = 10, layout = captureLayout })
        queue:Register(third, { order = 20, layout = captureLayout })

        queue:RequestLayout("Batch")

        assert.are.equal(1, #timerQueue)
        timerQueue[1].callback()

        assert.same({
            "first:Batch",
            "second:Batch",
            "third:Batch",
        }, calls)
    end)

    it("keeps the first layout reason until the deferred flush runs", function()
        local queue = LibLayoutQueue:Create()
        local target = {}
        local reasons = {}

        queue:Register(target, {
            layout = function(_, reason)
                reasons[#reasons + 1] = reason
            end,
        })

        queue:RequestLayout(target, "First")
        queue:RequestLayout(target, "Second")

        assert.are.equal(1, #timerQueue)

        timerQueue[1].callback()

        assert.same({ "First" }, reasons)
    end)

    it("runs layout before refresh when both are pending in the same batch", function()
        local queue = LibLayoutQueue:Create()
        local target = {}
        local calls = {}

        queue:Register(target, {
            layout = function(_, reason)
                calls[#calls + 1] = "layout:" .. reason
            end,
            refresh = function(_, reason)
                calls[#calls + 1] = "refresh:" .. reason
            end,
        })

        queue:RequestLayout(target, "LayoutPass")
        queue:RequestRefresh(target, "RefreshPass")

        assert.are.equal(1, #timerQueue)

        timerQueue[1].callback()

        assert.same({
            "layout:LayoutPass",
            "refresh:RefreshPass",
        }, calls)
    end)

    it("flushes immediately when opts.immediate is true", function()
        local queue = LibLayoutQueue:Create()
        local target = {}
        local calls = {}

        queue:Register(target, {
            layout = function(_, reason)
                calls[#calls + 1] = reason
            end,
        })

        queue:RequestLayout(target, "Immediate", { immediate = true })

        assert.same({ "Immediate" }, calls)
        assert.are.equal(0, #timerQueue)
    end)

    it("supports reason-only all-target refresh requests", function()
        local queue = LibLayoutQueue:Create()
        local calls = {}
        local first = { id = "first" }
        local second = { id = "second" }

        queue:Register(first, {
            order = 20,
            refresh = function(target, reason)
                calls[#calls + 1] = target.id .. ":" .. reason
            end,
        })
        queue:Register(second, {
            order = 10,
            refresh = function(target, reason)
                calls[#calls + 1] = target.id .. ":" .. reason
            end,
        })

        queue:RequestRefresh("Tick", { immediate = true })

        assert.same({
            "second:Tick",
            "first:Tick",
        }, calls)
        assert.are.equal(0, #timerQueue)
    end)

    it("coalesces mixed deferred requests behind one timer", function()
        local queue = LibLayoutQueue:Create()
        local calls = {}
        local target = {}

        queue:Register(target, {
            layout = function(_, reason)
                calls[#calls + 1] = "layout:" .. reason
            end,
            refresh = function(_, reason)
                calls[#calls + 1] = "refresh:" .. reason
            end,
        })

        queue:RequestLayout(target, "Layout")
        queue:RequestRefresh(target, "Refresh")
        queue:RequestLayout(target, "IgnoredSecondLayoutReason")

        assert.are.equal(1, #timerQueue)

        timerQueue[1].callback()

        assert.same({
            "layout:Layout",
            "refresh:Refresh",
        }, calls)
    end)

    it("skips pending work for a target that was unregistered before the flush", function()
        local queue = LibLayoutQueue:Create()
        local target = {}
        local calls = 0

        queue:Register(target, {
            layout = function()
                calls = calls + 1
            end,
        })

        queue:RequestLayout(target, "Queued")
        queue:Unregister(target)

        assert.are.equal(1, #timerQueue)

        timerQueue[1].callback()

        assert.are.equal(0, calls)
    end)

    it("asserts when targeted work is requested for an unregistered target", function()
        local queue = LibLayoutQueue:Create()

        assert.has_error(function()
            queue:RequestLayout({}, "BadTarget")
        end, "LibLayoutQueue target is not registered")
    end)
end)
