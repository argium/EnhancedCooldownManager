-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0

-- Bridges ModuleMixin frames with LibEQOLEditMode for drag-to-position
-- in Blizzard's Edit Mode. Registers free-anchor frames so users can
-- drag them instead of adjusting manual offset sliders.

local _, ns = ...

local C = ECM.Constants
local LibEQOL = LibStub("LibEQOLEditMode-1.0")
local EditModeBridge = {}
ECM.EditModeBridge = EditModeBridge

-- frame → module reverse lookup
local _frameToModule = {}

--- Position callback invoked by LibEQOL after drag/arrow-key moves.
--- Writes the new anchor point and offsets back into the module's config.
local function OnPositionChanged(frame, _layoutName, point, x, y)
    local module = _frameToModule[frame]
    if not module then return end

    local cfg = module:GetModuleConfig()
    if not cfg or cfg.anchorMode ~= C.ANCHORMODE_FREE then return end

    cfg.freeAnchorPoint = point
    cfg.offsetX = x
    cfg.offsetY = y
    module:ThrottledUpdateLayout("EditModeDrag")
end

--- Returns true when the module is in free anchor mode (allows dragging).
local function MakeDragPredicate(module)
    return function()
        local cfg = module:GetModuleConfig()
        return cfg and cfg.anchorMode == C.ANCHORMODE_FREE
    end
end

--- Builds the settings sheet (width slider) for a registered frame.
local function BuildSettings(module)
    local isFree = MakeDragPredicate(module)
    return {
        {
            kind = LibEQOL.SettingType.Slider,
            name = "Width",
            minValue = 100,
            maxValue = 600,
            valueStep = 1,
            default = C.DEFAULT_BAR_WIDTH,
            isShown = isFree,
            get = function()
                local cfg = module:GetModuleConfig()
                return cfg and cfg.width or C.DEFAULT_BAR_WIDTH
            end,
            set = function(_layoutName, value)
                local cfg = module:GetModuleConfig()
                if not cfg then return end
                cfg.width = value
                module:ThrottledUpdateLayout("EditModeWidth")
            end,
        },
    }
end

--- Registers a module's InnerFrame with LibEQOL Edit Mode.
--- Safe to call multiple times; subsequent calls are no-ops.
--- Skips Blizzard Edit Mode system frames to avoid taint propagation.
function EditModeBridge.Register(module)
    local frame = module and module.InnerFrame
    if not frame or _frameToModule[frame] then return end

    -- Blizzard Edit Mode system frames (e.g. BuffBarCooldownViewer) already
    -- have their own .Selection/.system fields. Writing addon-tainted values
    -- onto them propagates taint into Blizzard secure code on Edit Mode enter.
    local frameName = frame.GetName and frame:GetName()
    if not frameName or frameName:sub(1, 3) ~= "ECM" then return end

    local cfg = module:GetModuleConfig()
    local defaultX = cfg and cfg.offsetX or 0
    local defaultY = cfg and cfg.offsetY or C.DEFAULT_FREE_ANCHOR_OFFSET_Y
    local defaultPoint = cfg and cfg.freeAnchorPoint or "CENTER"

    frame.editModeName = C.ADDON_ABRV .. " " .. (module.Name or "Bar")

    _frameToModule[frame] = module
    LibEQOL:AddFrame(frame, OnPositionChanged, {
        point = defaultPoint,
        x = defaultX,
        y = defaultY,
    })
    LibEQOL:SetFrameDragEnabled(frame, MakeDragPredicate(module))
    LibEQOL:AddFrameSettings(frame, BuildSettings(module))
end

--- Updates drag enablement after an anchor mode change.
--- The frame stays registered (no unregister API) but drag is
--- disabled when in chain mode.
function EditModeBridge.UpdateDragState(module)
    local frame = module and module.InnerFrame
    if not frame or not _frameToModule[frame] then return end
    LibEQOL:SetFrameDragEnabled(frame, MakeDragPredicate(module))
end
