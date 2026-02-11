-- Enhanced Cooldown Manager addon for World of Warcraft
-- Author: Solär
-- Licensed under the GNU General Public License v3.0
--
-- BuffBarColors: Manages per-spell color customization for buff bars.
-- Discovery cache ownership (cache/textureMap refresh) lives in Layout.

local _, ns = ...

local Util = ns.Util
local C = ns.Constants
local SecretedStore = ns.SecretedStore

---@class ECM_BarCacheEntry
---@field spellName string|nil  Spell name, or nil if secret/unavailable
---@field lastSeen number       GetTime() timestamp of when the bar was last scanned

--------------------------------------------------------------------------------
-- Module Table
--------------------------------------------------------------------------------

local BuffBarColors = {}
ns.BuffBarColors = BuffBarColors

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Ensures nested tables exist for buff bar color storage.
---@param cfg table
local function EnsureColorStorage(cfg)
    if not cfg.colors then
        cfg.colors = {
            perSpell = {},
            defaultColor = C.BUFFBARS_DEFAULT_COLOR,
        }
    end

    local colors = cfg.colors
    if type(colors.perSpell) ~= "table" then
        colors.perSpell = {}
    end
    if not colors.defaultColor then
        colors.defaultColor = C.BUFFBARS_DEFAULT_COLOR
    end
end

---@return table|nil
local function GetConfig()
    local cfg = SecretedStore and SecretedStore.GetPath and SecretedStore.GetPath({ "buffBars" }, true) or nil
    if type(cfg) ~= "table" then
        Util.DebugAssert(false, "BuffBarColors.GetConfig - missing or invalid buffBars config")
        return nil
    end

    if cfg then
        EnsureColorStorage(cfg)
    end

    return cfg
end

--- Returns current class ID and spec ID, or nil, nil if either is unavailable.
---@return number|nil classID, number|nil specID
local function GetCurrentClassSpec()
    local _, _, classID = UnitClass("player")
    local specID = GetSpecialization()
    if not classID or not specID then
        return nil, nil
    end

    return classID, specID
end

--- Returns cfg, classID, specID or nil if any is unavailable.
---@return table|nil cfg, number|nil classID, number|nil specID
local function GetColorContext()
    local cfg = GetConfig()
    if not cfg then
        return nil, nil, nil
    end

    local classID, specID = GetCurrentClassSpec()
    return cfg, classID, specID
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Returns the color lookup key for a bar: spell name if known, or textureFileID fallback.
---@param spellName string|nil
---@param textureFileID number|nil
---@return string|number|nil
function BuffBarColors.GetColorKey(spellName, textureFileID)
    local normalizedName = SecretedStore and SecretedStore.NormalizeString and SecretedStore.NormalizeString(
        spellName,
        { trim = true, emptyToNil = true }
    ) or nil

    if normalizedName then
        return normalizedName
    end

    local normalizedTexture = SecretedStore and SecretedStore.NormalizeNumber and SecretedStore.NormalizeNumber(textureFileID) or nil
    if normalizedTexture ~= nil then
        return normalizedTexture
    end

    return nil
end

--- Returns the per-spell color for the given key and current class/spec, or nil if not set.
---@param colorKey string|number|nil
---@return ECM_Color|nil
function BuffBarColors.LookupSpellColor(colorKey)
    local cfg = GetConfig()
    if not cfg or not cfg.colors or not cfg.colors.perSpell then
        Util.DebugAssert(false, "BuffBarColors.LookupSpellColor called before config is available")
        return C.BUFFBARS_DEFAULT_COLOR
    end

    if type(colorKey) == "string" and SecretedStore and SecretedStore.IsSecretValue and SecretedStore.IsSecretValue(colorKey) then
        -- Secret keys can occur transiently when Blizzard marks aura data as protected.
        -- Treat this as "no custom color" so callers fall back to defaults.
        return nil
    end

    local classID, specID = GetCurrentClassSpec()
    local colors = cfg.colors.perSpell
    if classID and specID and colors[classID] and colors[classID][specID] then
        local c = colors[classID][specID][colorKey]
        if c then
            return c
        end
    end

    return nil
end

--- Resolves a full color for a bar: per-spell color -> default color -> constant fallback.
--- Returns r, g, b for direct use in color pickers and SetStatusBarColor.
---@param colorKey string|number|nil
---@return number r, number g, number b
function BuffBarColors.GetSpellColor(colorKey)
    local cfg = GetConfig()
    local color = BuffBarColors.LookupSpellColor(colorKey)
        or (cfg and cfg.colors and cfg.colors.defaultColor)
        or C.BUFFBARS_DEFAULT_COLOR
    return color.r, color.g, color.b
end

--- Gets the default bar color as r, g, b components.
---@return number r, number g, number b
function BuffBarColors.GetDefaultColor()
    local cfg = GetConfig()
    local c = (cfg and cfg.colors and cfg.colors.defaultColor)
        or C.BUFFBARS_DEFAULT_COLOR
    return c.r, c.g, c.b
end

--- Sets the default bar color.
---@param r number
---@param g number
---@param b number
function BuffBarColors.SetDefaultColor(r, g, b)
    local cfg = GetConfig()
    Util.DebugAssert(cfg and cfg.colors, "BuffBarColors.SetDefaultColor called before config is available")
    if cfg and cfg.colors then
        cfg.colors.defaultColor = { r = r, g = g, b = b, a = 1 }
    end
