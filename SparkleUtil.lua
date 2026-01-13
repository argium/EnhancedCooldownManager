local _, ns = ...

local SparkleUtil = ns.SparkleUtil or {}
ns.SparkleUtil = SparkleUtil

--------------------------------------------------------------------------------
-- Text / RGB helpers
--------------------------------------------------------------------------------

local function Clamp(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

---@param v any
---@return number
local function ToNumberOrError(v)
    local n = tonumber(v)
    assert(type(n) == "number", "ECM.Util: expected number")
    return n
end

---@param color any
---@return number r 0..1
---@return number g 0..1
---@return number b 0..1
local function NormalizeRGB(color)
    assert(color ~= nil, "ECM.Util: color is required")

    if type(color) == "string" then
        local hex = color:gsub("^#", "")
        if #hex == 8 then
            -- Accept AARRGGBB and ignore alpha.
            hex = hex:sub(3, 8)
        end
        assert(#hex == 6, "ECM.Util: hex color must be RRGGBB or #RRGGBB")

        local r = tonumber(hex:sub(1, 2), 16)
        local g = tonumber(hex:sub(3, 4), 16)
        local b = tonumber(hex:sub(5, 6), 16)
        assert(r and g and b, "ECM.Util: invalid hex color")
        return r / 255, g / 255, b / 255
    end

    if type(color) == "table" then
        local r = ToNumberOrError(color[1])
        local g = ToNumberOrError(color[2])
        local b = ToNumberOrError(color[3])

        -- Treat values > 1 as 0..255.
        if r > 1 or g > 1 or b > 1 then
            return Clamp(r / 255, 0, 1), Clamp(g / 255, 0, 1), Clamp(b / 255, 0, 1)
        end
        return Clamp(r, 0, 1), Clamp(g, 0, 1), Clamp(b, 0, 1)
    end

    error("ECM.Util: unsupported color type: " .. type(color))
end

---@param t number 0..1
---@param r1 number
---@param g1 number
---@param b1 number
---@param r2 number
---@param g2 number
---@param b2 number
---@return number r
---@return number g
---@return number b
local function LerpRGB(t, r1, g1, b1, r2, g2, b2)
    return (r1 + (r2 - r1) * t), (g1 + (g2 - g1) * t), (b1 + (b2 - b1) * t)
end

---@param t number 0..1
---@param sr number
---@param sg number
---@param sb number
---@param mr number
---@param mg number
---@param mb number
---@param er number
---@param eg number
---@param eb number
---@return number r
---@return number g
---@return number b
local function ThreeStopGradient(t, sr, sg, sb, mr, mg, mb, er, eg, eb)
    if t <= 0 then
        return sr, sg, sb
    end
    if t >= 1 then
        return er, eg, eb
    end

    if t <= 0.5 then
        return LerpRGB(t * 2, sr, sg, sb, mr, mg, mb)
    end
    return LerpRGB((t - 0.5) * 2, mr, mg, mb, er, eg, eb)
end

---@param r number 0..1
---@param g number 0..1
---@param b number 0..1
---@return string hex RRGGBB
local function RGBToHex(r, g, b)
    local ri = Clamp(math.floor((r * 255) + 0.5), 0, 255)
    local gi = Clamp(math.floor((g * 255) + 0.5), 0, 255)
    local bi = Clamp(math.floor((b * 255) + 0.5), 0, 255)
    return string.format("%02x%02x%02x", ri, gi, bi)
end

---@param s string
---@return number
local function GetCharCount(s)
    return #s
end

---@param s string
---@param i number 1-based character index
---@return string
local function GetCharAt(s, i)
    return s:sub(i, i)
end

--- Returns `text` with each character wrapped in a 3-stop gradient color.
---
--- The gradient is computed dynamically so that the start, midpoint, and endpoint colors
--- stay visually consistent for different lengths.
---
--- Notes:
--- - Designed for 4..60 characters; longer strings are mapped onto a 60-step gradient.
--- - Colors can be provided as "RRGGBB" / "#RRGGBB" strings or {r,g,b} arrays (0..1 or 0..255).
---@param text string
---@param startColor any|nil Default: purple ("a855f7")
---@param midColor any|nil Default: blue ("4cc9f0")
---@param endColor any|nil Default: green ("22c55e")
---@return string
function SparkleUtil.GradientText(text, startColor, midColor, endColor)
    assert(type(text) == "string", "ECM.Util.GradientText: text must be a string")

    local charCount = GetCharCount(text)
    if charCount <= 0 then
        return ""
    end

    local sr, sg, sb = NormalizeRGB(startColor or "a855f7")
    local mr, mg, mb = NormalizeRGB(midColor or "4cc9f0")
    local er, eg, eb = NormalizeRGB(endColor or "22c55e")

    local effectiveLen = Clamp(charCount, 4, 60)

    local parts = {}
    for i = 1, charCount do
        local pos
        if charCount == 1 then
            pos = math.ceil(effectiveLen / 2)
        else
            -- Map the actual character index into [1..effectiveLen] so strings longer than
            -- effectiveLen still preserve the same start/mid/end colors.
            pos = 1 + math.floor(((i - 1) * (effectiveLen - 1) / (charCount - 1)) + 0.5)
        end

        local t = (effectiveLen == 1) and 0 or ((pos - 1) / (effectiveLen - 1))
        local r, g, b = ThreeStopGradient(t, sr, sg, sb, mr, mg, mb, er, eg, eb)
        parts[#parts + 1] = "|cff" .. RGBToHex(r, g, b) .. GetCharAt(text, i) .. "|r"
    end

    return table.concat(parts)
end
