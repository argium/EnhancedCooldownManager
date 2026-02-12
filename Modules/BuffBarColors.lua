-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0
--
-- BuffBarColors: Manages per-spell color customization for buff bars.
-- Discovery cache ownership (cache/textureMap refresh) lives in Layout.

local _, ns = ...

local ECM = ns.Addon
local C = ns.Constants
local BuffBarColors = {}
ns.BuffBarColors = BuffBarColors

-- TODO: when setting a spellName, if the texture id was set more recently, then migrate it?

local function get_table_for_spec(cfg)
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()

    local colors = cfg.colors.perSpell
    colors[classID] = colors[classID] or {}
    colors[classID][specID] = colors[classID][specID] or {}
    return colors[classID][specID]
end

local function compute_key(spellName, textureFileId)
    ECM_debug_assert(not spellName or type(spellName) == "string", "Expected spellName to be a string or nil")
    ECM_debug_assert(not textureFileId or type(textureFileId) == "number", "Expected textureFileId to be a number or nil")

    if spellName and type(spellName) == "string" and not issecretvalue(spellName) then
        return spellName
    end

    if textureFileId and type(textureFileId) == "number" and not issecretvalue(textureFileId) then
        return textureFileId
    end

    return nil
end


--- Ensures nested tables exist for buff bar color storage.
---@param cfg ECM_BuffBarsConfig
local function ensure_profile_is_setup(cfg)
    if not cfg.colors then
        cfg.colors = {
            perSpell = {},
            perBar = {},
            cache = {},
            defaultColor = C.BUFFBARS_DEFAULT_COLOR,
        }
    end

    if type(cfg.colors.perSpell) ~= "table" then
        cfg.colors.perSpell = {}
    end
    if type(cfg.colors.perBar) ~= "table" then
        cfg.colors.perBar = {}
    end
    if type(cfg.colors.cache) ~= "table" then
        cfg.colors.cache = {}
    end
    if type(cfg.colors.defaultColor) ~= "table" then
        cfg.colors.defaultColor = C.BUFFBARS_DEFAULT_COLOR
    end
end

--- Returns config table and current class/spec IDs, or nils if not available.
--- @return ECM_BuffBarsConfig|nil config The buff bars config table, or nil if not available
local function config()
    local addon = ns.Addon
    local cfg = addon and addon.db and addon.db.profile and addon.db.profile.buffBars or nil
    if type(cfg) ~= "table" then
        ECM_debug_assert(false, "BuffBarColors.GetConfig - missing or invalid buffBars config")
        return nil
    end

    ensure_profile_is_setup(cfg)

    return cfg
end

local function get(cfg, key)
    local spec_colors = get_table_for_spec(cfg)
    return spec_colors[key] or nil
end

local function set(cfg, key, value)
    local spec_colors = get_table_for_spec(cfg)
    spec_colors[key] = value
end

local function remove(cfg, key)
    local spec_colors = get_table_for_spec(cfg)
    local exists = spec_colors[key] ~= nil
    spec_colors[key] = nil
    return exists
end

---------------------------------------------------------------------------
-- Public interface
---------------------------------------------------------------------------

function BuffBarColors.GetColor(spellName, textureFileID)
    local cfg = config()
    local key = compute_key(spellName, textureFileID)
    if not key then
        return nil
    end
    return get(cfg, key)
end

function BuffBarColors.GetColorForBar(frame)
    ECM_debug_assert(frame, "Expected bar frame")

    if not (frame and frame.__ecmHooked) then
        ECM_log(C.SYS.Styling, "BuffBarColors", "GetColorForBar - invalid bar frame", {
            frame = frame,
            nameExists = frame and type(frame.Name) == "table" and type(frame.Name.GetText) == "function",
            iconExists = frame and type(frame.Icon) == "table" and type(frame.Icon.GetRegions) == "function",
        })
        return nil
    end
    -- ECM_debug_assert(frame.Name and frame.Name.GetText, "Expected frame.Name with GetText method", frame)
    -- ECM_debug_assert(bar.Icon and bar.Icon.GetRegions, "Expected bar.Icon frame with GetRegions method. " .. (bar:GetName() or "nil") .. " " .. (bar.Name and bar.Name:GetText() or "nil"), bar)
    local spellName = frame and frame.Name and frame.Name.GetText and frame.Name:GetText() or nil
    -- local iconFrame = frame and frame.Icon
    -- local iconTexture = iconFrame and iconFrame.GetRegions and select(C.BUFFBARS_ICON_TEXTURE_REGION_INDEX, iconFrame:GetRegions()) or nil
    -- local textureFileID = iconTexture and iconTexture.GetIconTextureFileID and iconTexture:GetIconTextureFileID() or nil
    local textureFileID = FrameHelpers.GetIconTextureFileID(frame) or nil
    ECM_debug_assert(not textureFileID or not issecretvalue(textureFileID), "Texture file ID is a secret value, cannot use as color key")
    return BuffBarColors.GetColor(spellName, textureFileID)
end

function BuffBarColors.GetAllColors()
    local cfg = config()
    local spec_colors = get_table_for_spec(cfg)
    return spec_colors or {}
end

function BuffBarColors.SetColor(spellName, textureId, color)
    ECM_debug_assert(spellName and type(spellName) == "string", "Expected spellName to be a string")
    ECM_debug_assert(textureId and type(textureId) == "number", "Expected textureId to be a number")

    local cfg = config()
    if spellName and type(spellName) == "string" and not issecretvalue(spellName) then
        set(cfg, spellName, color)
    end

    if textureId and type(textureId) == "number" and not issecretvalue(textureId) then
        set(cfg, textureId, color)
    end
