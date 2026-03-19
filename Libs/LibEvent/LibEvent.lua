-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local MAJOR, MINOR = "LibEvent-1.0", 1
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

function LibEvent:RegisterEvent(event, callback)
    local instance = getInstance(self)
    assert(type(event) == "string" and event ~= "", "Usage: RegisterEvent(event, [callback])")

    callback = resolveCallback(self, event, callback)
    assert(type(callback) == "function", "Callback must resolve to a function")

    if not instance._events[event] then
        instance.frame:RegisterEvent(event)
    end

    instance._events[event] = callback
end

function LibEvent:UnregisterEvent(event)
    local instance = getInstance(self)
    if not instance._events[event] then
        return
    end

    instance._events[event] = nil
    instance.frame:UnregisterEvent(event)
end

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
        local callback = instance._events[event]
        if callback then
            callback(target, event, ...)
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

function LibEvent:Embed(target)
    createInstance(target)

    for _, methodName in ipairs(mixins) do
        target[methodName] = self[methodName]
    end

    return target
end

function LibEvent:OnEmbedDisable(target)
    target:UnregisterAllEvents()
end

for target in pairs(LibEvent.embeds) do
    LibEvent:Embed(target)
end
