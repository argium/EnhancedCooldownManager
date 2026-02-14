-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

ColorUtil = ColorUtil or {}

local function clamp(v, minV, maxV)
    return math.max(minV, math.min(maxV, v))
end

---@param v number|string
---@return number
local function tonumber_or_assert(v)
    local n = tonumber(v)
    assert(n, "ECM.Util: expected number")
    return n
end

---@param color string|table
---@return number r 0..1
---@return number g 0..1
---@return number b 0..1
local function normalize_rgb(color)
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
        local r = color.r or color[1]
        local g = color.g or color[2]
        local b = color.b or color[3]

        r = tonumber_or_assert(r)
        g = tonumber_or_assert(g)
        b = tonumber_or_assert(b)

        -- Treat values > 1 as 0..255.
        if r > 1 or g > 1 or b > 1 then
            return clamp(r / 255, 0, 1), clamp(g / 255, 0, 1), clamp(b / 255, 0, 1)
        end
        return clamp(r, 0, 1), clamp(g, 0, 1), clamp(b, 0, 1)
    end

    error("ECM.Util: unsupported color type: " .. type(color))
end

---@param r number 0..1
---@param g number 0..1
---@param b number 0..1
---@return string hex
local function rgb_to_hex(r, g, b)
    local ri = clamp(math.floor((r * 255) + 0.5), 0, 255)
    local gi = clamp(math.floor((g * 255) + 0.5), 0, 255)
    local bi = clamp(math.floor((b * 255) + 0.5), 0, 255)
    return string.format("%02x%02x%02x", ri, gi, bi)
end


---@param color ECM_Color
---@return string hex
function ColorUtil.color_to_hex(color)
    return rgb_to_hex(color.r, color.g, color.b)
end

---@param t number 0..1
---@param r1 number
---@param g1 number
---@param b1 number
---@param r2 number
---@param g2 number
---@param b2 number
---@return number r, number g, number b
local function lerp_rgb(t, r1, g1, b1, r2, g2, b2)
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
---@return number r, number g, number b
local function three_stop_gradient(t, sr, sg, sb, mr, mg, mb, er, eg, eb)
    if t <= 0 then
        return sr, sg, sb
    end
    if t >= 1 then
        return er, eg, eb
    end

    if t <= 0.5 then
        return lerp_rgb(t * 2, sr, sg, sb, mr, mg, mb)
    end
    return lerp_rgb((t - 0.5) * 2, mr, mg, mb, er, eg, eb)
end

--- Returns `text` with each character wrapped in a 3-stop gradient color.
---
--- The gradient is computed dynamically so that the start, midpoint, and endpoint colors
--- stay visually consistent for different lengths.
---
--- Notes:
--- - Designed for 4..60 characters; longer strings are mapped onto a 60-step gradient.
--- - Colors can be provided as "RRGGBB" / "#RRGGBB" strings, ECM_Color tables, or {r,g,b} arrays (0..1 or 0..255).
---@param text string
---@param startColor string|table|nil
---@param midColor string|table|nil
---@param endColor string|table|nil
---@return string
ColorUtil.Sparkle = function(text, startColor, midColor, endColor)
    assert(type(text) == "string", "text must be a string")
    startColor = startColor or { r = 0.25, g = 0.82, b = 1.00, a = 1 }
    midColor = midColor or { r = 0.62, g = 0.45, b = 1.00, a = 1 }
    endColor = endColor or { r = 0.13, g = 0.77, b = 0.37, a = 1 }

    local charCount = #text
    if charCount == 0 then
        return ""
    end

    local sr, sg, sb = normalize_rgb(startColor)
    local mr, mg, mb = normalize_rgb(midColor )
    local er, eg, eb = normalize_rgb(endColor)

    local effectiveLen = clamp(charCount, 4, 60)
    local parts = {}

    for i = 1, charCount do
        local pos = (charCount == 1) and math.ceil(effectiveLen / 2)
            or (1 + math.floor(((i - 1) * (effectiveLen - 1) / (charCount - 1)) + 0.5))

        local t = (effectiveLen == 1) and 0 or ((pos - 1) / (effectiveLen - 1))
        local r, g, b = three_stop_gradient(t, sr, sg, sb, mr, mg, mb, er, eg, eb)
        parts[i] = "|cff" .. rgb_to_hex(r, g, b) .. text:sub(i, i) .. "|r"
    end

    return table.concat(parts)
end