end

function BuffBarColors.ResetColor(spellName, textureId)
    local cfg = config()

    -- remove both keys
    local nameCleared = remove(cfg, spellName)
    local textureCleared = remove(cfg, textureId)
    return nameCleared, textureCleared
end












--- Gets configured per-key colors for current class/spec (for Options UI).
---@return table<string|number, ECM_Color> perSpell Indexed by spell name or texture file ID
-- function BuffBarColors.GetPerSpellColors()
--     local cfg, classID, specID = GetColorContext()
--     if not cfg or not classID or not specID then
--         return {}
--     end

--     local perSpell = cfg.colors.perSpell
--     if perSpell[classID] and perSpell[classID][specID] then
--         return perSpell[classID][specID]
--     end

--     return {}
-- end

--- Resolves discovery spell names and migrates custom colors from secondary keys to spell names.
--- Called by Layout after it builds the next discovery maps and before those maps are written.
---@param classID number
---@param specID number
---@param oldCache table<number, ECM_BarCacheEntry>|nil
---@param oldTextureMap table<number, number>|nil
---@param nextCache table<number, ECM_BarCacheEntry>
---@param nextTextureMap table<number, number|nil>
---@return boolean changed True if a name was resolved or a color key was migrated
-- function BuffBarColors.ResolveDiscoveryColors(classID, specID, oldCache, oldTextureMap, nextCache, nextTextureMap)
--     local cfg = GetConfig()
--     if not cfg then
--         return false
--     end

--     local perSpell = cfg.colors.perSpell
--     local classSpells = perSpell and perSpell[classID]
--     local specSpells = classSpells and classSpells[specID]

--     local textureToSpellName = {}
--     if type(oldCache) == "table" and type(oldTextureMap) == "table" then
--         for index, entry in pairs(oldCache) do
--             local textureID = oldTextureMap[index]
--             local spellName = type(entry) == "table" and entry.spellName or nil
--             local normalizedName = Util.NormalizeString(
--                 spellName,
--                 { trim = true, emptyToNil = true }
--             )
--             local normalizedTexture = Util.NormalizeNumber(textureID)
--             if normalizedName and normalizedTexture ~= nil then
--                 textureToSpellName[normalizedTexture] = normalizedName
--             end
--         end
--     end

--     local didChange = false

--     for index, nextEntry in pairs(nextCache or {}) do
--         local nextTexture = nextTextureMap and nextTextureMap[index] or nil
--         local normalizedTexture = Util.NormalizeNumber(nextTexture)

--         local spellName = type(nextEntry) == "table" and nextEntry.spellName or nil
--         spellName = Util.NormalizeString(
--             spellName,
--             { trim = true, emptyToNil = true }
--         )

--         if not spellName and normalizedTexture ~= nil then
--             local resolved = textureToSpellName[normalizedTexture]
--             if resolved then
--                 nextEntry.spellName = resolved
--                 spellName = resolved
--                 didChange = true
--                 ECM_log("BuffBarColors", "ResolveDiscoveryColors - resolved spell name", {
--                     spellName = resolved,
--                     textureFileID = normalizedTexture,
--                 })
--             end
--         end

--         if specSpells and spellName and normalizedTexture ~= nil and specSpells[normalizedTexture] then
--             if specSpells[spellName] == nil then
--                 specSpells[spellName] = specSpells[normalizedTexture]
--             end
--             specSpells[normalizedTexture] = nil
--             didChange = true
--             ECM_log("BuffBarColors", "ResolveDiscoveryColors - migrated color key", {
--                 spellName = spellName,
--                 textureFileID = normalizedTexture,
--             })
--         end
--     end

--     return didChange
-- end

--- Ensures buff-bar discovery storage exists in profile.
---@return table|nil colors
-- local function EnsureBuffBarStorage()
--     local profile = ECM.db and ECM.db.profile
--     if not profile then
--         return nil
--     end

--     if not profile.buffBars then
--         profile.buffBars = {}
--     end

--     local buffBars = profile.buffBars
--     if not buffBars.colors then
--         buffBars.colors = {}
--     end

--     local colors = buffBars.colors
--     if type(colors) ~= "table" then
--         return nil
--     end

--     if type(colors.cache) ~= "table" then
--         colors.cache = {}
--     end
--     if type(colors.textureMap) ~= "table" then
--         colors.textureMap = {}
--     end

--     return colors
-- end

-- ---@return table|nil colors, number|nil classID, number|nil specID
-- local function GetBuffBarDiscoveryContext()
--     local classID, specID = GetCurrentClassSpec()
--     if not classID or not specID then
--         return nil, nil, nil
--     end

--     local colors = EnsureBuffBarStorage()
--     if not colors then
--         return nil, nil, nil
--     end

--     colors.cache[classID] = colors.cache[classID] or {}
--     colors.textureMap[classID] = colors.textureMap[classID] or {}

--     return colors, classID, specID
-- end

local function RegisterProfileCallbacks(db)
    -- if _callbacksRegistered or not db or type(db.RegisterCallback) ~= "function" then
    --     SecretedStore.OnProfileChanged()
    --     return
    -- end

    -- db.RegisterCallback(SecretedStore, "OnProfileChanged", "OnProfileChanged")
    -- db.RegisterCallback(SecretedStore, "OnProfileCopied", "OnProfileChanged")
    -- db.RegisterCallback(SecretedStore, "OnProfileReset", "OnProfileChanged")
    -- _callbacksRegistered = true

    -- SecretedStore.OnProfileChanged()
end
