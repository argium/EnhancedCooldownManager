-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

---@class LibEvent
---@field embeds table<table, { frame: Frame, _events: table<string, function[]> }> Stores embedded event instances by target table.

local MAJOR, MINOR = "LibEvent-1.0", 2
local LibEvent = LibStub:NewLibrary(MAJOR, MINOR)

if not LibEvent then
    return
end

local ipairs = ipairs
local pairs = pairs
local type = type

LibEvent.embeds = LibEvent.embeds or {}

local function resolveCallback(target, event, callback)
    if callback == nil then
        return target[event]
    end

    if type(callback) == "string" then
        return target[callback]
    end

    return callback
end

local function getInstance(target)
    local instance = LibEvent.embeds[target]
    assert(type(instance) == "table", "LibEvent target is not embedded")
    return instance
end

---Registers a callback for a WoW event on the embedded target.
---If the same callback is already registered for this event, the call is a no-op.
---@param event string The event name to register.
---@param callback? string|fun(target: table, event: string, ...: any) The callback function or method name to invoke.
function LibEvent:RegisterEvent(event, callback)
    local instance = getInstance(self)
    assert(type(event) == "string" and event ~= "", "Usage: RegisterEvent(event, [callback])")

    callback = resolveCallback(self, event, callback)
    assert(type(callback) == "function", "Callback must resolve to a function")

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
---@param callback? string|fun(target: table, event: string, ...: any) Specific callback to remove. If omitted, removes all callbacks for the event.
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

    if type(callback) == "string" then
        callback = self[callback]
    end

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

local function createInstance(target)
    local instance = LibEvent.embeds[target]
    if type(instance) ~= "table" then
        instance = {}
    end

    instance.frame = instance.frame or CreateFrame("Frame")
    instance._events = instance._events or {}

    instance.frame:SetScript("OnEvent", function(_, event, ...)
        local callbacks = instance._events[event]
        if not callbacks then
            return
        end
        local snapshot = {}
        for i = 1, #callbacks do
            snapshot[i] = callbacks[i]
        end
        for i = 1, #snapshot do
            snapshot[i](target, event, ...)
        end
    end)

    LibEvent.embeds[target] = instance
    return instance
end

local mixins = {
    "RegisterEvent",
    "UnregisterEvent",
    "UnregisterAllEvents",
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
