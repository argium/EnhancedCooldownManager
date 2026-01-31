
local LAYOUT_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_ENTERING_WORLD",
}

local _, ns = ...
local ECM = ns.Addon
local _ecmFrames = {}

local function RegisterFrame(frame)
    assert(frame and type(frame) == "table" and frame.IsECMFrame, "RegisterFrame: invalid ECMFrame")
    assert(_ecmFrames[frame.Name] == nil, "RegisterFrame: frame with name '" .. frame.Name .. "' is already registered")
    _ecmFrames[frame.Name] = frame
    ECM.Log("Layout", "Frame registered", frame.Name)
end

ECM.RegisterFrame = RegisterFrame

-- Event handler frame to dispatch layout update events to registered ECMFrames.
local eventFrame = CreateFrame("Frame")
for _, eventName in ipairs(LAYOUT_EVENTS) do
    eventFrame:RegisterEvent(eventName)
end
eventFrame:SetScript("OnEvent", function(self, event, ...)
    for _, frame in pairs(_ecmFrames) do
        frame:UpdateLayout(event, ...)
    end
end)
