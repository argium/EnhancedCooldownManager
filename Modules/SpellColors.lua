-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0
--
-- SpellColors: Manages per-spell color customization for buff bars.
-- Backed by a FallbackKeyMap (primary = spell name, fallback = texture file ID).

local _, ns = ...
local SpellColors = {}
ECM.SpellColors = SpellColors

---------------------------------------------------------------------------
-- Key validation
---------------------------------------------------------------------------

--- Returns k if it is a valid, non-secret string or number; nil otherwise.
local function validateKey(k)
    if k == nil then
        return nil
    end
    if type(k) == "string" and not issecretvalue(k) then
        return k
    end
    if type(k) == "number" and not issecretvalue(k) then
        return k
    end
    return nil
end

---------------------------------------------------------------------------
-- Profile helpers
---------------------------------------------------------------------------

--- Ensures the color storage tables exist for the current class/spec.
---@param cfg table  buffBars config table
---@return table scope  { byPrimary = byName[classID][specID], byFallback = byTexture[classID][specID] }
local function get_scope(cfg)
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()

    cfg.colors.byName[classID] = cfg.colors.byName[classID] or {}
    cfg.colors.byName[classID][specID] = cfg.colors.byName[classID][specID] or {}

    cfg.colors.byTexture[classID] = cfg.colors.byTexture[classID] or {}
    cfg.colors.byTexture[classID][specID] = cfg.colors.byTexture[classID][specID] or {}

    return {
        byPrimary = cfg.colors.byName[classID][specID],
        byFallback = cfg.colors.byTexture[classID][specID],
    }
end

--- Ensures nested tables exist for color storage.
---@param cfg table  buffBars config table
local function ensure_profile_is_setup(cfg)
    if not cfg.colors then
        cfg.colors = {
            byName = {},
            byTexture = {},
            cache = {},
            defaultColor = ECM.Constants.BUFFBARS_DEFAULT_COLOR,
        }
    end
    if type(cfg.colors.byName) ~= "table" then
        cfg.colors.byName = {}
    end
    if type(cfg.colors.byTexture) ~= "table" then
        cfg.colors.byTexture = {}
    end
    if type(cfg.colors.cache) ~= "table" then
        cfg.colors.cache = {}
    end
    if type(cfg.colors.defaultColor) ~= "table" then
        cfg.colors.defaultColor = ECM.Constants.BUFFBARS_DEFAULT_COLOR
    end
end

--- Returns the buffBars config table, or nil if unavailable.
---@return table|nil cfg
local function config()
    local mod = ns.Addon
    local cfg = mod and mod.db and mod.db.profile and mod.db.profile.buffBars or nil
    if type(cfg) ~= "table" then
        ECM_debug_assert(false, "SpellColors.config - missing or invalid buffBars config")
        return nil
    end
    ensure_profile_is_setup(cfg)
    return cfg
end

---------------------------------------------------------------------------
-- Lazy singleton
---------------------------------------------------------------------------

local _map -- FallbackKeyMap instance (created on first use)

--- Returns the FallbackKeyMap instance, creating it on first call.
---@return FallbackKeyMap|nil
local function get_map()
    if _map then
        return _map
    end

    local cfg = config()
    if not cfg then
        return nil
    end

    _map = ECM.FallbackKeyMap.New(
        function()
            local cfg = config()
            if not cfg then return nil end
            return get_scope(cfg)
        end,
        validateKey
    )
    return _map
end

---------------------------------------------------------------------------
-- Public interface
---------------------------------------------------------------------------

--- Gets the custom color for a spell by name and/or texture ID.
---@param spellName string|nil
---@param textureFileID number|nil
---@return ECM_Color|nil
function SpellColors.GetColor(spellName, textureFileID)
    local map = get_map()
    if not map then
        return nil
    end
    return map:Get(spellName, textureFileID)
end

--- Gets the custom color for a bar frame.
---@param frame ECM_BuffBarMixin
---@return ECM_Color|nil
function SpellColors.GetColorForBar(frame)
    ECM_debug_assert(frame, "Expected bar frame")

    if not (frame and frame.__ecmHooked) then
        ECM_log(ECM.Constants.SYS.Styling, "SpellColors", "GetColorForBar - invalid bar frame", {
            frame = frame,
            nameExists = frame and type(frame.Name) == "table" and type(frame.Name.GetText) == "function",
            iconExists = frame and type(frame.Icon) == "table" and type(frame.Icon.GetRegions) == "function",
        })
        return nil
    end

    local spellName = frame.Name and frame.Name.GetText and frame.Name:GetText() or nil
    local textureFileID = FrameUtil.GetIconTextureFileID(frame) or nil
    ECM_debug_assert(not textureFileID or not issecretvalue(textureFileID),
        "Texture file ID is a secret value, cannot use as color key")
    return SpellColors.GetColor(spellName, textureFileID)
end

--- Returns a merged table of all custom colors for the current class/spec.
---@return table<string|number, ECM_Color>
function SpellColors.GetAllColors()
    local map = get_map()
    if not map then
        return {}
    end
    return map:GetAll()
end

--- Sets a custom color for a spell.
---@param spellName string|nil
---@param textureId number|nil
---@param color ECM_Color
function SpellColors.SetColor(spellName, textureId, color)
    ECM_debug_assert(not spellName or type(spellName) == "string", "Expected spellName to be a string or nil")
    ECM_debug_assert(not textureId or type(textureId) == "number", "Expected textureId to be a number or nil")

    local map = get_map()
    if not map then
        return
    end
    map:Set(spellName, textureId, color)
end

--- Removes the custom color for a spell from both key maps.
---@param spellName string|nil
---@param textureId number|nil
---@return boolean nameCleared
---@return boolean textureCleared
function SpellColors.ResetColor(spellName, textureId)
    local map = get_map()
    if not map then
        return false, false
    end
    return map:Remove(spellName, textureId)
end

--- Reconciles the color entry for a single bar frame.
---@param frame ECM_BuffBarMixin
function SpellColors.ReconcileBar(frame)
    if not (frame and frame.__ecmHooked) then
        return
    end
    local map = get_map()
    if not map then
        return
    end
    local spellName = frame.Name and frame.Name.GetText and frame.Name:GetText() or nil
    local textureFileID = FrameUtil.GetIconTextureFileID(frame) or nil
    map:Reconcile(spellName, textureFileID)
end

--- Reconciles color entries for a list of bar frames.
---@param frames ECM_BuffBarMixin[]
---@return number changed  Count of reconciled entries.
function SpellColors.ReconcileAllBars(frames)
    local map = get_map()
    if not map then
        return 0
    end
    local pairs_list = {}
    for _, frame in ipairs(frames) do
        if frame and frame.__ecmHooked then
            local spellName = frame.Name and frame.Name.GetText and frame.Name:GetText() or nil
            local textureFileID = FrameUtil.GetIconTextureFileID(frame) or nil
            pairs_list[#pairs_list + 1] = { spellName, textureFileID }
        end
    end
    return map:ReconcileAll(pairs_list)
end
