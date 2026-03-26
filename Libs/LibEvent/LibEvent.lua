-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

---@class LibEvent
---@field embeds table<table, { frame: Frame, _events: table<string, function[]>, _stats: table<string, number> }> Stores embedded event instances by target table.

local MAJOR, MINOR = "LibEvent-1.0", 3
local LibEvent = LibStub:NewLibrary(MAJOR, MINOR)

if not LibEvent then
    return
end

local ipairs = ipairs
local pairs = pairs
local type = type
local wipe = wipe

LibEvent.embeds = LibEvent.embeds or {}

local function getInstance(target)
    local instance = LibEvent.embeds[target]
    assert(type(instance) == "table", "LibEvent target is not embedded")
    return instance
end

---Registers a callback for a WoW event on the embedded target.
---@param event string The event name to register.
---@param callback fun(target: table, event: string, ...: any) The callback function to invoke.
function LibEvent:RegisterEvent(event, callback)
    local instance = getInstance(self)
    assert(type(event) == "string" and event ~= "", "Usage: RegisterEvent(event, callback)")
    assert(type(callback) == "function", "Callback must be a function")

    local callbacks = instance._events[event]
    if not callbacks then
        callbacks = {}
        instance._events[event] = callbacks
        instance.frame:RegisterEvent(event)
    end

    for i = 1, #callbacks do
        if callbacks[i] == callback then
            return
        end
    end

    callbacks[#callbacks + 1] = callback
end

---Unregisters a previously registered WoW event callback from the embedded target.
---@param event string The event name to unregister.
---@param callback? fun(target: table, event: string, ...: any) Specific callback to remove. If omitted, removes all callbacks for the event.
function LibEvent:UnregisterEvent(event, callback)
    local instance = getInstance(self)
    local callbacks = instance._events[event]
    if not callbacks then
        return
    end

    if callback == nil then
        instance._events[event] = nil
        instance.frame:UnregisterEvent(event)
        return
    end

    assert(type(callback) == "function", "Callback must be a function")

    for i = #callbacks, 1, -1 do
        if callbacks[i] == callback then
            table.remove(callbacks, i)
            break
        end
    end

    if #callbacks == 0 then
        instance._events[event] = nil
        instance.frame:UnregisterEvent(event)
    end
end

---Unregisters all WoW events currently registered on the embedded target.
function LibEvent:UnregisterAllEvents()
    local instance = getInstance(self)
    for event in pairs(instance._events) do
        instance.frame:UnregisterEvent(event)
        instance._events[event] = nil
    end
end

---Gets the event invocation stats for this embedded target.
---@return table<string, number> A table mapping event names to their fire counts.
function LibEvent:GetEventStats()
    return getInstance(self)._stats
end

---Resets the event invocation stats for this embedded target.
function LibEvent:ResetEventStats()
    wipe(getInstance(self)._stats)
end

local function createInstance(target)
    local instance = LibEvent.embeds[target]
    if type(instance) ~= "table" then
        instance = { _events = {}, _stats = {} }
    else
        -- Preserve existing events and stats on re-embed (library upgrade)
        instance._events = instance._events or {}
        instance._stats = instance._stats or {}
    end

    instance.frame = instance.frame or CreateFrame("Frame")

    -- Dispatch without snapshot: use index-based iteration that tolerates
    -- mid-loop unregisters (reverse iteration is not needed because
    -- unregister shifts elements down — we just re-check the current index).
    instance.frame:SetScript("OnEvent", function(_, event, ...)
        local cbs = instance._events[event]
        if not cbs then
            return
        end
        instance._stats[event] = (instance._stats[event] or 0) + 1
        instance._dispatching = true
        local i = 1
        while i <= #cbs do
            local cb = cbs[i]
            cb(target, event, ...)
            -- Advance only if the callback wasn't removed during dispatch
            if i <= #cbs and cbs[i] == cb then
                i = i + 1
            end
        end
        instance._dispatching = false
    end)

    LibEvent.embeds[target] = instance
    return instance
end

local mixins = {
    "RegisterEvent",
    "UnregisterEvent",
    "UnregisterAllEvents",
    "GetEventStats",
    "ResetEventStats",
}

---Embeds the LibEvent API into a target table.
---@param target table The table receiving the LibEvent methods.
---@return table target The same target table after embedding.
function LibEvent:Embed(target)
    createInstance(target)

    for _, methodName in ipairs(mixins) do
        target[methodName] = self[methodName]
    end

    return target
end

---Disables an embedded target by unregistering all of its events.
---@param target table The embedded target to disable.
function LibEvent:OnEmbedDisable(target)
    target:UnregisterAllEvents()
end

for target in pairs(LibEvent.embeds) do
    LibEvent:Embed(target)
end