end

--- Sets a custom color for the given key for current class/spec.
---@param colorKey string|number
---@param r number
---@param g number
---@param b number
---@return boolean changed True if the color was actually set
function BuffBarColors.SetSpellColor(colorKey, r, g, b)
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return false
    end

    if SecretedStore and SecretedStore.IsSecretValue and SecretedStore.IsSecretValue(colorKey) then
        return false
    end

    local colors = cfg.colors.perSpell
    colors[classID] = colors[classID] or {}
    colors[classID][specID] = colors[classID][specID] or {}
    colors[classID][specID][colorKey] = { r = r, g = g, b = b, a = 1 }

    Util.Log("BuffBarColors", "SetSpellColor", { colorKey = colorKey, r = r, g = g, b = b })
    return true
end

--- Removes the custom color for the given key for current class/spec.
---@param colorKey string|number
---@return boolean changed True if a color was actually removed
function BuffBarColors.ResetSpellColor(colorKey)
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return false
    end

    local colors = cfg.colors.perSpell
    if not (colors[classID] and colors[classID][specID]) then
        return false
    end

    local hadColor = colors[classID][specID][colorKey] ~= nil
    colors[classID][specID][colorKey] = nil

    Util.Log("BuffBarColors", "ResetSpellColor", { colorKey = colorKey })
    return hadColor
end

--- Checks if the given key has a custom color set for current class/spec.
---@param colorKey string|number
---@return boolean
function BuffBarColors.HasCustomSpellColor(colorKey)
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return false
    end

    local spells = cfg.colors.perSpell
    return spells[classID] and spells[classID][specID] and spells[classID][specID][colorKey] ~= nil
end

--- Gets configured per-key colors for current class/spec (for Options UI).
---@return table<string|number, ECM_Color> perSpell Indexed by spell name or texture file ID
function BuffBarColors.GetPerSpellColors()
    local cfg, classID, specID = GetColorContext()
    if not cfg or not classID or not specID then
        return {}
    end

    local perSpell = cfg.colors.perSpell
    if perSpell[classID] and perSpell[classID][specID] then
        return perSpell[classID][specID]
    end

    return {}
end

--- Resolves discovery spell names and migrates custom colors from secondary keys to spell names.
--- Called by Layout after it builds the next discovery maps and before those maps are written.
---@param classID number
---@param specID number
---@param oldCache table<number, ECM_BarCacheEntry>|nil
---@param oldTextureMap table<number, number>|nil
---@param nextCache table<number, ECM_BarCacheEntry>
---@param nextTextureMap table<number, number|nil>
---@return boolean changed True if a name was resolved or a color key was migrated
function BuffBarColors.ResolveDiscoveryColors(classID, specID, oldCache, oldTextureMap, nextCache, nextTextureMap)
    local cfg = GetConfig()
    if not cfg then
        return false
    end

    local perSpell = cfg.colors.perSpell
    local classSpells = perSpell and perSpell[classID]
    local specSpells = classSpells and classSpells[specID]

    local textureToSpellName = {}
    if type(oldCache) == "table" and type(oldTextureMap) == "table" then
        for index, entry in pairs(oldCache) do
            local textureID = oldTextureMap[index]
            local spellName = type(entry) == "table" and entry.spellName or nil
            local normalizedName = SecretedStore and SecretedStore.NormalizeString and SecretedStore.NormalizeString(
                spellName,
                { trim = true, emptyToNil = true }
            ) or nil
            local normalizedTexture = SecretedStore and SecretedStore.NormalizeNumber and SecretedStore.NormalizeNumber(textureID) or nil
            if normalizedName and normalizedTexture ~= nil then
                textureToSpellName[normalizedTexture] = normalizedName
            end
        end
    end

    local didChange = false

    for index, nextEntry in pairs(nextCache or {}) do
        local nextTexture = nextTextureMap and nextTextureMap[index] or nil
        local normalizedTexture = SecretedStore and SecretedStore.NormalizeNumber and SecretedStore.NormalizeNumber(nextTexture) or nil

        local spellName = type(nextEntry) == "table" and nextEntry.spellName or nil
        spellName = SecretedStore and SecretedStore.NormalizeString and SecretedStore.NormalizeString(
            spellName,
            { trim = true, emptyToNil = true }
        ) or nil

        if not spellName and normalizedTexture ~= nil then
            local resolved = textureToSpellName[normalizedTexture]
            if resolved then
                nextEntry.spellName = resolved
                spellName = resolved
                didChange = true
                Util.Log("BuffBarColors", "ResolveDiscoveryColors - resolved spell name", {
                    spellName = resolved,
                    textureFileID = normalizedTexture,
                })
            end
        end

        if specSpells and spellName and normalizedTexture ~= nil and specSpells[normalizedTexture] then
            if specSpells[spellName] == nil then
                specSpells[spellName] = specSpells[normalizedTexture]
            end
            specSpells[normalizedTexture] = nil
            didChange = true
            Util.Log("BuffBarColors", "ResolveDiscoveryColors - migrated color key", {
                spellName = spellName,
                textureFileID = normalizedTexture,
            })
        end
    end

    return didChange
end
