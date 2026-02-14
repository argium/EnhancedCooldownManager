-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Argium
-- Licensed under the GNU General Public License v3.0
--
-- SpellColors: Manages per-spell color customization for buff bars.
-- Backed by a PriorityKeyMap with four ordered tiers:
--   1. spell name   (highest priority — human-readable, preferred key)
--   2. spell ID      (numeric, survives secrets better than name)
--   3. cooldown ID   (numeric, frame-level identifier)
--   4. texture file ID (lowest priority — last-resort fallback)

local _, ns = ...
local FrameUtil = ECM.FrameUtil
local SpellColors = {}
ECM.SpellColors = SpellColors

--- Key tier definitions, ordered highest-priority first.
--- Must match the field names returned by get_scope().
local KEY_DEFS = { "byName", "bySpellID", "byCooldownID", "byTexture" }

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
---@return table|nil scope  Keyed by KEY_DEFS field names; each value is the class/spec sub-table.
local function get_scope(cfg)
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()

    if not classID or not specID then
        ECM_debug_assert(false, "SpellColors.get_scope - unable to determine player class/spec", {
            classID = classID,
            specID = specID,
        })
        return nil
    end

    local scope = {}
    for _, def in ipairs(KEY_DEFS) do
        cfg.colors[def][classID] = cfg.colors[def][classID] or {}
        cfg.colors[def][classID][specID] = cfg.colors[def][classID][specID] or {}
        scope[def] = cfg.colors[def][classID][specID]
    end
    return scope
end

--- Ensures nested tables exist for color storage.
---@param cfg table  buffBars config table
local function ensure_profile_is_setup(cfg)
    if not cfg.colors then
        cfg.colors = {
            byName = {},
            bySpellID = {},
            byCooldownID = {},
            byTexture = {},
            cache = {},
            defaultColor = ECM.Constants.BUFFBARS_DEFAULT_COLOR,
        }
    end
    for _, def in ipairs(KEY_DEFS) do
        if type(cfg.colors[def]) ~= "table" then
            cfg.colors[def] = {}
        end
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

local _map -- PriorityKeyMap instance (created on first use)

--- Repopulates lower-priority tier entries from byName for any colour
--- whose stored value carries embedded IDs (textureId, spellID,
--- cooldownID).  This repairs SavedVariables left incomplete by an
--- older Reconcile implementation that deleted fallback entries.
local function repair_from_primary()
    local cfg = config()
    if not cfg then return end

    local scope = get_scope(cfg)
    if not scope then return end
    local byName = scope.byName
    if not byName then return end

    for _, entry in pairs(byName) do
        if type(entry) == "table" and type(entry.value) == "table" then
            local v = entry.value
            if v.textureId and scope.byTexture and not scope.byTexture[v.textureId] then
                scope.byTexture[v.textureId] = entry
            end
            if v.spellID and scope.bySpellID and not scope.bySpellID[v.spellID] then
                scope.bySpellID[v.spellID] = entry
            end
            if v.cooldownID and scope.byCooldownID and not scope.byCooldownID[v.cooldownID] then
                scope.byCooldownID[v.cooldownID] = entry
            end
        end
    end
end

--- Returns the PriorityKeyMap instance, creating it on first call.
---@return PriorityKeyMap|nil
local function get_map()
    if _map then
        return _map
    end

    local cfg = config()
    if not cfg then
        return nil
    end

    repair_from_primary()

    _map = ECM.PriorityKeyMap.New(
        KEY_DEFS,
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

--- Gets the custom color for a spell by its identifying keys.
--- Keys are tried in priority order: spellName → spellID → cooldownID → textureFileID.
---@param spellName string|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureFileID number|nil
---@return ECM_Color|nil
function SpellColors.GetColor(spellName, spellID, cooldownID, textureFileID)
    local map = get_map()
    if not map then
        return nil
    end
    return map:Get({ spellName, spellID, cooldownID, textureFileID })
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

    local spellName = validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText())
    local spellID = validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID)
    local cooldownID = validateKey(frame.cooldownID)
    local textureFileID = validateKey(FrameUtil.GetIconTextureFileID(frame))
    return SpellColors.GetColor(spellName, spellID, cooldownID, textureFileID)
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
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureId number|nil
---@param color ECM_Color
function SpellColors.SetColor(spellName, spellID, cooldownID, textureId, color)
    ECM_debug_assert(not spellName or type(spellName) == "string", "Expected spellName to be a string or nil")
    ECM_debug_assert(not spellID or type(spellID) == "number", "Expected spellID to be a number or nil")
    ECM_debug_assert(not cooldownID or type(cooldownID) == "number", "Expected cooldownID to be a number or nil")
    ECM_debug_assert(not textureId or type(textureId) == "number", "Expected textureId to be a number or nil")

    local map = get_map()
    if not map then
        return
    end
    -- Embed secondary IDs in the color value so repair_from_primary can
    -- repopulate lower-priority tiers from byName entries.
    if textureId then
        color.textureId = textureId
    end
    if spellID then
        color.spellID = spellID
    end
    if cooldownID then
        color.cooldownID = cooldownID
    end
    map:Set({ spellName, spellID, cooldownID, textureId }, color)
end

--- Returns the default bar color.
---@return ECM_Color
function SpellColors.GetDefaultColor()
    local cfg = config()
    if not cfg then
        return ECM.Constants.BUFFBARS_DEFAULT_COLOR
    end
    return cfg.colors.defaultColor
end

--- Sets the default bar color.
---@param color ECM_Color
function SpellColors.SetDefaultColor(color)
    local cfg = config()
    if not cfg then
        return
    end
    cfg.colors.defaultColor = { r = color.r, g = color.g, b = color.b, a = 1 }
end

--- Removes the custom color for a spell from all key tiers.
---@param spellName string|nil
---@param spellID number|nil
---@param cooldownID number|nil
---@param textureId number|nil
---@return boolean nameCleared
---@return boolean spellIDCleared
---@return boolean cooldownIDCleared
---@return boolean textureCleared
function SpellColors.ResetColor(spellName, spellID, cooldownID, textureId)
    local map = get_map()
    if not map then
        return false, false, false, false
    end
    return map:Remove({ spellName, spellID, cooldownID, textureId })
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
    local spellName = validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText())
    local spellID = validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID)
    local cooldownID = validateKey(frame.cooldownID)
    local textureFileID = validateKey(FrameUtil.GetIconTextureFileID(frame))
    map:Reconcile({ spellName, spellID, cooldownID, textureFileID })
end

--- Reconciles color entries for a list of bar frames.
---@param frames ECM_BuffBarMixin[]
---@return number changed  Count of reconciled entries.
function SpellColors.ReconcileAllBars(frames)
    local map = get_map()
    if not map then
        return 0
    end
    local keys_list = {}
    for _, frame in ipairs(frames) do
        if frame and frame.__ecmHooked then
            local spellName = validateKey(frame.Bar and frame.Bar.Name and frame.Bar.Name.GetText and frame.Bar.Name:GetText())
            local spellID = validateKey(frame.cooldownInfo and frame.cooldownInfo.spellID)
            local cooldownID = validateKey(frame.cooldownID)
            local textureFileID = validateKey(FrameUtil.GetIconTextureFileID(frame))
            keys_list[#keys_list + 1] = { spellName, spellID, cooldownID, textureFileID }
        end
    end
    return map:ReconcileAll(keys_list)
end
