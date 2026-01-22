local _, ns = ...

local Util = ns.Util

--- BarFrame mixin: Frame creation, appearance, and text overlay.
--- Provides shared frame structure for PowerBar and SegmentBar.
local BarFrame = {}
ns.Mixins = ns.Mixins or {}
ns.Mixins.BarFrame = BarFrame

--- Creates a base resource bar frame with Background and StatusBar.
--- Modules can add additional elements (text, ticks, fragments) after creation.
---@param frameName string Unique frame name
---@param parent Frame Parent frame (typically UIParent)
---@param defaultHeight number Default bar height
---@return Frame bar The created bar frame with .Background and .StatusBar
function BarFrame.Create(frameName, parent, defaultHeight)
    assert(type(frameName) == "string", "frameName must be a string")

    local profile = ns.Addon.db and ns.Addon.db.profile
    local bar = CreateFrame("Frame", frameName, parent or UIParent)
    bar:SetFrameStrata("MEDIUM")
    bar:SetHeight(Util.PixelSnap(defaultHeight or 20))

    -- Background texture
    bar.Background = bar:CreateTexture(nil, "BACKGROUND")
    bar.Background:SetAllPoints()

    -- StatusBar for value display
    bar.StatusBar = CreateFrame("StatusBar", nil, bar)
    bar.StatusBar:SetAllPoints()
    bar.StatusBar:SetFrameLevel(bar:GetFrameLevel() + 1)

    bar:Hide()
    return bar
end

--- Adds a text overlay to an existing bar frame.
--- Creates TextFrame container and TextValue FontString.
---@param bar Frame Bar frame to add text overlay to
---@param profile table|nil Profile for font settings
---@return FontString textValue The created FontString
function BarFrame.AddTextOverlay(bar, profile)
    assert(bar, "bar frame required")

    bar.TextFrame = CreateFrame("Frame", nil, bar)
    bar.TextFrame:SetAllPoints(bar)
    bar.TextFrame:SetFrameLevel(bar.StatusBar:GetFrameLevel() + 10)

    bar.TextValue = bar.TextFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.TextValue:SetPoint("CENTER", bar.TextFrame, "CENTER", 0, 0)
    bar.TextValue:SetJustifyH("CENTER")
    bar.TextValue:SetJustifyV("MIDDLE")
    bar.TextValue:SetText("0")

    if profile then
        Util.ApplyFont(bar.TextValue, profile)
    end

    return bar.TextValue
end

--- Adds a ticks frame layer for segment dividers.
--- Used by SegmentBar for visual segment separation.
---@param bar Frame Bar frame to add ticks frame to
---@return Frame ticksFrame The created ticks container frame
function BarFrame.AddTicksFrame(bar)
    assert(bar, "bar frame required")

    bar.TicksFrame = CreateFrame("Frame", nil, bar)
    bar.TicksFrame:SetAllPoints(bar)
    bar.TicksFrame:SetFrameLevel(bar:GetFrameLevel() + 2)
    bar.ticks = {}

    return bar.TicksFrame
end

--- Applies appearance settings (background color, statusbar texture) to a bar.
--- Wrapper around Util.ApplyBarAppearance for consistency.
---@param bar Frame Bar frame with .Background and .StatusBar
---@param cfg table|nil Module-specific config
---@param profile table|nil Full profile
---@return string|nil texture The applied texture path
function BarFrame.ApplyAppearance(bar, cfg, profile)
    return Util.ApplyBarAppearance(bar, cfg, profile)
end

--- Updates the StatusBar value and color.
---@param bar Frame Bar frame with .StatusBar
---@param minVal number Minimum value
---@param maxVal number Maximum value
---@param currentVal number Current value
---@param r number Red component (0-1)
---@param g number Green component (0-1)
---@param b number Blue component (0-1)
function BarFrame.SetValue(bar, minVal, maxVal, currentVal, r, g, b)
    assert(bar and bar.StatusBar, "bar with StatusBar required")

    bar.StatusBar:SetMinMaxValues(minVal, maxVal)
    bar.StatusBar:SetValue(currentVal)
    bar.StatusBar:SetStatusBarColor(r, g, b)
end

--- Sets the text value on a bar with text overlay.
---@param bar Frame Bar frame with .TextValue
---@param text string Text to display
function BarFrame.SetText(bar, text)
    if bar and bar.TextValue then
        bar.TextValue:SetText(text)
    end
end

--- Shows or hides the text overlay.
---@param bar Frame Bar frame with .TextFrame
---@param shown boolean Whether to show the text
function BarFrame.SetTextVisible(bar, shown)
    if bar and bar.TextFrame then
        bar.TextFrame:SetShown(shown)
    end
end
