-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

local _ = ...
local LSM = LibStub("LibSharedMedia-3.0", true)

local function GetLSMValues(mediaType, fallback)
    local values = {}
    if LSM and LSM.List then
        for _, name in ipairs(LSM:List(mediaType)) do
            values[name] = name
        end
    end

    if not next(values) then
        values[fallback] = fallback
    end

    return values
end

local function GetStatusbarValues()
    return GetLSMValues("statusbar", "Blizzard")
end

local function GetFontValues()
    return GetLSMValues("font", "Expressway")
end

ECM.SharedMediaOptions = {
    GetStatusbarValues = GetStatusbarValues,
    GetFontValues = GetFontValues,
}
